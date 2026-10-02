--[[
	Builds small, chunky companion models from parts. All parts are anchored and
	non-colliding: pets are rendered and moved purely on the client (PetController),
	so they cost nothing on the server or the network.

	Returned model's PrimaryPart is "Body"; forward is -Z.
]]

local Particles = require(script.Parent.Particles)
local MutationLook = require(script.Parent.MutationLook)
local Rarity = require(script.Parent.Parent.Config.Rarity)
local Mutations = require(script.Parent.Parent.Config.Mutations)

local PetBuilder = {}

local rgb = Color3.fromRGB

local function p(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): BasePart
	local part = Instance.new("Part")
	part.Name = name
	if shape then
		part.Shape = shape
	end
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

local function w(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	local part = Instance.new("WedgePart")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = model
	return part
end

local function eyes(model: Model, center: CFrame, spacing: number, size: number, color: Color3, glow: boolean?)
	for side = -1, 1, 2 do
		local e = p(model, "Eye", Vector3.new(size, size * 1.2, size * 0.5), center * CFrame.new(side * spacing, 0, 0), color, if glow then Enum.Material.Neon else Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		p(model, "Shine", Vector3.new(size, size, size) * 0.35, e.CFrame * CFrame.new(size * 0.15, size * 0.25, -size * 0.2), Color3.new(1, 1, 1), Enum.Material.Neon, Enum.PartType.Ball)
	end
end

local function horns(model: Model, head: CFrame, spread: number, height: number, color: Color3)
	for side = -1, 1, 2 do
		w(model, "Horn", Vector3.new(0.08, height, height * 0.5), head * CFrame.new(side * spread, height * 0.6, 0.05) * CFrame.Angles(0, math.pi / 2, math.rad(side * -20)), color, Enum.Material.SmoothPlastic)
	end
end

local builders = {}

function builders.Blob(model: Model, pet)
	local c = pet.Colors
	local body = p(model, "Body", Vector3.new(1.6, 1.4, 1.6), CFrame.new(), c.Body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	p(model, "Belly", Vector3.new(1.1, 0.9, 0.6), CFrame.new(0, -0.2, -0.55), c.Accent, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	eyes(model, CFrame.new(0, 0.2, -0.72), 0.3, 0.28, c.Eyes)
	if pet.Horns then
		horns(model, CFrame.new(0, 0.5, 0), 0.4, 0.5, c.Accent)
	end
	return body
end

function builders.Wisp(model: Model, pet)
	local c = pet.Colors
	local body = p(model, "Body", Vector3.new(1.4, 1.4, 1.4), CFrame.new(), c.Body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	body.Transparency = 0.2
	p(model, "Core", Vector3.new(0.8, 0.8, 0.8), CFrame.new(), c.Accent, Enum.Material.Neon, Enum.PartType.Ball)
	for i = 1, 3 do
		local t = p(model, "Tail", Vector3.new(1, 1, 1) * (1 - i * 0.25), CFrame.new(0, -i * 0.35, i * 0.4), c.Body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		t.Transparency = 0.25 + i * 0.15
	end
	eyes(model, CFrame.new(0, 0.15, -0.64), 0.25, 0.22, c.Eyes, true)
	return body
end

function builders.Mini(model: Model, pet)
	local c = pet.Colors
	local body = p(model, "Body", Vector3.new(1, 1, 0.8), CFrame.new(0, -0.3, 0), c.Body, Enum.Material.SmoothPlastic)
	local head = p(model, "Head", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 0.6, 0), c.Body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	p(model, "Band", Vector3.new(0.2, 1.24, 1.24), CFrame.new(0, 0.75, 0) * CFrame.Angles(0, 0, math.pi / 2), c.Accent, Enum.Material.Fabric, Enum.PartType.Cylinder)
	p(model, "Face", Vector3.new(0.8, 0.3, 0.1), CFrame.new(0, 0.55, -0.58), rgb(235, 200, 170))
	eyes(model, CFrame.new(0, 0.55, -0.64), 0.18, 0.14, c.Eyes, pet.Horns)
	p(model, "Belt", Vector3.new(1.04, 0.18, 0.84), CFrame.new(0, -0.45, 0), c.Accent)
	for side = -1, 1, 2 do
		p(model, "Arm", Vector3.new(0.3, 0.7, 0.3), CFrame.new(side * 0.62, -0.3, 0), c.Body)
		p(model, "Foot", Vector3.new(0.35, 0.25, 0.45), CFrame.new(side * 0.25, -0.9, -0.05), c.Accent)
	end
	p(model, "Sword", Vector3.new(0.06, 0.12, 1.1), CFrame.new(0.62, -0.5, -0.5), rgb(220, 220, 230), Enum.Material.Metal)
	if pet.Horns then
		horns(model, head.CFrame, 0.35, 0.45, c.Accent)
	end
	return body
end

function builders.Quad(model: Model, pet)
	local c = pet.Colors
	local body = p(model, "Body", Vector3.new(1, 0.9, 1.5), CFrame.new(0, -0.2, 0.1), c.Body, Enum.Material.SmoothPlastic)
	local head = p(model, "Head", Vector3.new(1.05, 1, 1), CFrame.new(0, 0.4, -0.75), c.Body, Enum.Material.SmoothPlastic)
	p(model, "Snout", Vector3.new(0.5, 0.35, 0.35), head.CFrame * CFrame.new(0, -0.2, -0.6), c.Accent)
	p(model, "Nose", Vector3.new(0.18, 0.12, 0.08), head.CFrame * CFrame.new(0, -0.08, -0.8), rgb(20, 20, 20))
	eyes(model, head.CFrame * CFrame.new(0, 0.1, -0.52), 0.24, 0.18, c.Eyes, pet.Particles ~= nil)
	for side = -1, 1, 2 do
		w(model, "Ear", Vector3.new(0.1, 0.45, 0.3), head.CFrame * CFrame.new(side * 0.3, 0.65, 0.1) * CFrame.Angles(0, math.pi / 2, 0), c.Body)
		for z = -1, 1, 2 do
			p(model, "Leg", Vector3.new(0.28, 0.5, 0.28), CFrame.new(side * 0.32, -0.8, 0.1 + z * 0.5), c.Body)
			p(model, "Paw", Vector3.new(0.32, 0.14, 0.36), CFrame.new(side * 0.32, -1.02, 0.05 + z * 0.5), c.Accent)
		end
	end
	local tails = pet.Tails or 1
	for i = 1, tails do
		local spread = if tails > 1 then (i - (tails + 1) / 2) * 0.35 else 0
		local cf = CFrame.new(0, 0.1, 0.9) * CFrame.Angles(math.rad(40), spread, 0)
		local t = p(model, "Tail", Vector3.new(0.3, 0.3, 1), cf * CFrame.new(0, 0, 0.45), c.Body)
		p(model, "TailTip", Vector3.new(0.34, 0.34, 0.35), t.CFrame * CFrame.new(0, 0, 0.5), c.Accent)
	end
	if pet.Horns then
		horns(model, head.CFrame, 0.3, 0.5, c.Accent)
	end
	return body
end

function builders.Cat(model: Model, pet)
	local c = pet.Colors
	local body = p(model, "Body", Vector3.new(1.3, 1.2, 1.1), CFrame.new(0, -0.3, 0), c.Body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	local head = p(model, "Head", Vector3.new(1.3, 1.1, 1.1), CFrame.new(0, 0.6, 0), c.Body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	for side = -1, 1, 2 do
		w(model, "Ear", Vector3.new(0.1, 0.45, 0.35), head.CFrame * CFrame.new(side * 0.35, 0.55, 0) * CFrame.Angles(0, math.pi / 2, 0), c.Body)
	end
	eyes(model, head.CFrame * CFrame.new(0, 0.05, -0.52), 0.26, 0.2, c.Eyes)
	p(model, "Collar", Vector3.new(0.15, 1, 1), CFrame.new(0, 0.12, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(220, 40, 40), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	p(model, "Bell", Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, 0.02, -0.5), c.Accent, Enum.Material.Foil, Enum.PartType.Ball)
	-- raised beckoning paw
	p(model, "Paw", Vector3.new(0.35, 0.6, 0.35), CFrame.new(0.55, 0.3, -0.25) * CFrame.Angles(0, 0, math.rad(-15)), c.Body)
	p(model, "Coin", Vector3.new(0.08, 0.6, 0.6), CFrame.new(-0.3, -0.35, -0.6) * CFrame.Angles(0, math.pi / 2, 0), c.Accent, Enum.Material.Foil, Enum.PartType.Cylinder)
	return body
end

function builders.Bird(model: Model, pet)
	local c = pet.Colors
	local body = p(model, "Body", Vector3.new(1, 1, 1.3), CFrame.new(), c.Body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	local head = p(model, "Head", Vector3.new(0.8, 0.8, 0.8), CFrame.new(0, 0.55, -0.45), c.Body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	w(model, "Beak", Vector3.new(0.18, 0.18, 0.35), head.CFrame * CFrame.new(0, -0.05, -0.5) * CFrame.Angles(0, math.pi, 0), c.Accent)
	eyes(model, head.CFrame * CFrame.new(0, 0.1, -0.35), 0.2, 0.14, c.Eyes, pet.Glow)
	p(model, "Crest", Vector3.new(0.08, 0.35, 0.4), head.CFrame * CFrame.new(0, 0.45, 0.05), c.Accent)
	for side = -1, 1, 2 do
		local wing = p(model, "Wing", Vector3.new(1.2, 0.12, 0.7), CFrame.new(side * 0.85, 0.15, 0.05) * CFrame.Angles(0, 0, math.rad(side * 20)), c.Accent)
		wing:SetAttribute("Flap", side)
	end
	w(model, "TailFeathers", Vector3.new(0.5, 0.12, 0.7), CFrame.new(0, 0, 0.9), c.Accent)
	return body
end

function builders.Dragon(model: Model, pet)
	local c = pet.Colors
	local body = p(model, "Body", Vector3.new(1.1, 1, 1.6), CFrame.new(0, -0.1, 0.1), c.Body, Enum.Material.SmoothPlastic)
	p(model, "Belly", Vector3.new(0.8, 0.3, 1.3), CFrame.new(0, -0.55, 0.1), c.Accent)
	local head = p(model, "Head", Vector3.new(0.9, 0.8, 1.1), CFrame.new(0, 0.55, -0.9), c.Body)
	p(model, "Snout", Vector3.new(0.6, 0.4, 0.5), head.CFrame * CFrame.new(0, -0.15, -0.7), c.Body)
	eyes(model, head.CFrame * CFrame.new(0, 0.15, -0.56), 0.25, 0.16, c.Eyes, true)
	horns(model, head.CFrame * CFrame.new(0, 0.1, 0.3), 0.25, 0.55, c.Accent)
	for side = -1, 1, 2 do
		local wing = w(model, "Wing", Vector3.new(0.1, 0.9, 1.3), CFrame.new(side * 0.9, 0.45, 0.2) * CFrame.Angles(0, 0, math.rad(side * -70)), c.Accent)
		wing:SetAttribute("Flap", side)
		for z = -1, 1, 2 do
			p(model, "Leg", Vector3.new(0.3, 0.45, 0.3), CFrame.new(side * 0.35, -0.7, 0.1 + z * 0.5), c.Body)
		end
	end
	for i = 1, 3 do
		p(model, "Tail", Vector3.new(0.5, 0.5, 0.6) * (1 - i * 0.18), CFrame.new(0, -0.1 + i * 0.12, 0.9 + i * 0.45), c.Body)
	end
	for i = 1, 3 do
		w(model, "Spine", Vector3.new(0.08, 0.3, 0.3), CFrame.new(0, 0.5, -0.4 + i * 0.4), c.Accent)
	end
	return body
end

function builders.Fish(model: Model, pet)
	local c = pet.Colors
	local body = p(model, "Body", Vector3.new(0.9, 1, 1.6), CFrame.new(), c.Body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	for i = 1, 3 do
		p(model, "Spot", Vector3.new(0.4, 0.4, 0.4), CFrame.new(((i % 2) - 0.5) * 0.7, 0.25 - i * 0.12, -0.3 + i * 0.3), c.Accent, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end
	eyes(model, CFrame.new(0, 0.15, -0.72), 0.3, 0.16, c.Eyes)
	w(model, "Fin", Vector3.new(0.06, 0.4, 0.6), CFrame.new(0, 0.6, 0.1), c.Accent)
	local tail = w(model, "Tail", Vector3.new(0.08, 0.8, 0.6), CFrame.new(0, 0.2, 1) * CFrame.Angles(math.rad(-20), 0, 0), c.Accent)
	tail:SetAttribute("Flap", 1)
	return body
end

function builders.Dummy(model: Model, pet)
	local c = pet.Colors
	local body = p(model, "Body", Vector3.new(1.2, 1.1, 1.1), CFrame.new(0, -0.1, 0) * CFrame.Angles(0, 0, math.pi / 2), c.Body, Enum.Material.Fabric, Enum.PartType.Cylinder)
	p(model, "Head", Vector3.new(0.8, 0.8, 0.8), CFrame.new(0, 0.75, 0), c.Body, Enum.Material.Fabric, Enum.PartType.Ball)
	p(model, "Arms", Vector3.new(1.8, 0.2, 0.2), CFrame.new(0, 0.2, 0), rgb(120, 80, 50), Enum.Material.Wood)
	p(model, "Target", Vector3.new(0.05, 0.6, 0.6), CFrame.new(0, -0.05, -0.56) * CFrame.Angles(0, math.pi / 2, 0), c.Accent, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	eyes(model, CFrame.new(0, 0.8, -0.38), 0.15, 0.12, c.Eyes)
	p(model, "Stick", Vector3.new(0.2, 0.6, 0.2), CFrame.new(0, -0.95, 0), rgb(120, 80, 50), Enum.Material.Wood)
	return body
end

-- `mutation` (a Config/Mutations id, optional) adds its look and size; the model
-- gets attributes Mutation and MutationScale.
function PetBuilder.Build(pet, scale: number?, mutation: string?): Model
	local model = Instance.new("Model")
	model.Name = pet.Id
	local builder = builders[pet.Shape] or builders.Blob
	local body = builder(model, pet)
	model.PrimaryPart = body
	-- the model's pivot follows the body's position but never its rotation (the
	-- dummy's body is a cylinder turned on its side, which tipped the whole pet over)
	body.PivotOffset = (body.CFrame - body.CFrame.Position):Inverse()

	local rarity = Rarity.Info[pet.Rarity]
	if pet.Particles then
		Particles.Create(pet.Particles, body, { Rate = 6 })
	end
	if rarity and rarity.Glow then
		local light = Instance.new("PointLight")
		light.Color = if pet.Glow then pet.Colors.Accent else rarity.Color
		light.Range = 6
		light.Brightness = 1
		light.Parent = body
		if rarity.Index >= 5 then
			Particles.Create("Sparkle", body, { Rate = 4, Color = ColorSequence.new(rarity.Color) })
		end
	end

	local m = Mutations.Get(mutation)
	if m then
		MutationLook.Apply(model, body, m)
		model:SetAttribute("MutationScale", m.Scale)
		model.Name = pet.Id .. "_" .. m.Id
	end
	local finalScale = (scale or 1) * (if m then m.Scale else 1)
	if finalScale ~= 1 then
		model:ScaleTo(finalScale)
	end
	return model
end

return PetBuilder
