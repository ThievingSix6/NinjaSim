--[[
	HatBuilder: builds the loot hats (Config/Hats) from parts, for the character's
	head, the world drop and the menu previews.

	Hats are modelled in "head units": a 1.2-stud head with its crown (top centre)
	at the origin, its centre at (0, -0.6, 0) and its face on the z = -0.6 plane
	(-Z is the front). Wear() measures what is really on the head (the hero ninja
	suits hide the avatar head and bring a bigger one of their own, the part-built
	outfit wraps it in a hood) and scales and offsets the hat to sit on top of that.

	Optional mesh hook: an imported mesh named Hat_<id> (in the NinjaSim asset pack)
	replaces the part-built hat. Model it for the 1.2-stud head; it is scaled with the
	head, its bounding box sitting on the crown (masks: its back on the face plane).
]]

local Assets = require(script.Parent.Assets)
local Particles = require(script.Parent.Particles)
local Hats = require(script.Parent.Parent.Config.Hats)

local HatBuilder = {}

HatBuilder.FolderName = "NinjaHat"

local rad = math.rad
local BLACK = Color3.fromRGB(24, 20, 26)
local WHITE = Color3.fromRGB(250, 248, 244)

type Ctx = { Origin: CFrame, K: number, Folder: Instance, Parts: { BasePart } }

-- ===== primitives (positions and sizes in head units) =====
local function scaled(ctx: Ctx, cf: CFrame): CFrame
	return ctx.Origin * (cf - cf.Position + cf.Position * ctx.K)
end

local function part(ctx: Ctx, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	p.Name = "HatPart"
	if shape then
		p.Shape = shape
	end
	p.Size = size * ctx.K
	p.CFrame = scaled(ctx, cf)
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.Anchored = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = ctx.Folder
	table.insert(ctx.Parts, p)
	return p
end

local function ellipsoid(ctx: Ctx, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	local p = part(ctx, size, cf, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function ball(ctx: Ctx, d: number, pos: Vector3, color: Color3, material: Enum.Material?): BasePart
	return part(ctx, Vector3.new(d, d, d), CFrame.new(pos), color, material, Enum.PartType.Ball)
end

-- Upright cylinder (a disc or a band round the head).
local function vcyl(ctx: Ctx, dia: number, height: number, pos: Vector3, color: Color3, material: Enum.Material?): BasePart
	return part(ctx, Vector3.new(height, dia, dia), CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2), color, material, Enum.PartType.Cylinder)
end

-- Cylinder from a to b.
local function rod(ctx: Ctx, a: Vector3, b: Vector3, dia: number, color: Color3, material: Enum.Material?): BasePart
	local dir = b - a
	local up = if math.abs(dir.Unit.Y) > 0.98 then Vector3.zAxis else Vector3.yAxis
	local cf = CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, math.pi / 2, 0)
	return part(ctx, Vector3.new(dir.Magnitude, dia, dia), cf, color, material, Enum.PartType.Cylinder)
end

-- Flat disc facing `normal`.
local function disc(ctx: Ctx, pos: Vector3, normal: Vector3, dia: number, thick: number, color: Color3, material: Enum.Material?): BasePart
	return rod(ctx, pos - normal.Unit * thick / 2, pos + normal.Unit * thick / 2, dia, color, material)
end

-- Stepped cone of discs from y0 upward.
local function cone(ctx: Ctx, dia: number, height: number, y0: number, steps: number, color: Color3, material: Enum.Material?)
	local h = height / steps
	for i = 0, steps - 1 do
		vcyl(ctx, dia * (1 - i / steps), h * 1.02, Vector3.new(0, y0 + h * (i + 0.5), 0), color, material)
	end
end

-- Curving, tapering horn: n segments from `base` heading `dir`, turning by `bend` each step.
local function horn(ctx: Ctx, base: Vector3, dir: Vector3, bend: Vector3, n: number, len: number, dia: number, color: Color3, material: Enum.Material?, tip: Color3?)
	local p, d = base, dir.Unit
	for i = 1, n do
		local q = p + d * len
		local width = dia * (1 - (i - 1) / (n + 0.6))
		rod(ctx, p, q, width, if i == n and tip then tip else color, if i == n and tip then Enum.Material.Neon else material)
		ball(ctx, width * 0.98, q, if i == n and tip then tip else color, if i == n and tip then Enum.Material.Neon else material)
		p = q
		d = (d + bend).Unit
	end
end

-- A ring of small blocks: around `center` in the plane spanned by u and v.
local function ring(ctx: Ctx, center: Vector3, u: Vector3, v: Vector3, radius: number, n: number, size: Vector3, color: Color3, material: Enum.Material?, from: number?, to: number?)
	local a0, a1 = from or 0, to or (math.pi * 2 * (n - 1) / n)
	for i = 0, n - 1 do
		local a = if n > 1 then a0 + (a1 - a0) * i / (n - 1) else a0
		local pos = center + (u * math.cos(a) + v * math.sin(a)) * radius
		local tangent = -u * math.sin(a) + v * math.cos(a)
		part(ctx, size, CFrame.lookAt(pos, pos + tangent, u:Cross(v)) * CFrame.Angles(0, math.pi / 2, 0), color, material)
	end
end

local function face(ctx: Ctx, size: Vector3, color: Color3, material: Enum.Material?)
	return ellipsoid(ctx, size, CFrame.new(0, -0.6, -0.58), color, material)
end

local function v3(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

-- Samurai neck guard: rows of plates round the back and sides.
local function shikoro(ctx: Ctx, rows: number, radius: number, color: Color3, lace: Color3, y0: number)
	for row = 1, rows do
		local r = radius + 0.09 * row
		local y = y0 - 0.24 * (row - 1)
		for _, deg in ipairs({ -115, -78, -40, 0, 40, 78, 115 }) do
			local a = rad(deg)
			local dir = v3(math.sin(a), 0, math.cos(a))
			local pos = v3(0, y, 0) + dir * r
			part(ctx, v3(0.46, 0.3, 0.07), CFrame.lookAt(pos, pos + dir) * CFrame.Angles(rad(-22), 0, 0), if row % 2 == 0 then lace else color, Enum.Material.Metal)
		end
	end
end

-- ===== shapes =====
local SHAPES = {}

function SHAPES.Band(ctx: Ctx, c)
	vcyl(ctx, 1.3, 0.2, v3(0, -0.36, 0), c.Main, Enum.Material.Fabric)
	part(ctx, v3(0.44, 0.2, 0.06), CFrame.new(0, -0.36, -0.66), c.Trim, Enum.Material.Metal)
	part(ctx, v3(0.24, 0.22, 0.16), CFrame.new(0, -0.36, 0.67), c.Main, Enum.Material.Fabric)
	for _, s in ipairs({ -1, 1 }) do
		part(ctx, v3(0.14, 0.6, 0.04), CFrame.new(0.12 * s, -0.66, 0.8) * CFrame.Angles(rad(28), 0, rad(-14 * s)), c.Main, Enum.Material.Fabric)
	end
end

function SHAPES.Kasa(ctx: Ctx, c)
	cone(ctx, 2.7, 0.62, -0.14, 8, c.Main, Enum.Material.Fabric)
	vcyl(ctx, 2.74, 0.03, v3(0, -0.13, 0), c.Trim, Enum.Material.Fabric)
	vcyl(ctx, 1.4, 0.05, v3(0, 0.1, 0), c.Trim, Enum.Material.Fabric)
	ball(ctx, 0.14, v3(0, 0.5, 0), c.Trim, Enum.Material.Wood)
end

function SHAPES.Hood(ctx: Ctx, c)
	ellipsoid(ctx, v3(1.42, 1.02, 1.42), CFrame.new(0, -0.38, 0.22), c.Main, Enum.Material.Fabric)
	part(ctx, v3(0.46, 0.18, 0.06), CFrame.new(0, -0.24, -0.6) * CFrame.Angles(rad(-12), 0, 0), c.Trim, Enum.Material.Metal)
	part(ctx, v3(0.12, 0.12, 0.03), CFrame.new(0, -0.24, -0.64) * CFrame.Angles(rad(-12), 0, rad(45)), BLACK, Enum.Material.Metal)
	for _, s in ipairs({ -1, 1 }) do
		part(ctx, v3(0.16, 0.7, 0.05), CFrame.new(0.14 * s, -0.75, 0.92) * CFrame.Angles(rad(22), 0, rad(-12 * s)), c.Main, Enum.Material.Fabric)
	end
end

function SHAPES.Amigasa(ctx: Ctx, c)
	vcyl(ctx, 2.3, 0.06, v3(0, -0.2, 0), c.Main, Enum.Material.Fabric)
	vcyl(ctx, 2.34, 0.03, v3(0, -0.22, 0), c.Trim, Enum.Material.Fabric)
	ellipsoid(ctx, v3(1.75, 0.95, 1.75), CFrame.new(0, -0.12, 0), c.Main, Enum.Material.Fabric)
	for _, y in ipairs({ 0.05, 0.22 }) do
		local w = if y > 0.1 then 1.2 else 1.62
		vcyl(ctx, w, 0.03, v3(0, y, 0), c.Trim, Enum.Material.Fabric)
	end
end

function SHAPES.Kitsune(ctx: Ctx, c)
	face(ctx, v3(1.02, 1.12, 0.44), c.Main)
	ellipsoid(ctx, v3(0.44, 0.36, 0.52), CFrame.new(0, -0.8, -0.86), c.Main)
	ball(ctx, 0.13, v3(0, -0.74, -1.11), BLACK)
	for _, s in ipairs({ -1, 1 }) do
		part(ctx, v3(0.28, 0.06, 0.04), CFrame.new(0.22 * s, -0.52, -0.8) * CFrame.Angles(0, 0, rad(18 * s)), c.Trim, Enum.Material.Neon)
		part(ctx, v3(0.2, 0.04, 0.03), CFrame.new(0.3 * s, -0.86, -0.78) * CFrame.Angles(0, 0, rad(-10 * s)), c.Trim)
		ellipsoid(ctx, v3(0.34, 0.56, 0.12), CFrame.new(0.36 * s, 0.08, -0.28) * CFrame.Angles(0, 0, rad(-16 * s)), c.Main)
		ellipsoid(ctx, v3(0.2, 0.38, 0.06), CFrame.new(0.36 * s, 0.06, -0.35) * CFrame.Angles(0, 0, rad(-16 * s)), c.Trim)
	end
	part(ctx, v3(0.08, 0.2, 0.03), CFrame.new(0, -0.3, -0.81), c.Accent or c.Trim, Enum.Material.Neon)
end

function SHAPES.Tengu(ctx: Ctx, c)
	face(ctx, v3(1.02, 1.14, 0.44), c.Main)
	rod(ctx, v3(0, -0.66, -0.76), v3(0, -0.6, -1.5), 0.18, c.Main)
	ball(ctx, 0.18, v3(0, -0.6, -1.5), c.Main)
	for _, s in ipairs({ -1, 1 }) do
		part(ctx, v3(0.38, 0.11, 0.1), CFrame.new(0.21 * s, -0.42, -0.8) * CFrame.Angles(0, 0, rad(16 * s)), c.Accent or WHITE)
		ball(ctx, 0.12, v3(0.22 * s, -0.53, -0.82), Color3.fromRGB(255, 210, 60), Enum.Material.Neon)
	end
	ellipsoid(ctx, v3(0.64, 0.4, 0.24), CFrame.new(0, -1.08, -0.7), c.Accent or WHITE)
	part(ctx, v3(0.34, 0.26, 0.34), CFrame.new(0, 0.06, -0.24) * CFrame.Angles(rad(-10), 0, 0), c.Trim)
end

function SHAPES.Jingasa(ctx: Ctx, c)
	cone(ctx, 2.35, 0.44, -0.14, 7, c.Main, Enum.Material.Metal)
	vcyl(ctx, 2.38, 0.03, v3(0, -0.13, 0), c.Trim, Enum.Material.Metal)
	disc(ctx, v3(0, 0.1, -0.5), v3(0, 0.55, -0.83), 0.34, 0.03, c.Trim, Enum.Material.Metal)
end

function SHAPES.Kabuto(ctx: Ctx, c)
	ellipsoid(ctx, v3(1.44, 1.02, 1.48), CFrame.new(0, -0.32, 0.02), c.Main, Enum.Material.Metal)
	part(ctx, v3(1.16, 0.06, 0.32), CFrame.new(0, -0.3, -0.72) * CFrame.Angles(rad(-14), 0, 0), c.Main, Enum.Material.Metal)
	shikoro(ctx, 2, 0.72, c.Main, c.Accent or c.Trim, -0.5)
	disc(ctx, v3(0, -0.16, -0.74), v3(0, 0, -1), 0.24, 0.05, c.Trim, Enum.Material.Metal)
	for _, s in ipairs({ -1, 1 }) do
		part(ctx, v3(0.08, 0.8, 0.04), CFrame.new(0.24 * s, 0.18, -0.72) * CFrame.Angles(0, 0, rad(-24 * s)), c.Trim, Enum.Material.Metal)
		part(ctx, v3(0.06, 0.36, 0.38), CFrame.new(0.76 * s, -0.48, -0.3) * CFrame.Angles(0, rad(30 * s), 0), c.Trim, Enum.Material.Metal)
	end
end

function SHAPES.Mempo(ctx: Ctx, c)
	ellipsoid(ctx, v3(1.0, 0.62, 0.52), CFrame.new(0, -0.94, -0.5), c.Main, Enum.Material.Metal)
	part(ctx, v3(0.2, 0.24, 0.14), CFrame.new(0, -0.68, -0.78) * CFrame.Angles(rad(-15), 0, 0), c.Main, Enum.Material.Metal)
	part(ctx, v3(0.56, 0.06, 0.06), CFrame.new(0, -0.82, -0.78), c.Accent or BLACK)
	part(ctx, v3(0.32, 0.05, 0.03), CFrame.new(0, -0.95, -0.77), c.Trim)
	for i = 1, 3 do
		part(ctx, v3(0.84 - 0.08 * i, 0.12, 0.42), CFrame.new(0, -1.14 - 0.12 * i, -0.36) * CFrame.Angles(rad(-18), 0, 0), if i % 2 == 0 then c.Trim else c.Main, Enum.Material.Metal)
	end
end

function SHAPES.Oni(ctx: Ctx, c)
	face(ctx, v3(1.1, 1.2, 0.5), c.Main)
	part(ctx, v3(0.96, 0.16, 0.2), CFrame.new(0, -0.36, -0.8), c.Main:Lerp(BLACK, 0.3))
	for _, s in ipairs({ -1, 1 }) do
		part(ctx, v3(0.22, 0.12, 0.05), CFrame.new(0.22 * s, -0.48, -0.86) * CFrame.Angles(0, 0, rad(-12 * s)), c.Accent or c.Trim, Enum.Material.Neon)
		part(ctx, v3(0.08, 0.2, 0.06), CFrame.new(0.2 * s, -0.84, -0.86), c.Trim)
		horn(ctx, v3(0.3 * s, -0.16, -0.46), v3(0.3 * s, 1, -0.1), v3(0.12 * s, -0.05, 0), 4, 0.17, 0.22, c.Trim)
	end
	ellipsoid(ctx, v3(0.32, 0.22, 0.22), CFrame.new(0, -0.66, -0.88), c.Main)
	part(ctx, v3(0.62, 0.14, 0.05), CFrame.new(0, -0.94, -0.82), BLACK)
end

function SHAPES.Hannya(ctx: Ctx, c)
	face(ctx, v3(1.02, 1.16, 0.46), c.Main)
	for _, s in ipairs({ -1, 1 }) do
		part(ctx, v3(0.22, 0.1, 0.05), CFrame.new(0.21 * s, -0.5, -0.84) * CFrame.Angles(0, 0, rad(-20 * s)), c.Accent or c.Trim, Enum.Material.Neon)
		horn(ctx, v3(0.32 * s, -0.12, -0.4), v3(0.45 * s, 1, 0.2), v3(-0.1 * s, -0.02, 0.1), 5, 0.17, 0.17, c.Trim, Enum.Material.Metal)
		part(ctx, v3(0.12, 0.6, 0.12), CFrame.new(0.52 * s, -0.5, -0.46) * CFrame.Angles(0, 0, rad(8 * s)), BLACK, Enum.Material.Fabric)
	end
	part(ctx, v3(0.62, 0.22, 0.05), CFrame.new(0, -0.9, -0.8), BLACK)
	part(ctx, v3(0.54, 0.05, 0.03), CFrame.new(0, -0.82, -0.82), c.Trim)
	part(ctx, v3(0.54, 0.05, 0.03), CFrame.new(0, -0.98, -0.82), c.Trim)
end

function SHAPES.Horns(ctx: Ctx, c)
	for _, s in ipairs({ -1, 1 }) do
		horn(ctx, v3(0.4 * s, -0.12, -0.05), v3(0.85 * s, 0.55, 0), v3(-0.18 * s, 0.12, 0.08), 6, 0.2, 0.3, c.Main, Enum.Material.SmoothPlastic, c.Trim)
		disc(ctx, v3(0.42 * s, -0.12, -0.05), v3(s, 0.4, 0), 0.34, 0.06, c.Main:Lerp(BLACK, 0.4))
	end
end

function SHAPES.Basket(ctx: Ctx, c)
	vcyl(ctx, 1.44, 1.24, v3(0, -0.54, 0), c.Main, Enum.Material.Fabric)
	ellipsoid(ctx, v3(1.44, 0.5, 1.44), CFrame.new(0, 0.07, 0), c.Main, Enum.Material.Fabric)
	for _, y in ipairs({ -1.05, -0.78, -0.25, 0.02 }) do
		vcyl(ctx, 1.47, 0.04, v3(0, y, 0), c.Trim, Enum.Material.Fabric)
	end
	part(ctx, v3(0.56, 0.16, 0.05), CFrame.new(0, -0.52, -0.72), BLACK)
	for i = -2, 2 do
		part(ctx, v3(0.03, 0.16, 0.06), CFrame.new(i * 0.1, -0.52, -0.73), c.Trim)
	end
end

function SHAPES.Cowl(ctx: Ctx, c)
	ellipsoid(ctx, v3(1.52, 1.22, 1.5), CFrame.new(0, -0.44, 0.28), c.Main, Enum.Material.Fabric)
	part(ctx, v3(0.5, 0.32, 0.5), CFrame.new(0, 0.1, 0.34) * CFrame.Angles(rad(30), 0, 0), c.Main, Enum.Material.Fabric)
	part(ctx, v3(1.02, 0.46, 0.05), CFrame.new(0, -0.96, -0.66), c.Main, Enum.Material.Fabric)
	ring(ctx, v3(0, -0.52, -0.46), Vector3.xAxis, Vector3.yAxis, 0.66, 9, v3(0.24, 0.05, 0.05), c.Trim, Enum.Material.Neon, rad(-5), rad(185))
	part(ctx, v3(1.0, 0.9, 0.08), CFrame.new(0, -1.02, 0.84) * CFrame.Angles(rad(-14), 0, 0), c.Main, Enum.Material.Fabric)
end

function SHAPES.Crown(ctx: Ctx, c)
	vcyl(ctx, 1.32, 0.22, v3(0, -0.08, 0), c.Main, Enum.Material.Metal)
	for i = 0, 7 do
		local a = rad(i * 45)
		local pos = v3(math.sin(a) * 0.62, 0.16, -math.cos(a) * 0.62)
		part(ctx, v3(0.12, 0.38, 0.06), CFrame.new(pos) * CFrame.Angles(0, -a, 0), c.Main, Enum.Material.Metal)
		ball(ctx, 0.13, pos + v3(0, 0.24, 0), c.Trim, Enum.Material.Neon)
	end
	ball(ctx, 0.17, v3(0, -0.08, -0.67), c.Trim, Enum.Material.Neon)
end

function SHAPES.Dragon(ctx: Ctx, c)
	ellipsoid(ctx, v3(1.46, 1.02, 1.5), CFrame.new(0, -0.32, 0.04), c.Main, Enum.Material.Metal)
	part(ctx, v3(0.92, 0.14, 0.4), CFrame.new(0, -0.3, -0.74) * CFrame.Angles(rad(-20), 0, 0), c.Main, Enum.Material.Metal)
	for _, s in ipairs({ -1, 1 }) do
		ball(ctx, 0.1, v3(0.3 * s, -0.2, -0.76), c.Accent or c.Trim, Enum.Material.Neon)
		horn(ctx, v3(0.38 * s, -0.08, 0.1), v3(0.3 * s, 0.55, 1), v3(0, 0.1, 0.05), 5, 0.2, 0.2, c.Trim, Enum.Material.Metal)
		part(ctx, v3(0.08, 0.5, 0.5), CFrame.new(0.72 * s, -0.64, -0.08), c.Main, Enum.Material.Metal)
	end
	for i, z in ipairs({ -0.32, -0.04, 0.24, 0.5 }) do
		part(ctx, v3(0.06, 0.3 - 0.04 * i, 0.22), CFrame.new(0, 0.16 - 0.1 * (i - 1) ^ 1.4, z) * CFrame.Angles(rad(-30), 0, 0), c.Trim, Enum.Material.Metal)
	end
end

function SHAPES.DrumHalo(ctx: Ctx, c)
	local center = v3(0, -0.38, 0.66)
	ring(ctx, center, Vector3.xAxis, Vector3.yAxis, 1.0, 20, v3(0.34, 0.08, 0.08), c.Trim, Enum.Material.Metal)
	for i = 0, 7 do
		local a = rad(i * 45 + 22.5)
		local pos = center + v3(math.cos(a), math.sin(a), 0) * 1.0
		part(ctx, v3(0.18, 0.36, 0.36), CFrame.new(pos) * CFrame.Angles(0, math.pi / 2, 0), c.Main, Enum.Material.Wood, Enum.PartType.Cylinder)
		part(ctx, v3(0.03, 0.24, 0.24), CFrame.new(pos - v3(0, 0, 0.1)) * CFrame.Angles(0, math.pi / 2, 0), c.Accent or c.Trim, Enum.Material.Neon, Enum.PartType.Cylinder)
	end
end

function SHAPES.Circlet(ctx: Ctx, c)
	vcyl(ctx, 1.3, 0.08, v3(0, -0.32, 0), c.Main, Enum.Material.Metal)
	part(ctx, v3(0.26, 0.26, 0.05), CFrame.new(0, -0.27, -0.66) * CFrame.Angles(0, 0, rad(45)), c.Main, Enum.Material.Metal)
	ball(ctx, 0.17, v3(0, -0.27, -0.69), c.Accent or c.Trim, Enum.Material.Neon)
	for _, s in ipairs({ -1, 1 }) do
		for j = 0, 2 do
			part(ctx, v3(0.06, 0.46 - 0.09 * j, 0.14), CFrame.new(0.68 * s, -0.12 - 0.05 * j, 0.06 + 0.1 * j) * CFrame.Angles(0, 0, rad((-28 - 18 * j) * s)), c.Trim)
		end
	end
	ring(ctx, v3(0, 0.36, 0.08), Vector3.xAxis, Vector3.zAxis, 0.42, 14, v3(0.2, 0.04, 0.06), c.Main, Enum.Material.Neon)
end

function SHAPES.Shogun(ctx: Ctx, c)
	ellipsoid(ctx, v3(1.52, 1.12, 1.56), CFrame.new(0, -0.3, 0.03), c.Main, Enum.Material.Metal)
	part(ctx, v3(1.2, 0.06, 0.36), CFrame.new(0, -0.3, -0.76) * CFrame.Angles(rad(-14), 0, 0), c.Main, Enum.Material.Metal)
	shikoro(ctx, 3, 0.76, c.Main, c.Accent or c.Trim, -0.48)
	for i = -4, 4 do
		local a = rad(i * 20)
		local pos = v3(math.sin(a) * 0.62, -0.02 + (1 - math.cos(a)) * 0.7, -0.76)
		part(ctx, v3(0.16, 0.12, 0.04), CFrame.new(pos) * CFrame.Angles(0, 0, -a * 1.1), c.Trim, Enum.Material.Metal)
	end
	disc(ctx, v3(0, -0.06, -0.78), v3(0, 0, -1), 0.26, 0.05, c.Accent or c.Trim)
	for _, s in ipairs({ -1, 1 }) do
		part(ctx, v3(0.06, 0.44, 0.46), CFrame.new(0.8 * s, -0.46, -0.3) * CFrame.Angles(0, rad(32 * s), 0), c.Trim, Enum.Material.Metal)
	end
end

function SHAPES.VoidCrown(ctx: Ctx, c)
	local y = 0.24
	ring(ctx, v3(0, y, 0), Vector3.xAxis, Vector3.zAxis, 0.6, 16, v3(0.26, 0.1, 0.08), c.Main, Enum.Material.Glass)
	for i = 0, 8 do
		local a = rad(i * 40)
		local pos = v3(math.sin(a) * 0.6, y + 0.24, -math.cos(a) * 0.6)
		local tall = if i == 0 then 0.62 else 0.42
		part(ctx, v3(0.1, tall, 0.1), CFrame.new(pos + v3(0, tall / 2 - 0.2, 0)) * CFrame.Angles(0, -a, rad(4)), c.Main, Enum.Material.Glass)
		ball(ctx, 0.12, pos + v3(0, tall - 0.18, 0), c.Trim, Enum.Material.Neon)
	end
	for i = 0, 2 do
		local a = rad(i * 120 + 30)
		ball(ctx, 0.16, v3(math.sin(a) * 0.95, -0.12, math.cos(a) * 0.95), c.Accent or c.Trim, Enum.Material.Neon)
	end
end

-- ===== rarity dressing =====
local function rarityExtras(rarityName: string?, anchor: BasePart?)
	local rarity = Hats.Rarity(rarityName)
	if rarity.Index < 4 or not anchor then
		return
	end
	local light = Instance.new("PointLight")
	light.Color = rarity.Color
	light.Range = 5 + rarity.Index
	light.Brightness = 0.7
	light.Shadows = false
	light.Parent = anchor
	if rarity.Index >= 5 then
		Particles.Create("Sparkle", anchor, { Color = ColorSequence.new(rarity.Color), Rate = 6 })
	end
end

local function meshHat(ctx: Ctx, def): boolean
	local name = "Hat_" .. def.Id
	if not Assets.Has(name) then
		return false
	end
	local mesh = Assets.Textured(name, def.Colors.Main)
	if not mesh then
		return false
	end
	local s = mesh.Size
	mesh.Size = s * ctx.K
	local offset = if def.Face then CFrame.new(0, -0.6, -0.6 - s.Z / 2 + 0.12) else CFrame.new(0, s.Y / 2 - 0.15, 0)
	Assets.Place(mesh, scaled(ctx, offset))
	mesh.Name = "HatPart"
	mesh.Parent = ctx.Folder
	table.insert(ctx.Parts, mesh)
	return true
end

local function build(def, rarityName: string?, origin: CFrame, k: number, folder: Instance): { BasePart }
	local ctx: Ctx = { Origin = origin, K = k, Folder = folder, Parts = {} }
	if not meshHat(ctx, def) then
		local shape = SHAPES[def.Shape] or SHAPES.Band
		shape(ctx, def.Colors)
	end
	rarityExtras(rarityName, ctx.Parts[1])
	if def.Shape == "Crown" and ctx.Parts[1] then
		Particles.Create("Embers", ctx.Parts[1], { Rate = 4 })
	elseif def.Shape == "VoidCrown" and ctx.Parts[1] then
		Particles.Create("Void", ctx.Parts[1], { Rate = 5 })
	end
	return ctx.Parts
end

-- A free-standing, anchored hat model (menu previews, world drops). Its pivot is the crown.
function HatBuilder.Build(hatOrId: any, scale: number?): Model?
	local id = if type(hatOrId) == "table" then hatOrId.Id else hatOrId
	local rarityName = if type(hatOrId) == "table" then hatOrId.R else nil
	local def = Hats.Get(id)
	if not def then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "Hat_" .. def.Id
	local root = Instance.new("Part")
	root.Name = "Crown"
	root.Size = Vector3.new(0.1, 0.1, 0.1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root
	for _, p in ipairs(build(def, rarityName, CFrame.new(), scale or 1, model)) do
		p.Anchored = true
	end
	-- Kit.Viewport looks from +Z; turn the face towards the camera
	model:SetAttribute("ViewRotation", CFrame.Angles(0, math.pi + math.rad(10), 0))
	return model
end

-- ===== wearing =====
local function headHeight(head: BasePart): number
	if head:IsA("MeshPart") then
		return head.Size.Y
	end
	return head.Size.Y * 1.2 -- R6 head: a 2x1x1 part with a scaled mesh
end

local SKIP = { "Glow", "Horn", "Halo", "Tail", "Aura" }
local function skipPiece(name: string): boolean
	for _, word in ipairs(SKIP) do
		if string.find(name, word, 1, true) then
			return true
		end
	end
	return false
end

-- Bounding box (head space) of what the outfit put on the head: hood, mask, hero head.
local function dressedBox(character: Model, head: BasePart): (Vector3?, Vector3?)
	local outfit = character:FindFirstChild("NinjaOutfit")
	if not outfit then
		return nil, nil
	end
	local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	local any = false
	for _, p in ipairs(outfit:GetDescendants()) do
		if p:IsA("BasePart") and not skipPiece(p.Name) then
			local weld = p:FindFirstChildOfClass("WeldConstraint")
			if weld and (weld.Part0 == head or weld.Part1 == head) then
				local rel = head.CFrame:ToObjectSpace(p.CFrame)
				local half = p.Size / 2
				for _, sx in ipairs({ -1, 1 }) do
					for _, sy in ipairs({ -1, 1 }) do
						for _, sz in ipairs({ -1, 1 }) do
							local corner = rel * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
							lo = Vector3.new(math.min(lo.X, corner.X), math.min(lo.Y, corner.Y), math.min(lo.Z, corner.Z))
							hi = Vector3.new(math.max(hi.X, corner.X), math.max(hi.Y, corner.Y), math.max(hi.Z, corner.Z))
						end
					end
				end
				any = true
			end
		end
	end
	if not any then
		return nil, nil
	end
	return lo, hi
end

-- Where the crown is (head space) and how much to scale the 1.2-stud hat.
function HatBuilder.Fit(character: Model, head: BasePart): (CFrame, number)
	local h = headHeight(head)
	local lo, hi = dressedBox(character, head)
	if not lo or not hi then
		local k = h / 1.2
		return CFrame.new(0, h / 2, 0), k
	end
	local width = math.clamp(hi.X - lo.X, h * 0.95, h * 1.45)
	local k = width / 1.2
	local top = math.min(hi.Y, lo.Y + h * 1.32)
	local front = lo.Z
	return CFrame.new((lo.X + hi.X) / 2, top, front + 0.6 * k), k
end

function HatBuilder.Remove(character: Model)
	local existing = character:FindFirstChild(HatBuilder.FolderName)
	if existing then
		existing:Destroy()
	end
end

-- Puts a hat record (or nil to take it off) on the character's head, welded to it.
function HatBuilder.Wear(character: Model, hat: any?): Folder?
	HatBuilder.Remove(character)
	local def = hat and Hats.Get(hat.Id)
	local head = character:FindFirstChild("Head")
	if not def or not head or not head:IsA("BasePart") then
		return nil
	end
	local fit, k = HatBuilder.Fit(character, head)
	local folder = Instance.new("Folder")
	folder.Name = HatBuilder.FolderName
	folder:SetAttribute("HatId", def.Id)
	for _, p in ipairs(build(def, hat.R, head.CFrame * fit, k, folder)) do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = p
		weld.Parent = p
	end
	folder.Parent = character
	return folder
end

return HatBuilder
