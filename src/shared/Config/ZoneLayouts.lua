--[[
	ZoneLayouts: the land shape of each area, used by shared/Landscape.lua.
	Coordinates are zone-local studs from the zone centre (x along the row of
	zones, z across it); heights are studs above Zones.GroundY. The entrance gate
	is at (-Zones.Spacing/2, 0) and the exit gate at (+Zones.Spacing/2, 0), both at
	height 0. Camp positions come from Config/Zones (camp.Offset); keep plateaus
	under the camps when you move them.

	  Road         main road nodes {x, z, height} from the west gate to the east gate
	  Roads        extra roads (e.g. the climb to the arena); a nil first height
	               means "start at the main road's height"
	  CampHeights  height of each camp's flat fighting ground (Zones camp order)
	  Boss         boss arena centre (Vector2), BossHeight its height
	  Spawn / Egg / Board  spawn x, egg stand and leaderboard positions
	  Plateaus     {x, z, radius, height, blend} flat-topped rises
	  Hills        {x, z, radius, height} rounded lookout rises
	  Open         {x, z, radius} extra open ground (widens the valley)
	  Ponds        {x, z, radius, depth, waterHeight}
	  Box          {x, z, halfX, halfZ, cornerRadius} a squarish valley (the village)
	  Roll         size of the rolling swells; Scale multiplies every height
	  CliffHeight / CliffWidth / EdgeNoise  the ridge around the valley
	  Alt          second ground material for patches (must be a terrain material)

	Every camp, the arena and the egg get a branch road from the main road
	automatically unless a road already reaches them.
]]

local v2 = Vector2.new

local function mirror(t)
	local function flip(list)
		local out = {}
		for i, n in ipairs(list) do
			local c = table.clone(n)
			c[2] = -c[2]
			out[i] = c
		end
		return out
	end
	local m = table.clone(t)
	m.Road = flip(t.Road)
	m.Roads = {}
	for i, r in ipairs(t.Roads or {}) do
		m.Roads[i] = flip(r)
	end
	for _, key in ipairs({ "Plateaus", "Hills", "Open", "Ponds" }) do
		if t[key] then
			m[key] = flip(t[key])
		end
	end
	m.Boss = v2(t.Boss.X, -t.Boss.Y)
	m.Egg = v2(t.Egg.X, -t.Egg.Y)
	return m
end

local function with(base, extra)
	local t = table.clone(base)
	for k, v in pairs(extra) do
		t[k] = v
	end
	return t
end

-- Valley A: low meadow camp, a terrace camp across the road, a rise camp, arena on a high plateau.
local A = {
	Egg = v2(-200, -40),
	Road = {
		{ -280, 0, 0 }, { -236, 0, 0 }, { -190, 14, 0 }, { -140, 40, 1 }, { -85, 30, 3 }, { -40, -5, 6 }, { 10, -30, 10 },
		{ 70, -20, 10 }, { 120, 20, 8 }, { 170, 30, 5 }, { 215, 15, 2 }, { 248, 0, 0 }, { 280, 0, 0 },
	},
	Roads = { { { 70, -20, 10 }, { 95, -75, 16 }, { 130, -108, 22 }, { 175, -140, 26 } } },
	CampHeights = { 3, 14, 8 },
	Boss = v2(175, -140),
	BossHeight = 26,
	Plateaus = { { 175, -140, 62, 26, 34 }, { 0, -120, 60, 14, 30 }, { 135, 110, 55, 8, 26 } },
	Hills = { { -60, -160, 45, 18 }, { -200, -150, 40, 14 }, { 40, 175, 50, 20 }, { -30, 140, 35, 12 }, { 225, -205, 32, 12 } },
	Open = { { -180, -90, 50 }, { 60, 60, 55 }, { 210, 90, 45 }, { 70, -195, 45 }, { -40, 190, 45 }, { -200, 120, 45 } },
	Ponds = { { -205, 115, 20, 5, 0 } },
}

-- Valley B: the road snakes the other way; the top camp sits on a high terrace.
local B = {
	Egg = v2(-200, 40),
	Road = {
		{ -280, 0, 0 }, { -236, 0, 0 }, { -180, -20, 0 }, { -120, -30, 1 }, { -60, 0, 3 }, { -10, 40, 6 }, { 50, 40, 9 },
		{ 100, 0, 12 }, { 150, -20, 14 }, { 200, 10, 8 }, { 245, 0, 1 }, { 280, 0, 0 },
	},
	Roads = { { { 50, 40, 9 }, { 75, 95, 15 }, { 115, 128, 22 }, { 170, 150, 28 } } },
	CampHeights = { 2, 12, 18 },
	Boss = v2(170, 150),
	BossHeight = 28,
	Plateaus = { { 170, 150, 60, 28, 34 }, { 150, -108, 58, 18, 30 }, { 10, 120, 55, 12, 28 } },
	Hills = { { -40, -150, 45, 18 }, { -190, 140, 40, 14 }, { 60, -175, 45, 20 }, { -60, 140, 35, 12 }, { 225, -175, 35, 14 } },
	Open = { { -190, -110, 50 }, { -170, 120, 45 }, { 60, -70, 50 }, { 225, 80, 45 }, { 50, 195, 40 }, { -50, -200, 40 } },
	Ponds = { { -30, -70, 18, 4.5, 0 } },
}

-- Valley C: a long climb; the arena crowns the highest plateau.
local C = {
	Egg = v2(-200, 40),
	Road = {
		{ -280, 0, 0 }, { -236, 0, 0 }, { -185, -15, 0 }, { -130, 10, 2 }, { -80, 0, 4 }, { -40, -20, 6 }, { 20, -10, 8 },
		{ 60, 30, 12 }, { 100, 40, 14 }, { 150, 20, 12 }, { 200, 30, 8 }, { 240, 10, 3 }, { 280, 0, 0 },
	},
	Roads = { { { 150, 20, 12 }, { 140, -45, 18 }, { 165, -90, 26 }, { 190, -130, 32 } } },
	CampHeights = { 4, 10, 20 },
	Boss = v2(190, -130),
	BossHeight = 32,
	Plateaus = { { 190, -130, 60, 32, 36 }, { -10, -115, 55, 10, 28 }, { 112, 118, 55, 20, 30 } },
	Hills = { { -80, -155, 45, 20 }, { -200, -140, 40, 15 }, { -50, 140, 40, 16 }, { 30, 190, 40, 14 }, { 215, 165, 35, 16 } },
	Open = { { -180, -110, 50 }, { 40, -70, 50 }, { 225, 90, 40 }, { -60, 60, 40 }, { -200, 120, 45 }, { -60, -215, 40 } },
}

local M = Enum.Material

return {
	-- The starting village keeps its flat square; a short winding pass leads to the first gate.
	village = {
		Spawn = -130,
		Egg = v2(-105, -38),
		Board = v2(-110, 36),
		Boss = v2(70, 105),
		Box = { 0, 0, 160, 160, 26 },
		Road = { { -170, 0, 0 }, { 150, 0, 0 }, { 196, 12, 2 }, { 240, -6, 2 }, { 280, 0, 0 } },
		Open = { { 214, 2, 30 } },
		Ponds = { { -35, 118, 17, 4.5, 0 } },
		Roll = 0,
		EdgeNoise = 7,
		CliffHeight = 38,
		CliffWidth = 24,
		Alt = M.LeafyGrass,
	},
	bamboo = with(A, { Roll = 7, Alt = M.Grass }),
	samurai = with(B, { Roll = 4, Alt = M.Grass }),
	demon = with(C, { Roll = 8, Alt = M.Basalt }),
	shadow = with(mirror(A), { Roll = 7, Ponds = false }),
	volcanic = with(mirror(B), { Roll = 9, Scale = 1.15, CliffHeight = 54, Alt = M.Rock, Ponds = false }),
	sky = with(mirror(C), { Roll = 8, Scale = 1.3, CliffHeight = 56, Alt = M.Glacier }),
	void = with(A, { Roll = 6, Scale = 1.1, EdgeNoise = 16, Ponds = false }),
}
