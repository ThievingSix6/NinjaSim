--[[
	Builds the companions: chunky, rounded "chibi" models (big heads, big shiny eyes,
	blush, stubby limbs) from parts. All parts are anchored and non-colliding: pets
	are rendered and moved purely on the client (PetController), so they cost nothing
	on the server or the network.

	Shape (Config/Pets) picks the body plan and Look tunes it per species:
	  Quad    four-legged: Ears = Pointy | Round | Floppy | None, Snout = Fox | Short |
	          Wolf | Lizard, Tail = Fluffy | Thin | Ringed | Lizard | Stub, Legs = Long,
	          Patches (panda), Mask (tanuki), Chest, Belly, Antlers, Mane, Spots, Crown
	  Cat     maneki-neko (Kabuto = samurai helmet)
	  Bird    Kind = Crane | Bat | Owl | Phoenix | Thunder (default: round songbird)
	  Dragon  Kind = Serpent | Kirin (default: winged chibi dragon)
	  Fish    koi
	  Blob    Kind = OniMask | Cloud (default: slime)
	  Wisp    Kind = Sprite | Wraith | Crown (default: spirit flame)
	  Mini    Kind = Ninja | Samurai | Imp | Golem | Rift
	  Dummy   straw training dummy
	pet.Horns, pet.Tails (Quad) and pet.Glow still apply.

	Rounded pieces are Parts with a Sphere SpecialMesh (an ellipsoid that fills the
	part's size, so it scales with Model:ScaleTo). Wings and tails that flap carry a
	"Flap" attribute (direction) and a "Hinge" (Vector3, part space) for PetController.
	"Eye" and "Shine" parts keep their colours under every mutation (MutationLook).

	Returned model's PrimaryPart is "Body" (at the origin, feet about 1 stud below it);
	forward is -Z.
]]

local Particles = require(script.Parent.Particles)
local MutationLook = require(script.Parent.MutationLook)
local Rarity = require(script.Parent.Parent.Config.Rarity)
local Mutations = require(script.Parent.Parent.Config.Mutations)

local PetBuilder = {}

local rgb = Color3.fromRGB
local SMOOTH = Enum.Material.SmoothPlastic
local INK = rgb(28, 22, 34)
local BLUSH = rgb(255, 140, 160)

local function base(model: Model, class: string, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	local part = Instance.new(class) :: BasePart
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material or SMOOTH
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

-- Ellipsoid filling `size` (any proportions).
local function E(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	local part = base(model, "Part", name, size, cf, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

local function box(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	return base(model, "Part", name, size, cf, color, material)
end

-- Cylinder along its X axis.
local function cyl(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	local part = base(model, "Part", name, size, cf, color, material) :: Part
	part.Shape = Enum.PartType.Cylinder
	return part
end

local function wedge(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	return base(model, "WedgePart", name, size, cf, color, material)
end

-- A flapping piece (PetController): it swings about the model's `axis` ("Z" = the
-- body's long axis, wings beat up and down; "Y" = upright, tails wag side to side)
-- through `hinge`, a point in model space (the body is built at the origin).
local function flap(part: BasePart, direction: number, hinge: Vector3, axis: string?)
	part:SetAttribute("Flap", direction)
	part:SetAttribute("Hinge", hinge)
	part:SetAttribute("FlapAxis", axis or "Z")
end

local function luminance(c: Color3): number
	return c.R * 0.3 + c.G * 0.59 + c.B * 0.11
end

-- A point on the front of an ellipsoid head (size `s`, frame `cf`) at (x, y) across it,
-- pushed `out` studs off the surface.
local function onFace(cf: CFrame, s: Vector3, x: number, y: number, out: number?): CFrame
	local a, b, c = s.X / 2, s.Y / 2, s.Z / 2
	local k = math.max(0.05, 1 - (x / a) ^ 2 - (y / b) ^ 2)
	return cf * CFrame.new(x, y, -c * math.sqrt(k) - (out or 0))
end

--[[
	Big shiny eyes, blush and a little mouth on an ellipsoid head.
	opts: Spacing (fraction of head width), Size (fraction of head width), Y (fraction
	of head height), Glow, Mouth = "Smile" | "Fangs" | "Grin" | "None", Blush (default true)
]]
local function face(model: Model, pet, cf: CFrame, s: Vector3, opts: any?)
	local o = opts or {}
	local eyeColor = pet.Colors.Eyes
	local glow = o.Glow or pet.Glow or false
	-- light eye colours read as glowing irises around a dark pupil; dark ones as big pupils
	local bright = luminance(eyeColor) > 0.62
	local size = s.X * (o.Size or 0.2)
	local spacing = s.X * (o.Spacing or 0.21)
	local y = s.Y * (o.Y or 0.04)
	local lift = o.Out or 0 -- extra push off the head (eyes over a face patch)
	for side = -1, 1, 2 do
		local at = onFace(cf, s, side * spacing, y, lift - size * 0.12)
		local eye = E(model, "Eye", Vector3.new(size, size * 1.25, size * 0.45), at, if bright then INK else eyeColor, if glow and not bright then Enum.Material.Neon else SMOOTH)
		if bright then
			E(model, "Eye", Vector3.new(size * 0.66, size * 0.86, size * 0.2), eye.CFrame * CFrame.new(0, -size * 0.08, -size * 0.17), eyeColor, if glow then Enum.Material.Neon else SMOOTH)
		end
		E(model, "Shine", Vector3.one * size * 0.42, eye.CFrame * CFrame.new(side * size * 0.14, size * 0.24, -size * 0.2), Color3.new(1, 1, 1), Enum.Material.Neon)
		E(model, "Shine", Vector3.one * size * 0.2, eye.CFrame * CFrame.new(-side * size * 0.14, -size * 0.26, -size * 0.2), Color3.new(1, 1, 1), Enum.Material.Neon)
		if o.Blush ~= false then
			local blush = E(model, "Blush", Vector3.new(size * 0.9, size * 0.45, size * 0.2), onFace(cf, s, side * spacing * 1.35, y - size * 0.85, lift - 0.02), BLUSH)
			blush.Transparency = 0.35
		end
	end
	local mouth = o.Mouth or "Smile"
	if mouth ~= "None" then
		local at = onFace(cf, s, 0, y - size * 1.05, lift - 0.01)
		if mouth == "Grin" then
			E(model, "Mouth", Vector3.new(size * 1.6, size * 0.55, size * 0.25), at, INK)
			for i = -2, 2 do
				wedge(model, "Fang", Vector3.new(size * 0.22, size * 0.32, size * 0.1), at * CFrame.new(i * size * 0.28, size * 0.12, -size * 0.12) * CFrame.Angles(math.pi, 0, 0), Color3.new(1, 1, 1))
			end
		else
			E(model, "Mouth", Vector3.new(size * 0.55, size * 0.22, size * 0.15), at, INK)
			if mouth == "Fangs" then
				for side = -1, 1, 2 do
					wedge(model, "Fang", Vector3.new(size * 0.14, size * 0.3, size * 0.1), at * CFrame.new(side * size * 0.18, -size * 0.16, -size * 0.05) * CFrame.Angles(math.pi, 0, 0), Color3.new(1, 1, 1))
				end
			end
		end
	end
end

-- Two curved horns on top of a head.
local function horns(model: Model, cf: CFrame, spread: number, height: number, color: Color3)
	for side = -1, 1, 2 do
		local root = cf * CFrame.new(side * spread, 0, 0) * CFrame.Angles(math.rad(-20), 0, math.rad(-side * 22))
		E(model, "Horn", Vector3.new(height * 0.38, height * 0.62, height * 0.38), root * CFrame.new(0, height * 0.28, 0), color)
		E(model, "Horn", Vector3.new(height * 0.24, height * 0.5, height * 0.24), root * CFrame.new(0, height * 0.62, height * 0.08) * CFrame.Angles(math.rad(-25), 0, 0), color:Lerp(Color3.new(1, 1, 1), 0.15))
	end
end

-- A spiky crown ring (gold) on top of a head.
local function crown(model: Model, cf: CFrame, radius: number, gem: Color3)
	local gold = rgb(255, 205, 60)
	cyl(model, "Crown", Vector3.new(radius * 0.45, radius * 2.1, radius * 2.1), cf * CFrame.Angles(0, 0, math.pi / 2), gold, Enum.Material.Foil)
	for i = 0, 4 do
		local a = i * math.pi * 2 / 5
		wedge(model, "CrownSpike", Vector3.new(radius * 0.32, radius * 0.6, radius * 0.24), cf * CFrame.Angles(0, a, 0) * CFrame.new(0, radius * 0.48, -radius * 0.95), gold, Enum.Material.Foil)
	end
	E(model, "CrownGem", Vector3.one * radius * 0.42, cf * CFrame.new(0, 0, -radius * 1.06), gem, Enum.Material.Neon)
end

-- Samurai kabuto: a dome, side flaps and a golden crescent crest.
local function kabuto(model: Model, cf: CFrame, s: Vector3, color: Color3)
	local gold = rgb(240, 196, 70)
	E(model, "Helmet", Vector3.new(s.X * 1.08, s.Y * 0.75, s.Z * 1.08), cf * CFrame.new(0, s.Y * 0.22, s.Z * 0.02), color, Enum.Material.Metal)
	for side = -1, 1, 2 do
		wedge(model, "HelmetFlap", Vector3.new(s.X * 0.06, s.Y * 0.32, s.Z * 0.6), cf * CFrame.new(side * s.X * 0.52, -s.Y * 0.02, s.Z * 0.12) * CFrame.Angles(0, 0, side * 0.35), color, Enum.Material.Metal)
		wedge(model, "Crest", Vector3.new(s.X * 0.05, s.Y * 0.55, s.X * 0.2), cf * CFrame.new(side * s.X * 0.17, s.Y * 0.62, -s.Z * 0.4) * CFrame.Angles(0, 0, -side * 0.45), gold, Enum.Material.Foil)
	end
	E(model, "CrestGem", Vector3.one * s.X * 0.13, cf * CFrame.new(0, s.Y * 0.38, -s.Z * 0.5), rgb(220, 40, 40), Enum.Material.Neon)
end

local builders = {}

-- ===== four-legged =====
function builders.Quad(model: Model, pet)
	local c = pet.Colors
	local look = pet.Look or {}
	local long = look.Legs == "Long"
	local lizard = look.Snout == "Lizard"
	local bodySize = if lizard then Vector3.new(1.15, 0.8, 1.9) else Vector3.new(1.25, 1.02, 1.5)
	local bodyY = if long then 0.25 else 0
	local body = E(model, "Body", bodySize, CFrame.new(0, bodyY, 0.15), c.Body)
	if look.Patches then
		E(model, "Saddle", Vector3.new(1.3, 0.62, 0.8), CFrame.new(0, bodyY + 0.12, 0.05), c.Accent)
	end
	if look.Spots then
		for i, p in ipairs({ { -0.42, 0.25, -0.2 }, { 0.38, 0.3, 0.25 }, { -0.25, 0.32, 0.55 }, { 0.3, 0.2, -0.4 }, { 0, 0.4, 0.15 } }) do
			E(model, "Spot", Vector3.new(0.28, 0.12, 0.28) * (1 - i * 0.06), CFrame.new(p[1], bodyY + p[2], p[3]) * CFrame.Angles(0, 0, -p[1] * 0.9), c.Accent)
		end
	end
	if look.Chest or look.Belly then
		E(model, "Chest", Vector3.new(0.8, 0.78, 0.5), CFrame.new(0, bodyY - 0.08, -0.48), if look.Belly then c.Body:Lerp(Color3.new(1, 1, 1), 0.55) else c.Accent)
	end
	-- legs and paws
	for side = -1, 1, 2 do
		for _, z in ipairs({ -0.32, 0.62 }) do
			local x = side * (if lizard then 0.55 else 0.37)
			local legColor = if look.Patches then c.Accent else c.Body
			local top = bodyY - bodySize.Y * 0.25
			local bottom = -1
			local leg = E(model, "Leg", Vector3.new(0.38, top - bottom + 0.15, 0.38), CFrame.new(x, (top + bottom) / 2 + 0.05, z), legColor)
			if lizard then
				leg.CFrame = CFrame.new(x * 1.1, -0.55, z) * CFrame.Angles(0, 0, side * 0.9)
				leg.Size = Vector3.new(0.3, 0.75, 0.3)
			end
			E(model, "Paw", Vector3.new(0.42, 0.2, 0.46), CFrame.new(x * (if lizard then 1.45 else 1), -0.95, z - 0.05), if look.Patches then c.Accent else c.Accent:Lerp(c.Body, 0.4))
		end
	end
	-- head
	local headSize = if lizard then Vector3.new(1.05, 0.85, 1.05) else Vector3.new(1.32, 1.18, 1.12)
	local head = CFrame.new(0, bodyY + (if lizard then 0.35 else 0.62), -0.72)
	E(model, "Head", headSize, head, c.Body)
	if look.Patches then
		for side = -1, 1, 2 do
			E(model, "Patch", Vector3.new(0.42, 0.5, 0.2), onFace(head, headSize, side * 0.28, 0.02, -0.05) * CFrame.Angles(0, 0, side * 0.45), c.Accent)
		end
	end
	if look.Mask then
		E(model, "Mask", Vector3.new(headSize.X * 0.98, 0.42, 0.3), onFace(head, headSize, 0, 0.04, -0.12), c.Accent)
	end
	-- muzzle
	local snout = look.Snout or "Short"
	if snout == "Fox" or snout == "Wolf" or snout == "Lizard" then
		local len = if snout == "Wolf" then 0.62 else 0.5
		local m = E(model, "Muzzle", Vector3.new(0.55, 0.38, len + 0.2), onFace(head, headSize, 0, -0.22, len * 0.25), if snout == "Lizard" then c.Body else c.Accent:Lerp(c.Body, if look.Chest then 0 else 0.6))
		E(model, "Nose", Vector3.new(0.2, 0.14, 0.14), m.CFrame * CFrame.new(0, 0.08, -(len + 0.2) / 2), INK)
	else
		local m = E(model, "Muzzle", Vector3.new(0.5, 0.32, 0.3), onFace(head, headSize, 0, -0.24, 0.02), c.Body:Lerp(Color3.new(1, 1, 1), 0.45))
		E(model, "Nose", Vector3.new(0.18, 0.12, 0.12), m.CFrame * CFrame.new(0, 0.08, -0.14), INK)
	end
	face(model, pet, head, headSize, { Y = 0.12, Size = 0.19, Spacing = 0.22, Mouth = if pet.Horns then "Fangs" else "None", Glow = pet.Particles ~= nil })
	-- ears
	local ears = look.Ears or "Pointy"
	for side = -1, 1, 2 do
		if ears == "Pointy" then
			local at = head * CFrame.new(side * 0.38, headSize.Y * 0.4, 0.05) * CFrame.Angles(0, 0, -side * 0.42)
			E(model, "Ear", Vector3.new(0.44, 0.5, 0.18), at * CFrame.new(0, 0.12, 0), c.Body)
			wedge(model, "Ear", Vector3.new(0.16, 0.22, 0.16), at * CFrame.new(0, 0.42, 0) * CFrame.Angles(0, math.pi / 2, 0), c.Body)
			E(model, "EarInner", Vector3.new(0.24, 0.32, 0.08), at * CFrame.new(0, 0.1, -0.08), if look.Chest then c.Accent else BLUSH)
		elseif ears == "Round" then
			E(model, "Ear", Vector3.new(0.42, 0.42, 0.2), head * CFrame.new(side * 0.44, headSize.Y * 0.4, 0.05), if look.Patches then c.Accent else c.Body)
		elseif ears == "Floppy" then
			E(model, "Ear", Vector3.new(0.22, 0.62, 0.38), head * CFrame.new(side * 0.66, 0.05, 0.05) * CFrame.Angles(0, 0, side * 0.35), c.Accent)
		end
	end
	if pet.Horns then
		horns(model, head * CFrame.new(0, headSize.Y * 0.38, 0.1), 0.3, 0.55, c.Accent)
	end
	if look.Antlers then
		for side = -1, 1, 2 do
			local root = head * CFrame.new(side * 0.25, headSize.Y * 0.45, 0.1) * CFrame.Angles(0, 0, -side * 0.35)
			cyl(model, "Antler", Vector3.new(0.75, 0.12, 0.12), root * CFrame.new(0, 0.35, 0) * CFrame.Angles(0, 0, math.pi / 2), c.Accent)
			for i, t in ipairs({ 0.3, 0.55 }) do
				cyl(model, "Antler", Vector3.new(0.38, 0.1, 0.1), root * CFrame.new(side * 0.12, t + 0.1, 0) * CFrame.Angles(0, 0, math.pi / 2 - side * (0.9 - i * 0.2)), c.Accent)
			end
		end
	end
	if look.Mane then
		for i = 0, 6 do
			local a = (i / 6 - 0.5) * math.pi * 1.1
			E(model, "Mane", Vector3.new(0.38, 0.5, 0.38), head * CFrame.new(math.sin(a) * 0.62, -0.25 + math.cos(a) * 0.35, 0.35), c.Accent)
		end
	end
	if look.Crown then
		crown(model, head * CFrame.new(0, headSize.Y * 0.52, 0.05), 0.32, c.Eyes)
	end
	-- tail(s)
	local tail = look.Tail or "Fluffy"
	local tails = pet.Tails or 1
	for i = 1, tails do
		local spread = if tails > 1 then (i - (tails + 1) / 2) * (1.6 / tails) else 0
		local root = CFrame.new(0, bodyY + 0.15, 0.85) * CFrame.Angles(0, spread, 0)
		if tail == "Fluffy" or tail == "Ringed" then
			local cf = root * CFrame.Angles(math.rad(50), 0, 0) * CFrame.new(0, 0, 0.5)
			local t = E(model, "Tail", Vector3.new(0.5, 0.5, 1.15), cf, c.Body)
			if tail == "Ringed" then
				for k = 0, 1 do
					E(model, "TailRing", Vector3.new(0.53, 0.53, 0.18), t.CFrame * CFrame.new(0, 0, -0.05 + k * 0.32), c.Accent)
				end
			else
				E(model, "TailTip", Vector3.new(0.4, 0.4, 0.45), t.CFrame * CFrame.new(0, 0, 0.45), c.Accent)
			end
			flap(t, 0.4, Vector3.new(0, bodyY + 0.15, 0.85), "Y")
		elseif tail == "Lizard" then
			for k = 1, 4 do
				E(model, "Tail", Vector3.new(0.5, 0.42, 0.65) * (1.05 - k * 0.18), CFrame.new(math.sin(k * 0.8) * 0.15, bodyY - 0.15 - k * 0.04, 0.85 + k * 0.42), c.Body)
			end
		elseif tail == "Thin" then
			local t = E(model, "Tail", Vector3.new(0.2, 0.2, 0.9), root * CFrame.Angles(math.rad(35), 0, 0) * CFrame.new(0, 0, 0.4), c.Body)
			E(model, "TailTip", Vector3.new(0.26, 0.26, 0.3), t.CFrame * CFrame.new(0, 0, 0.42), c.Accent)
		else
			E(model, "Tail", Vector3.new(0.38, 0.38, 0.38), CFrame.new(0, bodyY + 0.2, 0.86), c.Body)
		end
	end
	if pet.Id and (pet.Tails or 1) > 1 then
		-- kitsune markings on the brow
		E(model, "Marking", Vector3.new(0.14, 0.32, 0.06), onFace(head, headSize, 0, headSize.Y * 0.3, -0.02), c.Accent, Enum.Material.Neon)
	end
	return body
end

-- ===== maneki-neko =====
function builders.Cat(model: Model, pet)
	local c = pet.Colors
	local look = pet.Look or {}
	local body = E(model, "Body", Vector3.new(1.35, 1.25, 1.15), CFrame.new(0, -0.35, 0.05), c.Body)
	E(model, "Belly", Vector3.new(0.85, 0.8, 0.4), CFrame.new(0, -0.42, -0.42), c.Body:Lerp(Color3.new(1, 1, 1), 0.5))
	local headSize = Vector3.new(1.55, 1.3, 1.25)
	local head = CFrame.new(0, 0.72, -0.08)
	E(model, "Head", headSize, head, c.Body)
	-- calico patches
	E(model, "Patch", Vector3.new(0.55, 0.45, 0.35), head * CFrame.new(0.42, 0.35, -0.32), c.Accent)
	E(model, "Patch", Vector3.new(0.6, 0.5, 0.5), CFrame.new(-0.35, -0.1, 0.35), c.Accent)
	for side = -1, 1, 2 do
		local at = head * CFrame.new(side * 0.45, headSize.Y * 0.4, 0) * CFrame.Angles(0, 0, -side * 0.3)
		E(model, "Ear", Vector3.new(0.4, 0.55, 0.22), at * CFrame.new(0, 0.15, 0), c.Body)
		E(model, "EarInner", Vector3.new(0.22, 0.34, 0.08), at * CFrame.new(0, 0.12, -0.09), BLUSH)
		for k = -1, 1, 2 do
			local w = onFace(head, headSize, side * 0.48, -0.2 + k * 0.06, -0.02)
			box(model, "Whisker", Vector3.new(0.5, 0.025, 0.025), w * CFrame.new(side * 0.25, 0, 0) * CFrame.Angles(0, 0, side * k * 0.18), INK)
		end
	end
	face(model, pet, head, headSize, { Y = 0.05, Size = 0.17, Spacing = 0.2, Mouth = "Smile" })
	E(model, "Nose", Vector3.new(0.14, 0.1, 0.1), onFace(head, headSize, 0, -0.12, 0), BLUSH)
	-- red collar and golden bell
	cyl(model, "Collar", Vector3.new(0.18, 1.12, 1.12), CFrame.new(0, 0.12, -0.02) * CFrame.Angles(0, 0, math.pi / 2), rgb(214, 40, 44), Enum.Material.Fabric)
	E(model, "Bell", Vector3.one * 0.34, CFrame.new(0, -0.02, -0.55), rgb(255, 205, 60), Enum.Material.Foil)
	-- raised beckoning paw and the koban coin
	E(model, "Paw", Vector3.new(0.38, 0.72, 0.38), CFrame.new(0.68, 0.45, -0.25) * CFrame.Angles(0, 0, math.rad(-12)), c.Body)
	E(model, "PawPad", Vector3.new(0.2, 0.2, 0.08), CFrame.new(0.74, 0.7, -0.45), BLUSH)
	E(model, "Arm", Vector3.new(0.36, 0.5, 0.36), CFrame.new(-0.42, -0.35, -0.48), c.Body)
	E(model, "Coin", Vector3.new(0.72, 0.95, 0.12), CFrame.new(-0.25, -0.38, -0.66) * CFrame.Angles(0, 0, 0.2), rgb(255, 205, 60), Enum.Material.Foil)
	for side = -1, 1, 2 do
		E(model, "Foot", Vector3.new(0.42, 0.24, 0.5), CFrame.new(side * 0.35, -0.95, -0.3), c.Body)
	end
	local tail = E(model, "Tail", Vector3.new(0.26, 0.26, 0.95), CFrame.new(0.3, -0.5, 0.65) * CFrame.Angles(math.rad(-30), math.rad(40), 0), c.Body)
	flap(tail, 0.3, Vector3.new(0.15, -0.5, 0.35), "Y")
	if look.Kabuto then
		kabuto(model, head, headSize, c.Accent)
	end
	return body
end

-- ===== birds =====
function builders.Bird(model: Model, pet)
	local c = pet.Colors
	local kind = (pet.Look or {}).Kind
	local bodySize = if kind == "Owl" then Vector3.new(1.3, 1.35, 1.2) else Vector3.new(1.15, 1.05, 1.3)
	local body = E(model, "Body", bodySize, CFrame.new(), c.Body)
	E(model, "Belly", Vector3.new(0.85, 0.8, 0.5), CFrame.new(0, -0.12, -0.42), if kind == "Bat" then c.Body:Lerp(Color3.new(1, 1, 1), 0.15) else c.Body:Lerp(Color3.new(1, 1, 1), 0.45))
	local headSize = if kind == "Owl" then Vector3.new(1.35, 1.1, 1.15) else Vector3.new(1.05, 0.98, 1)
	local headY = if kind == "Crane" then 1.15 else 0.72
	local head = CFrame.new(0, headY, -0.35)
	if kind == "Crane" then
		cyl(model, "Neck", Vector3.new(0.85, 0.32, 0.32), CFrame.new(0, 0.6, -0.4) * CFrame.Angles(0, 0, math.pi / 2), c.Body)
		E(model, "Crown", Vector3.new(0.38, 0.2, 0.38), head * CFrame.new(0, headSize.Y * 0.47, 0), c.Accent)
	end
	E(model, "Head", headSize, head, c.Body)
	if kind == "Owl" then
		for side = -1, 1, 2 do
			E(model, "FaceDisc", Vector3.new(0.6, 0.6, 0.2), onFace(head, headSize, side * 0.27, 0.02, -0.06), c.Accent:Lerp(Color3.new(1, 1, 1), 0.5))
			wedge(model, "Tuft", Vector3.new(0.12, 0.42, 0.3), head * CFrame.new(side * 0.42, headSize.Y * 0.52, 0) * CFrame.Angles(0, 0, -side * 0.3), c.Accent)
		end
	end
	face(model, pet, head, headSize, { Y = 0.08, Size = if kind == "Owl" then 0.24 else 0.2, Spacing = 0.22, Mouth = if kind == "Bat" then "Fangs" else "None", Glow = pet.Glow })
	if kind ~= "Bat" then
		local beak = onFace(head, headSize, 0, -0.12, 0.08)
		local beakColor = if kind == "Crane" then rgb(60, 60, 60) elseif kind == "Phoenix" or kind == "Thunder" then rgb(255, 190, 60) else rgb(255, 170, 60)
		wedge(model, "Beak", Vector3.new(0.2, 0.14, if kind == "Crane" then 0.65 else 0.32), beak * CFrame.new(0, 0.04, -0.1) * CFrame.Angles(0, math.pi, 0), beakColor)
		wedge(model, "Beak", Vector3.new(0.2, 0.1, if kind == "Crane" then 0.55 else 0.26), beak * CFrame.new(0, -0.06, -0.08) * CFrame.Angles(math.pi, math.pi, 0), beakColor:Lerp(Color3.new(0, 0, 0), 0.15))
	else
		for side = -1, 1, 2 do
			wedge(model, "Ear", Vector3.new(0.12, 0.55, 0.32), head * CFrame.new(side * 0.32, headSize.Y * 0.52, 0) * CFrame.Angles(0, 0, -side * 0.25), c.Body)
		end
	end
	-- wings (hinged at the shoulder)
	for side = -1, 1, 2 do
		local span = if kind == "Bat" or kind == "Phoenix" or kind == "Thunder" then 1.4 else 1.05
		local wingColor = if kind == "Crane" then c.Body else c.Accent
		local shoulder = Vector3.new(side * (bodySize.X / 2 - 0.25), 0.18, 0.08)
		local wing = E(model, "Wing", Vector3.new(span, 0.16, 0.85), CFrame.new(shoulder) * CFrame.Angles(0, 0, side * 0.25) * CFrame.new(side * span / 2, 0, 0), wingColor)
		flap(wing, side, shoulder)
		if kind == "Bat" then
			for k = -1, 1 do
				local tip = wedge(model, "WingTip", Vector3.new(0.1, 0.28, 0.32), wing.CFrame * CFrame.new(side * span * 0.15 * (k + 1), 0, 0.42) * CFrame.Angles(math.pi / 2, 0, 0), wingColor)
				flap(tip, side, shoulder)
			end
		elseif kind == "Crane" then
			local tip = E(model, "WingTip", Vector3.new(span * 0.45, 0.17, 0.6), wing.CFrame * CFrame.new(side * span * 0.32, 0, 0.12), INK)
			flap(tip, side, shoulder)
		elseif kind == "Thunder" then
			for k = 0, 1 do
				local bolt = box(model, "Bolt", Vector3.new(span * 0.32, 0.17, 0.08), wing.CFrame * CFrame.new(side * (-0.1 + k * 0.3), 0, -0.1 + k * 0.18) * CFrame.Angles(0, (k - 0.5) * 0.9, 0), rgb(255, 235, 80), Enum.Material.Neon)
				flap(bolt, side, shoulder)
			end
		end
	end
	-- tail feathers
	local streamers = kind == "Phoenix"
	for i = -1, 1 do
		local len = if streamers then 1.5 - math.abs(i) * 0.3 else 0.7
		local feather = E(model, "TailFeather", Vector3.new(0.26, 0.1, len), CFrame.new(i * 0.2, 0.05, 0.6 + len / 2) * CFrame.Angles(math.rad(if streamers then -25 else -10), i * 0.3, 0), c.Accent, if streamers then Enum.Material.Neon else SMOOTH)
		if streamers then
			E(model, "TailEye", Vector3.new(0.3, 0.12, 0.3), feather.CFrame * CFrame.new(0, 0, len / 2 - 0.1), rgb(255, 250, 200), Enum.Material.Neon)
		end
	end
	if kind == "Phoenix" or kind == "Thunder" then
		for i = -1, 1 do
			E(model, "Crest", Vector3.new(0.14, 0.55 - math.abs(i) * 0.12, 0.3), head * CFrame.new(i * 0.12, headSize.Y * 0.5, 0.12) * CFrame.Angles(math.rad(-25), 0, i * 0.35), if kind == "Phoenix" then rgb(255, 220, 90) else c.Accent, Enum.Material.Neon)
		end
	end
	if kind ~= "Bat" then
		for side = -1, 1, 2 do
			if kind == "Crane" then
				cyl(model, "Leg", Vector3.new(0.7, 0.08, 0.08), CFrame.new(side * 0.2, -0.85, 0.05) * CFrame.Angles(0, 0, math.pi / 2), rgb(60, 60, 60))
			end
			E(model, "Foot", Vector3.new(0.26, 0.12, 0.34), CFrame.new(side * 0.22, if kind == "Crane" then -1.2 else -0.55, -0.05), rgb(255, 170, 60))
		end
	end
	return body
end

-- ===== dragons =====
local function dragonHead(model: Model, pet, head: CFrame, kirin: boolean)
	local c = pet.Colors
	local headSize = Vector3.new(1.15, 1.0, 1.05)
	E(model, "Head", headSize, head, c.Body)
	local snout = E(model, "Snout", Vector3.new(0.78, 0.52, 0.62), onFace(head, headSize, 0, -0.2, 0.18), c.Body)
	for side = -1, 1, 2 do
		E(model, "Nostril", Vector3.new(0.09, 0.07, 0.05), snout.CFrame * CFrame.new(side * 0.15, 0.1, -0.3), INK)
		E(model, "EarFin", Vector3.new(0.12, 0.45, 0.4), head * CFrame.new(side * 0.58, 0.1, 0.15) * CFrame.Angles(0, side * 0.5, -side * 0.6), c.Accent)
	end
	face(model, pet, head, headSize, { Y = 0.14, Size = 0.19, Spacing = 0.21, Mouth = "None", Glow = true })
	if kirin then
		E(model, "Horn", Vector3.new(0.16, 0.7, 0.16), head * CFrame.new(0, headSize.Y * 0.62, 0) * CFrame.Angles(math.rad(-20), 0, 0), c.Accent, Enum.Material.Neon)
		for side = -1, 1, 2 do
			cyl(model, "Whisker", Vector3.new(0.75, 0.05, 0.05), snout.CFrame * CFrame.new(side * 0.6, -0.05, -0.1) * CFrame.Angles(0, side * 0.3, side * 0.3), c.Accent)
		end
	else
		horns(model, head * CFrame.new(0, headSize.Y * 0.36, 0.2), 0.27, 0.62, c.Accent)
	end
	return headSize
end

function builders.Dragon(model: Model, pet)
	local c = pet.Colors
	local kind = (pet.Look or {}).Kind
	local belly = c.Accent:Lerp(Color3.new(1, 1, 1), 0.25)
	if kind == "Serpent" then
		-- a long coiling sky serpent: head in front, body looping behind, whiskers and a mane
		local body = E(model, "Body", Vector3.new(0.85, 0.85, 1.05), CFrame.new(0, 0, 0.1), c.Body)
		for i = 1, 6 do
			local t = i / 6
			local y = math.sin(t * math.pi * 2) * 0.45
			local x = math.cos(t * math.pi * 1.5) * 0.35
			local s = 0.82 - t * 0.45
			E(model, "Coil", Vector3.new(s, s, s * 1.2), CFrame.new(x, y, 0.1 + i * 0.42), c.Body)
			if i % 2 == 0 then
				wedge(model, "Spine", Vector3.new(0.06, 0.22, 0.24), CFrame.new(x, y + s * 0.5, 0.1 + i * 0.42), c.Accent)
			end
		end
		E(model, "Belly", Vector3.new(0.6, 0.5, 0.8), CFrame.new(0, -0.22, 0), belly)
		local head = CFrame.new(0, 0.55, -0.62)
		dragonHead(model, pet, head, true)
		for i = 0, 4 do
			local a = (i / 4 - 0.5) * 2.4
			E(model, "Mane", Vector3.new(0.3, 0.42, 0.3), head * CFrame.new(math.sin(a) * 0.55, 0.1 + math.cos(a) * 0.35, 0.42), c.Accent, Enum.Material.Neon)
		end
		E(model, "TailFin", Vector3.new(0.12, 0.55, 0.5), CFrame.new(0, 0.1, 2.85), c.Accent, Enum.Material.Neon)
		return body
	end
	local kirin = kind == "Kirin"
	local body = E(model, "Body", Vector3.new(1.2, 1.05, 1.45), CFrame.new(0, 0, 0.15), c.Body)
	E(model, "Belly", Vector3.new(0.82, 0.78, 0.6), CFrame.new(0, -0.12, -0.32), belly)
	for i = 0, 2 do
		box(model, "BellyStripe", Vector3.new(0.6, 0.05, 0.3), CFrame.new(0, -0.32 + i * 0.22, -0.6 + i * 0.02), c.Accent:Lerp(Color3.new(0, 0, 0), 0.1))
	end
	local head = CFrame.new(0, 0.7, -0.68)
	dragonHead(model, pet, head, kirin)
	-- legs
	for side = -1, 1, 2 do
		for _, z in ipairs({ -0.3, 0.6 }) do
			E(model, "Leg", Vector3.new(0.36, if kirin then 0.85 else 0.55, 0.36), CFrame.new(side * 0.42, if kirin then -0.55 else -0.68, z), c.Body)
			E(model, "Claw", Vector3.new(0.38, 0.16, 0.42), CFrame.new(side * 0.42, -0.94, z - 0.06), c.Accent)
		end
	end
	if kirin then
		for i = 0, 4 do
			E(model, "Mane", Vector3.new(0.28, 0.5, 0.32), CFrame.new(0, 0.45 + i * 0.02, -0.4 + i * 0.25) * CFrame.Angles(math.rad(-20), 0, 0), c.Accent, Enum.Material.Neon)
		end
	else
		-- wings: a spar and a membrane on each side, hinged at the back
		for side = -1, 1, 2 do
			local root = CFrame.new(side * 0.5, 0.45, 0.1)
			local tilt = root * CFrame.Angles(0, 0, side * 0.85)
			local spar = cyl(model, "Wing", Vector3.new(1.2, 0.1, 0.1), tilt * CFrame.new(side * 0.6, 0, -0.1), c.Body)
			flap(spar, side, root.Position)
			local membrane = E(model, "Wing", Vector3.new(1.3, 0.08, 1.05), tilt * CFrame.new(side * 0.62, -0.02, 0.32) * CFrame.Angles(0, side * 0.25, 0), c.Accent)
			membrane.Transparency = 0.05
			flap(membrane, side, root.Position)
		end
		for i = 0, 2 do
			wedge(model, "Spine", Vector3.new(0.07, 0.28, 0.3), CFrame.new(0, 0.55 - i * 0.04, -0.15 + i * 0.4), c.Accent)
		end
	end
	-- tail, tapering and curling up, ending in a spade
	local last
	for i = 1, 4 do
		local s = 0.62 - i * 0.11
		last = E(model, "Tail", Vector3.new(s, s, s * 1.3), CFrame.new(0, -0.2 + i * i * 0.05, 0.75 + i * 0.36), c.Body)
	end
	if last then
		wedge(model, "TailSpade", Vector3.new(0.08, 0.36, 0.38), last.CFrame * CFrame.new(0, 0.12, 0.3) * CFrame.Angles(math.rad(-30), 0, 0), c.Accent)
	end
	return body
end

-- ===== koi =====
function builders.Fish(model: Model, pet)
	local c = pet.Colors
	local body = E(model, "Body", Vector3.new(1.0, 1.05, 1.75), CFrame.new(), c.Body)
	-- koi patches over the back
	for _, p in ipairs({ { 0.1, 0.3, -0.25, 0.75 }, { -0.15, 0.22, 0.35, 0.65 }, { 0.2, 0.05, 0.65, 0.45 } }) do
		E(model, "Patch", Vector3.new(p[4] * 1.05, p[4] * 0.65, p[4]), CFrame.new(p[1], p[2], p[3]), c.Accent)
	end
	local headSize = Vector3.new(0.98, 0.95, 1.0)
	local head = CFrame.new(0, 0.05, -0.42)
	face(model, pet, head, headSize, { Y = 0.08, Size = 0.2, Spacing = 0.27, Mouth = "None", Blush = true })
	E(model, "Mouth", Vector3.new(0.3, 0.2, 0.15), onFace(head, headSize, 0, -0.2, 0.02), BLUSH:Lerp(INK, 0.3))
	for side = -1, 1, 2 do
		cyl(model, "Whisker", Vector3.new(0.32, 0.045, 0.045), onFace(head, headSize, side * 0.14, -0.24, 0) * CFrame.new(side * 0.1, -0.1, -0.02) * CFrame.Angles(0, side * 0.5, -side * 1.1), c.Accent)
		local fin = E(model, "Fin", Vector3.new(0.6, 0.06, 0.4), CFrame.new(side * 0.6, -0.25, -0.15) * CFrame.Angles(0, side * 0.3, side * -0.4), c.Accent:Lerp(Color3.new(1, 1, 1), 0.3))
		fin.Transparency = 0.15
		flap(fin, side * 0.6, Vector3.new(side * 0.4, -0.25, -0.15))
	end
	E(model, "DorsalFin", Vector3.new(0.08, 0.5, 0.95), CFrame.new(0, 0.55, 0.2), c.Accent)
	-- the tail fans out in a V and wags (local Z is vertical, so the flap turns it side to side)
	for side = -1, 1, 2 do
		local fin = E(model, "Tail", Vector3.new(0.07, 0.95, 0.55), CFrame.new(0, side * 0.2, 1.15) * CFrame.Angles(math.pi / 2, 0, 0) * CFrame.Angles(side * 0.45, 0, 0), c.Accent:Lerp(Color3.new(1, 1, 1), 0.2))
		fin.Transparency = 0.1
		flap(fin, 0.6, Vector3.new(0, 0, 0.75), "Y")
	end
	return body
end

-- ===== blobs: slime, oni mask, cloud =====
function builders.Blob(model: Model, pet)
	local c = pet.Colors
	local kind = (pet.Look or {}).Kind
	if kind == "OniMask" then
		local body = E(model, "Body", Vector3.new(1.6, 1.8, 0.75), CFrame.new(0, 0.1, 0), c.Body)
		local s = Vector3.new(1.6, 1.8, 0.75)
		local cf = CFrame.new(0, 0.1, 0)
		face(model, pet, cf, s, { Y = 0.12, Size = 0.17, Spacing = 0.2, Mouth = "Grin", Glow = true, Blush = false })
		for side = -1, 1, 2 do
			wedge(model, "Brow", Vector3.new(0.45, 0.16, 0.12), onFace(cf, s, side * 0.3, 0.42, 0.02) * CFrame.Angles(0, 0, side * 0.35), INK)
			E(model, "Cheek", Vector3.new(0.45, 0.32, 0.3), onFace(cf, s, side * 0.5, -0.15, -0.08), c.Body:Lerp(Color3.new(0, 0, 0), 0.15))
			cyl(model, "Cord", Vector3.new(0.9, 0.06, 0.06), cf * CFrame.new(side * 0.75, 0.25, 0.35) * CFrame.Angles(0, side * 0.6, 0), rgb(60, 30, 20), Enum.Material.Fabric)
		end
		E(model, "Nose", Vector3.new(0.32, 0.26, 0.2), onFace(cf, s, 0, 0.05, 0.05), c.Body:Lerp(Color3.new(0, 0, 0), 0.1))
		horns(model, cf * CFrame.new(0, 0.82, 0), 0.42, 0.75, c.Accent)
		E(model, "Hair", Vector3.new(1.3, 0.45, 0.6), cf * CFrame.new(0, 0.82, 0.2), INK)
		return body
	elseif kind == "Cloud" then
		local body = E(model, "Body", Vector3.new(1.4, 1.15, 1.25), CFrame.new(), c.Body)
		for _, p in ipairs({ { -0.6, 0.1, 0.1, 0.85 }, { 0.6, 0.1, 0.1, 0.85 }, { -0.3, 0.45, 0.2, 0.8 }, { 0.32, 0.5, 0.15, 0.75 }, { 0, -0.3, 0.3, 0.9 }, { 0, 0.2, 0.6, 0.85 } }) do
			E(model, "Puff", Vector3.one * p[4], CFrame.new(p[1], p[2], p[3]), c.Body:Lerp(c.Accent, 0.12))
		end
		local s = Vector3.new(1.4, 1.15, 1.25)
		face(model, pet, CFrame.new(), s, { Y = 0.05, Size = 0.2, Spacing = 0.22, Mouth = "Smile" })
		for side = -1, 1, 2 do
			E(model, "Ear", Vector3.new(0.35, 0.4, 0.2), CFrame.new(side * 0.42, 0.62, -0.05) * CFrame.Angles(0, 0, -side * 0.3), c.Accent)
		end
		E(model, "Nose", Vector3.new(0.16, 0.11, 0.1), onFace(CFrame.new(), s, 0, -0.06, 0), INK)
		return body
	end
	-- slime: a droopy gummy blob with a glossy highlight and a drip
	local s = Vector3.new(1.7, 1.3, 1.6)
	local cf = CFrame.new(0, -0.25, 0)
	local body = E(model, "Body", s, cf, c.Body)
	body.Transparency = 0.08
	E(model, "Top", Vector3.new(0.9, 0.7, 0.85), CFrame.new(0, 0.45, 0.05), c.Body)
	local gloss = E(model, "Gloss", Vector3.new(0.45, 0.25, 0.3), cf * CFrame.new(-0.42, 0.42, -0.45) * CFrame.Angles(0, 0, 0.5), Color3.new(1, 1, 1), Enum.Material.Neon)
	gloss.Transparency = 0.4
	E(model, "Core", Vector3.new(0.6, 0.5, 0.55), cf * CFrame.new(0, -0.05, 0.1), c.Accent, Enum.Material.Neon).Transparency = 0.35
	face(model, pet, cf, s, { Y = 0.05, Size = 0.17, Spacing = 0.18, Mouth = "Smile" })
	for _, p in ipairs({ { 0.55, -0.75, -0.35 }, { -0.62, -0.78, 0.2 } }) do
		E(model, "Drip", Vector3.new(0.3, 0.42, 0.3), CFrame.new(p[1], p[2], p[3]), c.Body)
	end
	if pet.Horns then
		horns(model, CFrame.new(0, 0.55, 0.05), 0.35, 0.6, c.Accent)
	end
	return body
end

-- ===== wisps: spirit flames =====
function builders.Wisp(model: Model, pet)
	local c = pet.Colors
	local kind = (pet.Look or {}).Kind
	local s = Vector3.new(1.3, 1.35, 1.25)
	local body = E(model, "Body", s, CFrame.new(), c.Body)
	body.Transparency = 0.12
	E(model, "Core", Vector3.new(0.75, 0.75, 0.7), CFrame.new(0, -0.05, 0.1), c.Accent, Enum.Material.Neon)
	-- the flame tail curls up behind
	for i = 1, 4 do
		local t = E(model, "Flame", Vector3.one * (1.0 - i * 0.2), CFrame.new(math.sin(i) * 0.12, 0.25 + i * 0.28, 0.35 + i * 0.25), c.Body:Lerp(c.Accent, i * 0.15))
		t.Transparency = 0.15 + i * 0.12
	end
	local wisp = E(model, "Wisp", Vector3.new(0.18, 0.45, 0.18), CFrame.new(0, 1.55, 1.25) * CFrame.Angles(math.rad(30), 0, 0), c.Accent, Enum.Material.Neon)
	wisp.Transparency = 0.2
	face(model, pet, CFrame.new(), s, { Y = 0.02, Size = 0.2, Spacing = 0.2, Mouth = if kind == "Wraith" then "None" else "Smile", Glow = true })
	for side = -1, 1, 2 do
		local arm = E(model, "Arm", Vector3.new(0.4, 0.28, 0.28), CFrame.new(side * 0.72, -0.2, -0.05) * CFrame.Angles(0, 0, side * 0.5), c.Body)
		arm.Transparency = 0.15
		flap(arm, side * 0.5, Vector3.new(side * 0.55, -0.2, -0.05))
	end
	if kind == "Sprite" then
		cyl(model, "Stem", Vector3.new(0.35, 0.07, 0.07), CFrame.new(0, 0.82, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(90, 160, 60))
		for side = -1, 1, 2 do
			E(model, "Leaf", Vector3.new(0.5, 0.08, 0.28), CFrame.new(side * 0.22, 1.0, 0) * CFrame.Angles(0, 0, side * 0.4), rgb(120, 210, 90))
		end
	elseif kind == "Wraith" then
		local hood = E(model, "Hood", Vector3.new(1.45, 1.25, 1.35), CFrame.new(0, 0.2, 0.12), c.Body:Lerp(Color3.new(0, 0, 0), 0.45))
		hood.Transparency = 0.05
		for i = -2, 2 do
			wedge(model, "Tatter", Vector3.new(0.22, 0.6, 0.25), CFrame.new(i * 0.24, -0.8, 0.1 + math.abs(i) * 0.05) * CFrame.Angles(math.pi, 0, 0), c.Body:Lerp(Color3.new(0, 0, 0), 0.35))
		end
	elseif kind == "Crown" then
		crown(model, CFrame.new(0, 0.72, 0), 0.4, c.Accent)
	end
	return body
end

-- ===== mini warriors =====
function builders.Mini(model: Model, pet)
	local c = pet.Colors
	local kind = (pet.Look or {}).Kind or "Ninja"
	local skin = rgb(250, 214, 180)
	local golem = kind == "Golem"
	local bodySize = Vector3.new(0.95, 0.85, 0.75)
	local body
	if golem then
		body = box(model, "Body", Vector3.new(1.05, 0.9, 0.8), CFrame.new(0, -0.35, 0) * CFrame.Angles(0, 0.08, 0.05), c.Body, Enum.Material.Slate)
		for _, p in ipairs({ { 0.2, -0.2, -0.41 }, { -0.25, -0.45, -0.41 } }) do
			box(model, "Crack", Vector3.new(0.35, 0.06, 0.04), CFrame.new(p[1], p[2], p[3]) * CFrame.Angles(0, 0, p[1] * 2), c.Accent, Enum.Material.Neon)
		end
	else
		body = E(model, "Body", bodySize, CFrame.new(0, -0.38, 0), c.Body)
	end
	local headSize = Vector3.new(1.35, 1.22, 1.18)
	local head = CFrame.new(0, 0.55, -0.02)
	if golem then
		box(model, "Head", Vector3.new(1.2, 1.0, 1.0), head * CFrame.Angles(0.05, -0.1, 0), c.Body, Enum.Material.Slate)
		box(model, "Brow", Vector3.new(1.25, 0.25, 0.4), head * CFrame.new(0, 0.32, -0.38), c.Body:Lerp(Color3.new(0, 0, 0), 0.2), Enum.Material.Slate)
		for side = -1, 1, 2 do
			E(model, "Eye", Vector3.new(0.22, 0.16, 0.1), head * CFrame.new(side * 0.25, 0.1, -0.51), c.Eyes, Enum.Material.Neon)
		end
	elseif kind == "Rift" then
		E(model, "Head", headSize, head, c.Body)
		E(model, "HoodShadow", Vector3.new(0.9, 0.7, 0.3), onFace(head, headSize, 0, -0.05, -0.1), INK)
		for side = -1, 1, 2 do
			E(model, "Eye", Vector3.new(0.2, 0.12, 0.08), onFace(head, headSize, side * 0.2, 0, -0.02), c.Eyes, Enum.Material.Neon)
		end
		wedge(model, "HoodTip", Vector3.new(0.5, 0.6, 0.6), head * CFrame.new(0, 0.55, 0.3) * CFrame.Angles(math.rad(-30), 0, 0), c.Body)
	else
		E(model, "Head", headSize, head, c.Body)
		if kind == "Ninja" or kind == "Samurai" then
			-- the face shows through the hood (ninja) or under the helmet (samurai)
			E(model, "Face", Vector3.new(headSize.X * 0.78, headSize.Y * 0.42, 0.3), onFace(head, headSize, 0, 0.02, -0.12), skin)
		end
		local masked = kind == "Ninja" or kind == "Samurai"
		face(model, pet, head, headSize, { Y = 0.04, Size = 0.17, Spacing = 0.19, Mouth = if kind == "Imp" then "Fangs" elseif kind == "Ninja" then "None" else "Smile", Glow = kind == "Imp", Out = if masked then 0.07 else 0 })
		if kind == "Ninja" then
			-- headband with fluttering tails
			cyl(model, "Band", Vector3.new(0.2, headSize.X * 1.02, headSize.X * 1.02), head * CFrame.new(0, 0.32, 0) * CFrame.Angles(0, 0, math.pi / 2), c.Accent, Enum.Material.Fabric)
			box(model, "Plate", Vector3.new(0.38, 0.18, 0.05), onFace(head, headSize, 0, 0.32, 0.02), rgb(200, 205, 215), Enum.Material.Metal)
			for side = -1, 1, 2 do
				local tail = box(model, "BandTail", Vector3.new(0.12, 0.08, 0.55), head * CFrame.new(side * 0.12, 0.3, 0.75) * CFrame.Angles(0.3, side * 0.35, 0), c.Accent, Enum.Material.Fabric)
				flap(tail, side * 0.4, (head * CFrame.new(side * 0.12, 0.3, 0.5)).Position, "Y")
			end
			box(model, "Katana", Vector3.new(0.08, 0.08, 1.4), CFrame.new(0.2, -0.15, 0.4) * CFrame.Angles(math.rad(-50), 0, math.rad(30)), rgb(40, 35, 45))
		elseif kind == "Samurai" then
			kabuto(model, head, headSize, c.Body)
			for side = -1, 1, 2 do
				box(model, "Sode", Vector3.new(0.4, 0.38, 0.55), CFrame.new(side * 0.58, -0.12, 0) * CFrame.Angles(0, 0, side * 0.3), c.Body, Enum.Material.Metal)
			end
			box(model, "Katana", Vector3.new(0.08, 0.08, 1.2), CFrame.new(0.5, -0.55, -0.15) * CFrame.Angles(0.2, 0.1, 0), rgb(40, 35, 45))
		elseif kind == "Imp" then
			horns(model, head * CFrame.new(0, headSize.Y * 0.38, 0), 0.32, 0.5, c.Accent)
			for side = -1, 1, 2 do
				wedge(model, "Ear", Vector3.new(0.1, 0.35, 0.4), head * CFrame.new(side * 0.68, 0.05, 0) * CFrame.Angles(0, side * math.pi / 2, 0), c.Body)
				local wing = wedge(model, "Wing", Vector3.new(0.6, 0.45, 0.08), CFrame.new(side * 0.5, -0.05, 0.42) * CFrame.Angles(0, 0, side * 0.6), c.Accent)
				flap(wing, side, Vector3.new(side * 0.25, -0.05, 0.42))
			end
			local tail = E(model, "Tail", Vector3.new(0.12, 0.12, 0.8), CFrame.new(0, -0.6, 0.55) * CFrame.Angles(math.rad(-30), 0, 0), c.Body)
			wedge(model, "TailSpade", Vector3.new(0.06, 0.25, 0.25), tail.CFrame * CFrame.new(0, 0, 0.45), c.Accent)
		end
	end
	-- belt, arms and feet
	if not golem then
		cyl(model, "Belt", Vector3.new(0.14, bodySize.X * 1.02, bodySize.X * 1.02), CFrame.new(0, -0.45, 0) * CFrame.Angles(0, 0, math.pi / 2), c.Accent, Enum.Material.Fabric)
	end
	for side = -1, 1, 2 do
		local arm = if golem
			then box(model, "Arm", Vector3.new(0.35, 0.6, 0.35), CFrame.new(side * 0.68, -0.35, 0) * CFrame.Angles(0, 0, side * 0.15), c.Body, Enum.Material.Slate)
			else E(model, "Arm", Vector3.new(0.3, 0.55, 0.3), CFrame.new(side * 0.55, -0.35, 0) * CFrame.Angles(0, 0, side * 0.35), c.Body)
		E(model, "Hand", Vector3.one * (if golem then 0.38 else 0.26), arm.CFrame * CFrame.new(0, -0.3, 0), if golem then c.Body else skin)
		E(model, "Foot", Vector3.new(0.34, 0.22, 0.44), CFrame.new(side * 0.24, -0.9, -0.05), if golem then c.Body else c.Accent)
	end
	return body
end

-- ===== straw dummy =====
function builders.Dummy(model: Model, pet)
	local c = pet.Colors
	local body = E(model, "Body", Vector3.new(1.15, 1.15, 0.95), CFrame.new(0, -0.15, 0), c.Body, Enum.Material.Fabric)
	for i = 0, 1 do
		cyl(model, "Rope", Vector3.new(0.12, 1.12, 0.92), CFrame.new(0, -0.45 + i * 0.55, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(150, 110, 70), Enum.Material.Fabric)
	end
	local headSize = Vector3.new(1.0, 0.95, 0.9)
	local head = CFrame.new(0, 0.72, 0)
	E(model, "Head", headSize, head, c.Body, Enum.Material.Fabric)
	cyl(model, "Neck", Vector3.new(0.1, 0.5, 0.5), CFrame.new(0, 0.32, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(150, 110, 70), Enum.Material.Fabric)
	-- stitched cross eyes and a stitched smile
	for side = -1, 1, 2 do
		local at = onFace(head, headSize, side * 0.2, 0.06, -0.02)
		box(model, "Eye", Vector3.new(0.2, 0.05, 0.04), at * CFrame.Angles(0, 0, 0.785), c.Eyes)
		box(model, "Eye", Vector3.new(0.2, 0.05, 0.04), at * CFrame.Angles(0, 0, -0.785), c.Eyes)
		E(model, "Blush", Vector3.new(0.18, 0.1, 0.05), onFace(head, headSize, side * 0.3, -0.12, -0.01), BLUSH).Transparency = 0.35
	end
	box(model, "Mouth", Vector3.new(0.3, 0.04, 0.04), onFace(head, headSize, 0, -0.18, -0.01), c.Eyes)
	-- straw tufts on top and the painted target
	for i = -1, 1 do
		wedge(model, "Straw", Vector3.new(0.08, 0.3, 0.14), head * CFrame.new(i * 0.15, headSize.Y * 0.5, 0) * CFrame.Angles(0, 0, i * 0.4), rgb(235, 205, 130))
	end
	cyl(model, "Target", Vector3.new(0.04, 0.6, 0.6), CFrame.new(0, -0.1, -0.47) * CFrame.Angles(0, math.pi / 2, 0), Color3.new(1, 1, 1))
	cyl(model, "Target", Vector3.new(0.05, 0.42, 0.42), CFrame.new(0, -0.1, -0.48) * CFrame.Angles(0, math.pi / 2, 0), c.Accent)
	cyl(model, "Target", Vector3.new(0.06, 0.18, 0.18), CFrame.new(0, -0.1, -0.49) * CFrame.Angles(0, math.pi / 2, 0), Color3.new(1, 1, 1))
	-- crossbar arms and the post it stands on
	cyl(model, "Arms", Vector3.new(1.9, 0.16, 0.16), CFrame.new(0, 0.12, 0.05), rgb(120, 80, 50), Enum.Material.Wood)
	for side = -1, 1, 2 do
		E(model, "Hand", Vector3.new(0.3, 0.3, 0.3), CFrame.new(side * 0.95, 0.12, 0.05), c.Body, Enum.Material.Fabric)
	end
	cyl(model, "Stick", Vector3.new(0.45, 0.2, 0.2), CFrame.new(0, -0.9, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(120, 80, 50), Enum.Material.Wood)
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
	-- the model's pivot follows the body's position but never its rotation
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
