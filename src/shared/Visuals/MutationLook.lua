--[[
	MutationLook: dresses a freshly built pet (PetBuilder) in its mutation
	(Config/Mutations). Works on the part model before it is scaled, so every
	piece added here scales with the pet.

	  Big / Giant  only bigger (PetBuilder scales by Mutation.Scale)
	  Golden       gold foil body, gold sparkles and light
	  Frozen       translucent ice, ice crystals on the back, frost particles
	  Shocked      yellow-tinted, neon bolts, flickering electric arcs (beams)
	  Shadow       near-black body, purple glowing eyes, shimmering purple aura
	  Rainbow      colours cycle through the rainbow (animated)
	  Celestial    starry night body, gold halo, star specks, galaxy particles

	MutationLook.Animator(model) returns a step function for animated looks
	(Rainbow colours, Shocked arcs) or nil; PetController calls it each frame.
	MutationLook.Drive(model) runs that step on its own while the model is
	parented (used for UI viewports).
]]

local RunService = game:GetService("RunService")

local Particles = require(script.Parent.Particles)

local MutationLook = {}

local rgb = Color3.fromRGB

-- parts that keep their own colour (eyes stay readable on every mutation)
local KEEP = { Eye = true, Shine = true }

local function bodyParts(model: Model): { BasePart }
	local list = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and not KEEP[d.Name] and not d:GetAttribute("MutationPart") then
			table.insert(list, d)
		end
	end
	return list
end

local function luminance(c: Color3): number
	return c.R * 0.3 + c.G * 0.59 + c.B * 0.11
end

local function addPart(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): BasePart
	local part = Instance.new("Part")
	part.Name = name
	if shape then
		part.Shape = shape
	end
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("MutationPart", true)
	part.Parent = model
	return part
end

local function light(body: BasePart, color: Color3, range: number, brightness: number)
	local existing = body:FindFirstChildOfClass("PointLight")
	local l = existing or Instance.new("PointLight")
	l.Color = color
	l.Range = math.max(range, if existing then existing.Range else 0)
	l.Brightness = brightness
	l.Parent = body
end

-- bounding box of the pet in the body's space (the model is built at the origin)
local function extents(model: Model): (CFrame, Vector3)
	return model:GetBoundingBox()
end

local looks = {}

function looks.Golden(model: Model, body: BasePart)
	local gold = rgb(255, 196, 40)
	for _, part in ipairs(bodyParts(model)) do
		-- keep the pet's light/dark pattern, in gold
		local l = luminance(part.Color)
		part.Color = gold:Lerp(rgb(255, 245, 190), math.clamp(l - 0.35, 0, 1)):Lerp(rgb(170, 110, 10), math.clamp(0.35 - l, 0, 0.35) * 1.6)
		part.Material = Enum.Material.Foil
		part.Reflectance = 0.25
	end
	Particles.Create("Radiance", body, { Rate = 10, Color = ColorSequence.new(rgb(255, 250, 200), rgb(255, 190, 30)) })
	light(body, rgb(255, 210, 90), 8, 1.3)
end

function looks.Frozen(model: Model, body: BasePart)
	local ice = rgb(185, 235, 255)
	for _, part in ipairs(bodyParts(model)) do
		part.Color = part.Color:Lerp(ice, 0.65)
		part.Material = Enum.Material.Ice
		part.Transparency = math.max(part.Transparency, 0.28)
		part.Reflectance = 0.15
	end
	-- a few ice crystals poking out of the back
	local cf, size = extents(model)
	local top = cf.Position.Y + size.Y * 0.5
	for i, x in ipairs({ -0.28, 0, 0.3 }) do
		local h = if i == 2 then 0.75 else 0.5
		addPart(model, "IceCrystal", Vector3.new(0.22, h, 0.22),
			CFrame.new(x * size.X, top - h * 0.25, cf.Position.Z + (i - 2) * 0.25) * CFrame.Angles(math.rad((i - 2) * 18), math.rad(45), math.rad(-x * 40)),
			rgb(220, 248, 255), Enum.Material.Glass).Transparency = 0.2
	end
	Particles.Create("Frost", body, { Rate = 9 })
	light(body, rgb(170, 225, 255), 7, 0.9)
end

function looks.Shocked(model: Model, body: BasePart)
	local volt = rgb(255, 240, 80)
	for _, part in ipairs(bodyParts(model)) do
		part.Color = part.Color:Lerp(volt, 0.3)
	end
	local cf, size = extents(model)
	local center = cf.Position
	-- neon zigzag bolts on both flanks
	for side = -1, 1, 2 do
		local x = center.X + side * (size.X * 0.5 + 0.08)
		local points = { Vector3.new(x, center.Y + 0.55, center.Z - 0.25), Vector3.new(x, center.Y + 0.1, center.Z + 0.15), Vector3.new(x, center.Y + 0.05, center.Z - 0.15), Vector3.new(x, center.Y - 0.45, center.Z + 0.25) }
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			addPart(model, "Bolt", Vector3.new(0.09, 0.09, (b - a).Magnitude + 0.06), CFrame.lookAt((a + b) / 2, b), rgb(255, 250, 170), Enum.Material.Neon)
		end
	end
	-- electric arcs: beams between points around the body, re-bent by the animator
	local radius = math.max(size.X, size.Y, size.Z) * 0.55
	for i = 1, 3 do
		local a0 = Instance.new("Attachment")
		a0.Name = "ArcA"
		local angle = i * math.pi * 2 / 3
		a0.Position = Vector3.new(math.cos(angle) * radius, 0.3 * radius, math.sin(angle) * radius)
		a0.Parent = body
		local a1 = Instance.new("Attachment")
		a1.Name = "ArcB"
		a1.Position = Vector3.new(math.cos(angle + 2) * radius, -0.3 * radius, math.sin(angle + 2) * radius)
		a1.Parent = body
		local beam = Instance.new("Beam")
		beam.Name = "Arc"
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Color = ColorSequence.new(rgb(255, 255, 210), rgb(120, 210, 255))
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Width0 = 0.12
		beam.Width1 = 0.05
		beam.Segments = 8
		beam.FaceCamera = true
		beam.CurveSize0 = 0.8
		beam.CurveSize1 = -0.8
		beam.Transparency = NumberSequence.new(0)
		beam.Parent = body
	end
	Particles.Create("Lightning", body, { Rate = 12, Color = ColorSequence.new(rgb(255, 250, 180), rgb(120, 200, 255)) })
	light(body, rgb(255, 240, 140), 8, 1.2)
end

function looks.Shadow(model: Model, body: BasePart)
	local dark = rgb(24, 14, 38)
	for _, part in ipairs(bodyParts(model)) do
		part.Color = part.Color:Lerp(dark, 0.8)
		if part.Material == Enum.Material.Neon then
			part.Color = rgb(170, 90, 255)
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "Eye" then
			d.Color = rgb(200, 120, 255)
			d.Material = Enum.Material.Neon
		end
	end
	-- shimmering purple aura around the whole pet
	local cf, size = extents(model)
	local d = math.max(size.X, size.Y, size.Z) * 1.08
	local aura = addPart(model, "Aura", Vector3.new(d, d, d), CFrame.new(cf.Position), rgb(150, 70, 255), Enum.Material.ForceField, Enum.PartType.Ball)
	aura.Transparency = 0.25
	Particles.Create("Shadow", body, { Rate = 14 })
	light(body, rgb(150, 70, 255), 8, 1.4)
end

local function rainbowColor(phase: number): Color3
	return Color3.fromHSV(phase % 1, 0.62, 1)
end

function looks.Rainbow(model: Model, body: BasePart)
	-- each part gets a phase from its height and depth, so colour bands sweep over the pet
	for _, part in ipairs(bodyParts(model)) do
		local pos = part.CFrame.Position
		local phase = pos.Y * 0.32 + pos.Z * 0.2
		part:SetAttribute("RainbowPhase", phase)
		part.Color = rainbowColor(phase)
		part.Material = if part.Material == Enum.Material.Neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
	Particles.Create("Sparkle", body, {
		Rate = 14,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, rgb(255, 90, 90)), ColorSequenceKeypoint.new(0.25, rgb(255, 230, 80)),
			ColorSequenceKeypoint.new(0.5, rgb(90, 255, 140)), ColorSequenceKeypoint.new(0.75, rgb(90, 170, 255)),
			ColorSequenceKeypoint.new(1, rgb(220, 110, 255)),
		}),
	})
	light(body, rgb(255, 160, 230), 8, 1.2)
end

function looks.Celestial(model: Model, body: BasePart)
	local night = rgb(34, 26, 92)
	for _, part in ipairs(bodyParts(model)) do
		local l = luminance(part.Color)
		if part.Material == Enum.Material.Neon then
			part.Color = rgb(255, 225, 120)
		else
			-- the pet's dark areas become deep space, its light areas glow pale gold
			part.Color = night:Lerp(rgb(110, 90, 200), math.clamp(l, 0, 1) * 0.6)
			part.Material = Enum.Material.SmoothPlastic
			part.Reflectance = 0.1
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "Eye" then
			d.Color = rgb(255, 255, 255)
			d.Material = Enum.Material.Neon
		end
	end
	local cf, size = extents(model)
	local center = cf.Position
	-- star specks scattered over the body (deterministic, so every copy matches)
	local rng = Random.new(7)
	for _ = 1, 12 do
		local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.6, 1), rng:NextNumber(-1, 1)).Unit
		local s = rng:NextNumber(0.08, 0.15)
		addPart(model, "Star", Vector3.new(s, s, s), CFrame.new(center + dir * size * 0.5 * 0.92), rgb(255, 250, 220), Enum.Material.Neon, Enum.PartType.Ball)
	end
	-- gold halo floating above the head
	local top = center.Y + size.Y * 0.5
	local headZ = center.Z - size.Z * 0.18
	for i = 0, 11 do
		local a = i * math.pi * 2 / 12
		local pos = Vector3.new(math.cos(a) * 0.42, top + 0.32, headZ + math.sin(a) * 0.42)
		addPart(model, "Halo", Vector3.new(0.1, 0.08, 0.24), CFrame.lookAt(pos, pos + Vector3.new(-math.sin(a), 0, math.cos(a))), rgb(255, 215, 90), Enum.Material.Neon)
	end
	Particles.Create("Galaxy", body, { Rate = 16 })
	Particles.Create("Stars", body, { Rate = 8 })
	light(body, rgb(255, 230, 150), 10, 1.6)
end

-- Secret (Mutation Machine only): a black glitch with neon seams that shift colour,
-- an outline that cycles through the rainbow, orbiting runes and a galaxy haze.
function looks.Secret(model: Model, body: BasePart)
	local void = rgb(10, 6, 18)
	local i = 0
	for _, part in ipairs(bodyParts(model)) do
		i += 1
		if part.Material == Enum.Material.Neon or i % 4 == 0 then
			part.Material = Enum.Material.Neon
			part:SetAttribute("SecretPhase", i * 0.13)
			part.Color = Color3.fromHSV((i * 0.13) % 1, 0.8, 1)
		else
			part.Color = void:Lerp(rgb(60, 30, 90), luminance(part.Color) * 0.4)
			part.Material = Enum.Material.SmoothPlastic
			part.Reflectance = 0.2
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "Eye" then
			d.Color = rgb(255, 60, 200)
			d.Material = Enum.Material.Neon
		end
	end
	local cf, size = extents(model)
	local center = cf.Position
	local r = math.max(size.X, size.Z) * 0.62
	for k = 0, 5 do
		local a = k * math.pi / 3
		local rune = addPart(model, "Rune", Vector3.new(0.22, 0.22, 0.22), CFrame.new(center + Vector3.new(math.cos(a) * r, 0.2 + (k % 2) * 0.35, math.sin(a) * r)) * CFrame.Angles(0.6, a, 0.6), rgb(255, 255, 255), Enum.Material.Neon)
		rune:SetAttribute("SecretPhase", k / 6)
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "SecretOutline"
	highlight.FillTransparency = 1
	highlight.OutlineColor = rgb(255, 60, 200)
	highlight.Parent = model
	Particles.Create("Galaxy", body, { Rate = 18 })
	Particles.Create("Void", body, { Rate = 10 })
	light(body, rgb(255, 60, 200), 10, 1.8)
end

-- A hat's mutation (Mutation Machine): recolours the hat's parts the way the pet looks
-- do and adds the mutation's particles to `emitter` (a part of the hat).
function MutationLook.Tint(parts: { BasePart }, mutationId: string?, emitter: BasePart?)
	local id = mutationId
	if not id then
		return
	end
	for i, part in ipairs(parts) do
		if part.Transparency >= 1 then
			continue
		end
		local l = luminance(part.Color)
		if id == "Golden" then
			part.Color = rgb(255, 196, 40):Lerp(rgb(255, 245, 190), math.clamp(l - 0.35, 0, 1))
			part.Material = Enum.Material.Foil
		elseif id == "Frozen" then
			part.Color = part.Color:Lerp(rgb(185, 235, 255), 0.65)
			part.Material = Enum.Material.Ice
		elseif id == "Shocked" then
			part.Color = part.Color:Lerp(rgb(255, 240, 80), 0.35)
		elseif id == "Shadow" then
			part.Color = part.Color:Lerp(rgb(24, 14, 38), 0.8)
		elseif id == "Rainbow" then
			part.Color = rainbowColor(i * 0.11)
		elseif id == "Celestial" then
			part.Color = rgb(34, 26, 92):Lerp(rgb(255, 225, 120), math.clamp(l, 0, 1) * 0.5)
		elseif id == "Secret" then
			part.Color = if i % 3 == 0 then Color3.fromHSV((i * 0.13) % 1, 0.8, 1) else rgb(12, 8, 20)
			part.Material = if i % 3 == 0 then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end
	if emitter then
		local preset = ({ Golden = "Radiance", Frozen = "Frost", Shocked = "Lightning", Shadow = "Shadow", Rainbow = "Sparkle", Celestial = "Stars", Secret = "Galaxy", Big = "Sparkle", Giant = "Sparkle" })[id]
		if preset then
			Particles.Create(preset, emitter, { Rate = 6 })
		end
	end
end

-- Applies the look for `mutation` (a Config/Mutations entry) to `model`.
function MutationLook.Apply(model: Model, body: BasePart, mutation)
	model:SetAttribute("Mutation", mutation.Id)
	local look = looks[mutation.Id]
	if look then
		look(model, body)
	end
end

-- Step function for animated looks, or nil.
function MutationLook.Animator(model: Model): ((number) -> ())?
	local id = model:GetAttribute("Mutation")
	if id == "Rainbow" then
		local parts, phases = {}, {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				local phase = d:GetAttribute("RainbowPhase")
				if type(phase) == "number" then
					table.insert(parts, d)
					table.insert(phases, phase)
				end
			end
		end
		return function(t: number)
			local shift = t * 0.35
			for i, part in ipairs(parts) do
				part.Color = rainbowColor(phases[i] + shift)
			end
		end
	elseif id == "Secret" then
		local parts, phases = {}, {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and type(d:GetAttribute("SecretPhase")) == "number" then
				table.insert(parts, d)
				table.insert(phases, d:GetAttribute("SecretPhase"))
			end
		end
		local outline = model:FindFirstChild("SecretOutline")
		return function(t: number)
			for i, part in ipairs(parts) do
				part.Color = Color3.fromHSV((phases[i] + t * 0.5) % 1, 0.8, 1)
			end
			if outline and outline:IsA("Highlight") then
				outline.OutlineColor = Color3.fromHSV((t * 0.3) % 1, 0.9, 1)
			end
		end
	elseif id == "Shocked" then
		local beams = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("Beam") and d.Name == "Arc" then
				table.insert(beams, d)
			end
		end
		local rng = Random.new()
		local nextFlicker = 0
		return function(t: number)
			if t < nextFlicker then
				return
			end
			nextFlicker = t + 0.07
			for _, beam in ipairs(beams) do
				beam.Enabled = rng:NextNumber() < 0.7
				beam.CurveSize0 = rng:NextNumber(-1.5, 1.5)
				beam.CurveSize1 = rng:NextNumber(-1.5, 1.5)
			end
		end
	end
	return nil
end

-- Runs the model's animator every frame while it is parented (UI viewports).
function MutationLook.Drive(model: Model)
	local animate = MutationLook.Animator(model)
	if not animate then
		return
	end
	local seen = false
	local started = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not model.Parent then
			-- stop once it is destroyed (or if it never got shown)
			if seen or os.clock() - started > 5 then
				conn:Disconnect()
			end
			return
		end
		seen = true
		animate(os.clock())
	end)
end

return MutationLook
