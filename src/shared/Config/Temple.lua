--[[
	The Cursed Temple: the hardcore endgame, a tower you descend floor by floor
	(TempleService runs it; the temple zone in Config/Zones holds its entrance).

	Each run is your own: the gate in the ruined temple puts you in a sealed chamber
	deep below the valley. Kill every monster on the floor and the seal in the middle
	opens; step on it to go down. Monsters start at Level 550 (BaseLevel) and get
	LevelPerFloor levels stronger every floor, with bigger packs and more brutes the
	deeper you go. Every 10th floor is a boss floor. Dying, leaving or logging out ends
	the run.

	Checkpoints: reach floor 11, 21, ... and you may start later runs there.
	Rewards: the kills themselves (XP, Coins, loot, charms at CharmBoost x the usual rate)
	plus a floor-clear bonus of Spirit Shards and Coins that grows with depth, and a
	big one for each boss floor. Your deepest floor is saved (data.TempleBest).
]]

local Temple = {}

Temple.Floors = 100
Temple.BaseLevel = 550 -- above the temple area itself (Lv 500)
Temple.LevelPerFloor = 5 -- floor 100 monsters are Level 1045
Temple.CheckpointEvery = 10
Temple.CharmBoost = 2 -- charm drop chance inside the temple
Temple.Aggro = 70 -- temple monsters spot you from across the chamber

-- The chamber: a square hall ChamberSize studs across, Depth studs below the zone's
-- ground. Runs get their own hall on a grid of Lanes x Lanes under the valley.
Temple.Depth = 230
Temple.ChamberSize = 96
Temple.Lanes = 5
Temple.LaneSpacing = 104

-- Monsters by depth: each band adds tougher kinds to the pool.
Temple.Pools = {
	{ From = 1, Enemies = { "CursedMonk", "TempleGhoul", "HexWisp" } },
	{ From = 11, Enemies = { "CursedMonk", "TempleGhoul", "HexWisp", "HollowSamurai" } },
	{ From = 31, Enemies = { "TempleGhoul", "HexWisp", "HollowSamurai", "CursedOni" } },
	{ From = 61, Enemies = { "HexWisp", "HollowSamurai", "CursedOni" } },
}

-- Boss floors (10, 20, ... 100): the bosses of the world, then the Abbot at the bottom.
Temple.Bosses = {
	"BanditKing", "AncientSamurai", "IronShogun", "DemonLord", "ShadowMaster",
	"MagmaWarlord", "StormKami", "VoidEmperor", "CursedAbbot", "CursedAbbot",
}

function Temple.Level(floor: number): number
	return Temple.BaseLevel + (math.clamp(floor, 1, Temple.Floors) - 1) * Temple.LevelPerFloor
end

function Temple.IsBossFloor(floor: number): boolean
	return floor % Temple.CheckpointEvery == 0
end

function Temple.BossFor(floor: number): string
	return Temple.Bosses[math.clamp(math.floor(floor / Temple.CheckpointEvery), 1, #Temple.Bosses)]
end

-- How many monsters a floor holds (a boss floor: the boss plus a few guards).
function Temple.Count(floor: number): number
	if Temple.IsBossFloor(floor) then
		return 2 + math.floor(floor / 25)
	end
	return math.min(24, 7 + math.floor(floor / 6))
end

-- Health / damage on top of the level: deeper floors are meaner than the level says.
function Temple.Mods(floor: number): (number, number)
	return 1 + floor * 0.02, 1 + floor * 0.012
end

function Temple.Pool(floor: number): { string }
	local pool = Temple.Pools[1].Enemies
	for _, band in ipairs(Temple.Pools) do
		if floor >= band.From then
			pool = band.Enemies
		end
	end
	return pool
end

-- Floors a run may start on: 1 and every checkpoint (11, 21, ...) up to the best reached.
function Temple.StartFloors(best: number): { number }
	local out = { 1 }
	local f = Temple.CheckpointEvery + 1
	while f <= math.min(best, Temple.Floors) do
		table.insert(out, f)
		f += Temple.CheckpointEvery
	end
	return out
end

-- Floor-clear reward: Shards, and Coins as kills' worth at the floor's level.
function Temple.Reward(floor: number): (number, number)
	local shards = 2 + math.floor(floor / 5)
	local kills = 6 + floor * 0.2
	if Temple.IsBossFloor(floor) then
		shards *= 4
		kills *= 3
	end
	return shards, kills
end

return Temple
