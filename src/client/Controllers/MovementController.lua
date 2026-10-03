--[[
	MovementController: sprint and double jump for the local character.

	Sprint: hold Shift (keyboard) or click L3 (gamepad); touch screens always sprint.
	The server sets the walk speed from stats (Shared/Stats); sprinting multiplies
	it by Balance.SprintMultiplier on this client, which owns its character's movement.

	Double jump: jump again in the air (Balance.ExtraJumps times) for a flip, a
	burst ring and a whoosh. The jumps come back on landing.

	While a swing plays the walk speed drops to Balance.SwingMoveSpeed x (Souls-style
	commitment); dodging is DodgeController's.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Balance = require(ReplicatedStorage.Shared.Config.Balance)

local MovementController = {}

local player = Players.LocalPlayer
local controllers
local sprintHeld = false
local jumpsLeft = 0
local airborneSince: number? = nil
local lastExtraJump = 0

local function getHumanoid(): (Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if humanoid and humanoid.Health > 0 and root then
		return humanoid, root
	end
	return nil, nil
end

local function isSprinting(): boolean
	return sprintHeld or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
end

local function jumpSpeed(humanoid: Humanoid): number
	if humanoid.UseJumpPower then
		return humanoid.JumpPower
	end
	return math.sqrt(2 * workspace.Gravity * humanoid.JumpHeight)
end

function MovementController:TryExtraJump(): boolean
	local humanoid, root = getHumanoid()
	if not humanoid or not root or jumpsLeft <= 0 or not airborneSince then
		return false
	end
	local now = os.clock()
	-- JumpRequest repeats while the button is held: only count a fresh press a moment after take-off
	if now - airborneSince < 0.15 or now - lastExtraJump < 0.25 then
		return false
	end
	jumpsLeft -= 1
	lastExtraJump = now
	local v = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(v.X, jumpSpeed(humanoid) * 1.05, v.Z)
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	controllers.AnimationController:PlayFlip(player.Character :: Model, 0.5)
	controllers.EffectsController:Shockwave(root.Position - Vector3.new(0, 2.6, 0), Color3.fromRGB(235, 245, 255), 4, 0.35, 0.25)
	controllers.SoundController:Play("DoubleJump")
	return true
end

local function hookCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	jumpsLeft, airborneSince = 0, nil
	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping and controllers.CombatController then
			-- fluid combat: jumping out of a swing cancels it
			controllers.CombatController:CancelSwing(true)
		end
		if new == Enum.HumanoidStateType.Jumping or new == Enum.HumanoidStateType.Freefall then
			airborneSince = airborneSince or os.clock()
		elseif new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running
			or new == Enum.HumanoidStateType.RunningNoPhysics or new == Enum.HumanoidStateType.Swimming
			or new == Enum.HumanoidStateType.Climbing then
			airborneSince = nil
			jumpsLeft = Balance.ExtraJumps
		end
	end)
end

function MovementController:Start(c)
	controllers = c
	UserInputService.JumpRequest:Connect(function()
		self:TryExtraJump()
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			sprintHeld = true
		elseif input.KeyCode == Enum.KeyCode.ButtonL3 then
			sprintHeld = not sprintHeld -- clicking the stick toggles
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			sprintHeld = false
		end
	end)

	-- keep the walk speed at the stat value (x sprint); the server re-sends the base
	-- whenever stats change, so this also picks up upgrades straight away
	local wasSprinting = false
	RunService.Heartbeat:Connect(function()
		local humanoid, root = getHumanoid()
		local stats = c.DataController:GetStats()
		if not humanoid or not root or not stats then
			return
		end
		local sprinting = isSprinting()
		local target = stats.WalkSpeed * (if sprinting then Balance.SprintMultiplier else 1)
		if c.CombatController:IsAttacking() then
			target *= Balance.SwingMoveSpeed -- committed to the swing: no running while it plays
		end
		if math.abs(humanoid.WalkSpeed - target) > 0.01 and humanoid.WalkSpeed > 0 then
			humanoid.WalkSpeed = target
		end
		-- the wider view only while actually running
		local v = root.AssemblyLinearVelocity
		local running = sprinting and Vector3.new(v.X, 0, v.Z).Magnitude > stats.WalkSpeed * 0.8
		if running ~= wasSprinting then
			wasSprinting = running
			c.CameraController:SetSprint(running)
		end
	end)

	if player.Character then
		task.spawn(hookCharacter, player.Character)
	end
	player.CharacterAdded:Connect(hookCharacter)
end

return MovementController
