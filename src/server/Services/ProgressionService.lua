--[[
	ProgressionService: XP, levels, ninja tier unlocks and kill rewards.
	All reward math happens here on the server; clients only receive results.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Tiers = require(Shared.Config.Tiers)
local Katanas = require(Shared.Config.Katanas)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)

local ProgressionService = {}

local services
local MAX_LEVELS_PER_GRANT = 500

function ProgressionService:CheckTier(player: Player)
	local data = services.DataService:Get(player)
	if not data then
		return
	end
	local target = Tiers.ForLevel(data.Level).Index
	if target <= data.Tier then
		return
	end
	local previousTier = data.Tier
	for index = previousTier + 1, target do
		local tier = Tiers.Get(index)
		data.Katanas[tier.Katana] = true
	end
	data.Tier = target
	data.BestTier = math.max(data.BestTier, target)

	-- Auto-equip the new tier blade if it beats what they're holding.
	local newTier = Tiers.Get(target)
	local newKatana = Katanas.Get(newTier.Katana)
	local current = Katanas.Get(data.EquippedKatana)
	if newKatana and (not current or newKatana.Mult >= current.Mult) then
		data.EquippedKatana = newKatana.Id
		services.DataService:Changed(player, "EquippedKatana")
	end
	services.DataService:Changed(player, "Tier")
	services.DataService:Changed(player, "BestTier")
	services.DataService:Changed(player, "Katanas")

	Net.Event("TierUnlocked"):FireClient(player, target, previousTier)
	if target >= 4 then
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player then
				Net.Event("Notify"):FireClient(other, {
					Text = player.DisplayName .. " became a " .. newTier.Name .. "!",
					Color = newTier.Color,
				})
			end
		end
	end
end

function ProgressionService:AddXP(player: Player, amount: number)
	local data = services.DataService:Get(player)
	if not data or amount <= 0 then
		return
	end
	data.XP += math.floor(amount)
	local gained = 0
	while data.XP >= Balance.XPToNext(data.Level) and gained < MAX_LEVELS_PER_GRANT do
		data.XP -= Balance.XPToNext(data.Level)
		data.Level += 1
		gained += 1
	end
	services.DataService:Changed(player, "XP")
	if gained > 0 then
		services.DataService:Changed(player, "Level")
		if data.Level > data.Lifetime.HighestLevel then
			data.Lifetime.HighestLevel = data.Level
			services.DataService:Changed(player, "Lifetime")
		end
		-- new max health keeps the same health fraction: no full heal on level up
		-- (levels come fast; HealthService regenerates out of combat instead)
		services.StatService:Refresh(player)
		Net.Event("LevelUp"):FireClient(player, data.Level, gained)
		self:CheckTier(player)
	end
end

function ProgressionService:AddCoins(player: Player, amount: number)
	local data = services.DataService:Get(player)
	if not data or amount <= 0 then
		return
	end
	amount = math.floor(amount)
	data.Coins += amount
	data.Lifetime.CoinsEarned += amount
	services.DataService:Changed(player, "Coins")
	services.DataService:Changed(player, "Lifetime")
end

function ProgressionService:AddShards(player: Player, amount: number)
	local data = services.DataService:Get(player)
	if not data or amount <= 0 then
		return
	end
	data.Shards += math.floor(amount)
	services.DataService:Changed(player, "Shards")
end

-- Called by EnemyService for each rewarded player. Returns what they got (for UI).
function ProgressionService:GrantKill(player: Player, enemy)
	local data = services.DataService:Get(player)
	local stats = services.StatService:Get(player)
	if not data or not stats then
		return nil
	end
	local double = math.random() < stats.ExtraChance
	local mult = if double then 2 else 1
	local eventCoins, eventXP = 1, 1
	if services.EventService then
		eventCoins, eventXP = services.EventService:Multipliers(player)
	end
	local xp = math.floor(enemy.XP * stats.XPMult * Balance.XPPenalty(data.Level, enemy.Level) * mult * eventXP)
	local coins = math.floor(enemy.Coins * stats.CoinMult * mult * eventCoins)
	local reward = { XP = xp, Coins = coins, Double = double }

	data.Lifetime.Kills += 1
	if enemy.IsBoss then
		data.Lifetime.BossKills += 1
		local shards = enemy.Def.Shards or 0
		if shards > 0 then
			self:AddShards(player, shards)
			reward.Shards = shards
		end
		local dropId = enemy.Def.Drop
		local drop = dropId and Katanas.Get(dropId)
		if drop and not data.Katanas[drop.Id] and math.random() < (drop.DropChance or 0) then
			data.Katanas[drop.Id] = true
			services.DataService:Changed(player, "Katanas")
			reward.Drop = drop.Id
			for _, other in ipairs(Players:GetPlayers()) do
				Net.Event("Notify"):FireClient(other, {
					Text = player.DisplayName .. " looted the " .. drop.Name .. "!",
					Color = Color3.fromRGB(255, 200, 80), Big = other == player,
				})
			end
		end
	end
	self:AddCoins(player, coins)
	self:AddXP(player, xp)
	return reward
end

local function setupLeaderstats(player: Player, data)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local level = Instance.new("StringValue")
	level.Name = "Level"
	level.Value = Format.Abbrev(data.Level)
	level.Parent = folder
	local rebirths = Instance.new("StringValue")
	rebirths.Name = "Rebirths"
	rebirths.Value = Format.Abbrev(data.Rebirths)
	rebirths.Parent = folder
	folder.Parent = player
end

function ProgressionService:Init(registry)
	services = registry
end

function ProgressionService:Start()
	services.DataService:OnLoaded(function(player, data)
		setupLeaderstats(player, data)
		-- safety: make sure tier matches level after migrations / balance changes
		self:CheckTier(player)
	end)
	services.DataService:AddFlushHook(function(player, keys)
		if keys.Level or keys.Rebirths then
			local data = services.DataService:Get(player)
			local stats = player:FindFirstChild("leaderstats")
			if data and stats then
				(stats:FindFirstChild("Level") :: StringValue).Value = Format.Abbrev(data.Level);
				(stats:FindFirstChild("Rebirths") :: StringValue).Value = Format.Abbrev(data.Rebirths)
			end
		end
	end)
end

return ProgressionService
