--[[
	Hats: Diablo-style loot. The only gear slot for now is the head.

	Drops (server, LootService): every enemy kill has a DropChance (1%) chance to drop
	a hat for each player who earned the kill; bosses BossDropChance (25%). Training
	dummies never drop. Only that player sees the drop and can pick it up.

	A hat is one of the base hats below (each with its own fixed base stats and the
	areas it drops in, so later areas drop better bases), a rarity and an item level
	(the enemy's level). Magic and better hats roll affixes from Hats.Affixes, scaled
	by item level; Legendary and Mythic hats also roll one "chance on hit to cast a
	skill" proc. Luck (the same stat that helps eggs) makes better rarities likelier;
	it never changes the base 1% drop rate.

	Saved form (DataTemplate.Hats[uid]) is kept tiny and JSON-friendly:
	  { Id = baseId, R = rarity, L = itemLevel, A = { { K = affixId, V = value } }, P = { S = skillId, C = chance }?, Lock = bool? }
]]

local Skills = require(script.Parent.Skills)
local Mutations = require(script.Parent.Mutations)

local Hats = {}

local rgb = Color3.fromRGB

Hats.DropChance = 0.01 -- per kill, per player who earned the kill
Hats.BossDropChance = 0.25
Hats.Storage = 60 -- hats you can keep; a pickup with full storage is salvaged on the spot
Hats.PickupRadius = 9 -- studs: walk this close to a drop to collect it
Hats.AutoCollect = 6 -- seconds until an uncollected drop flies to you anyway
Hats.ProcCooldown = 2 -- seconds before the same hat proc can fire again
Hats.ProcLevel = 1 -- procs cast the skill at this skill level (SkillService:CastAt), whatever yours is
Hats.LifeStealCap = 15 -- most % of max HP a single kill can heal
Hats.MinRegenDelay = 1 -- seconds; RegenDelay affixes can't push it lower
Hats.MaxItemLevel = 545

-- ===== rarities =====
-- Affixes: {min, max} normal affixes. Proc: also rolls a skill proc. Roll: multiplier on
-- every roll. Weight: share of drops (Luck multiplies it by 1 + Luck x LuckK).
-- Salvage: kills' worth of Coins (at the hat's item level) plus Shards.
Hats.Rarities = {
	{ Name = "Common", Color = rgb(225, 225, 232), Paint = "Grey", Affixes = { 0, 0 }, Roll = 1, Weight = 60, BossWeight = 0, LuckK = 0, Salvage = { Kills = 3, Shards = 0 } },
	{ Name = "Magic", Color = rgb(110, 150, 255), Paint = "Blue", Affixes = { 1, 2 }, Roll = 1, Weight = 28, BossWeight = 50, LuckK = 0.5, Salvage = { Kills = 8, Shards = 0 } },
	{ Name = "Rare", Color = rgb(255, 228, 80), Paint = "Gold", Affixes = { 3, 4 }, Roll = 1.1, Weight = 9.5, BossWeight = 35, LuckK = 1, Salvage = { Kills = 20, Shards = 0 } },
	{ Name = "Legendary", Color = rgb(255, 140, 30), Paint = "Orange", Affixes = { 4, 4 }, Proc = true, Roll = 1.25, Weight = 2.2, BossWeight = 12, LuckK = 1.5, Salvage = { Kills = 60, Shards = 3 } },
	{ Name = "Mythic", Color = rgb(255, 80, 170), Paint = { rgb(255, 120, 200), rgb(196, 30, 130) }, Affixes = { 5, 5 }, Proc = true, Roll = 1.6, Weight = 0.3, BossWeight = 3, LuckK = 2, Salvage = { Kills = 150, Shards = 12 } },
}
Hats.RarityByName = {}
for i, r in ipairs(Hats.Rarities) do
	r.Index = i
	Hats.RarityByName[r.Name] = r
end

function Hats.Rarity(name: string?)
	return Hats.RarityByName[name or ""] or Hats.Rarities[1]
end

-- ===== affixes =====
-- Min/Max at item-level scale 1 (about level 60). Kind: "Pct" (shown as %), "Regen"
-- (% of max HP per second), "Seconds", "Life" (whole points, 1 point = 1% of max HP healed per kill).
Hats.Affixes = {
	{ Id = "Damage", Name = "Damage", Kind = "Pct", Min = 0.03, Max = 0.07, Prefix = "Brutal", Suffix = "of Slaughter" },
	{ Id = "Crit", Name = "Crit Chance", Kind = "Pct", Min = 0.01, Max = 0.03, Prefix = "Keen", Suffix = "of Precision" },
	{ Id = "Health", Name = "Max HP", Kind = "Pct", Min = 0.04, Max = 0.1, Prefix = "Sturdy", Suffix = "of the Ox" },
	{ Id = "Speed", Name = "Move Speed", Kind = "Pct", Min = 0.02, Max = 0.05, Prefix = "Swift", Suffix = "of the Wind" },
	{ Id = "Haste", Name = "Attack Speed", Kind = "Pct", Min = 0.02, Max = 0.05, Prefix = "Frenzied", Suffix = "of Fury" },
	{ Id = "XP", Name = "XP", Kind = "Pct", Min = 0.04, Max = 0.1, Prefix = "Wise", Suffix = "of the Sage" },
	{ Id = "Coins", Name = "Coins", Kind = "Pct", Min = 0.05, Max = 0.12, Prefix = "Gilded", Suffix = "of Greed" },
	{ Id = "Regen", Name = "HP Regen", Kind = "Regen", Min = 0.004, Max = 0.01, Prefix = "Vital", Suffix = "of Renewal" },
	{ Id = "RegenStart", Name = "Regen Start", Kind = "Seconds", Min = 0.4, Max = 1, Prefix = "Restless", Suffix = "of the Phoenix" },
	{ Id = "LifeSteal", Name = "Life Steal", Kind = "Life", Min = 1, Max = 2, Prefix = "Vampiric", Suffix = "of the Leech" },
	{ Id = "Luck", Name = "Luck", Kind = "Pct", Min = 0.03, Max = 0.08, Prefix = "Lucky", Suffix = "of Fortune" },
}
Hats.AffixById = {}
for i, a in ipairs(Hats.Affixes) do
	a.Order = i
	Hats.AffixById[a.Id] = a
end

-- "X% chance on hit to cast <skill>" (Legendary and Mythic). Chance per sword swing that lands.
Hats.Procs = {
	{ Skill = "lightning_blade", Prefix = "Thundering", Suffix = "of the Storm", Min = 0.04, Max = 0.07 },
	{ Skill = "shuriken_storm", Prefix = "Whirling", Suffix = "of a Thousand Stars", Min = 0.05, Max = 0.08 },
	{ Skill = "dragon_flame", Prefix = "Blazing", Suffix = "of the Dragon", Min = 0.04, Max = 0.07 },
	{ Skill = "oni_quake", Prefix = "Quaking", Suffix = "of the Oni", Min = 0.03, Max = 0.06 },
	{ Skill = "kunai_rain", Prefix = "Piercing", Suffix = "of Falling Steel", Min = 0.04, Max = 0.07 },
	{ Skill = "whirlwind_slash", Prefix = "Tempest", Suffix = "of the Tempest", Min = 0.05, Max = 0.08 },
}
Hats.ProcBySkill = {}
for _, p in ipairs(Hats.Procs) do
	Hats.ProcBySkill[p.Skill] = p
end

-- ===== base hats =====
-- Zones = { first, last } area index (Config/Zones order) it drops in.
-- Stats: fixed base stats, same keys as the affixes. Shape + Colors drive HatBuilder.
-- Face = true: worn over the face (masks) rather than on top of the head.
Hats.List = {
	{ Id = "hachimaki", Name = "Hachimaki", Shape = "Band", Zones = { 1, 2 }, Stats = { XP = 0.05 },
		Colors = { Main = rgb(220, 40, 50), Trim = rgb(200, 205, 215) }, Desc = "A training headband. Sweat now, level faster." },
	{ Id = "straw_kasa", Name = "Straw Kasa", Shape = "Kasa", Zones = { 1, 3 }, Stats = { Speed = 0.04 },
		Colors = { Main = rgb(214, 182, 112), Trim = rgb(150, 112, 60) }, Desc = "A wide woven hat for long roads." },
	{ Id = "ninja_hood", Name = "Ninja Hood", Shape = "Hood", Zones = { 1, 3 }, Stats = { Crit = 0.02 },
		Colors = { Main = rgb(36, 40, 58), Trim = rgb(170, 176, 190) }, Desc = "A shinobi cowl with a steel plate." },
	{ Id = "ronin_amigasa", Name = "Ronin Amigasa", Shape = "Amigasa", Zones = { 2, 4 }, Stats = { Coins = 0.08 },
		Colors = { Main = rgb(170, 128, 70), Trim = rgb(92, 62, 34) }, Desc = "Masterless, but never penniless." },
	{ Id = "kitsune_mask", Name = "Kitsune Mask", Shape = "Kitsune", Face = true, Zones = { 2, 5 }, Stats = { Crit = 0.05 },
		Colors = { Main = rgb(248, 246, 240), Trim = rgb(220, 40, 50), Accent = rgb(255, 196, 60) }, Desc = "The fox spirit guides your blade to soft spots." },
	{ Id = "tengu_mask", Name = "Tengu Mask", Shape = "Tengu", Face = true, Zones = { 2, 5 }, Stats = { Haste = 0.06 },
		Colors = { Main = rgb(210, 40, 36), Trim = rgb(30, 26, 30), Accent = rgb(245, 245, 240) }, Desc = "The mountain goblin's restless fury." },
	{ Id = "ashigaru_jingasa", Name = "Ashigaru Jingasa", Shape = "Jingasa", Zones = { 3, 4 }, Stats = { Health = 0.08 },
		Colors = { Main = rgb(34, 30, 34), Trim = rgb(220, 180, 70) }, Desc = "A foot soldier's lacquered iron hat." },
	{ Id = "samurai_kabuto", Name = "Samurai Kabuto", Shape = "Kabuto", Zones = { 3, 6 }, Stats = { Health = 0.12 },
		Colors = { Main = rgb(46, 42, 52), Trim = rgb(232, 186, 70), Accent = rgb(170, 30, 36) }, Desc = "A war helmet with golden horns." },
	{ Id = "iron_mempo", Name = "Iron Mempo", Shape = "Mempo", Face = true, Zones = { 3, 5 }, Stats = { Damage = 0.05, Health = 0.04 },
		Colors = { Main = rgb(70, 72, 80), Trim = rgb(200, 200, 210), Accent = rgb(40, 36, 40) }, Desc = "A snarling iron face guard." },
	{ Id = "oni_mask", Name = "Oni Mask", Shape = "Oni", Face = true, Zones = { 4, 6 }, Stats = { Damage = 0.08 },
		Colors = { Main = rgb(200, 36, 40), Trim = rgb(250, 240, 210), Accent = rgb(255, 210, 60) }, Desc = "The demon's grin. Hit like one." },
	{ Id = "hannya_mask", Name = "Hannya Mask", Shape = "Hannya", Face = true, Zones = { 4, 7 }, Stats = { Damage = 0.06, Crit = 0.03 },
		Colors = { Main = rgb(244, 238, 226), Trim = rgb(232, 186, 70), Accent = rgb(220, 30, 40) }, Desc = "A jealous spirit's mask, horned in gold." },
	{ Id = "demon_horns", Name = "Demon Horns", Shape = "Horns", Zones = { 4, 6 }, Stats = { Damage = 0.04, LifeSteal = 1 },
		Colors = { Main = rgb(70, 20, 24), Trim = rgb(255, 80, 40) }, Desc = "They drink a little of every foe you fell." },
	{ Id = "komuso_basket", Name = "Komuso Basket", Shape = "Basket", Zones = { 5, 7 }, Stats = { Regen = 0.01, RegenStart = 1 },
		Colors = { Main = rgb(196, 160, 96), Trim = rgb(120, 86, 46) }, Desc = "A wandering monk's basket hat. Breathe; mend." },
	{ Id = "shadow_cowl", Name = "Shadow Cowl", Shape = "Cowl", Zones = { 5, 8 }, Stats = { Speed = 0.06, Crit = 0.04 },
		Colors = { Main = rgb(30, 22, 48), Trim = rgb(170, 90, 255) }, Desc = "Woven from the Shadow Forest's dusk." },
	{ Id = "ember_crown", Name = "Ember Crown", Shape = "Crown", Zones = { 6, 8 }, Stats = { Damage = 0.1, Haste = 0.04 },
		Colors = { Main = rgb(232, 170, 60), Trim = rgb(255, 110, 30) }, Desc = "Forged in the Volcanic Fortress. Still burning." },
	{ Id = "dragon_helm", Name = "Dragon Helm", Shape = "Dragon", Zones = { 6, 8 }, Stats = { Health = 0.15, Damage = 0.06 },
		Colors = { Main = rgb(40, 110, 70), Trim = rgb(232, 186, 70), Accent = rgb(255, 120, 40) }, Desc = "Scaled and horned like the beast itself." },
	{ Id = "storm_halo", Name = "Raijin Drum Halo", Shape = "DrumHalo", Zones = { 7, 8 }, Stats = { Haste = 0.08, Damage = 0.06 },
		Colors = { Main = rgb(200, 150, 70), Trim = rgb(232, 186, 70), Accent = rgb(120, 230, 255) }, Desc = "The thunder god's drums beat with your strikes." },
	{ Id = "celestial_circlet", Name = "Celestial Circlet", Shape = "Circlet", Zones = { 7, 8 }, Stats = { XP = 0.12, Luck = 0.1 },
		Colors = { Main = rgb(255, 220, 110), Trim = rgb(250, 250, 255), Accent = rgb(120, 220, 255) }, Desc = "Sky Temple gold, light as a feather." },
	{ Id = "shogun_helm", Name = "Shogun Helm", Shape = "Shogun", Zones = { 7, 8 }, Stats = { Health = 0.2, Damage = 0.08 },
		Colors = { Main = rgb(26, 24, 30), Trim = rgb(255, 200, 60), Accent = rgb(190, 30, 40) }, Desc = "Worn by those who command armies." },
	{ Id = "void_crown", Name = "Void Crown", Shape = "VoidCrown", Zones = { 8, 8 }, Stats = { Damage = 0.15, Crit = 0.06, LifeSteal = 1 },
		Colors = { Main = rgb(24, 16, 36), Trim = rgb(190, 90, 255), Accent = rgb(255, 120, 255) }, Desc = "It floats. It hungers. It's yours." },
}
Hats.ById = {}
for i, def in ipairs(Hats.List) do
	def.Order = i
	Hats.ById[def.Id] = def
end

function Hats.Get(id: string?)
	return if id then Hats.ById[id] else nil
end

-- ===== rolling (server) =====
-- Roll multiplier from item level: about 0.63 at Lv 1, 1 at Lv 60, 2 at Lv 545.
function Hats.LevelScale(itemLevel: number): number
	return 0.6 + 1.4 * math.clamp(itemLevel / Hats.MaxItemLevel, 0, 1) ^ 0.6
end

local function weightedPick(list: { any }, weightOf: (any) -> number, rng: Random): any
	local total = 0
	for _, item in ipairs(list) do
		total += weightOf(item)
	end
	if total <= 0 then
		return list[1]
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

function Hats.RollRarity(luck: number, boss: boolean, rng: Random)
	luck = math.max(0, luck or 0)
	return weightedPick(Hats.Rarities, function(r)
		return (if boss then r.BossWeight else r.Weight) * (1 + luck * r.LuckK)
	end, rng)
end

-- Bases that drop in a given area index (falls back to the nearest band).
function Hats.BasesForZone(zoneIndex: number): { any }
	local out = {}
	for _, def in ipairs(Hats.List) do
		if zoneIndex >= def.Zones[1] and zoneIndex <= def.Zones[2] then
			table.insert(out, def)
		end
	end
	if #out == 0 then
		table.insert(out, Hats.List[1])
	end
	return out
end

local function round(v: number, step: number): number
	return math.floor(v / step + 0.5) * step
end

function Hats.RollAffix(def, scale: number, rng: Random): number
	local v = (def.Min + (def.Max - def.Min) * rng:NextNumber()) * scale
	if def.Kind == "Life" then
		return math.max(1, math.floor(v + 0.5))
	elseif def.Kind == "Seconds" then
		return math.max(0.1, round(v, 0.1))
	elseif def.Kind == "Regen" then
		return math.max(0.001, round(v, 0.001))
	end
	return math.max(0.005, round(v, 0.005))
end

-- A brand new hat record. zoneIndex picks the base, itemLevel scales the rolls.
-- rarityName / baseId force them (admin drops, tests).
function Hats.Roll(zoneIndex: number, itemLevel: number, luck: number, boss: boolean, rng: Random?, rarityName: string?, baseId: string?)
	local r = rng or Random.new()
	local rarity = if rarityName and Hats.RarityByName[rarityName] then Hats.RarityByName[rarityName] else Hats.RollRarity(luck, boss, r)
	local bases = Hats.BasesForZone(zoneIndex)
	local base = Hats.ById[baseId or ""] or bases[r:NextInteger(1, #bases)]
	local level = math.clamp(math.floor(itemLevel), 1, Hats.MaxItemLevel)
	local scale = Hats.LevelScale(level) * rarity.Roll
	local hat: any = { Id = base.Id, R = rarity.Name, L = level, A = {} }
	local pool = table.clone(Hats.Affixes)
	local count = r:NextInteger(rarity.Affixes[1], rarity.Affixes[2])
	for _ = 1, math.min(count, #pool) do
		local def = table.remove(pool, r:NextInteger(1, #pool))
		table.insert(hat.A, { K = def.Id, V = Hats.RollAffix(def, scale, r) })
	end
	table.sort(hat.A, function(a, b)
		return Hats.AffixById[a.K].Order < Hats.AffixById[b.K].Order
	end)
	if rarity.Proc then
		local proc = Hats.Procs[r:NextInteger(1, #Hats.Procs)]
		local chance = (proc.Min + (proc.Max - proc.Min) * r:NextNumber()) * (0.85 + 0.15 * Hats.LevelScale(level))
		if rarity.Name == "Mythic" then
			chance *= 1.4
		end
		hat.P = { S = proc.Skill, C = math.max(0.01, round(chance, 0.005)) }
	end
	return hat
end

-- True when a saved record is well formed (old or hand-edited saves).
function Hats.Valid(hat: any): boolean
	return type(hat) == "table" and Hats.ById[hat.Id] ~= nil and Hats.RarityByName[hat.R] ~= nil
		and type(hat.L) == "number" and type(hat.A) == "table"
end

-- ===== reading a hat =====
function Hats.Name(hat): string
	local base = Hats.ById[hat.Id]
	if not base then
		return "Unknown Hat"
	end
	local m = Mutations.Get(hat.M) -- a Mutation Machine mutation prefixes the name
	if m then
		return m.Name .. " " .. Hats.BaseName(hat)
	end
	return Hats.BaseName(hat)
end

function Hats.BaseName(hat): string
	local base = Hats.ById[hat.Id]
	local rarity = Hats.Rarity(hat.R)
	local a1 = hat.A[1] and Hats.AffixById[hat.A[1].K]
	local a2 = hat.A[2] and Hats.AffixById[hat.A[2].K]
	local proc = hat.P and Hats.ProcBySkill[hat.P.S]
	if rarity.Name == "Common" or not a1 then
		return base.Name
	elseif rarity.Name == "Legendary" and proc then
		return base.Name .. " " .. proc.Suffix
	elseif rarity.Name == "Mythic" and proc then
		return proc.Prefix .. " " .. base.Name .. " " .. a1.Suffix
	elseif a2 then
		return a1.Prefix .. " " .. base.Name .. " " .. a2.Suffix
	end
	return a1.Prefix .. " " .. base.Name
end

local function pct(v: number): string
	local p = v * 100
	if math.abs(p - math.floor(p + 0.5)) < 0.05 then
		return string.format("%d%%", math.floor(p + 0.5))
	end
	return string.format("%.1f%%", p)
end
Hats.Pct = pct

-- One line of tooltip text for a stat value ("+6% Damage", "+2 Life Steal (heals 2% HP per kill)").
function Hats.StatText(key: string, value: number): string
	local def = Hats.AffixById[key]
	if not def then
		return key
	end
	local sign = if value < 0 then "-" else "+"
	local v = math.abs(value)
	if def.Kind == "Regen" then
		return string.format("%s%s Max HP Regen per second", sign, pct(v))
	elseif def.Kind == "Seconds" then
		return string.format("Regen starts %.1fs %s", v, if value >= 0 then "sooner" else "later")
	elseif def.Kind == "Life" then
		return string.format("%s%d Life Steal (heal %d%% HP per kill)", sign, v, v)
	end
	return string.format("%s%s %s", sign, pct(v), def.Name)
end

function Hats.ProcText(proc): string
	local skill = Skills.Get(proc.S)
	local skillName = if skill then skill.Name else proc.S
	return string.format("%s chance on hit to cast %s", pct(proc.C), skillName)
end

-- Every stat a hat gives, base + affixes: { [statKey] = value, Procs = { { Skill, Chance } } }.
function Hats.Bonus(hat)
	local out: any = { Procs = {} }
	if not hat or not Hats.Valid(hat) then
		return out
	end
	for key, value in pairs(Hats.ById[hat.Id].Stats) do
		out[key] = (out[key] or 0) + value
	end
	for _, a in ipairs(hat.A) do
		if Hats.AffixById[a.K] and type(a.V) == "number" then
			out[a.K] = (out[a.K] or 0) + a.V
		end
	end
	if type(hat.P) == "table" and Hats.ProcBySkill[hat.P.S] and type(hat.P.C) == "number" then
		table.insert(out.Procs, { Skill = hat.P.S, Chance = math.clamp(hat.P.C, 0, 1) })
	end
	-- a mutation (Mutation Machine) multiplies every stat and the proc chance
	local m = Mutations.Get(hat.M)
	if m and m.HatMult then
		for key, value in pairs(out) do
			if type(value) == "number" then
				out[key] = value * m.HatMult
			end
		end
		for _, proc in ipairs(out.Procs) do
			proc.Chance = math.min(1, proc.Chance * m.HatMult)
		end
	end
	return out
end

-- The equipped hat's record (or nil).
function Hats.Equipped(data)
	local uid = data.EquippedHat
	local hats = data.Hats
	if type(uid) ~= "string" or uid == "" or type(hats) ~= "table" then
		return nil
	end
	local hat = hats[uid]
	return if Hats.Valid(hat) then hat else nil
end

-- Folds the equipped hat into the derived stats (called from Stats.Compute).
function Hats.ApplyToStats(stats, data, Balance)
	local b = Hats.Bonus(Hats.Equipped(data))
	stats.Damage = math.floor(stats.Damage * (1 + (b.Damage or 0)))
	stats.CritChance += b.Crit or 0
	stats.MaxHealth = math.floor(stats.MaxHealth * (1 + (b.Health or 0)))
	stats.WalkSpeed *= 1 + (b.Speed or 0)
	stats.AttackInterval = math.max(Balance.MinAttackInterval, stats.AttackInterval / (1 + (b.Haste or 0)))
	stats.XPMult *= 1 + (b.XP or 0)
	stats.CoinMult *= 1 + (b.Coins or 0)
	stats.Luck += b.Luck or 0
	stats.HealthRegen = (stats.HealthRegen or Balance.HealthRegen or 0.03) + (b.Regen or 0)
	stats.RegenDelay = math.max(Hats.MinRegenDelay, (stats.RegenDelay or Balance.RegenDelay or 5) - (b.RegenStart or 0))
	stats.LifeSteal = math.min(Hats.LifeStealCap, b.LifeSteal or 0)
	stats.HatProcs = b.Procs
	return stats
end

-- Coins (at the hat's item level) and Shards for salvaging it. Needs Balance.EnemyCoins.
function Hats.SalvageValue(hat, Balance): (number, number)
	local rarity = Hats.Rarity(hat.R)
	return math.max(1, math.floor(Balance.EnemyCoins(hat.L or 1) * rarity.Salvage.Kills)), rarity.Salvage.Shards
end

return Hats
