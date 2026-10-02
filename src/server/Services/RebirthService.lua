--[[
	RebirthService: validates and performs rebirths, and Spirit Shard upgrades.

	Rebirth resets: Level, XP, Coins, Tier, zone unlocks.
	Rebirth keeps:  Shards, Upgrades, Pets, Katanas (re-locked by tier), Cosmetics,
	                Boosts, Codes, Settings, lifetime stats.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Katanas = require(Shared.Config.Katanas)
local Upgrades = require(Shared.Config.Upgrades)
local Net = require(Shared.Net)

local RebirthService = {}

local services
local cooldown: { [Player]: number } = {}

function RebirthService:Preview(player: Player)
	local data = services.DataService:Get(player)
	local stats = services.StatService:Get(player)
	if not data or not stats then
		return nil
	end
	return {
		Required = Balance.RebirthLevelRequirement(data.Rebirths),
		Shards = Balance.RebirthShards(data.Level, data.Rebirths, stats.ShardMult),
		CurrentBonus = Balance.RebirthBonus(data.Rebirths),
		NextBonus = Balance.RebirthBonus(data.Rebirths + 1),
	}
end

-- Best katana the player owns that they can equip at tier 1.
local function bestStarterKatana(data): string
	local bestId, bestMult = "brown_katana", 0
	for id in pairs(data.Katanas) do
		local def = Katanas.Get(id)
		if def and def.RequiredTier <= 1 and def.Mult > bestMult then
			bestId, bestMult = id, def.Mult
		end
	end
	return bestId
end

function RebirthService:Rebirth(player: Player): (boolean, string?)
	local data = services.DataService:Get(player)
	local stats = services.StatService:Get(player)
	if not data or not stats then
		return false, "Data not loaded"
	end
	if cooldown[player] and os.clock() - cooldown[player] < 3 then
		return false, "Slow down!"
	end
	local required = Balance.RebirthLevelRequirement(data.Rebirths)
	if data.Level < required then
		return false, "Reach Level " .. required .. " to rebirth"
	end
	cooldown[player] = os.clock()

	local shards = Balance.RebirthShards(data.Level, data.Rebirths, stats.ShardMult)
	data.Rebirths += 1
	data.Shards += shards
	data.Level = 1
	data.XP = 0
	data.Coins = 0
	data.Tier = 1
	data.Zones = { village = true }
	data.LastZone = "village"
	data.EquippedKatana = bestStarterKatana(data)

	for _, key in ipairs({ "Rebirths", "Shards", "Level", "XP", "Coins", "Tier", "Zones", "LastZone", "EquippedKatana" }) do
		services.DataService:Changed(player, key)
	end
	services.StatService:Refresh(player)
	services.CharacterService:SpawnAtZone(player, "village")
	services.DataService:SaveNow(player)

	if services.EventService then
		services.EventService:Shoutout("🌀 " .. player.DisplayName .. " reached Rebirth " .. data.Rebirths .. "!", Color3.fromRGB(110, 242, 224))
	end
	Net.Event("Rebirthed"):FireClient(player, {
		Rebirths = data.Rebirths,
		Shards = shards,
		Bonus = Balance.RebirthBonus(data.Rebirths),
	})
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			Net.Event("Notify"):FireClient(other, {
				Text = player.DisplayName .. " reached Rebirth " .. data.Rebirths .. "!",
				Color = Color3.fromRGB(120, 255, 230),
			})
		end
	end
	return true
end

function RebirthService:BuyUpgrade(player: Player, upgradeId: string): (boolean, string?)
	local data = services.DataService:Get(player)
	local def = Upgrades.ById[upgradeId]
	if not data or not def then
		return false, "Unknown upgrade"
	end
	if data.Rebirths < 1 then
		return false, "Rebirth once to unlock upgrades"
	end
	local level = data.Upgrades[upgradeId] or 0
	if level >= def.Max then
		return false, "Maxed out"
	end
	local cost = Upgrades.Cost(def, level)
	if not services.DataService:Spend(player, "Shards", cost) then
		return false, "Need " .. cost .. " Spirit Shards"
	end
	data.Upgrades[upgradeId] = level + 1
	services.DataService:Changed(player, "Upgrades")
	return true
end

function RebirthService:Init(registry)
	services = registry
end

function RebirthService:Start()
	Players.PlayerRemoving:Connect(function(player)
		cooldown[player] = nil
	end)
end

return RebirthService
