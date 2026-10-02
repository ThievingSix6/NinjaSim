--[[
	InventoryService: equipping katanas and cosmetics, favourites, settings and
	code redemption. Ownership is always checked against saved data.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Katanas = require(Shared.Config.Katanas)
local Shop = require(Shared.Config.Shop)
local Codes = require(Shared.Config.Codes)
local DataTemplate = require(Shared.DataTemplate)
local Net = require(Shared.Net)

local InventoryService = {}

local services

function InventoryService:EquipKatana(player: Player, katanaId: string): (boolean, string?)
	local data = services.DataService:Get(player)
	local def = Katanas.Get(katanaId)
	if not data or not def or not data.Katanas[def.Id] then
		return false, "You don't own that katana"
	end
	if data.Tier < def.RequiredTier then
		return false, "Requires a higher Ninja tier"
	end
	data.EquippedKatana = def.Id
	services.DataService:Changed(player, "EquippedKatana")
	return true
end

function InventoryService:EquipCosmetic(player: Player, kind: string, cosmeticId: string): (boolean, string?)
	local data = services.DataService:Get(player)
	if not data or type(kind) ~= "string" or data.Equipped[kind] == nil then
		return false, "Unknown slot"
	end
	if cosmeticId == "" then
		data.Equipped[kind] = ""
	else
		local def = Shop.CosmeticsById[cosmeticId]
		if not def or def.Kind ~= kind or not data.Cosmetics[def.Id] then
			return false, "You don't own that"
		end
		data.Equipped[kind] = def.Id
	end
	services.DataService:Changed(player, "Equipped")
	return true
end

function InventoryService:ToggleFavorite(player: Player, key: string): (boolean, string?)
	local data = services.DataService:Get(player)
	if not data or type(key) ~= "string" or #key > 64 then
		return false, "Invalid item"
	end
	local kind, id = string.match(key, "^(%a+):(.+)$")
	local owned = (kind == "katana" and data.Katanas[id]) or (kind == "cosmetic" and data.Cosmetics[id])
	if not owned then
		return false, "You don't own that"
	end
	data.Favorites[key] = if data.Favorites[key] then nil else true
	services.DataService:Changed(player, "Favorites")
	return true
end

function InventoryService:SetSetting(player: Player, key: string, value: any): (boolean, string?)
	local data = services.DataService:Get(player)
	local default = DataTemplate.Settings[key]
	if not data or default == nil or type(value) ~= type(default) then
		return false, "Invalid setting"
	end
	if type(value) == "number" then
		value = math.clamp(value, 0, 1)
	end
	if key == "AutoSwing" and value == true and (data.Utility.auto_swing or 0) < 1 then
		return false, "Buy Auto Swing in the shop first"
	end
	data.Settings[key] = value
	services.DataService:Changed(player, "Settings")
	return true
end

function InventoryService:RedeemCode(player: Player, code: string): (boolean, string?)
	local data = services.DataService:Get(player)
	if not data or type(code) ~= "string" or #code > 32 then
		return false, "Invalid code"
	end
	code = string.upper((string.gsub(code, "%s", "")))
	local reward = Codes[code]
	if not reward or (reward.Expires and os.time() > reward.Expires) then
		return false, "That code doesn't exist or has expired"
	end
	if data.Codes[code] then
		return false, "Already redeemed"
	end
	data.Codes[code] = true
	services.DataService:Changed(player, "Codes")
	local parts = {}
	if reward.Coins then
		services.ProgressionService:AddCoins(player, reward.Coins)
		table.insert(parts, reward.Coins .. " Coins")
	end
	if reward.Shards then
		services.ProgressionService:AddShards(player, reward.Shards)
		table.insert(parts, reward.Shards .. " Spirit Shards")
	end
	if reward.Boost then
		services.ShopService:AddBoost(player, reward.Boost.Id, reward.Boost.Seconds)
		local def = Shop.BoostsById[reward.Boost.Id]
		table.insert(parts, (if def then def.Name else reward.Boost.Id) .. " boost")
	end
	if reward.Pet then
		services.PetService:Grant(player, reward.Pet)
		table.insert(parts, "a pet")
	end
	Net.Event("Reward"):FireClient(player, { Title = "Code redeemed!", Text = table.concat(parts, " + ") })
	return true, "Redeemed: " .. table.concat(parts, " + ")
end

function InventoryService:Init(registry)
	services = registry
end

function InventoryService:Start() end

return InventoryService
