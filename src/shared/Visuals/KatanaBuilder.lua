--[[
	Builds a katana Model from a Katanas.lua entry. Pure geometry from parts, so it
	works with no uploaded meshes. The blade is a chain of curved segments with a
	separate edge strip, a tip, a shaped guard (tsuba), collar, wrapped grip and
	pommel. Higher tiers add neon edges, lights and particles.

	Local space: grip at the origin, blade extends along -Z (the model's LookVector).
	The returned model's PrimaryPart is "Grip". Attachments "TrailBase"/"TrailTip"
	carry a disabled Trail named "SwingTrail" that the client enables mid-swing.
]]

local Particles = require(script.Parent.Particles)
local Assets = require(script.Parent.Assets)
local Rarity = require(script.Parent.Parent.Config.Rarity)

local KatanaBuilder = {}

local function part(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function wedge(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.Parent = model
	return p
end

-- A disc facing along Z (cylinders run along X by default).
local DISC = CFrame.Angles(0, math.pi / 2, 0)

local function buildGuard(model: Model, look, z: number)
	local color = look.GuardColor
	local material = Enum.Material.Metal
	local guardType = look.Guard or "Round"
	local center = CFrame.new(0, 0, z)

	if guardType == "Square" then
		part(model, "Guard", Vector3.new(0.62, 0.56, 0.1), center, color, material)
		part(model, "GuardInset", Vector3.new(0.4, 0.36, 0.12), center, look.Wrap, Enum.Material.SmoothPlastic)
	elseif guardType == "Flower" then
		part(model, "Guard", Vector3.new(0.1, 0.42, 0.42), center * DISC, color, material, Enum.PartType.Cylinder)
		for i = 0, 3 do
			local a = i * math.pi / 2 + math.pi / 4
			local offset = Vector3.new(math.cos(a), math.sin(a), 0) * 0.24
			part(model, "Petal", Vector3.new(0.1, 0.3, 0.3), CFrame.new(offset + Vector3.new(0, 0, z)) * DISC, color, material, Enum.PartType.Cylinder)
		end
	elseif guardType == "Spiked" then
		part(model, "Guard", Vector3.new(0.1, 0.6, 0.6), center * DISC, color, material, Enum.PartType.Cylinder)
		for i = 0, 3 do
			local a = i * math.pi / 2
			local dir = Vector3.new(math.cos(a), math.sin(a), 0)
			local pos = dir * 0.38 + Vector3.new(0, 0, z)
			-- spike: a thin wedge pointing outward
			wedge(model, "Spike", Vector3.new(0.08, 0.18, 0.3), CFrame.lookAt(pos, pos + dir) * CFrame.Angles(0, 0, 0), look.Edge, Enum.Material.Metal)
		end
	elseif guardType == "Wings" then
		part(model, "Guard", Vector3.new(0.1, 0.46, 0.46), center * DISC, color, material, Enum.PartType.Cylinder)
		for side = -1, 1, 2 do
			local wingCf = CFrame.new(side * 0.42, 0.05, z - 0.08) * CFrame.Angles(0, side * math.rad(25), side * math.rad(-15))
			part(model, "Wing", Vector3.new(0.5, 0.16, 0.08), wingCf, color, material)
			local tipCf = CFrame.new(side * 0.72, 0.14, z - 0.2) * CFrame.Angles(0, side * math.rad(40), side * math.rad(-30))
			part(model, "WingTip", Vector3.new(0.26, 0.1, 0.06), tipCf, look.Edge, if look.EdgeGlow then Enum.Material.Neon else material)
		end
	elseif guardType == "Ring" then
		for i = 0, 9 do
			local a = i * math.pi * 2 / 10
			local pos = Vector3.new(math.cos(a), math.sin(a), 0) * 0.3 + Vector3.new(0, 0, z)
			part(model, "RingSeg", Vector3.new(0.19, 0.08, 0.08), CFrame.new(pos) * CFrame.Angles(0, 0, a + math.pi / 2), color, Enum.Material.Neon)
		end
		part(model, "Guard", Vector3.new(0.08, 0.3, 0.3), center * DISC, look.Handle, material, Enum.PartType.Cylinder)
	elseif guardType == "Crescent" then
		part(model, "Guard", Vector3.new(0.1, 0.5, 0.5), center * DISC, color, material, Enum.PartType.Cylinder)
		for side = -1, 1, 2 do
			local cf = CFrame.new(side * 0.3, 0.12, z) * CFrame.Angles(0, 0, side * math.rad(35))
			part(model, "Crescent", Vector3.new(0.16, 0.42, 0.09), cf, look.Edge, if look.EdgeGlow then Enum.Material.Neon else material)
		end
	else -- Round
		part(model, "Guard", Vector3.new(0.1, 0.62, 0.62), center * DISC, color, material, Enum.PartType.Cylinder)
		part(model, "GuardRim", Vector3.new(0.12, 0.44, 0.44), center * DISC, look.Handle, material, Enum.PartType.Cylinder)
	end
end

-- Shared by both builders: invisible blade core (trail, light, particles), welds and scale.
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

-- Effects that stack with rarity (Rarity.Index: 1 Common .. 7 Divine), on top of
-- the katana's own Look.Particles / Light:
--   Epic+       glints along the blade, a burst of sparks on every swing, brighter trail
--   Legendary+  a shimmering energy sheath running up the blade
--   Mythic+     a rising aura from the guard and a stronger light
--   Divine      a second, faster sheath and drifting stardust around the blade
local function rarityEffects(core: BasePart, look, rarity: string, base: Attachment, tip: Attachment, trail: Trail, width: number)
	local tier = Rarity.Index(rarity)
	local accent: Color3 = look.Light or look.Trail[1]
	local deep: Color3 = look.Trail[2] or accent
	if tier >= 3 then
		trail.Lifetime = 0.2 + 0.03 * (tier - 2)
		trail.LightEmission = math.max(trail.LightEmission, 0.5 + 0.08 * tier)
	end
	if tier >= 4 then
		Particles.Create("Sparkle", core, {
			Name = "Glint", Color = ColorSequence.new(Color3.new(1, 1, 1), accent), Rate = 2 + tier,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.3), NumberSequenceKeypoint.new(1, 0) }),
			Speed = NumberRange.new(0, 0.3), Lifetime = NumberRange.new(0.3, 0.6),
		})
		-- emitted by the AnimationController when the swing trail lights up
		local burst = Particles.Create("Sparkle", core, {
			Name = "SwingBurst", Color = ColorSequence.new(accent, deep), Rate = 0,
			Speed = NumberRange.new(4, 9), Lifetime = NumberRange.new(0.25, 0.5), Drag = 6,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) }),
		})
		if burst then
			burst:SetAttribute("Burst", 4 + (tier - 4) * 4)
		end
	end
	if tier >= 5 then
		local sheath = Instance.new("Beam")
		sheath.Name = "Sheath"
		sheath.Attachment0 = base
		sheath.Attachment1 = tip
		sheath.Texture = SPARKLE
		sheath.TextureMode = Enum.TextureMode.Wrap
		sheath.TextureLength = 1.2
		sheath.TextureSpeed = 1.2
		sheath.LightEmission = 1
		sheath.LightInfluence = 0
		sheath.FaceCamera = true
		sheath.Width0 = width * 2.4
		sheath.Width1 = width * 1.2
		sheath.Color = ColorSequence.new(accent, deep)
		sheath.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.8, 0.45), NumberSequenceKeypoint.new(1, 1) })
		sheath.Parent = core
	end
	if tier >= 6 then
		local light = core:FindFirstChildOfClass("PointLight") or Instance.new("PointLight")
		light.Color = accent
		light.Range = 8 + (tier - 5) * 2
		light.Brightness = 2
		light.Shadows = false
		light.Parent = core
		local rise = Particles.Create(look.Particles or "Spirit", base, {
			Name = "Aura", Rate = 10 + (tier - 6) * 8, Color = ColorSequence.new(accent, deep),
			SpreadAngle = Vector2.new(25, 25), Speed = NumberRange.new(1, 2.5),
		})
		if rise then
			-- the base attachment sits on the blade, so point the aura up the blade
			rise.EmissionDirection = Enum.NormalId.Front
		end
	end
	if tier >= 7 then
		local inner = core:FindFirstChild("Sheath") :: Beam
		local fast = inner:Clone()
		fast.Name = "SheathFast"
		fast.TextureSpeed = -2.4
		fast.TextureLength = 0.6
		fast.Width0, fast.Width1 = width * 1.4, width * 0.8
		fast.Color = ColorSequence.new(Color3.new(1, 1, 1), accent)
		fast.Parent = core
		Particles.Create("Galaxy", core, { Name = "Stardust", Rate = 14, Color = ColorSequence.new(Color3.new(1, 1, 1), accent) })
	end
end

local function finish(model: Model, look, grip: BasePart, bladeStart: Vector3, tipPos: Vector3, width: number, scale: number?, rarity: string?): Model
	-- Invisible core spanning the blade: holds light, particles and trail attachments.
	local coreCenter = (bladeStart + tipPos) / 2
	local core = part(model, "BladeCore", Vector3.new(0.05, width * 0.8, (tipPos - bladeStart).Magnitude), CFrame.lookAt(coreCenter, tipPos), look.Blade)
	core.Transparency = 1

	local base = Instance.new("Attachment")
	base.Name = "TrailBase"
	base.Position = core.CFrame:PointToObjectSpace(bladeStart)
	base.Parent = core
	local tip = Instance.new("Attachment")
	tip.Name = "TrailTip"
	tip.Position = core.CFrame:PointToObjectSpace(tipPos)
	tip.Parent = core

	local trail = Instance.new("Trail")
	trail.Name = "SwingTrail"
	trail.Attachment0 = base
	trail.Attachment1 = tip
	trail.Color = ColorSequence.new(look.Trail[1], look.Trail[2])
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	trail.Lifetime = 0.2
	trail.LightEmission = if look.EdgeGlow then 0.8 else 0.3
	trail.MinLength = 0.05
	trail.Enabled = false
	trail.Parent = core

	if look.Light then
		local light = Instance.new("PointLight")
		light.Color = look.Light
		light.Range = 7
		light.Brightness = 1.4
		light.Shadows = false
		light.Parent = core
	end
	if look.Particles then
		Particles.Create(look.Particles, core, { Rate = (Particles.Presets[look.Particles].Rate or 10) * 0.7 })
	end
	rarityEffects(core, look, rarity or "Common", base, tip, trail, width)

	-- Weld everything to the grip
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") and child ~= grip then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = grip
			weld.Part1 = child
			weld.Parent = child
		end
	end

	if scale and scale ~= 1 then
		model:ScaleTo(scale)
	end
	return model
end

-- Blade style for the Blender meshes (Look.Style overrides).
local STYLE_BY_GUARD = { Spiked = "Jagged", Wings = "Wide", Square = "Straight" }
local REF_LENGTH, REF_WIDTH = 3.6, 0.27
local BLADE_BASE = Vector3.new(0, 0, -0.78)

-- Mesh katana from the imported Blender kit (tools/blender/katanas.py).
local function buildFromMeshes(def, scale: number?): Model?
	local look = def.Look
	local style = look.Style or STYLE_BY_GUARD[look.Guard] or "Standard"
	local guardName = "KatanaGuard_" .. (look.Guard or "Round")
	if not Assets.Has("KatanaGrip", "KatanaWrap", "KatanaCollar", "KatanaPommel_Cap", "KatanaBlade_" .. style, "KatanaEdge_" .. style) then
		return nil
	end
	if not Assets.Has(guardName) then
		guardName = "KatanaGuard_Round"
	end
	local model = Instance.new("Model")
	model.Name = def.Id
	local origin = CFrame.new()
	local function add(name: string, color: Color3, material: Enum.Material?, s: Vector3?, pivot: Vector3?): MeshPart?
		local mesh = Assets.Mesh(name, color, material)
		if mesh then
			Assets.Place(mesh, origin, s, pivot)
			mesh.Parent = model
		end
		return mesh
	end
	local grip = add("KatanaGrip", look.Handle, Enum.Material.Fabric) :: MeshPart
	grip.Name = "Grip"
	model.PrimaryPart = grip
	add("KatanaWrap", look.Wrap, Enum.Material.Fabric)
	add(guardName, look.GuardColor, Enum.Material.Metal)
	add("KatanaCollar", look.GuardColor:Lerp(Color3.fromRGB(230, 190, 90), 0.4), Enum.Material.Metal)
	add("KatanaPommel_Cap", look.GuardColor, Enum.Material.Metal)
	local pommel = look.Pommel or "Cap"
	if pommel == "Gem" then
		add("KatanaPommel_Setting", look.GuardColor, Enum.Material.Metal)
		add("KatanaGem", look.Gem or look.Edge, Enum.Material.Neon)
	elseif pommel == "Ring" then
		add("KatanaPommel_Ring", look.Wrap, Enum.Material.Metal)
	elseif pommel == "Tassel" then
		add("KatanaTassel", look.Gem or look.Wrap, Enum.Material.Fabric)
	end
	-- blade + edge scaled to this katana's length and width around the blade base
	local width = look.Width
	local bladeScale = Vector3.new(width / REF_WIDTH, width / REF_WIDTH, look.Length / REF_LENGTH)
	add("KatanaBlade_" .. style, look.Blade, look.BladeMaterial or Enum.Material.Metal, bladeScale, BLADE_BASE)
	add("KatanaEdge_" .. style, look.Edge, if look.EdgeGlow then Enum.Material.Neon else Enum.Material.Metal, bladeScale, BLADE_BASE)
	local tipPos = BLADE_BASE + Vector3.new(0, 0.2 * bladeScale.Y * 0.5, -look.Length)
	return finish(model, look, grip, BLADE_BASE, tipPos, width, scale, def.Rarity)
end

-- Textured hero katana modelled from a reference sheet (tools/blender/hero_katanas.py):
-- one mesh HeroKatana_<id> (+ __Glow gems), grip centred on the origin, blade toward -Z.
local function buildHero(def, scale: number?): Model?
	local name = "HeroKatana_" .. def.Id
	local info = Assets.Manifest[name]
	if not (info and Assets.Has(name)) then
		return nil
	end
	local look = def.Look
	local model = Instance.new("Model")
	model.Name = def.Id
	local grip = part(model, "Grip", Vector3.new(0.2, 0.2, 1), CFrame.new(), look.Handle)
	grip.Transparency = 1
	model.PrimaryPart = grip
	local mesh = Assets.Textured(name, look.Blade)
	if mesh then
		Assets.Place(mesh, CFrame.new())
		mesh.CastShadow = false
		mesh.Parent = model
	end
	local glow = Assets.Mesh(name .. "__Glow", look.Gem or look.Edge, Enum.Material.Neon)
	if glow then
		Assets.Place(glow, CFrame.new())
		glow.Parent = model
	end
	local base = info.BladeBase or Vector3.new(0, 0, -0.8)
	local tip = info.BladeTip or (base + Vector3.new(0, 0, -look.Length))
	return finish(model, look, grip, base, tip, look.Width, scale, def.Rarity)
end

-- ===== Nunchaku =====
-- Look: Stick, StickMaterial, Cap, Wrap, Chain, Glow (optional neon rings), Length
-- (one stick), Radius, Particles, Light, Trail. The held stick sits in the hand along
-- -Z like a short blade with the chain anchor ("ChainAnchor") at its far end. The
-- other stick and the chain are built twice: a "display" copy hanging still (shop,
-- server) and, on clients, a free copy that Controllers/NunchakuController swings.
local CHUCK_HOLD = 0.45 -- studs of stick behind the hand
local CHAIN_LINKS = 3
local CHAIN_LINK = 0.2

local function chuckLook(look)
	return look.Length or 1.5, look.Radius or 0.13
end

-- One stick along -Z from z = 0 to z = -Length (imported HeroNunchaku_<id> mesh or parts).
local function buildStick(model: Model, def, origin: CFrame, name: string): BasePart
	local look = def.Look
	local length, radius = chuckLook(look)
	local meshName = "HeroNunchaku_" .. def.Id
	local mesh = Assets.Manifest[meshName] and Assets.Has(meshName) and Assets.Textured(meshName, look.Stick)
	if mesh then
		local info = Assets.Manifest[meshName]
		local k = length / info.Size.Z
		Assets.Place(mesh, origin * CFrame.new(0, 0, -length / 2), Vector3.one * k)
		mesh.Name = name
		mesh.CastShadow = false
		mesh.Parent = model
		local glow = Assets.Mesh(meshName .. "__Glow", look.Glow or look.Cap, Enum.Material.Neon)
		if glow then
			Assets.Place(glow, origin * CFrame.new(0, 0, -length / 2), Vector3.one * k)
			glow.Parent = model
		end
		return mesh
	end
	local axis = CFrame.Angles(0, math.pi / 2, 0) -- cylinders run along X; turn them onto Z
	local stick = part(model, name, Vector3.new(length, radius * 2, radius * 2), origin * CFrame.new(0, 0, -length / 2) * axis, look.Stick, look.StickMaterial or Enum.Material.Wood, Enum.PartType.Cylinder)
	for _, z in ipairs({ -0.04, -length + 0.04 }) do
		part(model, name .. "Cap", Vector3.new(0.1, radius * 2.3, radius * 2.3), origin * CFrame.new(0, 0, z) * axis, look.Cap, Enum.Material.Metal, Enum.PartType.Cylinder)
	end
	for i = 1, 3 do
		local z = -length + 0.25 + (i - 1) * 0.13
		part(model, name .. "Wrap", Vector3.new(0.07, radius * 2.15, radius * 2.15), origin * CFrame.new(0, 0, z) * axis, look.Wrap, Enum.Material.Fabric, Enum.PartType.Cylinder)
	end
	if look.Glow then
		for _, z in ipairs({ -length * 0.3, -length * 0.62 }) do
			part(model, name .. "Rune", Vector3.new(0.05, radius * 2.12, radius * 2.12), origin * CFrame.new(0, 0, z) * axis, look.Glow, Enum.Material.Neon, Enum.PartType.Cylinder)
		end
	end
	return stick
end

-- The free half (chain links + second stick) for NunchakuController, unanchored-free:
-- every part is anchored and moved by the controller. Returns the stick model (its
-- pivot is the chain end of the stick, stick along -Z) and the link parts.
function KatanaBuilder.BuildFreeHalf(def): (Model, { BasePart }, Trail)
	local look = def.Look
	local length = chuckLook(look)
	local stick = Instance.new("Model")
	stick.Name = "FreeStick"
	local main = buildStick(stick, def, CFrame.new(), "Stick")
	for _, d in ipairs(stick:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	stick.PrimaryPart = main
	stick.WorldPivot = CFrame.new()
	main.PivotOffset = main.CFrame:Inverse()
	-- the swing trail rides the free stick, the part that actually whips through
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailBase"
	a0.Position = main.CFrame:PointToObjectSpace(Vector3.new(0, 0, 0))
	a0.Parent = main
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailTip"
	a1.Position = main.CFrame:PointToObjectSpace(Vector3.new(0, 0, -length))
	a1.Parent = main
	local trail = Instance.new("Trail")
	trail.Name = "SwingTrail"
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Color = ColorSequence.new(look.Trail[1], look.Trail[2])
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	trail.Lifetime = 0.18 + 0.02 * Rarity.Index(def.Rarity)
	trail.LightEmission = 0.4 + 0.08 * Rarity.Index(def.Rarity)
	trail.MinLength = 0.05
	trail.Enabled = false
	trail.Parent = main
	local links = {}
	for i = 1, CHAIN_LINKS do
		local link = part(stick, "Link" .. i, Vector3.new(CHAIN_LINK * 1.1, 0.07, 0.07), CFrame.new(), look.Chain, Enum.Material.Metal, Enum.PartType.Cylinder)
		link.Anchored = true
		link.Parent = nil
		table.insert(links, link)
	end
	return stick, links, trail
end

KatanaBuilder.ChainLinks = CHAIN_LINKS
KatanaBuilder.ChainLink = CHAIN_LINK

local function buildNunchaku(def, scale: number?): Model
	local look = def.Look
	local length, radius = chuckLook(look)
	local model = Instance.new("Model")
	model.Name = def.Id
	local grip = part(model, "Grip", Vector3.new(0.2, 0.2, 0.4), CFrame.new(), look.Stick)
	grip.Transparency = 1
	model.PrimaryPart = grip
	local tipZ = -(length - CHUCK_HOLD)
	buildStick(model, def, CFrame.new(0, 0, CHUCK_HOLD), "HeldStick")
	local anchor = Instance.new("Attachment")
	anchor.Name = "ChainAnchor"
	anchor.Position = Vector3.new(0, 0, tipZ - 0.04)
	anchor.Parent = grip
	-- display half: the chain and second stick hanging down from the anchor
	local hang = CFrame.new(0, 0, tipZ - 0.04) * CFrame.Angles(math.rad(80), 0, 0)
	for i = 1, CHAIN_LINKS do
		local link = part(model, "Link" .. i, Vector3.new(CHAIN_LINK * 1.1, 0.07, 0.07), hang * CFrame.new(0, 0, -(i - 0.5) * CHAIN_LINK) * CFrame.Angles(0, math.pi / 2, 0), look.Chain, Enum.Material.Metal, Enum.PartType.Cylinder)
		link:SetAttribute("DisplayHalf", true)
	end
	local before = {}
	for _, d in ipairs(model:GetChildren()) do
		before[d] = true
	end
	buildStick(model, def, hang * CFrame.new(0, 0, -CHAIN_LINKS * CHAIN_LINK), "SwingStick")
	for _, d in ipairs(model:GetChildren()) do
		if not before[d] and d:IsA("BasePart") then
			d:SetAttribute("DisplayHalf", true)
		end
	end
	model:SetAttribute("WeaponType", "Nunchaku")
	local built = finish(model, {
		Blade = look.Stick, Trail = look.Trail, Particles = look.Particles, Light = look.Light, EdgeGlow = look.Glow ~= nil,
	}, grip, Vector3.new(0, 0, CHUCK_HOLD), Vector3.new(0, 0, tipZ), radius * 2, scale, def.Rarity)
	-- the swing trail belongs on the free stick (NunchakuController adds it there)
	local core = built:FindFirstChild("BladeCore")
	local heldTrail = core and core:FindFirstChild("SwingTrail")
	if heldTrail then
		heldTrail:Destroy()
	end
	return built
end

-- ===== Spear =====
-- Look: Shaft, ShaftMaterial, Band (metal fittings), Wrap (grip wraps), Head, HeadMaterial,
-- Edge, EdgeGlow, Style ("Yari" | "Leaf" | "Jumonji" | "Naginata" | "Crescent" |
-- "Celestial"), Length (whole spear), HeadLength, HeadWidth, Radius, Tassel, Ribbon,
-- Glow (neon runes), Gem, Particles, Light, Trail. The hand holds the shaft SPEAR_BUTT
-- studs from the butt (grip at the origin, head along -Z); the swing trail runs along
-- the blade head. An imported HeroSpear_<id> mesh (+ __Glow) replaces the parts,
-- placed like HeroKatana_<id> (its manifest may give BladeBase / BladeTip).
local SPEAR_BUTT = 2.2
KatanaBuilder.SpearButt = SPEAR_BUTT
local SPEAR_HOLD = 15 -- degrees the grip is tilted in the hand (CharacterService reads HoldAngle)
local AXIS = CFrame.Angles(0, math.pi / 2, 0) -- cylinders run along X; turn them onto Z
local THICK = 0.07

local function ring(model: Model, name: string, z: number, radius: number, length: number, color: Color3, material: Enum.Material?)
	return part(model, name, Vector3.new(length, radius * 2, radius * 2), CFrame.new(0, 0, z) * AXIS, color, material or Enum.Material.Metal, Enum.PartType.Cylinder)
end

-- A double-edged pointed blade from `base` (its -Z is the blade direction): flat body
-- (optionally several segments of the given relative widths, for a leaf shape),
-- a symmetric point of two wedges, edge strips on both sides and a raised centre ridge.
local function pointedBlade(model: Model, look, base: CFrame, length: number, width: number, widths: { number }?)
	local profile = widths or { 1 }
	local bodyLength = length * 0.6
	local segment = bodyLength / #profile
	local headMaterial = look.HeadMaterial or Enum.Material.Metal
	local edgeMaterial = if look.EdgeGlow then Enum.Material.Neon else Enum.Material.Metal
	local w = width
	for i, k in ipairs(profile) do
		w = width * k
		local cf = base * CFrame.new(0, 0, -(i - 0.5) * segment)
		part(model, "Blade", Vector3.new(THICK, w, segment * 1.02), cf, look.Head, headMaterial)
		for side = -1, 1, 2 do
			part(model, "Edge", Vector3.new(THICK * 0.8, 0.06, segment * 1.02), cf * CFrame.new(0, side * w / 2, 0), look.Edge, edgeMaterial)
		end
	end
	local tipLength = length - bodyLength
	local tipBase = base * CFrame.new(0, 0, -bodyLength)
	wedge(model, "Tip", Vector3.new(THICK, w / 2, tipLength), tipBase * CFrame.new(0, w / 4, -tipLength / 2), look.Head, headMaterial)
	wedge(model, "Tip", Vector3.new(THICK, w / 2, tipLength), tipBase * CFrame.new(0, -w / 4, -tipLength / 2) * CFrame.Angles(0, 0, math.pi), look.Head, headMaterial)
	local point = (tipBase * CFrame.new(0, 0, -tipLength)).Position
	for side = -1, 1, 2 do
		local back = (tipBase * CFrame.new(0, side * w / 2, 0)).Position
		local mid = (back + point) / 2
		part(model, "Edge", Vector3.new(THICK * 0.8, 0.06, (point - back).Magnitude), CFrame.lookAt(mid, point, base.UpVector), look.Edge, edgeMaterial)
	end
	-- centre ridge (shinogi) on both faces, running into the point
	part(model, "Ridge", Vector3.new(THICK * 1.35, math.max(0.04, width * 0.1), length * 0.85), base * CFrame.new(0, 0, -length * 0.425), look.Edge:Lerp(look.Head, 0.5), headMaterial)
	return point
end

-- A crescent moon blade on one side of the head (side = 1: +Y): its back is fixed to
-- the shaft and its hollow, sharpened side faces outward, horns pointing out.
local function crescent(model: Model, look, base: CFrame, side: number, radius: number, sweep: number)
	local segments = 8
	local edgeMaterial = if look.EdgeGlow then Enum.Material.Neon else Enum.Material.Metal
	local center = (base * CFrame.new(0, side * radius * 1.12, 0)).Position
	local prev: Vector3? = nil
	for i = 0, segments do
		local a = math.rad(-sweep / 2 + sweep * i / segments)
		local p = (base * CFrame.new(0, side * radius * (1.12 - math.cos(a)), -radius * math.sin(a))).Position
		if prev then
			local mid = (prev + p) / 2
			local taper = 1 - math.abs(i - 0.5 - segments / 2) / (segments / 2) * 0.7
			local cf = CFrame.lookAt(mid, p, base.RightVector)
			local len = (p - prev).Magnitude * 1.1
			part(model, "Crescent", Vector3.new(0.18 * taper, THICK, len), cf, look.Head, look.HeadMaterial or Enum.Material.Metal)
			part(model, "CrescentEdge", Vector3.new(0.05, THICK * 0.8, len), cf + (center - mid).Unit * 0.09 * taper, look.Edge, edgeMaterial)
		end
		prev = p
	end
end

-- Naginata: a long curved single-edged blade bending toward +Y, with a small guard.
local function curvedBlade(model: Model, look, base: CFrame, length: number, width: number): Vector3
	local segments = 6
	local segLength = length * 0.86 / segments
	local curve = 0.35
	local pos = base.Position
	local lastCf = base
	local headMaterial = look.HeadMaterial or Enum.Material.Metal
	local edgeMaterial = if look.EdgeGlow then Enum.Material.Neon else Enum.Material.Metal
	part(model, "Guard", Vector3.new(0.08, width * 1.9, width * 1.9), base * CFrame.new(0, 0, 0.05) * DISC, look.Band, Enum.Material.Metal, Enum.PartType.Cylinder)
	for i = 1, segments do
		local bend = curve * (i - 0.5) / segments
		local dir = base:VectorToWorldSpace(Vector3.new(0, math.sin(bend), -math.cos(bend)))
		local center = pos + dir * segLength / 2
		local cf = CFrame.lookAt(center, center + dir, base.UpVector)
		local taper = 1 - 0.25 * (i - 1) / segments
		part(model, "Blade", Vector3.new(THICK, width * taper, segLength * 1.04), cf, look.Head, headMaterial)
		part(model, "Edge", Vector3.new(THICK * 0.8, width * 0.22, segLength * 1.04), cf * CFrame.new(0, -width * taper * 0.5, 0), look.Edge, edgeMaterial)
		if i <= segments - 2 then
			part(model, "Groove", Vector3.new(THICK * 1.2, width * 0.1, segLength * 1.04), cf * CFrame.new(0, width * taper * 0.2, 0), look.Edge:Lerp(look.Head, 0.6), headMaterial)
		end
		pos += dir * segLength
		lastCf = CFrame.lookAt(pos, pos + dir, base.UpVector)
	end
	local tipLength = length * 0.14 + width * 0.6
	wedge(model, "Tip", Vector3.new(THICK, width * 0.75, tipLength), lastCf * CFrame.new(0, 0, -tipLength / 2) * CFrame.Angles(0, 0, math.pi), look.Head, headMaterial)
	return pos + lastCf.LookVector * tipLength
end

local function buildSpearHead(model: Model, look, zSocket: number): Vector3
	local style = look.Style or "Yari"
	local length = look.HeadLength or 1.3
	local width = look.HeadWidth or 0.3
	local base = CFrame.new(0, 0, zSocket)
	if style == "Leaf" then
		return pointedBlade(model, look, base, length, width, { 0.7, 1.05, 1.2, 0.95 })
	elseif style == "Jumonji" then
		-- cross-shaped yari: a long centre blade with two side blades curving forward
		for side = -1, 1, 2 do
			local arm = base * CFrame.new(0, side * 0.12, -0.3) * CFrame.Angles(side * math.rad(-62), 0, 0)
			pointedBlade(model, look, arm, length * 0.5, width * 0.7)
		end
		return pointedBlade(model, look, base, length, width)
	elseif style == "Naginata" then
		return curvedBlade(model, look, base, length, width)
	elseif style == "Crescent" then
		for side = -1, 1, 2 do
			crescent(model, look, base * CFrame.new(0, 0, -length * 0.22), side, 0.55, 150)
		end
		return pointedBlade(model, look, base, length, width * 0.8, { 0.8, 1.1 })
	elseif style == "Celestial" then
		for side = -1, 1, 2 do
			crescent(model, look, base * CFrame.new(0, 0, -length * 0.18), side, 0.7, 165)
		end
		-- a floating halo around the head
		local halo = base * CFrame.new(0, 0, -length * 0.42)
		for i = 0, 11 do
			local a = i * math.pi * 2 / 12
			local p = (halo * CFrame.new(math.cos(a) * 0.62, math.sin(a) * 0.62, 0)).Position
			part(model, "Halo", Vector3.new(0.34, 0.06, 0.06), CFrame.lookAt(p, p + halo.LookVector, halo:VectorToWorldSpace(Vector3.new(math.cos(a), math.sin(a), 0))) * CFrame.Angles(0, math.pi / 2, 0), look.Glow or look.Edge, Enum.Material.Neon)
		end
		return pointedBlade(model, look, base, length, width, { 0.7, 1.05, 1.25, 1.0 })
	end
	return pointedBlade(model, look, base, length, width)
end

local function buildSpearParts(model: Model, look, rarity: number)
	local length = look.Length or 7
	local radius = look.Radius or 0.12
	local headLength = look.HeadLength or 1.3
	local zButt = SPEAR_BUTT
	local zSocket = -(length - SPEAR_BUTT - headLength)
	local shaftMaterial = look.ShaftMaterial or Enum.Material.Wood
	local band = look.Band or Color3.fromRGB(200, 170, 90)
	local wrap = look.Wrap or Color3.fromRGB(60, 30, 20)
	local wrapDark = wrap:Lerp(Color3.new(0, 0, 0), 0.4)

	-- shaft, butt cap (ishizuki) and its spike
	ring(model, "Shaft", (zButt + zSocket) / 2, radius, zButt - zSocket, look.Shaft, shaftMaterial)
	ring(model, "ButtCap", zButt - 0.12, radius * 1.3, 0.34, band)
	part(model, "ButtSpike", Vector3.new(radius * 2.2, radius * 2.2, radius * 2.2), CFrame.new(0, 0, zButt + 0.06), band, Enum.Material.Metal, Enum.PartType.Ball)

	-- grip wraps where each hand holds the shaft: a fabric sleeve with crossed bindings
	for _, span in ipairs({ { 0.5, -0.5 }, { -1.05, -2.05 } }) do
		local a, b = span[1], span[2]
		ring(model, "Wrap", (a + b) / 2, radius * 1.1, a - b, wrap, Enum.Material.Fabric)
		local count = math.floor((a - b) / 0.2 + 0.5)
		for i = 0, count - 1 do
			local z = a - 0.1 - i * 0.2
			part(model, "Binding", Vector3.new(radius * 2.35, radius * 1.1, radius * 1.1), CFrame.new(0, 0, z) * CFrame.Angles(math.rad(45), 0, 0), wrapDark, Enum.Material.Fabric)
		end
		ring(model, "Band", a + 0.04, radius * 1.22, 0.08, band)
		ring(model, "Band", b - 0.04, radius * 1.22, 0.08, band)
	end
	ring(model, "Band", zButt - 0.45, radius * 1.18, 0.07, band)
	ring(model, "Band", zSocket + 0.95, radius * 1.18, 0.07, band)

	-- lacquer stripes between the wraps on fancier shafts
	if rarity >= 4 then
		for _, z in ipairs({ -0.7, -0.85, zSocket + 0.75 }) do
			ring(model, "Stripe", z, radius * 1.04, 0.05, band:Lerp(look.Shaft, 0.4), Enum.Material.SmoothPlastic)
		end
	end

	-- socket collar and habaki
	ring(model, "Collar", zSocket + 0.24, radius * 1.35, 0.48, band)
	ring(model, "Habaki", zSocket + 0.03, radius * 1.6, 0.08, band:Lerp(Color3.new(1, 1, 1), 0.25))

	-- glowing runes: neon rings plus diamond marks up the shaft, more with rarity
	if look.Glow then
		local runes = 2 + rarity
		local from, to = -2.25, zSocket + 1.1
		for i = 1, runes do
			local z = from + (to - from) * (i - 0.5) / runes
			for side = -1, 1, 2 do
				part(model, "Rune", Vector3.new(0.03, 0.1, 0.1), CFrame.new(side * radius * 1.02, 0, z) * CFrame.Angles(math.rad(45), 0, 0), look.Glow, Enum.Material.Neon)
			end
		end
		for _, z in ipairs({ zButt - 0.6, zSocket + 0.6, 0.62, -0.62 }) do
			ring(model, "RuneRing", z, radius * 1.08, 0.04, look.Glow, Enum.Material.Neon)
		end
		if rarity >= 6 then
			-- a thin glowing inlay along the shaft
			for side = -1, 1, 2 do
				part(model, "Inlay", Vector3.new(0.025, 0.025, (to - from)), CFrame.new(0, side * radius * 1.01, (from + to) / 2), look.Glow, Enum.Material.Neon)
			end
		end
	end

	-- horsehair tassel below the head: a knot and a ring of strands flaring back
	if look.Tassel then
		local knotZ = zSocket + 0.62
		part(model, "TasselKnot", Vector3.new(radius * 2.6, radius * 2.6, radius * 2.6), CFrame.new(0, 0, knotZ), look.Tassel, Enum.Material.Fabric, Enum.PartType.Ball)
		local strands = 10
		for i = 0, strands - 1 do
			local a = i * math.pi * 2 / strands
			local out = Vector3.new(math.cos(a), math.sin(a), 0)
			local len = if i % 2 == 0 then 0.75 else 0.6
			local from = Vector3.new(0, 0, knotZ) + out * radius
			local to = from + out * len * 0.42 + Vector3.new(0, 0, len)
			part(model, "Tassel", Vector3.new(0.06, 0.06, len), CFrame.lookAt((from + to) / 2, to), look.Tassel:Lerp(Color3.new(0, 0, 0), (i % 3) * 0.1), Enum.Material.Fabric)
		end
	end
	-- ribbons streaming back from the collar
	if look.Ribbon then
		for side = -1, 1, 2 do
			local p = Vector3.new(side * radius * 1.4, 0, zSocket + 0.3)
			for i = 1, 4 do
				local dir = Vector3.new(side * (0.35 - i * 0.05), math.sin(i * 1.3) * 0.25, 1).Unit
				local q = p + dir * 0.42
				part(model, "Ribbon", Vector3.new(0.02, 0.16 - i * 0.02, 0.44), CFrame.lookAt((p + q) / 2, q), look.Ribbon, if look.Glow and i == 4 then Enum.Material.Neon else Enum.Material.Fabric)
				p = q
			end
		end
	end
	if look.Gem then
		part(model, "Gem", Vector3.new(0.2, 0.2, 0.2), CFrame.new(0, 0, zSocket + 0.24) * CFrame.Angles(math.rad(45), math.rad(45), 0), look.Gem, Enum.Material.Neon)
	end

	local tip = buildSpearHead(model, look, zSocket)
	return Vector3.new(0, 0, zSocket), tip
end

local function buildSpear(def, scale: number?): Model
	local look = def.Look
	local model = Instance.new("Model")
	model.Name = def.Id
	local grip = part(model, "Grip", Vector3.new(0.2, 0.2, 0.4), CFrame.new(), look.Shaft)
	grip.Transparency = 1
	model.PrimaryPart = grip
	local bladeBase, tip
	local meshName = "HeroSpear_" .. def.Id
	local info = Assets.Manifest[meshName]
	local mesh = info and Assets.Has(meshName) and Assets.Textured(meshName, look.Shaft)
	if mesh then
		Assets.Place(mesh, CFrame.new())
		mesh.CastShadow = false
		mesh.Parent = model
		local glow = Assets.Mesh(meshName .. "__Glow", look.Glow or look.Edge, Enum.Material.Neon)
		if glow then
			Assets.Place(glow, CFrame.new())
			glow.Parent = model
		end
		local length = look.Length or 7
		bladeBase = info.BladeBase or Vector3.new(0, 0, -(length - SPEAR_BUTT - (look.HeadLength or 1.3)))
		tip = info.BladeTip or Vector3.new(0, 0, -(length - SPEAR_BUTT))
	else
		bladeBase, tip = buildSpearParts(model, look, Rarity.Index(def.Rarity))
	end
	model:SetAttribute("WeaponType", "Spear")
	model:SetAttribute("HoldAngle", SPEAR_HOLD)
	return finish(model, {
		Blade = look.Head, Trail = look.Trail, Particles = look.Particles, Light = look.Light, EdgeGlow = look.EdgeGlow,
	}, grip, bladeBase, tip, look.HeadWidth or 0.3, scale, def.Rarity)
end

-- ===== Claws =====
-- Dual-wielded: Build gives the right-hand claw, BuildOffhand the left (the parts are
-- symmetric in X, so the same build mirrors itself). Grip at the origin in the fist,
-- blades along -Z (CharacterService turns them along the forearm with HoldAngle).
-- Styles: "Steel" (three long blades from a knuckle mount) and "Katar" (Bartuc's: blades
-- rising from a frame with side bars, a cross grip and ring bands at the base).
local CLAW_HOLD = -80

local function clawBlade(model: Model, look, x: number, fan: number, zBase: number): (Vector3, Vector3)
	local length = look.Length or 2
	local width = look.Width or 0.12
	local curve = look.Curve or 0.1
	local segments = 5
	local segLength = length * 0.86 / segments
	local material = look.BladeMaterial or Enum.Material.Metal
	local edgeMaterial = if look.EdgeGlow then Enum.Material.Neon else Enum.Material.Metal
	local base = CFrame.new(x, 0, zBase) * CFrame.Angles(0, fan, 0)
	local pos = base.Position
	local lastCf = base
	for i = 1, segments do
		local bend = curve * (i - 0.5) / segments
		local dir = base:VectorToWorldSpace(Vector3.new(0, math.sin(bend), -math.cos(bend)))
		local center = pos + dir * segLength / 2
		local cf = CFrame.lookAt(center, center + dir, base.UpVector)
		local taper = 1 - 0.4 * (i - 1) / segments
		part(model, "ClawBlade", Vector3.new(0.045, width * taper, segLength * 1.04), cf, look.Blade, material)
		part(model, "ClawEdge", Vector3.new(0.035, width * 0.22, segLength * 1.04), cf * CFrame.new(0, -width * taper * 0.5, 0), look.Edge, edgeMaterial)
		pos += dir * segLength
		lastCf = CFrame.lookAt(pos, pos + dir, base.UpVector)
	end
	local tipLength = length * 0.14 + 0.1
	wedge(model, "ClawTip", Vector3.new(0.045, width * 0.6, tipLength), lastCf * CFrame.new(0, 0, -tipLength / 2) * CFrame.Angles(0, 0, math.pi), look.Blade, material)
	return base.Position, pos + lastCf.LookVector * tipLength
end

local function buildClawParts(model: Model, look, rarity: number): (Vector3, Vector3)
	local mount = look.Mount or Color3.fromRGB(60, 60, 70)
	local accent = look.Accent or mount
	local spread = 0.17
	local zBase
	if look.Style == "Katar" then
		local frame = look.Frame or mount
		-- dark side bars from the ring bands at the wrist up to the gold top plate
		for side = -1, 1, 2 do
			part(model, "SideBar", Vector3.new(0.09, 0.15, 0.85), CFrame.new(side * 0.3, 0, 0.08), accent, Enum.Material.SmoothPlastic)
			part(model, "SideTrim", Vector3.new(0.1, 0.04, 0.85), CFrame.new(side * 0.3, 0.08, 0.08), frame, Enum.Material.Metal)
			if look.Glow then
				for i = 0, 2 do
					part(model, "Rune", Vector3.new(0.1, 0.07, 0.07), CFrame.new(side * 0.305, 0, 0.3 - i * 0.22) * CFrame.Angles(math.rad(45), 0, 0), look.Glow, Enum.Material.Neon)
				end
			end
		end
		part(model, "TopPlate", Vector3.new(0.74, 0.2, 0.12), CFrame.new(0, 0, -0.36), frame, Enum.Material.Metal)
		part(model, "TopRidge", Vector3.new(0.78, 0.08, 0.06), CFrame.new(0, 0, -0.44), frame:Lerp(Color3.new(1, 1, 1), 0.2), Enum.Material.Metal)
		-- the cross grip with its knob, inside the fist
		part(model, "CrossGrip", Vector3.new(0.55, 0.09, 0.09), CFrame.new(0, 0, -0.02), frame, Enum.Material.Metal, Enum.PartType.Cylinder)
		part(model, "Knob", Vector3.new(0.16, 0.16, 0.16), CFrame.new(0, 0, -0.02), look.Gem or frame, if look.Gem then Enum.Material.Neon else Enum.Material.Metal, Enum.PartType.Ball)
		-- silver ring bands round the base of the frame
		for _, z in ipairs({ 0.4, 0.5 }) do
			for i = 0, 11 do
				local a = i * math.pi * 2 / 12
				local p = Vector3.new(math.cos(a) * 0.34, math.sin(a) * 0.2, z)
				part(model, "Ring", Vector3.new(0.2, 0.05, 0.06), CFrame.new(p) * CFrame.Angles(0, 0, a + math.pi / 2), look.Rings or Color3.fromRGB(210, 210, 220), Enum.Material.Metal)
			end
		end
		zBase = -0.42
		spread = 0.2
	else
		-- knuckle mount: a rounded block with stripes, one slot per blade
		part(model, "Mount", Vector3.new(0.6, 0.24, 0.34), CFrame.new(0, 0, -0.12), mount, Enum.Material.Metal)
		for side = -1, 1, 2 do
			part(model, "MountEnd", Vector3.new(0.12, 0.24, 0.34), CFrame.new(side * 0.3, 0, -0.12) * CFrame.Angles(0, math.pi / 2, 0), mount, Enum.Material.Metal, Enum.PartType.Cylinder)
		end
		for _, z in ipairs({ -0.04, -0.2 }) do
			part(model, "Stripe", Vector3.new(0.62, 0.26, 0.05), CFrame.new(0, 0, z), accent, Enum.Material.SmoothPlastic)
		end
		part(model, "Strap", Vector3.new(0.5, 0.08, 0.5), CFrame.new(0, -0.14, 0.2), mount:Lerp(Color3.new(0, 0, 0), 0.5), Enum.Material.Fabric)
		if look.Glow then
			for side = -1, 1, 2 do
				part(model, "Rune", Vector3.new(0.05, 0.08, 0.08), CFrame.new(side * 0.36, 0, -0.12) * CFrame.Angles(math.rad(45), 0, 0), look.Glow, Enum.Material.Neon)
			end
			part(model, "RuneBar", Vector3.new(0.5, 0.03, 0.03), CFrame.new(0, 0.125, -0.12), look.Glow, Enum.Material.Neon)
		end
		if look.Gem then
			part(model, "Gem", Vector3.new(0.14, 0.14, 0.14), CFrame.new(0, 0.12, -0.12) * CFrame.Angles(math.rad(45), math.rad(45), 0), look.Gem, Enum.Material.Neon)
		end
		zBase = -0.3
	end
	local base, tip
	for i = -1, 1 do
		local b, t = clawBlade(model, look, i * spread, i * math.rad(-4), zBase)
		if i == 0 then
			base, tip = b, t
		end
	end
	if rarity >= 6 and look.Glow then
		-- a faint glowing core along each blade
		for i = -1, 1 do
			part(model, "BladeGlow", Vector3.new(0.05, 0.03, (look.Length or 2) * 0.6), CFrame.new(i * spread, 0.02, zBase - (look.Length or 2) * 0.3) * CFrame.Angles(0, i * math.rad(-4), 0), look.Glow, Enum.Material.Neon)
		end
	end
	return base, tip
end

local function buildClaw(def, scale: number?, offhand: boolean): Model
	local look = def.Look
	local model = Instance.new("Model")
	model.Name = def.Id
	local grip = part(model, "Grip", Vector3.new(0.2, 0.2, 0.3), CFrame.new(), look.Mount or look.Blade)
	grip.Transparency = 1
	model.PrimaryPart = grip
	local base, tip
	local meshName = "HeroClaw_" .. def.Id
	local info = Assets.Manifest[meshName]
	local mesh = info and Assets.Has(meshName) and Assets.Textured(meshName, look.Blade)
	if mesh then
		Assets.Place(mesh, CFrame.new())
		mesh.CastShadow = false
		mesh.Parent = model
		local glow = Assets.Mesh(meshName .. "__Glow", look.Glow or look.Edge, Enum.Material.Neon)
		if glow then
			Assets.Place(glow, CFrame.new())
			glow.Parent = model
		end
		base = info.BladeBase or Vector3.new(0, 0, -0.4)
		tip = info.BladeTip or Vector3.new(0, 0, -0.4 - (look.Length or 2))
	else
		base, tip = buildClawParts(model, look, Rarity.Index(def.Rarity))
	end
	model:SetAttribute("WeaponType", "Claws")
	model:SetAttribute("HoldAngle", CLAW_HOLD)
	if offhand then
		model:SetAttribute("Offhand", true)
	end
	return finish(model, {
		Blade = look.Blade, Trail = look.Trail, Particles = look.Particles, Light = look.Light, EdgeGlow = look.EdgeGlow,
	}, grip, base, tip, (look.Width or 0.12) * 3, scale, def.Rarity)
end

-- The left-hand weapon for dual-wielded weapons (claws), or nil.
function KatanaBuilder.BuildOffhand(def, scale: number?): Model?
	if def.Weapon == "Claws" then
		return buildClaw(def, scale, true)
	end
	return nil
end

function KatanaBuilder.Build(def, scale: number?): Model
	if def.Weapon == "Nunchaku" then
		return buildNunchaku(def, scale)
	elseif def.Weapon == "Spear" then
		return buildSpear(def, scale)
	elseif def.Weapon == "Claws" then
		return buildClaw(def, scale, false)
	end
	local hero = buildHero(def, scale)
	if hero then
		return hero
	end
	local fromMeshes = buildFromMeshes(def, scale)
	if fromMeshes then
		return fromMeshes
	end
	local look = def.Look
	local model = Instance.new("Model")
	model.Name = def.Id

	local gripLength = 1.0
	local grip = part(model, "Grip", Vector3.new(0.2, 0.22, gripLength), CFrame.new(), look.Handle, Enum.Material.Fabric)
	model.PrimaryPart = grip

	-- Grip wrapping: diamonds along the handle
	for i = 0, 4 do
		local z = -gripLength / 2 + 0.1 + i * 0.2
		part(model, "Wrap", Vector3.new(0.23, 0.12, 0.12), CFrame.new(0, 0, z) * CFrame.Angles(math.rad(45), 0, 0), look.Wrap, Enum.Material.Fabric)
	end

	-- Pommel
	local pommelZ = gripLength / 2 + 0.06
	local pommel = look.Pommel or "Cap"
	part(model, "Pommel", Vector3.new(0.12, 0.26, 0.26), CFrame.new(0, 0, pommelZ) * DISC, look.GuardColor, Enum.Material.Metal, Enum.PartType.Cylinder)
	if pommel == "Gem" then
		part(model, "Gem", Vector3.new(0.18, 0.18, 0.18), CFrame.new(0, 0, pommelZ + 0.1) * CFrame.Angles(math.rad(45), math.rad(45), 0), look.Gem or look.Edge, Enum.Material.Neon)
	elseif pommel == "Ring" then
		part(model, "PommelRing", Vector3.new(0.06, 0.24, 0.24), CFrame.new(0, 0, pommelZ + 0.15) * CFrame.Angles(0, 0, 0) * CFrame.Angles(0, 0, math.pi / 2) * DISC, look.Wrap, Enum.Material.Metal, Enum.PartType.Cylinder)
	elseif pommel == "Tassel" then
		local tassel = part(model, "Tassel", Vector3.new(0.07, 0.5, 0.07), CFrame.new(0, -0.22, pommelZ + 0.12) * CFrame.Angles(math.rad(-20), 0, 0), look.Gem or look.Wrap, Enum.Material.Fabric)
		part(model, "TasselKnot", Vector3.new(0.14, 0.14, 0.14), tassel.CFrame * CFrame.new(0, 0.25, 0), look.Gem or look.Wrap, Enum.Material.Fabric, Enum.PartType.Ball)
	end

	-- Guard + collar
	local guardZ = -gripLength / 2 - 0.05
	buildGuard(model, look, guardZ)
	part(model, "Collar", Vector3.new(0.12, 0.3, 0.14), CFrame.new(0, 0, guardZ - 0.12), look.GuardColor, Enum.Material.Metal)

	-- Blade: curved chain of segments
	local length = look.Length
	local width = look.Width
	local thickness = 0.07
	local segments = 6
	local segLength = length / segments
	local pos = Vector3.new(0, 0, guardZ - 0.19)
	local bladeStart = pos
	local bladeMaterial = look.BladeMaterial or Enum.Material.Metal
	local edgeMaterial = if look.EdgeGlow then Enum.Material.Neon else Enum.Material.Metal
	local lastCf = CFrame.new(pos)
	for i = 1, segments do
		local bend = look.Curve * (i - 0.5) / segments
		local dir = Vector3.new(0, math.sin(bend), -math.cos(bend))
		local center = pos + dir * segLength / 2
		local cf = CFrame.lookAt(center, center + dir)
		local taper = 1 - 0.18 * (i - 1) / segments
		part(model, "Blade", Vector3.new(thickness, width * taper, segLength * 1.04), cf, look.Blade, bladeMaterial)
		part(model, "Edge", Vector3.new(thickness * 0.7, width * 0.2, segLength * 1.04), cf * CFrame.new(0, -width * taper * 0.5, 0), look.Edge, edgeMaterial)
		-- blood groove (bohi) on the first two thirds of the blade
		if i <= segments - 2 then
			part(model, "Groove", Vector3.new(thickness * 1.15, width * 0.12, segLength * 1.04), cf * CFrame.new(0, width * taper * 0.18, 0), look.Edge:Lerp(look.Blade, 0.6), bladeMaterial)
		end
		pos += dir * segLength
		lastCf = CFrame.lookAt(pos, pos + dir)
	end
	-- Tip (kissaki)
	local tipLength = width * 1.5
	wedge(model, "Tip", Vector3.new(thickness, width * 0.82, tipLength), lastCf * CFrame.new(0, 0, -tipLength / 2) * CFrame.Angles(0, 0, math.pi), look.Blade, bladeMaterial)
	local tipPos = pos + (lastCf.LookVector * tipLength)

	return finish(model, look, grip, bladeStart, tipPos, width, scale, def.Rarity)
end

return KatanaBuilder
