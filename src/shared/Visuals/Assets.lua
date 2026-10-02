--[[
	Assets: optional Blender-made meshes (tools/blender). When the imported asset
	packs are present under ReplicatedStorage.NinjaAssets, builders use them;
	otherwise they fall back to the part-built models, so the game always works.

	Import 3D drops the model into Workspace, so the server also looks there (and in
	ReplicatedStorage and ServerStorage) for anything holding our mesh names and
	moves it into ReplicatedStorage.NinjaAssets itself; nobody has to make the folder.

	Each pack ships a manifest (Visuals/Manifests) with every mesh's bounding box
	in the pack's shared frame, so pieces can be placed and scaled exactly.
	Colours and materials are always set in code, so one mesh serves every tier.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Assets = {}

local Manifests = script.Parent:WaitForChild("Manifests")
Assets.Manifest = {}
for _, module in ipairs(Manifests:GetChildren()) do
	if module:IsA("ModuleScript") then
		for name, info in pairs(require(module) :: any) do
			Assets.Manifest[name] = info
		end
	end
end

local index: { [string]: MeshPart }? = nil

-- An imported pack is any model or folder with a few of our mesh names inside.
local function looksLikePack(container: Instance): boolean
	local hits = 0
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("MeshPart") and Assets.Manifest[d.Name] then
			hits += 1
			if hits >= 3 then
				return true
			end
		end
	end
	return false
end

-- Server only: gathers imported packs wherever Studio put them into
-- ReplicatedStorage.NinjaAssets, and always leaves that folder behind so clients
-- know the server has looked. Runs when this module is first required, before any
-- builder has cloned a mesh into the world.
-- The same packs uploaded to Roblox as Model assets (owned by the place's creator),
-- so a published place gets the meshes without a Studio import.
local UPLOADED_PACKS = {
	133633399850349, -- Props
	77555472980068, -- Ninja
	136585053455646, -- Katanas
	70723840289843, -- UIIcons
	100262888258071, -- Enemies
	105221494430646, -- HeroKatanas
	90776977117209, -- HeroDemons
	121682745294017, -- HeroNinjas
}

local function adopt()
	local folder = ReplicatedStorage:FindFirstChild("NinjaAssets") or Instance.new("Folder")
	folder.Name = "NinjaAssets"
	local places: { Instance } = { workspace, ReplicatedStorage }
	if not looksLikePack(folder) and not looksLikePack(workspace) and not looksLikePack(ReplicatedStorage) then
		local okInsert, InsertService = pcall(function()
			return game:GetService("InsertService")
		end)
		for _, id in ipairs(UPLOADED_PACKS) do
			local okLoad, model = pcall(function()
				return InsertService:LoadAsset(id)
			end)
			if okInsert and okLoad and model then
				model.Name = "UploadedPack_" .. id
				model.Parent = folder
			else
				warn(string.format("[NinjaSim] Could not load uploaded mesh pack %d: %s", id, tostring(model)))
			end
		end
	end
	local ok, serverStorage = pcall(function()
		return game:GetService("ServerStorage")
	end)
	if ok and serverStorage then
		table.insert(places, serverStorage)
	end
	for _, place in ipairs(places) do
		for _, child in ipairs(place:GetChildren()) do
			if child ~= folder and (child:IsA("Model") or child:IsA("Folder")) and looksLikePack(child) then
				print(string.format("[NinjaSim] Found imported model %s in %s; moving it into ReplicatedStorage.NinjaAssets", child.Name, place.Name))
				child.Parent = folder
			end
		end
	end
	folder.Parent = ReplicatedStorage
end

if RunService:IsServer() then
	local ok, err = pcall(adopt)
	if not ok then
		warn("[NinjaSim] Could not gather imported meshes: " .. tostring(err))
	end
end

local function build(): { [string]: MeshPart }
	if index then
		return index
	end
	local found = {}
	local root = ReplicatedStorage:FindFirstChild("NinjaAssets")
	if not root and RunService:IsClient() then
		-- the server makes the folder at startup; until it replicates, use parts and look again later
		return found
	end
	if root then
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("MeshPart") and not found[d.Name] then
				found[d.Name] = d
			end
		end
	end
	index = found
	local count, warned = 0, 0
	for name, mesh in pairs(found) do
		count += 1
		local info = Assets.Manifest[name]
		if info and warned < 5 then
			-- the importer keeps proportions, so a mismatch means the axes got swapped
			local r = mesh.Size / info.Size
			local lo, hi = math.min(r.X, r.Y, r.Z), math.max(r.X, r.Y, r.Z)
			if lo > 0 and hi / lo > 1.3 then
				warned += 1
				warn(string.format("[NinjaSim] Imported mesh %s looks rotated or stretched (size %s, expected proportions of %s)", name, tostring(mesh.Size), tostring(info.Size)))
			end
		end
	end
	if count > 0 then
		print(string.format("[NinjaSim] Using %d imported meshes from ReplicatedStorage.NinjaAssets", count))
	elseif RunService:IsServer() then
		print("[NinjaSim] No imported meshes found (Import 3D NinjaSim_AllAssets.fbx to use them); using part-built models")
	end
	return found
end

-- True when the named mesh (or every named mesh) was imported.
function Assets.Has(...: string): boolean
	local found = build()
	for _, name in ipairs({ ... }) do
		if not found[name] then
			return false
		end
	end
	return true
end

-- The UI icon atlas image. Importing the asset pack uploads the texture of its
-- UIIconAtlas mesh, so that mesh's TextureID (or SurfaceAppearance colour map)
-- is an image the UI can crop icons from (rects in Visuals/IconAtlas). An
-- IconAtlas attribute or StringValue on ReplicatedStorage.NinjaAssets overrides it.
local iconImage: string? = nil
local iconChecked = false
function Assets.IconImage(): string?
	if iconChecked then
		return iconImage
	end
	local root = ReplicatedStorage:FindFirstChild("NinjaAssets")
	if not root then
		return nil -- not replicated yet; look again next time
	end
	iconChecked = true
	local override = root:GetAttribute("IconAtlas")
	local value = root:FindFirstChild("IconAtlas")
	if typeof(override) == "string" and override ~= "" then
		iconImage = override
	elseif value and value:IsA("StringValue") and value.Value ~= "" then
		iconImage = value.Value
	else
		local mesh = build().UIIconAtlas
		if mesh then
			local ok, texture = pcall(function()
				return mesh.TextureID
			end)
			if ok and type(texture) == "string" and texture ~= "" then
				iconImage = texture
			else
				local surface = mesh:FindFirstChildWhichIsA("SurfaceAppearance")
				if surface then
					local okMap, map = pcall(function()
						return (surface :: any).ColorMap
					end)
					if okMap and type(map) == "string" and map ~= "" then
						iconImage = map
					end
				end
			end
		end
	end
	if RunService:IsClient() then
		if iconImage then
			print("[NinjaSim] UI icons loaded from " .. iconImage)
		else
			print("[NinjaSim] UI icon atlas not found; menus use emoji icons until NinjaSim_AllAssets.fbx is imported")
		end
	end
	return iconImage
end

-- A fresh copy of an imported mesh, cleaned up for use as a decorative part.
-- `frame` is the pack-space CFrame the manifest centre is relative to.
function Assets.Mesh(name: string, color: Color3?, material: Enum.Material?): MeshPart?
	local source = build()[name]
	if not source then
		return nil
	end
	local mesh = source:Clone()
	for _, child in ipairs(mesh:GetChildren()) do
		-- importer extras (textures, attachments) would fight the code-driven colours
		if child:IsA("SurfaceAppearance") or child:IsA("Decal") or child:IsA("Texture") or child:IsA("Attachment") or child:IsA("Bone") then
			child:Destroy()
		end
	end
	pcall(function()
		mesh.TextureID = ""
	end)
	mesh.Anchored = false
	mesh.CanCollide = false
	mesh.CanQuery = false
	mesh.CanTouch = false
	mesh.Massless = true
	mesh.CastShadow = false
	if color then
		mesh.Color = color
	end
	mesh.Material = material or Enum.Material.SmoothPlastic
	return mesh
end

-- A fresh copy of a textured "hero" mesh (tools/blender/hero_*.py) that keeps the
-- texture the importer uploaded (TextureID or a SurfaceAppearance). If Studio
-- imported it without its texture, it falls back to a flat `fallback` colour.
function Assets.Textured(name: string, fallback: Color3?): MeshPart?
	local source = build()[name]
	if not source then
		return nil
	end
	local mesh = source:Clone()
	for _, child in ipairs(mesh:GetChildren()) do
		if child:IsA("Attachment") or child:IsA("Bone") then
			child:Destroy()
		end
	end
	local textured = mesh:FindFirstChildWhichIsA("SurfaceAppearance") ~= nil
	if not textured then
		local ok, texture = pcall(function()
			return mesh.TextureID
		end)
		textured = ok and type(texture) == "string" and texture ~= ""
	end
	mesh.Anchored = false
	mesh.CanCollide = false
	mesh.CanQuery = false
	mesh.CanTouch = false
	mesh.Massless = true
	mesh.CastShadow = true
	mesh.Material = Enum.Material.SmoothPlastic
	mesh.Color = if textured then Color3.new(1, 1, 1) else (fallback or mesh.Color)
	return mesh
end

-- Places a mesh the way the manifest describes it, relative to `origin`,
-- optionally scaled per axis around `pivot` (pack space).
-- Studio's Import 3D turns the Blender packs half a turn about Y (their front,
-- which the manifests and every builder treat as -Z, arrives facing +Z: faces on
-- the back of the head, katanas held by the blade). Placement turns it back. A
-- pack imported some other way can set the attribute NoImportTurn = true on
-- ReplicatedStorage.NinjaAssets.
local IMPORT_TURN = CFrame.Angles(0, math.pi, 0)
local turn: CFrame? = nil
local function importTurn(): CFrame
	if turn then
		return turn
	end
	local root = ReplicatedStorage:FindFirstChild("NinjaAssets")
	local t = if root and root:GetAttribute("NoImportTurn") == true then CFrame.identity else IMPORT_TURN
	turn = t
	return t
end

function Assets.Place(mesh: MeshPart, origin: CFrame, scale: Vector3?, pivot: Vector3?)
	local info = Assets.Manifest[mesh.Name]
	if not info then
		mesh.CFrame = origin * importTurn()
		return
	end
	local s = scale or Vector3.one
	local p = pivot or Vector3.zero
	mesh.Size = info.Size * s
	mesh.CFrame = origin * CFrame.new(p + (info.Center - p) * s) * importTurn()
end

return Assets
