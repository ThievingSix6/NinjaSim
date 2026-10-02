--[[
	Dresses a player character as a ninja of a given tier, entirely from parts:
	hood with eye plate, headband with tails, sash, and (per tier Features) chest
	emblem, scarf, shoulder armour, glowing seams, cape, horns, halo and aura.
	Works with both R15 and R6 rigs by looking up body parts by name.

	With the Blender ninja suit (tools/blender/ninja.py) imported, the avatar's body
	parts turn invisible and a sculpted suit is worn over every body part instead:
	hood and mask, gi, obi, sleeves, wraps, gloves, tabi, and per tier a scarf,
	samurai armour, cape, horns and halo. Otherwise the older outfit pack
	(tools/blender/outfit.py) dresses the avatar, and without either the outfit is
	built from parts.
]]

local Particles = require(script.Parent.Particles)
local Assets = require(script.Parent.Assets)

local OutfitBuilder = {}

local OUTFIT_NAME = "NinjaOutfit"

local function findPart(character: Model, ...: string): BasePart?
	for _, name in ipairs({ ... }) do
		local p = character:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	return nil
end

local function makePart(folder: Instance, name: string, size: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Fabric
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.Anchored = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = folder
	return p
end

local function attach(p: BasePart, target: BasePart, offset: CFrame)
	p.CFrame = target.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = target
	weld.Part1 = p
	weld.Parent = p
end

local function headHeight(head: BasePart): number
	if head:IsA("MeshPart") then
		return head.Size.Y
	end
	return head.Size.Y * 1.2 -- R6 head is a 2x1x1 part with a 1.25 scaled mesh
end

-- ---------------------------------------------------------------- mesh outfit

-- Sizes of the default R15 blocky parts the Blender pieces were modelled around.
local REF = {
	Head = Vector3.new(1.2, 1.2, 1.2),
	UpperTorso = Vector3.new(2, 1.6, 1),
	LowerTorso = Vector3.new(2, 0.4, 1),
	UpperArm = Vector3.new(1, 1.169, 1),
	LowerArm = Vector3.new(1, 1.052, 1),
	LowerLeg = Vector3.new(1, 1.193, 1),
}

type Slot = { Part: BasePart, Frame: CFrame, Size: Vector3 }

-- A body region to dress: the real part, where the region sits on it, and its size.
-- R6 limbs and torsos are split into the R15 regions the pieces were made for.
local function slot(character: Model, r15: string, r6: string?, r6Share: number?, r6Offset: number?): Slot?
	local p = findPart(character, r15)
	if p then
		return { Part = p, Frame = CFrame.new(), Size = p.Size }
	end
	p = r6 and findPart(character, r6)
	if not p then
		return nil
	end
	local share, offset = r6Share or 1, r6Offset or 0
	return { Part = p, Frame = CFrame.new(0, p.Size.Y * offset, 0), Size = Vector3.new(p.Size.X, p.Size.Y * share, p.Size.Z) }
end

local function headSlot(head: BasePart): Slot
	if head:IsA("MeshPart") then
		local y = head.Size.Y
		return { Part = head, Frame = CFrame.new(), Size = Vector3.new(math.clamp(head.Size.X, y * 0.8, y * 1.4), y, math.clamp(head.Size.Z, y * 0.8, y * 1.4)) }
	end
	local h = headHeight(head)
	return { Part = head, Frame = CFrame.new(), Size = Vector3.new(h, h, h) }
end

local function wear(folder: Instance, name: string, where: Slot?, ref: Vector3, color: Color3, material: Enum.Material, flip: boolean?): MeshPart?
	if not where then
		return nil
	end
	local mesh = Assets.Mesh(name, color, material)
	if not mesh then
		return nil
	end
	local origin = where.Part.CFrame * where.Frame
	if flip then
		origin *= CFrame.Angles(0, math.pi, 0) -- pieces are modelled for the right side
	end
	Assets.Place(mesh, origin, where.Size / ref)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = where.Part
	weld.Part1 = mesh
	weld.Parent = mesh
	mesh.Parent = folder
	return mesh
end

-- ---------------------------------------------------------------- full-body suit

-- Default R15 part sizes the suit pieces were modelled around (tools/blender/ninja.py).
local SUIT_REF = {
	Head = Vector3.new(1.2, 1.2, 1.2),
	UpperTorso = Vector3.new(2, 1.6, 1),
	LowerTorso = Vector3.new(2, 0.4, 1),
	UpperArm = Vector3.new(1, 1.169, 1),
	LowerArm = Vector3.new(1, 1.052, 1),
	Hand = Vector3.new(1, 0.3, 1),
	UpperLeg = Vector3.new(1, 1.217, 1),
	LowerLeg = Vector3.new(1, 1.193, 1),
	Foot = Vector3.new(1, 0.3, 1),
}
-- R6 limbs split into the R15 regions: { share of the part's height, centre offset }
local R6_ARM = { UpperArm = { 0.45, 0.275 }, LowerArm = { 0.425, -0.1625 }, Hand = { 0.125, -0.4375 } }
local R6_LEG = { UpperLeg = { 0.475, 0.2625 }, LowerLeg = { 0.425, -0.1875 }, Foot = { 0.1, -0.45 } }
local LEATHER = Color3.fromRGB(80, 52, 36)
local SOLE = Color3.fromRGB(28, 24, 26)

local function limbSlot(character: Model, side: string, region: string): Slot?
	local isLeg = R6_LEG[region] ~= nil
	local r6 = side .. (if isLeg then " Leg" else " Arm")
	local split = if isLeg then R6_LEG[region] else R6_ARM[region]
	return slot(character, side .. region, r6, split[1], split[2])
end

-- Hides the avatar's own body (the suit replaces it); the head stays as the face
-- under the hood unless the suit brings its own (hero suits).
local function hideBody(character: Model, includeHead: boolean?)
	for _, p in ipairs(character:GetChildren()) do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" and (includeHead or p.Name ~= "Head") and p.Transparency < 1 then
			p.Transparency = 1
			p:SetAttribute("NinjaHidden", true)
		end
	end
end

-- Returns false when the suit pack isn't imported.
local function applySuit(character: Model, folder: Folder, head: BasePart, outfit, features): boolean
	if not Assets.Has("NSuitHood__Cloth", "NSuitTorso__Cloth", "NSuitHips__Cloth", "NSuitArm__Cloth", "NSuitThigh__Cloth", "NSuitShin__Cloth") then
		return false
	end
	hideBody(character)
	local glow = features.GlowLines == true
	local cloth = outfit.Material
	local fabric = Enum.Material.Fabric
	local trimMat = if glow then Enum.Material.Neon else fabric
	local metal = outfit.Secondary:Lerp(Color3.new(0.72, 0.74, 0.8), 0.45)
	local mask = outfit.Primary:Lerp(Color3.new(0, 0, 0), 0.4)
	local armour = features.Armor == true

	local hs = headSlot(head)
	wear(folder, "NSuitHood__Cloth", hs, SUIT_REF.Head, outfit.Primary, cloth)
	wear(folder, "NSuitHood__Mask", hs, SUIT_REF.Head, mask, fabric)
	wear(folder, "NSuitHood__Band", hs, SUIT_REF.Head, outfit.Trim, fabric)
	wear(folder, "NSuitHood__Plate", hs, SUIT_REF.Head, metal, if glow then Enum.Material.Neon else Enum.Material.Metal)
	wear(folder, "NSuitHood__Eyes", hs, SUIT_REF.Head, outfit.EyeColor, if outfit.EyeGlow then Enum.Material.Neon else Enum.Material.SmoothPlastic)
	if features.Horns then
		wear(folder, "NSuitHorns__Horn", hs, SUIT_REF.Head, outfit.Trim, Enum.Material.Neon)
	end
	if features.Halo then
		wear(folder, "NSuitHalo__Ring", hs, SUIT_REF.Head, outfit.Trim, Enum.Material.Neon)
	end

	local upper = slot(character, "UpperTorso", "Torso", 0.8, 0.1)
	local lower = slot(character, "LowerTorso", "Torso", 0.2, -0.4)
	wear(folder, "NSuitTorso__Cloth", upper, SUIT_REF.UpperTorso, outfit.Primary, cloth)
	wear(folder, "NSuitTorso__Lapel", upper, SUIT_REF.UpperTorso, outfit.Trim, fabric)
	if armour then
		wear(folder, "NSuitTorso__Plate", upper, SUIT_REF.UpperTorso, metal, Enum.Material.Metal)
		wear(folder, "NSuitTorso__Rim", upper, SUIT_REF.UpperTorso, outfit.Trim, trimMat)
	else
		wear(folder, "NSuitTorso__Strap", upper, SUIT_REF.UpperTorso, LEATHER, Enum.Material.Leather)
		wear(folder, "NSuitTorso__Gear", upper, SUIT_REF.UpperTorso, if features.Emblem then outfit.Trim else metal, if features.Emblem then Enum.Material.Neon else Enum.Material.Metal)
	end
	wear(folder, "NSuitHips__Cloth", lower, SUIT_REF.LowerTorso, outfit.Primary, cloth)
	wear(folder, "NSuitHips__Belt", lower, SUIT_REF.LowerTorso, outfit.Trim, fabric)
	wear(folder, "NSuitHips__Gear", lower, SUIT_REF.LowerTorso, LEATHER, Enum.Material.Leather)
	if features.Scarf then
		wear(folder, "NSuitScarf__Cloth", upper, SUIT_REF.UpperTorso, outfit.Trim, fabric)
	end
	if features.Cape then
		wear(folder, "NSuitCape__Cloth", upper, SUIT_REF.UpperTorso, outfit.Secondary, fabric)
		wear(folder, "NSuitCape__Hem", upper, SUIT_REF.UpperTorso, outfit.Trim, Enum.Material.Neon)
	end

	for _, side in ipairs({ "Right", "Left" }) do
		local flip = side == "Left" -- arm pieces are modelled for the right side
		local letter = if side == "Right" then "R" else "L"
		local upperArm = limbSlot(character, side, "UpperArm")
		local lowerArm = limbSlot(character, side, "LowerArm")
		local hand = limbSlot(character, side, "Hand")
		wear(folder, "NSuitArm__Cloth", upperArm, SUIT_REF.UpperArm, outfit.Primary, cloth, flip)
		wear(folder, "NSuitForearm__Cloth", lowerArm, SUIT_REF.LowerArm, outfit.Primary, cloth, flip)
		wear(folder, "NSuitForearm__Wrap", lowerArm, SUIT_REF.LowerArm, outfit.Secondary, fabric, flip)
		wear(folder, "NSuitHand" .. letter .. "__Glove", hand, SUIT_REF.Hand, outfit.Secondary, fabric)
		wear(folder, "NSuitHand" .. letter .. "__Cuff", hand, SUIT_REF.Hand, outfit.Trim, trimMat)
		local thigh = limbSlot(character, side, "UpperLeg")
		local shin = limbSlot(character, side, "LowerLeg")
		local foot = limbSlot(character, side, "Foot")
		wear(folder, "NSuitThigh__Cloth", thigh, SUIT_REF.UpperLeg, outfit.Primary, cloth)
		if side == "Right" then
			wear(folder, "NSuitHolster__Gear", thigh, SUIT_REF.UpperLeg, LEATHER, Enum.Material.Leather)
		end
		wear(folder, "NSuitShin__Cloth", shin, SUIT_REF.LowerLeg, outfit.Primary, cloth)
		wear(folder, "NSuitShin__Wrap", shin, SUIT_REF.LowerLeg, outfit.Secondary, fabric)
		wear(folder, "NSuitFoot" .. letter .. "__Cloth", foot, SUIT_REF.Foot, outfit.Secondary, fabric)
		wear(folder, "NSuitFoot" .. letter .. "__Sole", foot, SUIT_REF.Foot, SOLE, Enum.Material.SmoothPlastic)
		if armour then
			wear(folder, "NSuitArm__Plate", upperArm, SUIT_REF.UpperArm, metal, Enum.Material.Metal, flip)
			wear(folder, "NSuitArm__Rim", upperArm, SUIT_REF.UpperArm, outfit.Trim, trimMat, flip)
			wear(folder, "NSuitForearm__Plate", lowerArm, SUIT_REF.LowerArm, metal, Enum.Material.Metal, flip)
			wear(folder, "NSuitShin__Plate", shin, SUIT_REF.LowerLeg, metal, Enum.Material.Metal)
		end
	end
	return true
end

-- ---------------------------------------------------------------- hero suits
-- Textured full-body suits modelled from the reference sheets (tools/blender/hero_ninjas.py):
-- one mesh per body part named HeroNinja_<tier id>_<part>, with its own face and hands.
local HERO_PARTS = {
	"Head", "UpperTorso", "LowerTorso",
	"RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightUpperLeg", "RightLowerLeg", "RightFoot", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
}

local function heroSlot(character: Model, head: BasePart, part: string): Slot?
	if part == "Head" then
		return headSlot(head)
	elseif part == "UpperTorso" then
		return slot(character, "UpperTorso", "Torso", 0.8, 0.1)
	elseif part == "LowerTorso" then
		return slot(character, "LowerTorso", "Torso", 0.2, -0.4)
	end
	local side = if string.sub(part, 1, 5) == "Right" then "Right" else "Left"
	return limbSlot(character, side, string.sub(part, #side + 1))
end

local function heroRef(part: string): Vector3
	local region = string.gsub(part, "^Right", "")
	region = string.gsub(region, "^Left", "")
	return SUIT_REF[region]
end

local function placeOn(folder: Instance, mesh: MeshPart, where: Slot, ref: Vector3)
	Assets.Place(mesh, where.Part.CFrame * where.Frame, where.Size / ref)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = where.Part
	weld.Part1 = mesh
	weld.Parent = mesh
	mesh.Parent = folder
end

-- Returns false unless every piece of this tier's hero suit was imported.
local function applyHero(character: Model, folder: Folder, head: BasePart, tier): boolean
	local prefix = "HeroNinja_" .. tostring(tier.Id) .. "_"
	for _, part in ipairs(HERO_PARTS) do
		if not Assets.Has(prefix .. part) then
			return false
		end
	end
	hideBody(character, true)
	for _, part in ipairs(HERO_PARTS) do
		local where = heroSlot(character, head, part)
		if where then
			local ref = heroRef(part)
			local mesh = Assets.Textured(prefix .. part, tier.Outfit.Primary)
			if mesh then
				placeOn(folder, mesh, where, ref)
			end
			-- gem eyes, buckle gems: neon in the eye colour for glowing-eye tiers, else the tier colour
			local glowColor = if tier.Outfit.EyeGlow and tier.Outfit.EyeColor then tier.Outfit.EyeColor else tier.Color
			local glow = Assets.Mesh(prefix .. part .. "__Glow", glowColor, Enum.Material.Neon)
			if glow then
				placeOn(folder, glow, where, ref)
			end
		end
	end
	return true
end

-- Returns false when the outfit pack isn't imported (the part outfit is used then).
local function applyMeshes(character: Model, folder: Folder, head: BasePart, outfit, features): boolean
	if not Assets.Has("NinjaHood__Cloth", "NinjaHood__Mask", "NinjaHood__Band", "NinjaGi__Lapel", "NinjaBelt__Obi") then
		return false
	end
	local glow = features.GlowLines == true
	local trimMat = if glow then Enum.Material.Neon else Enum.Material.Fabric
	local metal = outfit.Secondary:Lerp(Color3.new(0.72, 0.74, 0.8), 0.45)
	local black = Color3.new(0, 0, 0)

	local hs = headSlot(head)
	wear(folder, "NinjaHood__Cloth", hs, REF.Head, outfit.Primary, outfit.Material)
	wear(folder, "NinjaHood__Mask", hs, REF.Head, outfit.Primary:Lerp(black, 0.4), Enum.Material.Fabric)
	wear(folder, "NinjaHood__Band", hs, REF.Head, outfit.Trim, Enum.Material.Fabric)
	wear(folder, "NinjaHood__Plate", hs, REF.Head, metal, if glow then Enum.Material.Neon else Enum.Material.Metal)
	wear(folder, "NinjaHood__Eyes", hs, REF.Head, outfit.EyeColor, if outfit.EyeGlow then Enum.Material.Neon else Enum.Material.SmoothPlastic)
	if features.Horns then
		wear(folder, "NinjaHorns__Horn", hs, REF.Head, outfit.Trim, Enum.Material.Neon)
	end
	if features.Halo then
		wear(folder, "NinjaHalo__Ring", hs, REF.Head, outfit.Trim, Enum.Material.Neon)
	end

	local upper = slot(character, "UpperTorso", "Torso", 0.8, 0.1)
	local lower = slot(character, "LowerTorso", "Torso", 0.2, -0.4)
	wear(folder, "NinjaGi__Lapel", upper, REF.UpperTorso, outfit.Trim, Enum.Material.Fabric)
	wear(folder, "NinjaBelt__Obi", lower, REF.LowerTorso, outfit.Trim, Enum.Material.Fabric)
	if features.Scarf then
		wear(folder, "NinjaScarf__Cloth", upper, REF.UpperTorso, outfit.Trim, Enum.Material.Fabric)
	end
	if features.Cape then
		wear(folder, "NinjaCape__Cloth", upper, REF.UpperTorso, outfit.Secondary, Enum.Material.Fabric)
		wear(folder, "NinjaCape__Hem", upper, REF.UpperTorso, outfit.Trim, Enum.Material.Neon)
	end

	for _, side in ipairs({ "Right", "Left" }) do
		local flip = side == "Left"
		local lowerArm = slot(character, side .. "LowerArm", side .. " Arm", 0.5, -0.2)
		wear(folder, "NinjaBracer__Wrap", lowerArm, REF.LowerArm, outfit.Secondary, Enum.Material.Fabric, flip)
		wear(folder, "NinjaBracer__Strap", lowerArm, REF.LowerArm, outfit.Trim, trimMat, flip)
		local shin = slot(character, side .. "LowerLeg", side .. " Leg", 0.5, -0.25)
		wear(folder, "NinjaShin__Wrap", shin, REF.LowerLeg, outfit.Secondary, Enum.Material.Fabric)
		wear(folder, "NinjaShin__Strap", shin, REF.LowerLeg, outfit.Trim, trimMat)
		if features.Armor then
			wear(folder, "NinjaBracer__Plate", lowerArm, REF.LowerArm, metal, Enum.Material.Metal, flip)
			wear(folder, "NinjaShin__Plate", shin, REF.LowerLeg, metal, Enum.Material.Metal)
			local upperArm = slot(character, side .. "UpperArm", side .. " Arm", 0.5, 0.25)
			wear(folder, "NinjaShoulder__Plate", upperArm, REF.UpperArm, outfit.Secondary:Lerp(metal, 0.3), Enum.Material.Metal, flip)
			wear(folder, "NinjaShoulder__Rim", upperArm, REF.UpperArm, outfit.Trim, trimMat, flip)
		end
	end

	if features.Emblem and upper then
		-- small glowing crest on the chest, clear of the lapels
		local size = upper.Size
		local emblem = makePart(folder, "Emblem", Vector3.new(0.3, 0.3, 0.06), outfit.Trim, Enum.Material.Neon)
		attach(emblem, upper.Part, upper.Frame * CFrame.new(-size.X * 0.3, size.Y * 0.2, -size.Z / 2 - 0.05) * CFrame.Angles(0, 0, math.rad(45)))
	end
	return true
end

function OutfitBuilder.Clear(character: Model)
	local existing = character:FindFirstChild(OUTFIT_NAME)
	if existing then
		existing:Destroy()
	end
	-- bring back body parts the full-body suit hid
	for _, p in ipairs(character:GetChildren()) do
		if p:IsA("BasePart") and p:GetAttribute("NinjaHidden") then
			p.Transparency = 0
			p:SetAttribute("NinjaHidden", nil)
		end
	end
end

-- Removes aura/light added to the root by a previous Apply.
function OutfitBuilder.ClearRootEffects(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		for _, child in ipairs(root:GetChildren()) do
			if child:GetAttribute("NinjaOutfit") then
				child:Destroy()
			end
		end
	end
end

-- Aura particles + tier light on the root, then parent the outfit.
local function finishOutfit(character: Model, folder: Folder, root: BasePart, outfit, tier)
	if outfit.Aura then
		local aura = Particles.Create(outfit.Aura, root, { Rate = (Particles.Presets[outfit.Aura].Rate or 10) * 0.8 })
		if aura then
			aura.Name = "TierAura"
			aura:SetAttribute("NinjaOutfit", true)
		end
	end
	if tier.Index >= 6 then
		local light = Instance.new("PointLight")
		light.Name = "TierLight"
		light.Color = outfit.Trim
		light.Range = 6 + tier.Index * 0.5
		light.Brightness = 0.6 + tier.Index * 0.08
		light.Shadows = false
		light:SetAttribute("NinjaOutfit", true)
		light.Parent = root
	end

	folder.Parent = character
	character:SetAttribute("NinjaTier", tier.Index)
end

function OutfitBuilder.Apply(character: Model, tier)
	OutfitBuilder.Clear(character)
	OutfitBuilder.ClearRootEffects(character)
	local outfit = tier.Outfit
	local features = outfit.Features or {}
	local folder = Instance.new("Folder")
	folder.Name = OUTFIT_NAME

	-- Strip default clothing / accessories so the ninja silhouette reads clearly.
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") or child:IsA("Shirt") or child:IsA("Pants") or child:IsA("ShirtGraphic") or child:IsA("BodyColors") then
			child:Destroy()
		end
	end

	local head = findPart(character, "Head")
	local upperTorso = findPart(character, "UpperTorso", "Torso")
	local lowerTorso = findPart(character, "LowerTorso", "Torso")
	local root = findPart(character, "HumanoidRootPart")
	if not (head and upperTorso and lowerTorso and root) then
		return
	end
	local isR15 = character:FindFirstChild("UpperTorso") ~= nil

	-- Body colours
	local secondaryParts = {
		LeftHand = true, RightHand = true, LeftFoot = true, RightFoot = true,
		LeftLowerLeg = true, RightLowerLeg = true, ["Left Leg"] = true, ["Right Leg"] = true,
	}
	for _, p in ipairs(character:GetChildren()) do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" and p.Name ~= "Head" then
			p.Color = if secondaryParts[p.Name] then outfit.Secondary else outfit.Primary
			p.Material = outfit.Material
		end
	end
	local face = head:FindFirstChildOfClass("Decal")
	if face then
		face.Transparency = 1
	end

	if applyHero(character, folder, head, tier) or applySuit(character, folder, head, outfit, features) or applyMeshes(character, folder, head, outfit, features) then
		finishOutfit(character, folder, root, outfit, tier)
		return
	end

	local h = headHeight(head)
	local d = h * 1.18
	local r = d / 2
	local eyeMaterial = if outfit.EyeGlow then Enum.Material.Neon else Enum.Material.SmoothPlastic

	-- Hood
	local hood = makePart(folder, "Hood", Vector3.new(d, d, d), outfit.Primary, outfit.Material, Enum.PartType.Ball)
	attach(hood, head, CFrame.new(0, h * 0.04, 0.02))

	-- Curved eye plate + eyes on the front of the hood
	local skin = head.Color
	local plateY = h * 0.04
	local rr = math.sqrt(r * r - plateY * plateY)
	for _, angle in ipairs({ -32, 0, 32 }) do
		local a = math.rad(angle)
		local pos = Vector3.new(math.sin(a) * rr * 0.96, plateY, -math.cos(a) * rr * 0.96)
		local outward = Vector3.new(pos.X, 0, pos.Z).Unit
		local plate = makePart(folder, "EyePlate", Vector3.new(d * 0.3, h * 0.24, 0.08), skin, Enum.Material.SmoothPlastic)
		attach(plate, hood, CFrame.lookAt(pos, pos + outward))
	end
	for side = -1, 1, 2 do
		local a = math.rad(side * 14)
		local pos = Vector3.new(math.sin(a) * rr, plateY + h * 0.01, -math.cos(a) * rr - 0.03)
		local eye = makePart(folder, "Eye", Vector3.new(h * 0.12, h * 0.1, 0.06), outfit.EyeColor, eyeMaterial)
		attach(eye, hood, CFrame.lookAt(pos, pos + Vector3.new(pos.X, 0, pos.Z).Unit) * CFrame.Angles(0, 0, math.rad(side * -12)))
	end

	-- Headband with trailing tails
	local band = makePart(folder, "Headband", Vector3.new(h * 0.14, d * 1.03, d * 1.03), outfit.Trim, Enum.Material.Fabric, Enum.PartType.Cylinder)
	attach(band, hood, CFrame.new(0, h * 0.24, 0) * CFrame.Angles(0, 0, math.pi / 2))
	local plateMat = if features.GlowLines then Enum.Material.Neon else Enum.Material.Metal
	local bandPlate = makePart(folder, "BandPlate", Vector3.new(h * 0.36, h * 0.16, 0.06), outfit.Secondary:Lerp(Color3.new(0.7, 0.7, 0.75), 0.5), plateMat)
	attach(bandPlate, hood, CFrame.new(0, h * 0.24, -r * 0.93))
	for side = -1, 1, 2 do
		local tail = makePart(folder, "BandTail", Vector3.new(h * 0.1, 0.05, h * 0.75), outfit.Trim, Enum.Material.Fabric)
		attach(tail, hood, CFrame.new(side * h * 0.1, h * 0.12, r + h * 0.3) * CFrame.Angles(math.rad(35), side * math.rad(12), 0))
	end

	-- Sash / belt
	local sashY = if isR15 then lowerTorso.Size.Y * 0.35 else -upperTorso.Size.Y * 0.35
	local sash = makePart(folder, "Sash", Vector3.new(lowerTorso.Size.X * 1.05, 0.32, lowerTorso.Size.Z * 1.12), outfit.Trim, Enum.Material.Fabric)
	attach(sash, lowerTorso, CFrame.new(0, sashY, 0))
	local knot = makePart(folder, "SashKnot", Vector3.new(0.3, 0.3, 0.2), outfit.Trim, Enum.Material.Fabric)
	attach(knot, lowerTorso, CFrame.new(lowerTorso.Size.X * 0.32, sashY, -lowerTorso.Size.Z * 0.58) * CFrame.Angles(0, 0, math.rad(45)))
	for i = -1, 1, 2 do
		local ribbon = makePart(folder, "SashRibbon", Vector3.new(0.14, 0.6, 0.05), outfit.Trim, Enum.Material.Fabric)
		attach(ribbon, lowerTorso, CFrame.new(lowerTorso.Size.X * 0.32 + i * 0.08, sashY - 0.35, -lowerTorso.Size.Z * 0.6) * CFrame.Angles(0, 0, math.rad(i * 12)))
	end

	-- Chest wrap: diagonal cross strap (every tier) gives the gi a clear shape
	local tSize = upperTorso.Size
	local strap = makePart(folder, "Strap", Vector3.new(0.2, tSize.Y * 1.05, 0.05), outfit.Secondary, Enum.Material.Fabric)
	attach(strap, upperTorso, CFrame.new(0, 0, -tSize.Z / 2 - 0.02) * CFrame.Angles(0, 0, math.rad(30)))

	if features.Emblem then
		local emblem = makePart(folder, "Emblem", Vector3.new(0.34, 0.34, 0.06), outfit.Trim, Enum.Material.Neon)
		attach(emblem, upperTorso, CFrame.new(-tSize.X * 0.22, tSize.Y * 0.18, -tSize.Z / 2 - 0.05) * CFrame.Angles(0, 0, math.rad(45)))
	end

	if features.GlowLines then
		for side = -1, 1, 2 do
			local seam = makePart(folder, "GlowSeam", Vector3.new(0.07, tSize.Y * 0.9, 0.04), outfit.Trim, Enum.Material.Neon)
			attach(seam, upperTorso, CFrame.new(side * tSize.X * 0.38, 0, -tSize.Z / 2 - 0.03))
		end
		for _, name in ipairs({ "LeftLowerArm", "RightLowerArm", "Left Arm", "Right Arm" }) do
			local arm = findPart(character, name)
			if arm then
				local cuff = makePart(folder, "GlowCuff", Vector3.new(arm.Size.X * 1.08, 0.12, arm.Size.Z * 1.08), outfit.Trim, Enum.Material.Neon)
				attach(cuff, arm, CFrame.new(0, -arm.Size.Y * 0.3, 0))
			end
		end
	end

	if features.Scarf then
		local neck = makePart(folder, "ScarfRing", Vector3.new(0.34, tSize.X * 0.62, tSize.X * 0.62), outfit.Trim, Enum.Material.Fabric, Enum.PartType.Cylinder)
		attach(neck, upperTorso, CFrame.new(0, tSize.Y / 2 + 0.05, 0) * CFrame.Angles(0, 0, math.pi / 2))
		local tail1 = makePart(folder, "ScarfTail", Vector3.new(0.34, 0.08, 1.1), outfit.Trim, Enum.Material.Fabric)
		attach(tail1, upperTorso, CFrame.new(tSize.X * 0.2, tSize.Y * 0.35, tSize.Z / 2 + 0.5) * CFrame.Angles(math.rad(-25), math.rad(15), 0))
		local tail2 = makePart(folder, "ScarfTail", Vector3.new(0.3, 0.08, 0.9), outfit.Trim, Enum.Material.Fabric)
		attach(tail2, upperTorso, CFrame.new(tSize.X * 0.34, tSize.Y * 0.05, tSize.Z / 2 + 1.1) * CFrame.Angles(math.rad(-50), math.rad(25), 0))
	end

	if features.Armor then
		for side = -1, 1, 2 do
			local arm = if side < 0 then findPart(character, "LeftUpperArm", "Left Arm") else findPart(character, "RightUpperArm", "Right Arm")
			if arm then
				local plate = makePart(folder, "ShoulderPlate", Vector3.new(arm.Size.X * 1.6, 0.22, arm.Size.Z * 1.5), outfit.Secondary, Enum.Material.Metal)
				attach(plate, arm, CFrame.new(side * 0.1, arm.Size.Y * 0.45, 0) * CFrame.Angles(0, 0, math.rad(side * 18)))
				local rim = makePart(folder, "ShoulderRim", Vector3.new(arm.Size.X * 1.62, 0.07, arm.Size.Z * 1.52), outfit.Trim, if features.GlowLines then Enum.Material.Neon else Enum.Material.Metal)
				attach(rim, plate, CFrame.new(0, -0.12, 0))
			end
		end
	end

	if features.Cape then
		local capeHeight = if isR15 then tSize.Y + lowerTorso.Size.Y + 1.6 else tSize.Y * 1.6
		local cape = makePart(folder, "Cape", Vector3.new(tSize.X * 0.9, capeHeight, 0.08), outfit.Secondary, Enum.Material.Fabric)
		attach(cape, upperTorso, CFrame.new(0, tSize.Y / 2 - capeHeight / 2, tSize.Z / 2 + 0.18) * CFrame.Angles(math.rad(8), 0, 0))
		local hem = makePart(folder, "CapeHem", Vector3.new(tSize.X * 0.92, 0.14, 0.1), outfit.Trim, Enum.Material.Neon)
		attach(hem, cape, CFrame.new(0, -capeHeight / 2 + 0.07, 0))
	end

	if features.Horns then
		for side = -1, 1, 2 do
			local horn = Instance.new("WedgePart")
			horn.Name = "Horn"
			horn.Size = Vector3.new(0.12, h * 0.55, h * 0.3)
			horn.Color = outfit.Trim
			horn.Material = Enum.Material.Neon
			horn.CanCollide = false
			horn.CanQuery = false
			horn.CanTouch = false
			horn.Massless = true
			horn.Parent = folder
			attach(horn, hood, CFrame.new(side * r * 0.55, r * 0.85, 0.05) * CFrame.Angles(0, math.pi / 2, math.rad(side * -20)))
		end
	end

	if features.Halo then
		for i = 0, 13 do
			local a = i * math.pi * 2 / 14
			local seg = makePart(folder, "Halo", Vector3.new(0.26, 0.06, 0.1), outfit.Trim, Enum.Material.Neon)
			attach(seg, hood, CFrame.new(math.cos(a) * r * 0.9, r + 0.45, math.sin(a) * r * 0.9) * CFrame.Angles(0, -a + math.pi / 2, 0))
		end
	end

	finishOutfit(character, folder, root, outfit, tier)
end

return OutfitBuilder
