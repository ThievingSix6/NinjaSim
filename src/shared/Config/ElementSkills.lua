--[[
	Elemental tier skills: every ninja tier unlocks two skills in its colour's
	element (free, at that tier; they stay through rebirths because the unlock
	reads BestTier). Config/Skills appends this List to Skills.List, so they level,
	equip and cool down exactly like the base skills. SkillService/ElementCasts
	(server) and Controllers/ElementEffects (client) hold their behaviour and looks.

	Extra fields used by these skills (besides the ones in Config/Skills):
	  Element    the element id (see Elements below)
	  IconTint   multiplies the atlas icon's colours (cards, slots, skill bar); only
	             used on light / neutral icons, since a multiply can only darken
	  Hits       damage instances per target (menu shows "N x dmg")
	  FinalDamage a second, bigger hit after the first ones
	  Dot / DotTicks / DotTag   damage over time per tick (Burn, Bleed, Holy, ...)
	  Slow / SlowTime           enemy walk speed multiplier and seconds
	  Freeze / Root             stun seconds, drawn as ice / vines / hands
	  KnockUp    upward launch speed (studs/s); Pull = pulls toward the centre
	  Heal       fraction of max health healed (per tick for fields)
	  Field      seconds a lingering area lasts; Tick = seconds between its hits
	  AreaText / Effect         short texts for the Skills menu
	  PointCast  true: the skill plays well cast at a point (SkillService:CastAt,
	             e.g. "chance on hit to cast" procs). Self-centred ones centre there.
	Damage is x the player's hit damage, like every skill. A tier's strong attack
	starts at x2.2 (Brown) and climbs about x0.3 per tier to x5.5 (Void).
]]

local rgb = Color3.fromRGB

local ElementSkills = {}

-- One element per ninja tier, in tier order (Tier = index in Config/Tiers).
ElementSkills.Elements = {
	{ Id = "Earth", Name = "Earth", Tier = 1, Icon = "Mystery", IconTint = rgb(215, 160, 110), Color = rgb(200, 150, 95), Paint = { rgb(214, 162, 102), rgb(118, 76, 40) } },
	{ Id = "Wind", Name = "Wind", Tier = 2, Icon = "Clover", Color = rgb(130, 240, 130), Paint = { rgb(130, 232, 120), rgb(36, 140, 70) } },
	{ Id = "Ice", Name = "Ice", Tier = 3, Icon = "Shard", Color = rgb(150, 225, 255), Paint = { rgb(170, 230, 255), rgb(50, 130, 230) } },
	{ Id = "Lightning", Name = "Arcane Lightning", Tier = 4, Icon = "Bolt", Color = rgb(200, 140, 255), Paint = { rgb(206, 150, 255), rgb(104, 40, 200) } },
	{ Id = "Fire", Name = "Fire", Tier = 5, Icon = "Flame", Color = rgb(255, 120, 50), Paint = { rgb(255, 150, 70), rgb(200, 40, 30) } },
	{ Id = "Storm", Name = "Smoke Storm", Tier = 6, Icon = "Bolt", Color = rgb(170, 175, 205), Paint = { rgb(120, 124, 150), rgb(34, 34, 46) } },
	{ Id = "Light", Name = "Holy Light", Tier = 7, Icon = "Sparkle", IconTint = rgb(255, 255, 235), Color = rgb(255, 248, 210), Paint = { rgb(255, 252, 236), rgb(176, 196, 226) } },
	{ Id = "Sun", Name = "Sun", Tier = 8, Icon = "Star", Color = rgb(255, 205, 60), Paint = { rgb(255, 222, 90), rgb(214, 128, 20) } },
	{ Id = "Blood", Name = "Blood", Tier = 9, Icon = "Heart", Color = rgb(235, 30, 70), Paint = { rgb(232, 50, 80), rgb(100, 6, 26) } },
	{ Id = "Darkness", Name = "Darkness", Tier = 10, Icon = "Oni", IconTint = rgb(190, 150, 255), Color = rgb(150, 80, 240), Paint = { rgb(110, 66, 190), rgb(22, 12, 40) } },
	{ Id = "Cosmic", Name = "Cosmic", Tier = 11, Icon = "Star", IconTint = rgb(200, 225, 255), Color = rgb(150, 210, 255), Paint = { rgb(90, 140, 240), rgb(30, 30, 100) } },
	{ Id = "Gravity", Name = "Void Gravity", Tier = 12, Icon = "Rebirth", IconTint = rgb(225, 140, 255), Color = rgb(210, 80, 255), Paint = { rgb(190, 70, 255), rgb(40, 0, 70) } },
}
ElementSkills.ById = {}
for _, element in ipairs(ElementSkills.Elements) do
	ElementSkills.ById[element.Id] = element
end

local function tier(n: number)
	return { Kind = "Tier", Tier = n }
end

ElementSkills.List = {
	-- ===== Brown Ninja: Earth =====
	{
		Id = "stone_spikes", Name = "Stone Spikes", Element = "Earth", Kind = "Damage",
		Icon = "Shard", Paint = { rgb(214, 162, 102), rgb(118, 76, 40) }, Color = rgb(200, 150, 95),
		Desc = "Stamp the ground: a line of rock spikes bursts out ahead and launches everything on it.",
		Cooldown = 8, Damage = 2.2, Length = 36, Width = 9, MaxTargets = 30, Knockback = 0, KnockUp = 42, Stun = 0.9,
		AreaText = "36 stud line", Effect = "Knock-up", PointCast = false,
		Unlock = tier(1),
	},
	{
		Id = "earth_wall", Name = "Earth Wall", Element = "Earth", Kind = "Control",
		Icon = "Mystery", IconTint = rgb(190, 140, 96), Paint = { rgb(190, 140, 90), rgb(96, 62, 34) }, Color = rgb(180, 130, 80),
		Desc = "Raise a wall of stone in front of you. It slams enemies back and pins them behind it.",
		Cooldown = 12, Damage = 1.3, Range = 8, Width = 26, Depth = 8, MaxTargets = 30, Knockback = 2.2, Stun = 2, Field = 3,
		AreaText = "26 stud wall", Effect = "Pin 2s", PointCast = true,
		Unlock = tier(1),
	},

	-- ===== Green Ninja: Wind / Nature =====
	{
		Id = "razor_gale", Name = "Razor Gale", Element = "Wind", Kind = "Damage",
		Icon = "Rebirth", Paint = { rgb(130, 232, 120), rgb(36, 140, 70) }, Color = rgb(150, 255, 160),
		Desc = "Send a whirling tornado of razor leaves forward. It drags enemies along and cuts them four times.",
		Cooldown = 9, Damage = 0.8, Hits = 4, Length = 40, Radius = 8, MaxTargets = 30, Knockback = 0.5, Stun = 0.3,
		AreaText = "40 stud tornado", Effect = "Pulls along", PointCast = true,
		Unlock = tier(2),
	},
	{
		Id = "vine_snare", Name = "Vine Snare", Element = "Wind", Kind = "Control",
		Icon = "Clover", Paint = { rgb(110, 210, 90), rgb(40, 110, 40) }, Color = rgb(120, 220, 90),
		Desc = "Thorny vines burst from the ground under the nearest crowd and hold them fast.",
		Cooldown = 13, Damage = 1, Range = 34, Radius = 14, MaxTargets = 30, Knockback = 0, Stun = 3, Root = 3,
		Dot = 0.3, DotTicks = 3, DotTag = "Thorns",
		AreaText = "14 stud patch", Effect = "Root 3s", PointCast = true,
		Unlock = tier(2),
	},

	-- ===== Blue Ninja: Ice =====
	{
		Id = "frost_nova", Name = "Frost Nova", Element = "Ice", Kind = "Damage",
		Icon = "Shard", Paint = { rgb(170, 230, 255), rgb(50, 130, 230) }, Color = rgb(150, 225, 255),
		Desc = "Burst into a ring of frost. Every enemy around you is frozen solid in a block of ice.",
		Cooldown = 11, Damage = 2.8, Radius = 20, MaxTargets = 40, Knockback = 0, Stun = 2.2, Freeze = 2.2,
		AreaText = "20 studs around you", Effect = "Freeze 2.2s", PointCast = true,
		Unlock = tier(3),
	},
	{
		Id = "blizzard_gust", Name = "Blizzard Gust", Element = "Ice", Kind = "Control",
		Icon = "Sparkle", Paint = { rgb(220, 244, 255), rgb(90, 160, 220) }, Color = rgb(200, 240, 255),
		Desc = "Blow a freezing gale in a wide cone. Enemies caught in it are chilled and crawl for a while.",
		Cooldown = 8, Damage = 1.4, Range = 36, Arc = 0.55, MaxTargets = 30, Knockback = 0.9, Stun = 0.2,
		Slow = 0.45, SlowTime = 4,
		AreaText = "36 stud cone", Effect = "Slow 55% 4s", PointCast = false,
		Unlock = tier(3),
	},

	-- ===== Purple Ninja: Arcane Lightning =====
	{
		Id = "arcane_storm", Name = "Arcane Storm", Element = "Lightning", Kind = "Damage",
		Icon = "Bolt", Paint = { rgb(206, 150, 255), rgb(104, 40, 200) }, Color = rgb(210, 150, 255),
		Desc = "Violet lightning rains around you, striking enemy after enemy. More bolts each level.",
		Cooldown = 10, Damage = 1.3, Bolts = 8, Radius = 26, BoltRadius = 7, MaxTargets = 12, Knockback = 0.4, Stun = 0.6,
		AreaText = "26 stud storm", Effect = "Stun 0.6s", PointCast = true,
		Unlock = tier(4),
	},
	{
		Id = "arcane_blink", Name = "Arcane Blink", Element = "Lightning", Kind = "Mobility",
		Icon = "Book", IconTint = rgb(225, 185, 255), Paint = { rgb(170, 110, 255), rgb(70, 24, 150) }, Color = rgb(190, 130, 255),
		Desc = "Blink through space, leaving a rune behind. Both ends of the jump explode in arcane light.",
		Cooldown = 7, Damage = 1.6, Hits = 2, Length = 26, Radius = 12, MaxTargets = 30, Knockback = 1, Stun = 0.6,
		AreaText = "26 stud blink", Effect = "Two blasts", PointCast = true,
		Unlock = tier(4),
	},

	-- ===== Red Ninja: Fire =====
	{
		Id = "phoenix_dive", Name = "Phoenix Dive", Element = "Fire", Kind = "Damage",
		Icon = "Flame", Paint = { rgb(255, 170, 70), rgb(210, 40, 20) }, Color = rgb(255, 130, 50),
		Desc = "Wrap yourself in phoenix fire, dive onto the enemy ahead and explode, setting the crowd ablaze.",
		Cooldown = 11, Damage = 3.4, Length = 28, Radius = 16, MaxTargets = 40, Knockback = 1.6, Stun = 0.6,
		Dot = 0.5, DotTicks = 4, DotTag = "Burn",
		AreaText = "28 stud dive", Effect = "Burn x4", PointCast = true,
		Unlock = tier(5),
	},
	{
		Id = "ring_of_fire", Name = "Ring of Fire", Element = "Fire", Kind = "Control",
		Icon = "Flame", IconTint = rgb(255, 120, 90), Paint = { rgb(255, 110, 60), rgb(150, 20, 20) }, Color = rgb(255, 90, 40),
		Desc = "A wall of flame rings you for a few seconds. Anything inside burns and slows in the heat.",
		Cooldown = 15, Damage = 0.45, Radius = 18, MaxTargets = 40, Knockback = 0, Stun = 0, Field = 5, Tick = 0.5,
		Slow = 0.7, SlowTime = 1, DotTag = "Burn",
		AreaText = "18 studs, 5s", Effect = "Burn + slow", PointCast = true,
		Unlock = tier(5),
	},

	-- ===== Black Ninja: Smoke Storm =====
	{
		Id = "storm_cloud", Name = "Storm Cloud", Element = "Storm", Kind = "Damage",
		Icon = "Bolt", Paint = { rgb(120, 124, 150), rgb(34, 34, 46) }, Color = rgb(200, 210, 255),
		Desc = "Summon a black thundercloud over the nearest crowd. It hammers them with lightning.",
		Cooldown = 13, Damage = 0.75, Hits = 6, Range = 38, Radius = 16, MaxTargets = 30, Knockback = 0.3, Stun = 0.45,
		Field = 3, Tick = 0.5,
		AreaText = "16 stud cloud", Effect = "6 strikes", PointCast = true,
		Unlock = tier(6),
	},
	{
		Id = "smoke_cyclone", Name = "Smoke Cyclone", Element = "Storm", Kind = "Control",
		Icon = "Rebirth", IconTint = rgb(170, 170, 200), Paint = { rgb(150, 150, 175), rgb(50, 50, 66) }, Color = rgb(160, 160, 190),
		Desc = "Spin up a cyclone of black smoke that sucks enemies in, then hurls them into the sky.",
		Cooldown = 10, Damage = 2, Radius = 22, MaxTargets = 40, Knockback = 0, KnockUp = 55, Stun = 1.4, Pull = true,
		AreaText = "22 studs around you", Effect = "Pull, launch", PointCast = true,
		Unlock = tier(6),
	},

	-- ===== White Ninja: Holy Light =====
	{
		Id = "holy_judgment", Name = "Holy Judgment", Element = "Light", Kind = "Damage",
		Icon = "Sparkle", IconTint = rgb(255, 255, 235), Paint = { rgb(255, 252, 236), rgb(176, 196, 226) }, Color = rgb(255, 248, 210),
		Desc = "Point to the sky: a pillar of holy light crashes down on the nearest crowd.",
		Cooldown = 10, Damage = 4.6, Range = 40, Radius = 14, MaxTargets = 30, Knockback = 1.4, Stun = 1,
		AreaText = "14 stud pillar", Effect = "Stun 1s", PointCast = true,
		Unlock = tier(7),
	},
	{
		Id = "sanctuary", Name = "Sanctuary", Element = "Light", Kind = "Buff",
		Icon = "Heart", IconTint = rgb(255, 236, 190), Paint = { rgb(255, 240, 190), rgb(220, 170, 80) }, Color = rgb(255, 236, 170),
		Desc = "Bless the ground around you. While it glows you heal, and enemies inside are seared.",
		Cooldown = 20, Damage = 0.45, Radius = 18, MaxTargets = 40, Knockback = 0, Stun = 0, Field = 6, Tick = 0.6,
		Heal = 0.03, DotTag = "Holy",
		AreaText = "18 studs, 6s", Effect = "Heal 5% HP/s", PointCast = true,
		Unlock = tier(7),
	},

	-- ===== Gold Ninja: Sun =====
	{
		Id = "solar_flare", Name = "Solar Flare", Element = "Sun", Kind = "Damage",
		Icon = "Star", Paint = { rgb(255, 222, 90), rgb(214, 128, 20) }, Color = rgb(255, 210, 70),
		Desc = "Raise a tiny sun over your head and let it burst. The blinding flare scorches a huge circle.",
		Cooldown = 14, Damage = 4.3, Radius = 28, MaxTargets = 50, Knockback = 2, Stun = 1.6,
		AreaText = "28 studs around you", Effect = "Blind, stun", PointCast = true,
		Unlock = tier(8),
	},
	{
		Id = "sunbeam", Name = "Sunbeam", Element = "Sun", Kind = "Damage",
		Icon = "Coin", Paint = { rgb(255, 236, 140), rgb(230, 150, 30) }, Color = rgb(255, 230, 120),
		Desc = "Fire a blazing beam of sunlight straight ahead. It keeps burning for a moment and pushes foes away.",
		Cooldown = 10, Damage = 1, Hits = 5, Length = 48, Width = 10, MaxTargets = 30, Knockback = 0.5, Stun = 0.3, Tick = 0.3,
		AreaText = "48 stud beam", Effect = "5 hits", PointCast = false,
		Unlock = tier(8),
	},

	-- ===== Crimson Ninja: Blood =====
	{
		Id = "crimson_crescent", Name = "Crimson Crescent", Element = "Blood", Kind = "Damage",
		Icon = "Katana", IconTint = rgb(255, 110, 130), Paint = { rgb(232, 50, 80), rgb(100, 6, 26) }, Color = rgb(235, 30, 70),
		Desc = "Swing a giant crescent of blood that flies forward, splitting the crowd and leaving it bleeding.",
		Cooldown = 10, Damage = 4.6, Length = 44, Width = 16, MaxTargets = 40, Knockback = 1.2, Stun = 0.5,
		Dot = 0.6, DotTicks = 4, DotTag = "Bleed",
		AreaText = "44 stud wave", Effect = "Bleed x4", PointCast = false,
		Unlock = tier(9),
	},
	{
		Id = "life_drain", Name = "Life Drain", Element = "Blood", Kind = "Buff",
		Icon = "Heart", Paint = { rgb(255, 80, 110), rgb(130, 10, 40) }, Color = rgb(255, 60, 90),
		Desc = "Tether the enemies around you with threads of blood and drink their life to heal yourself.",
		Cooldown = 16, Damage = 0.7, Hits = 5, Radius = 24, MaxTargets = 8, Knockback = 0, Stun = 0.3, Tick = 0.4,
		Heal = 0.012, DotTag = "Drain",
		AreaText = "8 foes in 24", Effect = "Lifesteal", PointCast = true,
		Unlock = tier(9),
	},

	-- ===== Shadow Ninja: Darkness =====
	{
		Id = "umbral_grasp", Name = "Umbral Grasp", Element = "Darkness", Kind = "Damage",
		Icon = "Oni", IconTint = rgb(190, 150, 255), Paint = { rgb(110, 66, 190), rgb(22, 12, 40) }, Color = rgb(150, 80, 240),
		Desc = "Shadow hands rise under every enemy around you, hold them still, then crush them.",
		Cooldown = 13, Damage = 2.2, FinalDamage = 3, Radius = 24, MaxTargets = 30, Knockback = 0, Stun = 1.6, Root = 1.4,
		AreaText = "24 studs around you", Effect = "Grab, crush", PointCast = true,
		Unlock = tier(10),
	},
	{
		Id = "eclipse", Name = "Eclipse", Element = "Darkness", Kind = "Control",
		Icon = "Coin", IconTint = rgb(150, 115, 210), Paint = { rgb(70, 40, 120), rgb(10, 4, 20) }, Color = rgb(120, 60, 220),
		Desc = "Blot out the sun. Enemies in the darkness lose sight of you, stumble slowly and wither.",
		Cooldown = 18, Damage = 0.35, Radius = 24, MaxTargets = 40, Knockback = 0, Stun = 0, Field = 5, Tick = 0.5,
		Slow = 0.5, SlowTime = 1, DotTag = "Shadow",
		AreaText = "24 studs, 5s", Effect = "Blind + slow", PointCast = true,
		Unlock = tier(10),
	},

	-- ===== Celestial Ninja: Cosmic =====
	{
		Id = "starfall", Name = "Starfall", Element = "Cosmic", Kind = "Damage",
		Icon = "Star", IconTint = rgb(200, 225, 255), Paint = { rgb(90, 140, 240), rgb(30, 30, 100) }, Color = rgb(170, 215, 255),
		Desc = "Call down a shower of falling stars on the nearest crowd. Each one lands with a blast.",
		Cooldown = 13, Damage = 2.1, Meteors = 7, Range = 40, Radius = 18, MeteorRadius = 9, MaxTargets = 20, Knockback = 1.4, Stun = 0.6,
		AreaText = "18 stud zone", Effect = "Meteors", PointCast = true,
		Unlock = tier(11),
	},
	{
		Id = "constellation", Name = "Constellation", Element = "Cosmic", Kind = "Damage",
		Icon = "Sparkle", Paint = { rgb(150, 200, 255), rgb(60, 70, 170) }, Color = rgb(150, 210, 255),
		Desc = "Mark a chain of enemies as stars and join them into a constellation, then make it explode.",
		Cooldown = 10, Damage = 4.6, Range = 34, Arc = 0.2, Chain = 10, ChainRange = 18, MaxTargets = 16, Knockback = 1, Stun = 1.2,
		AreaText = "Chains to 10+ foes", Effect = "Stun 1.2s", PointCast = true,
		Unlock = tier(11),
	},

	-- ===== Void Ninja: Gravity =====
	{
		Id = "black_hole", Name = "Black Hole", Element = "Gravity", Kind = "Damage",
		Icon = "Rebirth", IconTint = rgb(225, 140, 255), Paint = { rgb(190, 70, 255), rgb(40, 0, 70) }, Color = rgb(210, 80, 255),
		Desc = "Open a black hole in the crowd. It drags every enemy in, grinds them, then collapses in a blast.",
		Cooldown = 16, Damage = 0.7, Hits = 6, FinalDamage = 5.5, Range = 36, Radius = 24, MaxTargets = 50, Knockback = 2.5, Stun = 0.5,
		Field = 2.4, Tick = 0.4, Pull = true,
		AreaText = "24 stud vortex", Effect = "Pull, blast", PointCast = true,
		Unlock = tier(12),
	},
	{
		Id = "zero_gravity", Name = "Zero Gravity", Element = "Gravity", Kind = "Control",
		Icon = "Boot", IconTint = rgb(230, 170, 255), Paint = { rgb(220, 120, 255), rgb(80, 20, 140) }, Color = rgb(230, 130, 255),
		Desc = "Switch gravity off around you. Enemies float helplessly into the air, then slam back down.",
		Cooldown = 13, Damage = 1.2, FinalDamage = 4.4, Radius = 28, MaxTargets = 50, Knockback = 0, KnockUp = 30, Stun = 2.6,
		AreaText = "28 studs around you", Effect = "Float, slam", PointCast = true,
		Unlock = tier(12),
	},
}

return ElementSkills
