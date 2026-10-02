--[[
	Enemy definitions. Levels are assigned per spawn camp in Zones.lua, and
	Health/XP/Coins/Damage are derived from level via Balance, scaled by the *Mod
	fields here. So a "tanky" enemy is just HealthMod > 1.

	Archetype picks the rig built by Visuals/EnemyBuilder:
	  Dummy (static training post), Humanoid, Oni (large humanoid), Beast (quadruped),
	  Golem (bulky stone/magma), Wisp (floating spirit)
	Hat:     None | Kasa | Hood | Kabuto | Horns | Bandana | Crown | Topknot | Halo
	Weapon:  None | Katana | Spear | Club | Dagger | Claws | Staff | Greatsword
	Armor:   nil | "Light" (cuirass + shin guards) | "Full" (adds shoulder guards)
	Menpo:   true adds a samurai face guard (armour needs the Blender enemy pack)
	Demon:   hero demon suit variant (tools/blender/hero_demons.py); when its meshes
	         are imported it replaces the body, hat and armour (a Halo is kept)
]]

local Enemies = {}

local rgb = Color3.fromRGB

local defs = {
	-- ===== Zone 1: Ninja Village =====
	TrainingDummy = {
		Name = "Training Dummy", Archetype = "Dummy", Scale = 1, Static = true,
		HealthMod = 0.6, DamageMod = 0, XPMod = 0.8, CoinMod = 0.8,
		Colors = { Body = rgb(214, 180, 120), Accent = rgb(180, 40, 40), Clothes = rgb(120, 80, 50) },
	},
	RogueNinja = {
		Name = "Rogue Ninja", Archetype = "Humanoid", Scale = 1, Speed = 13,
		HealthMod = 1, DamageMod = 1, XPMod = 1, CoinMod = 1,
		Colors = { Body = rgb(60, 60, 70), Clothes = rgb(40, 40, 48), Accent = rgb(170, 30, 30), Skin = rgb(230, 190, 150), Eyes = rgb(20, 20, 20) },
		Demon = "shadow", Hat = "Hood", Weapon = "Dagger",
	},
	Bandit = {
		Name = "Bandit", Archetype = "Humanoid", Scale = 1.1, Speed = 12,
		HealthMod = 1.3, DamageMod = 1.2, XPMod = 1.2, CoinMod = 1.4,
		Colors = { Body = rgb(150, 110, 70), Clothes = rgb(110, 70, 40), Accent = rgb(200, 60, 40), Skin = rgb(210, 160, 120), Eyes = rgb(20, 20, 20) },
		Demon = "bandit", Hat = "Bandana", Weapon = "Club",
	},

	-- ===== Zone 2: Bamboo Forest =====
	BambooBandit = {
		Name = "Bamboo Bandit", Archetype = "Humanoid", Scale = 1.05, Speed = 13,
		HealthMod = 1, DamageMod = 1, XPMod = 1, CoinMod = 1,
		Colors = { Body = rgb(110, 140, 70), Clothes = rgb(70, 100, 50), Accent = rgb(220, 200, 90), Skin = rgb(220, 180, 140), Eyes = rgb(20, 20, 20) },
		Demon = "bamboo", Hat = "Kasa", Weapon = "Staff",
	},
	ForestFox = {
		Name = "Wild Kitsune", Archetype = "Beast", Scale = 1, Speed = 17,
		HealthMod = 0.85, DamageMod = 0.9, XPMod = 1.05, CoinMod = 1,
		Colors = { Body = rgb(230, 130, 50), Accent = rgb(255, 250, 240), Eyes = rgb(255, 220, 90) },
		Tails = 2,
	},
	MantisWarrior = {
		Name = "Mantis Warrior", Archetype = "Humanoid", Scale = 1.2, Speed = 14,
		HealthMod = 1.3, DamageMod = 1.3, XPMod = 1.3, CoinMod = 1.3,
		Colors = { Body = rgb(120, 200, 80), Clothes = rgb(70, 140, 50), Accent = rgb(250, 240, 90), Skin = rgb(140, 220, 90), Eyes = rgb(255, 60, 60) },
		Demon = "mantis", Hat = "Horns", Weapon = "Claws", GlowEyes = true,
	},

	-- ===== Zone 3: Samurai Village =====
	Ashigaru = {
		Name = "Ashigaru Spearman", Archetype = "Humanoid", Scale = 1.05, Speed = 13,
		HealthMod = 1, DamageMod = 1, XPMod = 1, CoinMod = 1,
		Colors = { Body = rgb(90, 70, 50), Clothes = rgb(160, 40, 40), Accent = rgb(30, 30, 30), Skin = rgb(225, 185, 145), Eyes = rgb(20, 20, 20) },
		Demon = "samurai_red", Hat = "Kasa", Weapon = "Spear", Armor = "Light",
	},
	Samurai = {
		Name = "Samurai", Archetype = "Humanoid", Scale = 1.1, Speed = 13,
		HealthMod = 1.25, DamageMod = 1.15, XPMod = 1.2, CoinMod = 1.2,
		Colors = { Body = rgb(170, 40, 40), Clothes = rgb(40, 30, 30), Accent = rgb(230, 190, 80), Skin = rgb(225, 185, 145), Eyes = rgb(20, 20, 20) },
		Demon = "samurai_red", Hat = "Kabuto", Weapon = "Katana", Armor = "Full",
	},
	EliteSamurai = {
		Name = "Elite Samurai", Archetype = "Humanoid", Scale = 1.25, Speed = 14,
		HealthMod = 1.6, DamageMod = 1.4, XPMod = 1.5, CoinMod = 1.6,
		Colors = { Body = rgb(30, 30, 40), Clothes = rgb(120, 20, 30), Accent = rgb(255, 210, 90), Skin = rgb(225, 185, 145), Eyes = rgb(255, 80, 40) },
		Demon = "samurai_black", Hat = "Kabuto", Weapon = "Greatsword", GlowEyes = true, Armor = "Full", Menpo = true,
	},

	-- ===== Zone 4: Demon Valley =====
	Imp = {
		Name = "Fire Imp", Archetype = "Humanoid", Scale = 0.8, Speed = 16,
		HealthMod = 0.8, DamageMod = 0.9, XPMod = 0.95, CoinMod = 0.95,
		Colors = { Body = rgb(200, 50, 30), Clothes = rgb(90, 20, 10), Accent = rgb(255, 180, 40), Skin = rgb(210, 60, 40), Eyes = rgb(255, 230, 60) },
		Demon = "imp", Hat = "Horns", Weapon = "Claws", GlowEyes = true, Particles = "Embers",
	},
	Demon = {
		Name = "Demon", Archetype = "Oni", Scale = 1.2, Speed = 13,
		HealthMod = 1.2, DamageMod = 1.2, XPMod = 1.15, CoinMod = 1.2,
		Colors = { Body = rgb(150, 30, 40), Clothes = rgb(40, 20, 20), Accent = rgb(240, 230, 200), Skin = rgb(160, 30, 40), Eyes = rgb(255, 220, 60) },
		Demon = "oni_red", Hat = "Horns", Weapon = "Club", GlowEyes = true,
	},
	OniBrute = {
		Name = "Oni Brute", Archetype = "Oni", Scale = 1.55, Speed = 11,
		HealthMod = 1.8, DamageMod = 1.5, XPMod = 1.6, CoinMod = 1.7,
		Colors = { Body = rgb(50, 90, 170), Clothes = rgb(230, 200, 60), Accent = rgb(240, 240, 230), Skin = rgb(50, 90, 170), Eyes = rgb(255, 255, 120) },
		Demon = "oni_blue", Hat = "Horns", Weapon = "Club", GlowEyes = true,
	},

	-- ===== Zone 5: Shadow Forest =====
	ShadowWisp = {
		Name = "Shadow Wisp", Archetype = "Wisp", Scale = 1, Speed = 15,
		HealthMod = 0.8, DamageMod = 1, XPMod = 1, CoinMod = 1,
		Colors = { Body = rgb(60, 20, 110), Accent = rgb(170, 90, 255), Eyes = rgb(230, 200, 255) },
		GlowEyes = true, Particles = "Shadow",
	},
	ShadowBeast = {
		Name = "Shadow Beast", Archetype = "Beast", Scale = 1.5, Speed = 16,
		HealthMod = 1.3, DamageMod = 1.3, XPMod = 1.2, CoinMod = 1.2,
		Colors = { Body = rgb(20, 16, 30), Accent = rgb(140, 70, 255), Eyes = rgb(190, 110, 255) },
		GlowEyes = true, Particles = "Shadow", Tails = 1,
	},
	ShadeAssassin = {
		Name = "Shade Assassin", Archetype = "Humanoid", Scale = 1.1, Speed = 17,
		HealthMod = 1.4, DamageMod = 1.6, XPMod = 1.5, CoinMod = 1.5,
		Colors = { Body = rgb(15, 10, 25), Clothes = rgb(30, 15, 50), Accent = rgb(150, 80, 255), Skin = rgb(40, 30, 60), Eyes = rgb(190, 120, 255) },
		Demon = "shade", Hat = "Hood", Weapon = "Katana", GlowEyes = true, Particles = "Shadow",
	},

	-- ===== Zone 6: Volcanic Fortress =====
	EmberSoldier = {
		Name = "Ember Soldier", Archetype = "Humanoid", Scale = 1.1, Speed = 13,
		HealthMod = 1, DamageMod = 1, XPMod = 1, CoinMod = 1,
		Colors = { Body = rgb(60, 40, 35), Clothes = rgb(200, 70, 20), Accent = rgb(255, 180, 40), Skin = rgb(200, 150, 110), Eyes = rgb(255, 140, 20) },
		Demon = "samurai_ember", Hat = "Kabuto", Weapon = "Spear", GlowEyes = true, Armor = "Light",
	},
	MagmaGolem = {
		Name = "Magma Golem", Archetype = "Golem", Scale = 1.4, Speed = 10,
		HealthMod = 1.8, DamageMod = 1.3, XPMod = 1.4, CoinMod = 1.5,
		Colors = { Body = rgb(50, 40, 40), Accent = rgb(255, 110, 20), Eyes = rgb(255, 200, 60) },
		GlowEyes = true, Particles = "Embers", Material = Enum.Material.Basalt,
	},
	FlameSamurai = {
		Name = "Flame Samurai", Archetype = "Humanoid", Scale = 1.3, Speed = 14,
		HealthMod = 1.5, DamageMod = 1.5, XPMod = 1.5, CoinMod = 1.6,
		Colors = { Body = rgb(40, 20, 20), Clothes = rgb(255, 90, 20), Accent = rgb(255, 220, 90), Skin = rgb(80, 30, 20), Eyes = rgb(255, 230, 90) },
		Demon = "samurai_ember", Hat = "Kabuto", Weapon = "Greatsword", GlowEyes = true, Particles = "Embers", Armor = "Full", Menpo = true,
	},

	-- ===== Zone 7: Sky Temple =====
	CloudMonk = {
		Name = "Cloud Monk", Archetype = "Humanoid", Scale = 1.05, Speed = 15,
		HealthMod = 1, DamageMod = 1, XPMod = 1, CoinMod = 1,
		Colors = { Body = rgb(240, 240, 250), Clothes = rgb(255, 200, 80), Accent = rgb(120, 200, 255), Skin = rgb(235, 200, 170), Eyes = rgb(40, 60, 90) },
		Demon = "tengu", Hat = "Topknot", Weapon = "Staff",
	},
	StormTengu = {
		Name = "Storm Tengu", Archetype = "Humanoid", Scale = 1.2, Speed = 17,
		HealthMod = 1.2, DamageMod = 1.3, XPMod = 1.25, CoinMod = 1.25,
		Colors = { Body = rgb(40, 60, 120), Clothes = rgb(230, 230, 255), Accent = rgb(120, 220, 255), Skin = rgb(200, 40, 40), Eyes = rgb(120, 230, 255) },
		Demon = "tengu", Hat = "Kasa", Weapon = "Katana", GlowEyes = true, Particles = "Sparkle",
	},
	ThunderGuardian = {
		Name = "Thunder Guardian", Archetype = "Golem", Scale = 1.5, Speed = 11,
		HealthMod = 1.9, DamageMod = 1.5, XPMod = 1.6, CoinMod = 1.7,
		Colors = { Body = rgb(230, 225, 210), Accent = rgb(90, 200, 255), Eyes = rgb(140, 230, 255) },
		GlowEyes = true, Particles = "Sparkle", Material = Enum.Material.Marble,
	},

	-- ===== Zone 8: Void Realm =====
	VoidWraith = {
		Name = "Void Wraith", Archetype = "Wisp", Scale = 1.3, Speed = 16,
		HealthMod = 1, DamageMod = 1.1, XPMod = 1, CoinMod = 1,
		Colors = { Body = rgb(20, 0, 40), Accent = rgb(230, 70, 255), Eyes = rgb(255, 160, 255) },
		GlowEyes = true, Particles = "Void",
	},
	VoidKnight = {
		Name = "Void Knight", Archetype = "Humanoid", Scale = 1.35, Speed = 13,
		HealthMod = 1.4, DamageMod = 1.4, XPMod = 1.35, CoinMod = 1.4,
		Colors = { Body = rgb(20, 10, 35), Clothes = rgb(60, 0, 100), Accent = rgb(230, 80, 255), Skin = rgb(30, 10, 50), Eyes = rgb(255, 120, 255) },
		Demon = "void", Hat = "Crown", Weapon = "Greatsword", GlowEyes = true, Particles = "Void", Armor = "Full",
	},
	Voidborn = {
		Name = "Voidborn Horror", Archetype = "Beast", Scale = 1.9, Speed = 15,
		HealthMod = 2, DamageMod = 1.6, XPMod = 1.7, CoinMod = 1.8,
		Colors = { Body = rgb(10, 0, 20), Accent = rgb(255, 60, 220), Eyes = rgb(255, 120, 255) },
		GlowEyes = true, Particles = "Void", Tails = 3,
	},

	-- ===================== BOSSES =====================
	-- Boss attacks: Slam, Shockwave, Barrage, Dash, Summon (see BossService)
	BanditKing = {
		Name = "Bandit King Goro", Archetype = "Oni", Scale = 2.2, Speed = 14, IsBoss = true,
		HealthMod = 30, DamageMod = 2.2, XPMod = 14, CoinMod = 18, Shards = 0,
		Colors = { Body = rgb(150, 110, 70), Clothes = rgb(120, 40, 30), Accent = rgb(255, 210, 80), Skin = rgb(210, 160, 120), Eyes = rgb(255, 230, 120) },
		Demon = "bandit", Hat = "Crown", Weapon = "Club", GlowEyes = true,
		Attacks = { "Slam", "Dash" }, Minion = "Bandit",
	},
	AncientSamurai = {
		Name = "Ancient Samurai", Archetype = "Humanoid", Scale = 2.6, Speed = 14, IsBoss = true,
		HealthMod = 34, DamageMod = 2.4, XPMod = 15, CoinMod = 20, Shards = 1,
		Colors = { Body = rgb(70, 90, 60), Clothes = rgb(40, 50, 35), Accent = rgb(230, 200, 110), Skin = rgb(160, 170, 140), Eyes = rgb(160, 255, 140) },
		Demon = "samurai_jade", Hat = "Kabuto", Weapon = "Greatsword", GlowEyes = true, Particles = "Sparkle", Armor = "Full", Menpo = true,
		Attacks = { "Slam", "Dash", "Shockwave" }, Minion = "BambooBandit", Drop = "ancestral_blade",
	},
	IronShogun = {
		Name = "Iron Shogun Takeru", Archetype = "Humanoid", Scale = 2.8, Speed = 14, IsBoss = true,
		HealthMod = 38, DamageMod = 2.5, XPMod = 16, CoinMod = 22, Shards = 2,
		Colors = { Body = rgb(40, 40, 50), Clothes = rgb(180, 20, 30), Accent = rgb(255, 215, 90), Skin = rgb(225, 185, 145), Eyes = rgb(255, 60, 40) },
		Demon = "samurai_black", Hat = "Kabuto", Weapon = "Greatsword", GlowEyes = true, Armor = "Full", Menpo = true,
		Attacks = { "Slam", "Dash", "Barrage", "Summon" }, Minion = "Samurai",
	},
	DemonLord = {
		Name = "Demon Lord Akuma", Archetype = "Oni", Scale = 3.2, Speed = 13, IsBoss = true,
		HealthMod = 42, DamageMod = 2.6, XPMod = 17, CoinMod = 24, Shards = 3,
		Colors = { Body = rgb(120, 10, 20), Clothes = rgb(20, 10, 10), Accent = rgb(255, 150, 40), Skin = rgb(130, 10, 25), Eyes = rgb(255, 230, 60) },
		Demon = "oni_red", Hat = "Horns", Weapon = "Greatsword", GlowEyes = true, Particles = "Embers",
		Attacks = { "Slam", "Shockwave", "Barrage", "Summon" }, Minion = "Imp", Drop = "hellfang",
	},
	ShadowMaster = {
		Name = "The Shadow Master", Archetype = "Humanoid", Scale = 2.7, Speed = 18, IsBoss = true,
		HealthMod = 46, DamageMod = 2.7, XPMod = 18, CoinMod = 26, Shards = 4,
		Colors = { Body = rgb(10, 6, 20), Clothes = rgb(40, 10, 70), Accent = rgb(170, 90, 255), Skin = rgb(30, 20, 50), Eyes = rgb(200, 130, 255) },
		Demon = "shade", Hat = "Hood", Weapon = "Katana", GlowEyes = true, Particles = "Shadow",
		Attacks = { "Dash", "Barrage", "Shockwave", "Summon" }, Minion = "ShadowWisp", Drop = "masters_whisper",
	},
	MagmaWarlord = {
		Name = "Magma Warlord Kagutsu", Archetype = "Golem", Scale = 3.2, Speed = 12, IsBoss = true,
		HealthMod = 50, DamageMod = 2.8, XPMod = 19, CoinMod = 28, Shards = 5,
		Colors = { Body = rgb(40, 30, 30), Accent = rgb(255, 120, 20), Eyes = rgb(255, 230, 90) },
		GlowEyes = true, Particles = "Embers", Material = Enum.Material.Basalt,
		Attacks = { "Slam", "Shockwave", "Barrage", "Summon" }, Minion = "EmberSoldier",
	},
	StormKami = {
		Name = "Raijin, the Storm Kami", Archetype = "Oni", Scale = 3.1, Speed = 16, IsBoss = true,
		HealthMod = 55, DamageMod = 2.9, XPMod = 20, CoinMod = 30, Shards = 6,
		Colors = { Body = rgb(60, 110, 200), Clothes = rgb(240, 240, 255), Accent = rgb(140, 230, 255), Skin = rgb(60, 110, 200), Eyes = rgb(200, 250, 255) },
		Demon = "oni_blue", Hat = "Halo", Weapon = "Staff", GlowEyes = true, Particles = "Sparkle",
		Attacks = { "Dash", "Barrage", "Shockwave", "Slam" }, Minion = "CloudMonk",
	},
	VoidEmperor = {
		Name = "The Void Emperor", Archetype = "Humanoid", Scale = 3.4, Speed = 15, IsBoss = true,
		HealthMod = 64, DamageMod = 3, XPMod = 22, CoinMod = 34, Shards = 8,
		Colors = { Body = rgb(10, 0, 20), Clothes = rgb(50, 0, 90), Accent = rgb(240, 90, 255), Skin = rgb(20, 0, 40), Eyes = rgb(255, 150, 255) },
		Demon = "void", Hat = "Crown", Weapon = "Greatsword", GlowEyes = true, Particles = "Void", Armor = "Full",
		Attacks = { "Slam", "Shockwave", "Barrage", "Dash", "Summon" }, Minion = "VoidWraith", Drop = "emperors_end",
	},
}

Enemies.ById = {}
for id, def in pairs(defs) do
	def.Id = id
	def.Speed = def.Speed or 14
	def.AttackCooldown = def.AttackCooldown or (if def.IsBoss then 1.2 else 1.6)
	def.AggroRange = def.AggroRange or (if def.IsBoss then 70 else 24)
	Enemies.ById[id] = def
end

function Enemies.Get(id: string)
	return Enemies.ById[id]
end

return Enemies
