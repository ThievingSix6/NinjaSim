--!nocheck
-- Pet preview scenario: builds pets with every mutation (Config/Mutations) through the
-- real PetBuilder and dumps their parts, particles, beams and lights to
-- $PETSHOTS_DIR/pets.json (default /tmp/claude-0/petshots) for
-- tools/blender/pet_previews.py, which renders them. Also dumps the Pets menu,
-- the Egg menu and a mutated hatch reveal for tools/uipreview.
--   SCENARIO=petshots lune run run.luau
local task = require("@lune/task")
local serde = require("@lune/serde")
local fs = require("@lune/fs")
local process = require("@lune/process")
local dump = require("./uidump")

local PETS = { "fox", "jade_dragon", "koi", "baby_ninja", "phoenix", "panda_cub" }

return function(E)
	local roblox = E.roblox
	local CFrame = roblox.CFrame
	local player = E.player
	local out = process.env.PETSHOTS_DIR or "/tmp/claude-0/petshots"
	pcall(fs.writeDir, out)
	task.wait(2)
	local C = function(path)
		return E.C["ReplicatedStorage.Shared." .. path]
	end
	local PetBuilder = C("Visuals.PetBuilder")
	local Pets = C("Config.Pets")
	local Mutations = C("Config.Mutations")

	local function v3(v)
		return { v.X, v.Y, v.Z }
	end
	local function col(c)
		return { c.R, c.G, c.B }
	end
	local function enumName(e)
		return (string.gsub(tostring(e), "^Enum%.%w+%.", ""))
	end
	-- Model:ScaleTo only records the scale in the emulator, so apply it here about the pivot.
	local function serialize(model)
		local scale = model:GetScale()
		local pivot = model:GetPivot()
		local function place(cf)
			local rel = pivot:ToObjectSpace(cf)
			return CFrame.new(rel.Position * scale) * rel.Rotation
		end
		local parts, fx = {}, {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				local cf = place(d.CFrame)
				table.insert(parts, {
					-- a Sphere SpecialMesh makes the part an ellipsoid filling its size (PetBuilder)
					name = d.Name, class = d.ClassName,
					shape = if d:FindFirstChildOfClass("SpecialMesh") and d:FindFirstChildOfClass("SpecialMesh").MeshType == roblox.Enum.MeshType.Sphere then "Ellipsoid"
						elseif d.ClassName == "Part" then enumName(d.Shape) else nil,
					size = v3(d.Size * scale), cf = { cf:GetComponents() }, color = col(d.Color),
					material = enumName(d.Material), transparency = d.Transparency, reflectance = d.Reflectance,
				})
			elseif d:IsA("ParticleEmitter") then
				local kps = d.Color.Keypoints
				local size = 0
				for _, k in ipairs(d.Size.Keypoints) do
					size = math.max(size, k.Value)
				end
				table.insert(fx, { kind = "particles", name = d.Name, at = v3(place(d.Parent.CFrame).Position), colors = { col(kps[1].Value), col(kps[#kps].Value) }, rate = d.Rate, size = size * scale, emission = d.LightEmission })
			elseif d:IsA("Beam") and d.Attachment0 and d.Attachment1 then
				local a = place(d.Attachment0.Parent.CFrame * CFrame.new(d.Attachment0.Position * 1)).Position
				local b = place(d.Attachment1.Parent.CFrame * CFrame.new(d.Attachment1.Position * 1)).Position
				table.insert(fx, { kind = "beam", a = v3(a), b = v3(b), color = col(d.Color.Keypoints[1].Value), width = d.Width0 * scale })
			elseif d:IsA("PointLight") then
				table.insert(fx, { kind = "light", at = v3(place(d.Parent.CFrame).Position), color = col(d.Color), range = d.Range * scale, brightness = d.Brightness })
			end
		end
		return { scale = scale, parts = parts, fx = fx }
	end

	local models = {}
	for _, petId in ipairs(PETS) do
		local list = { { mutation = "", model = serialize(PetBuilder.Build(Pets.ById[petId], 1)) } }
		for _, m in ipairs(Mutations.List) do
			table.insert(list, { mutation = m.Id, model = serialize(PetBuilder.Build(Pets.ById[petId], 1, m.Id)) })
		end
		models[petId] = list
	end
	-- plain models of every other pet (the UI shots and the --gallery sheet)
	for _, pet in ipairs(Pets.List) do
		if not models[pet.Id] then
			models[pet.Id] = { { mutation = "", model = serialize(PetBuilder.Build(pet, 1)) } }
		end
	end
	local mutations = {}
	for _, m in ipairs(Mutations.List) do
		table.insert(mutations, { id = m.Id, name = m.Name, mult = m.Mult, oneIn = m.OneIn, color = col(m.Color) })
	end
	local order = {}
	for _, pet in ipairs(Pets.List) do
		table.insert(order, pet.Id)
	end
	fs.writeFile(out .. "/pets.json", serde.encode("json", { pets = PETS, order = order, mutations = mutations, models = models }))
	print("[petshots] wrote " .. out .. "/pets.json")

	-- UI: a save with one pet of each mutation, the Pets menu, the Egg menu and a hatch reveal
	local PS = E.sm("PetService")
	local data = E.sm("DataService"):Get(player)
	for i, m in ipairs(Mutations.List) do
		PS:Grant(player, PETS[(i - 1) % #PETS + 1], m.Id)
	end
	PS:Grant(player, "fox")
	PS:Grant(player, "koi")
	data.Utility.pet_slot = 3
	E.sm("StatService"):Refresh(player)
	E.cm("Controllers.DataController"):Request("EquipBestPets")
	task.wait(16) -- daily reward popup and toasts clear
	local toasts = player.PlayerGui:FindFirstChild("NinjaToasts")
	if toasts then
		toasts.Enabled = false
	end
	local function shot(name)
		task.wait(0.6)
		fs.writeFile(out .. "/" .. name .. ".json", serde.encode("json", { name = name, w = 1280, h = 720, guis = dump(E, player.PlayerGui) }))
		print("[petshots] " .. name)
	end
	local MM = E.cm("UI.MenuManager")
	MM:Open("Pets")
	shot("ui_pets")
	-- the detail panel for the Celestial pet: click its card
	local window = E.cm("Controllers.UIController"):Root("Menus"):FindFirstChild("Pets")
	for _, d in ipairs(window:GetDescendants()) do
		if d.Name == "MutationTag" and d.Text == "CELESTIAL" then
			E.signalFor(d.Parent, "Activated"):Fire()
		end
	end
	shot("ui_pets_celestial")
	MM:Open("Egg", "village_egg")
	shot("ui_egg")
	MM:Close()
	-- hatch reveal: three pets, two of them mutated (Rainbow and Golden)
	local Net = E.shared("Net")
	Net.Event("EggHatched"):FireClient(player, { Egg = "bamboo_egg", Pets = {
		{ Uid = "900", Id = "panda_cub", Mutation = "Golden" },
		{ Uid = "901", Id = "jade_dragon", Mutation = "Rainbow" },
		{ Uid = "902", Id = "kitsune" },
	} })
	task.wait(4.6)
	shot("ui_hatch")
end
