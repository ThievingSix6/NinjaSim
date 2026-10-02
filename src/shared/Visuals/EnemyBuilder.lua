--[[
	Builds enemy rigs from parts + Motor6Ds so they can walk with a Humanoid on the
	server and be animated procedurally on clients (Motor6D.Transform). Archetypes:
	Dummy, Humanoid, Oni, Beast, Golem, Wisp. Hats and weapons add identity.

	Returns model, info = { HipHeight, Radius, Height }

	When the Blender enemy pack (tools/blender/enemies.py) is imported, the rig's
	box parts turn invisible and sculpted meshes are welded over them: faces, gi
	and hair, samurai armour (def.Armor = "Light" | "Full", def.Menpo), muscular
	oni, hats, weapons, the kitsune, the wisp flame, golem rocks and the training
	dummy. The boxes still drive animation and hit detection. Without the pack,
	the boxes are the look.
]]

local Particles = require(script.Parent.Particles)
local KatanaBuilder = require(script.Parent.KatanaBuilder)
local Assets = require(script.Parent.Assets)

local EnemyBuilder = {}

local rgb = Color3.fromRGB

local function newPart(parent: Instance, name: string, size: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = true
	p.Massless = true
	p.Anchored = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function newWedge(parent: Instance, name: string, size: Vector3, color: Color3, material: Enum.Material?): BasePart
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.Parent = parent
	return p
end

local function weldTo(p: BasePart, target: BasePart, offset: CFrame)
	p.CFrame = target.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = target
	w.Part1 = p
	w.Parent = p
end

local function motor(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame): Motor6D
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.C1 = c1
	m.Parent = part0
	part1.CFrame = part0.CFrame * c0 * c1:Inverse()
	return m
end

-- ---------------------------------------------------------------- meshes

local REF = {
	Torso = Vector3.new(2, 2, 1.05),
	Head = Vector3.new(1.25, 1.25, 1.25),
	Arm = Vector3.new(0.9, 2, 0.9),
	Leg = Vector3.new(0.95, 2, 0.95),
	HoodHead = Vector3.new(1.2, 1.2, 1.2), -- the ninja suit's hood was made for a 1.2 head
	OniTorso = Vector3.new(2.6, 2.3, 1.05),
	OniHead = Vector3.new(1.5, 1.5, 1.5),
	OniArm = Vector3.new(1.15, 2.3, 1.15),
	OniLeg = Vector3.new(1.15, 2, 1.15),
	Wisp = Vector3.new(2.2, 2.2, 2.2),
	GolemTorso = Vector3.new(3.2, 3, 2),
	GolemHead = Vector3.new(1.4, 1.2, 1.3),
	GolemArm = Vector3.new(1.4, 3, 1.4),
	GolemFist = Vector3.new(1.7, 1.3, 1.7),
	GolemBoulder = Vector3.new(1.8, 1.4, 1.8),
	GolemLeg = Vector3.new(1.3, 1.8, 1.3),
	FoxBody = Vector3.new(2.2, 1.6, 4),
	FoxHead = Vector3.new(1.6, 1.4, 1.6),
	FoxLeg = Vector3.new(0.6, 1.6, 0.6),
	FoxTail = Vector3.new(0.5, 0.5, 2),
}
-- Hero demon suits (tools/blender/hero_demons.py): one textured mesh per R6 part,
-- HeroDemon_<variant>_<Part>, made for these part sizes, plus __Glow meshes
-- (eyes, scars, sigils) lit in the enemy's eye colour.
local DEMON_REF = {
	Head = Vector3.new(1.25, 1.25, 1.25),
	Torso = Vector3.new(2, 2, 1.05),
	RightArm = Vector3.new(0.9, 2, 0.9),
	LeftArm = Vector3.new(0.9, 2, 0.9),
	RightLeg = Vector3.new(0.95, 2, 0.95),
	LeftLeg = Vector3.new(0.95, 2, 0.95),
}
local DEMON_GLOW = Color3.fromRGB(255, 70, 30)
local DARK = rgb(34, 28, 30)
local BONE = rgb(245, 240, 225)
local STRAW = rgb(225, 205, 150)
local IRON = rgb(60, 60, 66)

local function eyeLook(def): (Color3, Enum.Material)
	return def.Colors.Eyes or rgb(20, 20, 20), if def.GlowEyes then Enum.Material.Neon else Enum.Material.SmoothPlastic
end

-- Welds a mesh over `target`, scaled from the reference part size (or by `scale`).
local function dress(model: Instance, target: BasePart, name: string, ref: Vector3?, color: Color3, material: Enum.Material?, offset: CFrame?, scale: Vector3?): MeshPart?
	local mesh = Assets.Mesh(name, color, material)
	if not mesh then
		return nil
	end
	Assets.Place(mesh, target.CFrame * (offset or CFrame.new()), scale or (if ref then target.Size / ref else Vector3.one))
	local w = Instance.new("WeldConstraint")
	w.Part0 = target
	w.Part1 = mesh
	w.Parent = mesh
	mesh.Parent = model
	return mesh
end

-- True when every part of the def's demon suit was imported.
local function hasDemon(def): boolean
	if not def.Demon then
		return false
	end
	local prefix = "HeroDemon_" .. def.Demon .. "_"
	for part in pairs(DEMON_REF) do
		if not Assets.Has(prefix .. part) then
			return false
		end
	end
	return true
end

-- Dresses the rig parts (by name) in the def's demon suit.
local function dressDemon(model: Model, def, parts: { [string]: BasePart })
	local c = def.Colors
	local glow = if def.GlowEyes and c.Eyes then c.Eyes else DEMON_GLOW
	local prefix = "HeroDemon_" .. def.Demon .. "_"
	for part, target in pairs(parts) do
		local ref = DEMON_REF[part]
		local mesh = Assets.Textured(prefix .. part, c.Clothes or c.Body)
		if mesh then
			Assets.Place(mesh, target.CFrame, target.Size / ref)
			local w = Instance.new("WeldConstraint")
			w.Part0 = target
			w.Part1 = mesh
			w.Parent = mesh
			mesh.Parent = model
		end
		dress(model, target, prefix .. part .. "__Glow", ref, glow, Enum.Material.Neon)
	end
end

local function hide(...: BasePart)
	for _, p in ipairs({ ... }) do
		p.Transparency = 1
	end
end

local function addEyes(head: BasePart, def, s: number, frontZ: number, y: number, spacing: number)
	local material = if def.GlowEyes then Enum.Material.Neon else Enum.Material.SmoothPlastic
	for side = -1, 1, 2 do
		local eye = newPart(head, "Eye", Vector3.new(0.22, 0.16, 0.06) * s, def.Colors.Eyes or rgb(20, 20, 20), material)
		eye.CanQuery = false
		weldTo(eye, head, CFrame.new(side * spacing * s, y * s, frontZ) * CFrame.Angles(0, 0, math.rad(side * -10)))
	end
end

local function meshHat(model: Model, head: BasePart, def): boolean
	local hat = def.Hat or "None"
	local c = def.Colors
	local glow = if def.GlowEyes then Enum.Material.Neon else Enum.Material.Foil
	if hat == "Kasa" and Assets.Has("EnemyHat_Kasa__Straw") then
		dress(model, head, "EnemyHat_Kasa__Straw", REF.Head, rgb(214, 186, 120), Enum.Material.Fabric)
		dress(model, head, "EnemyHat_Kasa__Band", REF.Head, c.Accent, Enum.Material.Fabric)
	elseif hat == "Kabuto" and Assets.Has("EnemyHat_Kabuto__Metal") then
		dress(model, head, "EnemyHat_Kabuto__Metal", REF.Head, c.Body:Lerp(DARK, 0.3), Enum.Material.Metal)
		dress(model, head, "EnemyHat_Kabuto__Crest", REF.Head, c.Accent, glow)
		dress(model, head, "EnemyHat_Kabuto__Lace", REF.Head, c.Accent, Enum.Material.Fabric)
	elseif hat == "Horns" and Assets.Has("EnemyHorns__Horn") then
		dress(model, head, "EnemyHorns__Horn", REF.Head, c.Accent, Enum.Material.SmoothPlastic)
	elseif hat == "Crown" and Assets.Has("EnemyHat_Crown__Gold") then
		dress(model, head, "EnemyHat_Crown__Gold", REF.Head, c.Accent, Enum.Material.Foil)
		dress(model, head, "EnemyHat_Crown__Gems", REF.Head, c.Accent:Lerp(Color3.new(1, 1, 1), 0.35), Enum.Material.Neon)
	elseif hat == "Hood" and Assets.Has("NSuitHood__Cloth", "NSuitHood__Mask") then
		local cloth = c.Clothes or c.Body
		dress(model, head, "NSuitHood__Cloth", REF.HoodHead, cloth, Enum.Material.Fabric)
		dress(model, head, "NSuitHood__Mask", REF.HoodHead, cloth:Lerp(DARK, 0.5), Enum.Material.Fabric)
		dress(model, head, "NSuitHood__Band", REF.HoodHead, c.Accent, Enum.Material.Fabric)
		dress(model, head, "NSuitHood__Plate", REF.HoodHead, rgb(150, 155, 165), Enum.Material.Metal)
	elseif hat == "Hood" and Assets.Has("NinjaHood__Cloth", "NinjaHood__Mask") then
		local cloth = c.Clothes or c.Body
		dress(model, head, "NinjaHood__Cloth", REF.HoodHead, cloth, Enum.Material.Fabric)
		dress(model, head, "NinjaHood__Mask", REF.HoodHead, cloth:Lerp(DARK, 0.5), Enum.Material.Fabric)
		dress(model, head, "NinjaHood__Band", REF.HoodHead, c.Accent, Enum.Material.Fabric)
	elseif hat == "Bandana" and Assets.Has("EnemyHat_Bandana__Cloth") then
		dress(model, head, "EnemyHat_Bandana__Cloth", REF.Head, c.Accent, Enum.Material.Fabric)
	elseif hat == "Topknot" and Assets.Has("EnemyHat_Topknot__Hair") then
		dress(model, head, "EnemyHat_Topknot__Hair", REF.Head, DARK, Enum.Material.SmoothPlastic)
	elseif hat == "Halo" and Assets.Has("NSuitHalo__Ring") then
		dress(model, head, "NSuitHalo__Ring", REF.HoodHead, c.Accent, Enum.Material.Neon)
	elseif hat == "Bandana" and Assets.Has("NinjaHood__Band") then
		-- the hood's headband, tightened to sit on a bare head
		dress(model, head, "NinjaHood__Band", REF.HoodHead * 1.18, c.Accent, Enum.Material.Fabric)
	elseif hat == "Halo" and Assets.Has("NinjaHalo__Ring") then
		dress(model, head, "NinjaHalo__Ring", REF.HoodHead, c.Accent, Enum.Material.Neon)
	else
		return false
	end
	return true
end

local function addHat(model: Model, head: BasePart, def, s: number, headSize: number)
	if meshHat(model, head, def) then
		return
	end
	local hat = def.Hat or "None"
	local c = def.Colors
	local top = headSize / 2
	if hat == "Kasa" then
		local straw = rgb(214, 186, 120)
		local brim = newPart(model, "Kasa", Vector3.new(0.12, 2.8, 2.8) * s, straw, Enum.Material.Fabric, Enum.PartType.Cylinder)
		weldTo(brim, head, CFrame.new(0, top + 0.1 * s, 0) * CFrame.Angles(0, 0, math.pi / 2))
		for i = 1, 3 do
			local ring = newPart(model, "Kasa", Vector3.new(0.18, (2.6 - i * 0.75) * s, (2.6 - i * 0.75) * s), straw:Lerp(Color3.new(0, 0, 0), i * 0.06), Enum.Material.Fabric, Enum.PartType.Cylinder)
			weldTo(ring, head, CFrame.new(0, top + (0.1 + i * 0.16) * s, 0) * CFrame.Angles(0, 0, math.pi / 2))
		end
	elseif hat == "Hood" then
		local hood = newPart(model, "Hood", Vector3.new(1, 1, 1) * headSize * 1.18, c.Clothes or c.Body, Enum.Material.Fabric, Enum.PartType.Ball)
		weldTo(hood, head, CFrame.new(0, 0.05 * s, 0.05 * s))
		local band = newPart(model, "Visor", Vector3.new(headSize * 0.9, headSize * 0.22, 0.1), rgb(20, 20, 24))
		weldTo(band, head, CFrame.new(0, 0.05 * s, -headSize * 0.56))
	elseif hat == "Kabuto" then
		local dome = newPart(model, "Kabuto", Vector3.new(1.25, 1.05, 1.25) * headSize, c.Body, Enum.Material.Metal, Enum.PartType.Ball)
		weldTo(dome, head, CFrame.new(0, 0.28 * headSize, 0.05 * s))
		local guard = newPart(model, "NeckGuard", Vector3.new(1.4 * headSize, 0.45 * headSize, 0.2 * s), c.Body, Enum.Material.Metal)
		weldTo(guard, head, CFrame.new(0, -0.05 * headSize, 0.55 * headSize) * CFrame.Angles(math.rad(-20), 0, 0))
		for side = -1, 1, 2 do
			local horn = newPart(model, "Crest", Vector3.new(0.12 * s, 0.9 * s, 0.08 * s), c.Accent, Enum.Material.Neon)
			weldTo(horn, head, CFrame.new(side * 0.28 * s, top + 0.45 * s, -0.5 * headSize) * CFrame.Angles(0, 0, math.rad(side * -28)))
		end
	elseif hat == "Horns" then
		for side = -1, 1, 2 do
			local horn = newWedge(model, "Horn", Vector3.new(0.18, 0.8, 0.4) * s, c.Accent)
			weldTo(horn, head, CFrame.new(side * 0.4 * headSize, top + 0.3 * s, 0) * CFrame.Angles(0, math.pi / 2, math.rad(side * -18)))
		end
	elseif hat == "Bandana" then
		local band = newPart(model, "Bandana", Vector3.new(0.3 * s, headSize * 1.06, headSize * 1.06), c.Accent, Enum.Material.Fabric, Enum.PartType.Cylinder)
		weldTo(band, head, CFrame.new(0, top * 0.55, 0) * CFrame.Angles(0, 0, math.pi / 2))
		local knot = newPart(model, "Knot", Vector3.new(0.3, 0.3, 0.5) * s, c.Accent, Enum.Material.Fabric)
		weldTo(knot, head, CFrame.new(0, top * 0.5, headSize * 0.6) * CFrame.Angles(math.rad(30), 0, 0))
	elseif hat == "Crown" then
		for i = 0, 7 do
			local a = i * math.pi / 4
			local spike = newWedge(model, "Crown", Vector3.new(0.12, 0.55, 0.3) * s, c.Accent, Enum.Material.Neon)
			weldTo(spike, head, CFrame.new(math.cos(a) * headSize * 0.45, top + 0.25 * s, math.sin(a) * headSize * 0.45) * CFrame.Angles(0, -a, 0))
		end
	elseif hat == "Topknot" then
		local knot = newPart(model, "Topknot", Vector3.new(0.5, 0.5, 0.5) * s, rgb(30, 30, 30), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		weldTo(knot, head, CFrame.new(0, top + 0.2 * s, 0.1 * s))
	elseif hat == "Halo" then
		for i = 0, 11 do
			local a = i * math.pi * 2 / 12
			local seg = newPart(model, "Halo", Vector3.new(0.3, 0.08, 0.12) * s, c.Accent, Enum.Material.Neon)
			seg.CanQuery = false
			weldTo(seg, head, CFrame.new(math.cos(a) * headSize * 0.6, top + 0.6 * s, math.sin(a) * headSize * 0.6) * CFrame.Angles(0, -a + math.pi / 2, 0))
		end
	end
end

-- Weapons are built pointing along -Z from the origin, then welded to the hand.
local MESH_WEAPONS = {
	-- weapon -> mesh prefix, grip angle, pieces { suffix, colour key or Color3, material }
	Club = { "EnemyKanabo", -30, { { "Wood", rgb(52, 46, 52), Enum.Material.Metal }, { "Studs", rgb(200, 200, 205), Enum.Material.Metal }, { "Grip", "Accent", Enum.Material.Fabric } } },
	Spear = { "EnemyYari", -15, { { "Shaft", rgb(110, 80, 50), Enum.Material.Wood }, { "Blade", rgb(220, 220, 230), Enum.Material.Metal }, { "Tassel", "Accent", Enum.Material.Fabric } } },
	Staff = { "EnemyStaff", -80, { { "Wood", rgb(120, 90, 60), Enum.Material.Wood }, { "Metal", rgb(230, 190, 90), Enum.Material.Foil }, { "Orb", "Accent", Enum.Material.Neon } } },
	Dagger = { "EnemyKunai", -10, { { "Blade", rgb(200, 202, 212), Enum.Material.Metal }, { "Grip", "Accent", Enum.Material.Fabric } } },
}

local function meshWeapon(model: Model, arm: BasePart, def, s: number, hand: CFrame): boolean
	local info = MESH_WEAPONS[def.Weapon or "None"]
	if not info or not Assets.Has(info[1] .. "__" .. info[3][1][1]) then
		return false
	end
	local grip = arm.CFrame * hand * CFrame.Angles(math.rad(info[2]), 0, 0)
	for _, piece in ipairs(info[3]) do
		local color = if piece[2] == "Accent" then def.Colors.Accent else piece[2]
		local mesh = Assets.Mesh(info[1] .. "__" .. piece[1], color, piece[3])
		if mesh then
			Assets.Place(mesh, grip, Vector3.one * s)
			local w = Instance.new("WeldConstraint")
			w.Part0 = arm
			w.Part1 = mesh
			w.Parent = mesh
			mesh.Parent = model
		end
	end
	return true
end

local function addWeapon(model: Model, arm: BasePart, def, s: number, armLength: number)
	local weapon = def.Weapon or "None"
	local c = def.Colors
	local hand = CFrame.new(0, -armLength / 2 + 0.2 * s, 0)
	if meshWeapon(model, arm, def, s, hand) then
		return
	end
	if weapon == "Claws" and Assets.Has("EnemyClaw__Blade", "EnemyClawL__Blade") then
		local material = if def.GlowEyes then Enum.Material.Neon else Enum.Material.Metal
		for _, armPart in ipairs({ arm, model:FindFirstChild("LeftArm") :: BasePart? }) do
			if armPart then
				local left = armPart.Name == "LeftArm"
				dress(model, armPart, if left then "EnemyClawL__Blade" else "EnemyClaw__Blade", REF.Arm, c.Accent, material)
				dress(model, armPart, "EnemyClaw__Band", REF.Arm, DARK, Enum.Material.SmoothPlastic)
			end
		end
		return
	end
	if weapon == "Katana" or weapon == "Greatsword" or weapon == "Dagger" then
		local look = {
			Blade = if weapon == "Greatsword" then c.Accent:Lerp(rgb(220, 220, 225), 0.5) else rgb(210, 210, 220),
			BladeMaterial = Enum.Material.Metal, Edge = c.Accent, EdgeGlow = def.GlowEyes == true,
			Length = if weapon == "Dagger" then 1.4 elseif weapon == "Greatsword" then 4.4 else 3.4,
			Width = if weapon == "Greatsword" then 0.55 else 0.26,
			Curve = if weapon == "Greatsword" then 0.02 else 0.12,
			Guard = if weapon == "Greatsword" then "Wings" else "Round",
			GuardColor = c.Accent, Handle = rgb(30, 25, 25), Wrap = c.Accent, Pommel = "Cap",
			Trail = { c.Accent, c.Accent },
		}
		local blade = KatanaBuilder.Build({ Id = "EnemyBlade", Look = look }, s)
		for _, p in ipairs(blade:GetDescendants()) do
			if p:IsA("BasePart") then
				p.CanQuery = false
			elseif p:IsA("ParticleEmitter") or p:IsA("PointLight") then
				p:Destroy()
			end
		end
		blade:PivotTo(arm.CFrame * hand * CFrame.Angles(math.rad(-30), 0, 0))
		local grip = blade.PrimaryPart :: BasePart
		local w = Instance.new("WeldConstraint")
		w.Part0 = arm
		w.Part1 = grip
		w.Parent = grip
		blade.Parent = model
	elseif weapon == "Spear" then
		local shaft = newPart(model, "Spear", Vector3.new(0.16, 0.16, 6.5) * s, rgb(110, 80, 50), Enum.Material.Wood)
		shaft.CanQuery = false
		weldTo(shaft, arm, hand * CFrame.Angles(math.rad(-15), 0, 0) * CFrame.new(0, 0, -1.8 * s))
		local tip = newWedge(model, "SpearTip", Vector3.new(0.1, 0.35, 0.9) * s, rgb(220, 220, 230), Enum.Material.Metal)
		weldTo(tip, shaft, CFrame.new(0, 0, -3.6 * s) * CFrame.Angles(0, 0, math.pi))
		local tassel = newPart(model, "SpearTassel", Vector3.new(0.3, 0.3, 0.3) * s, c.Accent, Enum.Material.Fabric)
		weldTo(tassel, shaft, CFrame.new(0, 0, -3.1 * s))
	elseif weapon == "Club" then
		local club = newPart(model, "Club", Vector3.new(2.6, 0.7, 0.7) * s, c.Clothes or rgb(90, 60, 40), Enum.Material.Wood, Enum.PartType.Cylinder)
		club.CanQuery = false
		weldTo(club, arm, hand * CFrame.Angles(math.rad(-30), 0, 0) * CFrame.new(0, 0, -1.2 * s) * CFrame.Angles(0, math.pi / 2, 0))
		for i = 0, 3 do
			local stud = newPart(model, "ClubStud", Vector3.new(0.25, 0.25, 0.25) * s, rgb(200, 200, 200), Enum.Material.Metal)
			weldTo(stud, club, CFrame.new(0.5 * s + i * 0.25 * s, 0, 0) * CFrame.Angles(i, i * 2, 0) * CFrame.new(0, 0.35 * s, 0))
		end
	elseif weapon == "Staff" then
		local staff = newPart(model, "Staff", Vector3.new(0.18, 0.18, 6) * s, rgb(120, 90, 60), Enum.Material.Wood)
		staff.CanQuery = false
		weldTo(staff, arm, hand * CFrame.Angles(math.rad(-80), 0, 0))
		local orb = newPart(model, "StaffOrb", Vector3.new(0.6, 0.6, 0.6) * s, c.Accent, Enum.Material.Neon, Enum.PartType.Ball)
		orb.CanQuery = false
		weldTo(orb, staff, CFrame.new(0, 0, -3 * s))
	elseif weapon == "Claws" then
		for _, armPart in ipairs({ arm, model:FindFirstChild("LeftArm") :: BasePart? }) do
			if armPart then
				for i = -1, 1 do
					local claw = newWedge(model, "Claw", Vector3.new(0.08, 0.2, 0.9) * s, c.Accent, if def.GlowEyes then Enum.Material.Neon else Enum.Material.Metal)
					weldTo(claw, armPart, CFrame.new(i * 0.25 * s, -armLength / 2 - 0.1 * s, -0.3 * s) * CFrame.Angles(math.rad(-60), 0, math.pi))
				end
			end
		end
	end
end

local function buildHumanoidRig(model: Model, def, s: number, oni: boolean)
	local c = def.Colors
	local mat = def.Material or Enum.Material.SmoothPlastic
	local torsoW = (if oni then 2.6 else 2) * s
	local armW = (if oni then 1.15 else 0.9) * s
	local legLen = 2 * s
	local torsoH = (if oni then 2.3 else 2) * s
	local armLen = (if oni then 2.3 else 2) * s

	local root = newPart(model, "HumanoidRootPart", Vector3.new(torsoW, torsoH, 1 * s), c.Body)
	root.Transparency = 1
	root.CanCollide = true
	root.CFrame = CFrame.new(0, legLen + torsoH / 2, 0)

	local torso = newPart(model, "Torso", Vector3.new(torsoW, torsoH, 1.05 * s), c.Clothes or c.Body, mat)
	motor("Waist", root, torso, CFrame.new(), CFrame.new())
	local headSize = (if oni then 1.5 else 1.25) * s
	local head = newPart(model, "Head", Vector3.new(headSize, headSize, headSize), c.Skin or c.Body, mat)
	motor("Neck", torso, head, CFrame.new(0, torsoH / 2 + headSize / 2, 0), CFrame.new())

	local right = newPart(model, "RightArm", Vector3.new(armW, armLen, armW), c.Skin or c.Body, mat)
	motor("RightShoulder", torso, right, CFrame.new(torsoW / 2 + armW / 2, torsoH / 2 - 0.25 * s, 0), CFrame.new(0, armLen / 2 - 0.25 * s, 0))
	local left = newPart(model, "LeftArm", Vector3.new(armW, armLen, armW), c.Skin or c.Body, mat)
	motor("LeftShoulder", torso, left, CFrame.new(-torsoW / 2 - armW / 2, torsoH / 2 - 0.25 * s, 0), CFrame.new(0, armLen / 2 - 0.25 * s, 0))
	local legW = (if oni then 1.15 else 0.95) * s
	local rightLeg = newPart(model, "RightLeg", Vector3.new(legW, legLen, legW), c.Clothes or c.Body, mat)
	motor("RightHip", torso, rightLeg, CFrame.new(torsoW / 4, -torsoH / 2, 0), CFrame.new(0, legLen / 2, 0))
	local leftLeg = newPart(model, "LeftLeg", Vector3.new(legW, legLen, legW), c.Clothes or c.Body, mat)
	motor("LeftHip", torso, leftLeg, CFrame.new(-torsoW / 4, -torsoH / 2, 0), CFrame.new(0, legLen / 2, 0))

	local clothes, skin = c.Clothes or c.Body, c.Skin or c.Body
	local eyeColor, eyeMaterial = eyeLook(def)
	local meshed = if oni
		then Assets.Has("EnemyOniTorso__Skin", "EnemyOniHead__Skin", "EnemyOniArm__Skin", "EnemyOniArmL__Skin", "EnemyOniLeg__Skin", "EnemyOniLegL__Skin")
		else Assets.Has("EnemyTorso__Cloth", "EnemyHead__Skin", "EnemyArm__Skin", "EnemyArmL__Skin", "EnemyLeg__Pants", "EnemyLegL__Boot")
	local demon = hasDemon(def)
	if demon then
		-- hero demon suit: horns, fangs, glowing eyes, textured like the hero ninjas
		hide(torso, head, right, left, rightLeg, leftLeg)
		dressDemon(model, def, { Head = head, Torso = torso, RightArm = right, LeftArm = left, RightLeg = rightLeg, LeftLeg = leftLeg })
	elseif meshed and oni then
		-- sculpted oni: muscles, tiger-skin loincloth, rope belt, tusks and a wild mane
		hide(torso, head, right, left, rightLeg, leftLeg)
		dress(model, torso, "EnemyOniTorso__Skin", REF.OniTorso, skin, mat)
		dress(model, torso, "EnemyOniTorso__Cloth", REF.OniTorso, clothes, Enum.Material.Fabric)
		dress(model, torso, "EnemyOniTorso__Stripe", REF.OniTorso, DARK, Enum.Material.Fabric)
		dress(model, torso, "EnemyOniTorso__Rope", REF.OniTorso, STRAW, Enum.Material.Fabric)
		dress(model, head, "EnemyOniHead__Skin", REF.OniHead, skin, mat)
		dress(model, head, "EnemyOniHead__Eyes", REF.OniHead, eyeColor, eyeMaterial)
		dress(model, head, "EnemyOniHead__Brow", REF.OniHead, DARK, Enum.Material.SmoothPlastic)
		dress(model, head, "EnemyOniHead__Fangs", REF.OniHead, BONE, Enum.Material.SmoothPlastic)
		dress(model, head, "EnemyOniHead__Hair", REF.OniHead, DARK, Enum.Material.SmoothPlastic)
		dress(model, right, "EnemyOniArm__Skin", REF.OniArm, skin, mat)
		dress(model, left, "EnemyOniArmL__Skin", REF.OniArm, skin, mat)
		dress(model, rightLeg, "EnemyOniLeg__Skin", REF.OniLeg, skin, mat)
		dress(model, leftLeg, "EnemyOniLegL__Skin", REF.OniLeg, skin, mat)
		for _, p in ipairs({ right, left }) do
			dress(model, p, "EnemyOniArm__Cuff", REF.OniArm, IRON, Enum.Material.Metal)
		end
		for _, p in ipairs({ rightLeg, leftLeg }) do
			dress(model, p, "EnemyOniLeg__Cuff", REF.OniLeg, IRON, Enum.Material.Metal)
		end
	elseif meshed then
		-- sculpted face, gi and wraps over the (now invisible) rig boxes
		hide(torso, head, right, left, rightLeg, leftLeg)
		dress(model, torso, "EnemyTorso__Cloth", REF.Torso, clothes, Enum.Material.Fabric)
		dress(model, torso, "EnemyTorso__Skin", REF.Torso, skin, mat)
		dress(model, torso, "EnemyTorso__Trim", REF.Torso, c.Accent, Enum.Material.Fabric)
		dress(model, head, "EnemyHead__Skin", REF.Head, skin, mat)
		dress(model, head, "EnemyHead__Eyes", REF.Head, eyeColor, eyeMaterial)
		dress(model, head, "EnemyHead__Brow", REF.Head, DARK, Enum.Material.SmoothPlastic)
		local hat = def.Hat or "None"
		if hat ~= "Hood" and hat ~= "Kabuto" and hat ~= "Topknot" then
			dress(model, head, "EnemyHead__Hair", REF.Head, DARK, Enum.Material.SmoothPlastic)
		end
		local wrap = clothes:Lerp(rgb(220, 205, 180), 0.5)
		for _, arm in ipairs({ right, left }) do
			dress(model, arm, "EnemyArm__Sleeve", REF.Arm, clothes, Enum.Material.Fabric)
			dress(model, arm, if arm == left then "EnemyArmL__Skin" else "EnemyArm__Skin", REF.Arm, skin, mat)
			dress(model, arm, "EnemyArm__Wrap", REF.Arm, c.Accent, Enum.Material.Fabric)
		end
		for _, leg in ipairs({ rightLeg, leftLeg }) do
			dress(model, leg, "EnemyLeg__Pants", REF.Leg, clothes, Enum.Material.Fabric)
			dress(model, leg, "EnemyLeg__Wrap", REF.Leg, wrap, Enum.Material.Fabric)
			dress(model, leg, if leg == leftLeg then "EnemyLegL__Boot" else "EnemyLeg__Boot", REF.Leg, DARK, Enum.Material.SmoothPlastic)
		end
		-- samurai armour: cuirass and shin guards, shoulder guards for full sets, face guard
		if def.Armor and Assets.Has("EnemyDo__Plate", "EnemySuneate__Plate") then
			local plate = c.Body
			dress(model, torso, "EnemyDo__Plate", REF.Torso, plate, Enum.Material.Metal)
			dress(model, torso, "EnemyDo__Lace", REF.Torso, c.Accent, Enum.Material.Fabric)
			for _, leg in ipairs({ rightLeg, leftLeg }) do
				dress(model, leg, "EnemySuneate__Plate", REF.Leg, plate, Enum.Material.Metal)
			end
			if def.Armor == "Full" then
				for _, arm in ipairs({ right, left }) do
					local flip = if arm == left then CFrame.Angles(0, math.pi, 0) else nil
					dress(model, arm, "EnemySode__Plate", REF.Arm, plate, Enum.Material.Metal, flip)
					dress(model, arm, "EnemySode__Lace", REF.Arm, c.Accent, Enum.Material.Fabric, flip)
				end
			end
		end
		if def.Menpo and Assets.Has("EnemyMenpo__Mask") then
			dress(model, head, "EnemyMenpo__Mask", REF.Head, c.Body, Enum.Material.Metal)
			dress(model, head, "EnemyMenpo__Stache", REF.Head, DARK, Enum.Material.SmoothPlastic)
		end
	else
		-- Clothing details: belt, shirt sleeves, chest piece
		local belt = newPart(model, "Belt", Vector3.new(torsoW * 1.04, 0.3 * s, 1.12 * s), c.Accent)
		weldTo(belt, torso, CFrame.new(0, -torsoH / 2 + 0.3 * s, 0))
		for _, arm in ipairs({ right, left }) do
			local sleeve = newPart(model, "Sleeve", Vector3.new(armW * 1.1, armLen * 0.45, armW * 1.1), c.Clothes or c.Body, Enum.Material.Fabric)
			weldTo(sleeve, arm, CFrame.new(0, armLen * 0.28, 0))
		end
		if oni then
			local loin = newPart(model, "Loincloth", Vector3.new(torsoW * 0.5, 1 * s, 0.1 * s), c.Accent, Enum.Material.Fabric)
			weldTo(loin, torso, CFrame.new(0, -torsoH / 2 - 0.4 * s, -0.58 * s))
			local belly = newPart(model, "Belly", Vector3.new(torsoW * 0.7, torsoH * 0.55, 0.3 * s), c.Skin or c.Body, mat)
			weldTo(belly, torso, CFrame.new(0, -0.1 * s, -0.45 * s))
			local mouth = newPart(model, "Fangs", Vector3.new(headSize * 0.6, 0.18 * s, 0.1 * s), rgb(245, 240, 225))
			weldTo(mouth, head, CFrame.new(0, -headSize * 0.25, -headSize / 2 - 0.03))
		else
			local chest = newPart(model, "Chest", Vector3.new(torsoW * 0.5, torsoH * 0.5, 0.12 * s), c.Body, mat)
			weldTo(chest, torso, CFrame.new(0, torsoH * 0.15, -0.55 * s))
		end
		addEyes(head, def, s, -headSize / 2 - 0.02, 0.1, 0.25)
	end

	if not demon or def.Hat == "Halo" then -- demon suits carry their own headgear
		addHat(model, head, def, s, headSize)
	end
	addWeapon(model, right, def, s, armLen)

	return root, legLen, math.max(torsoW, 1.05 * s) / 2 + 0.6 * s, legLen + torsoH + headSize
end

local function buildBeastRig(model: Model, def, s: number)
	local c = def.Colors
	local legLen = 1.6 * s
	local bodySize = Vector3.new(2.2, 1.6, 4) * s
	local root = newPart(model, "HumanoidRootPart", bodySize, c.Body)
	root.Transparency = 1
	root.CanCollide = true
	root.CFrame = CFrame.new(0, legLen + bodySize.Y / 2, 0)

	local body = newPart(model, "Torso", bodySize, c.Body, Enum.Material.SmoothPlastic)
	motor("Waist", root, body, CFrame.new(), CFrame.new())
	local belly = newPart(model, "Belly", Vector3.new(bodySize.X * 0.8, 0.3 * s, bodySize.Z * 0.7), c.Accent)
	weldTo(belly, body, CFrame.new(0, -bodySize.Y / 2, 0))

	local headSize = Vector3.new(1.6, 1.4, 1.6) * s
	local head = newPart(model, "Head", headSize, c.Body)
	motor("Neck", body, head, CFrame.new(0, bodySize.Y * 0.45, -bodySize.Z / 2 - 0.3 * s), CFrame.new(0, 0, 0.3 * s))
	local snout = newPart(model, "Snout", Vector3.new(0.9, 0.7, 0.9) * s, c.Accent)
	weldTo(snout, head, CFrame.new(0, -0.25 * s, -headSize.Z / 2 - 0.3 * s))
	local nose = newPart(model, "Nose", Vector3.new(0.3, 0.25, 0.1) * s, rgb(20, 20, 20))
	weldTo(nose, snout, CFrame.new(0, 0.15 * s, -0.46 * s))
	for side = -1, 1, 2 do
		local ear = newWedge(model, "Ear", Vector3.new(0.15, 0.7, 0.5) * s, c.Body)
		weldTo(ear, head, CFrame.new(side * 0.5 * s, headSize.Y / 2 + 0.3 * s, 0.1 * s) * CFrame.Angles(0, math.pi / 2, math.rad(side * -10)))
	end
	addEyes(head, def, s, -headSize.Z / 2 - 0.02, 0.2, 0.4)

	local legs = {
		{ "FrontRight", 1, -1 }, { "FrontLeft", -1, -1 }, { "BackRight", 1, 1 }, { "BackLeft", -1, 1 },
	}
	for _, info in ipairs(legs) do
		local leg = newPart(model, info[1], Vector3.new(0.6, legLen, 0.6) * Vector3.new(s, 1, s), c.Body)
		motor(info[1], body, leg, CFrame.new(info[2] * bodySize.X * 0.35, -bodySize.Y / 2, info[3] * bodySize.Z * 0.35), CFrame.new(0, legLen / 2, 0))
		local paw = newPart(model, "Paw", Vector3.new(0.7, 0.3, 0.8) * s, c.Accent)
		weldTo(paw, leg, CFrame.new(0, -legLen / 2 + 0.15 * s, -0.1 * s))
	end
	local tails = def.Tails or 1
	for i = 1, tails do
		local spread = if tails > 1 then (i - (tails + 1) / 2) * 0.35 else 0
		local tail = newPart(model, "Tail", Vector3.new(0.5, 0.5, 2) * s, c.Body)
		local m = motor("Tail" .. i, body, tail, CFrame.new(0, bodySize.Y * 0.3, bodySize.Z / 2) * CFrame.Angles(math.rad(35), spread, 0), CFrame.new(0, 0, -1 * s))
		m:SetAttribute("Tail", true)
		local tip = newPart(model, "TailTip", Vector3.new(0.55, 0.55, 0.7) * s, c.Accent, Enum.Material.SmoothPlastic)
		weldTo(tip, tail, CFrame.new(0, 0, 1 * s))
	end
	if def.Particles or def.GlowEyes then
		for side = -1, 1, 2 do
			local stripe = newPart(model, "Stripe", Vector3.new(0.08, 0.9 * s, bodySize.Z * 0.6), c.Accent, Enum.Material.Neon)
			weldTo(stripe, body, CFrame.new(side * bodySize.X / 2, 0.1 * s, 0))
		end
	end
	return root, legLen, bodySize.Z / 2, legLen + bodySize.Y + headSize.Y * 0.5
end

local function buildGolemRig(model: Model, def, s: number)
	local c = def.Colors
	local mat = def.Material or Enum.Material.Slate
	local legLen = 1.8 * s
	local torsoSize = Vector3.new(3.2, 3, 2) * s
	local root = newPart(model, "HumanoidRootPart", torsoSize, c.Body)
	root.Transparency = 1
	root.CanCollide = true
	root.CFrame = CFrame.new(0, legLen + torsoSize.Y / 2, 0)
	local torso = newPart(model, "Torso", torsoSize, c.Body, mat)
	motor("Waist", root, torso, CFrame.new(), CFrame.new())
	local head = newPart(model, "Head", Vector3.new(1.4, 1.2, 1.3) * s, c.Body, mat)
	motor("Neck", torso, head, CFrame.new(0, torsoSize.Y / 2 + 0.4 * s, -0.3 * s), CFrame.new())
	addEyes(head, def, s, -0.67 * s, 0.05, 0.3)
	local armLen = 3 * s
	for _, side in ipairs({ 1, -1 }) do
		local arm = newPart(model, if side > 0 then "RightArm" else "LeftArm", Vector3.new(1.4, armLen, 1.4) * Vector3.new(s, 1, s), c.Body, mat)
		motor(if side > 0 then "RightShoulder" else "LeftShoulder", torso, arm, CFrame.new(side * (torsoSize.X / 2 + 0.75 * s), torsoSize.Y / 2 - 0.4 * s, 0), CFrame.new(0, armLen / 2 - 0.4 * s, 0))
		local fist = newPart(model, "Fist", Vector3.new(1.7, 1.3, 1.7) * s, c.Body, mat)
		weldTo(fist, arm, CFrame.new(0, -armLen / 2, 0))
		local shoulder = newPart(model, "Boulder", Vector3.new(1.8, 1.4, 1.8) * s, c.Body, mat)
		weldTo(shoulder, arm, CFrame.new(0, armLen / 2 - 0.2 * s, 0) * CFrame.Angles(0.3, 0.5, 0.2))
		local leg = newPart(model, if side > 0 then "RightLeg" else "LeftLeg", Vector3.new(1.3, legLen, 1.3) * Vector3.new(s, 1, s), c.Body, mat)
		motor(if side > 0 then "RightHip" else "LeftHip", torso, leg, CFrame.new(side * torsoSize.X * 0.28, -torsoSize.Y / 2, 0), CFrame.new(0, legLen / 2, 0))
	end
	-- glowing cracks
	for i = 1, 5 do
		local crack = newPart(model, "Crack", Vector3.new(0.12 * s, (0.6 + (i % 3) * 0.4) * s, 0.06 * s), c.Accent, Enum.Material.Neon)
		crack.CanQuery = false
		weldTo(crack, torso, CFrame.new((i - 3) * 0.55 * s, ((i % 2) - 0.5) * 0.8 * s, -torsoSize.Z / 2 - 0.02) * CFrame.Angles(0, 0, (i - 3) * 0.4))
	end
	local core = newPart(model, "Core", Vector3.new(0.9, 0.9, 0.2) * s, c.Accent, Enum.Material.Neon, Enum.PartType.Cylinder)
	weldTo(core, torso, CFrame.new(0, 0.3 * s, -torsoSize.Z / 2 - 0.05) * CFrame.Angles(0, math.pi / 2, 0))
	return root, legLen, torsoSize.X / 2 + 1, legLen + torsoSize.Y + 1.4 * s
end

local function buildWispRig(model: Model, def, s: number)
	local c = def.Colors
	local hover = 3 * s
	local bodyD = 2.2 * s
	local root = newPart(model, "HumanoidRootPart", Vector3.new(bodyD, bodyD, bodyD), c.Body)
	root.Transparency = 1
	root.CanCollide = true
	root.CFrame = CFrame.new(0, hover + bodyD / 2, 0)
	local body = newPart(model, "Torso", Vector3.new(bodyD, bodyD, bodyD), c.Body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	body.Transparency = 0.15
	motor("Waist", root, body, CFrame.new(), CFrame.new())
	local core = newPart(model, "Core", Vector3.new(1, 1, 1) * bodyD * 0.55, c.Accent, Enum.Material.Neon, Enum.PartType.Ball)
	weldTo(core, body, CFrame.new())
	local head = body
	addEyes(head, def, s * 1.3, -bodyD / 2 - 0.02, 0.15, 0.3)
	-- wispy tail
	for i = 1, 3 do
		local tail = newPart(model, "Tail", Vector3.new(1, 1, 1) * bodyD * (0.7 - i * 0.15), c.Body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		tail.Transparency = 0.2 + i * 0.15
		weldTo(tail, body, CFrame.new(0, -i * 0.55 * s, i * 0.55 * s))
	end
	for _, side in ipairs({ 1, -1 }) do
		local hand = newPart(model, if side > 0 then "RightArm" else "LeftArm", Vector3.new(0.7, 0.7, 0.7) * s, c.Accent, Enum.Material.Neon, Enum.PartType.Ball)
		motor(if side > 0 then "RightShoulder" else "LeftShoulder", body, hand, CFrame.new(side * (bodyD / 2 + 0.6 * s), -0.2 * s, -0.3 * s), CFrame.new())
	end
	local light = Instance.new("PointLight")
	light.Color = c.Accent
	light.Range = 10 * s
	light.Brightness = 1.5
	light.Parent = core
	return root, hover, bodyD / 2 + 0.5, hover + bodyD
end

local function buildDummy(model: Model, def, s: number)
	local c = def.Colors
	local base = newPart(model, "Base", Vector3.new(0.4, 2.6, 2.6) * s, rgb(90, 70, 50), Enum.Material.Wood, Enum.PartType.Cylinder)
	base.CFrame = CFrame.new(0, 0.2 * s, 0) * CFrame.Angles(0, 0, math.pi / 2)
	local post = newPart(model, "Post", Vector3.new(3.4, 0.5, 0.5) * s, c.Clothes, Enum.Material.Wood, Enum.PartType.Cylinder)
	post.CFrame = CFrame.new(0, 1.9 * s, 0) * CFrame.Angles(0, 0, math.pi / 2)
	local root = newPart(model, "HumanoidRootPart", Vector3.new(2, 2.6, 1.4) * s, c.Body, Enum.Material.Fabric)
	root.CFrame = CFrame.new(0, 3.6 * s, 0)
	root.Transparency = 1
	local body = newPart(model, "Torso", Vector3.new(2.6, 1.9, 1.9) * s, c.Body, Enum.Material.Fabric, Enum.PartType.Cylinder)
	body.CFrame = CFrame.new(0, 3.6 * s, 0) * CFrame.Angles(0, 0, math.pi / 2)
	for i = -1, 1, 2 do
		local rope = newPart(model, "Rope", Vector3.new(0.18, 2, 2) * s, c.Clothes, Enum.Material.Fabric, Enum.PartType.Cylinder)
		rope.CFrame = CFrame.new(0, 3.6 * s + i * 0.8 * s, 0) * CFrame.Angles(0, 0, math.pi / 2)
	end
	local arms = newPart(model, "Arms", Vector3.new(3.6, 0.4, 0.4) * s, c.Clothes, Enum.Material.Wood)
	arms.CFrame = CFrame.new(0, 4.1 * s, 0)
	local head = newPart(model, "Head", Vector3.new(1.4, 1.4, 1.4) * s, c.Body, Enum.Material.Fabric, Enum.PartType.Ball)
	head.CFrame = CFrame.new(0, 5.25 * s, 0)
	-- target rings on the chest
	for i, size in ipairs({ 1.2, 0.8, 0.4 }) do
		local ring = newPart(model, "Target", Vector3.new(0.05, size, size) * s, if i % 2 == 1 then c.Accent else rgb(245, 240, 230), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		ring.CFrame = CFrame.new(0, 3.7 * s, -0.95 * s - i * 0.02) * CFrame.Angles(0, math.pi / 2, 0)
	end
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") then
			p.Anchored = true
		end
	end
	return root, 0, 1.4 * s, 6 * s
end

-- Mesh looks for the non-humanoid rigs, applied after the box rig is built.
local function meshBeast(model: Model, def)
	if not Assets.Has("FoxBody__Fur", "FoxHead__Fur", "FoxLeg__Fur", "FoxTail__Fur") then
		return
	end
	local c = def.Colors
	local skin = Enum.Material.SmoothPlastic
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") and table.find({ "Belly", "Snout", "Nose", "Ear", "Paw", "TailTip", "Stripe" }, p.Name) then
			p:Destroy()
		end
	end
	local body = model:FindFirstChild("Torso") :: BasePart
	local head = model:FindFirstChild("Head") :: BasePart
	hide(body, head)
	dress(model, body, "FoxBody__Fur", REF.FoxBody, c.Body, skin)
	dress(model, body, "FoxBody__Fluff", REF.FoxBody, c.Accent, skin)
	dress(model, head, "FoxHead__Fur", REF.FoxHead, c.Body, skin)
	dress(model, head, "FoxHead__Fluff", REF.FoxHead, c.Accent, skin)
	dress(model, head, "FoxHead__Nose", REF.FoxHead, DARK, skin)
	if Assets.Has("FoxHead__Eyes") then
		local eyeColor, eyeMaterial = eyeLook(def)
		for _, p in ipairs(head:GetChildren()) do
			if p.Name == "Eye" then
				p:Destroy()
			end
		end
		dress(model, head, "FoxHead__Eyes", REF.FoxHead, eyeColor, eyeMaterial)
	end
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") and table.find({ "FrontRight", "FrontLeft", "BackRight", "BackLeft" }, p.Name) then
			hide(p)
			dress(model, p, "FoxLeg__Fur", REF.FoxLeg, c.Body, skin)
			dress(model, p, "FoxLeg__Paw", REF.FoxLeg, c.Accent, skin)
		elseif p:IsA("BasePart") and p.Name == "Tail" then
			hide(p)
			dress(model, p, "FoxTail__Fur", REF.FoxTail, c.Body, skin)
			dress(model, p, "FoxTail__Tip", REF.FoxTail, c.Accent, skin)
		end
	end
end

local GOLEM_PIECES = {
	Torso = { "GolemTorso", REF.GolemTorso, true },
	Head = { "GolemHead", REF.GolemHead },
	RightArm = { "GolemArm", REF.GolemArm },
	LeftArm = { "GolemArm", REF.GolemArm },
	Fist = { "GolemFist", REF.GolemFist },
	Boulder = { "GolemBoulder", REF.GolemBoulder, true },
	RightLeg = { "GolemLeg", REF.GolemLeg },
	LeftLeg = { "GolemLeg", REF.GolemLeg },
}

local function meshGolem(model: Model, def)
	if not Assets.Has("GolemTorso__Rock", "GolemHead__Rock", "GolemArm__Rock", "GolemFist__Rock", "GolemLeg__Rock") then
		return
	end
	local c = def.Colors
	local mat = def.Material or Enum.Material.Slate
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") and (p.Name == "Crack" or p.Name == "Core") then
			p:Destroy()
		end
	end
	for _, p in ipairs(model:GetChildren()) do
		local piece = p:IsA("BasePart") and GOLEM_PIECES[p.Name]
		if piece then
			hide(p)
			dress(model, p, piece[1] .. "__Rock", piece[2], p.Color, mat)
			if piece[3] then
				dress(model, p, piece[1] .. "__Glow", piece[2], c.Accent, Enum.Material.Neon)
			end
		end
	end
end

local function meshWisp(model: Model, def)
	if not Assets.Has("WispBody__Flame") then
		return
	end
	local c = def.Colors
	local body = model:FindFirstChild("Torso") :: BasePart
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") and (p == body or p.Name == "Tail") then
			hide(p)
		end
	end
	local flame = dress(model, body, "WispBody__Flame", REF.Wisp, c.Body:Lerp(c.Accent, 0.35), Enum.Material.Neon)
	if flame then
		flame.Transparency = 0.3
	end
end

local function meshDummy(model: Model, def, s: number)
	if not Assets.Has("Dummy__Wood", "Dummy__Straw") then
		return
	end
	local c = def.Colors
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") then
			if table.find({ "Base", "Post", "Torso", "Rope", "Arms", "Head" }, p.Name) then
				hide(p)
			elseif p.Name == "Target" then
				p.Position += Vector3.new(0, 0, -0.1 * s) -- clear of the rounder straw body
			end
		end
	end
	for _, piece in ipairs({
		{ "Dummy__Wood", rgb(110, 76, 48), Enum.Material.Wood },
		{ "Dummy__Straw", c.Body, Enum.Material.Fabric },
		{ "Dummy__Rope", c.Clothes, Enum.Material.Fabric },
		{ "Dummy__Face", DARK, Enum.Material.SmoothPlastic },
	}) do
		local mesh = Assets.Mesh(piece[1], piece[2], piece[3])
		if mesh then
			Assets.Place(mesh, CFrame.new(), Vector3.one * s)
			mesh.Anchored = true
			mesh.Parent = model
		end
	end
end

function EnemyBuilder.Build(def, scale: number?)
	local s = (scale or 1) * (def.Scale or 1)
	local model = Instance.new("Model")
	model.Name = def.Id
	local root, hipHeight, radius, height
	if def.Archetype == "Dummy" then
		root, hipHeight, radius, height = buildDummy(model, def, s)
		meshDummy(model, def, s)
	elseif def.Archetype == "Beast" then
		root, hipHeight, radius, height = buildBeastRig(model, def, s)
		meshBeast(model, def)
	elseif def.Archetype == "Golem" then
		root, hipHeight, radius, height = buildGolemRig(model, def, s)
		meshGolem(model, def)
	elseif def.Archetype == "Wisp" then
		root, hipHeight, radius, height = buildWispRig(model, def, s)
		meshWisp(model, def)
	else
		root, hipHeight, radius, height = buildHumanoidRig(model, def, s, def.Archetype == "Oni")
	end
	model.PrimaryPart = root

	if def.Particles then
		Particles.Create(def.Particles, root)
	end
	if def.IsBoss then
		local light = Instance.new("PointLight")
		light.Color = def.Colors.Accent
		light.Range = 18
		light.Brightness = 2
		light.Parent = root
	end

	if def.Archetype ~= "Dummy" then
		local humanoid = Instance.new("Humanoid")
		humanoid.RigType = Enum.HumanoidRigType.R15
		humanoid.HipHeight = hipHeight
		humanoid.WalkSpeed = def.Speed
		humanoid.MaxHealth = 1e9
		humanoid.Health = 1e9
		humanoid.RequiresNeck = false
		humanoid.BreakJointsOnDeath = false
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.AutoRotate = true
		humanoid.Parent = model
		for _, state in ipairs({
			Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.Climbing,
			Enum.HumanoidStateType.Swimming, Enum.HumanoidStateType.Seated, Enum.HumanoidStateType.Dead,
			Enum.HumanoidStateType.Flying, Enum.HumanoidStateType.PlatformStanding,
		}) do
			humanoid:SetStateEnabled(state, false)
		end
	end

	return model, { HipHeight = hipHeight, Radius = radius, Height = height }
end

return EnemyBuilder
