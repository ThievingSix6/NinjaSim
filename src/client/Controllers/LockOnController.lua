--[[
	LockOnController: Souls-style target lock.

	Toggle with the middle mouse button or L on a keyboard, Square on a PlayStation pad
	(X on Xbox; R3 belongs to the camera), or the LOCK button on touch screens. It picks
	the nearest living enemy in front of the camera (within Range studs; anything in
	Range if nothing is in front).
	While locked:
	  - the camera swings behind you to keep the target framed (CameraController calls
	    Apply from its render step, after the default camera, so shake still plays and
	    the camera stays where it is when the lock drops);
	  - your ninja keeps facing the target, so you can strafe and roll around it;
	  - a reticle marks the target; swings aim at it (CombatController aim assist).
	Flick the right stick (or press L / middle mouse again) to cycle or drop: on a
	gamepad a hard flick left/right switches to the next target that side. When the
	target dies the lock jumps to the next nearest enemy, or ends.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local LockOnController = {}

local RANGE = 70 -- how far a new lock reaches
local KEEP = 95 -- the lock breaks past this
local player = Players.LocalPlayer
local controllers
local target: Model? = nil
local reticle: BillboardGui? = nil
local lookSmooth: Vector3? = nil
local flickReady = true

local function getRoot(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function alive(model: Model?): boolean
	return model ~= nil and model.Parent ~= nil and not model:GetAttribute("Dead") and model.PrimaryPart ~= nil
end

local function aimPoint(model: Model): Vector3
	local height = model:GetAttribute("Height") or 5
	return (model.PrimaryPart :: BasePart).Position + Vector3.new(0, height * 0.15, 0)
end

-- Candidates scored by distance, with enemies off to the side of the camera costing
-- more; `side` (-1 / 1) keeps only enemies to that side of the current target.
local function pick(exclude: Model?, side: number?): Model?
	local root = getRoot()
	if not root then
		return nil
	end
	local camera = workspace.CurrentCamera
	local look = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	local right = camera.CFrame.RightVector
	local best, bestScore = nil, math.huge
	-- enemies, plus your duel opponent while a duel is on
	local candidates = CollectionService:GetTagged("Enemy")
	local duel = controllers and controllers.DuelController
	local foe = duel and duel:Opponent()
	if foe and foe.Character then
		candidates = table.clone(candidates)
		table.insert(candidates, foe.Character)
	end
	for _, model in ipairs(candidates) do
		if model:IsA("Model") and model ~= exclude and alive(model) then
			local to = (model.PrimaryPart :: BasePart).Position - root.Position
			local flat = Vector3.new(to.X, 0, to.Z)
			local dist = flat.Magnitude
			if dist <= RANGE then
				local dot = if dist > 0.5 then look:Dot(flat.Unit) else 1
				local ok = true
				if side and exclude and alive(exclude) then
					local from = (exclude.PrimaryPart :: BasePart).Position - root.Position
					ok = math.sign(right:Dot(flat) - right:Dot(from)) == side
				end
				if ok then
					-- behind the camera counts as much farther away
					local score = dist * (if dot > 0.3 then 1 else 3) - dot * 6
					if score < bestScore then
						best, bestScore = model, score
					end
				end
			end
		end
	end
	return best
end

local function clearReticle()
	if reticle then
		reticle:Destroy()
		reticle = nil
	end
end

local function showReticle(model: Model)
	clearReticle()
	local Kit, Theme = controllers.Kit, controllers.Theme
	local gui = Kit.New("BillboardGui", {
		Name = "LockOn", Adornee = model.PrimaryPart, AlwaysOnTop = true, LightInfluence = 0, Size = UDim2.fromOffset(46, 46),
		StudsOffsetWorldSpace = Vector3.new(0, (model:GetAttribute("Height") or 5) * 0.15, 0), ResetOnSpawn = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local ring = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
	Kit.Corner(23).Parent = ring
	Kit.Stroke(Color3.fromRGB(255, 255, 255), 2.5).Parent = ring
	local dot = Kit.New("Frame", {
		BackgroundColor3 = Theme.Red or Color3.fromRGB(255, 70, 70), Size = UDim2.fromOffset(10, 10),
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = gui,
	})
	Kit.Corner(5).Parent = dot
	Kit.Stroke(Color3.fromRGB(20, 10, 10), 1.5).Parent = dot
	reticle = gui
end

local function setTarget(model: Model?)
	target = model
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if model then
		showReticle(model)
		if humanoid then
			humanoid.AutoRotate = false
		end
	else
		clearReticle()
		lookSmooth = nil
		if humanoid then
			humanoid.AutoRotate = true
		end
	end
	if controllers.HUD and controllers.HUD.SetLockOn then
		controllers.HUD:SetLockOn(model ~= nil)
	end
end

function LockOnController:Target(): Model?
	return if alive(target) then target else nil
end

function LockOnController:Toggle()
	if target then
		controllers.SoundController:Play("Click")
		setTarget(nil)
		return
	end
	local found = pick(nil)
	if found then
		controllers.SoundController:Play("Equip")
		setTarget(found)
	else
		controllers.NotificationController:Toast("No enemy in range to lock on to", controllers.Theme.SubText, "Oni")
	end
end

function LockOnController:Cycle(side: number)
	if not target then
		return
	end
	local found = pick(target, side)
	if found then
		controllers.SoundController:Play("Click")
		setTarget(found)
	end
end

-- Called by CameraController every frame after the default camera: turn the camera to
-- look past you at the target, keeping the zoom the player chose. The default camera
-- reads its next look direction from camera.CFrame, so the turn sticks naturally.
function LockOnController:Apply(camera: Camera, dt: number)
	if not target then
		return
	end
	local root = getRoot()
	if not alive(target) or not root or (((target :: Model).PrimaryPart :: BasePart).Position - root.Position).Magnitude > KEEP then
		-- the target died or got away: jump to the next one, or let go
		setTarget(if root then pick(target) else nil)
		if not target then
			return
		end
	end
	local model = target :: Model
	local aim = aimPoint(model)

	-- face the target (flat), so swings, skills and strafing all point at it
	local flatTarget = Vector3.new(aim.X, root.Position.Y, aim.Z)
	if (flatTarget - root.Position).Magnitude > 0.5 and not (controllers.DodgeController and controllers.DodgeController:IsDodging()) then
		local want = CFrame.lookAt(root.Position, flatTarget)
		root.CFrame = root.CFrame:Lerp(want, math.min(1, dt * 14))
	end

	local focus = root.Position + Vector3.new(0, 2, 0)
	local zoom = math.clamp((camera.CFrame.Position - camera.Focus.Position).Magnitude, 8, 28)
	local to = aim - focus
	local flat = Vector3.new(to.X, 0, to.Z)
	if flat.Magnitude < 1 then
		return
	end
	-- look down at a slight angle; more when the target is close and below
	local pitch = math.clamp(math.atan2(-to.Y, flat.Magnitude), math.rad(-15), math.rad(35)) * 0.5 + math.rad(12)
	local want = (flat.Unit * math.cos(pitch) - Vector3.new(0, math.sin(pitch), 0)).Unit
	lookSmooth = if lookSmooth then lookSmooth:Lerp(want, math.min(1, dt * 9)).Unit else camera.CFrame.LookVector:Lerp(want, 0.25).Unit
	local look = lookSmooth :: Vector3
	local position = focus - look * zoom
	-- don't put the camera inside a wall
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Model, model }
	local hit = workspace:Raycast(focus, position - focus, params)
	if hit then
		position = hit.Position + look * 0.6
	end
	camera.CFrame = CFrame.lookAt(position, position + look)
	camera.Focus = CFrame.new(focus)
end

function LockOnController:Start(c)
	controllers = c
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton3 or input.KeyCode == Enum.KeyCode.L or input.KeyCode == Enum.KeyCode.ButtonX then
			LockOnController:Toggle()
		end
	end)
	-- a hard right-stick flick while locked switches target that way
	UserInputService.InputChanged:Connect(function(input)
		if not target or input.KeyCode ~= Enum.KeyCode.Thumbstick2 then
			return
		end
		local x = input.Position.X
		if flickReady and math.abs(x) > 0.85 then
			flickReady = false
			LockOnController:Cycle(if x > 0 then 1 else -1)
		elseif math.abs(x) < 0.3 then
			flickReady = true
		end
	end)
	player.CharacterAdded:Connect(function()
		setTarget(nil)
	end)
end

return LockOnController
