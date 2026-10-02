--[[
	Landscape: the shape of every zone's land, as pure math so the server (terrain,
	props, bounds) and the client (Zones.WorldPosition) agree on it.

	Each zone is a valley carved out of a ridge. The valley is the smooth union of
	circles and capsules around its roads, camps, arena, spawn and open meadows
	(Config/ZoneLayouts), with a noisy, meandering edge. Inside, the ground rolls
	gently and rises into plateaus and hills; roads and pads (camps, arena, spawn,
	egg, gates) are graded flat at their own heights. Outside, cliffs climb into a
	terraced ridge.

	Everything is in zone-local studs (x along the zone row, z across it).
	Zones.lua compiles each zone once at load (Landscape.Compile).
]]

local Landscape = {}

local sqrt, abs, floor, min, max = math.sqrt, math.abs, math.floor, math.min, math.max

-- Global defaults the zone edges blend into, so neighbouring zones meet seamlessly.
local EDGE_ROLL = 5
local EDGE_CLIFF_HEIGHT = 46
local EDGE_CLIFF_WIDTH = 30
local EDGE_SDF = 40
local UNION_K = 26

Landscape.MainRoadHalfWidth = 9
Landscape.BranchHalfWidth = 5

-- ------------------------------------------------------------------ noise

-- Lattice values from a fixed shuffled table (fast, and identical on server and client).
local PERM, VALUE = {}, {}
do
	local state = 12345
	local function nextRandom(): number
		state = (state * 16807) % 2147483647
		return state / 2147483647
	end
	for i = 1, 256 do
		PERM[i] = i - 1
		VALUE[i] = nextRandom()
	end
	for i = 256, 2, -1 do
		local j = math.floor(nextRandom() * i) + 1
		PERM[i], PERM[j] = PERM[j], PERM[i]
	end
	for i = 1, 256 do
		PERM[i + 256] = PERM[i]
	end
end

-- Smooth value noise in -1..1.
local function noise(x: number, z: number, seed: number): number
	local ix, iz = floor(x), floor(z)
	local fx, fz = x - ix, z - iz
	local ux = fx * fx * (3 - 2 * fx)
	local uz = fz * fz * (3 - 2 * fz)
	local px = (ix + seed * 31) % 256 + 1
	local qz = iz % 256
	local p0, p1 = PERM[px], PERM[px + 1]
	local a = VALUE[(p0 + qz) % 256 + 1]
	local b = VALUE[(p1 + qz) % 256 + 1]
	local c = VALUE[(p0 + qz + 1) % 256 + 1]
	local d = VALUE[(p1 + qz + 1) % 256 + 1]
	return (a + (b - a) * ux + (c - a) * uz + (a - b - c + d) * ux * uz) * 2 - 1
end

local function fbm(x: number, z: number, seed: number, octaves: number): number
	local sum, amp, norm = 0, 1, 0
	for o = 1, octaves do
		sum += noise(x, z, seed + o * 17) * amp
		norm += amp
		amp *= 0.5
		x *= 2.03
		z *= 2.03
	end
	return sum / norm
end
Landscape.Noise = noise
Landscape.Fbm = fbm

local function smoothstep(e0: number, e1: number, x: number): number
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end
Landscape.Smoothstep = smoothstep

local function smin(a: number, b: number, k: number): number
	local h = max(k - abs(a - b), 0) / k
	return min(a, b) - h * h * k * 0.25
end

local function segment(px: number, pz: number, ax: number, az: number, dx: number, dz: number, len2: number): (number, number)
	local t = math.clamp(((px - ax) * dx + (pz - az) * dz) / len2, 0, 1)
	local ex, ez = px - (ax + dx * t), pz - (az + dz * t)
	return sqrt(ex * ex + ez * ez), t
end

-- ------------------------------------------------------------------ compile

local function newSeg(ax, az, ha, bx, bz, hb, hw)
	local dx, dz = bx - ax, bz - az
	return { ax = ax, az = az, ha = ha, hb = hb, dx = dx, dz = dz, len2 = max(dx * dx + dz * dz, 1e-6), hw = hw }
end

-- Fills nil heights along a node list by interpolating between known ones.
local function fillHeights(nodes)
	local n = #nodes
	local dist = { 0 }
	for i = 2, n do
		local a, b = nodes[i - 1], nodes[i]
		dist[i] = dist[i - 1] + sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
	end
	for i = 1, n do
		if nodes[i][3] == nil then
			local lo, hi
			for j = i - 1, 1, -1 do
				if nodes[j][3] ~= nil then
					lo = j
					break
				end
			end
			for j = i + 1, n do
				if nodes[j][3] ~= nil then
					hi = j
					break
				end
			end
			local h
			if lo and hi then
				h = nodes[lo][3] + (nodes[hi][3] - nodes[lo][3]) * (dist[i] - dist[lo]) / max(dist[hi] - dist[lo], 1e-6)
			else
				h = if lo then nodes[lo][3] elseif hi then nodes[hi][3] else 0
			end
			nodes[i] = { nodes[i][1], nodes[i][2], h }
		end
	end
	return nodes
end

-- Nearest point on a set of segments: distance, x, z, height.
local function nearestOnSegs(segs, px, pz)
	local best, bx, bz, bh = math.huge, 0, 0, 0
	for _, s in ipairs(segs) do
		local d, t = segment(px, pz, s.ax, s.az, s.dx, s.dz, s.len2)
		if d < best then
			best, bx, bz, bh = d, s.ax + s.dx * t, s.az + s.dz * t, s.ha + (s.hb - s.ha) * t
		end
	end
	return best, bx, bz, bh
end

--[[
	Builds zone.Land from zone.Layout and the zone's camps/boss/spawn/egg.
	spacing: centre-to-centre distance of zones (the zone's strip is spacing wide)
	depth: how far the land reaches across the row (-depth/2 .. depth/2)
]]
function Landscape.Compile(zone, spacing: number, depth: number, isFirst: boolean, isLast: boolean)
	local layout = zone.Layout or {}
	local H = spacing / 2
	local scale = layout.Scale or 1
	local L = {
		H = H,
		D = depth / 2,
		Roll = layout.Roll or 6,
		CliffHeight = layout.CliffHeight or EDGE_CLIFF_HEIGHT,
		CliffWidth = layout.CliffWidth or EDGE_CLIFF_WIDTH,
		EdgeNoise = layout.EdgeNoise or 12,
		cx = zone.Center.X,
		cz = zone.Center.Z,
		Segs = {}, -- every road segment
		MainSegs = {}, -- the main road only
		Main = {}, -- main road nodes {x, z, h}
		Pads = {},
		Plateaus = {},
		Hills = {},
		Ponds = {},
		Prims = {},
		Gates = {},
	}
	zone.Land = L

	local function pad(kind: string, x: number, z: number, r: number, h: number, valley: number?)
		local p = { Kind = kind, x = x, z = z, r = r, h = h }
		table.insert(L.Pads, p)
		if valley then
			table.insert(L.Prims, { k = 1, x = x, z = z, r = valley })
		end
		return p
	end

	-- gates sit at height 0 on the strip edges
	if not isFirst then
		table.insert(L.Gates, { x = -H, z = 0, dir = 1 })
		pad("Gate", -H, 0, 14, 0)
	end
	if not isLast then
		table.insert(L.Gates, { x = H, z = 0, dir = -1 })
		pad("Gate", H, 0, 14, 0)
	end

	local spawnX = zone.Spawn.X - zone.Center.X
	pad("Spawn", spawnX, 0, 20, (layout.SpawnHeight or 0) * scale, 42)
	pad("Egg", zone.EggOffset.X, zone.EggOffset.Y, 15, 0, 28)
	if zone.Index == 1 and zone.BoardOffset then
		pad("Board", zone.BoardOffset.X, zone.BoardOffset.Y, 13, 0, 24)
	end
	local campHeights = layout.CampHeights or {}
	for i, camp in ipairs(zone.Camps) do
		local p = pad("Camp", camp.Offset.X, camp.Offset.Y, camp.Radius + 16, (campHeights[i] or 0) * scale, camp.Radius + 56)
		p.Camp = i
	end
	pad("Boss", zone.BossOffset.X, zone.BossOffset.Y, 50, (layout.BossHeight or 0) * scale, 78)

	for _, f in ipairs(layout.Plateaus or {}) do
		table.insert(L.Plateaus, { x = f[1], z = f[2], r = f[3], h = f[4] * scale, blend = f[5] or 30 })
		table.insert(L.Prims, { k = 1, x = f[1], z = f[2], r = f[3] + 8 })
	end
	for _, f in ipairs(layout.Hills or {}) do
		table.insert(L.Hills, { x = f[1], z = f[2], r = f[3], h = f[4] * scale })
	end
	for _, f in ipairs(layout.Open or {}) do
		table.insert(L.Prims, { k = 1, x = f[1], z = f[2], r = f[3] })
	end
	if layout.Ponds then
		for _, f in ipairs(layout.Ponds) do
			local level = (f[5] or 0) * scale
			table.insert(L.Ponds, { x = f[1], z = f[2], r = f[3], depth = f[4], level = level })
			pad("Pond", f[1], f[2], f[3] + 4, level, f[3] + 16)
		end
	end
	if layout.Box then
		local b = layout.Box
		table.insert(L.Prims, { k = 3, x = b[1], z = b[2], hx = b[3], hz = b[4], rr = b[5] or 20 })
	end

	-- roads: main road first, then extra roads, then automatic branches to pads
	local function addRoad(nodes, hw: number, main: boolean)
		local list = {}
		for _, n in ipairs(nodes) do
			if not (isLast and n[1] > H - 50) and not (isFirst and n[1] < -H + 50) then
				table.insert(list, { n[1], n[2], if n[3] ~= nil then n[3] * scale else nil })
			end
		end
		fillHeights(list)
		for i = 2, #list do
			local a, b = list[i - 1], list[i]
			local s = newSeg(a[1], a[2], a[3], b[1], b[2], b[3], hw)
			table.insert(L.Segs, s)
			if main then
				table.insert(L.MainSegs, s)
			end
			table.insert(L.Prims, { k = 2, ax = s.ax, az = s.az, dx = s.dx, dz = s.dz, len2 = s.len2, r = if main then 24 else 17 })
		end
		if main then
			L.Main = list
		end
	end
	if layout.Road then
		addRoad(layout.Road, Landscape.MainRoadHalfWidth, true)
	end
	for _, nodes in ipairs(layout.Roads or {}) do
		local copy = table.clone(nodes)
		-- a road that starts on the main road takes the main road's height there
		if copy[1][3] == nil and #L.MainSegs > 0 then
			local _, _, _, h = nearestOnSegs(L.MainSegs, copy[1][1], copy[1][2])
			copy[1] = { copy[1][1], copy[1][2], h / scale }
		end
		addRoad(copy, Landscape.BranchHalfWidth + 1, false)
	end
	if #L.MainSegs > 0 then
		for _, p in ipairs(L.Pads) do
			if p.Kind == "Camp" or p.Kind == "Boss" or p.Kind == "Egg" then
				local d = nearestOnSegs(L.Segs, p.x, p.z)
				if d > p.r * 0.6 then
					local _, jx, jz, jh = nearestOnSegs(L.MainSegs, p.x, p.z)
					local hw = if p.Kind == "Boss" then Landscape.BranchHalfWidth + 1 else Landscape.BranchHalfWidth
					local s = newSeg(jx, jz, jh, p.x, p.z, p.h, hw)
					s.Branch = p.Kind
					table.insert(L.Segs, s)
					table.insert(L.Prims, { k = 2, ax = s.ax, az = s.az, dx = s.dx, dz = s.dz, len2 = s.len2, r = 17 })
				end
			end
		end
	end
	return L
end

-- ------------------------------------------------------------------ sampling

-- Signed distance to the valley edge (negative inside), before cliffs.
-- Also returns the edge blend (1 on the strip borders, where zones meet).
local function valley(L, x: number, z: number, wx: number, wz: number): (number, number)
	local s = 1e9
	for _, p in ipairs(L.Prims) do
		local d
		if p.k == 1 then
			local ex, ez = x - p.x, z - p.z
			d = sqrt(ex * ex + ez * ez) - p.r
		elseif p.k == 2 then
			d = segment(x, z, p.ax, p.az, p.dx, p.dz, p.len2) - p.r
		else
			local qx = abs(x - p.x) - p.hx + p.rr
			local qz = abs(z - p.z) - p.hz + p.rr
			local ox, oz = max(qx, 0), max(qz, 0)
			d = sqrt(ox * ox + oz * oz) + min(max(qx, qz), 0) - p.rr
		end
		if d < s + UNION_K then
			s = smin(s, d, UNION_K)
		end
	end
	local att = 1
	for _, g in ipairs(L.Gates) do
		local ex, ez = x - g.x, z - g.z
		att = min(att, math.clamp((sqrt(ex * ex + ez * ez) - 30) / 70, 0, 1))
	end
	s += L.EdgeNoise * fbm(wx / 90, wz / 90, 51, 3) * att
	local e = max(smoothstep(L.H - 40, L.H - 6, abs(x)), smoothstep(L.D - 40, L.D - 6, abs(z)))
	s += (EDGE_SDF - s) * e
	-- the pass through each gate is the same shape on both sides of the border
	for _, g in ipairs(L.Gates) do
		local d, t = segment(x, z, g.x, g.z, g.dir * 44, 0, 44 * 44)
		s = min(s, d - (15 + 12 * t))
	end
	return s, e
end

-- Cliff height and width around the valley at a world position (blended to the
-- shared defaults on the strip borders).
local function cliff(L, wx: number, wz: number, e: number): (number, number)
	local n1 = fbm(wx / 150, wz / 150, 31, 2) * 0.5 + 0.5
	local n2 = fbm(wx / 120, wz / 120, 37, 2) * 0.5 + 0.5
	local hgt = L.CliffHeight * (0.7 + 0.6 * n1)
	local wid = L.CliffWidth * (0.65 + 0.9 * n2)
	local eh = EDGE_CLIFF_HEIGHT * (0.7 + 0.6 * n1)
	local ew = EDGE_CLIFF_WIDTH * (0.65 + 0.9 * n2)
	return hgt + (eh - hgt) * e, wid + (ew - wid) * e
end


local function rectDistance(cx: number, cz: number, hx: number, hz: number, px: number, pz: number): number
	local dx = max(abs(px - cx) - hx, 0)
	local dz = max(abs(pz - cz) - hz, 0)
	return sqrt(dx * dx + dz * dz)
end

--[[
	The parts of a zone's land that can affect the rectangle x0..x1, z0..z1, for
	fast sampling there (pass it to Sample). Same results as sampling without it.
]]
function Landscape.Region(zone, x0: number, z0: number, x1: number, z1: number)
	local L = zone.Land
	local cx, cz, hx, hz = (x0 + x1) / 2, (z0 + z1) / 2, (x1 - x0) / 2, (z1 - z0) / 2
	local reach = sqrt(hx * hx + hz * hz)
	local R = setmetatable({ Prims = {}, Segs = {}, Pads = {}, Hills = {}, Plateaus = {}, Ponds = {} }, { __index = L })
	for _, f in ipairs(L.Hills) do
		if rectDistance(cx, cz, hx, hz, f.x, f.z) < f.r then
			table.insert(R.Hills, f)
		end
	end
	for _, f in ipairs(L.Plateaus) do
		if rectDistance(cx, cz, hx, hz, f.x, f.z) < f.r * 1.2 + f.blend then
			table.insert(R.Plateaus, f)
		end
	end
	for _, f in ipairs(L.Ponds) do
		if rectDistance(cx, cz, hx, hz, f.x, f.z) < f.r then
			table.insert(R.Ponds, f)
		end
	end
	for _, p in ipairs(L.Pads) do
		if rectDistance(cx, cz, hx, hz, p.x, p.z) < p.r + 60 then
			table.insert(R.Pads, p)
		end
	end
	for _, sg in ipairs(L.Segs) do
		if segment(cx, cz, sg.ax, sg.az, sg.dx, sg.dz, sg.len2) - reach < sg.hw + 62 then
			table.insert(R.Segs, sg)
		end
	end
	-- valley shapes: distances are 1-Lipschitz, so a shape whose nearest possible
	-- distance is beyond the best farthest distance + the blend can't matter
	local lows, best = {}, math.huge
	for i, p in ipairs(L.Prims) do
		local d
		if p.k == 1 then
			d = sqrt((cx - p.x) ^ 2 + (cz - p.z) ^ 2) - p.r
		elseif p.k == 2 then
			d = segment(cx, cz, p.ax, p.az, p.dx, p.dz, p.len2) - p.r
		else
			local qx = abs(cx - p.x) - p.hx + p.rr
			local qz = abs(cz - p.z) - p.hz + p.rr
			d = sqrt(max(qx, 0) ^ 2 + max(qz, 0) ^ 2) + min(max(qx, qz), 0) - p.rr
		end
		lows[i] = d - reach
		best = min(best, d + reach)
	end
	for i, p in ipairs(L.Prims) do
		if lows[i] < best + UNION_K then
			table.insert(R.Prims, p)
		end
	end
	return R
end

--[[
	Full sample at a zone-local position. Returns:
	  height, road (0..1, 1 on the road surface), edge sdf (negative inside the
	  valley), water level (or nil), pad (0..1, 1 on a flat pad), cliff width
	region (from Landscape.Region) speeds up many samples in one small area.
]]
function Landscape.Sample(zone, x: number, z: number, region: any?): (number, number, number, number?, number, number)
	local L = region or zone.Land
	local wx, wz = L.cx + x, L.cz + z
	local s, e = valley(L, x, z, wx, wz)

	-- rolling ground (world-space noise so zones meet seamlessly)
	local roll = L.Roll + (EDGE_ROLL - L.Roll) * e
	local h = roll * (fbm(wx / 130, wz / 130, 7, 3) + 0.35 * fbm(wx / 47, wz / 47, 9, 2))

	for _, f in ipairs(L.Hills) do
		local ex, ez = x - f.x, z - f.z
		local q = (ex * ex + ez * ez) / (f.r * f.r)
		if q < 1 then
			h += f.h * (1 - q) * (1 - q)
		end
	end
	for _, f in ipairs(L.Plateaus) do
		local ex, ez = x - f.x, z - f.z
		local d = sqrt(ex * ex + ez * ez)
		if d < f.r * 1.2 + f.blend then
			local r = f.r * (1 + 0.16 * noise(wx / 26, wz / 26, 61))
			local w = 1 - smoothstep(r, r + f.blend, d)
			h += (f.h - h) * w
		end
	end

	-- roads: graded to their own height, banks blend out (wider when the cut is deeper)
	local sumW, sumWH, maxW, road = 0, 0, 0, 0
	for _, sg in ipairs(L.Segs) do
		local d, t = segment(x, z, sg.ax, sg.az, sg.dx, sg.dz, sg.len2)
		local inner = sg.hw + 2
		if d < inner + 60 then
			local rh = sg.ha + (sg.hb - sg.ha) * t
			local w = 1 - smoothstep(inner, inner + min(6 + 2.4 * abs(h - rh), 60), d)
			if w > 0 then
				sumW += w
				sumWH += w * rh
				maxW = max(maxW, w)
				road = max(road, 1 - smoothstep(sg.hw - 1.5, sg.hw + 1, d))
			end
		end
	end
	if maxW > 0 then
		h += (sumWH / sumW - h) * maxW
	end

	-- flat pads (camps, arena, spawn, egg, gates, ponds)
	sumW, sumWH, maxW = 0, 0, 0
	for _, p in ipairs(L.Pads) do
		local ex, ez = x - p.x, z - p.z
		local d = sqrt(ex * ex + ez * ez)
		if d < p.r + 60 then
			local w = 1 - smoothstep(p.r, p.r + min(8 + 2.4 * abs(h - p.h), 60), d)
			if w > 0 then
				sumW += w
				sumWH += w * p.h
				maxW = max(maxW, w)
			end
		end
	end
	local padW = maxW
	if maxW > 0 then
		h += (sumWH / sumW - h) * maxW
	end

	local water
	for _, p in ipairs(L.Ponds) do
		local ex, ez = x - p.x, z - p.z
		local q = (ex * ex + ez * ez) / (p.r * p.r)
		if q < 1 then
			h -= p.depth * (1 - q) * (1 - q)
			water = p.level - 0.6
		end
	end

	-- cliffs and the terraced ridge outside the valley
	local cliffW = L.CliffWidth
	if s > 0 then
		local cliffH
		cliffH, cliffW = cliff(L, wx, wz, e)
		local k = smoothstep(0, cliffW, s)
		local r = cliffH * k + min(0.18 * max(s - cliffW, 0), 22)
		r += 6 * fbm(wx / 22, wz / 22, 41, 2) * k
		local q = max(r, 0) / 7
		local fl = floor(q)
		local terraced = 7 * (fl + smoothstep(0.55, 1, q - fl))
		h += r + (terraced - r) * 0.55
	end
	return h, road, s, water, padW, cliffW
end

function Landscape.Height(zone, x: number, z: number): number
	return (Landscape.Sample(zone, x, z))
end

-- Field whose zero contour is where the invisible bounds go: part way up the cliffs.
function Landscape.BoundField(zone, x: number, z: number, region: any?): number
	local L = region or zone.Land
	local wx, wz = L.cx + x, L.cz + z
	local s, e = valley(L, x, z, wx, wz)
	local _, cliffW = cliff(L, wx, wz, e)
	return s - 0.45 * cliffW
end

-- Edge sdf only (negative inside the valley), cheaper than a full sample.
function Landscape.Edge(zone, x: number, z: number, region: any?): number
	local L = region or zone.Land
	return (valley(L, x, z, L.cx + x, L.cz + z))
end

-- Points every `step` studs along the main road: { X, Z, Height, DirX, DirZ }.
function Landscape.RoadPoints(zone, step: number)
	local L = zone.Land
	local out = {}
	local carry = 0
	for _, s in ipairs(L.MainSegs) do
		local len = sqrt(s.len2)
		local ux, uz = s.dx / len, s.dz / len
		local t = carry
		while t < len do
			local f = t / len
			table.insert(out, { X = s.ax + s.dx * f, Z = s.az + s.dz * f, Height = s.ha + (s.hb - s.ha) * f, DirX = ux, DirZ = uz })
			t += step
		end
		carry = t - len
	end
	return out
end

-- Distance from a point to the nearest road (any road) and that road's half width.
function Landscape.RoadDistance(zone, x: number, z: number, mainOnly: boolean?): (number, number)
	local best, hw = math.huge, 0
	for _, s in ipairs(if mainOnly then zone.Land.MainSegs else zone.Land.Segs) do
		local d = segment(x, z, s.ax, s.az, s.dx, s.dz, s.len2)
		if d - s.hw < best - hw then
			best, hw = d, s.hw
		end
	end
	return best, hw
end

return Landscape
