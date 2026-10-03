--[[
	CharmBuilder: part-built charms (Config/Charms) for the world drop and the menu
	preview. Each size has its own object, trimmed in the charm's rarity colour:
	  Small  a magatama bead on a cord
	  Large  an ofuda talisman slip with a glowing seal
	  Grand  an omamori charm bag with a knot and tassel
	  Hexfire Torch  a short iron-bound torch with a living flame
	Skill charms carry a glowing seal disc in the skill's colour. About 1.6 studs tall
	at scale 1, centred on the origin, front facing +Z (Kit.Viewport's camera side).
]]

local Charms = require(script.Parent.Parent.Config.Charms)
local Skills = require(script.Parent.Parent.Config.Skills)

local CharmBuilder = {}

local rgb = Color3.fromRGB
local rad = math.rad

local function part(model: Model, k: number, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	p.Name = "CharmPart"
	if shape then
		p.Shape = shape
	end
	p.Size = size * k
	p.CFrame = cf - cf.Position + cf.Position * k
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function cylinder(model, k, length: number, diameter: number, cf: CFrame, color, material)
	-- Roblox cylinders run along X; stand them up
	return part(model, k, Vector3.new(length, diameter, diameter), cf * CFrame.Angles(0, 0, rad(90)), color, material, Enum.PartType.Cylinder)
end

local function seal(model, k, cf: CFrame, color: Color3, diameter: number)
	local disc = part(model, k, Vector3.new(0.06, diameter, diameter), cf * CFrame.Angles(0, rad(90), 0), color, Enum.Material.Neon, Enum.PartType.Cylinder)
	disc.Name = "Glow"
	return disc
end

local function small(model, k, color: Color3)
	-- a comma-shaped magatama: a fat bead and a tapering tail, on a cord loop
	part(model, k, Vector3.new(0.9, 0.9, 0.55), CFrame.new(0, 0.1, 0), color:Lerp(rgb(40, 160, 110), 0.55), Enum.Material.Glass, Enum.PartType.Ball)
	part(model, k, Vector3.new(0.55, 0.55, 0.42), CFrame.new(0.28, -0.42, 0) * CFrame.Angles(0, 0, rad(-30)), color:Lerp(rgb(40, 160, 110), 0.55), Enum.Material.Glass, Enum.PartType.Ball)
	part(model, k, Vector3.new(0.3, 0.3, 0.3), CFrame.new(0.38, -0.72, 0), color:Lerp(rgb(40, 160, 110), 0.5), Enum.Material.Glass, Enum.PartType.Ball)
	part(model, k, Vector3.new(0.22, 0.22, 0.6), CFrame.new(-0.12, 0.18, 0), color, Enum.Material.Neon, Enum.PartType.Ball).Name = "Glow"
	-- cord
	for i = 0, 7 do
		local a = rad(i * 45)
		part(model, k, Vector3.new(0.1, 0.1, 0.1), CFrame.new(math.cos(a) * 0.25, 0.75 + math.sin(a) * 0.25, 0), rgb(200, 40, 50), nil, Enum.PartType.Ball)
	end
end

local function large(model, k, color: Color3)
	-- a paper slip with ink strokes and a red seal
	part(model, k, Vector3.new(0.75, 1.9, 0.05), CFrame.new(), rgb(244, 232, 200))
	part(model, k, Vector3.new(0.8, 0.12, 0.08), CFrame.new(0, 0.9, 0), color)
	part(model, k, Vector3.new(0.8, 0.12, 0.08), CFrame.new(0, -0.9, 0), color)
	for i = 0, 3 do
		part(model, k, Vector3.new(0.1, 0.22, 0.07), CFrame.new(0, 0.55 - i * 0.28, 0) * CFrame.Angles(0, 0, rad(if i % 2 == 0 then 12 else -10)), rgb(30, 24, 30))
	end
	seal(model, k, CFrame.new(0, -0.55, 0.05), color, 0.42)
end

local function grand(model, k, color: Color3)
	-- an omamori bag: brocade body, rounded top, a knot and a tassel
	local body = color:Lerp(rgb(150, 30, 40), 0.45)
	part(model, k, Vector3.new(1.05, 1.5, 0.35), CFrame.new(0, -0.15, 0), body, Enum.Material.Fabric)
	-- the rounded top: a disc facing front (cylinders run along X, so turn it)
	part(model, k, Vector3.new(0.35, 1.05, 1.05), CFrame.new(0, 0.6, 0) * CFrame.Angles(0, rad(90), 0), body, Enum.Material.Fabric, Enum.PartType.Cylinder)
	part(model, k, Vector3.new(1.08, 0.08, 0.38), CFrame.new(0, -0.55, 0), rgb(232, 186, 70), Enum.Material.Metal)
	part(model, k, Vector3.new(1.08, 0.08, 0.38), CFrame.new(0, 0.25, 0), rgb(232, 186, 70), Enum.Material.Metal)
	part(model, k, Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, 1.0, 0), rgb(232, 186, 70), nil, Enum.PartType.Ball)
	cylinder(model, k, 0.5, 0.12, CFrame.new(0, -1.15, 0), rgb(232, 186, 70))
	seal(model, k, CFrame.new(0, -0.15, 0.19), color, 0.5)
end

local function torch(model, k)
	local wood, iron = rgb(92, 60, 36), rgb(60, 58, 64)
	cylinder(model, k, 1.5, 0.28, CFrame.new(0, -0.35, 0), wood, Enum.Material.Wood)
	cylinder(model, k, 0.14, 0.36, CFrame.new(0, -0.65, 0), iron, Enum.Material.Metal)
	cylinder(model, k, 0.14, 0.36, CFrame.new(0, -0.1, 0), iron, Enum.Material.Metal)
	cylinder(model, k, 0.4, 0.52, CFrame.new(0, 0.5, 0), iron, Enum.Material.Metal)
	local flame = part(model, k, Vector3.new(0.55, 0.75, 0.55), CFrame.new(0, 0.95, 0), Charms.Hexfire.Color, Enum.Material.Neon, Enum.PartType.Ball)
	flame.Name = "Glow"
	part(model, k, Vector3.new(0.3, 0.45, 0.3), CFrame.new(0, 1.05, 0), rgb(255, 230, 140), Enum.Material.Neon, Enum.PartType.Ball).Name = "Glow"
	local fire = Instance.new("Fire")
	fire.Color = Charms.Hexfire.Color
	fire.SecondaryColor = rgb(140, 20, 200) -- hexed: a violet edge
	fire.Size = 2.2 * k
	fire.Heat = 6
	fire.Parent = flame
	local light = Instance.new("PointLight")
	light.Color = Charms.Hexfire.Color
	light.Range = 8 * k
	light.Brightness = 2
	light.Parent = flame
end

function CharmBuilder.Build(charm: any, scale: number?): Model?
	if not Charms.Valid(charm) then
		return nil
	end
	local k = scale or 1
	local model = Instance.new("Model")
	model.Name = "Charm"
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.1, 0.1, 0.1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Parent = model
	model.PrimaryPart = root
	local color = Charms.Color(charm)
	if charm.U == "hexfire" then
		torch(model, k)
	elseif charm.Z == "Small" then
		small(model, k, color)
	elseif charm.Z == "Large" then
		large(model, k, color)
	else
		grand(model, k, color)
	end
	local skill = charm.S and Skills.Get(charm.S.K)
	if skill then
		-- a skill charm: a ring of the skill's colour floating in front
		local ring = seal(model, k, CFrame.new(0, -0.15, 0.24), skill.Color, 0.32)
		ring.Name = "SkillGlow"
	end
	return model
end

return CharmBuilder
