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

function ZoneDecor.Village(ctx)
	local f, rng = ctx.Folder, ctx.Rng
	-- Dojo near spawn and houses lining the main road
	Props.House(f, ctx.At(-110, 60, math.pi), { Width = 28, Depth = 18, Height = 11, Wall = rgb(240, 230, 210), Roof = rgb(60, 60, 75), RoofHeight = 7, RoofTrim = rgb(200, 60, 50) })
	Props.Sign(f, ctx.At(-110, 44, math.pi), "DOJO", "Train here, young ninja!")
	ctx.Claim(-110, 60, 18)
	for i, x in ipairs({ -60, -20, 25, 65, 110 }) do
		local side = if i % 2 == 0 then 1 else -1
		ctx.Claim(x, side * 30, 11)
		Props.House(f, ctx.At(x, side * 30, if side > 0 then math.pi else 0), {
			Width = rng:NextNumber(13, 18), Depth = rng:NextNumber(10, 13),
			Wall = rgb(235, 225, 205):Lerp(rgb(220, 200, 170), rng:NextNumber()),
			Roof = if i % 2 == 0 then rgb(70, 75, 95) else rgb(150, 60, 45),
		})
	end
	for x = -140, 130, 26 do
		Props.PaperLantern(f, ctx.At(x, -11, 0), rgb(255, 90, 70))
		Props.PaperLantern(f, ctx.At(x + 13, 11, math.pi), rgb(255, 200, 90))
	end
	Props.Torii(f, ctx.At(-150, 0, math.pi / 2), 16, 16)
	-- Training yard fence around the dummies
	local camp = ctx.Zone.Camps[1]
	local cx, cz = camp.Offset.X, camp.Offset.Y
	local r = camp.Radius + 6
	Props.Fence(f, ctx.At(cx - r, cz - r).Position, ctx.At(cx + r, cz - r).Position)
	Props.Fence(f, ctx.At(cx - r, cz - r).Position, ctx.At(cx - r, cz + r).Position)
	Props.Fence(f, ctx.At(cx + r, cz - r).Position, ctx.At(cx + r, cz + r - 14).Position)
	local inVillage = { Area = { 0, 0, 175 } }
	ctx.Scatter(28, 6, function(cf)
		Props.Tree(f, cf, { Height = rng:NextNumber(11, 16), Leaf = rgb(255, 170, 200), Trunk = rgb(90, 60, 50), Rng = rng, Petals = rng:NextNumber() < 0.35 })
	end, inVillage)
	ctx.Scatter(25, 3, function(cf)
		Props.Bush(f, cf, rgb(80, 150, 70), rng)
	end, inVillage)
	ctx.Scatter(12, 4, function(cf)
		Props.Rock(f, cf, rng:NextNumber(3, 6), rgb(130, 128, 122), Enum.Material.Slate, rng)
	end, inVillage)
	ctx.Scatter(6, 5, function(cf)
		Props.StoneLantern(f, cf)
	end, inVillage)
	-- the pass to the Bamboo Forest, the village edges and the ridges
	ctx.Scatter(14, 6, function(cf)
		Props.Tree(f, cf, { Height = rng:NextNumber(12, 17), Leaf = rgb(90, 150, 70), Trunk = rgb(90, 65, 50), Rng = rng })
	end, { Edge = 8, MaxSlope = 0.8 })
	ctx.Scatter(18, 3, function(cf)
		Props.Bush(f, cf, rgb(80, 150, 70), rng)
	end, { Edge = 6 })
	ctx.Groves(6, 4, 10, 2, function(cf)
		Props.Flowers(f, cf, if rng:NextNumber() < 0.5 then rgb(255, 190, 210) else rgb(255, 240, 150), rng)
	end)
	ctx.Ridge(30, 7, function(cf)
		Props.Tree(f, cf, { Height = rng:NextNumber(14, 20), Kind = "Pine", Leaf = rgb(60, 110, 60), Trunk = rgb(80, 60, 45), Rng = rng })
	end)
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

return ZoneDecor
