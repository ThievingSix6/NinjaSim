--[[
	Hired ninjas (justin, 2026-10-03: "hire ninjas to battle with you, they follow you
	around and can attack and use skills depending on which ninja you hire. Make them
	have their own ragdoll inventories too and they can carry charms which benefit
	them and the player").

	Hire a ninja once (Coins, from a player level) and they are yours for good; one
	fights beside you at a time (data.ActiveHire, picked in the Hire menu).
	CompanionService runs them: they follow you, pick fights near you, attack on their
	own beat and fire their skill on its cooldown. Enemies can turn on them; knocked
	out, they get back up after Respawn seconds.

	Each hire has its own charm grid on its own paper doll (Inventory menu, the arrows
	above the figure). Its charms power the hire, and Charms.HireShare of their stats
	also go to you while that hire is the one fighting (Charms.ApplyToStats).
	Hired ninjas drop combat tokens too (Config/Tokens): Token on TokenChance of their
	hits, and the rarer ones RareToken now and then.

	Per hire:
	  Level, CostKills  unlock level, and the price in kills' worth of Coins at that level
	  Role              shown in the menu
	  Look              EnemyBuilder fields (Hat, Weapon, Armor, Colors, Scale)
	  DamageMult        hit damage x your Damage
	  HealthMult        max health x your max health
	  Interval          seconds between attacks
	  Reach             studs of melee reach (Ranged hires: Range)
	  Crit              crit chance
	  Skill             { Kind, Name, Text, Cooldown, ... } (CompanionService)
]]

local Balance = require(script.Parent.Balance)

local Hires = {}

local rgb = Color3.fromRGB

Hires.Respawn = 20 -- seconds a knocked-out hire stays down
Hires.FollowDistance = 7
Hires.Leash = 90 -- further than this from you and they catch up in a blink
Hires.EngageRange = 30 -- they pick fights this close to you

Hires.List = {
	{
		Id = "genin", Name = "Genin Swordsman", Role = "Melee", Level = 5, CostKills = 60,
		Look = { Hat = "Bandana", Weapon = "Katana", Colors = { Body = rgb(60, 70, 110), Clothes = rgb(40, 46, 80), Accent = rgb(230, 230, 240), Skin = rgb(230, 190, 150), Eyes = rgb(20, 20, 20) } },
		DamageMult = 0.35, HealthMult = 0.9, Interval = 1.0, Reach = 5, Crit = 0.05,
		Skill = { Kind = "Whirlwind", Name = "Whirlwind", Text = "Spins, cutting every enemy around for 2.2x damage", Cooldown = 10, Mult = 2.2, Radius = 12 },
		Token = "Fury", TokenChance = 0.04,
	},
	{
		Id = "shuriken", Name = "Shuriken Adept", Role = "Ranged", Level = 20, CostKills = 70,
		Look = { Hat = "Hood", Weapon = "Dagger", Colors = { Body = rgb(40, 40, 46), Clothes = rgb(30, 30, 36), Accent = rgb(120, 220, 255), Skin = rgb(220, 180, 140), Eyes = rgb(20, 20, 20) } },
		DamageMult = 0.28, HealthMult = 0.7, Interval = 0.9, Range = 24, Crit = 0.1,
		Skill = { Kind = "Fan", Name = "Shuriken Fan", Text = "Throws a shuriken at up to 5 enemies for 1.6x damage each", Cooldown = 9, Mult = 1.6, Targets = 5, Radius = 26 },
		Token = "Focus", TokenChance = 0.04,
	},
	{
		Id = "monk", Name = "Fire Monk", Role = "Caster", Level = 45, CostKills = 80,
		Look = { Hat = "Topknot", Weapon = "Staff", Colors = { Body = rgb(200, 110, 40), Clothes = rgb(170, 70, 30), Accent = rgb(255, 210, 90), Skin = rgb(210, 160, 120), Eyes = rgb(20, 20, 20) } },
		DamageMult = 0.3, HealthMult = 0.85, Interval = 1.1, Reach = 6, Crit = 0.05,
		Skill = { Kind = "Fire", Name = "Flame Pillar", Text = "Calls a pillar of fire on the target: 3x damage to everything near it", Cooldown = 11, Mult = 3, Radius = 11 },
		Token = "Spirit", TokenChance = 0.035,
	},
	{
		Id = "maiden", Name = "Shrine Maiden", Role = "Healer", Level = 70, CostKills = 90,
		Look = { Hat = "Kasa", Weapon = "Staff", Colors = { Body = rgb(245, 245, 250), Clothes = rgb(200, 30, 40), Accent = rgb(255, 230, 120), Skin = rgb(235, 200, 170), Eyes = rgb(20, 20, 20) } },
		DamageMult = 0.2, HealthMult = 0.9, Interval = 1.2, Reach = 6, Crit = 0.05,
		Skill = { Kind = "Heal", Name = "Blessing", Text = "Heals you for 25% of your health (and herself) when you're hurt", Cooldown = 12, Amount = 0.25 },
		Token = "Heal", TokenChance = 0.04,
	},
	{
		Id = "assassin", Name = "Shadow Assassin", Role = "Assassin", Level = 110, CostKills = 100,
		Look = { Hat = "Hood", Weapon = "Dagger", Armor = "Light", Colors = { Body = rgb(30, 20, 40), Clothes = rgb(20, 14, 28), Accent = rgb(170, 80, 255), Skin = rgb(200, 170, 150), Eyes = rgb(200, 120, 255) }, GlowEyes = true },
		DamageMult = 0.4, HealthMult = 0.8, Interval = 0.75, Reach = 5, Crit = 0.25,
		Skill = { Kind = "Shadow", Name = "Shadow Strike", Text = "Blinks behind the target and strikes for 5x damage", Cooldown = 9, Mult = 5 },
		Token = "Haste", TokenChance = 0.045, RareToken = "Storm",
	},
	{
		Id = "samurai", Name = "Iron Samurai", Role = "Guardian", Level = 160, CostKills = 120,
		Look = { Hat = "Kabuto", Weapon = "Greatsword", Armor = "Full", Menpo = true, Scale = 1.15, Colors = { Body = rgb(70, 70, 80), Clothes = rgb(130, 20, 30), Accent = rgb(220, 180, 70), Skin = rgb(210, 170, 130), Eyes = rgb(20, 20, 20) } },
		DamageMult = 0.45, HealthMult = 2.4, Interval = 1.4, Reach = 6.5, Crit = 0.05,
		Skill = { Kind = "Slam", Name = "Iron Roar", Text = "Slams the ground: 2x damage and a 1.5s stun round him, and enemies turn on him", Cooldown = 12, Mult = 2, Radius = 14, Stun = 1.5 },
		Token = "Coins", TokenChance = 0.04, RareToken = "Jackpot",
	},
}

Hires.ById = {}
for i, def in ipairs(Hires.List) do
	def.Order = i
	Hires.ById[def.Id] = def
end

function Hires.Get(id: string?)
	return if id then Hires.ById[id] else nil
end

function Hires.Price(def): number
	return Balance.CoinsForKills(def.Level, def.CostKills)
end

-- A hire's fighting stats from yours and its own charm grid (Charms.Bonus for its grid).
function Hires.Stats(def, playerStats, bonus)
	local b = bonus or {}
	return {
		Damage = math.max(1, math.floor(playerStats.Damage * def.DamageMult * (1 + (b.Damage or 0)))),
		MaxHealth = math.max(10, math.floor(playerStats.MaxHealth * def.HealthMult * (1 + (b.Health or 0)))),
		Crit = math.min(0.8, def.Crit + (b.Crit or 0)),
		CritMult = playerStats.CritMult or 2,
		Interval = def.Interval / (1 + (b.Haste or 0)),
		Speed = (playerStats.WalkSpeed or 20) * (1 + (b.Speed or 0)) + 3,
		LifeSteal = b.LifeSteal or 0,
		Regen = b.Regen or 0,
	}
end

-- The rig def EnemyBuilder builds for a hire.
function Hires.RigDef(def)
	local look = def.Look
	return {
		Id = "hire_" .. def.Id, Name = def.Name, Archetype = "Humanoid", Scale = look.Scale or 1, Speed = 20,
		Colors = look.Colors, Hat = look.Hat, Weapon = look.Weapon, Armor = look.Armor, Menpo = look.Menpo, GlowEyes = look.GlowEyes,
	}
end

return Hires
