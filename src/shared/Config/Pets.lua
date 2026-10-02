--[[
	Companions and eggs.

	Pet.Bonus is additive with other pets: {Damage = 0.1} means +10% damage.
	Shape picks the builder in Visuals/PetBuilder:
	  Blob, Quad (four-legged), Bird, Dragon, Mini (tiny ninja), Dummy, Wisp, Fish, Cat
	Eggs list pets with weights; rarer rarities are boosted by the player's Luck.
	Every hatch also rolls a mutation (Config/Mutations: Big, Golden, Rainbow...).

	To add a pet: add it to Pets.List. To add an egg: add it to Pets.Eggs and point
	a zone's `Egg` field at it (or give it RequiredRebirths for a special egg).
]]

local Balance = require(script.Parent.Balance)
local Mutations = require(script.Parent.Mutations)

local Pets = {}

local rgb = Color3.fromRGB

Pets.List = {
	-- Village
	{ Id = "baby_ninja", Name = "Baby Ninja", Rarity = "Common", Shape = "Mini", Bonus = { Damage = 0.05 }, Colors = { Body = rgb(60, 60, 70), Accent = rgb(220, 60, 60), Eyes = rgb(255, 255, 255) } },
	{ Id = "straw_dummy", Name = "Straw Dummy", Rarity = "Common", Shape = "Dummy", Bonus = { XP = 0.05 }, Colors = { Body = rgb(214, 180, 120), Accent = rgb(180, 40, 40), Eyes = rgb(40, 30, 20) } },
	{ Id = "fox", Name = "Fox", Rarity = "Uncommon", Shape = "Quad", Bonus = { Coins = 0.1, Damage = 0.04 }, Colors = { Body = rgb(235, 130, 50), Accent = rgb(255, 250, 240), Eyes = rgb(30, 20, 10) } },
	{ Id = "mini_samurai", Name = "Mini Samurai", Rarity = "Rare", Shape = "Mini", Bonus = { Damage = 0.18 }, Colors = { Body = rgb(170, 40, 40), Accent = rgb(230, 190, 80), Eyes = rgb(255, 255, 255) } },
	{ Id = "lucky_cat", Name = "Lucky Cat", Rarity = "Epic", Shape = "Cat", Bonus = { Coins = 0.35, Luck = 0.1 }, Colors = { Body = rgb(255, 250, 240), Accent = rgb(255, 200, 60), Eyes = rgb(30, 30, 30) } },
	-- Bamboo
	{ Id = "panda_cub", Name = "Panda Cub", Rarity = "Common", Shape = "Quad", Bonus = { Damage = 0.12 }, Colors = { Body = rgb(245, 245, 245), Accent = rgb(30, 30, 30), Eyes = rgb(20, 20, 20) } },
	{ Id = "bamboo_sprite", Name = "Bamboo Sprite", Rarity = "Uncommon", Shape = "Wisp", Bonus = { XP = 0.18 }, Colors = { Body = rgb(150, 230, 110), Accent = rgb(230, 255, 180), Eyes = rgb(30, 60, 20) } },
	{ Id = "kitsune", Name = "Kitsune", Rarity = "Rare", Shape = "Quad", Bonus = { Damage = 0.3, Luck = 0.05 }, Colors = { Body = rgb(255, 245, 235), Accent = rgb(255, 120, 60), Eyes = rgb(255, 60, 60) }, Tails = 3 },
	{ Id = "jade_dragon", Name = "Jade Dragon", Rarity = "Legendary", Shape = "Dragon", Bonus = { Damage = 0.7, XP = 0.3 }, Colors = { Body = rgb(80, 200, 120), Accent = rgb(230, 255, 200), Eyes = rgb(255, 230, 80) } },
	-- Samurai
	{ Id = "koi", Name = "Koi", Rarity = "Common", Shape = "Fish", Bonus = { Coins = 0.25 }, Colors = { Body = rgb(255, 250, 245), Accent = rgb(255, 90, 40), Eyes = rgb(20, 20, 20) } },
	{ Id = "crane", Name = "Red Crane", Rarity = "Uncommon", Shape = "Bird", Bonus = { XP = 0.3 }, Colors = { Body = rgb(250, 250, 250), Accent = rgb(220, 30, 40), Eyes = rgb(20, 20, 20) } },
	{ Id = "tanuki", Name = "Tanuki", Rarity = "Rare", Shape = "Quad", Bonus = { Damage = 0.5, Coins = 0.2 }, Colors = { Body = rgb(140, 100, 70), Accent = rgb(50, 40, 30), Eyes = rgb(20, 20, 20) } },
	{ Id = "golden_koi", Name = "Golden Koi", Rarity = "Legendary", Shape = "Fish", Bonus = { Coins = 1.2, Luck = 0.15 }, Colors = { Body = rgb(255, 210, 60), Accent = rgb(255, 250, 220), Eyes = rgb(20, 20, 20) }, Glow = true },
	-- Demon
	{ Id = "demon_pup", Name = "Demon Pup", Rarity = "Common", Shape = "Quad", Bonus = { Damage = 0.45 }, Colors = { Body = rgb(150, 30, 40), Accent = rgb(255, 170, 40), Eyes = rgb(255, 230, 60) }, Horns = true },
	{ Id = "imp_buddy", Name = "Imp Buddy", Rarity = "Uncommon", Shape = "Mini", Bonus = { XP = 0.5, Damage = 0.2 }, Colors = { Body = rgb(210, 60, 40), Accent = rgb(255, 180, 40), Eyes = rgb(255, 240, 80) }, Horns = true },
	{ Id = "oni_mask", Name = "Floating Oni Mask", Rarity = "Rare", Shape = "Blob", Bonus = { Damage = 0.9 }, Colors = { Body = rgb(200, 30, 30), Accent = rgb(255, 240, 220), Eyes = rgb(255, 220, 60) }, Horns = true },
	{ Id = "hellhound", Name = "Hellhound", Rarity = "Epic", Shape = "Quad", Bonus = { Damage = 1.5, Coins = 0.4 }, Colors = { Body = rgb(30, 10, 10), Accent = rgb(255, 90, 20), Eyes = rgb(255, 120, 20) }, Horns = true, Particles = "Embers" },
	{ Id = "infernal_drake", Name = "Infernal Drake", Rarity = "Legendary", Shape = "Dragon", Bonus = { Damage = 2.6, XP = 0.8 }, Colors = { Body = rgb(170, 20, 20), Accent = rgb(255, 160, 40), Eyes = rgb(255, 240, 80) }, Particles = "Embers" },
	-- Shadow
	{ Id = "shadow_bat", Name = "Shadow Bat", Rarity = "Common", Shape = "Bird", Bonus = { Damage = 1.0 }, Colors = { Body = rgb(30, 20, 45), Accent = rgb(150, 80, 255), Eyes = rgb(200, 140, 255) } },
	{ Id = "shadow_wolf", Name = "Shadow Wolf", Rarity = "Uncommon", Shape = "Quad", Bonus = { Damage = 1.5, XP = 0.4 }, Colors = { Body = rgb(25, 20, 40), Accent = rgb(140, 70, 255), Eyes = rgb(190, 120, 255) }, Particles = "Shadow" },
	{ Id = "wraith", Name = "Wraith", Rarity = "Rare", Shape = "Wisp", Bonus = { XP = 2.0 }, Colors = { Body = rgb(60, 30, 100), Accent = rgb(200, 150, 255), Eyes = rgb(255, 255, 255) }, Particles = "Shadow" },
	{ Id = "night_kitsune", Name = "Night Kitsune", Rarity = "Epic", Shape = "Quad", Bonus = { Damage = 3.0, Luck = 0.2 }, Colors = { Body = rgb(30, 20, 60), Accent = rgb(180, 110, 255), Eyes = rgb(220, 170, 255) }, Tails = 5, Particles = "Shadow" },
	{ Id = "umbral_dragon", Name = "Umbral Dragon", Rarity = "Mythic", Shape = "Dragon", Bonus = { Damage = 6, XP = 2, Coins = 2 }, Colors = { Body = rgb(20, 10, 40), Accent = rgb(170, 90, 255), Eyes = rgb(230, 190, 255) }, Particles = "Shadow" },
	-- Volcanic
	{ Id = "ember_slime", Name = "Ember Slime", Rarity = "Common", Shape = "Blob", Bonus = { Damage = 2.2 }, Colors = { Body = rgb(255, 110, 30), Accent = rgb(255, 220, 90), Eyes = rgb(40, 10, 0) }, Particles = "Embers" },
	{ Id = "salamander", Name = "Salamander", Rarity = "Uncommon", Shape = "Quad", Bonus = { Damage = 3, Coins = 1 }, Colors = { Body = rgb(230, 70, 20), Accent = rgb(40, 20, 20), Eyes = rgb(255, 230, 60) } },
	{ Id = "golem_jr", Name = "Golem Jr.", Rarity = "Rare", Shape = "Mini", Bonus = { Damage = 5 }, Colors = { Body = rgb(60, 50, 50), Accent = rgb(255, 120, 20), Eyes = rgb(255, 220, 60) } },
	{ Id = "phoenix", Name = "Phoenix", Rarity = "Legendary", Shape = "Bird", Bonus = { Damage = 9, XP = 3 }, Colors = { Body = rgb(255, 120, 20), Accent = rgb(255, 230, 80), Eyes = rgb(255, 255, 255) }, Particles = "Embers", Glow = true },
	{ Id = "inferno_dragon", Name = "Inferno Dragon", Rarity = "Mythic", Shape = "Dragon", Bonus = { Damage = 15, Coins = 5 }, Colors = { Body = rgb(255, 70, 10), Accent = rgb(40, 10, 0), Eyes = rgb(255, 255, 120) }, Particles = "Embers", Glow = true },
	-- Sky
	{ Id = "cloud_pup", Name = "Cloud Pup", Rarity = "Common", Shape = "Blob", Bonus = { Damage = 5 }, Colors = { Body = rgb(245, 250, 255), Accent = rgb(150, 210, 255), Eyes = rgb(40, 60, 100) } },
	{ Id = "thunderbird", Name = "Thunderbird", Rarity = "Uncommon", Shape = "Bird", Bonus = { Damage = 7, XP = 2 }, Colors = { Body = rgb(60, 90, 180), Accent = rgb(255, 230, 80), Eyes = rgb(200, 250, 255) }, Particles = "Sparkle" },
	{ Id = "sky_serpent", Name = "Sky Serpent", Rarity = "Rare", Shape = "Dragon", Bonus = { Damage = 11, Luck = 0.25 }, Colors = { Body = rgb(120, 200, 255), Accent = rgb(255, 255, 255), Eyes = rgb(255, 220, 80) } },
	{ Id = "celestial_fox", Name = "Celestial Fox", Rarity = "Epic", Shape = "Quad", Bonus = { Damage = 16, XP = 6 }, Colors = { Body = rgb(255, 250, 230), Accent = rgb(255, 210, 100), Eyes = rgb(120, 200, 255) }, Tails = 7, Particles = "Stars", Glow = true },
	{ Id = "qilin", Name = "Qilin", Rarity = "Mythic", Shape = "Dragon", Bonus = { Damage = 30, Coins = 10, Luck = 0.3 }, Colors = { Body = rgb(255, 220, 110), Accent = rgb(90, 200, 160), Eyes = rgb(255, 255, 255) }, Particles = "Stars", Glow = true },
	-- Void
	{ Id = "void_wisp", Name = "Void Wisp", Rarity = "Common", Shape = "Wisp", Bonus = { Damage = 12 }, Colors = { Body = rgb(40, 0, 70), Accent = rgb(230, 80, 255), Eyes = rgb(255, 200, 255) }, Particles = "Void" },
	{ Id = "void_spirit", Name = "Void Spirit", Rarity = "Uncommon", Shape = "Wisp", Bonus = { Damage = 17, XP = 6 }, Colors = { Body = rgb(90, 20, 140), Accent = rgb(255, 150, 255), Eyes = rgb(255, 255, 255) }, Particles = "Void" },
	{ Id = "rift_walker", Name = "Rift Walker", Rarity = "Rare", Shape = "Mini", Bonus = { Damage = 26 }, Colors = { Body = rgb(20, 0, 30), Accent = rgb(230, 80, 255), Eyes = rgb(255, 150, 255) }, Particles = "Void" },
	{ Id = "void_dragon", Name = "Void Dragon", Rarity = "Legendary", Shape = "Dragon", Bonus = { Damage = 45, XP = 15 }, Colors = { Body = rgb(15, 0, 30), Accent = rgb(230, 80, 255), Eyes = rgb(255, 180, 255) }, Particles = "Void", Glow = true },
	{ Id = "void_sovereign", Name = "Void Sovereign", Rarity = "Divine", Shape = "Wisp", Bonus = { Damage = 90, XP = 30, Coins = 30, Luck = 0.5 }, Colors = { Body = rgb(0, 0, 0), Accent = rgb(255, 120, 255), Eyes = rgb(255, 255, 255) }, Particles = "Void", Glow = true },
	-- Spirit egg (Shards)
	{ Id = "spirit_owl", Name = "Spirit Owl", Rarity = "Rare", Shape = "Bird", Bonus = { XP = 0.5, Luck = 0.1 }, Colors = { Body = rgb(170, 240, 255), Accent = rgb(255, 255, 255), Eyes = rgb(60, 200, 255) }, Particles = "Sparkle", Glow = true },
	{ Id = "spirit_stag", Name = "Spirit Stag", Rarity = "Epic", Shape = "Quad", Bonus = { XP = 1.0, Coins = 1.0 }, Colors = { Body = rgb(150, 255, 230), Accent = rgb(255, 255, 255), Eyes = rgb(40, 150, 140) }, Particles = "Sparkle", Glow = true, Horns = true },
	{ Id = "guardian_spirit", Name = "Guardian Spirit", Rarity = "Legendary", Shape = "Wisp", Bonus = { XP = 2, Coins = 2, Luck = 0.3 }, Colors = { Body = rgb(120, 255, 240), Accent = rgb(255, 255, 255), Eyes = rgb(255, 255, 255) }, Particles = "Stars", Glow = true },
	{ Id = "ascended_kirin", Name = "Ascended Kirin", Rarity = "Mythic", Shape = "Dragon", Bonus = { XP = 5, Coins = 5, Luck = 0.5 }, Colors = { Body = rgb(240, 255, 255), Accent = rgb(120, 255, 240), Eyes = rgb(255, 255, 255) }, Particles = "Stars", Glow = true },
	-- Secret pets: one per egg, from 1 in 100,000 to 1 in 1,000,000,000 (see the egg weights)
	{ Id = "shogun_cat", Name = "Golden Shogun Cat", Rarity = "Secret", Shape = "Cat", Bonus = { Coins = 3, Luck = 0.6, Damage = 1 }, Colors = { Body = rgb(255, 205, 60), Accent = rgb(190, 20, 40), Eyes = rgb(255, 255, 255) }, Particles = "Radiance", Glow = true },
	{ Id = "panda_emperor", Name = "Panda Emperor", Rarity = "Secret", Shape = "Quad", Bonus = { Damage = 3, XP = 1.5, Luck = 0.6 }, Colors = { Body = rgb(255, 250, 235), Accent = rgb(255, 200, 40), Eyes = rgb(40, 255, 140) }, Horns = true, Particles = "Petals", Glow = true },
	{ Id = "rainbow_koi", Name = "Rainbow Koi King", Rarity = "Secret", Shape = "Fish", Bonus = { Coins = 8, Luck = 0.7, Damage = 2 }, Colors = { Body = rgb(255, 120, 220), Accent = rgb(120, 255, 240), Eyes = rgb(255, 255, 255) }, Particles = "Galaxy", Glow = true },
	{ Id = "oni_overlord", Name = "Oni Overlord", Rarity = "Secret", Shape = "Blob", Bonus = { Damage = 12, XP = 4, Luck = 0.8 }, Colors = { Body = rgb(255, 40, 60), Accent = rgb(20, 0, 0), Eyes = rgb(255, 255, 120) }, Horns = true, Particles = "BloodFlame", Glow = true },
	{ Id = "eclipse_dragon", Name = "Eclipse Dragon", Rarity = "Secret", Shape = "Dragon", Bonus = { Damage = 25, XP = 8, Coins = 8, Luck = 0.9 }, Colors = { Body = rgb(10, 0, 20), Accent = rgb(255, 210, 90), Eyes = rgb(255, 255, 255) }, Particles = "Shadow", Glow = true },
	{ Id = "sunfire_phoenix", Name = "Sunfire Phoenix", Rarity = "Secret", Shape = "Bird", Bonus = { Damage = 60, XP = 15, Luck = 1 }, Colors = { Body = rgb(255, 245, 200), Accent = rgb(255, 120, 20), Eyes = rgb(255, 255, 255) }, Particles = "Radiance", Glow = true },
	{ Id = "storm_emperor", Name = "Storm Emperor", Rarity = "Secret", Shape = "Dragon", Bonus = { Damage = 120, Coins = 40, Luck = 1.2 }, Colors = { Body = rgb(40, 60, 160), Accent = rgb(200, 245, 255), Eyes = rgb(255, 255, 140) }, Particles = "Lightning", Glow = true },
	{ Id = "omega_titan", Name = "Omega Void Titan", Rarity = "Secret", Shape = "Dragon", Bonus = { Damage = 400, XP = 120, Coins = 120, Luck = 2 }, Colors = { Body = rgb(0, 0, 0), Accent = rgb(255, 255, 255), Eyes = rgb(255, 80, 255) }, Particles = "Galaxy", Glow = true },
	{ Id = "spirit_king", Name = "Ancestral Spirit King", Rarity = "Secret", Shape = "Wisp", Bonus = { XP = 20, Coins = 20, Luck = 1.5 }, Colors = { Body = rgb(255, 255, 255), Accent = rgb(255, 220, 120), Eyes = rgb(120, 255, 240) }, Particles = "Spirit", Glow = true },
}

Pets.ById = {}
for index, pet in ipairs(Pets.List) do
	pet.Order = index
	Pets.ById[pet.Id] = pet
end

Pets.Eggs = {
	{
		Id = "village_egg", Name = "Village Egg", Zone = "village", Currency = "Coins", CostLevel = 3, CostKills = 12,
		Color = Color3.fromRGB(230, 200, 150), Accent = Color3.fromRGB(150, 100, 60),
		Pets = { { "baby_ninja", 45 }, { "straw_dummy", 32 }, { "fox", 17 }, { "mini_samurai", 5.5 }, { "lucky_cat", 0.5 }, { "shogun_cat", 0.001 } },
	},
	{
		Id = "bamboo_egg", Name = "Bamboo Egg", Zone = "bamboo", Currency = "Coins", CostLevel = 13, CostKills = 18,
		Color = Color3.fromRGB(140, 220, 110), Accent = Color3.fromRGB(60, 120, 50),
		Pets = { { "panda_cub", 50 }, { "bamboo_sprite", 33 }, { "kitsune", 15 }, { "jade_dragon", 2 }, { "panda_emperor", 0.0004 } },
	},
	{
		Id = "samurai_egg", Name = "Samurai Egg", Zone = "samurai", Currency = "Coins", CostLevel = 30, CostKills = 20,
		Color = Color3.fromRGB(230, 60, 60), Accent = Color3.fromRGB(255, 210, 90),
		Pets = { { "koi", 50 }, { "crane", 33 }, { "tanuki", 15 }, { "golden_koi", 2 }, { "rainbow_koi", 0.0002 } },
	},
	{
		Id = "demon_egg", Name = "Demon Egg", Zone = "demon", Currency = "Coins", CostLevel = 56, CostKills = 22,
		Color = Color3.fromRGB(120, 20, 20), Accent = Color3.fromRGB(255, 140, 30),
		Pets = { { "demon_pup", 45 }, { "imp_buddy", 32 }, { "oni_mask", 17 }, { "hellhound", 5 }, { "infernal_drake", 1 }, { "oni_overlord", 0.0001 } },
	},
	{
		Id = "shadow_egg", Name = "Shadow Egg", Zone = "shadow", Currency = "Coins", CostLevel = 98, CostKills = 24,
		Color = Color3.fromRGB(40, 20, 70), Accent = Color3.fromRGB(170, 90, 255),
		Pets = { { "shadow_bat", 45 }, { "shadow_wolf", 32 }, { "wraith", 17 }, { "night_kitsune", 5.7 }, { "umbral_dragon", 0.3 }, { "eclipse_dragon", 2e-5 } },
	},
	{
		Id = "magma_egg", Name = "Magma Egg", Zone = "volcanic", Currency = "Coins", CostLevel = 160, CostKills = 26,
		Color = Color3.fromRGB(60, 40, 40), Accent = Color3.fromRGB(255, 110, 20),
		Pets = { { "ember_slime", 45 }, { "salamander", 32 }, { "golem_jr", 18 }, { "phoenix", 4.7 }, { "inferno_dragon", 0.3 }, { "sunfire_phoenix", 4e-6 } },
	},
	{
		Id = "sky_egg", Name = "Sky Egg", Zone = "sky", Currency = "Coins", CostLevel = 255, CostKills = 28,
		Color = Color3.fromRGB(240, 248, 255), Accent = Color3.fromRGB(255, 210, 90),
		Pets = { { "cloud_pup", 45 }, { "thunderbird", 32 }, { "sky_serpent", 17 }, { "celestial_fox", 5.75 }, { "qilin", 0.25 }, { "storm_emperor", 1e-6 } },
	},
	{
		Id = "void_egg", Name = "Void Egg", Zone = "void", Currency = "Coins", CostLevel = 380, CostKills = 30,
		Color = Color3.fromRGB(20, 0, 30), Accent = Color3.fromRGB(230, 80, 255),
		Pets = { { "void_wisp", 45 }, { "void_spirit", 32 }, { "rift_walker", 17 }, { "void_dragon", 5.9 }, { "void_sovereign", 0.1 }, { "omega_titan", 1e-7 } },
	},
	{
		Id = "spirit_egg", Name = "Spirit Egg", Zone = "village", Currency = "Shards", Cost = 4, RequiredRebirths = 2, Offset = Vector2.new(-105, 38),
		Color = Color3.fromRGB(150, 255, 240), Accent = Color3.fromRGB(255, 255, 255),
		Pets = { { "spirit_owl", 60 }, { "spirit_stag", 30 }, { "guardian_spirit", 9 }, { "ascended_kirin", 1 }, { "spirit_king", 1e-5 } },
	},
}

Pets.EggsById = {}
for index, egg in ipairs(Pets.Eggs) do
	egg.Order = index
	if not egg.Cost then
		egg.Cost = Balance.CoinsForKills(egg.CostLevel, egg.CostKills)
	end
	Pets.EggsById[egg.Id] = egg
end

-- World position of an egg's stand (next to its zone's spawn unless it sets Offset).
function Pets.EggPosition(egg): Vector3
	local Zones = require(script.Parent.Zones)
	local zone = Zones.Get(egg.Zone)
	return Zones.WorldPosition(zone, egg.Offset or zone.EggOffset)
end

Pets.BaseSlots = 3
Pets.BaseStorage = 60
Pets.StatKeys = { "Damage", "XP", "Coins", "Luck" }

-- Weighted roll. Luck boosts every rarity above Common a little more per rarity step.
function Pets.Roll(egg, luck: number, rng: Random?)
	local Rarity = require(script.Parent.Rarity)
	local random = rng or Random.new()
	local total = 0
	local weights = {}
	for i, entry in ipairs(egg.Pets) do
		local pet = Pets.ById[entry[1]]
		local step = Rarity.Index(pet.Rarity) - 1
		local w = entry[2] * (1 + luck * step * 0.5)
		weights[i] = w
		total += w
	end
	local roll = random:NextNumber() * total
	for i, entry in ipairs(egg.Pets) do
		roll -= weights[i]
		if roll <= 0 then
			return Pets.ById[entry[1]]
		end
	end
	return Pets.ById[egg.Pets[#egg.Pets][1]]
end

-- Display chances (percent) for the egg preview, with luck applied.
function Pets.Chances(egg, luck: number)
	local Rarity = require(script.Parent.Rarity)
	local total = 0
	local weights = {}
	for i, entry in ipairs(egg.Pets) do
		local pet = Pets.ById[entry[1]]
		weights[i] = entry[2] * (1 + luck * (Rarity.Index(pet.Rarity) - 1) * 0.5)
		total += weights[i]
	end
	local out = {}
	for i, entry in ipairs(egg.Pets) do
		out[i] = { Pet = Pets.ById[entry[1]], Chance = weights[i] / total * 100 }
	end
	return out
end

-- How rare a pet is from its egg: 1 in N (N rounded), with `luck` applied (0 for
-- the pet's base odds). nil for pets no egg drops.
function Pets.OneIn(petId: string, luck: number?): number?
	for _, egg in ipairs(Pets.Eggs) do
		for _, entry in ipairs(Pets.Chances(egg, luck or 0)) do
			if entry.Pet.Id == petId and entry.Chance > 0 then
				return math.max(1, math.floor(100 / entry.Chance + 0.5))
			end
		end
	end
	return nil
end

-- A single number used for sorting / "equip best" (the mutation multiplier counts).
function Pets.Score(pet, mutation: string?): number
	local b = pet.Bonus
	return ((b.Damage or 0) * 1.2 + (b.XP or 0) + (b.Coins or 0) * 0.8 + (b.Luck or 0) * 3) * Mutations.Mult(mutation)
end

-- ===== mutations (Config/Mutations) =====
Pets.Mutations = Mutations

-- "Golden Panda Cub" for a mutated pet, the plain name otherwise.
function Pets.DisplayName(pet, mutation: string?): string
	local m = Mutations.Get(mutation)
	return if m then m.Name .. " " .. pet.Name else pet.Name
end

-- The pet's bonus with its mutation multiplier applied.
function Pets.BonusOf(pet, mutation: string?): { [string]: number }
	local mult = Mutations.Mult(mutation)
	if mult == 1 then
		return pet.Bonus
	end
	local out = {}
	for stat, value in pairs(pet.Bonus) do
		out[stat] = value * mult
	end
	return out
end

-- How rare this exact pet + mutation is: 1 in (pet odds x mutation odds).
function Pets.MutatedOneIn(petId: string, mutation: string?, luck: number?): number?
	local base = Pets.OneIn(petId, luck)
	local m = Mutations.Get(mutation)
	if not base or not m then
		return base
	end
	return math.floor(base / Mutations.ChanceOf(m.Id, luck) + 0.5)
end

return Pets
