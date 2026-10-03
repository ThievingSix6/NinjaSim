--[[
	ShopService: every purchase is priced and validated here. Handles weapon
	(katana) purchases, timed boosts (ticking only while online), cosmetics and
	utility upgrades. Rebirth-milestone cosmetics are granted automatically.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Katanas = require(Shared.Config.Katanas)
local Secrets = require(Shared.Config.Secrets)
local Shop = require(Shared.Config.Shop)
local Net = require(Shared.Net)

local ShopService = {}

local services

function ShopService:KatanaPrice(def): number
	return Balance.CoinsForKills(def.CostLevel, def.CostKills)
end

function ShopService:BoostPrice(player: Player, def): number
	local data = services.DataService:Get(player)
	local level = if data then data.Level else 1
	return Balance.CoinsForKills(level, def.CostKills)
end

function ShopService:BuyKatana(player: Player, katanaId: string): (boolean, string?)
	local data = services.DataService:Get(player)
	local def = Katanas.Get(katanaId)
	if not data or not def or def.Source ~= "Shop" then
		return false, "Not for sale"
	end
	if data.Katanas[def.Id] then
		return false, "Already owned"
	end
	if data.Tier < def.RequiredTier then
		return false, "Requires a higher Ninja tier"
	end
	local price = self:KatanaPrice(def)
	if not services.DataService:Spend(player, "Coins", price) then
		return false, "Not enough Coins"
	end
	data.Katanas[def.Id] = true
	services.DataService:Changed(player, "Katanas")
	local current = Katanas.Get(data.EquippedKatana)
	if not current or def.Mult > current.Mult then
		data.EquippedKatana = def.Id
		services.DataService:Changed(player, "EquippedKatana")
	end
	return true
end

-- The Seal Shop (Config/Secrets): secret suits, weapons and pets for Cursed Seals.
function ShopService:BuySecret(player: Player, id: string?): (boolean, string?)
	local data = services.DataService:Get(player)
	local item = id and Secrets.ById[id]
	if not data or not item then
		return false, "Unknown item"
	end
	if item.Kind == "Suit" and data.Secrets[item.Id] or item.Kind == "Weapon" and data.Katanas[item.Id] then
		return false, "Already owned"
	end
	if (data.Seals or 0) < item.Price then
		return false, "Not enough Cursed Seals"
	end
	data.Seals -= item.Price
	services.DataService:Changed(player, "Seals")
	if item.Kind == "Suit" then
		data.Secrets[item.Id] = true
		services.DataService:Changed(player, "Secrets")
	elseif item.Kind == "Weapon" then
		data.Katanas[item.Id] = true
		services.DataService:Changed(player, "Katanas")
	else
		services.PetService:Grant(player, item.Id)
	end
	return true, "Unlocked!"
end

function ShopService:BuyBoost(player: Player, boostId: string): (boolean, string?)
	local data = services.DataService:Get(player)
	local def = Shop.BoostsById[boostId]
	if not data or not def then
		return false, "Unknown boost"
	end
	local remaining = data.Boosts[def.Id] or 0
	if remaining + def.Duration > Shop.MaxBoostSeconds then
		return false, "Boost is already stacked to the max"
	end
	local price = self:BoostPrice(player, def)
	if not services.DataService:Spend(player, "Coins", price) then
		return false, "Not enough Coins"
	end
	self:AddBoost(player, def.Id, def.Duration)
	return true
end

function ShopService:AddBoost(player: Player, boostId: string, seconds: number)
	local data = services.DataService:Get(player)
	if not data or not Shop.BoostsById[boostId] then
		return
	end
	data.Boosts[boostId] = math.min(Shop.MaxBoostSeconds, (data.Boosts[boostId] or 0) + seconds)
	services.DataService:Changed(player, "Boosts")
end

function ShopService:BuyCosmetic(player: Player, cosmeticId: string): (boolean, string?)
	local data = services.DataService:Get(player)
	local def = Shop.CosmeticsById[cosmeticId]
	if not data or not def then
		return false, "Unknown item"
	end
	if data.Cosmetics[def.Id] then
		return false, "Already owned"
	end
	if def.Currency == "Rebirth" then
		if data.Rebirths < def.Cost then
			return false, "Unlocks at Rebirth " .. def.Cost
		end
	elseif not services.DataService:Spend(player, def.Currency, def.Cost) then
		return false, "Not enough " .. (if def.Currency == "Shards" then "Spirit Shards" else "Coins")
	end
	data.Cosmetics[def.Id] = true
	services.DataService:Changed(player, "Cosmetics")
	-- equip right away: buying something means you want to see it
	data.Equipped[def.Kind] = def.Id
	services.DataService:Changed(player, "Equipped")
	return true
end

function ShopService:BuyUtility(player: Player, utilityId: string): (boolean, string?)
	local data = services.DataService:Get(player)
	local def = Shop.UtilityById[utilityId]
	if not data or not def then
		return false, "Unknown item"
	end
	local owned = data.Utility[def.Id] or 0
	if owned >= def.MaxOwned then
		return false, "Maxed out"
	end
	if def.RequiredRebirths and data.Rebirths < def.RequiredRebirths then
		return false, "Requires Rebirth " .. def.RequiredRebirths
	end
	local price = Shop.UtilityCost(def, owned)
	if not services.DataService:Spend(player, def.Currency, price) then
		return false, "Not enough " .. (if def.Currency == "Shards" then "Spirit Shards" else "Coins")
	end
	data.Utility[def.Id] = owned + 1
	services.DataService:Changed(player, "Utility")
	return true
end

local function grantRebirthCosmetics(player: Player)
	local data = services.DataService:Get(player)
	if not data then
		return
	end
	local changed = false
	for _, def in ipairs(Shop.Cosmetics) do
		if def.Currency == "Rebirth" and data.Rebirths >= def.Cost and not data.Cosmetics[def.Id] then
			data.Cosmetics[def.Id] = true
			changed = true
			Net.Event("Notify"):FireClient(player, { Text = "Unlocked " .. def.Name .. "! Equip it in your Inventory.", Color = def.Color, Big = true })
		end
	end
	if changed then
		services.DataService:Changed(player, "Cosmetics")
	end
end

function ShopService:Init(registry)
	services = registry
end

function ShopService:Start()
	services.DataService:OnLoaded(grantRebirthCosmetics)
	services.DataService:AddFlushHook(function(player, keys)
		if keys.Rebirths then
			task.defer(grantRebirthCosmetics, player)
		end
	end)

	-- Boost timers + play time (online time only)
	task.spawn(function()
		local syncCounter = 0
		while true do
			task.wait(1)
			syncCounter += 1
			for _, player in ipairs(Players:GetPlayers()) do
				local data = services.DataService:Get(player)
				if data then
					data.Lifetime.PlayTime += 1
					local expired = false
					for id, seconds in pairs(data.Boosts) do
						local left = seconds - 1
						if left <= 0 then
							data.Boosts[id] = nil
							expired = true
							local def = Shop.BoostsById[id]
							Net.Event("Notify"):FireClient(player, { Text = (if def then def.Name else id) .. " boost ended", Color = Color3.fromRGB(200, 200, 210) })
						else
							data.Boosts[id] = left
						end
					end
					if expired or (syncCounter % 15 == 0 and next(data.Boosts) ~= nil) then
						services.DataService:Changed(player, "Boosts")
					end
				end
			end
		end
	end)
end

return ShopService
