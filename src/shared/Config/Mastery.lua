--[[
	Suit mastery (in the spirit of Blox Fruits' fruit mastery).

	Every ninja suit (Config/Tiers) you have unlocked can be worn (data.Suit, picked in
	the Suits menu); the suit only changes your look, your power still comes from your
	rank. The worn suit gains mastery from every kill (bosses count for much more), up
	to Mastery.Max. Mastery gives the worn suit's passive bonus (+DamagePerLevel damage
	per level) and unlocks its four ultimates, cast with Z X C V (gamepad: d-pad):

	  Lv 25  Rush       movement: an invulnerable rush that carves a path and bursts
	  Lv 50  Lance      long range: a huge piercing beam that hits again and again
	  Lv 75  Cataclysm  area: three expanding shockwaves that launch everything
	  Lv 100 Avatar     awaken the element for a while: big damage, speed and attack
	                    speed, every swing throws a wave, and hits heal you

	Each suit's ultimates are its element's (Config/ElementSkills: Earth for Brown up to
	Void Gravity for Void), with their own names and colours, and hit harder on higher
	suits (TierScale). Save: data.Mastery[tierId] = { L = level, P = points into it }.
	Server: MasteryService (gains, suit choice) and SkillService:CastUltimate.
]]

local Tiers = require(script.Parent.Tiers)
local ElementSkills = require(script.Parent.ElementSkills)

local Mastery = {}

Mastery.Max = 100
Mastery.DamagePerLevel = 0.005 -- +0.5% damage per level of the worn suit (+50% at 100)
Mastery.KillPoints = 3 -- a same-level kill
Mastery.BossPoints = 75
Mastery.TierScale = 0.15 -- ultimates hit +15% harder per suit above Brown

-- Points to go from `level` to the next.
function Mastery.ToNext(level: number): number
	return math.floor(8 + 1.2 * level ^ 1.2)
end

-- Points a kill gives: more for enemies above you, less (down to a third) below.
function Mastery.PointsForKill(enemyLevel: number, playerLevel: number, boss: boolean): number
	if boss then
		return Mastery.BossPoints
	end
	local ratio = math.clamp(enemyLevel / math.max(1, playerLevel), 0.34, 2)
	return math.max(1, math.floor(Mastery.KillPoints * ratio + 0.5))
end

-- The four ultimate archetypes (slot order = Z X C V).
Mastery.Kinds = {
	{
		Kind = "Rush", Level = 25, Label = "Movement", Icon = "Bolt",
		Cooldown = 10, Damage = 6, BurstDamage = 4, Length = 60, Width = 14, BurstRadius = 18, Iframes = 1, MaxTargets = 60,
		Text = "Rush %d studs through everything in your way, untouchable, and burst at the end.",
	},
	{
		Kind = "Lance", Level = 50, Label = "Long range", Icon = "Star",
		Cooldown = 16, Damage = 3.2, Hits = 5, Length = 140, Width = 12, MaxTargets = 80, Windup = 0.45, Tick = 0.18,
		Text = "Fire a %d stud beam that pierces every enemy on it %d times.",
	},
	{
		Kind = "Cataclysm", Level = 75, Label = "Area", Icon = "Flame",
		Cooldown = 22, Damage = 7, Radii = { 20, 32, 46 }, Interval = 0.45, KnockUp = 55, MaxTargets = 120,
		Text = "Slam the ground: three shockwaves up to %d studs launch everything around you.",
	},
	{
		Kind = "Avatar", Level = 100, Label = "Awakening", Icon = "Crown",
		Cooldown = 60, Duration = 20, DamageMult = 1.75, SpeedMult = 1.35, AttackSpeed = 1.45, WaveDamage = 2.5,
		WaveLength = 48, WaveWidth = 9, Heal = 0.01, MaxTargets = 30,
		Text = "Awaken for %ds: x%.2f damage, faster moves and swings, every swing throws a wave and hits heal you.",
	},
}

-- Names per element, in Kinds order.
local NAMES = {
	Earth = { "Landslide Rush", "Tectonic Lance", "Continental Quake", "Stone Titan" },
	Wind = { "Tempest Rush", "Gale Spear", "Typhoon Cataclysm", "Fujin Ascension" },
	Ice = { "Glacier Rush", "Absolute Zero", "Frozen Apocalypse", "Frost Monarch" },
	Lightning = { "Thunder Rush", "Arcane Railgun", "Ten Thousand Bolts", "Raijin Ascension" },
	Fire = { "Phoenix Rush", "Inferno Lance", "Meteor Cataclysm", "Phoenix Avatar" },
	Storm = { "Phantom Rush", "Thunderhead Lance", "Black Tempest", "Storm Wraith" },
	Light = { "Radiant Rush", "Heaven's Lance", "Divine Judgment", "Seraph Ascension" },
	Sun = { "Solar Rush", "Sunspear", "Supernova", "Sun God Avatar" },
	Blood = { "Crimson Rush", "Blood Lance", "Sanguine Cataclysm", "Blood Moon Demon" },
	Darkness = { "Shadow Rush", "Void Lance", "Eternal Night", "Lord of Shadows" },
	Cosmic = { "Comet Rush", "Starlight Lance", "Big Bang", "Celestial Avatar" },
	Gravity = { "Singularity Rush", "Event Horizon", "Gravity Collapse", "Void Emperor" },
}

Mastery.Keys = { "Z", "X", "C", "V" }
Mastery.PadKeys = { "Up", "Right", "Down", "Left" }

-- The ultimates, generated per suit: Mastery.ById[id] and Mastery.ForSuit(tierId).
Mastery.ById = {}
local bySuit: { [string]: { any } } = {}
for index, tier in ipairs(Tiers.List) do
	local element = ElementSkills.Elements[index] or ElementSkills.Elements[#ElementSkills.Elements]
	local names = NAMES[element.Id] or NAMES.Earth
	local scale = 1 + Mastery.TierScale * (index - 1)
	local list = {}
	for slot, kind in ipairs(Mastery.Kinds) do
		local def = table.clone(kind)
		def.Id = "ult_" .. tier.Id .. "_" .. string.lower(kind.Kind)
		def.Name = names[slot]
		def.Slot = slot
		def.Suit = tier.Id
		def.SuitIndex = index
		def.Element = element.Id
		def.Color = element.Color
		def.Paint = element.Paint
		def.IconTint = element.IconTint
		def.Ultimate = true
		def.Scale = scale
		if kind.Kind == "Rush" then
			def.Desc = string.format(kind.Text, kind.Length)
		elseif kind.Kind == "Lance" then
			def.Desc = string.format(kind.Text, kind.Length, kind.Hits)
		elseif kind.Kind == "Cataclysm" then
			def.Desc = string.format(kind.Text, kind.Radii[#kind.Radii])
		else
			def.Desc = string.format(kind.Text, kind.Duration, kind.DamageMult)
		end
		Mastery.ById[def.Id] = def
		table.insert(list, def)
	end
	bySuit[tier.Id] = list
end

function Mastery.Get(id: string?)
	return if id then Mastery.ById[id] else nil
end

function Mastery.ForSuit(tierId: string): { any }
	return bySuit[tierId] or {}
end

-- The tier record of the suit `data` is wearing (its chosen suit if unlocked, else its rank's).
function Mastery.WornTier(data)
	local chosen = type(data.Suit) == "string" and data.Suit ~= "" and Tiers.ById[data.Suit]
	if chosen and chosen.Index <= math.max(data.BestTier or 1, data.Tier or 1) then
		return chosen
	end
	return Tiers.Get(data.Tier or 1)
end

-- Mastery level and points of a suit in a save.
function Mastery.Of(data, tierId: string): (number, number)
	local entry = type(data.Mastery) == "table" and data.Mastery[tierId]
	if type(entry) ~= "table" then
		return 1, 0
	end
	return math.clamp(tonumber(entry.L) or 1, 1, Mastery.Max), math.max(0, tonumber(entry.P) or 0)
end

-- Whether the ultimate's suit is worn and its mastery reached.
function Mastery.CanUse(data, def): (boolean, string?)
	if not def then
		return false, "Unknown ultimate"
	end
	local worn = Mastery.WornTier(data)
	if worn.Id ~= def.Suit then
		return false, "Wear the " .. Tiers.ById[def.Suit].Name .. " suit"
	end
	local level = Mastery.Of(data, def.Suit)
	if level < def.Level then
		return false, "Reach Mastery " .. def.Level .. " with this suit"
	end
	return true, nil
end

return Mastery
