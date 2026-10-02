--[[
	Pet mutations (in the spirit of Grow a Garden). Every hatch rolls once; a
	mutated pet keeps its mutation for good (saved as Pets[uid].Mutation, old
	pets have none). A mutation multiplies every stat in the pet's Bonus and
	changes how it looks everywhere (follow pet, viewports, hatch reveal).

	  Chance  base chance per hatch (1 / OneIn). Luck raises every chance a
	          little: x(1 + Luck * LuckPerPoint), capped at MaxLuckMult.
	  Mult    multiplier on the pet's bonus (Damage, XP, Coins, Luck)
	  Scale   model size (1 = normal)
	  Look    which visual MutationLook applies (see Visuals/MutationLook)
	  Shout   announce the hatch to the whole server

	  HatMult multiplier on a hat's stats when a hat carries the mutation (hats only
	          get one from the Mutation Machine)

	About 1 hatch in 9 is mutated. The odds stack with the pet's own odds, so a
	Rainbow Legendary from a 1-in-50 pet is 1 in 25,000.

	The Mutation Machine (MutationService, by the village spawn) rerolls the mutation
	of a pet or a hat for Coins, or with better odds on the rare ones for Shards
	(Mutations.Machine). It always gives a mutation, but it can be a worse one. Its
	rarest result is Secret, which only the machine can give (Mutations.Secret, not in
	List, so eggs never roll it).
]]

local Balance = require(script.Parent.Balance)

local Mutations = {}

local rgb = Color3.fromRGB

-- commonest first; Order is the display order
Mutations.List = {
	{ Id = "Big", Name = "Big", OneIn = 15, Mult = 1.5, HatMult = 1.1, Scale = 1.4, Color = rgb(120, 220, 255) },
	{ Id = "Golden", Name = "Golden", OneIn = 40, Mult = 2, HatMult = 1.15, Scale = 1, Color = rgb(255, 205, 50) },
	{ Id = "Frozen", Name = "Frozen", OneIn = 90, Mult = 2.5, HatMult = 1.2, Scale = 1, Color = rgb(160, 230, 255) },
	{ Id = "Shocked", Name = "Shocked", OneIn = 150, Mult = 3, HatMult = 1.25, Scale = 1, Color = rgb(255, 245, 90) },
	{ Id = "Shadow", Name = "Shadow", OneIn = 300, Mult = 4, HatMult = 1.35, Scale = 1, Color = rgb(170, 90, 255) },
	{ Id = "Rainbow", Name = "Rainbow", OneIn = 500, Mult = 5, HatMult = 1.5, Scale = 1, Color = rgb(255, 110, 200), Shout = true },
	{ Id = "Giant", Name = "Giant", OneIn = 2000, Mult = 8, HatMult = 1.75, Scale = 2.2, Color = rgb(255, 140, 60), Shout = true },
	{ Id = "Celestial", Name = "Celestial", OneIn = 25000, Mult = 20, HatMult = 2.25, Scale = 1.3, Color = rgb(255, 250, 210), Shout = true },
}

-- The machine-only mutation: never hatched, only rolled at the Mutation Machine.
Mutations.Secret = { Id = "Secret", Name = "Secret", OneIn = 0, Mult = 50, HatMult = 3, Scale = 1.5, Color = rgb(255, 60, 200), Shout = true, MachineOnly = true }

Mutations.ById = {}
for index, m in ipairs(Mutations.List) do
	m.Order = index
	m.Chance = 1 / m.OneIn
	Mutations.ById[m.Id] = m
end
Mutations.Secret.Order = #Mutations.List + 1
Mutations.Secret.Chance = 0
Mutations.ById.Secret = Mutations.Secret
-- every mutation, hatchable ones first, Secret last
Mutations.All = table.clone(Mutations.List)
table.insert(Mutations.All, Mutations.Secret)

-- ===== Mutation Machine =====
-- Weights per roll (relative). A Shard roll ("Lucky") multiplies the rare ones (Rare = true)
-- by LuckyBoost. Luck (stats) also tilts toward the rare ones a little, as for hatches.
Mutations.Machine = {
	Zone = "village",
	Offset = Vector2.new(-238, -30), -- beside the spawn plaza (ZoneDecor.Village builds it there)
	Range = 22, -- studs: stand this close to use it
	Weights = {
		{ Id = "Big", Weight = 300 },
		{ Id = "Golden", Weight = 220 },
		{ Id = "Frozen", Weight = 160 },
		{ Id = "Shocked", Weight = 120 },
		{ Id = "Shadow", Weight = 90 },
		{ Id = "Rainbow", Weight = 60, Rare = true },
		{ Id = "Giant", Weight = 35, Rare = true },
		{ Id = "Celestial", Weight = 12, Rare = true },
		{ Id = "Secret", Weight = 3, Rare = true },
	},
	LuckyBoost = 3,
	-- prices: Coins = Balance.CoinsForKills(max(level, 10), CoinKills x pet rarity step); Shards flat
	CoinKills = 40,
	LuckyShards = 25,
}

-- Coins for a normal machine roll of an item `step` rarities up (1 = Common) at `level`.
function Mutations.MachinePrice(level: number, step: number): number
	return Balance.CoinsForKills(math.max(level, 10), Mutations.Machine.CoinKills * math.max(1, step))
end

-- Chance (0..1) of each machine result: { [id] = chance }.
function Mutations.MachineOdds(lucky: boolean, luck: number?): { [string]: number }
	local tilt = Mutations.LuckMult(luck)
	local total, weights = 0, {}
	for _, w in ipairs(Mutations.Machine.Weights) do
		local weight = w.Weight
		if w.Rare then
			weight *= tilt * (if lucky then Mutations.Machine.LuckyBoost else 1)
		end
		weights[w.Id] = weight
		total += weight
	end
	for id, weight in pairs(weights) do
		weights[id] = weight / total
	end
	return weights
end

-- One machine roll: always a mutation id.
function Mutations.MachineRoll(lucky: boolean, luck: number?, rng: Random?): string
	local odds = Mutations.MachineOdds(lucky, luck)
	local roll = (rng or Random.new()):NextNumber()
	-- rarest first, so float error can only shave the commonest
	for i = #Mutations.Machine.Weights, 1, -1 do
		local id = Mutations.Machine.Weights[i].Id
		roll -= odds[id]
		if roll < 0 then
			return id
		end
	end
	return Mutations.Machine.Weights[1].Id
end

Mutations.LuckPerPoint = 0.25 -- +25% mutation chance per point of Luck (1.0 = +100% Luck)
Mutations.MaxLuckMult = 2 -- never more than double

-- The rarest mutations get the big hatch banner and a server-wide shoutout.
Mutations.RareOneIn = 500

function Mutations.Get(id: string?)
	return if id then Mutations.ById[id] else nil
end

function Mutations.LuckMult(luck: number?): number
	return math.min(Mutations.MaxLuckMult, 1 + math.max(0, luck or 0) * Mutations.LuckPerPoint)
end

-- Chance (0..1) of a given mutation with `luck` applied.
function Mutations.ChanceOf(id: string, luck: number?): number
	local m = Mutations.ById[id]
	return if m then m.Chance * Mutations.LuckMult(luck) else 0
end

-- 1 in N for a mutation with luck applied (rounded).
function Mutations.OneIn(id: string, luck: number?): number?
	local chance = Mutations.ChanceOf(id, luck)
	return if chance > 0 then math.max(1, math.floor(1 / chance + 0.5)) else nil
end

-- Chance (0..1) that a hatch is mutated at all.
function Mutations.TotalChance(luck: number?): number
	local total = 0
	for _, m in ipairs(Mutations.List) do
		total += m.Chance
	end
	return total * Mutations.LuckMult(luck)
end

-- One roll per hatch: nil (no mutation) or a mutation id. `force` (admin and
-- tests) skips the roll.
function Mutations.Roll(luck: number?, rng: Random?, force: string?): string?
	if force then
		return if Mutations.ById[force] then force else nil
	end
	local random = rng or Random.new()
	local roll = random:NextNumber()
	local mult = Mutations.LuckMult(luck)
	-- rarest first so float error can only ever shave the commonest
	for i = #Mutations.List, 1, -1 do
		local m = Mutations.List[i]
		roll -= m.Chance * mult
		if roll < 0 then
			return m.Id
		end
	end
	return nil
end

function Mutations.Mult(id: string?): number
	local m = id and Mutations.ById[id]
	return if m then m.Mult else 1
end

-- Accepts "golden", "Golden", "GOLDEN".
function Mutations.Find(text: string?): string?
	if type(text) ~= "string" then
		return nil
	end
	local lower = string.lower(text)
	for _, m in ipairs(Mutations.All) do
		if string.lower(m.Id) == lower then
			return m.Id
		end
	end
	return nil
end

return Mutations
