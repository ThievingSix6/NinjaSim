--[[
	Charms: Diablo II style charms. They do nothing in storage; placed in the charm
	grid of the inventory (Charms.Cols x Charms.Rows, 10 x 4) every one of them counts.
	So the grid is the real limit: big charms roll more but take more room.

	Sizes (W x H cells):  Small 1x1, Large 1x2, Grand 1x3.
	Rarities: Magic, Rare, Legendary, Mythic (more and bigger affixes), plus Unique for
	named charms (the Hexfire Torch). Affixes are the hat affixes (Config/Hats), scaled by
	size, rarity and item level (the enemy's level).

	Skill charms: a Grand charm can roll "+N to <skill>" (Charms.SkillChance). Skill
	levels from charms stack on top of the bought level and are the only way past
	Skills.MaxLevel (up to Skills.HardCap). "+N to all skills" only comes from uniques.

	Drops (LootService): Charms.DropChance (0.3%) per kill for each player who earned it,
	bosses included; training dummies never. Every boss kill also rolls
	Charms.TorchChance (0.01%) for the Hexfire Torch.

	The Hexfire Torch (Large, Unique): +1-3 to all skills, +10-20% damage and max HP, and
	every attack has a 25% chance to cast Hexfire: a rolling tendril of flame that
	burns its way forward (SkillService:CastHexfire). Only one torch in the grid counts.

	Saved form (DataTemplate.Charms[uid]):
	  { Z = size, R = rarity, L = itemLevel, A = { { K = affix, V = value } },
	    S = { K = skillId | "All", N = levels }?, U = uniqueId?, X = col?, Y = row? }
	X / Y (1-based top-left cell) are set while the charm sits in the grid.
]]

local Hats = require(script.Parent.Hats)
local Skills = require(script.Parent.Skills)

local Charms = {}

local rgb = Color3.fromRGB

Charms.Cols = 10
Charms.Rows = 4
Charms.Storage = 60 -- charms you can keep, grid included; a pickup past this is salvaged
Charms.DropChance = 0.003 -- per kill, per player who earned it
Charms.TorchChance = 0.0001 -- per boss kill, per player who earned it
Charms.SkillChance = 0.3 -- share of Grand charms that roll a skill
Charms.Caps = { Crit = 0.3, Speed = 0.4, Haste = 0.5 } -- most the whole grid can add

Charms.Sizes = {
	{ Id = "Small", Name = "Small Charm", W = 1, H = 1, Scale = 0.45, Weight = 50, Icon = "Sparkle" },
	{ Id = "Large", Name = "Large Charm", W = 1, H = 2, Scale = 0.7, Weight = 32, Icon = "Scroll" },
	{ Id = "Grand", Name = "Grand Charm", W = 1, H = 3, Scale = 1, Weight = 18, Icon = "Book" },
}
Charms.SizeById = {}
for i, s in ipairs(Charms.Sizes) do
	s.Index = i
	Charms.SizeById[s.Id] = s
end

-- Affixes {min, max}, Roll: multiplier on every value, SkillBonus: extra skill levels.
-- Shards: what a charm salvages for when storage is full.
Charms.Rarities = {
	{ Name = "Magic", Color = rgb(110, 150, 255), Paint = "Blue", Affixes = { 1, 2 }, Roll = 1, Weight = 70, LuckK = 0.5, SkillBonus = 0, Shards = 2 },
	{ Name = "Rare", Color = rgb(255, 228, 80), Paint = "Gold", Affixes = { 2, 3 }, Roll = 1.1, Weight = 22, LuckK = 1, SkillBonus = 0, Shards = 5 },
	{ Name = "Legendary", Color = rgb(255, 140, 30), Paint = "Orange", Affixes = { 3, 3 }, Roll = 1.3, Weight = 6.5, LuckK = 1.5, SkillBonus = 1, Shards = 15 },
	{ Name = "Mythic", Color = rgb(255, 80, 170), Paint = { rgb(255, 120, 200), rgb(196, 30, 130) }, Affixes = { 4, 4 }, Roll = 1.6, Weight = 1.5, LuckK = 2, SkillBonus = 2, Shards = 40 },
	{ Name = "Unique", Color = rgb(226, 178, 96), Paint = { rgb(240, 196, 110), rgb(150, 92, 30) }, Affixes = { 0, 0 }, Roll = 1, Weight = 0, LuckK = 0, SkillBonus = 0, Shards = 250 },
}
Charms.RarityByName = {}
for i, r in ipairs(Charms.Rarities) do
	r.Index = i
	Charms.RarityByName[r.Name] = r
end

function Charms.Rarity(name: string?)
	return Charms.RarityByName[name or ""] or Charms.Rarities[1]
end

-- "+N to <skill>" rolls: +1 most of the time, +3 rarely (rarity adds SkillBonus).
Charms.SkillRolls = { { N = 1, Weight = 70 }, { N = 2, Weight = 24 }, { N = 3, Weight = 6 } }

-- The Hexfire spell the torch casts (server: SkillService:CastHexfire; looks: CharmEffects).
Charms.Hexfire = {
	Id = "hexfire", Name = "Hexfire", Color = rgb(255, 110, 30), Icon = "Flame", Paint = "Orange",
	Chance = 0.25, -- per attack
	Cooldown = 0.45, -- seconds between two casts, however fast you swing
	Length = 44, Width = 9, Segments = 7, Step = 0.085, -- the tendril rolls forward a segment at a time
	Damage = 1.4, -- x your hit damage, once per enemy it rolls over
	Burn = 0.3, BurnTicks = 3, MaxTargets = 30,
}

-- Named charms. Stats: { key = { min, max } }, AllSkills = { min, max }.
Charms.Uniques = {
	hexfire = {
		Id = "hexfire", Name = "Hexfire Torch", Size = "Large", Icon = "Flame",
		Stats = { Damage = { 0.1, 0.2 }, Health = { 0.1, 0.2 } }, AllSkills = { 1, 3 },
		Desc = "A torch lit from a cursed shrine. It never goes out, and it is never satisfied.",
	},
}

function Charms.Size(charm)
	return Charms.SizeById[charm and charm.Z or ""] or Charms.Sizes[1]
end

-- True when a saved record is well formed (old or hand-edited saves).
function Charms.Valid(charm: any): boolean
	if type(charm) ~= "table" or not Charms.SizeById[charm.Z] or not Charms.RarityByName[charm.R] then
		return false
	end
	if type(charm.L) ~= "number" or type(charm.A) ~= "table" then
		return false
	end
	if charm.U ~= nil and not Charms.Uniques[charm.U] then
		return false
	end
	if charm.G ~= nil and type(charm.G) ~= "string" then
		return false
	end
	return true
end

-- ===== rolling (server) =====
local function weighted(list: { any }, weightOf: (any) -> number, rng: Random): any
	local total = 0
	for _, item in ipairs(list) do
		total += weightOf(item)
	end
	local pick = rng:NextNumber() * total
	for _, item in ipairs(list) do
		pick -= weightOf(item)
		if pick <= 0 then
			return item
		end
	end
	return list[#list]
end

local function round(v: number, step: number): number
	return math.floor(v / step + 0.5) * step
end

local function sortAffixes(list)
	table.sort(list, function(a, b)
		return Hats.AffixById[a.K].Order < Hats.AffixById[b.K].Order
	end)
end

-- A brand new charm. Pass sizeId / rarityName / skillId to force them (admin, tests;
-- a skillId that is no skill, such as "any", forces a random skill on a Grand charm).
function Charms.Roll(itemLevel: number, luck: number, rng: Random?, sizeId: string?, rarityName: string?, skillId: string?)
	local r = rng or Random.new()
	luck = math.max(0, luck or 0)
	local size = Charms.SizeById[sizeId or ""] or weighted(Charms.Sizes, function(s)
		return s.Weight
	end, r)
	local rarity = Charms.RarityByName[rarityName or ""]
	if not rarity or rarity.Name == "Unique" then
		rarity = weighted(Charms.Rarities, function(x)
			return x.Weight * (1 + luck * x.LuckK)
		end, r)
	end
	local level = math.clamp(math.floor(itemLevel), 1, Hats.MaxItemLevel)
	local scale = Hats.LevelScale(level) * rarity.Roll * size.Scale
	local charm: any = { Z = size.Id, R = rarity.Name, L = level, A = {} }
	local pool = table.clone(Hats.Affixes)
	for _ = 1, r:NextInteger(rarity.Affixes[1], rarity.Affixes[2]) do
		local def = table.remove(pool, r:NextInteger(1, #pool))
		table.insert(charm.A, { K = def.Id, V = Hats.RollAffix(def, scale, r) })
	end
	sortAffixes(charm.A)
	if size.Id == "Grand" and (skillId ~= nil or r:NextNumber() < Charms.SkillChance) then
		local skill = Skills.Get(skillId) or Skills.List[r:NextInteger(1, #Skills.List)]
		local n = weighted(Charms.SkillRolls, function(x)
			return x.Weight
		end, r).N
		charm.S = { K = skill.Id, N = n + rarity.SkillBonus }
	end
	return charm
end

-- A named charm (Charms.Uniques), rolled within its ranges.
function Charms.RollUnique(uniqueId: string, itemLevel: number, rng: Random?)
	local def = Charms.Uniques[uniqueId]
	if not def then
		return nil
	end
	local r = rng or Random.new()
	local charm: any = { Z = def.Size, R = "Unique", L = math.clamp(math.floor(itemLevel), 1, Hats.MaxItemLevel), A = {}, U = def.Id }
	for key, range in pairs(def.Stats) do
		table.insert(charm.A, { K = key, V = round(range[1] + (range[2] - range[1]) * r:NextNumber(), 0.005) })
	end
	sortAffixes(charm.A)
	if def.AllSkills then
		charm.S = { K = "All", N = r:NextInteger(def.AllSkills[1], def.AllSkills[2]) }
	end
	return charm
end

-- ===== reading a charm =====
function Charms.Name(charm): string
	if not Charms.Valid(charm) then
		return "Unknown Charm"
	end
	local size = Charms.Size(charm)
	if charm.U then
		return Charms.Uniques[charm.U].Name
	end
	local a1 = charm.A[1] and Hats.AffixById[charm.A[1].K]
	local a2 = charm.A[2] and Hats.AffixById[charm.A[2].K]
	local skill = charm.S and Skills.Get(charm.S.K)
	if skill then
		return (if a1 then a1.Prefix .. " " else "") .. size.Name .. " of " .. skill.Name
	elseif a1 and a2 then
		return a1.Prefix .. " " .. size.Name .. " " .. a2.Suffix
	elseif a1 then
		return a1.Prefix .. " " .. size.Name
	end
	return size.Name
end

function Charms.Color(charm): Color3
	return Charms.Rarity(charm and charm.R).Color
end

function Charms.Icon(charm): string
	if charm and charm.U then
		return Charms.Uniques[charm.U].Icon
	end
	local skill = charm and charm.S and Skills.Get(charm.S.K)
	return if skill then skill.Icon else Charms.Size(charm).Icon
end

-- Every line of a charm's tooltip, in order: { text, color? }.
function Charms.Lines(charm): { { any } }
	local out = {}
	if not Charms.Valid(charm) then
		return out
	end
	if charm.S then
		local name = if charm.S.K == "All" then "All Skills" else (Skills.Get(charm.S.K) and Skills.Get(charm.S.K).Name or charm.S.K)
		table.insert(out, { string.format("+%d to %s", charm.S.N, name), rgb(255, 214, 90) })
	end
	for _, a in ipairs(charm.A) do
		table.insert(out, { Hats.StatText(a.K, a.V) })
	end
	if charm.U == "hexfire" then
		table.insert(out, { string.format("%d%% chance on attack to cast Hexfire", Charms.Hexfire.Chance * 100), Charms.Hexfire.Color })
	end
	return out
end

-- ===== the grid =====
-- Cells a charm would cover at (x, y), or nil when it runs off the grid.
function Charms.Cells(charm, x: number, y: number): { number }?
	local size = Charms.Size(charm)
	if type(x) ~= "number" or type(y) ~= "number" or x ~= math.floor(x) or y ~= math.floor(y) then
		return nil
	end
	if x < 1 or y < 1 or x + size.W - 1 > Charms.Cols or y + size.H - 1 > Charms.Rows then
		return nil
	end
	local cells = {}
	for dx = 0, size.W - 1 do
		for dy = 0, size.H - 1 do
			table.insert(cells, (y + dy - 1) * Charms.Cols + (x + dx))
		end
	end
	return cells
end

-- Grids: your own (grid nil) and one per hired ninja (grid = the hire's id, Config/Hires).
-- A charm's G says whose grid it sits in (nil = yours); X, Y where in it.
local function inGrid(charm, grid: string?): boolean
	return (charm.G or "") == (grid or "")
end

-- Which charm uid covers each cell of a grid: { [cellIndex] = uid }. Skips placements
-- that are off the grid or overlap one already counted (old or hand-edited saves).
function Charms.Occupancy(data, ignoreUid: string?, grid: string?): { [number]: string }
	local taken = {}
	local charms = type(data.Charms) == "table" and data.Charms or {}
	local uids = {}
	for uid, charm in pairs(charms) do
		if uid ~= ignoreUid and Charms.Valid(charm) and charm.X and charm.Y and inGrid(charm, grid) then
			table.insert(uids, uid)
		end
	end
	table.sort(uids)
	for _, uid in ipairs(uids) do
		local charm = charms[uid]
		local cells = Charms.Cells(charm, charm.X, charm.Y)
		local free = cells ~= nil
		for _, c in ipairs(cells or {}) do
			if taken[c] then
				free = false
			end
		end
		if free then
			for _, c in ipairs(cells :: { number }) do
				taken[c] = uid
			end
		end
	end
	return taken
end

-- Whether `charm` (uid) fits at (x, y) of a grid, ignoring its own current spot.
function Charms.Fits(data, uid: string, x: number, y: number, grid: string?): boolean
	local charm = data.Charms and data.Charms[uid]
	local cells = charm and Charms.Cells(charm, x, y)
	if not cells then
		return false
	end
	local taken = Charms.Occupancy(data, uid, grid)
	for _, c in ipairs(cells) do
		if taken[c] then
			return false
		end
	end
	return true
end

-- The first free spot for a charm (scanning columns left to right), or nil.
function Charms.FreeSpot(data, uid: string, grid: string?): (number?, number?)
	for x = 1, Charms.Cols do
		for y = 1, Charms.Rows do
			if Charms.Fits(data, uid, x, y, grid) then
				return x, y
			end
		end
	end
	return nil, nil
end

-- The uids that are really in a grid (valid spot, no overlap), as a set.
function Charms.Active(data, grid: string?): { [string]: boolean }
	local out = {}
	for _, uid in pairs(Charms.Occupancy(data, nil, grid)) do
		out[uid] = true
	end
	return out
end

-- Everything a grid adds up to: { [statKey] = value, Skills = { [id] = n }, AllSkills, Hexfire }.
function Charms.Bonus(data, grid: string?)
	local out: any = { Skills = {}, AllSkills = 0, Hexfire = 0 }
	local torch = false
	local uids = {}
	for uid in pairs(Charms.Active(data, grid)) do
		table.insert(uids, uid)
	end
	table.sort(uids, function(a, b)
		return (tonumber(a) or 0) < (tonumber(b) or 0) -- oldest first: the first torch is the one that counts
	end)
	for _, uid in ipairs(uids) do
		local charm = data.Charms[uid]
		local counts = true
		if charm.U == "hexfire" then
			counts = not torch -- only one torch works
			torch = true
		end
		if counts then
			for _, a in ipairs(charm.A) do
				if Hats.AffixById[a.K] and type(a.V) == "number" then
					out[a.K] = (out[a.K] or 0) + a.V
				end
			end
			if type(charm.S) == "table" and type(charm.S.N) == "number" then
				if charm.S.K == "All" then
					out.AllSkills += charm.S.N
				elseif Skills.Get(charm.S.K) then
					out.Skills[charm.S.K] = (out.Skills[charm.S.K] or 0) + charm.S.N
				end
			end
		end
	end
	if torch then
		out.Hexfire = Charms.Hexfire.Chance
	end
	for key, cap in pairs(Charms.Caps) do
		if out[key] then
			out[key] = math.min(cap, out[key])
		end
	end
	return out
end

-- Share of the fighting hire's charm stats that you get too (not skills or the torch).
Charms.HireShare = 0.5
Charms.SharedStats = { "Damage", "Crit", "Health", "Speed", "Haste", "XP", "Coins", "Luck", "Regen", "RegenStart", "LifeSteal" }

-- Your grid plus HireShare of the active hire's grid (data.ActiveHire), capped as usual.
function Charms.PlayerBonus(data)
	local b = Charms.Bonus(data)
	local hire = type(data.ActiveHire) == "string" and data.ActiveHire ~= "" and data.ActiveHire or nil
	if hire and type(data.Hires) == "table" and data.Hires[hire] then
		local h = Charms.Bonus(data, hire)
		for _, key in ipairs(Charms.SharedStats) do
			if h[key] then
				b[key] = (b[key] or 0) + h[key] * Charms.HireShare
			end
		end
		for key, cap in pairs(Charms.Caps) do
			if b[key] then
				b[key] = math.min(cap, b[key])
			end
		end
	end
	return b
end

-- Folds the charm grid into the derived stats (called from Stats.Compute, after hats).
function Charms.ApplyToStats(stats, data, Balance)
	local b = Charms.PlayerBonus(data)
	stats.Damage = math.floor(stats.Damage * (1 + (b.Damage or 0)))
	stats.CritChance += b.Crit or 0
	stats.MaxHealth = math.floor(stats.MaxHealth * (1 + (b.Health or 0)))
	stats.WalkSpeed *= 1 + (b.Speed or 0)
	stats.AttackInterval = math.max(Balance.MinAttackInterval, stats.AttackInterval / (1 + (b.Haste or 0)))
	stats.XPMult *= 1 + (b.XP or 0)
	stats.CoinMult *= 1 + (b.Coins or 0)
	stats.Luck += b.Luck or 0
	stats.HealthRegen += b.Regen or 0
	stats.RegenDelay = math.max(Hats.MinRegenDelay, stats.RegenDelay - (b.RegenStart or 0))
	stats.LifeSteal = math.min(Hats.LifeStealCap, (stats.LifeSteal or 0) + (b.LifeSteal or 0))
	stats.SkillBonus = b.Skills
	stats.AllSkills = b.AllSkills
	stats.Hexfire = b.Hexfire
	return stats
end

-- Spirit Shards a charm salvages for.
function Charms.SalvageValue(charm): number
	return Charms.Rarity(charm.R).Shards * Charms.Size(charm).Index
end

return Charms
