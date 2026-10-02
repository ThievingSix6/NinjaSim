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

	About 1 hatch in 9 is mutated. The odds stack with the pet's own odds, so a
	Rainbow Legendary from a 1-in-50 pet is 1 in 25,000.
]]

local Mutations = {}

local rgb = Color3.fromRGB

-- commonest first; Order is the display order
Mutations.List = {
	{ Id = "Big", Name = "Big", OneIn = 15, Mult = 1.5, Scale = 1.4, Color = rgb(120, 220, 255) },
	{ Id = "Golden", Name = "Golden", OneIn = 40, Mult = 2, Scale = 1, Color = rgb(255, 205, 50) },
	{ Id = "Frozen", Name = "Frozen", OneIn = 90, Mult = 2.5, Scale = 1, Color = rgb(160, 230, 255) },
	{ Id = "Shocked", Name = "Shocked", OneIn = 150, Mult = 3, Scale = 1, Color = rgb(255, 245, 90) },
	{ Id = "Shadow", Name = "Shadow", OneIn = 300, Mult = 4, Scale = 1, Color = rgb(170, 90, 255) },
	{ Id = "Rainbow", Name = "Rainbow", OneIn = 500, Mult = 5, Scale = 1, Color = rgb(255, 110, 200), Shout = true },
	{ Id = "Giant", Name = "Giant", OneIn = 2000, Mult = 8, Scale = 2.2, Color = rgb(255, 140, 60), Shout = true },
	{ Id = "Celestial", Name = "Celestial", OneIn = 25000, Mult = 20, Scale = 1.3, Color = rgb(255, 250, 210), Shout = true },
}

Mutations.ById = {}
for index, m in ipairs(Mutations.List) do
	m.Order = index
	m.Chance = 1 / m.OneIn
	Mutations.ById[m.Id] = m
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
	for _, m in ipairs(Mutations.List) do
		if string.lower(m.Id) == lower then
			return m.Id
		end
	end
	return nil
end

return Mutations
