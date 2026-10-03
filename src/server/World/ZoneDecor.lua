--[[
	Per-zone decoration and vegetation. Each function receives a context from
	WorldBuilder (all positions are zone-local studs; the ground is not flat):
	  ctx.Zone, ctx.Folder, ctx.Rng, ctx.Land (the compiled Landscape)
	  ctx.At(x, z, yaw?, sink?)        -> CFrame on the ground at a zone-local position
	  ctx.Height(x, z), ctx.Slope(x, z), ctx.Edge(x, z) (negative inside the valley)
	  ctx.IsClear(x, z, margin, opts?) -> free of roads, pads, cliffs and other props
	  ctx.Scatter(count, margin, fn(cf, x, z), opts?)   random clear spots
	  ctx.Groves(groves, per, spread, margin, fn, opts?) clusters of clear spots
	  ctx.RoadSide(step, offset, fn(cf, side, i), both?, radius?) beside the main road
	  ctx.Ridge(count, margin, fn(cf, x, z))             on the ridges past the cliffs
	  ctx.Claim(x, z, radius)                             reserve ground by hand
	opts: Edge (how far up the valley edge, studs), MaxSlope, Area = {x, z, r}, Sink.
	Add a new function here and set a zone's Decor field to its name.
]]

local Props = require(script.Parent.Props)
local Landscape = require(game:GetService("ReplicatedStorage").Shared.Landscape)
local Mutations = require(game:GetService("ReplicatedStorage").Shared.Config.Mutations)

local ZoneDecor = {}

local rgb = Color3.fromRGB

-- Ground frame on the main road near zone-local x, facing along the road.
local function roadFrame(ctx, x: number): CFrame
	local points = Landscape.RoadPoints(ctx.Zone, 3)
	local best = points[1]
	for _, p in ipairs(points) do
		if math.abs(p.X - x) < math.abs(best.X - x) then
			best = p
		end
	end
	local base = ctx.At(best.X, best.Z).Position
	return CFrame.lookAt(base, base + Vector3.new(best.DirX, 0, best.DirZ))
end

-- A gate arch spanning the road just inside the entrance.
local function entranceArch(ctx, build: (CFrame) -> ())
	local cf = roadFrame(ctx, -ctx.Land.H + 72)
	ctx.Claim(cf.Position.X - ctx.Zone.Center.X, cf.Position.Z - ctx.Zone.Center.Z, 4)
	build(cf)
end

-- A foundation block under a building so it never floats on sloped ground.
local function plinth(parent: Instance, cf: CFrame, sx: number, sz: number, color: Color3, material: Enum.Material?, depth: number?)
	local d = depth or 10
	Props.Part(parent, Vector3.new(sx, d, sz), cf * CFrame.new(0, -d / 2 + 0.6, 0), color, material or Enum.Material.Cobblestone)
end

-- A building on top of one of the layout's hills, with the ground around it reserved.
local function hillBuilding(ctx, index: number, radius: number, build: (CFrame) -> ())
	local hill = ctx.Land.Hills[index]
	if not hill then
		return
	end
	ctx.Claim(hill.x, hill.z, radius)
	build(ctx.At(hill.x, hill.z, ctx.Rng:NextNumber(-0.3, 0.3), 1))
end

-- ---------------------------------------------------------------- village

-- Kyoto (justin, 2026-10-02: "look at images of Kyoto Japan and base it off of that.
-- I want a lot more vegetation, like entire forests of trees. And I want cherry
-- blossoms in the first starting area").
--   spawn plaza under a great vermilion torii, ringed by cherry trees
--   Gion: the main street lined with machiya, strung with paper lanterns
--   Shirakawa: a stone-walled canal behind the south row, cherry trees and willows on its banks
--   Ninenzaka: the stone lane up past the Yasaka pagoda to the Kiyomizu stage on stilts
--   Kinkaku-ji: the golden pavilion over its mirror pond, with pine islands
--   Fushimi Inari: a tunnel of torii gates climbing to the boss shrine, guarded by foxes
--   a dojo and a raked-gravel zen garden by the training dummies
--   forests of cedar, maple and wild cherry on every hill and ridge round the basin

local VERMILION = rgb(232, 84, 32)

-- The extra roads of a layout (Roads), each as a list of {x, z, h} points every `step` studs.
local function extraRoads(ctx, step: number)
	local roads, current, last = {}, nil, nil
	for _, seg in ipairs(ctx.Land.Segs) do
		if not seg.Branch and not table.find(ctx.Land.MainSegs, seg) then
			if not current or not last or math.abs(seg.ax - last.X) > 0.5 or math.abs(seg.az - last.Z) > 0.5 then
				current = {}
				table.insert(roads, current)
			end
			local len = math.sqrt(seg.len2)
			local dir = Vector3.new(seg.dx, 0, seg.dz) / len
			for d = 0, len - 0.01, step do
				local t = d / len
				table.insert(current, { X = seg.ax + seg.dx * t, Z = seg.az + seg.dz * t, Dir = dir })
			end
			last = { X = seg.ax + seg.dx, Z = seg.az + seg.dz }
		end
	end
	return roads
end

-- The nearest clear spot to (x, z), searching outward up to `reach` studs.
local function findSpot(ctx, x: number, z: number, margin: number, opts: any?, reach: number?): (number?, number?)
	if ctx.IsClear(x, z, margin, opts) then
		return x, z
	end
	for r = 4, reach or 40, 4 do
		for k = 0, 11 do
			local a = k * math.pi / 6 + r
			local px, pz = x + math.cos(a) * r, z + math.sin(a) * r
			if ctx.IsClear(px, pz, margin, opts) then
				return px, pz
			end
		end
	end
	return nil, nil
end

local function cherry(ctx, cf: CFrame, opts: any?)
	local o = opts or {}
	o.Rng = ctx.Rng
	o.Petals = o.Petals or ctx.Rng:NextNumber() < 0.3
	Props.CherryTree(ctx.Folder, cf, o)
end

-- Kiyomizu-dera: the main hall on the hilltop and its wooden stage jutting out over
-- the slope on a lattice of tall pillars, with the vermilion three-storey pagoda beside it.
local function kiyomizu(ctx, x: number, z: number)
	local f = ctx.Folder
	local c = ctx.Zone.Center
	local top = ctx.Height(x, z)
	local deck = top + 4
	local wood = rgb(116, 80, 52)
	ctx.Claim(x, z, 24)
	ctx.Claim(x, z + 18, 22)
	-- hall on the top and the stage out over the slope in front (toward the valley = +z)
	local hall = CFrame.new(c.X + x, c.Y + deck, c.Z + z) * CFrame.Angles(0, math.pi, 0)
	plinth(f, hall, 32, 18, rgb(120, 112, 100), Enum.Material.Cobblestone, 16)
	Props.House(f, hall, { Width = 30, Depth = 16, Height = 10, Wall = rgb(214, 196, 160), Wood = wood, Roof = rgb(84, 66, 56), RoofHeight = 9, RoofTrim = rgb(60, 48, 40) })
	local stageZ = z + 18
	Props.Part(f, Vector3.new(34, 1.2, 18), CFrame.new(c.X + x, c.Y + deck - 0.6, c.Z + stageZ), rgb(150, 110, 72), Enum.Material.WoodPlanks)
	for _, side in ipairs({ { -17, 0, 0.4, 18 }, { 17, 0, 0.4, 18 }, { 0, 9, 34, 0.4 } }) do
		Props.Part(f, Vector3.new(side[3], 3, side[4]), CFrame.new(c.X + x + side[1], c.Y + deck + 1.5, c.Z + stageZ + side[2]), wood, Enum.Material.Wood)
	end
	for px = -15, 15, 6 do
		for pz = -7, 7, 4.6 do
			local wx, wz = x + px, stageZ + pz
			local ground = ctx.Height(wx, wz)
			local len = deck - ground + 2
			if len > 1.5 then
				Props.Part(f, Vector3.new(1.3, len, 1.3), CFrame.new(c.X + wx, c.Y + ground - 2 + len / 2, c.Z + wz), wood, Enum.Material.Wood)
			end
		end
	end
	-- nuki tie beams through the pillars every 7 studs down
	for y = deck - 6, math.min(ctx.Height(x, stageZ + 7), deck) + 2, -7 do
		for pz = -7, 7, 4.6 do
			Props.Part(f, Vector3.new(32, 0.7, 0.7), CFrame.new(c.X + x, c.Y + y, c.Z + stageZ + pz), wood:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.Wood)
		end
	end
	local px, pz = findSpot(ctx, x + 34, z + 2, 9, { Edge = 30, MaxSlope = 2, Road = 1 }, 24)
	if px and pz then
		ctx.Claim(px, pz, 10)
		local cf = ctx.At(px, pz, math.pi, 0.5)
		plinth(f, cf, 16, 16, rgb(120, 112, 100))
		Props.Pagoda(f, cf, 3, { Base = 12, Wall = VERMILION, Trim = rgb(245, 238, 222), Roof = rgb(64, 58, 56), Stone = rgb(120, 112, 100) })
	end
end

-- The Shirakawa canal: a straight stone-walled channel of terrain water at one level
-- from x0 to x1 along z, with stone slab bridges.
local function canal(ctx, x0: number, x1: number, z: number, bridges: { number })
	local f = ctx.Folder
	local c = ctx.Zone.Center
	local lowest = math.huge
	for x = x0, x1, 4 do
		if ctx.Edge(x, z) > -8 then
			return -- not inside the valley here: skip the canal
		end
		lowest = math.min(lowest, ctx.Height(x, z - 4), ctx.Height(x, z + 4))
	end
	local water = lowest - 1.4
	local len = x1 - x0
	local mid = Vector3.new(c.X + (x0 + x1) / 2, 0, c.Z + z)
	local terrain = workspace.Terrain
	terrain:FillBlock(CFrame.new(mid.X, c.Y + water + 6, mid.Z), Vector3.new(len, 16, 7), Enum.Material.Air)
	terrain:FillBlock(CFrame.new(mid.X, c.Y + water - 1.2, mid.Z), Vector3.new(len, 2.4, 7), Enum.Material.Water)
	terrain:FillBlock(CFrame.new(mid.X, c.Y + water - 4.4, mid.Z), Vector3.new(len, 4, 7), Enum.Material.Slate)
	local stone = rgb(132, 128, 120)
	for x = x0, x1 - 0.01, 8 do
		local seg = math.min(8, x1 - x)
		for _, side in ipairs({ -1, 1 }) do
			local bz = z + side * 4
			local ground = ctx.Height(x + seg / 2, bz)
			local h = ground - water + 3.2
			Props.Part(f, Vector3.new(seg, h, 1.2), CFrame.new(c.X + x + seg / 2, c.Y + water - 3 + h / 2, c.Z + bz), stone:Lerp(Color3.new(0, 0, 0), ctx.Rng:NextNumber(0, 0.12)), Enum.Material.Cobblestone)
		end
	end
	for x = x0, x1, 2 do
		ctx.Claim(x, z, 4.5)
	end
	-- a bridge wherever a road crosses, plus the footbridges asked for
	local spans = {}
	for _, bx in ipairs(bridges) do
		table.insert(spans, { bx, 5 })
	end
	for _, seg in ipairs(ctx.Land.Segs) do
		if math.abs(seg.dz) > 0.01 then
			local t = (z - seg.az) / seg.dz
			local bx = seg.ax + seg.dx * t
			if t >= 0 and t <= 1 and bx > x0 - 4 and bx < x1 + 4 then
				table.insert(spans, { bx, seg.hw * 2 + 1 })
			end
		end
	end
	for _, span in ipairs(spans) do
		local bx, width = span[1], span[2]
		local ground = math.max(ctx.Height(bx, z - 6), ctx.Height(bx, z + 6))
		local deck = CFrame.new(c.X + bx, c.Y + ground - 0.1, c.Z + z)
		Props.Part(f, Vector3.new(width, 0.8, 12), deck, rgb(150, 145, 136), Enum.Material.Slate)
		for sx = -1, 1, 2 do
			Props.Part(f, Vector3.new(0.4, 1.2, 9), deck * CFrame.new(sx * (width / 2 - 0.2), 0.9, 0), VERMILION, Enum.Material.Wood)
		end
	end
	return water
end

function ZoneDecor.Village(ctx)
	local f, rng = ctx.Folder, ctx.Rng
	local zone = ctx.Zone
	local spawnX = zone.Spawn.X - zone.Center.X

	-- ===== the Mutation Machine beside the spawn plaza (MutationService) =====
	local machine = Mutations.Machine.Offset
	ctx.Claim(machine.X, machine.Y, 10)
	local mcf = ctx.At(machine.X, machine.Y, 0, 0.3)
	Props.MutationMachine(f, CFrame.lookAt(mcf.Position, Vector3.new(zone.Spawn.X, mcf.Position.Y, zone.Spawn.Z)))

	-- ===== spawn plaza: the great torii over the road, cherry trees all round =====
	Props.Torii(f, roadFrame(ctx, spawnX + 34), 24, 26, VERMILION)
	ctx.Claim(spawnX + 34, -12, 3)
	ctx.Claim(spawnX + 34, 12, 3)
	for i = 0, 15 do
		local a = i * math.pi / 8 + rng:NextNumber(-0.1, 0.1)
		local r = rng:NextNumber(30, 38)
		local x, z = spawnX + math.cos(a) * r, math.sin(a) * r
		if ctx.IsClear(x, z, 5, { Road = 1 }) then
			ctx.Claim(x, z, 5)
			cherry(ctx, ctx.At(x, z, rng:NextNumber(0, 6)), { Height = rng:NextNumber(13, 17), Petals = i % 3 == 0 })
		end
	end
	for _, side in ipairs({ -1, 1 }) do
		Props.StoneLantern(f, ctx.At(spawnX + 24, side * 13, -side * math.pi / 2))
		ctx.Claim(spawnX + 24, side * 13, 2)
	end

	-- ===== Gion: machiya on both sides of the main street, lanterns strung across =====
	local function street(x0: number, x1: number)
		for _, side in ipairs({ -1, 1 }) do
			local x = x0
			while x < x1 do
				local w = rng:NextNumber(9.5, 12.5)
				local cx, cz = x + w / 2, side * 18.5
				if ctx.IsClear(cx, cz, 5, { Road = -3, Edge = -2 }) then
					ctx.Claim(cx, cz, w / 2)
					Props.Machiya(f, ctx.At(cx, cz, if side > 0 then 0 else math.pi, 0.3), { Width = w, Rng = rng, Light = (math.floor(x) % 3 == 0) })
				end
				x += w + 0.6
			end
		end
		for x = x0 + 10, x1 - 6, 22 do
			local a = ctx.At(x, -12.5).Position + Vector3.new(0, 14.5, 0)
			local b = ctx.At(x, 12.5).Position + Vector3.new(0, 14.5, 0)
			Props.LanternLine(f, a, b, rng)
		end
	end
	street(spawnX + 52, -78)
	Props.Sign(f, ctx.At(spawnX + 44, -13, math.pi / 2), "GION", "Ninja Village", rgb(255, 210, 200))

	-- ===== Shirakawa canal behind the south row =====
	if canal(ctx, -152, -82, -42, { -130, -100 }) then
		for x = -148, -84, 9 do
			if rng:NextNumber() < 0.75 then
				local tx, tz = x + rng:NextNumber(-1.5, 1.5), -42 - rng:NextNumber(8.5, 10)
				if ctx.IsClear(tx, tz, 3, { Road = 1 }) then
					ctx.Claim(tx, tz, 4)
					if rng:NextNumber() < 0.7 then
						cherry(ctx, ctx.At(tx, tz, rng:NextNumber(0, 6)), { Height = rng:NextNumber(11, 15), Weeping = rng:NextNumber() < 0.4 })
					else
						Props.Willow(f, ctx.At(tx, tz), rng)
					end
				end
			end
		end
		for x = -146, -88, 14 do
			if ctx.IsClear(x, -33, 2, { Road = -4 }) then
				ctx.Claim(x, -33, 2)
				Props.PaperLantern(f, ctx.At(x, -33, math.pi / 2), rgb(255, 205, 140))
			end
		end
	end

	-- ===== Ninenzaka lane, Yasaka pagoda, Kiyomizu stage =====
	local roads = extraRoads(ctx, 3)
	local boss = zone.BossOffset
	local toriiRoad, laneRoad
	for _, road in ipairs(roads) do
		local tail = road[#road]
		if tail and (tail.X - boss.X) ^ 2 + (tail.Z - boss.Y) ^ 2 < 70 ^ 2 then
			toriiRoad = road
		else
			laneRoad = road
		end
	end
	if laneRoad then
		for i, p in ipairs(laneRoad) do
			if i % 4 == 2 and i > 6 then
				for _, side in ipairs({ -1, 1 }) do
					local x, z = p.X - p.Dir.Z * 13 * side, p.Z + p.Dir.X * 13 * side
					if ctx.IsClear(x, z, 4.5, { Road = -2, MaxSlope = 0.9, Edge = 0 }) then
						ctx.Claim(x, z, 5.5)
						local base = ctx.At(x, z)
						local face = CFrame.lookAt(base.Position, base.Position - Vector3.new(-p.Dir.Z * side, 0, p.Dir.X * side))
						plinth(f, face, 11, 12, rgb(126, 120, 110))
						Props.Machiya(f, face, { Width = 9.5, Depth = 11, Rng = rng })
					end
				end
			elseif i % 4 == 0 then
				local x, z = p.X + p.Dir.Z * 8, p.Z - p.Dir.X * 8
				if ctx.IsClear(x, z, 1.5, { Road = -4, Edge = 2 }) then
					ctx.Claim(x, z, 1.5)
					Props.StoneLantern(f, ctx.At(x, z, rng:NextNumber(0, 6)))
				end
			end
		end
	end
	hillBuilding(ctx, 1, 22, function(cf)
		plinth(f, cf, 30, 30, rgb(126, 120, 110))
		Props.Pagoda(f, cf, 5, { Base = 19, Wall = rgb(92, 60, 40), Trim = rgb(236, 228, 210), Roof = rgb(58, 56, 60), Gold = rgb(176, 146, 80), Stone = rgb(126, 120, 110) })
	end)
	local kiyo = ctx.Land.Hills[2]
	if kiyo then
		kiyomizu(ctx, kiyo.x, kiyo.z)
	end

	-- ===== Kinkaku-ji: the golden pavilion over its pond, pine islands =====
	local pond = ctx.Land.Ponds[1]
	if pond then
		-- on the shore with the most room behind it, facing the water
		local px, pz, yaw = pond.x, pond.z + pond.r + 9, 0
		for _, side in ipairs({ { 0, 1, 0 }, { -1, 0, -math.pi / 2 }, { 1, 0, math.pi / 2 }, { 0, -1, math.pi } }) do
			local sx, sz = pond.x + side[1] * (pond.r + 9), pond.z + side[2] * (pond.r + 9)
			if ctx.Edge(sx + side[1] * 12, sz + side[2] * 12) < -4 then
				px, pz, yaw = sx, sz, side[3]
				break
			end
		end
		ctx.Claim(px, pz, 13)
		local cf = ctx.At(px, pz, yaw, 0.5)
		plinth(f, cf, 22, 19, rgb(126, 120, 110))
		Props.GoldenPavilion(f, cf)
		local c = zone.Center
		for _, isle in ipairs({ { -9, -6, 4 }, { 10, 3, 3 }, { -2, 12, 2.5 } }) do
			local ix, iz = pond.x + isle[1], pond.z + isle[2]
			local top = c.Y + pond.level + 0.8
			Props.Rock(f, CFrame.new(c.X + ix, top - 1.6, c.Z + iz), isle[3] * 1.8, rgb(110, 108, 100), Enum.Material.Rock, rng)
			Props.GardenPine(f, CFrame.new(c.X + ix, top, c.Z + iz), rng, isle[3] * 2.2)
		end
		for i = 0, 13 do
			local a = i * math.pi * 2 / 14 + rng:NextNumber(-0.1, 0.1)
			local r = pond.r + rng:NextNumber(9, 14)
			local x, z = pond.x + math.cos(a) * r, pond.z + math.sin(a) * r
			if ctx.IsClear(x, z, 4, { Road = 1, Edge = -2 }) then
				ctx.Claim(x, z, 4)
				if i % 3 == 0 then
					Props.GardenPine(f, ctx.At(x, z), rng)
				elseif i % 3 == 1 then
					cherry(ctx, ctx.At(x, z, rng:NextNumber(0, 6)), { Weeping = true })
				else
					Props.ForestTree(f, ctx.At(x, z), rng, rgb(200, 72, 46), rng:NextNumber(10, 13))
				end
			end
		end
	end

	-- ===== Fushimi Inari: a tunnel of torii up to the shrine, fox guardians =====
	if toriiRoad then
		local count = 0
		local first, lastP
		for _, p in ipairs(toriiRoad) do
			local dBoss = math.sqrt((p.X - boss.X) ^ 2 + (p.Z - boss.Y) ^ 2)
			local d = Landscape.RoadDistance(zone, p.X, p.Z, true)
			if dBoss > 56 and d > 14 and count < 60 then
				count += 1
				first = first or p
				lastP = p
				local base = ctx.At(p.X, p.Z).Position
				Props.Torii(f, CFrame.lookAt(base, base + p.Dir), 14, 16, VERMILION) -- tall enough to walk and jump through
				for _, side in ipairs({ -1, 1 }) do
					ctx.Claim(p.X - p.Dir.Z * 7 * side, p.Z + p.Dir.X * 7 * side, 1.5)
				end
			end
		end
		for _, p in ipairs({ first, lastP }) do
			if p then
				for _, side in ipairs({ -1, 1 }) do
					local x, z = p.X - p.Dir.Z * 10 * side, p.Z + p.Dir.X * 10 * side
					ctx.Claim(x, z, 2.5)
					local base = ctx.At(x, z).Position
					Props.FoxStatue(f, CFrame.lookAt(base, base - Vector3.new(-p.Dir.Z * side, 0, p.Dir.X * side)), side > 0)
				end
			end
		end
	end

	-- ===== dojo and zen garden by the training dummies =====
	local camp = zone.Camps[1]
	local cx, cz = camp.Offset.X, camp.Offset.Y
	local r = camp.Radius + 6
	Props.Fence(f, ctx.At(cx - r, cz - r).Position, ctx.At(cx + r, cz - r).Position)
	Props.Fence(f, ctx.At(cx - r, cz - r).Position, ctx.At(cx - r, cz + r).Position)
	Props.Fence(f, ctx.At(cx + r, cz - r).Position, ctx.At(cx + r, cz + r - 14).Position)
	local dx, dz = findSpot(ctx, cx - 10, cz - r - 22, 16, { Road = 2, MaxSlope = 0.5 }, 48)
	if dx and dz then
		ctx.Claim(dx, dz, 17)
		local cf = ctx.At(dx, dz, math.pi, 0.5)
		plinth(f, cf, 30, 20, rgb(126, 120, 110))
		Props.House(f, cf, { Width = 28, Depth = 18, Height = 11, Wall = rgb(240, 230, 210), Wood = rgb(92, 60, 40), Roof = rgb(58, 58, 66), RoofHeight = 7, RoofTrim = rgb(190, 60, 46) })
		Props.Sign(f, cf * CFrame.new(0, 0, 14) * CFrame.Angles(0, math.pi, 0), "DOJO", "Train here, young ninja!")
	end
	local gx, gz = findSpot(ctx, cx + r + 22, cz - 6, 13, { Road = 2, MaxSlope = 0.35 }, 50)
	if gx and gz then
		ctx.Claim(gx, gz, 14)
		local cf = ctx.At(gx, gz, rng:NextNumber(-0.2, 0.2), 0)
		Props.Part(f, Vector3.new(24, 0.5, 15), cf * CFrame.new(0, 0.1, 0), rgb(232, 230, 222), Enum.Material.Sand)
		for x = -11, 11, 1.5 do
			Props.Foliage(Props.Part(f, Vector3.new(0.25, 0.16, 15), cf * CFrame.new(x, 0.42, 0), rgb(210, 208, 198), Enum.Material.Sand))
		end
		for _, rock in ipairs({ { -7, -3, 2.6 }, { -1, 3.5, 1.8 }, { 4, -2, 2.2 }, { 8.5, 4, 1.5 }, { 1, -5, 1.2 } }) do
			local rcf = cf * CFrame.new(rock[1], 0, rock[2])
			Props.Foliage(Props.Part(f, Vector3.new(0.2, rock[3] * 3, rock[3] * 3), rcf * CFrame.new(0, 0.4, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(90, 130, 60), Enum.Material.Grass, Enum.PartType.Cylinder))
			Props.Rock(f, rcf, rock[3], rgb(110, 106, 100), Enum.Material.Slate, rng)
		end
		for sx = -1, 1, 2 do
			Props.Part(f, Vector3.new(0.9, 3.4, 16), cf * CFrame.new(sx * 12.5, 1.7, 0), rgb(196, 160, 110), Enum.Material.Plaster)
		end
		Props.Part(f, Vector3.new(26, 3.4, 0.9), cf * CFrame.new(0, 1.7, 8), rgb(196, 160, 110), Enum.Material.Plaster)
	end

	-- ===== cherry groves through the town and meadows =====
	ctx.Groves(9, 6, 22, 6, function(cf)
		cherry(ctx, cf, { Height = rng:NextNumber(11, 16), Weeping = rng:NextNumber() < 0.15 })
	end, { Edge = -10, MaxSlope = 0.5 })
	ctx.Scatter(30, 6, function(cf)
		cherry(ctx, cf, {})
	end, { Edge = -6, MaxSlope = 0.6 })
	ctx.Scatter(26, 3, function(cf)
		Props.Bush(f, cf, rgb(78, 140, 64), rng)
	end, { Edge = -4 })
	ctx.Groves(8, 5, 12, 2, function(cf)
		Props.Flowers(f, cf, if rng:NextNumber() < 0.6 then rgb(255, 190, 210) else rgb(255, 240, 160), rng)
	end, { Edge = -6 })
	ctx.Scatter(10, 4, function(cf)
		Props.Rock(f, cf, rng:NextNumber(3, 5), rgb(126, 124, 118), Enum.Material.Slate, rng)
	end, { Edge = -4 })

	-- ===== forests: the wooded hills round the basin (Higashiyama) =====
	local function mixedTree(cf, cheap: boolean)
		local roll = rng:NextNumber()
		if roll < 0.55 then
			Props.Cedar(f, cf, rng, rng:NextNumber(22, 34), cheap)
		elseif roll < 0.8 then
			Props.ForestTree(f, cf, rng, rgb(74, 132, 58):Lerp(rgb(110, 160, 70), rng:NextNumber()), nil, cheap)
		elseif roll < 0.9 then
			Props.ForestTree(f, cf, rng, if rng:NextNumber() < 0.6 then rgb(196, 66, 42) else rgb(222, 132, 52), rng:NextNumber(11, 16), cheap)
		elseif cheap then
			Props.ForestTree(f, cf, rng, rgb(250, 196, 210), rng:NextNumber(12, 15), true) -- wild mountain cherry
		else
			cherry(ctx, cf, {})
		end
	end
	-- the valley's wooded fringe and lower slopes (in reach, so trunks collide)
	ctx.Groves(26, 9, 26, 4.5, function(cf)
		mixedTree(cf, false)
	end, { Edge = 8, MinEdge = -22, MaxSlope = 1 })
	ctx.Scatter(140, 4.5, function(cf)
		mixedTree(cf, false)
	end, { Edge = 10, MinEdge = -14, MaxSlope = 1.1 })
	-- the temple hills
	for _, hill in ipairs({ ctx.Land.Hills[1], ctx.Land.Hills[2] }) do
		ctx.Scatter(22, 4.5, function(cf)
			mixedTree(cf, false)
		end, { Area = { hill.x, hill.z, hill.r + 10 }, Edge = 12, MaxSlope = 1.2 })
	end
	-- the mountains past the cliffs, out of bounds: a dense skyline forest
	local cliffW = ctx.Land.CliffWidth
	ctx.Scatter(900, 4.2, function(cf)
		mixedTree(cf, true)
	end, { Edge = cliffW * 3.4, MinEdge = cliffW * 0.45, MaxSlope = 1.3, Sink = 1 })
	ctx.Scatter(90, 4, function(cf)
		Props.Fern(f, cf, rgb(70, 125, 60), rng)
	end, { Edge = 6, MinEdge = -10 })
end

-- ---------------------------------------------------------------- bamboo

function ZoneDecor.Bamboo(ctx)
	local f, rng = ctx.Folder, ctx.Rng
	entranceArch(ctx, function(cf)
		Props.Torii(f, cf, 16, 17, rgb(40, 40, 40))
	end)
	-- forest shrine on a lookout hill
	hillBuilding(ctx, 3, 14, function(cf)
		plinth(f, cf, 18, 14, rgb(120, 120, 110))
		Props.House(f, cf, { Width = 14, Depth = 10, Height = 7, Wall = rgb(200, 180, 140), Wood = rgb(160, 40, 30), Roof = rgb(50, 70, 50), RoofTrim = rgb(160, 40, 30) })
	end)
	ctx.RoadSide(30, 13, function(cf)
		Props.StoneLantern(f, cf, rgb(200, 255, 170))
	end)
	-- dense bamboo groves, then strays
	local function clump(cf)
		Props.Bamboo(f, cf, rng:NextInteger(4, 7), rng)
	end
	ctx.Groves(16, 4, 24, 5, clump, { Edge = 8, MaxSlope = 0.75 })
	ctx.Scatter(18, 5, clump, { Edge = 4, MaxSlope = 0.75 })
	ctx.Scatter(36, 6, function(cf)
		Props.Tree(f, cf, { Height = rng:NextNumber(13, 19), Leaf = rgb(70, 135, 55), Trunk = rgb(85, 65, 45), Rng = rng })
	end, { Edge = 10, MaxSlope = 0.85 })
	ctx.Scatter(70, 3, function(cf)
		Props.Bush(f, cf, rgb(70, 130, 55), rng)
	end, { Edge = 6 })
	ctx.Groves(12, 6, 14, 2.5, function(cf)
		Props.Fern(f, cf, rgb(80, 150, 60), rng)
	end, { Edge = 4 })
	ctx.Groves(8, 4, 12, 2, function(cf)
		Props.Flowers(f, cf, if rng:NextNumber() < 0.5 then rgb(255, 255, 240) else rgb(255, 220, 90), rng, rgb(70, 125, 55))
	end)
	ctx.Scatter(40, 1.5, function(cf)
		Props.GrassTuft(f, cf, rgb(110, 165, 70), rng)
	end)
	ctx.Scatter(10, 6, function(cf)
		Props.FallenLog(f, cf, rgb(105, 85, 60), rng, rgb(90, 140, 60))
	end, { MaxSlope = 0.25 })
	ctx.Scatter(22, 4, function(cf)
		Props.Rock(f, cf, rng:NextNumber(3, 7), rgb(100, 115, 95), Enum.Material.Slate, rng)
	end, { Edge = 8, Sink = 1 })
	ctx.Ridge(40, 7, function(cf)
		if rng:NextNumber() < 0.6 then
			Props.Tree(f, cf, { Height = rng:NextNumber(16, 22), Kind = "Pine", Leaf = rgb(55, 105, 55), Trunk = rgb(80, 60, 45), Rng = rng })
		else
			clump(cf)
		end
	end)
end

-- ---------------------------------------------------------------- samurai

function ZoneDecor.Samurai(ctx)
	local f, rng = ctx.Folder, ctx.Rng
	entranceArch(ctx, function(cf)
		Props.Torii(f, cf, 18, 18)
	end)
	hillBuilding(ctx, 3, 22, function(cf)
		plinth(f, cf, 36, 36, rgb(140, 135, 128), Enum.Material.Cobblestone, 14)
		Props.Pagoda(f, cf, 4, { Base = 28, Roof = rgb(45, 50, 65), Trim = rgb(170, 30, 30) })
	end)
	-- houses and banners along the road
	ctx.RoadSide(58, 30, function(cf)
		plinth(f, cf, 19, 15, rgb(120, 115, 110))
		Props.House(f, cf, { Width = 16, Depth = 12, Wall = rgb(240, 235, 220), Wood = rgb(60, 40, 30), Roof = rgb(45, 50, 65), RoofTrim = rgb(170, 30, 30) })
	end, false, 12)
	ctx.RoadSide(26, 12, function(cf, _side, i)
		Props.Banner(f, cf, if i % 2 == 0 then rgb(190, 30, 30) else rgb(240, 240, 240), rgb(30, 30, 30))
	end, true)
	-- rock garden in an open meadow
	ctx.Scatter(1, 18, function(cf)
		Props.Part(f, Vector3.new(30, 1, 20), cf * CFrame.new(0, 0.2, 0), rgb(225, 222, 215), Enum.Material.Sand)
		for _ = 1, 5 do
			Props.Rock(f, cf * CFrame.new(rng:NextNumber(-12, 12), 0, rng:NextNumber(-7, 7)), rng:NextNumber(2, 4), rgb(110, 110, 105), Enum.Material.Slate, rng)
		end
	end, { MaxSlope = 0.08 })
	-- cherry orchards, autumn maples, pines
	ctx.Groves(10, 5, 22, 6, function(cf)
		Props.Tree(f, cf, { Height = rng:NextNumber(12, 16), Leaf = rgb(255, 180, 205), Trunk = rgb(80, 55, 45), Rng = rng, Petals = rng:NextNumber() < 0.2 })
	end, { Edge = 6, MaxSlope = 0.6 })
	ctx.Scatter(18, 6, function(cf)
		Props.Tree(f, cf, { Height = rng:NextNumber(13, 17), Kind = "Leafy", Leaf = if rng:NextNumber() < 0.5 then rgb(220, 90, 40) else rgb(235, 160, 50), Trunk = rgb(85, 55, 40), Rng = rng })
	end, { Edge = 10, MaxSlope = 0.8 })
	ctx.Scatter(60, 3, function(cf)
		Props.Bush(f, cf, rgb(95, 135, 65), rng)
	end, { Edge = 6 })
	ctx.Groves(10, 4, 12, 2, function(cf)
		Props.Flowers(f, cf, if rng:NextNumber() < 0.5 then rgb(255, 170, 200) else rgb(255, 250, 245), rng, rgb(90, 130, 60))
	end)
	ctx.Scatter(30, 1.5, function(cf)
		Props.GrassTuft(f, cf, rgb(150, 160, 80), rng)
	end)
	ctx.Scatter(10, 5, function(cf)
		Props.StoneLantern(f, cf)
	end, { MaxSlope = 0.3 })
	ctx.Scatter(15, 4, function(cf)
		Props.Rock(f, cf, rng:NextNumber(3, 6), rgb(170, 160, 145), Enum.Material.Limestone, rng)
	end, { Edge = 8, Sink = 1 })
	ctx.Ridge(36, 7, function(cf)
		Props.Tree(f, cf, { Height = rng:NextNumber(15, 21), Kind = "Pine", Leaf = rgb(60, 100, 60), Trunk = rgb(80, 60, 45), Rng = rng })
	end)
end

-- ---------------------------------------------------------------- demon

function ZoneDecor.Demon(ctx)
	local f, rng = ctx.Folder, ctx.Rng
	entranceArch(ctx, function(cf)
		Props.Torii(f, cf, 16, 17, rgb(40, 10, 10))
	end)
	hillBuilding(ctx, 1, 6, function(cf)
		Props.Statue(f, cf, rgb(90, 40, 40), rgb(255, 180, 40))
	end)
	hillBuilding(ctx, 3, 6, function(cf)
		Props.Statue(f, cf, rgb(90, 40, 40), rgb(255, 180, 40))
	end)
	ctx.RoadSide(40, 12, function(cf)
		Props.Brazier(f, cf, rgb(255, 90, 30))
	end)
	ctx.Scatter(12, 8, function(cf)
		Props.LavaPool(f, cf, rng:NextNumber(4, 8))
	end, { MaxSlope = 0.12 })
	ctx.Scatter(30, 4, function(cf)
		Props.Spikes(f, cf, rgb(50, 25, 25), rng)
	end, { Edge = 8, Sink = 0.6 })
	local function deadTree(cf)
		Props.DeadTree(f, cf, rgb(40, 25, 20), rng)
	end
	ctx.Groves(8, 5, 20, 4, deadTree, { Edge = 8, MaxSlope = 0.8 })
	ctx.Scatter(20, 4, deadTree, { Edge = 10 })
	ctx.Scatter(12, 4, function(cf)
		Props.Crystal(f, cf, rgb(255, 60, 30), rng:NextNumber(5, 9), rng)
	end, { Edge = 4 })
	ctx.Scatter(50, 3, function(cf)
		Props.Bush(f, cf, rgb(110, 35, 30), rng)
	end, { Edge = 6 })
	ctx.Scatter(50, 1.5, function(cf)
		Props.GrassTuft(f, cf, rgb(170, 70, 40), rng)
	end)
	ctx.Scatter(24, 4, function(cf)
		Props.Rock(f, cf, rng:NextNumber(4, 8), rgb(55, 40, 40), Enum.Material.Basalt, rng)
	end, { Edge = 10, Sink = 1 })
	ctx.Ridge(30, 6, deadTree)
end

-- ---------------------------------------------------------------- shadow

function ZoneDecor.Shadow(ctx)
	local f, rng = ctx.Folder, ctx.Rng
	entranceArch(ctx, function(cf)
		Props.Torii(f, cf, 16, 17, rgb(40, 20, 70))
	end)
	local function shadowTree(cf)
		Props.Tree(f, cf, {
			Height = rng:NextNumber(14, 22), Trunk = rgb(30, 22, 35), Leaf = rgb(90, 40, 160), LeafMaterial = Enum.Material.Neon,
			LeafTransparency = 0.35, Rng = rng, Blobs = 3, Glow = rng:NextNumber() < 0.15,
		})
	end
	ctx.Groves(12, 5, 22, 6, shadowTree, { Edge = 8, MaxSlope = 0.8 })
	ctx.Scatter(20, 6, shadowTree, { Edge = 10, MaxSlope = 0.85 })
	ctx.Scatter(35, 3, function(cf)
		Props.Mushroom(f, cf, if rng:NextNumber() < 0.5 then rgb(170, 90, 255) else rgb(90, 220, 255), rng)
	end, { Edge = 4 })
	ctx.Groves(10, 5, 14, 2.5, function(cf)
		Props.Fern(f, cf, rgb(70, 40, 110), rng)
	end, { Edge = 4 })
	ctx.Scatter(40, 3, function(cf)
		Props.Bush(f, cf, rgb(55, 35, 85), rng)
	end, { Edge = 6 })
	ctx.Scatter(40, 1.5, function(cf)
		Props.GrassTuft(f, cf, rgb(90, 60, 140), rng)
	end)
	ctx.Scatter(14, 5, function(cf)
		Props.Rock(f, cf, rng:NextNumber(4, 7), rgb(40, 35, 55), Enum.Material.Slate, rng)
	end, { Edge = 8, Sink = 1 })
	ctx.Scatter(8, 6, function(cf)
		Props.FallenLog(f, cf, rgb(40, 30, 45), rng, rgb(90, 50, 150))
	end, { MaxSlope = 0.25 })
	-- floating wisps
	ctx.Scatter(14, 2, function(cf)
		local orb = Props.Part(f, Vector3.new(1.4, 1.4, 1.4), cf * CFrame.new(0, rng:NextNumber(6, 14), 0), rgb(200, 160, 255), Enum.Material.Neon, Enum.PartType.Ball)
		Props.Foliage(orb)
		Props.Light(orb, rgb(170, 100, 255), 16, 1.5)
	end)
	ctx.Ridge(36, 7, function(cf)
		Props.Tree(f, cf, { Height = rng:NextNumber(16, 22), Kind = "Pine", Leaf = rgb(60, 30, 100), Trunk = rgb(30, 22, 35), Rng = rng })
	end)
end

-- ---------------------------------------------------------------- volcanic

function ZoneDecor.Volcanic(ctx)
	local f, rng = ctx.Folder, ctx.Rng
	local stone = rgb(45, 38, 38)
	-- fortress walls with crenellations along the road (gaps at every branch)
	ctx.RoadSide(38, 24, function(cf)
		local wall = cf -- its x axis runs along the road
		plinth(f, wall, 30, 5, stone, Enum.Material.Basalt, 8)
		Props.Part(f, Vector3.new(30, 10, 5), wall * CFrame.new(0, 5, 0), stone, Enum.Material.Basalt)
		for c = -12, 12, 6 do
			Props.Part(f, Vector3.new(3, 2.5, 5), wall * CFrame.new(c, 11.2, 0), stone, Enum.Material.Basalt)
		end
	end, true, 15)
	for _, x in ipairs({ -ctx.Land.H + 60, ctx.Land.H - 60 }) do
		local road = roadFrame(ctx, x)
		for _, side in ipairs({ -1, 1 }) do
			local cf = road * CFrame.new(side * 22, 0, 0)
			local p = cf.Position - ctx.Zone.Center
			if ctx.Edge(p.X, p.Z) < 0 then
				ctx.Claim(p.X, p.Z, 7)
				plinth(f, cf, 10, 10, rgb(40, 34, 34), Enum.Material.Basalt, 8)
				Props.Part(f, Vector3.new(10, 22, 10), cf * CFrame.new(0, 11, 0), rgb(40, 34, 34), Enum.Material.Basalt)
				Props.Brazier(f, cf * CFrame.new(0, 22, 0), rgb(255, 120, 30))
			end
		end
	end
	-- lava channels on flat ground
	ctx.Scatter(10, 10, function(cf)
		local lava = Props.Part(f, Vector3.new(4, 0.6, rng:NextNumber(24, 40)), cf * CFrame.new(0, 0.5, 0), rgb(255, 100, 20), Enum.Material.Neon)
		lava.CanCollide = false
		if rng:NextNumber() < 0.6 then
			Props.Light(lava, rgb(255, 110, 30), 20, 2)
		end
	end, { MaxSlope = 0.06 })
	ctx.Scatter(8, 8, function(cf)
		Props.LavaPool(f, cf, rng:NextNumber(4, 7))
	end, { MaxSlope = 0.12 })
	local function charred(cf)
		Props.DeadTree(f, cf, rgb(25, 20, 20), rng)
	end
	ctx.Groves(7, 5, 20, 4, charred, { Edge = 8, MaxSlope = 0.8 })
	ctx.Scatter(12, 4, charred, { Edge = 10 })
	ctx.Scatter(12, 7, function(cf)
		Props.Rock(f, cf, rng:NextNumber(8, 14), rgb(35, 30, 30), Enum.Material.Basalt, rng)
	end, { Edge = 12, Sink = 2 })
	ctx.Scatter(24, 4, function(cf)
		Props.Rock(f, cf, rng:NextNumber(3, 7), rgb(35, 30, 30), Enum.Material.Basalt, rng)
	end, { Edge = 8, Sink = 1 })
	ctx.Scatter(30, 3, function(cf)
		Props.Bush(f, cf, rgb(70, 60, 55), rng)
	end, { Edge = 6 })
	ctx.Scatter(40, 1.5, function(cf)
		Props.GrassTuft(f, cf, rgb(255, 120, 40), rng, rng:NextNumber(1.2, 2.2))
	end)
	ctx.Ridge(26, 6, charred)
end

-- ---------------------------------------------------------------- sky

function ZoneDecor.Sky(ctx)
	local f, rng = ctx.Folder, ctx.Rng
	entranceArch(ctx, function(cf)
		Props.Torii(f, cf, 18, 20, rgb(255, 210, 90))
	end)
	hillBuilding(ctx, 3, 20, function(cf)
		plinth(f, cf, 32, 32, rgb(235, 235, 245), Enum.Material.Marble, 14)
		Props.Pagoda(f, cf, 5, { Base = 26, Wall = rgb(250, 250, 255), Roof = rgb(240, 200, 90), Trim = rgb(120, 190, 255), Stone = rgb(235, 235, 245), Gold = rgb(255, 230, 120) })
	end)
	ctx.RoadSide(26, 13, function(cf)
		Props.Pillar(f, cf, 14, rgb(245, 245, 250), rgb(255, 215, 110))
	end, true)
	for _ = 1, 16 do
		local x, z = rng:NextNumber(-ctx.Land.H + 40, ctx.Land.H - 40), rng:NextNumber(-ctx.Land.D + 80, ctx.Land.D - 80)
		Props.Cloud(f, ctx.At(x, z) * CFrame.new(0, rng:NextNumber(35, 65), 0), rng:NextNumber(8, 16), rng)
	end
	ctx.Scatter(10, 5, function(cf)
		Props.Crystal(f, cf, rgb(140, 220, 255), rng:NextNumber(5, 10), rng)
	end, { Edge = 4 })
	local function snowyPine(cf)
		Props.Tree(f, cf, { Height = rng:NextNumber(14, 21), Kind = "Pine", Leaf = rgb(215, 232, 245), Trunk = rgb(150, 130, 110), Rng = rng })
	end
	ctx.Groves(10, 5, 22, 6, snowyPine, { Edge = 10, MaxSlope = 0.85 })
	ctx.Scatter(18, 6, function(cf)
		Props.Tree(f, cf, { Height = rng:NextNumber(10, 14), Leaf = rgb(255, 245, 200), Trunk = rgb(180, 150, 110), Rng = rng, Petals = rng:NextNumber() < 0.3 })
	end, { Edge = 4, MaxSlope = 0.6 })
	ctx.Scatter(40, 3, function(cf)
		Props.Bush(f, cf, rgb(200, 225, 240), rng)
	end, { Edge = 6 })
	ctx.Groves(8, 4, 12, 2, function(cf)
		Props.Flowers(f, cf, if rng:NextNumber() < 0.5 then rgb(140, 200, 255) else rgb(255, 220, 110), rng, rgb(190, 220, 235))
	end)
	ctx.Scatter(15, 4, function(cf)
		Props.Rock(f, cf, rng:NextNumber(3, 7), rgb(200, 220, 240), Enum.Material.Glacier, rng)
	end, { Edge = 8, Sink = 1 })
	ctx.Ridge(36, 7, snowyPine)
end

-- ---------------------------------------------------------------- void

function ZoneDecor.Void(ctx)
	local f, rng = ctx.Folder, ctx.Rng
	entranceArch(ctx, function(cf)
		Props.Rift(f, cf, 14, rgb(230, 80, 255))
	end)
	hillBuilding(ctx, 2, 26, function(cf)
		Props.Rift(f, cf, 24, rgb(230, 80, 255))
	end)
	ctx.Scatter(30, 5, function(cf)
		Props.Crystal(f, cf, if rng:NextNumber() < 0.5 then rgb(230, 80, 255) else rgb(120, 60, 255), rng:NextNumber(6, 14), rng, rng:NextNumber() < 0.4)
	end, { Edge = 4 })
	ctx.Scatter(12, 8, function(cf)
		Props.Obelisk(f, cf, rng:NextNumber(14, 24), rgb(15, 8, 25), rgb(230, 80, 255))
	end, { MaxSlope = 0.35, Sink = 1 })
	local function voidTree(cf)
		Props.Tree(f, cf, {
			Height = rng:NextNumber(14, 20), Trunk = rgb(20, 10, 30), Leaf = rgb(150, 50, 220), LeafMaterial = Enum.Material.Neon,
			LeafTransparency = 0.45, Rng = rng, Blobs = 3,
		})
	end
	ctx.Groves(6, 5, 20, 6, voidTree, { Edge = 8, MaxSlope = 0.8 })
	ctx.Scatter(30, 3, function(cf)
		Props.Bush(f, cf, rgb(60, 25, 90), rng)
	end, { Edge = 6 })
	ctx.Scatter(50, 1.5, function(cf)
		Props.GrassTuft(f, cf, rgb(160, 70, 230), rng)
	end)
	ctx.Scatter(14, 5, function(cf)
		Props.Rock(f, cf, rng:NextNumber(4, 8), rgb(25, 12, 40), Enum.Material.Slate, rng)
	end, { Edge = 10, Sink = 1 })
	for _ = 1, 25 do
		local x, z = rng:NextNumber(-ctx.Land.H + 30, ctx.Land.H - 30), rng:NextNumber(-ctx.Land.D + 60, ctx.Land.D - 60)
		local cf = ctx.At(x, z) * CFrame.new(0, rng:NextNumber(25, 75), 0) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6))
		local rock = Props.Part(f, Vector3.new(rng:NextNumber(4, 12), rng:NextNumber(3, 8), rng:NextNumber(4, 12)), cf, rgb(25, 12, 40), Enum.Material.Slate)
		rock.CanCollide = false
		rock.CanQuery = false
	end
	ctx.Ridge(24, 7, function(cf)
		Props.Rock(f, cf, rng:NextNumber(6, 12), rgb(30, 14, 46), Enum.Material.Slate, rng)
	end)
end

-- ---------------------------------------------------------------- cursed temple

-- The ruined temple of the Cursed Temple zone. Its gate (the glowing seal under the
-- black torii, a ProximityPrompt tagged TempleGate) opens the Temple menu: the way down
-- into the 100 floors (TempleService).
local function cursedTemple(ctx, x: number, z: number, yaw: number)
	local f, rng = ctx.Folder, ctx.Rng
	local stone, dark, blood = rgb(70, 58, 60), rgb(30, 24, 26), rgb(150, 18, 24)
	-- the gate stands 26 studs out from the hall's front, turned by yaw
	local front = CFrame.Angles(0, yaw, 0) * Vector3.new(0, 0, -26)
	local gx, gz = x + front.X, z + front.Z
	ctx.Claim(x, z, 26)
	ctx.Claim(gx, gz, 14)
	local hall = ctx.At(x, z, yaw, 0.5)
	plinth(f, hall, 40, 28, stone, Enum.Material.Cobblestone, 14)
	Props.House(f, hall * CFrame.new(0, 0.6, 4), { Width = 30, Depth = 18, Height = 12, Wall = rgb(64, 50, 50), Wood = dark, Roof = rgb(36, 28, 30), RoofHeight = 10, RoofTrim = blood })
	-- broken pillars along the front steps, some fallen
	for i = -2, 2 do
		local cf = hall * CFrame.new(i * 8, 0.6, -12)
		local h = if i % 2 == 0 then 14 else rng:NextNumber(4, 8)
		Props.Part(f, Vector3.new(2.6, h, 2.6), cf * CFrame.new(0, h / 2, 0), stone, Enum.Material.Basalt)
		if h < 10 then
			Props.Part(f, Vector3.new(2.4, 2.4, 7), cf * CFrame.new(1.5, 1.2, -4) * CFrame.Angles(0, rng:NextNumber(-0.6, 0.6), 0), stone, Enum.Material.Basalt)
		end
	end
	for _, side in ipairs({ -1, 1 }) do
		Props.Brazier(f, hall * CFrame.new(side * 17, 0.6, -12), rgb(255, 50, 30))
		Props.Banner(f, hall * CFrame.new(side * 11, 0.6, -6), blood, rgb(20, 10, 10))
	end
	-- the gate: a black torii over a glowing seal in the ground
	local gate = ctx.At(gx, gz, yaw, 0.3)
	Props.Torii(f, gate, 14, 16, rgb(26, 16, 18))
	local seal = Props.Part(f, Vector3.new(0.6, 12, 12), gate * CFrame.new(0, 0.35, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(255, 40, 30), Enum.Material.Neon, Enum.PartType.Cylinder)
	seal.Transparency = 0.25
	seal.CanCollide = false
	Props.Light(seal, rgb(255, 50, 40), 26, 2.5)
	local veil = Props.Part(f, Vector3.new(12, 13, 0.3), gate * CFrame.new(0, 7, 0), rgb(120, 0, 20), Enum.Material.Neon)
	veil.Transparency = 0.7
	veil.CanCollide = false
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Enter the Depths"
	prompt.ObjectText = "The Cursed Temple"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("TempleGate", true)
	prompt.Parent = veil
	Props.Sign(f, gate * CFrame.new(11, 0, -10), "The Cursed Temple", "100 floors down. Few return.", rgb(255, 90, 80))
end

function ZoneDecor.Cursed(ctx)
	local f, rng = ctx.Folder, ctx.Rng
	entranceArch(ctx, function(cf)
		Props.Torii(f, cf, 16, 18, rgb(26, 16, 18))
	end)
	-- turned 60 degrees left so the gate opens toward the valley, not the mountain
	local tx, tz = findSpot(ctx, -150, 95, 22, { MaxSlope = 0.5 }, 48)
	cursedTemple(ctx, tx or -150, tz or 95, math.rad(60))
	ctx.RoadSide(34, 12, function(cf)
		Props.StoneLantern(f, cf, rgb(255, 50, 40))
	end)
	ctx.Scatter(14, 6, function(cf)
		Props.Statue(f, cf, rgb(60, 50, 52), rgb(255, 40, 30))
	end, { MaxSlope = 0.3, Sink = 0.5 })
	ctx.Scatter(18, 4, function(cf)
		local h = rng:NextNumber(5, 12)
		Props.Part(f, Vector3.new(2.4, h, 2.4), cf * CFrame.new(0, h / 2 - 0.5, 0) * CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, rng:NextNumber(-0.15, 0.15)), rgb(66, 56, 58), Enum.Material.Basalt)
	end, { Edge = 4, MaxSlope = 0.4 })
	local function blighted(cf)
		Props.DeadTree(f, cf, rgb(36, 24, 24), rng)
	end
	ctx.Groves(9, 5, 20, 4, blighted, { Edge = 8, MaxSlope = 0.8 })
	ctx.Scatter(20, 4, blighted, { Edge = 10 })
	ctx.Scatter(10, 4, function(cf)
		Props.Crystal(f, cf, rgb(220, 30, 40), rng:NextNumber(4, 8), rng)
	end, { Edge = 4 })
	ctx.Scatter(40, 3, function(cf)
		Props.Bush(f, cf, rgb(70, 30, 32), rng)
	end, { Edge = 6 })
	ctx.Scatter(50, 1.5, function(cf)
		Props.GrassTuft(f, cf, rgb(120, 40, 36), rng)
	end)
	ctx.Scatter(20, 4, function(cf)
		Props.Rock(f, cf, rng:NextNumber(4, 8), rgb(40, 28, 30), Enum.Material.Basalt, rng)
	end, { Edge = 10, Sink = 1 })
	-- drifting embers
	ctx.Scatter(14, 2, function(cf)
		local orb = Props.Part(f, Vector3.new(1, 1, 1), cf * CFrame.new(0, rng:NextNumber(5, 12), 0), rgb(255, 60, 40), Enum.Material.Neon, Enum.PartType.Ball)
		Props.Foliage(orb)
		Props.Light(orb, rgb(255, 50, 30), 14, 1.4)
	end)
	ctx.Ridge(28, 6, blighted)
end

return ZoneDecor
