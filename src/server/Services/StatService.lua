--[[
	StatService: caches each player's derived stats (Shared/Stats) and keeps the
	character's WalkSpeed / MaxHealth in sync. Stats are recomputed whenever a
	stat-affecting data key changes and sent to the client as "__Stats".
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Stats = require(ReplicatedStorage.Shared.Stats)

local StatService = {}
StatService.Cache = {} :: { [Player]: any }

local STAT_KEYS = {
	Level = true, Tier = true, EquippedKatana = true, EquippedPets = true, Pets = true,
	Upgrades = true, Boosts = true, Rebirths = true, Utility = true,
	Hats = true, EquippedHat = true, -- hat stats (LootService)
	SkillBuff = true, -- not a save key: SetModifier marks it to push buffed stats
	Mastery = true, Suit = true, -- the worn suit's mastery bonus (Config/Mastery)
	Charms = true, -- the charm grid (CharmService)
	ActiveHire = true, Hires = true, -- the fighting hire's charms share stats with you (Config/Hires)
}

local services

function StatService:Get(player: Player)
	local cached = self.Cache[player]
	if cached then
		return cached
	end
	return self:Refresh(player)
end

function StatService:ApplyToCharacter(player: Player, stats)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	humanoid.WalkSpeed = stats.WalkSpeed
	if humanoid.MaxHealth ~= stats.MaxHealth then
		local ratio = if humanoid.MaxHealth > 0 then humanoid.Health / humanoid.MaxHealth else 1
		humanoid.MaxHealth = stats.MaxHealth
		humanoid.Health = math.max(1, stats.MaxHealth * ratio)
	end
end

-- A temporary stat multiplier from `source` (e.g. a skill buff) for `duration`
-- seconds: { Damage = x, AttackInterval = x, WalkSpeed = x }. Recasting refreshes it.
StatService.Modifiers = {} :: { [Player]: { [string]: { [string]: number } } }
local modifierRuns: { [Player]: { [string]: number } } = {}
function StatService:SetModifier(player: Player, source: string, mods: { [string]: number }, duration: number)
	self.Modifiers[player] = self.Modifiers[player] or {}
	modifierRuns[player] = modifierRuns[player] or {}
	self.Modifiers[player][source] = mods
	local run = (modifierRuns[player][source] or 0) + 1
	modifierRuns[player][source] = run
	self:Refresh(player)
	services.DataService:Changed(player, "SkillBuff")
	task.delay(duration, function()
		local list = self.Modifiers[player]
		if list and modifierRuns[player] and modifierRuns[player][source] == run then
			list[source] = nil
			self:Refresh(player)
			services.DataService:Changed(player, "SkillBuff")
		end
	end)
end

function StatService:Refresh(player: Player)
	local data = services.DataService:Get(player)
	if not data then
		return nil
	end
	local stats = Stats.Compute(data)
	-- temporary multipliers from skills (Bushido Spirit, Wind Step)
	for _, mods in pairs(self.Modifiers[player] or {}) do
		stats.Damage = math.floor(stats.Damage * (mods.Damage or 1))
		stats.AttackInterval *= mods.AttackInterval or 1
		stats.WalkSpeed *= mods.WalkSpeed or 1
		stats.CritChance += mods.CritChance or 0 -- Focus tokens (TokenService)
		stats.Avatar = stats.Avatar or mods.Avatar -- a mastery Avatar is awake (SkillService:CastUltimate)
	end
	self.Cache[player] = stats
	self:ApplyToCharacter(player, stats)
	return stats
end

function StatService:Init(registry)
	services = registry
end

function StatService:Start()
	services.DataService:AddFlushHook(function(player, keys, payload)
		for key in pairs(keys) do
			if STAT_KEYS[key] then
				payload.__Stats = self:Refresh(player)
				return
			end
		end
	end)
	services.DataService:OnLoaded(function(player)
		self:Refresh(player)
		services.DataService:Changed(player, "Level") -- pushes __Stats to the client
	end)
	Players.PlayerRemoving:Connect(function(player)
		self.Modifiers[player] = nil
		modifierRuns[player] = nil
		self.Cache[player] = nil
	end)
end

return StatService
