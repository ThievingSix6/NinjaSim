--[[
	Procedural prop library used by ZoneDecor. Every prop is built from anchored
	parts and returned as a Model so zones can be composed from code alone.
	All builders take a CFrame (position + facing) on the ground.

	When the Blender prop pack (tools/blender/props.py) has been imported into
	ReplicatedStorage.NinjaAssets, the village props use those meshes, with
	invisible boxes for collision; otherwise they fall back to parts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Particles = require(ReplicatedStorage.Shared.Visuals.Particles)
local Assets = require(ReplicatedStorage.Shared.Visuals.Assets)

local Props = {}

local rgb = Color3.fromRGB

local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end
Props.Part = part

local function wedge(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	local p = Instance.new("WedgePart")
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.Parent = parent
	return p
end
Props.Wedge = wedge

local function model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local UP = CFrame.Angles(0, 0, math.pi / 2) -- turns a cylinder's axis to vertical

local function light(p: BasePart, color: Color3, range: number, brightness: number?)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 1.5
	l.Shadows = false
	l.Parent = p
	return l
end
Props.Light = light

-- Small greenery: no collisions, queries, touches or shadows (cheap, and raycasts
-- for the ground pass through it).
local function foliage(p: BasePart): BasePart
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end
Props.Foliage = foliage

-- ---------------------------------------------------------------- meshes

-- One imported mesh piece, placed from the manifest (prop origin = ground, front -Z).
local function piece(m: Instance, name: string, cf: CFrame, scale: Vector3?, color: Color3?, material: Enum.Material?): MeshPart?
	local info = Assets.Manifest[name]
	local mesh = info and Assets.Mesh(name, color or info.Color, material or info.Material)
	if not mesh then
		return nil
	end
	Assets.Place(mesh, cf, scale)
	mesh.Anchored = true
	mesh.CastShadow = true
	mesh.Parent = m
	return mesh
end

-- Invisible collision box, so walkable props don't depend on mesh collision.
local function collider(m: Instance, size: Vector3, cf: CFrame): BasePart
	local p = part(m, size, cf, Color3.new(0, 0, 0))
	p.Name = "Collider"
	p.Transparency = 1
	p.CastShadow = false
	return p
end

local function hasProp(prop: string, groups: { string }): boolean
	for _, g in ipairs(groups) do
		if not Assets.Has(prop .. "__" .. g) then
			return false
		end
	end
	return true
end

local function yaw(rng: Random): CFrame
	return CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
end

local function tint(color: Color3, rng: Random, amount: number): Color3
	return color:Lerp(if rng:NextNumber() < 0.5 then Color3.new(1, 1, 1) else Color3.new(0, 0, 0), rng:NextNumber(0, amount))
end

local Mesh = {}

function Mesh.House(parent: Instance, cf: CFrame, opts: any): Model?
	if not hasProp("House", { "Base", "Walls", "Wood", "Shoji", "Roof" }) then
		return nil
	end
	local m = model(parent, "House")
	local w, d, h = opts.Width or 16, opts.Depth or 12, opts.Height or 9
	local s = Vector3.new(w / 16, h / 9, d / 12)
	piece(m, "House__Base", cf, s)
	piece(m, "House__Walls", cf, s, opts.Wall)
	piece(m, "House__Wood", cf, s, opts.Wood)
	local shoji = piece(m, "House__Shoji", cf, s)
	-- the roof sits on the wall tops (y 10.2 in the pack) and can be taller than the house scale
	local rise = (opts.RoofHeight or 5) / 5
	local roofScale = Vector3.new(s.X, s.Y * rise, s.Z)
	local eave = 10.2
	local roof = Assets.Mesh("House__Roof", opts.Roof or Assets.Manifest["House__Roof"].Color, Enum.Material.Slate)
	if roof then
		Assets.Place(roof, cf * CFrame.new(0, eave * s.Y - eave, 0), roofScale, Vector3.new(0, eave, 0))
		roof.Anchored = true
		roof.CastShadow = true
		roof.Parent = m
	end
	collider(m, Vector3.new(w + 2.4 * s.X, 1.2 * s.Y, d + 2.4 * s.Z), cf * CFrame.new(0, 0.6 * s.Y, 0))
	collider(m, Vector3.new(w, 9 * s.Y, d), cf * CFrame.new(0, 5.7 * s.Y, 0))
	if shoji then
		light(shoji, rgb(255, 190, 120), 14, 1)
	end
	return m
end

function Mesh.Pagoda(parent: Instance, cf: CFrame, tiers: number, opts: any): Model?
	if not (hasProp("PagodaBase", { "Stone" }) and hasProp("PagodaTier", { "Walls", "Trim", "Roof" }) and hasProp("PagodaTop", { "Gold" })) then
		return nil
	end
	local m = model(parent, "Pagoda")
	local k = (opts.Base or 26) / 26
	piece(m, "PagodaBase__Stone", cf, Vector3.new(k, 1, k), opts.Stone)
	collider(m, Vector3.new(34 * k, 4, 34 * k), cf * CFrame.new(0, 2, 0))
	local shrink = if tiers > 3 then 0.12 else 0.16
	local y = 4
	for i = 1, tiers do
		local t = k * (1 - (i - 1) * shrink)
		local at = cf * CFrame.new(0, y, 0)
		local sv = Vector3.one * t
		local walls = piece(m, "PagodaTier__Walls", at, sv, opts.Wall)
		piece(m, "PagodaTier__Trim", at, sv, opts.Trim)
		piece(m, "PagodaTier__Roof", at, sv, opts.Roof)
		if i == 1 then
			collider(m, Vector3.new(26 * t, 8.4 * t, 26 * t), at * CFrame.new(0, 4.2 * t, 0))
		end
		if walls and i % 2 == 1 then
			light(walls, rgb(255, 200, 140), 18 * t, 1)
		end
		y += (8.4 + 3.0) * t
	end
	piece(m, "PagodaTop__Gold", cf * CFrame.new(0, y - 0.6 * k, 0), Vector3.one * k, opts.Gold)
	return m
end

function Mesh.Torii(parent: Instance, cf: CFrame, width: number, height: number, color: Color3?): Model?
	if not hasProp("Torii", { "Red", "Black", "Stone" }) then
		return nil
	end
	local m = model(parent, "Torii")
	local s = Vector3.new(width / 16, height / 16, (width + height) / 32)
	piece(m, "Torii__Red", cf, s, color)
	piece(m, "Torii__Black", cf, s)
	piece(m, "Torii__Stone", cf, s)
	for sx = -1, 1, 2 do
		collider(m, Vector3.new(1.8 * s.Z, height, 1.8 * s.Z), cf * CFrame.new(sx * width / 2, height / 2, 0))
	end
	return m
end

function Mesh.StoneLantern(parent: Instance, cf: CFrame, glow: Color3?): Model?
	if not hasProp("StoneLantern", { "Stone", "Glow" }) then
		return nil
	end
	local m = model(parent, "Lantern")
	piece(m, "StoneLantern__Stone", cf)
	local fire = piece(m, "StoneLantern__Glow", cf, nil, glow)
	if fire then
		light(fire, glow or rgb(255, 180, 100), 16, 1.6)
	end
	collider(m, Vector3.new(2.4, 6.4, 2.4), cf * CFrame.new(0, 3.2, 0))
	return m
end

function Mesh.PaperLantern(parent: Instance, cf: CFrame, color: Color3?): Model?
	if not hasProp("PaperLantern", { "Wood", "Paper", "Black" }) then
		return nil
	end
	local m = model(parent, "PaperLantern")
	local at = cf * CFrame.Angles(0, math.pi, 0) -- the pack hangs the lamp toward -X; the part version uses +X
	piece(m, "PaperLantern__Wood", at)
	piece(m, "PaperLantern__Black", at)
	local lamp = piece(m, "PaperLantern__Paper", at, nil, color)
	if lamp then
		light(lamp, color or rgb(255, 140, 90), 14, 1.3)
	end
	collider(m, Vector3.new(0.5, 7, 0.5), cf * CFrame.new(0, 3.5, 0))
	return m
end

local TREE_KINDS = {
	Sakura = { "TreeSakura1", "TreeSakura2" },
	Leafy = { "TreeLeafy4", "TreeSakura1" },
	Pine = { "TreePine3" },
}

function Mesh.Tree(parent: Instance, cf: CFrame, opts: any): Model?
	local rng = opts.Rng or Random.new()
	local leaf = opts.Leaf or rgb(80, 150, 70)
	local kind = opts.Kind
	if not kind then
		-- pale or pink canopies read as blossom trees; greens mix broadleaf and pine
		local blossom = leaf.R > leaf.G + 0.08 or (leaf.R > 0.85 and leaf.G > 0.85)
		kind = if blossom then "Sakura" elseif rng:NextNumber() < 0.3 then "Pine" else "Leafy"
	end
	local choices = TREE_KINDS[kind] or TREE_KINDS.Leafy
	local name = choices[rng:NextInteger(1, #choices)]
	if not hasProp(name, { "Trunk", "Leaves" }) then
		return nil
	end
	local m = model(parent, "Tree")
	local h = opts.Height or 14
	local s = Vector3.one * ((h + 4) / 16)
	local at = cf * yaw(rng)
	piece(m, name .. "__Trunk", at, s, opts.Trunk)
	local leaves = piece(m, name .. "__Leaves", at, s, tint(leaf, rng, 0.1), opts.LeafMaterial or Enum.Material.SmoothPlastic)
	if leaves then
		leaves.CastShadow = true
		leaves.CanCollide = false
		leaves.CanQuery = false
		leaves.CanTouch = false
		if opts.LeafTransparency then
			leaves.Transparency = opts.LeafTransparency
		end
		if opts.Glow then
			light(leaves, leaf, 14, 1)
		end
		if opts.Petals then
			Particles.Create("Petals", leaves, { Rate = 2 })
		end
	end
	collider(m, Vector3.new(1.6 * s.X, 9 * s.Y, 1.6 * s.X), cf * CFrame.new(0, 4.5 * s.Y, 0))
	return m
end

function Mesh.Bamboo(parent: Instance, cf: CFrame, count: number, rng: Random): Model?
	if not hasProp("Bamboo", { "Stalk", "Leaves" }) then
		return nil
	end
	local m = model(parent, "Bamboo")
	for _ = 1, count do
		local h = rng:NextNumber(22, 42)
		local sy = h / 21
		local at = cf * CFrame.new(rng:NextNumber(-4, 4), 0, rng:NextNumber(-4, 4)) * CFrame.Angles(rng:NextNumber(-0.06, 0.06), 0, rng:NextNumber(-0.06, 0.06)) * yaw(rng)
		local green = rgb(110, 170, 70):Lerp(rgb(160, 200, 90), rng:NextNumber())
		piece(m, "Bamboo__Stalk", at, Vector3.new(1, sy, 1), green)
		-- leaves keep their size and ride up with the top of the stalk
		local leaves = piece(m, "Bamboo__Leaves", at * CFrame.new(0, 16.5 * (sy - 1), 0), nil, rgb(90, 160, 60), Enum.Material.SmoothPlastic)
		if leaves then
			foliage(leaves)
		end
	end
	-- one collider for the clump keeps the part count down
	collider(m, Vector3.new(14, 7, 7), cf * CFrame.new(0, 7, 0) * UP)
	return m
end

function Mesh.Rock(parent: Instance, cf: CFrame, size: number, color: Color3, material: Enum.Material?, rng: Random): Model?
	if not hasProp("Rock1", { "Stone" }) then
		return nil
	end
	local m = model(parent, "Rock")
	for i = 1, 2 do
		local name = "Rock" .. rng:NextInteger(1, 3) .. "__Stone"
		if Assets.Has(name) then
			local k = size / 2 * (if i == 1 then rng:NextNumber(0.9, 1.2) else rng:NextNumber(0.45, 0.65))
			local s = Vector3.new(k * rng:NextNumber(0.85, 1.15), k * rng:NextNumber(0.7, 1.1), k * rng:NextNumber(0.85, 1.15))
			local offset = if i == 1 then Vector3.zero else Vector3.new(rng:NextNumber(-0.7, 0.7) * size, 0, rng:NextNumber(-0.7, 0.7) * size)
			local at = cf * CFrame.new(offset) * yaw(rng)
			local rock = piece(m, name, at, s, tint(color, rng, 0.12), material or Enum.Material.Rock)
			if rock and i == 1 then
				collider(m, rock.Size * Vector3.new(0.8, 0.9, 0.8), rock.CFrame)
			end
		end
	end
	return m
end

function Mesh.Bush(parent: Instance, cf: CFrame, color: Color3, rng: Random): Model?
	local name = "Bush" .. rng:NextInteger(1, 2)
	if not hasProp(name, { "Leaves" }) then
		return nil
	end
	local m = model(parent, "Bush")
	local leaves = piece(m, name .. "__Leaves", cf * yaw(rng), Vector3.one * rng:NextNumber(0.95, 1.4), tint(color, rng, 0.1), Enum.Material.SmoothPlastic)
	if leaves then
		foliage(leaves)
	end
	return m
end

function Mesh.Fence(parent: Instance, from: Vector3, to: Vector3, color: Color3?): Model?
	if not hasProp("Fence", { "Wood" }) then
		return nil
	end
	local m = model(parent, "Fence")
	local len = (to - from).Magnitude
	local segments = math.max(1, math.floor(len / 8 + 0.5))
	local step = len / segments
	-- turn the pack's X-running segment to run along the line
	local along = CFrame.lookAt(from, to) * CFrame.Angles(0, math.pi / 2, 0)
	for i = 0, segments - 1 do
		piece(m, "Fence__Wood", along * CFrame.new((i + 0.5) * step, 0, 0), Vector3.new(step / 8, 1, 1), color)
	end
	collider(m, Vector3.new(len, 3.8, 0.5), along * CFrame.new(len / 2, 1.9, 0))
	return m
end

-- Sloped roof with upturned eaves: two wedges + ridge + corner flicks.
function Props.Roof(parent: Instance, cf: CFrame, width: number, depth: number, height: number, color: Color3, trim: Color3?)
	local half = depth / 2
	-- WedgeParts are tall at +Z and slope down toward -Z, so the front half is unrotated
	wedge(parent, Vector3.new(width, height, half), cf * CFrame.new(0, height / 2, -half / 2), color, Enum.Material.Slate)
	wedge(parent, Vector3.new(width, height, half), cf * CFrame.new(0, height / 2, half / 2) * CFrame.Angles(0, math.pi, 0), color, Enum.Material.Slate)
	part(parent, Vector3.new(width + 0.6, 0.6, 0.8), cf * CFrame.new(0, height + 0.1, 0), trim or color:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.Slate)
	for sx = -1, 1, 2 do
		for sz = -1, 1, 2 do
			wedge(parent, Vector3.new(0.6, 1.2, 1.6), cf * CFrame.new(sx * width / 2, 0.3, sz * (half + 0.2)) * CFrame.Angles(0, if sz > 0 then 0 else math.pi, 0), trim or color, Enum.Material.Slate)
		end
	end
end

function Props.House(parent: Instance, cf: CFrame, opts: any?)
	opts = opts or {}
	local meshed = Mesh.House(parent, cf, opts)
	if meshed then
		return meshed
	end
	local m = model(parent, "House")
	local w, d, h = opts.Width or 16, opts.Depth or 12, opts.Height or 9
	local wall = opts.Wall or rgb(235, 225, 205)
	local wood = opts.Wood or rgb(110, 70, 45)
	local roof = opts.Roof or rgb(70, 75, 90)
	part(m, Vector3.new(w + 2, 1.2, d + 2), cf * CFrame.new(0, 0.6, 0), rgb(120, 115, 110), Enum.Material.Cobblestone)
	part(m, Vector3.new(w, h, d), cf * CFrame.new(0, 1.2 + h / 2, 0), wall, Enum.Material.Plaster)
	-- timber frame
	for sx = -1, 1, 2 do
		for sz = -1, 1, 2 do
			part(m, Vector3.new(0.9, h, 0.9), cf * CFrame.new(sx * w / 2, 1.2 + h / 2, sz * d / 2), wood, Enum.Material.Wood)
		end
	end
	part(m, Vector3.new(w + 0.4, 0.8, d + 0.4), cf * CFrame.new(0, 1.2 + h * 0.55, 0), wood, Enum.Material.Wood)
	-- door + windows (front = -Z)
	part(m, Vector3.new(3.4, 5.5, 0.3), cf * CFrame.new(0, 1.2 + 2.75, -d / 2 - 0.1), wood:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.Wood)
	for sx = -1, 1, 2 do
		local win = part(m, Vector3.new(3, 2.4, 0.3), cf * CFrame.new(sx * w * 0.3, 1.2 + h * 0.75, -d / 2 - 0.1), rgb(255, 220, 150), Enum.Material.Neon)
		win.Transparency = 0.25
		part(m, Vector3.new(0.25, 2.4, 0.35), win.CFrame, wood, Enum.Material.Wood)
	end
	Props.Roof(m, cf * CFrame.new(0, 1.2 + h, 0), w + 4, d + 5, opts.RoofHeight or 5, roof, opts.RoofTrim)
	local lamp = part(m, Vector3.new(1, 1.4, 1), cf * CFrame.new(w * 0.3, 1.2 + h * 0.45, -d / 2 - 1), rgb(255, 90, 60), Enum.Material.Neon, Enum.PartType.Ball)
	light(lamp, rgb(255, 150, 90), 12, 1.2)
	return m
end

function Props.Pagoda(parent: Instance, cf: CFrame, tiers: number, opts: any?)
	opts = opts or {}
	local meshed = Mesh.Pagoda(parent, cf, tiers, opts)
	if meshed then
		return meshed
	end
	local m = model(parent, "Pagoda")
	local base = opts.Base or 26
	local wall = opts.Wall or rgb(240, 235, 225)
	local roof = opts.Roof or rgb(60, 65, 80)
	local trim = opts.Trim or rgb(200, 50, 40)
	part(m, Vector3.new(base + 8, 4, base + 8), cf * CFrame.new(0, 2, 0), opts.Stone or rgb(140, 135, 128), Enum.Material.Cobblestone)
	local y = 4
	for i = 1, tiers do
		local size = base * (1 - (i - 1) * 0.16)
		local h = 9 - i * 0.6
		part(m, Vector3.new(size, h, size), cf * CFrame.new(0, y + h / 2, 0), wall, Enum.Material.Plaster)
		part(m, Vector3.new(size + 0.6, 1, size + 0.6), cf * CFrame.new(0, y + h * 0.3, 0), trim, Enum.Material.Wood)
		for sx = -1, 1, 2 do
			for sz = -1, 1, 2 do
				part(m, Vector3.new(1, h, 1), cf * CFrame.new(sx * size / 2, y + h / 2, sz * size / 2), trim, Enum.Material.Wood)
			end
		end
		local win = part(m, Vector3.new(size * 0.5, h * 0.35, 0.4), cf * CFrame.new(0, y + h * 0.65, -size / 2 - 0.1), rgb(255, 210, 140), Enum.Material.Neon)
		win.Transparency = 0.3
		y += h
		-- wide flat roof with flicked corners
		part(m, Vector3.new(size + 9, 1.2, size + 9), cf * CFrame.new(0, y, 0), roof, Enum.Material.Slate)
		part(m, Vector3.new(size + 3, 2, size + 3), cf * CFrame.new(0, y + 1.4, 0), roof, Enum.Material.Slate)
		for sx = -1, 1, 2 do
			for sz = -1, 1, 2 do
				wedge(m, Vector3.new(1.4, 2.2, 3), cf * CFrame.new(sx * (size / 2 + 4.2), y + 1, sz * (size / 2 + 4.2)) * CFrame.Angles(0, math.atan2(sx, sz), 0), opts.Gold or rgb(230, 190, 80), Enum.Material.Foil)
			end
		end
		y += 2.4
	end
	local spire = part(m, Vector3.new(6, 1, 1), cf * CFrame.new(0, y + 3, 0) * UP, opts.Gold or rgb(230, 190, 80), Enum.Material.Foil, Enum.PartType.Cylinder)
	spire.Size = Vector3.new(7, 1, 1)
	return m
end

function Props.Torii(parent: Instance, cf: CFrame, width: number, height: number, color: Color3?)
	local meshed = Mesh.Torii(parent, cf, width, height, color)
	if meshed then
		return meshed
	end
	local m = model(parent, "Torii")
	local c = color or rgb(210, 45, 35)
	for sx = -1, 1, 2 do
		part(m, Vector3.new(height, 1.8, 1.8), cf * CFrame.new(sx * width / 2, height / 2, 0) * UP, c, Enum.Material.Wood, Enum.PartType.Cylinder)
		part(m, Vector3.new(2.6, 1.2, 2.6), cf * CFrame.new(sx * width / 2, 0.6, 0), rgb(30, 30, 30), Enum.Material.Wood)
	end
	part(m, Vector3.new(width + 1.5, 1.2, 1.4), cf * CFrame.new(0, height * 0.78, 0), c, Enum.Material.Wood)
	part(m, Vector3.new(width + 7, 1.4, 2), cf * CFrame.new(0, height + 0.4, 0), rgb(30, 25, 25), Enum.Material.Wood)
	part(m, Vector3.new(width + 6, 1.2, 1.8), cf * CFrame.new(0, height - 0.8, 0), c, Enum.Material.Wood)
	for sx = -1, 1, 2 do
		wedge(m, Vector3.new(1.8, 1, 2), cf * CFrame.new(sx * (width / 2 + 4), height + 1.3, 0) * CFrame.Angles(0, sx * math.pi / 2, 0), rgb(30, 25, 25), Enum.Material.Wood)
	end
	part(m, Vector3.new(1.6, height * 0.2, 0.4), cf * CFrame.new(0, height * 0.88, -0.8), rgb(30, 25, 25), Enum.Material.Wood)
	return m
end

function Props.StoneLantern(parent: Instance, cf: CFrame, glow: Color3?)
	local meshed = Mesh.StoneLantern(parent, cf, glow)
	if meshed then
		return meshed
	end
	local m = model(parent, "Lantern")
	local stone = rgb(150, 148, 140)
	part(m, Vector3.new(2.4, 0.8, 2.4), cf * CFrame.new(0, 0.4, 0), stone, Enum.Material.Slate)
	part(m, Vector3.new(3, 0.9, 0.9), cf * CFrame.new(0, 2.2, 0) * UP, stone, Enum.Material.Slate, Enum.PartType.Cylinder)
	part(m, Vector3.new(2, 0.5, 2), cf * CFrame.new(0, 3.9, 0), stone, Enum.Material.Slate)
	local fire = part(m, Vector3.new(1.3, 1.3, 1.3), cf * CFrame.new(0, 4.8, 0), glow or rgb(255, 190, 110), Enum.Material.Neon)
	part(m, Vector3.new(1.7, 1.4, 0.3), cf * CFrame.new(0, 4.8, 0), stone, Enum.Material.Slate)
	wedge(m, Vector3.new(2.8, 1.2, 1.4), cf * CFrame.new(0, 6.1, 0.7) * CFrame.Angles(0, math.pi, 0), stone, Enum.Material.Slate)
	wedge(m, Vector3.new(2.8, 1.2, 1.4), cf * CFrame.new(0, 6.1, -0.7), stone, Enum.Material.Slate)
	light(fire, glow or rgb(255, 180, 100), 16, 1.6)
	return m
end

function Props.PaperLantern(parent: Instance, cf: CFrame, color: Color3?)
	local meshed = Mesh.PaperLantern(parent, cf, color)
	if meshed then
		return meshed
	end
	local m = model(parent, "PaperLantern")
	part(m, Vector3.new(0.5, 7, 0.5), cf * CFrame.new(0, 3.5, 0), rgb(60, 40, 30), Enum.Material.Wood)
	part(m, Vector3.new(2, 0.4, 0.4), cf * CFrame.new(0.9, 6.8, 0), rgb(60, 40, 30), Enum.Material.Wood)
	local lamp = part(m, Vector3.new(1.4, 1.8, 1.4), cf * CFrame.new(1.6, 5.6, 0), color or rgb(255, 80, 60), Enum.Material.Neon, Enum.PartType.Ball)
	lamp.Size = Vector3.new(1.6, 1.6, 1.6)
	light(lamp, color or rgb(255, 140, 90), 14, 1.3)
	return m
end

function Props.Tree(parent: Instance, cf: CFrame, opts: any?)
	opts = opts or {}
	local meshed = Mesh.Tree(parent, cf, opts)
	if meshed then
		return meshed
	end
	local m = model(parent, "Tree")
	local h = opts.Height or 14
	local trunk = opts.Trunk or rgb(100, 70, 45)
	local leaf = opts.Leaf or rgb(80, 150, 70)
	part(m, Vector3.new(h, 1.8, 1.8), cf * CFrame.new(0, h / 2, 0) * UP, trunk, Enum.Material.Wood, Enum.PartType.Cylinder)
	local material = opts.LeafMaterial or Enum.Material.Grass
	local rng = opts.Rng or Random.new()
	if opts.Kind == "Pine" then
		-- stacked discs read as a stylised conifer
		for i = 1, 3 do
			local r = (4 - i) * 2.6 + rng:NextNumber(-0.4, 0.4)
			local tier = part(m, Vector3.new(2.2, r * 2, r * 2), cf * CFrame.new(0, h * 0.35 + i * h * 0.2, 0) * UP, leaf:Lerp(Color3.new(1, 1, 1), rng:NextNumber(0, 0.1)), material, Enum.PartType.Cylinder)
			tier.CanCollide = false
			if opts.LeafTransparency then
				tier.Transparency = opts.LeafTransparency
			end
		end
		return m
	end
	for i = 1, opts.Blobs or 4 do
		local r = rng:NextNumber(5, 8)
		local offset = Vector3.new(rng:NextNumber(-3.5, 3.5), h + rng:NextNumber(-2, 2.5), rng:NextNumber(-3.5, 3.5))
		local ball = part(m, Vector3.new(r, r, r), cf * CFrame.new(offset), leaf:Lerp(Color3.new(1, 1, 1), rng:NextNumber(0, 0.12)), material, Enum.PartType.Ball)
		ball.CanCollide = false
		if opts.LeafTransparency then
			ball.Transparency = opts.LeafTransparency
		end
		if opts.Glow and i == 1 then
			light(ball, leaf, 14, 1)
		end
	end
	if opts.Petals then
		local emitter = part(m, Vector3.new(8, 1, 8), cf * CFrame.new(0, h, 0), leaf)
		emitter.Transparency = 1
		emitter.CanCollide = false
		Particles.Create("Petals", emitter, { Rate = 2 })
	end
	return m
end

function Props.Bamboo(parent: Instance, cf: CFrame, count: number, rng: Random)
	local meshed = Mesh.Bamboo(parent, cf, count, rng)
	if meshed then
		return meshed
	end
	local m = model(parent, "Bamboo")
	for _ = 1, count do
		local h = rng:NextNumber(22, 42)
		local pos = cf * CFrame.new(rng:NextNumber(-4, 4), 0, rng:NextNumber(-4, 4))
		local tilt = CFrame.Angles(rng:NextNumber(-0.06, 0.06), 0, rng:NextNumber(-0.06, 0.06))
		local green = rgb(110, 170, 70):Lerp(rgb(160, 200, 90), rng:NextNumber())
		part(m, Vector3.new(h, 0.9, 0.9), pos * tilt * CFrame.new(0, h / 2, 0) * UP, green, Enum.Material.Wood, Enum.PartType.Cylinder)
		for y = 6, h - 4, 12 do
			foliage(part(m, Vector3.new(0.3, 1.05, 1.05), pos * tilt * CFrame.new(0, y, 0) * UP, green:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Wood, Enum.PartType.Cylinder))
		end
		for i = 1, 2 do
			local a = rng:NextNumber(0, math.pi * 2)
			foliage(wedge(m, Vector3.new(0.2, 0.8, 3.2), pos * tilt * CFrame.new(0, h - i * 2.5, 0) * CFrame.Angles(0, a, math.rad(-20)) * CFrame.new(0, 0, -1.6), rgb(90, 160, 60), Enum.Material.Grass))
		end
	end
	return m
end

function Props.Rock(parent: Instance, cf: CFrame, size: number, color: Color3, material: Enum.Material?, rng: Random)
	local meshed = Mesh.Rock(parent, cf, size, color, material, rng)
	if meshed then
		return meshed
	end
	local m = model(parent, "Rock")
	for _ = 1, 3 do
		local s = Vector3.new(rng:NextNumber(0.6, 1.1), rng:NextNumber(0.4, 0.8), rng:NextNumber(0.6, 1.1)) * size
		part(m, s, cf * CFrame.new(rng:NextNumber(-0.3, 0.3) * size, s.Y * 0.35, rng:NextNumber(-0.3, 0.3) * size) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6), rng:NextNumber(-0.4, 0.4)), color:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.15)), material or Enum.Material.Rock)
	end
	return m
end

function Props.Bush(parent: Instance, cf: CFrame, color: Color3, rng: Random)
	local meshed = Mesh.Bush(parent, cf, color, rng)
	if meshed then
		return meshed
	end
	local m = model(parent, "Bush")
	for _ = 1, 3 do
		local r = rng:NextNumber(3, 5)
		foliage(part(m, Vector3.new(r, r, r), cf * CFrame.new(rng:NextNumber(-1.5, 1.5), r * 0.3, rng:NextNumber(-1.5, 1.5)), color:Lerp(Color3.new(1, 1, 1), rng:NextNumber(0, 0.1)), Enum.Material.Grass, Enum.PartType.Ball))
	end
	return m
end

-- A tuft of grass blades (3 parts, no collisions).
function Props.GrassTuft(parent: Instance, cf: CFrame, color: Color3, rng: Random, height: number?)
	local m = model(parent, "Grass")
	local h = height or rng:NextNumber(1.8, 3.4)
	for i = 1, 3 do
		local a = i * math.pi * 2 / 3 + rng:NextNumber(-0.5, 0.5)
		local bh = h * rng:NextNumber(0.7, 1.1)
		foliage(wedge(m, Vector3.new(0.15, bh, rng:NextNumber(0.9, 1.5)), cf * CFrame.Angles(0, a, 0) * CFrame.Angles(rng:NextNumber(-0.3, -0.08), 0, 0) * CFrame.new(0, bh / 2 - 0.2, 0.4), tint(color, rng, 0.15), Enum.Material.Grass))
	end
	return m
end

-- A few flower heads over a leafy mound (4 parts, no collisions).
function Props.Flowers(parent: Instance, cf: CFrame, color: Color3, rng: Random, leaf: Color3?)
	local m = model(parent, "Flowers")
	foliage(part(m, Vector3.one * rng:NextNumber(2.4, 3.2), cf * CFrame.new(0, 0.3, 0), leaf or rgb(70, 130, 55), Enum.Material.Grass, Enum.PartType.Ball))
	for _ = 1, 3 do
		local s = rng:NextNumber(0.6, 0.95)
		foliage(part(m, Vector3.new(s, s, s), cf * CFrame.new(rng:NextNumber(-1.3, 1.3), rng:NextNumber(1.3, 1.9), rng:NextNumber(-1.3, 1.3)), tint(color, rng, 0.15), Enum.Material.SmoothPlastic, Enum.PartType.Ball))
	end
	return m
end

-- Fronds fanning out from the ground (5 parts, no collisions).
function Props.Fern(parent: Instance, cf: CFrame, color: Color3, rng: Random, material: Enum.Material?)
	local m = model(parent, "Fern")
	local size = rng:NextNumber(0.8, 1.3)
	for i = 1, 5 do
		local a = i * math.pi * 2 / 5 + rng:NextNumber(-0.3, 0.3)
		local len = rng:NextNumber(2.8, 4.2) * size
		foliage(wedge(m, Vector3.new(0.2, len * 0.4, len), cf * CFrame.Angles(0, a, 0) * CFrame.new(0, len * 0.18, -len * 0.42) * CFrame.Angles(0.45, 0, 0), tint(color, rng, 0.12), material or Enum.Material.Grass))
	end
	return m
end

-- A fallen log, optionally with a mossy top (1-2 parts).
function Props.FallenLog(parent: Instance, cf: CFrame, color: Color3, rng: Random, moss: Color3?)
	local m = model(parent, "Log")
	local len, r = rng:NextNumber(9, 16), rng:NextNumber(1.6, 2.6)
	local log = part(m, Vector3.new(len, r, r), cf * CFrame.new(0, r * 0.3, 0) * CFrame.Angles(0, 0, rng:NextNumber(-0.05, 0.05)), tint(color, rng, 0.1), Enum.Material.Wood, Enum.PartType.Cylinder)
	if moss then
		foliage(part(m, Vector3.new(len * 0.6, 0.35, r * 0.75), log.CFrame * CFrame.new(rng:NextNumber(-0.15, 0.15) * len, r * 0.42, 0), moss, Enum.Material.Grass))
	end
	return m
end

function Props.Fence(parent: Instance, from: Vector3, to: Vector3, color: Color3?)
	local meshed = Mesh.Fence(parent, from, to, color)
	if meshed then
		return meshed
	end
	local m = model(parent, "Fence")
	local c = color or rgb(120, 85, 55)
	local dir = to - from
	local len = dir.Magnitude
	local cf = CFrame.lookAt(from, to)
	local posts = math.max(2, math.floor(len / 6))
	for i = 0, posts do
		part(m, Vector3.new(0.7, 4, 0.7), cf * CFrame.new(0, 2, -len * i / posts), c, Enum.Material.Wood)
	end
	part(m, Vector3.new(0.35, 0.5, len), cf * CFrame.new(0, 3.2, -len / 2), c, Enum.Material.Wood)
	part(m, Vector3.new(0.35, 0.5, len), cf * CFrame.new(0, 1.8, -len / 2), c, Enum.Material.Wood)
	return m
end

function Props.Banner(parent: Instance, cf: CFrame, color: Color3, emblem: Color3?)
	local m = model(parent, "Banner")
	part(m, Vector3.new(12, 0.5, 0.5), cf * CFrame.new(0, 6, 0) * UP, rgb(40, 30, 25), Enum.Material.Wood, Enum.PartType.Cylinder)
	part(m, Vector3.new(0.4, 0.4, 3), cf * CFrame.new(0, 11.6, -1.4), rgb(40, 30, 25), Enum.Material.Wood)
	local flag = part(m, Vector3.new(0.15, 7, 2.6), cf * CFrame.new(0, 8, -1.5), color, Enum.Material.Fabric)
	if emblem then
		part(m, Vector3.new(0.2, 1.6, 1.6), flag.CFrame * CFrame.new(0, 1, 0), emblem, Enum.Material.Fabric, Enum.PartType.Cylinder)
	end
	return m
end

function Props.Crystal(parent: Instance, cf: CFrame, color: Color3, height: number, rng: Random, floating: boolean?)
	local m = model(parent, "Crystal")
	local base = if floating then cf * CFrame.new(0, rng:NextNumber(6, 16), 0) else cf
	for i = 1, 3 do
		local h = height * (if i == 1 then 1 else rng:NextNumber(0.4, 0.7))
		local c = part(m, Vector3.new(h * 0.25, h, h * 0.25), base * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6), rng:NextNumber(-0.4, 0.4)) * CFrame.new(0, h * 0.4, 0), color, if i == 1 then Enum.Material.Neon else Enum.Material.Glass)
		c.Transparency = if i == 1 then 0.1 else 0.3
		c.CanCollide = not floating
		if i == 1 then
			light(c, color, 14, 1.4)
		end
	end
	return m
end

function Props.DeadTree(parent: Instance, cf: CFrame, color: Color3, rng: Random)
	local m = model(parent, "DeadTree")
	local h = rng:NextNumber(10, 18)
	part(m, Vector3.new(1.4, h, 1.4), cf * CFrame.new(0, h / 2, 0) * CFrame.Angles(rng:NextNumber(-0.1, 0.1), 0, rng:NextNumber(-0.1, 0.1)), color, Enum.Material.Wood)
	for _ = 1, 4 do
		local len = rng:NextNumber(4, 8)
		local y = rng:NextNumber(h * 0.5, h)
		part(m, Vector3.new(0.6, len, 0.6), cf * CFrame.new(0, y, 0) * CFrame.Angles(0, rng:NextNumber(0, 6), rng:NextNumber(0.6, 1.1)) * CFrame.new(0, len / 2, 0), color, Enum.Material.Wood)
	end
	return m
end

function Props.Mushroom(parent: Instance, cf: CFrame, cap: Color3, rng: Random)
	local m = model(parent, "Mushroom")
	local h = rng:NextNumber(2, 6)
	part(m, Vector3.new(h, 0.9, 0.9), cf * CFrame.new(0, h / 2, 0) * UP, rgb(220, 210, 230), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	local c = part(m, Vector3.new(h * 0.5, h * 1.2, h * 1.2), cf * CFrame.new(0, h, 0) * UP, cap, Enum.Material.Neon, Enum.PartType.Cylinder)
	light(c, cap, 10, 1)
	return m
end

function Props.Brazier(parent: Instance, cf: CFrame, flame: Color3?)
	local m = model(parent, "Brazier")
	part(m, Vector3.new(4, 1, 1), cf * CFrame.new(0, 2, 0) * UP, rgb(50, 45, 45), Enum.Material.Metal, Enum.PartType.Cylinder)
	local bowl = part(m, Vector3.new(1.2, 3.4, 3.4), cf * CFrame.new(0, 4.4, 0) * UP, rgb(60, 50, 45), Enum.Material.Metal, Enum.PartType.Cylinder)
	local fire = part(m, Vector3.new(2.4, 0.6, 2.4), bowl.CFrame * CFrame.new(0.7, 0, 0) * CFrame.Angles(0, 0, -math.pi / 2), flame or rgb(255, 140, 40), Enum.Material.Neon)
	Particles.Create("Embers", fire, { Rate = 18, Color = ColorSequence.new(flame or rgb(255, 200, 80), rgb(255, 60, 20)) })
	local f = Instance.new("Fire")
	f.Heat = 8
	f.Size = 5
	f.Color = flame or rgb(255, 140, 40)
	f.SecondaryColor = rgb(255, 60, 20)
	f.Parent = fire
	light(fire, flame or rgb(255, 160, 80), 20, 2)
	return m
end

function Props.Pillar(parent: Instance, cf: CFrame, height: number, color: Color3, trim: Color3)
	local m = model(parent, "Pillar")
	part(m, Vector3.new(4.5, 1.5, 4.5), cf * CFrame.new(0, 0.75, 0), trim, Enum.Material.Marble)
	part(m, Vector3.new(height, 2.8, 2.8), cf * CFrame.new(0, height / 2 + 1.5, 0) * UP, color, Enum.Material.Marble, Enum.PartType.Cylinder)
	part(m, Vector3.new(4.5, 1.2, 4.5), cf * CFrame.new(0, height + 2.1, 0), trim, Enum.Material.Marble)
	return m
end

function Props.Cloud(parent: Instance, cf: CFrame, size: number, rng: Random)
	local m = model(parent, "Cloud")
	for _ = 1, 5 do
		local r = rng:NextNumber(0.5, 1) * size
		local c = part(m, Vector3.new(r, r, r), cf * CFrame.new(rng:NextNumber(-1, 1) * size, rng:NextNumber(-0.2, 0.3) * size, rng:NextNumber(-0.6, 0.6) * size), rgb(255, 255, 255), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		c.Transparency = 0.15
		c.CanCollide = false
		c.CastShadow = false
	end
	return m
end

function Props.Obelisk(parent: Instance, cf: CFrame, height: number, color: Color3, glow: Color3)
	local m = model(parent, "Obelisk")
	part(m, Vector3.new(6, 1.5, 6), cf * CFrame.new(0, 0.75, 0), color, Enum.Material.Slate)
	part(m, Vector3.new(3.4, height, 3.4), cf * CFrame.new(0, height / 2 + 1.5, 0), color, Enum.Material.Slate)
	wedge(m, Vector3.new(3.4, 3, 1.7), cf * CFrame.new(0, height + 3, 0.85) * CFrame.Angles(0, math.pi, 0), color, Enum.Material.Slate)
	wedge(m, Vector3.new(3.4, 3, 1.7), cf * CFrame.new(0, height + 3, -0.85), color, Enum.Material.Slate)
	for i = 1, 4 do
		local rune = part(m, Vector3.new(1.2, 1.2, 0.2), cf * CFrame.new(0, 3 + i * height / 5, -1.75) * CFrame.Angles(0, 0, math.rad(45)), glow, Enum.Material.Neon)
		if i == 2 then
			light(rune, glow, 14, 1.5)
		end
	end
	return m
end

function Props.Rift(parent: Instance, cf: CFrame, radius: number, color: Color3)
	local m = model(parent, "Rift")
	local center = cf * CFrame.new(0, radius + 2, 0)
	for i = 0, 17 do
		local a = i * math.pi * 2 / 18
		local seg = part(m, Vector3.new(radius * 0.38, 0.8, 0.8), center * CFrame.new(math.cos(a) * radius, math.sin(a) * radius, 0) * CFrame.Angles(0, 0, a + math.pi / 2), color, Enum.Material.Neon)
		seg.CanCollide = false
	end
	local core = part(m, Vector3.new(0.2, radius * 1.9, radius * 1.9), center * CFrame.Angles(0, math.pi / 2, 0), rgb(10, 0, 20), Enum.Material.ForceField, Enum.PartType.Cylinder)
	core.CanCollide = false
	core.Transparency = 0.2
	Particles.Create("Void", core, { Rate = 25 })
	light(core, color, 24, 2)
	return m
end

function Props.Spikes(parent: Instance, cf: CFrame, color: Color3, rng: Random)
	local m = model(parent, "Spikes")
	for _ = 1, 4 do
		local h = rng:NextNumber(4, 10)
		wedge(m, Vector3.new(1.5, h, 2), cf * CFrame.new(rng:NextNumber(-2, 2), h / 2, rng:NextNumber(-2, 2)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), color, Enum.Material.Basalt)
	end
	return m
end

function Props.LavaPool(parent: Instance, cf: CFrame, radius: number)
	local m = model(parent, "LavaPool")
	part(m, Vector3.new(0.6, radius * 2 + 3, radius * 2 + 3), cf * CFrame.new(0, 0.2, 0) * UP, rgb(40, 30, 30), Enum.Material.Basalt, Enum.PartType.Cylinder)
	local lava = part(m, Vector3.new(0.6, radius * 2, radius * 2), cf * CFrame.new(0, 0.35, 0) * UP, rgb(255, 100, 20), Enum.Material.Neon, Enum.PartType.Cylinder)
	Particles.Create("Embers", lava, { Rate = 10 })
	light(lava, rgb(255, 110, 30), radius * 3, 2)
	return m
end

function Props.Statue(parent: Instance, cf: CFrame, color: Color3, eyes: Color3)
	local m = model(parent, "Statue")
	part(m, Vector3.new(8, 3, 8), cf * CFrame.new(0, 1.5, 0), rgb(70, 60, 60), Enum.Material.Slate)
	part(m, Vector3.new(6, 8, 4), cf * CFrame.new(0, 7, 0), color, Enum.Material.Slate)
	local head = part(m, Vector3.new(5, 5, 5), cf * CFrame.new(0, 13.5, 0), color, Enum.Material.Slate)
	for sx = -1, 1, 2 do
		part(m, Vector3.new(1, 0.8, 0.3), head.CFrame * CFrame.new(sx * 1.2, 0.6, -2.55), eyes, Enum.Material.Neon)
		wedge(m, Vector3.new(0.8, 3.5, 1.6), head.CFrame * CFrame.new(sx * 2, 3.5, 0) * CFrame.Angles(0, math.pi / 2, sx * -0.3), rgb(230, 220, 200), Enum.Material.Marble)
	end
	part(m, Vector3.new(3, 0.6, 0.3), head.CFrame * CFrame.new(0, -1.3, -2.55), rgb(240, 235, 220), Enum.Material.Marble)
	return m
end

function Props.Sign(parent: Instance, cf: CFrame, title: string, subtitle: string?, color: Color3?)
	local m = model(parent, "Sign")
	for sx = -1, 1, 2 do
		part(m, Vector3.new(0.8, 9, 0.8), cf * CFrame.new(sx * 6, 4.5, 0), rgb(90, 60, 40), Enum.Material.Wood)
	end
	local board = part(m, Vector3.new(15, 5, 0.6), cf * CFrame.new(0, 7, 0), rgb(120, 85, 55), Enum.Material.Wood)
	Props.Roof(m, cf * CFrame.new(0, 9.5, 0), 17, 2.4, 1.2, rgb(60, 60, 70))
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.CanvasSize = Vector2.new(600, 200)
		gui.LightInfluence = 0.3
		gui.Parent = board
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Position = UDim2.new(0.05, 0, if subtitle then 0.14 else 0.25, 0)
		t.Size = UDim2.new(0.9, 0, 0.42, 0)
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.Text = title
		t.TextColor3 = color or rgb(255, 240, 210)
		t.TextStrokeTransparency = 1
		local outline = Instance.new("UIStroke")
		outline.Color = rgb(26, 22, 40)
		outline.Thickness = 3
		outline.Parent = t
		local cap = Instance.new("UITextSizeConstraint")
		cap.MaxTextSize = 64
		cap.Parent = t
		t.Parent = gui
		if subtitle then
			local s = t:Clone()
			s.Position = UDim2.new(0.05, 0, 0.6, 0)
			s.Size = UDim2.new(0.9, 0, 0.24, 0)
			s.Text = subtitle
			s.TextColor3 = rgb(255, 255, 255)
			s:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize = 36
			s:FindFirstChildOfClass("UIStroke").Thickness = 2
			s.Parent = gui
		end
	end
	return m
end

return Props
