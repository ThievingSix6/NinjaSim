--[[
	Ninja tiers. A tier is unlocked automatically when the player reaches its level.
	Each tier boosts power, max health and move speed, re-dresses the character
	and grants its matching katana (see Config/Katanas).

	To add a tier: append an entry, give it a Katana id that exists in Katanas.lua,
	and pick a Level above the previous tier. Everything else (UI, unlock flow,
	character visuals) reads from this table.

	Outfit.Features toggles extra outfit pieces built by Visuals/OutfitBuilder:
	  Scarf, Armor (shoulder plates), Emblem (chest crest), GlowLines (neon seams),
	  Halo, Horns, Cape, Orbit (floating orbs)
	Outfit.Aura is a ParticleEmitter preset name from OutfitBuilder.AuraPresets.
]]

local Tiers = {}

local rgb = Color3.fromRGB

Tiers.List = {
	{
		Id = "brown", Name = "Brown Ninja", Level = 1, Power = 1.0, HealthMult = 1.0, SpeedBonus = 0,
		Katana = "brown_katana", Color = rgb(150, 100, 60),
		Outfit = {
			Primary = rgb(112, 74, 46), Secondary = rgb(74, 48, 30), Trim = rgb(196, 150, 96),
			Material = Enum.Material.Fabric, EyeColor = rgb(30, 20, 15), EyeGlow = false,
			Features = {},
		},
	},
	{
		Id = "green", Name = "Green Ninja", Level = 10, Power = 1.5, HealthMult = 1.3, SpeedBonus = 1,
		Katana = "jade_katana", Color = rgb(80, 200, 90),
		Outfit = {
			Primary = rgb(46, 122, 58), Secondary = rgb(26, 70, 34), Trim = rgb(160, 235, 110),
			Material = Enum.Material.Fabric, EyeColor = rgb(20, 40, 20), EyeGlow = false,
			Features = { Emblem = true },
		},
	},
	{
		Id = "blue", Name = "Blue Ninja", Level = 25, Power = 2.2, HealthMult = 1.7, SpeedBonus = 2,
		Katana = "tide_katana", Color = rgb(70, 150, 255),
		Outfit = {
			Primary = rgb(34, 78, 170), Secondary = rgb(18, 38, 92), Trim = rgb(110, 220, 255),
			Material = Enum.Material.Fabric, EyeColor = rgb(120, 220, 255), EyeGlow = true,
			Features = { Emblem = true, Scarf = true },
			Aura = "Droplets",
		},
	},
	{
		Id = "purple", Name = "Purple Ninja", Level = 50, Power = 3.2, HealthMult = 2.3, SpeedBonus = 3,
		Katana = "amethyst_katana", Color = rgb(170, 90, 255),
		Outfit = {
			Primary = rgb(92, 44, 150), Secondary = rgb(46, 20, 80), Trim = rgb(214, 160, 255),
			Material = Enum.Material.Fabric, EyeColor = rgb(220, 150, 255), EyeGlow = true,
			Features = { Emblem = true, Scarf = true },
			Aura = "Sparkle",
		},
	},
	{
		Id = "red", Name = "Red Ninja", Level = 75, Power = 4.6, HealthMult = 3.1, SpeedBonus = 4,
		Katana = "ember_katana", Color = rgb(255, 70, 60),
		Outfit = {
			Primary = rgb(170, 30, 30), Secondary = rgb(70, 12, 12), Trim = rgb(255, 196, 70),
			Material = Enum.Material.Fabric, EyeColor = rgb(255, 170, 60), EyeGlow = true,
			Features = { Emblem = true, Scarf = true, Armor = true },
			Aura = "Embers",
		},
	},
	{
		Id = "black", Name = "Black Ninja", Level = 100, Power = 6.5, HealthMult = 4.2, SpeedBonus = 5,
		Katana = "obsidian_katana", Color = rgb(70, 70, 80),
		Outfit = {
			Primary = rgb(22, 22, 26), Secondary = rgb(10, 10, 12), Trim = rgb(200, 205, 215),
			Material = Enum.Material.Fabric, EyeColor = rgb(255, 40, 40), EyeGlow = true,
			Features = { Emblem = true, Scarf = true, Armor = true, GlowLines = true },
			Aura = "Smoke",
		},
	},
	{
		Id = "white", Name = "White Ninja", Level = 140, Power = 9, HealthMult = 5.6, SpeedBonus = 6,
		Katana = "frostmoon_katana", Color = rgb(235, 245, 255),
		Outfit = {
			Primary = rgb(236, 240, 246), Secondary = rgb(170, 190, 215), Trim = rgb(120, 210, 255),
			Material = Enum.Material.SmoothPlastic, EyeColor = rgb(120, 220, 255), EyeGlow = true,
			Features = { Emblem = true, Scarf = true, Armor = true, GlowLines = true, Cape = true },
			Aura = "Frost",
		},
	},
	{
		Id = "gold", Name = "Gold Ninja", Level = 190, Power = 12.5, HealthMult = 7.4, SpeedBonus = 7,
		Katana = "sunforged_katana", Color = rgb(255, 200, 50),
		Outfit = {
			Primary = rgb(230, 175, 40), Secondary = rgb(130, 90, 20), Trim = rgb(255, 250, 220),
			Material = Enum.Material.Foil, EyeColor = rgb(255, 255, 200), EyeGlow = true,
			Features = { Emblem = true, Scarf = true, Armor = true, GlowLines = true, Cape = true },
			Aura = "Radiance",
		},
	},
	{
		Id = "crimson", Name = "Crimson Ninja", Level = 250, Power = 17, HealthMult = 9.8, SpeedBonus = 8,
		Katana = "bloodmoon_katana", Color = rgb(220, 20, 60),
		Outfit = {
			Primary = rgb(120, 8, 30), Secondary = rgb(30, 4, 10), Trim = rgb(255, 60, 90),
			Material = Enum.Material.Fabric, EyeColor = rgb(255, 30, 70), EyeGlow = true,
			Features = { Emblem = true, Scarf = true, Armor = true, GlowLines = true, Cape = true, Horns = true },
			Aura = "BloodFlame",
		},
	},
	{
		Id = "shadow", Name = "Shadow Ninja", Level = 325, Power = 23, HealthMult = 13, SpeedBonus = 9,
		Katana = "umbra_katana", Color = rgb(130, 80, 220),
		Outfit = {
			Primary = rgb(16, 12, 26), Secondary = rgb(6, 4, 10), Trim = rgb(140, 70, 255),
			Material = Enum.Material.Fabric, EyeColor = rgb(170, 100, 255), EyeGlow = true,
			Features = { Emblem = true, Scarf = true, Armor = true, GlowLines = true, Cape = true, Orbit = true },
			Aura = "Shadow",
		},
	},
	{
		Id = "celestial", Name = "Celestial Ninja", Level = 420, Power = 31, HealthMult = 17, SpeedBonus = 10,
		Katana = "starfall_katana", Color = rgb(140, 210, 255),
		Outfit = {
			Primary = rgb(28, 40, 96), Secondary = rgb(240, 236, 220), Trim = rgb(255, 214, 110),
			Material = Enum.Material.SmoothPlastic, EyeColor = rgb(255, 240, 180), EyeGlow = true,
			Features = { Emblem = true, Scarf = true, Armor = true, GlowLines = true, Cape = true, Halo = true, Orbit = true },
			Aura = "Stars",
		},
	},
	{
		Id = "void", Name = "Void Ninja", Level = 550, Power = 42, HealthMult = 23, SpeedBonus = 12,
		Katana = "oblivion_katana", Color = rgb(200, 60, 255),
		Outfit = {
			Primary = rgb(8, 4, 16), Secondary = rgb(40, 0, 70), Trim = rgb(230, 70, 255),
			Material = Enum.Material.Glass, EyeColor = rgb(255, 120, 255), EyeGlow = true,
			Features = { Emblem = true, Scarf = true, Armor = true, GlowLines = true, Cape = true, Horns = true, Halo = true, Orbit = true },
			Aura = "Void",
		},
	},
}

Tiers.ById = {}
for index, tier in ipairs(Tiers.List) do
	tier.Index = index
	Tiers.ById[tier.Id] = tier
end

function Tiers.Get(index: number)
	return Tiers.List[math.clamp(index, 1, #Tiers.List)]
end

-- Highest tier whose level requirement is met.
function Tiers.ForLevel(level: number)
	local result = Tiers.List[1]
	for _, tier in ipairs(Tiers.List) do
		if level >= tier.Level then
			result = tier
		else
			break
		end
	end
	return result
end

function Tiers.Next(index: number)
	return Tiers.List[index + 1]
end

return Tiers
