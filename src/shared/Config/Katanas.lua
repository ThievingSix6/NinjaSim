--[[
	All katanas. Sources:
	  "Tier" - granted when the matching ninja tier unlocks (never lost)
	  "Shop" - bought with Coins in the Weapons shop (never lost)
	  "Boss" - rare drop from a boss (never lost)

	Mult is the damage multiplier. RequiredTier gates equipping (so rebirthing
	re-locks strong blades until you re-earn the tier, but you keep them).

	Look describes how Visuals/KatanaBuilder assembles the model:
	  Blade/BladeMaterial   main blade colour + material
	  Edge/EdgeGlow         cutting edge strip (neon when EdgeGlow)
	  Length, Width, Curve  blade shape (Curve in radians of total bend)
	  Guard                 "Round" | "Square" | "Flower" | "Spiked" | "Wings" | "Ring" | "Crescent"
	  GuardColor, Handle, Wrap, Pommel ("Cap" | "Gem" | "Ring" | "Tassel"), Gem
	  Particles             optional emitter preset (see KatanaBuilder.ParticlePresets)
	  Light                 optional PointLight colour
	  Trail                 swing trail colours {start, end}
]]

local Katanas = {}

local rgb = Color3.fromRGB

Katanas.List = {
	-- ===== Tier katanas =====
	{
		Id = "brown_katana", Name = "Brown Katana", Rarity = "Common", Mult = 1.0, RequiredTier = 1, Source = "Tier",
		Look = {
			Blade = rgb(196, 170, 140), BladeMaterial = Enum.Material.Metal, Edge = rgb(230, 220, 205), EdgeGlow = false,
			Length = 3.4, Width = 0.26, Curve = 0.10, Guard = "Round", GuardColor = rgb(90, 60, 36),
			Handle = rgb(70, 44, 26), Wrap = rgb(150, 105, 64), Pommel = "Cap",
			Trail = { rgb(200, 170, 130), rgb(120, 90, 60) },
		},
	},
	{
		Id = "jade_katana", Name = "Jade Katana", Rarity = "Uncommon", Mult = 1.4, RequiredTier = 2, Source = "Tier",
		Look = {
			Blade = rgb(110, 200, 130), BladeMaterial = Enum.Material.Glass, Edge = rgb(200, 255, 200), EdgeGlow = false,
			Length = 3.6, Width = 0.27, Curve = 0.12, Guard = "Square", GuardColor = rgb(40, 90, 50),
			Handle = rgb(20, 50, 28), Wrap = rgb(150, 230, 110), Pommel = "Ring",
			Trail = { rgb(150, 255, 150), rgb(40, 140, 60) },
		},
	},
	{
		Id = "tide_katana", Name = "Tide Katana", Rarity = "Rare", Mult = 2.0, RequiredTier = 3, Source = "Tier",
		Look = {
			Blade = rgb(150, 180, 220), BladeMaterial = Enum.Material.Metal, Edge = rgb(90, 220, 255), EdgeGlow = true,
			Length = 3.8, Width = 0.27, Curve = 0.14, Guard = "Flower", GuardColor = rgb(30, 70, 150),
			Handle = rgb(16, 30, 70), Wrap = rgb(100, 210, 255), Pommel = "Gem", Gem = rgb(90, 220, 255),
			Particles = "Droplets", Trail = { rgb(120, 230, 255), rgb(20, 80, 200) },
		},
	},
	{
		Id = "amethyst_katana", Name = "Amethyst Katana", Rarity = "Rare", Mult = 2.8, RequiredTier = 4, Source = "Tier",
		Look = {
			Blade = rgb(170, 110, 255), BladeMaterial = Enum.Material.Glass, Edge = rgb(230, 190, 255), EdgeGlow = true,
			Length = 3.9, Width = 0.28, Curve = 0.12, Guard = "Crescent", GuardColor = rgb(80, 30, 130),
			Handle = rgb(40, 14, 70), Wrap = rgb(200, 150, 255), Pommel = "Gem", Gem = rgb(210, 140, 255),
			Particles = "Sparkle", Light = rgb(180, 110, 255), Trail = { rgb(220, 170, 255), rgb(100, 30, 200) },
		},
	},
	{
		Id = "ember_katana", Name = "Ember Katana", Rarity = "Epic", Mult = 4.0, RequiredTier = 5, Source = "Tier",
		Look = {
			Blade = rgb(200, 50, 30), BladeMaterial = Enum.Material.Metal, Edge = rgb(255, 150, 40), EdgeGlow = true,
			Length = 4.0, Width = 0.29, Curve = 0.16, Guard = "Spiked", GuardColor = rgb(255, 190, 70),
			Handle = rgb(60, 10, 10), Wrap = rgb(255, 190, 70), Pommel = "Tassel", Gem = rgb(255, 80, 30),
			Particles = "Embers", Light = rgb(255, 110, 40), Trail = { rgb(255, 210, 90), rgb(255, 40, 20) },
		},
	},
	{
		Id = "obsidian_katana", Name = "Obsidian Katana", Rarity = "Epic", Mult = 5.6, RequiredTier = 6, Source = "Tier",
		Look = {
			Blade = rgb(24, 24, 30), BladeMaterial = Enum.Material.Metal, Edge = rgb(240, 240, 255), EdgeGlow = true,
			Length = 4.1, Width = 0.28, Curve = 0.13, Guard = "Square", GuardColor = rgb(160, 165, 180),
			Handle = rgb(10, 10, 12), Wrap = rgb(200, 30, 30), Pommel = "Gem", Gem = rgb(255, 40, 40),
			Particles = "Smoke", Trail = { rgb(255, 255, 255), rgb(30, 30, 40) },
		},
	},
	{
		Id = "frostmoon_katana", Name = "Frostmoon Katana", Rarity = "Legendary", Mult = 8.0, RequiredTier = 7, Source = "Tier",
		Look = {
			Blade = rgb(200, 235, 255), BladeMaterial = Enum.Material.Ice, Edge = rgb(140, 230, 255), EdgeGlow = true,
			Length = 4.2, Width = 0.3, Curve = 0.15, Guard = "Crescent", GuardColor = rgb(230, 240, 255),
			Handle = rgb(40, 60, 100), Wrap = rgb(160, 230, 255), Pommel = "Gem", Gem = rgb(160, 240, 255),
			Particles = "Frost", Light = rgb(150, 220, 255), Trail = { rgb(230, 250, 255), rgb(80, 170, 255) },
		},
	},
	{
		Id = "sunforged_katana", Name = "Sunforged Katana", Rarity = "Legendary", Mult = 11, RequiredTier = 8, Source = "Tier",
		Look = {
			Blade = rgb(255, 205, 70), BladeMaterial = Enum.Material.Foil, Edge = rgb(255, 250, 200), EdgeGlow = true,
			Length = 4.3, Width = 0.31, Curve = 0.14, Guard = "Wings", GuardColor = rgb(255, 230, 120),
			Handle = rgb(120, 70, 10), Wrap = rgb(255, 245, 210), Pommel = "Gem", Gem = rgb(255, 255, 160),
			Particles = "Radiance", Light = rgb(255, 220, 110), Trail = { rgb(255, 255, 200), rgb(255, 170, 20) },
		},
	},
	{
		Id = "bloodmoon_katana", Name = "Bloodmoon Katana", Rarity = "Mythic", Mult = 15, RequiredTier = 9, Source = "Tier",
		Look = {
			Blade = rgb(60, 0, 10), BladeMaterial = Enum.Material.Metal, Edge = rgb(255, 30, 70), EdgeGlow = true,
			Length = 4.5, Width = 0.32, Curve = 0.2, Guard = "Spiked", GuardColor = rgb(40, 0, 8),
			Handle = rgb(20, 0, 4), Wrap = rgb(255, 40, 80), Pommel = "Tassel", Gem = rgb(255, 20, 60),
			Particles = "BloodFlame", Light = rgb(255, 30, 60), Trail = { rgb(255, 80, 110), rgb(90, 0, 20) },
		},
	},
	{
		Id = "umbra_katana", Name = "Umbra Katana", Rarity = "Mythic", Mult = 21, RequiredTier = 10, Source = "Tier",
		Look = {
			Blade = rgb(20, 8, 40), BladeMaterial = Enum.Material.Glass, Edge = rgb(150, 70, 255), EdgeGlow = true,
			Length = 4.6, Width = 0.32, Curve = 0.18, Guard = "Ring", GuardColor = rgb(90, 40, 180),
			Handle = rgb(8, 4, 16), Wrap = rgb(150, 70, 255), Pommel = "Gem", Gem = rgb(170, 90, 255),
			Particles = "Shadow", Light = rgb(140, 60, 255), Trail = { rgb(180, 120, 255), rgb(10, 0, 30) },
		},
	},
	{
		Id = "starfall_katana", Name = "Starfall Katana", Rarity = "Divine", Mult = 29, RequiredTier = 11, Source = "Tier",
		Look = {
			Blade = rgb(170, 220, 255), BladeMaterial = Enum.Material.Glass, Edge = rgb(255, 225, 120), EdgeGlow = true,
			Length = 4.7, Width = 0.33, Curve = 0.14, Guard = "Wings", GuardColor = rgb(255, 225, 130),
			Handle = rgb(30, 40, 100), Wrap = rgb(255, 235, 170), Pommel = "Gem", Gem = rgb(140, 220, 255),
			Particles = "Stars", Light = rgb(200, 230, 255), Trail = { rgb(255, 245, 200), rgb(90, 150, 255) },
		},
	},
	{
		Id = "oblivion_katana", Name = "Oblivion Katana", Rarity = "Divine", Mult = 40, RequiredTier = 12, Source = "Tier",
		Look = {
			Blade = rgb(10, 0, 20), BladeMaterial = Enum.Material.ForceField, Edge = rgb(240, 80, 255), EdgeGlow = true,
			Length = 5.0, Width = 0.35, Curve = 0.22, Guard = "Ring", GuardColor = rgb(200, 60, 255),
			Handle = rgb(10, 0, 20), Wrap = rgb(230, 80, 255), Pommel = "Gem", Gem = rgb(255, 120, 255),
			Particles = "Void", Light = rgb(220, 60, 255), Trail = { rgb(255, 150, 255), rgb(40, 0, 80) },
		},
	},

	-- ===== Shop katanas (Coins). ~25% stronger than the tier blade they sit next to. =====
	{
		Id = "oak_fang", Name = "Oak Fang", Rarity = "Uncommon", Mult = 1.25, RequiredTier = 1, Source = "Shop", CostLevel = 7, CostKills = 70,
		Look = {
			Blade = rgb(220, 220, 225), BladeMaterial = Enum.Material.Metal, Edge = rgb(255, 255, 255), EdgeGlow = false,
			Length = 3.6, Width = 0.25, Curve = 0.08, Guard = "Square", GuardColor = rgb(110, 80, 40),
			Handle = rgb(90, 60, 30), Wrap = rgb(40, 30, 20), Pommel = "Tassel", Gem = rgb(200, 60, 40),
			Trail = { rgb(255, 255, 255), rgb(150, 150, 150) },
		},
	},
	{
		Id = "viper_edge", Name = "Viper Edge", Rarity = "Rare", Mult = 1.8, RequiredTier = 2, Source = "Shop", CostLevel = 20, CostKills = 90,
		Look = {
			Blade = rgb(60, 90, 60), BladeMaterial = Enum.Material.Metal, Edge = rgb(180, 255, 80), EdgeGlow = true,
			Length = 3.8, Width = 0.24, Curve = 0.2, Guard = "Spiked", GuardColor = rgb(30, 50, 30),
			Handle = rgb(20, 30, 20), Wrap = rgb(170, 255, 60), Pommel = "Gem", Gem = rgb(170, 255, 60),
			Trail = { rgb(200, 255, 100), rgb(30, 80, 20) },
		},
	},
	{
		Id = "stormcaller", Name = "Stormcaller", Rarity = "Epic", Mult = 2.6, RequiredTier = 3, Source = "Shop", CostLevel = 42, CostKills = 110,
		Look = {
			Blade = rgb(220, 230, 255), BladeMaterial = Enum.Material.Metal, Edge = rgb(120, 170, 255), EdgeGlow = true,
			Length = 4.0, Width = 0.28, Curve = 0.1, Guard = "Wings", GuardColor = rgb(60, 80, 160),
			Handle = rgb(20, 20, 40), Wrap = rgb(120, 170, 255), Pommel = "Gem", Gem = rgb(160, 200, 255),
			Particles = "Sparkle", Trail = { rgb(200, 220, 255), rgb(60, 60, 200) },
		},
	},
	{
		Id = "demonbane", Name = "Demonbane", Rarity = "Epic", Mult = 5.2, RequiredTier = 5, Source = "Shop", CostLevel = 90, CostKills = 130,
		Look = {
			Blade = rgb(235, 235, 240), BladeMaterial = Enum.Material.Metal, Edge = rgb(255, 240, 180), EdgeGlow = true,
			Length = 4.2, Width = 0.3, Curve = 0.12, Guard = "Flower", GuardColor = rgb(200, 30, 40),
			Handle = rgb(30, 10, 10), Wrap = rgb(255, 240, 200), Pommel = "Tassel", Gem = rgb(255, 60, 60),
			Particles = "Radiance", Trail = { rgb(255, 250, 220), rgb(255, 80, 60) },
		},
	},
	{
		Id = "nightglass", Name = "Nightglass", Rarity = "Legendary", Mult = 10, RequiredTier = 7, Source = "Shop", CostLevel = 175, CostKills = 150,
		Look = {
			Blade = rgb(30, 30, 60), BladeMaterial = Enum.Material.Glass, Edge = rgb(120, 255, 220), EdgeGlow = true,
			Length = 4.4, Width = 0.28, Curve = 0.16, Guard = "Ring", GuardColor = rgb(60, 200, 180),
			Handle = rgb(10, 10, 20), Wrap = rgb(120, 255, 220), Pommel = "Gem", Gem = rgb(120, 255, 220),
			Particles = "Stars", Light = rgb(100, 255, 220), Trail = { rgb(160, 255, 230), rgb(20, 40, 80) },
		},
	},
	{
		Id = "ragnablade", Name = "Ragnablade", Rarity = "Mythic", Mult = 19, RequiredTier = 9, Source = "Shop", CostLevel = 300, CostKills = 170,
		Look = {
			Blade = rgb(255, 120, 30), BladeMaterial = Enum.Material.Neon, Edge = rgb(255, 255, 160), EdgeGlow = true,
			Length = 4.6, Width = 0.34, Curve = 0.12, Guard = "Spiked", GuardColor = rgb(40, 20, 10),
			Handle = rgb(30, 10, 0), Wrap = rgb(255, 160, 40), Pommel = "Gem", Gem = rgb(255, 220, 80),
			Particles = "Embers", Light = rgb(255, 140, 40), Trail = { rgb(255, 240, 150), rgb(255, 60, 0) },
		},
	},
	{
		Id = "eventide", Name = "Eventide", Rarity = "Divine", Mult = 36, RequiredTier = 11, Source = "Shop", CostLevel = 470, CostKills = 190,
		Look = {
			Blade = rgb(255, 170, 220), BladeMaterial = Enum.Material.Glass, Edge = rgb(255, 255, 255), EdgeGlow = true,
			Length = 4.8, Width = 0.32, Curve = 0.18, Guard = "Wings", GuardColor = rgb(255, 200, 240),
			Handle = rgb(60, 20, 80), Wrap = rgb(255, 220, 250), Pommel = "Gem", Gem = rgb(255, 170, 240),
			Particles = "Stars", Light = rgb(255, 180, 240), Trail = { rgb(255, 255, 255), rgb(255, 100, 200) },
		},
	},

	-- ===== Nunchucks (Coins, Weapons shop). Weapon = "Nunchaku" swaps in the five-move
	-- acrobatic nunchaku combo (Config/Combo, Combo.Nunchaku). Look for nunchucks:
	-- Stick, StickMaterial, Cap, Wrap, Chain, Glow (neon rings), Length (one stick),
	-- Radius, Particles, Light, Trail. =====
	{
		Id = "training_chucks", Name = "Training Nunchucks", Weapon = "Nunchaku", Rarity = "Uncommon", Mult = 1.15, RequiredTier = 1, Source = "Shop", CostLevel = 5, CostKills = 60,
		Look = {
			Stick = rgb(150, 100, 58), StickMaterial = Enum.Material.Wood, Cap = rgb(200, 205, 215), Wrap = rgb(190, 40, 40), Chain = rgb(170, 175, 185),
			Length = 1.5, Radius = 0.13, Trail = { rgb(255, 255, 255), rgb(150, 120, 90) },
		},
	},
	{
		Id = "iron_dragon_chucks", Name = "Iron Dragon Nunchucks", Weapon = "Nunchaku", Rarity = "Rare", Mult = 1.65, RequiredTier = 2, Source = "Shop", CostLevel = 18, CostKills = 85,
		Look = {
			Stick = rgb(30, 26, 30), StickMaterial = Enum.Material.SmoothPlastic, Cap = rgb(235, 185, 60), Wrap = rgb(200, 30, 40), Chain = rgb(235, 185, 60),
			Length = 1.55, Radius = 0.14, Trail = { rgb(255, 220, 120), rgb(160, 20, 30) },
		},
	},
	{
		Id = "thunder_chucks", Name = "Thunderclap Nunchucks", Weapon = "Nunchaku", Rarity = "Epic", Mult = 2.4, RequiredTier = 3, Source = "Shop", CostLevel = 40, CostKills = 105,
		Look = {
			Stick = rgb(40, 60, 140), StickMaterial = Enum.Material.Metal, Cap = rgb(220, 235, 255), Wrap = rgb(20, 30, 70), Chain = rgb(200, 220, 255),
			Glow = rgb(120, 220, 255), Length = 1.6, Radius = 0.14, Particles = "Lightning", Light = rgb(120, 200, 255),
			Trail = { rgb(220, 245, 255), rgb(40, 90, 255) },
		},
	},
	{
		Id = "inferno_chucks", Name = "Inferno Nunchucks", Weapon = "Nunchaku", Rarity = "Legendary", Mult = 9, RequiredTier = 7, Source = "Shop", CostLevel = 170, CostKills = 145,
		Look = {
			Stick = rgb(50, 20, 12), StickMaterial = Enum.Material.Basalt, Cap = rgb(255, 170, 40), Wrap = rgb(255, 90, 20), Chain = rgb(255, 150, 60),
			Glow = rgb(255, 120, 30), Length = 1.65, Radius = 0.15, Particles = "Embers", Light = rgb(255, 120, 40),
			Trail = { rgb(255, 240, 150), rgb(255, 60, 0) },
		},
	},
	{
		Id = "void_chucks", Name = "Void Reaver Nunchucks", Weapon = "Nunchaku", Rarity = "Mythic", Mult = 18, RequiredTier = 9, Source = "Shop", CostLevel = 290, CostKills = 165,
		Look = {
			Stick = rgb(18, 6, 30), StickMaterial = Enum.Material.Glass, Cap = rgb(230, 90, 255), Wrap = rgb(80, 20, 130), Chain = rgb(200, 120, 255),
			Glow = rgb(230, 80, 255), Length = 1.7, Radius = 0.15, Particles = "Void", Light = rgb(220, 60, 255),
			Trail = { rgb(255, 180, 255), rgb(90, 0, 160) },
		},
	},
	{
		Id = "heavenly_chucks", Name = "Heavenly Dragon Nunchucks", Weapon = "Nunchaku", Rarity = "Divine", Mult = 34, RequiredTier = 11, Source = "Shop", CostLevel = 460, CostKills = 185,
		Look = {
			Stick = rgb(250, 245, 230), StickMaterial = Enum.Material.Marble, Cap = rgb(255, 210, 90), Wrap = rgb(90, 220, 200), Chain = rgb(255, 225, 140),
			Glow = rgb(120, 255, 240), Length = 1.75, Radius = 0.16, Particles = "Stars", Light = rgb(150, 255, 240),
			Trail = { rgb(255, 255, 255), rgb(60, 220, 255) },
		},
	},

	-- ===== Spears (Coins, Weapons shop). Weapon = "Spear" swaps in the six-move spear
	-- combo (Config/Combo, Combo.Spear): long-reach thrusts and spins. Look for spears:
	-- Shaft, ShaftMaterial, Band, Wrap, Head, HeadMaterial, Edge, EdgeGlow, Style ("Yari" |
	-- "Leaf" | "Jumonji" | "Naginata" | "Crescent" | "Celestial"), Length, HeadLength,
	-- HeadWidth, Radius, Tassel, Ribbon, Glow (runes), Gem, Particles, Light, Trail. =====
	{
		Id = "bamboo_yari", Name = "Bamboo Yari", Weapon = "Spear", Rarity = "Uncommon", Mult = 1.2, RequiredTier = 1, Source = "Shop", CostLevel = 6, CostKills = 65,
		Look = {
			Shaft = rgb(196, 172, 104), ShaftMaterial = Enum.Material.Wood, Band = rgb(150, 152, 162), Wrap = rgb(40, 52, 92),
			Head = rgb(212, 218, 228), HeadMaterial = Enum.Material.Metal, Edge = rgb(250, 250, 255), EdgeGlow = false, Style = "Yari",
			Length = 7.0, HeadLength = 1.2, HeadWidth = 0.26, Radius = 0.11, Tassel = rgb(205, 40, 40),
			Trail = { rgb(255, 255, 255), rgb(150, 150, 160) },
		},
	},
	{
		Id = "ironleaf_spear", Name = "Ironleaf Spear", Weapon = "Spear", Rarity = "Rare", Mult = 1.7, RequiredTier = 2, Source = "Shop", CostLevel = 19, CostKills = 88,
		Look = {
			Shaft = rgb(34, 24, 24), ShaftMaterial = Enum.Material.SmoothPlastic, Band = rgb(222, 172, 64), Wrap = rgb(168, 30, 36),
			Head = rgb(198, 204, 214), HeadMaterial = Enum.Material.Metal, Edge = rgb(245, 245, 255), EdgeGlow = false, Style = "Leaf",
			Length = 7.2, HeadLength = 1.35, HeadWidth = 0.34, Radius = 0.12, Tassel = rgb(220, 40, 44), Glow = rgb(255, 196, 90),
			Trail = { rgb(255, 232, 170), rgb(168, 30, 36) },
		},
	},
	{
		Id = "thunder_jumonji", Name = "Thunder Jumonji", Weapon = "Spear", Rarity = "Epic", Mult = 2.5, RequiredTier = 3, Source = "Shop", CostLevel = 41, CostKills = 108,
		Look = {
			Shaft = rgb(30, 46, 112), ShaftMaterial = Enum.Material.Metal, Band = rgb(212, 222, 236), Wrap = rgb(18, 24, 60),
			Head = rgb(226, 236, 255), HeadMaterial = Enum.Material.Metal, Edge = rgb(120, 210, 255), EdgeGlow = true, Style = "Jumonji",
			Length = 7.3, HeadLength = 1.4, HeadWidth = 0.28, Radius = 0.12, Tassel = rgb(236, 242, 255), Glow = rgb(120, 220, 255),
			Particles = "Lightning", Light = rgb(120, 200, 255), Trail = { rgb(220, 245, 255), rgb(40, 90, 255) },
		},
	},
	{
		Id = "phoenix_naginata", Name = "Phoenix Naginata", Weapon = "Spear", Rarity = "Legendary", Mult = 9.5, RequiredTier = 7, Source = "Shop", CostLevel = 172, CostKills = 148,
		Look = {
			Shaft = rgb(140, 22, 16), ShaftMaterial = Enum.Material.SmoothPlastic, Band = rgb(255, 192, 72), Wrap = rgb(40, 10, 6),
			Head = rgb(255, 128, 44), HeadMaterial = Enum.Material.Metal, Edge = rgb(255, 232, 120), EdgeGlow = true, Style = "Naginata",
			Length = 7.5, HeadLength = 2.1, HeadWidth = 0.32, Radius = 0.13, Tassel = rgb(255, 180, 40), Ribbon = rgb(255, 92, 30), Glow = rgb(255, 140, 40),
			Particles = "Embers", Light = rgb(255, 130, 40), Trail = { rgb(255, 240, 150), rgb(255, 60, 0) },
		},
	},
	{
		Id = "abyssal_crescent", Name = "Abyssal Crescent Spear", Weapon = "Spear", Rarity = "Mythic", Mult = 18.5, RequiredTier = 9, Source = "Shop", CostLevel = 295, CostKills = 168,
		Look = {
			Shaft = rgb(22, 8, 36), ShaftMaterial = Enum.Material.Metal, Band = rgb(150, 82, 255), Wrap = rgb(42, 10, 72),
			Head = rgb(44, 20, 74), HeadMaterial = Enum.Material.Metal, Edge = rgb(222, 92, 255), EdgeGlow = true, Style = "Crescent",
			Length = 7.6, HeadLength = 1.6, HeadWidth = 0.3, Radius = 0.13, Tassel = rgb(120, 40, 220), Ribbon = rgb(200, 90, 255), Glow = rgb(205, 80, 255),
			Particles = "Void", Light = rgb(200, 70, 255), Trail = { rgb(255, 180, 255), rgb(80, 0, 160) },
		},
	},
	{
		Id = "celestial_moonpiercer", Name = "Celestial Moonpiercer", Weapon = "Spear", Rarity = "Divine", Mult = 35, RequiredTier = 11, Source = "Shop", CostLevel = 465, CostKills = 188,
		Look = {
			Shaft = rgb(246, 240, 226), ShaftMaterial = Enum.Material.Marble, Band = rgb(255, 214, 110), Wrap = rgb(60, 170, 200),
			Head = rgb(212, 240, 255), HeadMaterial = Enum.Material.Glass, Edge = rgb(255, 250, 210), EdgeGlow = true, Style = "Celestial",
			Length = 7.8, HeadLength = 1.7, HeadWidth = 0.34, Radius = 0.13, Tassel = rgb(255, 255, 255), Ribbon = rgb(120, 230, 255), Glow = rgb(130, 255, 240),
			Gem = rgb(140, 255, 240), Particles = "Stars", Light = rgb(170, 240, 255), Trail = { rgb(255, 255, 255), rgb(70, 200, 255) },
		},
	},

	-- ===== Claws (Coins, Weapons shop). Weapon = "Claws" is dual-wielded: one claw in each
	-- hand (CharacterService welds a mirrored second model, "EquippedOffhand", to the left
	-- hand) with the fast six-move flurry combo (Config/Combo, Combo.Claws). Look for claws:
	-- Style ("Steel": Wolverine-style blades from a knuckle mount | "Katar": blades rising
	-- from a frame with side bars, cross grip and ring bands), Blade, BladeMaterial, Edge,
	-- EdgeGlow, Mount, Accent (stripes / side bars), Frame, Rings, Length, Curve, Width,
	-- Glow (runes), Gem, Particles, Light, Trail. =====
	{
		Id = "iron_claws", Name = "Iron Claws", Weapon = "Claws", Rarity = "Uncommon", Mult = 1.15, RequiredTier = 1, Source = "Shop", CostLevel = 5, CostKills = 62,
		Look = {
			Style = "Steel", Blade = rgb(188, 194, 204), BladeMaterial = Enum.Material.Metal, Edge = rgb(245, 245, 250), EdgeGlow = false,
			Mount = rgb(62, 64, 72), Accent = rgb(140, 144, 152), Length = 1.8, Curve = 0.08, Width = 0.11,
			Trail = { rgb(255, 255, 255), rgb(140, 140, 150) },
		},
	},
	{
		Id = "tiger_claws", Name = "Tiger Fang Claws", Weapon = "Claws", Rarity = "Rare", Mult = 1.65, RequiredTier = 2, Source = "Shop", CostLevel = 18, CostKills = 86,
		Look = {
			Style = "Steel", Blade = rgb(216, 220, 230), BladeMaterial = Enum.Material.Metal, Edge = rgb(255, 244, 210), EdgeGlow = false,
			Mount = rgb(214, 124, 30), Accent = rgb(24, 20, 18), Length = 2.0, Curve = 0.14, Width = 0.12, Glow = rgb(255, 190, 80),
			Trail = { rgb(255, 236, 190), rgb(214, 110, 20) },
		},
	},
	{
		Id = "frostbite_claws", Name = "Frostbite Claws", Weapon = "Claws", Rarity = "Epic", Mult = 2.45, RequiredTier = 3, Source = "Shop", CostLevel = 40, CostKills = 106,
		Look = {
			Style = "Steel", Blade = rgb(196, 232, 255), BladeMaterial = Enum.Material.Ice, Edge = rgb(150, 230, 255), EdgeGlow = true,
			Mount = rgb(40, 70, 122), Accent = rgb(210, 236, 255), Length = 2.1, Curve = 0.1, Width = 0.12, Glow = rgb(150, 230, 255),
			Particles = "Frost", Light = rgb(150, 220, 255), Trail = { rgb(235, 250, 255), rgb(70, 160, 255) },
		},
	},
	{
		Id = "shadowrend_claws", Name = "Shadowrend Claws", Weapon = "Claws", Rarity = "Legendary", Mult = 9.2, RequiredTier = 7, Source = "Shop", CostLevel = 171, CostKills = 146,
		Look = {
			Style = "Steel", Blade = rgb(32, 30, 42), BladeMaterial = Enum.Material.Metal, Edge = rgb(176, 96, 255), EdgeGlow = true,
			Mount = rgb(16, 14, 22), Accent = rgb(120, 60, 200), Length = 2.2, Curve = 0.2, Width = 0.13, Glow = rgb(170, 90, 255),
			Particles = "Shadow", Light = rgb(150, 70, 255), Trail = { rgb(200, 150, 255), rgb(20, 0, 40) },
		},
	},
	{
		Id = "dragonbone_claws", Name = "Dragonbone Claws", Weapon = "Claws", Rarity = "Mythic", Mult = 18.2, RequiredTier = 9, Source = "Shop", CostLevel = 292, CostKills = 166,
		Look = {
			Style = "Steel", Blade = rgb(238, 228, 206), BladeMaterial = Enum.Material.Marble, Edge = rgb(255, 130, 40), EdgeGlow = true,
			Mount = rgb(110, 22, 18), Accent = rgb(255, 180, 60), Length = 2.3, Curve = 0.3, Width = 0.14, Glow = rgb(255, 110, 30), Gem = rgb(255, 150, 40),
			Particles = "Embers", Light = rgb(255, 120, 40), Trail = { rgb(255, 230, 150), rgb(220, 40, 0) },
		},
	},
	{
		-- an ode to Diablo II's Bartuc's Cut-Throat: a katar with three long golden blades
		-- rising from a frame of dark red side bars, a gold cross grip and silver rings
		Id = "bartucs_claws", Name = "Bartuc's Claws", Weapon = "Claws", Rarity = "Divine", Mult = 34.5, RequiredTier = 11, Source = "Shop", CostLevel = 462, CostKills = 186,
		Look = {
			Style = "Katar", Blade = rgb(226, 178, 62), BladeMaterial = Enum.Material.Metal, Edge = rgb(255, 70, 40), EdgeGlow = true,
			Mount = rgb(232, 186, 76), Accent = rgb(112, 22, 20), Frame = rgb(232, 186, 76), Rings = rgb(214, 216, 224),
			Length = 2.5, Curve = 0.22, Width = 0.14, Glow = rgb(255, 36, 24), Gem = rgb(255, 40, 30),
			Particles = "BloodFlame", Light = rgb(255, 50, 30), Trail = { rgb(255, 222, 120), rgb(200, 0, 0) },
		},
	},

	-- ===== Boss drops =====
	{
		Id = "ancestral_blade", Name = "Ancestral Blade", Rarity = "Legendary", Mult = 3.0, RequiredTier = 2, Source = "Boss", DropChance = 0.08,
		Look = {
			Blade = rgb(210, 200, 170), BladeMaterial = Enum.Material.Metal, Edge = rgb(255, 230, 150), EdgeGlow = true,
			Length = 4.3, Width = 0.3, Curve = 0.16, Guard = "Flower", GuardColor = rgb(200, 160, 60),
			Handle = rgb(40, 30, 20), Wrap = rgb(220, 180, 90), Pommel = "Tassel", Gem = rgb(255, 210, 90),
			Particles = "Radiance", Trail = { rgb(255, 240, 180), rgb(160, 120, 40) },
		},
	},
	{
		Id = "hellfang", Name = "Hellfang", Rarity = "Mythic", Mult = 7.5, RequiredTier = 4, Source = "Boss", DropChance = 0.06,
		Look = {
			Blade = rgb(40, 0, 0), BladeMaterial = Enum.Material.CrackedLava, Edge = rgb(255, 60, 0), EdgeGlow = true,
			Length = 4.5, Width = 0.36, Curve = 0.24, Guard = "Spiked", GuardColor = rgb(80, 0, 0),
			Handle = rgb(20, 0, 0), Wrap = rgb(255, 80, 20), Pommel = "Gem", Gem = rgb(255, 60, 0),
			Particles = "Embers", Light = rgb(255, 60, 0), Trail = { rgb(255, 150, 40), rgb(120, 0, 0) },
		},
	},
	{
		Id = "masters_whisper", Name = "Master's Whisper", Rarity = "Mythic", Mult = 16, RequiredTier = 6, Source = "Boss", DropChance = 0.05,
		Look = {
			Blade = rgb(80, 60, 110), BladeMaterial = Enum.Material.Glass, Edge = rgb(200, 150, 255), EdgeGlow = true,
			Length = 4.6, Width = 0.26, Curve = 0.22, Guard = "Crescent", GuardColor = rgb(40, 20, 60),
			Handle = rgb(10, 5, 20), Wrap = rgb(200, 150, 255), Pommel = "Ring", Gem = rgb(200, 150, 255),
			Particles = "Shadow", Light = rgb(160, 100, 255), Trail = { rgb(220, 180, 255), rgb(30, 0, 60) },
		},
	},
	{
		Id = "emperors_end", Name = "Emperor's End", Rarity = "Divine", Mult = 60, RequiredTier = 12, Source = "Boss", DropChance = 0.04,
		Look = {
			Blade = rgb(255, 255, 255), BladeMaterial = Enum.Material.Neon, Edge = rgb(200, 60, 255), EdgeGlow = true,
			Length = 5.2, Width = 0.38, Curve = 0.2, Guard = "Wings", GuardColor = rgb(40, 0, 60),
			Handle = rgb(20, 0, 30), Wrap = rgb(255, 255, 255), Pommel = "Gem", Gem = rgb(255, 100, 255),
			Particles = "Void", Light = rgb(255, 120, 255), Trail = { rgb(255, 255, 255), rgb(120, 0, 200) },
		},
	},
}

-- secret weapons (Seal Shop, Config/Secrets)
for _, k in ipairs({
	{ Id = "secret_soulreaver", Name = "Soulreaver", Mult = 90, Blade = rgb(40, 0, 10), Edge = rgb(255, 40, 60), Particles = "Embers" },
	{ Id = "secret_jade_dragon", Name = "Jade Dragon Fang", Mult = 130, Blade = rgb(20, 120, 80), Edge = rgb(140, 255, 200), Particles = "Sparkle" },
	{ Id = "secret_abyss_edge", Name = "Edge of the Abyss", Mult = 180, Blade = rgb(5, 10, 40), Edge = rgb(90, 170, 255), Particles = "Void" },
}) do
	table.insert(Katanas.List, {
		Id = k.Id, Name = k.Name, Rarity = "Secret", Mult = k.Mult, RequiredTier = 1, Source = "Secret",
		Look = {
			Blade = k.Blade, BladeMaterial = Enum.Material.ForceField, Edge = k.Edge, EdgeGlow = true, Length = 5.2, Width = 0.36, Curve = 0.2,
			Guard = "Ring", GuardColor = k.Edge, Handle = rgb(10, 10, 14), Wrap = k.Edge, Pommel = "Gem", Gem = k.Edge,
			Particles = k.Particles, Light = k.Edge, Trail = { k.Edge, k.Blade },
		},
	})
end

Katanas.ById = {}
for index, katana in ipairs(Katanas.List) do
	katana.Order = index
	Katanas.ById[katana.Id] = katana
end

function Katanas.Get(id: string?)
	return if id then Katanas.ById[id] else nil
end

return Katanas
