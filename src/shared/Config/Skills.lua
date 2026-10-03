--[[
	Ninja and samurai skills: flashy crowd clearers on hotkeys (1-4 by default).
	The server (SkillService) owns every number here: who owns what, cooldowns,
	shapes and damage. Damage is a multiple of the player's own hit damage
	(Shared/Stats), so skills grow with level, tier, katana, pets and rebirths.

	Per skill:
	  Theme      "Ninja" | "Samurai" (flavour + the menu tag)
	  Kind       "Damage" | "Control" | "Mobility" | "Buff" | "Ultimate"
	  Icon/Paint atlas icon + Theme paint (or a {top, bottom} pair) for its tiles
	  Cooldown   seconds at level 1 (each level takes CooldownPerLevel off)
	  Damage     hit multiplier per target (x the player's damage) at level 1
	  Radius / Range / Arc / Width / Length   the hit shape (studs; Arc = cos of half angle)
	  MaxTargets enemies a single hit can reach
	  Unlock     how it is obtained:
	               { Kind = "Level", Level = n }     free at that level
	               { Kind = "Tier", Tier = n }       free at that ninja tier
	               { Kind = "Coins", Level = n, Kills = k }  bought; price = Balance.CoinsForKills(n, k)
	               { Kind = "Shards", Cost = n, Rebirths = r } bought with Spirit Shards
	Skills level up to Skills.MaxLevel with Coins (or Shards for Shard skills):
	+25% damage and a little less cooldown per level.
	Charms (Config/Charms) add levels on top, past MaxLevel up to HardCap; beyond
	MaxLevel each level still adds +25% damage and takes 3% off the cooldown.
]]

local Balance = require(script.Parent.Balance)
local Tiers = require(script.Parent.Tiers)

local Skills = {}

Skills.Slots = 4
Skills.MaxLevel = 5 -- highest level you can buy
Skills.HardCap = 20 -- highest level charms can push a skill to
Skills.OverCooldown = 0.97 -- cooldown multiplier per level past MaxLevel
Skills.DamagePerLevel = 0.25
Skills.CooldownPerLevel = 0.05
Skills.GlobalCooldown = 0.3 -- seconds between any two casts
Skills.UpgradeKills = 30 -- coin upgrades cost this many kills' worth per level
Skills.CutStep = 0.1 -- seconds between Thousand Cuts slashes (server timing, mirrored by the client)

local rgb = Color3.fromRGB

Skills.List = {
	{
		Id = "shuriken_storm", Name = "Shuriken Storm", Theme = "Ninja", Kind = "Damage",
		Icon = "Shuriken", Paint = "Blue", Color = rgb(140, 210, 255),
		Desc = "Fling a fan of spinning stars that shred every enemy in front of you.",
		Cooldown = 6, Damage = 2, Range = 44, Arc = 0.55, MaxTargets = 30, Knockback = 0.6, Stun = 0.3,
		Unlock = { Kind = "Level", Level = 1 },
	},
	{
		Id = "whirlwind_slash", Name = "Whirlwind Slash", Theme = "Samurai", Kind = "Damage",
		Icon = "Rebirth", Paint = "Sky", Color = rgb(200, 240, 255),
		Desc = "Spin with your blade out. Two sweeping cuts hit everything around you.",
		Cooldown = 8, Damage = 1.4, Radius = 17, MaxTargets = 40, Knockback = 1.4, Stun = 0.4,
		Unlock = { Kind = "Level", Level = 6 },
	},
	{
		Id = "iaido_dash", Name = "Iaido Dash", Theme = "Samurai", Kind = "Mobility",
		Icon = "Katana", Paint = "Gold", Color = rgb(255, 236, 160),
		Desc = "Quick-draw dash. Blink forward and sheathe: everyone on your path falls a moment later.",
		Cooldown = 7, Damage = 3, Length = 30, Width = 11, MaxTargets = 30, Knockback = 1, Stun = 0.6,
		Unlock = { Kind = "Tier", Tier = 2 },
	},
	{
		Id = "wind_step", Name = "Wind Step", Theme = "Ninja", Kind = "Mobility",
		Icon = "Boot", Paint = "Green", Color = rgb(170, 255, 170),
		Desc = "Dash like the wind, untouchable for a moment, then run faster for a few seconds.",
		Cooldown = 5, Damage = 0.8, Length = 24, Width = 8, MaxTargets = 20, Knockback = 0.8, Stun = 0.2,
		Duration = 4, Speed = 1.35,
		Unlock = { Kind = "Coins", Level = 12, Kills = 40 },
	},
	{
		Id = "smoke_bomb", Name = "Smoke Bomb", Theme = "Ninja", Kind = "Control",
		Icon = "Potion", Paint = "Grey", Color = rgb(150, 150, 170),
		Desc = "Vanish in a cloud of smoke. Nearby enemies are blinded and stunned while you blink away.",
		Cooldown = 14, Damage = 0.8, Radius = 20, MaxTargets = 40, Knockback = 0.4, Stun = 2.5, Length = 18,
		Unlock = { Kind = "Coins", Level = 15, Kills = 60 },
	},
	{
		Id = "kunai_rain", Name = "Kunai Rain", Theme = "Ninja", Kind = "Damage",
		Icon = "Sparkle", Paint = "Pink", Color = rgb(255, 170, 220),
		Desc = "Leap and hurl a storm of kunai. Three waves rain down on the nearest crowd.",
		Cooldown = 11, Damage = 1.2, Radius = 15, Range = 36, MaxTargets = 30, Knockback = 0.3, Stun = 0.3,
		Unlock = { Kind = "Tier", Tier = 3 },
	},
	{
		Id = "dragon_flame", Name = "Dragon Flame", Theme = "Ninja", Kind = "Damage",
		Icon = "Flame", Paint = "Orange", Color = rgb(255, 150, 60),
		Desc = "Breathe a roaring cone of dragon fire that keeps burning whatever it touches.",
		Cooldown = 10, Damage = 1.6, Range = 34, Arc = 0.7, MaxTargets = 30, Knockback = 0.8, Stun = 0.3,
		Burn = 0.4, BurnTicks = 4,
		Unlock = { Kind = "Coins", Level = 25, Kills = 80 },
	},
	{
		Id = "oni_quake", Name = "Oni Quake", Theme = "Samurai", Kind = "Control",
		Icon = "Oni", Paint = { rgb(232, 176, 104), rgb(150, 86, 40) }, Color = rgb(230, 170, 100),
		Desc = "Leap and slam the ground like an oni. The shockwave launches and stuns a huge circle.",
		Cooldown = 12, Damage = 2.6, Radius = 26, MaxTargets = 50, Knockback = 2.4, Stun = 1.6,
		Unlock = { Kind = "Tier", Tier = 4 },
	},
	{
		Id = "lightning_blade", Name = "Lightning Blade", Theme = "Samurai", Kind = "Damage",
		Icon = "Bolt", Paint = "Cyan", Color = rgb(150, 240, 255),
		Desc = "Call lightning down your blade. It leaps from enemy to enemy, stunning each one.",
		Cooldown = 9, Damage = 2.6, Range = 32, Arc = 0.2, Chain = 12, ChainRange = 16, MaxTargets = 16, Knockback = 0.5, Stun = 1,
		Unlock = { Kind = "Coins", Level = 50, Kills = 100 },
	},
	{
		Id = "shadow_clone", Name = "Shadow Clone", Theme = "Ninja", Kind = "Damage",
		Icon = "Friends", Paint = "Purple", Color = rgb(190, 120, 255),
		Desc = "Split into three shadow clones that blink onto nearby enemies and fight beside you.",
		Cooldown = 24, Damage = 0.9, Radius = 22, Clones = 3, Duration = 8, Interval = 0.7, Knockback = 0.5, Stun = 0.2,
		MaxTargets = 3,
		Unlock = { Kind = "Coins", Level = 75, Kills = 120 },
	},
	{
		Id = "bushido_spirit", Name = "Bushido Spirit", Theme = "Samurai", Kind = "Buff",
		Icon = "Heart", Paint = "Red", Color = rgb(255, 90, 90),
		Desc = "A warrior's roar: heal, then hit harder and swing faster for a while.",
		Cooldown = 30, Damage = 0.5, Radius = 12, MaxTargets = 30, Knockback = 1.2, Stun = 0.3,
		Duration = 8, DamageBuff = 1.5, AttackSpeedBuff = 1.35, Heal = 0.3,
		Unlock = { Kind = "Tier", Tier = 5 },
	},
	{
		Id = "thousand_cuts", Name = "Thousand Cuts", Theme = "Ninja", Kind = "Ultimate",
		Icon = "Crown", Paint = { rgb(255, 130, 210), rgb(120, 40, 220) }, Color = rgb(255, 150, 255),
		Desc = "Ultimate. Become a blur and cut through every enemy around you, then finish with a blast.",
		Cooldown = 45, Damage = 2.2, Radius = 32, MaxTargets = 18, Knockback = 2, Stun = 1, FinalDamage = 3,
		Unlock = { Kind = "Shards", Cost = 75, Rebirths = 1 },
	},
}

-- Elemental tier skills (Config/ElementSkills): two per ninja tier, free at that tier.
local ElementSkills = require(script.Parent.ElementSkills)
Skills.Elements = ElementSkills.Elements
Skills.ElementById = ElementSkills.ById
Skills.BaseCount = #Skills.List
for _, def in ipairs(ElementSkills.List) do
	def.Theme = def.Theme or ElementSkills.ById[def.Element].Name
	table.insert(Skills.List, def)
end

-- 2026-10-03: shorter cooldowns across the board, 80% of each skill's listed value,
-- at most 15 s (40 s for the Ultimate-kind skill).
Skills.CooldownScale = 0.8
Skills.MaxCooldown = 15
Skills.MaxUltimateCooldown = 40

Skills.ById = {}
for i, def in ipairs(Skills.List) do
	def.Order = i
	local cap = if def.Kind == "Ultimate" then Skills.MaxUltimateCooldown else Skills.MaxCooldown
	def.Cooldown = math.min(cap, math.floor(def.Cooldown * Skills.CooldownScale * 2 + 0.5) / 2)
	Skills.ById[def.Id] = def
end

function Skills.Get(id: string?)
	return if id then Skills.ById[id] else nil
end

-- The level a skill really casts at: the bought level plus charm levels (from the
-- derived stats' SkillBonus / AllSkills), capped at HardCap. nil when not learned.
function Skills.Effective(level: number?, stats, id: string): number?
	if not level then
		return nil
	end
	local bonus = 0
	if stats then
		bonus = (stats.SkillBonus and stats.SkillBonus[id] or 0) + (stats.AllSkills or 0)
	end
	return math.clamp(level + bonus, 1, Skills.HardCap)
end

-- Damage multiplier from the skill's level.
function Skills.Power(level: number): number
	return 1 + Skills.DamagePerLevel * (math.clamp(level, 1, Skills.HardCap) - 1)
end

function Skills.Cooldown(def, level: number): number
	local l = math.clamp(level, 1, Skills.HardCap)
	local cd = def.Cooldown * (1 - Skills.CooldownPerLevel * (math.min(l, Skills.MaxLevel) - 1))
	return cd * Skills.OverCooldown ^ math.max(0, l - Skills.MaxLevel)
end

-- Buff / clone duration grows a little with level.
function Skills.Duration(def, level: number): number
	local l = math.clamp(level, 1, Skills.HardCap)
	return (def.Duration or 0) + 0.5 * (math.min(l, Skills.MaxLevel) - 1) + 0.25 * math.max(0, l - Skills.MaxLevel)
end

-- Purchase price: currency, amount (nil for free unlocks).
function Skills.Price(def): (string?, number?)
	local u = def.Unlock
	if u.Kind == "Coins" then
		return "Coins", Balance.CoinsForKills(u.Level, u.Kills)
	elseif u.Kind == "Shards" then
		return "Shards", u.Cost
	end
	return nil, nil
end

-- Cost to go from `level` to level + 1. Coin upgrades scale with the player's level.
function Skills.UpgradeCost(def, level: number, playerLevel: number): (string, number)
	if def.Unlock.Kind == "Shards" then
		return "Shards", math.floor(def.Unlock.Cost * 0.5 * level)
	end
	local base = math.max(def.Unlock.Level or 1, playerLevel)
	return "Coins", Balance.CoinsForKills(base, Skills.UpgradeKills * level)
end

-- Whether a player's save meets the skill's requirement (free unlocks are granted
-- automatically; bought ones must also be paid for). Returns ok, reason.
function Skills.MeetsRequirement(def, data): (boolean, string?)
	local u = def.Unlock
	local level = math.max(data.Level, data.Lifetime and data.Lifetime.HighestLevel or 0)
	if u.Kind == "Level" or u.Kind == "Coins" then
		if level < u.Level then
			return false, "Reach Level " .. u.Level
		end
	elseif u.Kind == "Tier" then
		if (data.BestTier or data.Tier) < u.Tier then
			return false, "Become a " .. Tiers.Get(u.Tier).Name
		end
	elseif u.Kind == "Shards" then
		if data.Rebirths < (u.Rebirths or 0) then
			return false, "Unlocks at Rebirth " .. u.Rebirths
		end
	end
	return true, nil
end

-- The elemental skills a ninja tier unlocks (in list order), and that tier's element.
function Skills.ForTier(tierIndex: number): ({ any }, any)
	local list = {}
	for _, def in ipairs(Skills.List) do
		if def.Element and def.Unlock.Kind == "Tier" and def.Unlock.Tier == tierIndex then
			table.insert(list, def)
		end
	end
	local element = nil
	for _, e in ipairs(Skills.Elements) do
		if e.Tier == tierIndex then
			element = e
		end
	end
	return list, element
end

function Skills.IsFree(def): boolean
	return def.Unlock.Kind == "Level" or def.Unlock.Kind == "Tier"
end

return Skills
