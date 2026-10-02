--[[
	PetController: renders every player's equipped companions on the client.
	The server only publishes a player attribute "EquippedPets" (comma-separated
	pet ids, "id:Mutation" for mutated pets), so pets cost zero server physics or
	network per frame. Mutated pets are bigger or animated (MutationLook).

	Pets follow in an arc behind their owner, bob and flap, face where the owner
	is heading, and are moved in one workspace:BulkMoveTo call per frame.
	Also renders the floating orbit orbs for high ninja tiers.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Pets = require(Shared.Config.Pets)
local Tiers = require(Shared.Config.Tiers)
local PetBuilder = require(Shared.Visuals.PetBuilder)
local MutationLook = require(Shared.Visuals.MutationLook)

local PetController = {}

local controllers
local folder: Folder
local localPlayer = Players.LocalPlayer
local showOthers = true
local lowGraphics = false

type PetEntry = {
	Model: Model,
	Parts: { BasePart },
	Offsets: { CFrame },
	Flaps: { number },
	Flying: boolean,
	Current: CFrame,
	Scale: number,
	Animate: ((number) -> ())?,
}
type Owner = {
	Pets: { PetEntry },
	Ids: string,
	Orbs: { BasePart },
	OrbColor: Color3?,
	Visible: boolean,
}

local owners: { [Player]: Owner } = {}
local FLYING_SHAPES = { Wisp = true, Bird = true, Dragon = true, Fish = true, Blob = false }

local function buildPet(token: string): PetEntry?
	local id, mutation = string.match(token, "^([^:]+):?(.*)$")
	local def = id and Pets.ById[id]
	if not def then
		return nil
	end
	local model = PetBuilder.Build(def, 1, if mutation ~= "" then mutation else nil)
	local pivot = model:GetPivot()
	local parts, offsets, flaps = {}, {}, {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			table.insert(parts, d)
			table.insert(offsets, pivot:ToObjectSpace(d.CFrame))
			table.insert(flaps, d:GetAttribute("Flap") or 0)
		end
	end
	if lowGraphics then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("ParticleEmitter") or d:IsA("Beam") then
				d.Enabled = false
			end
		end
	end
	model.Parent = folder
	return {
		Model = model, Parts = parts, Offsets = offsets, Flaps = flaps,
		Flying = FLYING_SHAPES[def.Shape] == true, Current = pivot,
		Scale = model:GetAttribute("MutationScale") or 1,
		Animate = if lowGraphics then nil else MutationLook.Animator(model),
	}
end

local function clearOwner(owner: Owner)
	for _, pet in ipairs(owner.Pets) do
		pet.Model:Destroy()
	end
	for _, orb in ipairs(owner.Orbs) do
		orb:Destroy()
	end
	table.clear(owner.Pets)
	table.clear(owner.Orbs)
end

local function rebuildPets(player: Player)
	local owner = owners[player]
	if not owner then
		return
	end
	local ids = player:GetAttribute("EquippedPets") or ""
	local visible = player == localPlayer or showOthers
	if ids == owner.Ids and visible == owner.Visible then
		return
	end
	owner.Ids = ids
	owner.Visible = visible
	for _, pet in ipairs(owner.Pets) do
		pet.Model:Destroy()
	end
	table.clear(owner.Pets)
	if not visible then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	for id in string.gmatch(ids, "[^,]+") do
		local pet = buildPet(id)
		if pet then
			if root then
				pet.Current = root.CFrame * CFrame.new(0, 0, 6)
			end
			table.insert(owner.Pets, pet)
		end
	end
end

local function rebuildOrbs(player: Player)
	local owner = owners[player]
	if not owner then
		return
	end
	for _, orb in ipairs(owner.Orbs) do
		orb:Destroy()
	end
	table.clear(owner.Orbs)
	local character = player.Character
	local tierIndex = character and character:GetAttribute("NinjaTier")
	local tier = tierIndex and Tiers.Get(tierIndex)
	if not tier or not tier.Outfit.Features.Orbit or lowGraphics then
		return
	end
	local color = if tier.Outfit.EyeGlow then tier.Outfit.EyeColor else tier.Color
	for i = 1, 3 do
		local orb = Instance.new("Part")
		orb.Name = "Orb" .. i
		orb.Shape = Enum.PartType.Ball
		orb.Size = Vector3.new(0.7, 0.7, 0.7)
		orb.Material = Enum.Material.Neon
		orb.Color = color
		orb.Anchored = true
		orb.CanCollide = false
		orb.CanQuery = false
		orb.CanTouch = false
		orb.CastShadow = false
		orb.Parent = folder
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 6
		light.Brightness = 1
		light.Parent = orb
		table.insert(owner.Orbs, orb)
	end
end

local function watchCharacter(player: Player, character: Model)
	character:GetAttributeChangedSignal("NinjaTier"):Connect(function()
		rebuildOrbs(player)
	end)
	rebuildOrbs(player)
	-- snap pets to the new spawn point
	local owner = owners[player]
	local root = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if owner and root then
		for _, pet in ipairs(owner.Pets) do
			pet.Current = root.CFrame * CFrame.new(0, 0, 6)
		end
	end
end

local function addPlayer(player: Player)
	owners[player] = { Pets = {}, Ids = "", Orbs = {}, Visible = false }
	player:GetAttributeChangedSignal("EquippedPets"):Connect(function()
		rebuildPets(player)
	end)
	player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
	end)
	if player.Character then
		task.spawn(watchCharacter, player, player.Character)
	end
	rebuildPets(player)
end

local function removePlayer(player: Player)
	local owner = owners[player]
	if owner then
		clearOwner(owner)
		owners[player] = nil
	end
end

-- formation slot i of n: an arc behind the owner (wider when a Big or Giant pet is in it)
local function slotOffset(i: number, n: number, size: number): Vector3
	local row = math.floor((i - 1) / 4)
	local inRow = math.min(4, n - row * 4)
	local col = (i - 1) % 4
	local spread = 3.6 * size
	local x = (col - (inRow - 1) / 2) * spread
	local z = 5 + (size - 1) * 1.5 + row * 3.6 * size + math.abs(x) * 0.25
	return Vector3.new(x, 0, z)
end

local partsBuffer: { BasePart } = {}
local cframeBuffer: { CFrame } = {}

local function step(dt: number)
	local camera = workspace.CurrentCamera
	local camPos = camera.CFrame.Position
	local now = os.clock()
	table.clear(partsBuffer)
	table.clear(cframeBuffer)
	local alpha = 1 - math.exp(-dt * 8)
	for player, owner in pairs(owners) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			continue
		end
		local rootPos = root.Position
		local far = (rootPos - camPos).Magnitude > 260
		local velocity = root.AssemblyLinearVelocity
		local flatVel = Vector3.new(velocity.X, 0, velocity.Z)
		local moving = flatVel.Magnitude > 2
		local base = CFrame.new(rootPos) * root.CFrame.Rotation
		local groundY = rootPos.Y - 2.6
		local n = #owner.Pets
		local size = 1
		for _, pet in ipairs(owner.Pets) do
			size = math.max(size, 1 + (pet.Scale - 1) * 0.6)
		end
		for i, pet in ipairs(owner.Pets) do
			local offset = slotOffset(i, n, size)
			local target = base * CFrame.new(offset)
			local bob = math.sin(now * (if moving then 9 else 3) + i * 1.3)
			-- bigger pets stand taller (their feet stay on the ground)
			local lift = (pet.Scale - 1) * 1.05
			local y = if pet.Flying then groundY + 3.4 + lift + bob * 0.45 else groundY + 1 + lift + math.max(0, bob) * (if moving then 0.9 else 0.15)
			local pos = Vector3.new(target.X, y, target.Z)
			local look = if moving then flatVel.Unit else root.CFrame.LookVector
			local goal = CFrame.lookAt(pos, pos + look)
			if far or (pet.Current.Position - pos).Magnitude > 60 then
				pet.Current = goal
			else
				pet.Current = pet.Current:Lerp(goal, alpha)
			end
			if far then
				continue
			end
			if pet.Animate then
				pet.Animate(now)
			end
			local flapAngle = math.sin(now * 14 + i) * 0.5
			for k, part in ipairs(pet.Parts) do
				local off = pet.Offsets[k]
				local flap = pet.Flaps[k]
				if flap ~= 0 then
					off = off * CFrame.Angles(0, 0, flap * flapAngle)
				end
				table.insert(partsBuffer, part)
				table.insert(cframeBuffer, pet.Current * off)
			end
		end
		-- orbit orbs
		local orbCount = #owner.Orbs
		for i, orb in ipairs(owner.Orbs) do
			local a = now * 2 + (i - 1) * (math.pi * 2 / orbCount)
			local pos = rootPos + Vector3.new(math.cos(a) * 3.2, 0.6 + math.sin(now * 3 + i) * 0.6, math.sin(a) * 3.2)
			table.insert(partsBuffer, orb)
			table.insert(cframeBuffer, CFrame.new(pos))
		end
	end
	if #partsBuffer > 0 then
		workspace:BulkMoveTo(partsBuffer, cframeBuffer, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function PetController:Start(c)
	controllers = c
	folder = Instance.new("Folder")
	folder.Name = "ClientPets"
	folder.Parent = workspace

	Players.PlayerAdded:Connect(addPlayer)
	Players.PlayerRemoving:Connect(removePlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(addPlayer, player)
	end

	controllers.DataController:OnChange("Settings", function(settings)
		local others = settings.OtherPets ~= false
		local low = settings.LowGraphics == true
		local lowChanged = low ~= lowGraphics
		showOthers = others
		lowGraphics = low
		for player, owner in pairs(owners) do
			if lowChanged then
				owner.Ids = "\0" -- force rebuild
				rebuildOrbs(player)
			end
			rebuildPets(player)
		end
	end)

	RunService.RenderStepped:Connect(step)
end

return PetController
