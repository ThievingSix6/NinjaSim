--[[
	Suit mastery (in the spirit of Blox Fruits' fruit mastery).

	Every ninja suit (Config/Tiers) you have unlocked can be worn (data.Suit, picked in
	the Suits menu); the suit only changes your look, your power still comes from your
	rank. The worn suit gains mastery from every kill (bosses count for much more), up
	to Mastery.Max. Mastery gives the worn suit's passive bonus (+DamagePerLevel damage
	per level) and unlocks its four ultimates, cast with Z X C V (gamepad: d-pad):
	Lv 25 a movement skill, Lv 50 a long range one, Lv 75 an area one, Lv 100 a special.

	Every suit has its own four (Mastery.Kinds for Brown, Mastery.Sets for the rest),
	in its element's colours (Config/ElementSkills: Earth for Brown up to Void Gravity
	for Void), and they hit harder on higher suits (TierScale). Save: data.Mastery[tierId] = { L = level, P = points into it }.
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
Mastery.CooldownScale = 0.8 -- 2026-10-03: ultimate cooldowns are 80% of the listed value...
Mastery.MaxCooldown = 40 -- ...and never more than 40 s

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

-- Every suit has its own four ultimates, one per slot (Z X C V), unlocking at these
-- mastery levels: a movement skill, a long range one, an area one and a special.
Mastery.Slots = {
	{ Level = 25, Label = "Movement" },
	{ Level = 50, Label = "Long range" },
	{ Level = 75, Label = "Area" },
	{ Level = 100, Label = "Special" },
}

-- The Brown Ninja's set (the first ultimates; Earth).
--   Rush       an invulnerable rush that carves a path and bursts
--   Lance      a huge piercing beam that hits again and again
--   Cataclysm  three expanding shockwaves that launch everything
--   Avatar     awaken: big damage, speed and attack speed, swings throw waves, hits heal
Mastery.Kinds = {
	{
		Kind = "Rush", Steer = true, Name = "Landslide Rush", Icon = "Bolt",
		Cooldown = 10, Damage = 6, BurstDamage = 4, Length = 60, Width = 14, BurstRadius = 18, Iframes = 1, MaxTargets = 60,
		Desc = "Rush 60 studs through everything in your way, untouchable, and burst at the end.",
	},
	{
		Kind = "Lance", Name = "Tectonic Lance", Icon = "Star",
		Cooldown = 16, Damage = 3.2, Hits = 5, Length = 140, Width = 12, MaxTargets = 80, Windup = 0.45, Tick = 0.18,
		Desc = "Fire a 140 stud beam that pierces every enemy on it 5 times.",
	},
	{
		Kind = "Cataclysm", Name = "Continental Quake", Icon = "Flame",
		Cooldown = 22, Damage = 7, Radii = { 20, 32, 46 }, Interval = 0.45, KnockUp = 55, MaxTargets = 120,
		Desc = "Slam the ground: three shockwaves up to 46 studs launch everything around you.",
	},
	{
		Kind = "Avatar", Name = "Stone Titan", Icon = "Crown",
		Cooldown = 60, Duration = 20, DamageMult = 1.75, SpeedMult = 1.35, AttackSpeed = 1.45, WaveDamage = 2.5,
		WaveLength = 48, WaveWidth = 9, Heal = 0.01, MaxTargets = 30,
		Desc = "Awaken for 20s: x1.75 damage, faster moves and swings, every swing throws a wave and hits heal you.",
	},
}

-- Every other suit's own four, each with its own mechanics and look (server:
-- SuitUltimates, client: SuitUltimateEffects; poses: UltimatePoses). Damage numbers
-- are x your hit damage x the suit's Scale. Steer = true: aimed where you move.
Mastery.Sets = {
	green = { -- Wind
		{ Kind = "GaleZigzag", Steer = true, Name = "Gale Zigzag", Icon = "Boot", Cooldown = 10,
			Dashes = 3, Leg = 22, Angle = 35, Width = 12, Damage = 3.5, Iframes = 1.2, MaxTargets = 60,
			Desc = "Three lightning-fast zig-zag dashes on the wind, untouchable. Each one cuts everything it crosses." },
		{ Kind = "VacuumBoomerang", Name = "Vacuum Boomerang", Icon = "Rebirth", Cooldown = 14,
			Length = 80, Width = 14, Damage = 3.5, Steps = 8, Time = 0.8, MaxTargets = 80,
			Desc = "Hurl a giant crescent of wind 80 studs out. It comes back to your hand, cutting on the way out and back." },
		{ Kind = "Typhoon", Name = "Eye of the Typhoon", Icon = "Clover", Cooldown = 22,
			Radius = 36, Ticks = 6, Tick = 0.4, Damage = 1.6, BlastDamage = 6, MaxTargets = 120,
			Desc = "Become the eye of a typhoon: everything nearby is dragged into the spinning wall, then blown away." },
		{ Kind = "SkyDancer", Name = "Sky Dancer", Icon = "Sparkle", Cooldown = 40,
			Blades = 10, Range = 60, Damage = 4.5, Hover = 1.4, Iframes = 2.2, MaxTargets = 10,
			Desc = "Spring into the sky and loose ten homing wind blades at the ten nearest enemies, then glide down." },
	},
	blue = { -- Ice
		{ Kind = "GlacialSkate", Steer = true, Name = "Glacial Skate", Icon = "Boot", Cooldown = 10,
			Length = 60, Width = 12, Damage = 5, Freeze = 2.5, Trail = 5, Slow = 0.4, Iframes = 0.8, MaxTargets = 60,
			Desc = "Skate 60 studs on a road of ice, freezing everything you pass. The road stays and slows enemies." },
		{ Kind = "FrostVolley", Name = "Frost Lance Volley", Icon = "Shard", Cooldown = 15,
			Spears = 5, Spread = 0.4, Length = 110, Width = 6, Damage = 4, Freeze = 1.5, Interval = 0.12, MaxTargets = 40,
			Desc = "Hurl five great ice lances in a fan, one after another. Each pierces 110 studs and freezes." },
		{ Kind = "PermafrostDome", Name = "Permafrost Dome", Icon = "Shard", Cooldown = 22,
			Radius = 34, Freeze = 2.5, Damage = 2, ShatterDamage = 14, MaxTargets = 120,
			Desc = "Raise a dome of ice that freezes everything inside solid, then shatter it all at once." },
		{ Kind = "GlacialSentinel", Name = "Glacial Sentinel", Icon = "Crown", Cooldown = 45,
			Duration = 12, Interval = 0.6, Range = 50, Damage = 3, Freeze = 0.6, MaxTargets = 3,
			Desc = "Raise a towering ice sentinel for 12s. It fires freezing frost bolts at the nearest enemies." },
	},
	purple = { -- Arcane Lightning
		{ Kind = "LightningStep", Steer = true, Name = "Lightning Step", Icon = "Bolt", Cooldown = 9,
			Blinks = 3, Leg = 22, Radius = 11, Damage = 4, Interval = 0.16, Iframes = 0.7, MaxTargets = 40,
			Desc = "Blink forward three times as a bolt of lightning. Every landing calls down a thunderclap." },
		{ Kind = "RailgunArc", Name = "Railgun Arc", Icon = "Bolt", Cooldown = 14,
			Range = 90, Chain = 12, Hop = 30, Damage = 5, Windup = 0.35, MaxTargets = 12,
			Desc = "Charge and fire an arcane railgun at the nearest enemy ahead. It arcs on through up to 12 enemies." },
		{ Kind = "ThunderCage", Name = "Thunder Cage", Icon = "Lock", Cooldown = 22,
			Radius = 32, Pillars = 8, Ticks = 6, Tick = 0.45, Damage = 1.8, Stun = 3, MaxTargets = 120,
			Desc = "Drive eight lightning pillars into the ground around you. Arcs between them shock and stun everything inside." },
		{ Kind = "StormOverload", Name = "Storm Overload", Icon = "Crown", Cooldown = 45,
			Duration = 15, BoltDamage = 3.5, BoltRadius = 9, Reach = 30, DamageMult = 1.25, AttackSpeed = 1.25, MaxTargets = 20,
			Desc = "Overload for 15s: faster, harder swings, and every swing calls a lightning bolt onto the enemy in front." },
	},
	red = { -- Fire
		{ Kind = "CometDive", Steer = true, Name = "Comet Dive", Icon = "Flame", Cooldown = 10,
			Length = 48, Radius = 18, Damage = 9, Burn = 0.8, BurnTicks = 4, Air = 0.55, MaxTargets = 60,
			Desc = "Leap up and crash down as a burning comet on the nearest enemy ahead (up to 48 studs). The crater keeps burning." },
		{ Kind = "DragonBreath", Name = "Dragon's Breath", Icon = "Flame", Cooldown = 15,
			Range = 55, Sweep = 110, Ticks = 8, Tick = 0.16, Damage = 1.8, MaxTargets = 60,
			Desc = "Breathe a torrent of dragon fire that sweeps across 110 degrees in front of you." },
		{ Kind = "VolcanicEruption", Name = "Volcanic Eruption", Icon = "Flame", Cooldown = 22,
			Radius = 42, Geysers = 12, Interval = 0.15, GeyserRadius = 9, Damage = 4.5, KnockUp = 60, MaxTargets = 40,
			Desc = "Split the earth: twelve lava geysers burst up all around you, hurling enemies into the air." },
		{ Kind = "PhoenixRebirth", Name = "Phoenix Rebirth", Icon = "Heart", Cooldown = 60,
			Duration = 20, Regen = 0.03, Threshold = 0.15, Radius = 30, Damage = 10, MaxTargets = 80,
			Desc = "Wreathe yourself in phoenix fire for 20s: you regenerate, and the first deadly blow instead rebirths you at full health in an explosion." },
	},
	black = { -- Smoke Storm
		{ Kind = "ThunderheadSurf", Steer = true, Name = "Thunderhead Surf", Icon = "Boot", Cooldown = 11,
			Length = 70, Time = 1.1, Strikes = 7, Radius = 10, Damage = 3, Iframes = 1.1, MaxTargets = 30,
			Desc = "Ride a storm cloud 70 studs forward. Lightning lashes the ground beneath you the whole way." },
		{ Kind = "SpearBarrage", Name = "Thunder Spear Barrage", Icon = "Bolt", Cooldown = 15,
			Length = 100, Spears = 12, Interval = 0.08, Radius = 8, Damage = 3, MaxTargets = 30,
			Desc = "Twelve spears of lightning rain down one after another along a 100 stud line." },
		{ Kind = "BlackTempest", Name = "Black Tempest", Icon = "Rebirth", Cooldown = 22,
			Radius = 40, Damage = 5, PullDamage = 5, Bolts = 10, BoltDamage = 1.5, MaxTargets = 120,
			Desc = "A black hurricane bursts out from you, then collapses back in, dragging everything in under lightning." },
		{ Kind = "StormClones", Name = "Storm Clones", Icon = "Friends", Cooldown = 45,
			Clones = 3, Duration = 10, Interval = 1, Range = 35, Damage = 2.5, Chain = 3, MaxTargets = 3,
			Desc = "Split off three storm clones for 10s. Each one hurls chain lightning at enemies near it every second." },
	},
	white = { -- Holy Light
		{ Kind = "RadiantAscension", Steer = true, Name = "Radiant Ascension", Icon = "Sparkle", Cooldown = 11,
			Length = 45, Radius = 16, Damage = 10, Air = 0.6, Iframes = 0.9, MaxTargets = 60,
			Desc = "Ascend in a column of light and descend on the nearest enemy ahead (up to 45 studs) as a pillar from the heavens, blinding all nearby." },
		{ Kind = "PrismBeam", Name = "Prism Beam", Icon = "Star", Cooldown = 15,
			Length = 45, Splits = 3, SplitLength = 70, SplitAngle = 0.35, Width = 10, Damage = 6, SplitDamage = 5, MaxTargets = 60,
			Desc = "Fire a beam of holy light into a prism: at 45 studs it splits into three beams that fan out 70 studs further." },
		{ Kind = "JudgmentSwords", Name = "Judgment Swords", Icon = "Katana", Cooldown = 22,
			Swords = 8, Ring = 24, SwordRadius = 8, Damage = 4, CenterRadius = 34, CenterDamage = 10, MaxTargets = 120,
			Desc = "Eight great swords of light fall in a ring around you, then judgment explodes from the centre." },
		{ Kind = "DawnSanctuary", Name = "Dawn Sanctuary", Icon = "Heart", Cooldown = 45,
			Duration = 10, Radius = 26, Heal = 0.04, Tick = 0.5, Damage = 1.2, Slow = 0.5, MaxTargets = 80,
			Desc = "Consecrate the ground for 10s: you heal fast while inside, and enemies inside burn and slow." },
	},
	gold = { -- Sun
		{ Kind = "SunflareCharge", Steer = true, Name = "Sunflare Charge", Icon = "Boot", Cooldown = 10,
			Length = 55, Width = 14, Damage = 6, EndRadius = 20, EndDamage = 6, Iframes = 0.8, MaxTargets = 60,
			Desc = "Charge 55 studs wrapped in sunfire, throwing enemies aside, and end in a solar flare." },
		{ Kind = "SunspearJavelin", Name = "Sunspear Javelin", Icon = "Katana", Cooldown = 15,
			Length = 120, Width = 6, Damage = 5, Fuse = 0.9, Radius = 26, BlastDamage = 12, MaxTargets = 80,
			Desc = "Throw a javelin of sunlight. It pins the first enemy it meets, then detonates like a small sun." },
		{ Kind = "Supernova", Name = "Supernova", Icon = "Star", Cooldown = 25,
			Charge = 1.1, Radius = 55, Damage = 18, Iframes = 1.4, MaxTargets = 150,
			Desc = "Gather the sun's light for a moment, untouchable, then go supernova over 55 studs." },
		{ Kind = "SolarCrown", Name = "Solar Crown", Icon = "Crown", Cooldown = 45,
			Duration = 14, Radius = 14, Tick = 0.5, Damage = 1.2, DamageMult = 1.3, MaxTargets = 40,
			Desc = "Crown yourself with a small sun for 14s: +30% damage, and it scorches everything close to you." },
	},
	crimson = { -- Blood
		{ Kind = "BloodRend", Name = "Blood Rend", Icon = "Katana", Cooldown = 11,
			Range = 50, Targets = 6, Damage = 6, Bleed = 0.6, BleedTicks = 4, Heal = 0.02, Step = 0.12, Iframes = 1, MaxTargets = 6,
			Desc = "Flash from enemy to enemy, rending up to six of them. Each cut bleeds and heals you." },
		{ Kind = "HemorrhageScythe", Name = "Hemorrhage Scythe", Icon = "Rebirth", Cooldown = 15,
			Radius = 50, Turns = 2, Steps = 16, Time = 1.4, Damage = 2.5, PerEnemy = 3, MaxTargets = 60,
			Desc = "Fling a spinning blood scythe that spirals out to 50 studs, slicing each enemy up to three times." },
		{ Kind = "BloodMoon", Name = "Blood Moon", Icon = "Heart", Cooldown = 22,
			Radius = 42, Ticks = 6, Tick = 0.5, Damage = 2.2, Heal = 0.004, MaxTargets = 120,
			Desc = "Raise a blood moon. Everything under it bleeds again and again, and every drop heals you." },
		{ Kind = "BloodPact", Name = "Blood Pact", Icon = "Heart", Cooldown = 50,
			Cost = 0.2, Duration = 15, DamageMult = 1.6, SwingHeal = 0.02, HealCap = 0.08, WaveLength = 30, WaveWidth = 8, WaveDamage = 1.5,
			Desc = "Pay 20% of your health: for 15s you deal +60% damage and every swing throws a blood crescent that heals you for each enemy it cuts." },
	},
	shadow = { -- Darkness
		{ Kind = "ShadowSwap", Name = "Shadow Swap", Icon = "Oni", Cooldown = 9,
			Range = 60, Damage = 14, SplashRadius = 12, Splash = 4, MaxTargets = 30,
			Desc = "Sink into your shadow and rise behind the farthest enemy in reach, striking it from the dark." },
		{ Kind = "ShadowSerpent", Name = "Shadow Serpent", Icon = "Oni", Cooldown = 15,
			Range = 80, Bites = 7, Hop = 24, Damage = 4, Interval = 0.15, MaxTargets = 7,
			Desc = "Loose a serpent of shadow. It hunts down seven enemies one after another, biting each." },
		{ Kind = "NightFall", Name = "Nightfall", Icon = "Oni", Cooldown = 22,
			Radius = 40, Root = 2, Delay = 1, Damage = 8, MaxTargets = 120,
			Desc = "Night falls around you: shadow hands grab every enemy, then spikes of darkness impale them." },
		{ Kind = "ShadowRealm", Name = "Shadow Realm", Icon = "Crown", Cooldown = 45,
			Duration = 5, SpeedMult = 1.5, EndRadius = 45, EndDamage = 10, MaxTargets = 120,
			Desc = "Step into the shadow realm for 5s: untouchable and fast. When you step out, everything near you is torn apart." },
	},
	celestial = { -- Cosmic
		{ Kind = "WarpGate", Steer = true, Name = "Warp Gate", Icon = "Rebirth", Cooldown = 10,
			Length = 65, Radius = 14, Damage = 6, Iframes = 0.6, MaxTargets = 60,
			Desc = "Open a gate in space and step out of another 65 studs ahead. Both gates blast with starlight." },
		{ Kind = "StarlightArrow", Name = "Starlight Arrow", Icon = "Star", Cooldown = 16,
			Distance = 60, Radius = 30, Arrows = 20, Delay = 0.6, Damage = 2.4, MaxTargets = 60,
			Desc = "Shoot an arrow of starlight into the sky. It bursts into twenty arrows raining down 60 studs ahead." },
		{ Kind = "ConstellationCollapse", Name = "Constellation Collapse", Icon = "Star", Cooldown = 24,
			Radius = 46, Stars = 14, Damage = 6, Delay = 0.9, BangRadius = 20, BangDamage = 10, MaxTargets = 120,
			Desc = "Mark the enemies around you as stars of a constellation, then bring every star crashing down." },
		{ Kind = "TimeStop", Name = "Zodiac Time Stop", Icon = "Clock", Cooldown = 50,
			Radius = 80, Stop = 4, Damage = 16, MaxTargets = 150,
			Desc = "Stop time for every enemy within 80 studs for 4s. When it starts again, all the damage lands at once." },
	},
	void = { -- Void Gravity
		{ Kind = "GravitySlingshot", Name = "Gravity Slingshot", Icon = "Boot", Cooldown = 10,
			Range = 70, Width = 12, Damage = 7, Radius = 16, Iframes = 0.8, MaxTargets = 60,
			Desc = "Slingshot yourself at the farthest enemy in reach, dragging everything in your wake along to the landing." },
		{ Kind = "HorizonBeam", Name = "Event Horizon", Icon = "Star", Cooldown = 15,
			Length = 110, Width = 16, PullTime = 0.4, Hits = 4, Tick = 0.2, Damage = 3, MaxTargets = 80,
			Desc = "Fire a beam of collapsed space that pulls enemies onto it, then crushes them four times." },
		{ Kind = "GravityCrush", Name = "Gravity Crush", Icon = "Rebirth", Cooldown = 22,
			Radius = 40, Float = 1.2, Ticks = 4, Damage = 2.5, Slam = 8, MaxTargets = 120,
			Desc = "Lift everything around you into the air, crush it in a fist of gravity, then slam it down." },
		{ Kind = "BlackSun", Name = "Black Sun", Icon = "Rebirth", Cooldown = 45,
			Distance = 30, Radius = 50, Duration = 4, Tick = 0.5, Damage = 1.5, Collapse = 16, MaxTargets = 150,
			Desc = "Ignite a black sun ahead of you. It drags in everything within 50 studs for 4s, then collapses." },
	},
}

Mastery.Keys = { "Z", "X", "C", "V" }
Mastery.PadKeys = { "Up", "Right", "Down", "Left" }

-- The ultimates, built per suit: Mastery.ById[id] and Mastery.ForSuit(tierId).
Mastery.ById = {}
local bySuit: { [string]: { any } } = {}
for index, tier in ipairs(Tiers.List) do
	local element = ElementSkills.Elements[index] or ElementSkills.Elements[#ElementSkills.Elements]
	local set = Mastery.Sets[tier.Id] or Mastery.Kinds
	local scale = 1 + Mastery.TierScale * (index - 1)
	local list = {}
	for slot, base in ipairs(set) do
		local def = table.clone(base)
		def.Cooldown = math.min(Mastery.MaxCooldown, math.floor(base.Cooldown * Mastery.CooldownScale * 2 + 0.5) / 2)
		def.Id = "ult_" .. tier.Id .. "_" .. string.lower(base.Kind)
		def.Slot = slot
		def.Level = Mastery.Slots[slot].Level
		def.Label = Mastery.Slots[slot].Label
		def.Suit = tier.Id
		def.SuitIndex = index
		def.Element = element.Id
		def.Color = element.Color
		def.Paint = element.Paint
		def.IconTint = element.IconTint
		def.Ultimate = true
		def.Scale = scale
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
