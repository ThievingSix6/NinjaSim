--[[
	Core progression math. Enemy health, XP and coin rewards are all derived from
	what a fresh (no rebirth, no pets) player of the same level deals, so every new
	zone/enemy stays in balance automatically: a same-level enemy takes ~4 hits.

	Rebirths, pets, upgrades and shop katanas are what push the player ahead of that
	baseline, which is exactly the feeling of "getting stronger".
]]

local Tiers = require(script.Parent.Tiers)
local Katanas = require(script.Parent.Katanas)

local Balance = {}

-- Combat
Balance.BaseAttackInterval = 0.42 -- seconds between swings
Balance.MinAttackInterval = 0.18
Balance.AttackRange = 13 -- studs from root to enemy root (plus enemy radius)
Balance.AttackArcDot = -0.1 -- enemies must be roughly in front (cos of ~95 degrees)
Balance.MaxTargetsPerSwing = 12 -- swings cleave through crowds
Balance.BaseCritChance = 0.05
Balance.CritMultiplier = 2
Balance.ComboWindow = 1.4 -- seconds before combo resets
Balance.ComboBonusPerHit = 0.01 -- +1% damage per combo hit
Balance.MaxComboBonus = 0.3

-- Movement
-- Horde battles (one-man-army): every camp holds Count x EnemyDensity enemies, spread
-- over Radius x CampSpread. Zones only fill while players are in them. Regular enemies
-- have HordeHealth x the normal health, and at most MaxAttackers swing at one player at
-- a time; the rest crowd round waiting for their turn.
Balance.EnemyDensity = 10
Balance.CampSpread = 2.2
Balance.HordeHealth = 0.6
Balance.MaxAttackers = 5
Balance.XPMultiplier = 0.5 -- XP per kill (halved with the 10x density)

Balance.BaseWalkSpeed = 26
Balance.SprintMultiplier = 1.4 -- hold Shift (always on for touch screens)
Balance.ExtraJumps = 1 -- jumps allowed in the air (1 = double jump)

-- Rewards
Balance.RewardShareThreshold = 0.1 -- deal 10% of an enemy's HP to share its rewards
Balance.BossShareThreshold = 0.03

function Balance.XPToNext(level: number): number
	return math.floor(12 * level ^ 1.55 + 18)
end

function Balance.BaseDamage(level: number): number
	return 5 + 2 * (level - 1)
end

function Balance.PlayerMaxHealth(level: number, healthMult: number): number
	return math.floor((100 + 6 * (level - 1)) * healthMult)
end

-- Damage per hit of a fresh player at `level` wielding their tier katana.
function Balance.ExpectedDamage(level: number): number
	local tier = Tiers.ForLevel(level)
	local katana = Katanas.ById[tier.Katana]
	return Balance.BaseDamage(level) * tier.Power * katana.Mult
end

function Balance.ExpectedHealth(level: number): number
	return Balance.PlayerMaxHealth(level, Tiers.ForLevel(level).HealthMult)
end

-- How many same-level kills it takes to level up. Grows slowly so early levels fly by.
function Balance.KillsPerLevel(level: number): number
	return 2.2 + 1.1 * level ^ 0.5
end

-- Player health regen (HealthService): none while fighting; after RegenDelay seconds
-- without taking damage, HealthRegen x MaxHealth per second. Level-ups don't heal.
Balance.HealthRegen = 0.03
Balance.RegenDelay = 5

-- Enemy size variety (EnemyService:Spawn): { chance, min scale, max scale }, rolled per
-- spawn (not bosses). Health scales with size^1.5 and damage with size.
Balance.EnemySizes = {
	{ 0.15, 0.72, 0.88 }, -- runts
	{ 0.65, 0.92, 1.1 }, -- normal
	{ 0.15, 1.15, 1.35 }, -- big
	{ 0.05, 1.45, 1.75 }, -- brutes
}

-- every enemy and boss (justin, 2026-10-01: "double enemy hp across the board")
Balance.EnemyHealthMultiplier = 2

function Balance.EnemyHealth(level: number, mod: number?): number
	return math.max(10, math.floor(Balance.ExpectedDamage(level) * 4 * Balance.EnemyHealthMultiplier * (mod or 1)))
end

function Balance.EnemyXP(level: number, mod: number?): number
	return math.max(1, math.floor(Balance.XPToNext(level) / Balance.KillsPerLevel(level) * (mod or 1) * Balance.XPMultiplier))
end

function Balance.EnemyCoins(level: number, mod: number?): number
	return math.max(1, math.floor((2 + level ^ 1.45) * 1.01 ^ level * (mod or 1)))
end

function Balance.EnemyDamage(level: number, mod: number?): number
	return math.max(1, math.floor(Balance.ExpectedHealth(level) * 0.055 * (mod or 1)))
end

-- Killing enemies far below your level gives less XP, nudging players forward.
function Balance.XPPenalty(playerLevel: number, enemyLevel: number): number
	local diff = playerLevel - enemyLevel
	if diff <= 12 then
		return 1
	end
	return math.clamp(1 - (diff - 12) * 0.025, 0.2, 1)
end

-- Price something as "N kills worth of coins at level L".
function Balance.CoinsForKills(level: number, kills: number): number
	local raw = Balance.EnemyCoins(level) * kills
	-- round to 2 significant figures so prices look intentional
	local magnitude = 10 ^ math.max(0, math.floor(math.log10(math.max(raw, 1))) - 1)
	return math.floor(raw / magnitude + 0.5) * magnitude
end

-- ===== Rebirth =====
function Balance.RebirthLevelRequirement(rebirths: number): number
	return math.min(50 + 20 * rebirths, 450)
end

-- Total permanent bonus after `rebirths` rebirths: +10%, +20%, +35%, +50%, +70%, +90%...
function Balance.RebirthBonus(rebirths: number): number
	local bonus = 0
	for k = 1, rebirths do
		bonus += 0.05 * (1 + math.floor((k + 1) / 2))
	end
	return bonus
end

function Balance.RebirthShards(level: number, rebirths: number, shardMult: number?): number
	local req = Balance.RebirthLevelRequirement(rebirths)
	local base = 5 + math.floor(math.max(0, level - req) / 5) + rebirths
	return math.floor(base * (shardMult or 1))
end

return Balance
