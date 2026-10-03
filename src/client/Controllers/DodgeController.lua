--[[
	DodgeController: the dodge roll (Balance.Dodge).

	Circle on a PlayStation pad (ButtonB; B on Xbox), Q or Left Ctrl on a keyboard, or
	the roll button on touch screens. Moving, the player rolls that way; standing
	still, they hop back (a backstep). It costs stamina (CombatController's pool), works
	only on the ground, and cancels a swing in progress (fluid combat: a roll during a
	swing's wind-up cancels it on the server too, see CombatService:CancelSwing).

	This client owns its character's physics, so it moves the roll itself with a
	LinearVelocity in the ground plane. The server (CombatService "Dodge") checks the
	cadence and stamina and opens the i-frames: enemy and boss hits in that window miss
	("Evaded" -> "DODGED!" pop). Other players see the roll through "Dodged".

	A Circle press that closes a menu doesn't also roll (MenuManager.ClosedAt).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Net = require(Shared.Net)

local DodgeController = {}

local player = Players.LocalPlayer
local controllers
local dodgingUntil = 0
local lastDodge = 0
local active: { Velocity: LinearVelocity, Attachment: Attachment, Direction: Vector3, Speed: number, Start: number, Length: number }? = nil

local function isDodgeKey(code: Enum.KeyCode): boolean
	-- Circle (PlayStation) / B (Xbox), Q, Left Ctrl
	return code == Enum.KeyCode.ButtonB or code == Enum.KeyCode.Q or code == Enum.KeyCode.LeftControl
end

-- Forward roll: tuck, turn a full circle forward low to the ground, come up.
local ROLL = {
	Name = "Roll",
	Keys = {
		{
			T = 0.12, Ease = "Out", RootPos = { 0, -1, 0 }, Root = { -45, 0, 0 }, Waist = { -30, 0, 0 }, Neck = { -25, 0, 0 },
			RightShoulder = { 75, 0, 20 }, RightElbow = { 70, 0, 0 }, LeftShoulder = { 75, 0, -20 }, LeftElbow = { 70, 0, 0 },
			RightHip = { 95, 0, 5 }, RightKnee = { -115, 0, 0 }, LeftHip = { 95, 0, -5 }, LeftKnee = { -115, 0, 0 },
		},
		{
			T = 0.55, Ease = "Linear", RootPos = { 0, -1.3, 0 }, Root = { -230, 0, 0 }, Waist = { -35, 0, 0 }, Neck = { -30, 0, 0 },
			RightShoulder = { 80, 0, 15 }, RightElbow = { 90, 0, 0 }, LeftShoulder = { 80, 0, -15 }, LeftElbow = { 90, 0, 0 },
			RightHip = { 115, 0, 5 }, RightKnee = { -130, 0, 0 }, LeftHip = { 115, 0, -5 }, LeftKnee = { -130, 0, 0 },
		},
		{
			T = 0.82, Ease = "Out", RootPos = { 0, -0.7, 0 }, Root = { -360, 0, 0 }, Waist = { -15, 0, 0 }, Neck = { -5, 0, 0 },
			RightShoulder = { 35, 0, 30 }, RightElbow = { 40, 0, 0 }, LeftShoulder = { 35, 0, -30 }, LeftElbow = { 40, 0, 0 },
			RightHip = { 55, 0, 5 }, RightKnee = { -75, 0, 0 }, LeftHip = { 25, 0, -5 }, LeftKnee = { -50, 0, 0 },
		},
	},
}

-- Backstep: a low hop back with the weapon kept up.
local BACKSTEP = {
	Name = "Backstep",
	Keys = {
		{
			T = 0.25, Ease = "Out", RootPos = { 0, -0.5, 0 }, Root = { 12, 0, 0 }, Waist = { -10, 0, 0 },
			RightShoulder = { 45, -20, 0 }, RightElbow = { 50, 0, 0 }, LeftShoulder = { 30, 10, -15 }, LeftElbow = { 60, 0, 0 },
			RightHip = { -25, 0, 8 }, RightKnee = { -40, 0, 0 }, LeftHip = { 35, 0, -8 }, LeftKnee = { -60, 0, 0 },
		},
		{
			T = 0.7, Ease = "Out", RootPos = { 0, -0.7, 0 }, Root = { 5, 0, 0 }, Waist = { -15, 0, 0 },
			RightShoulder = { 50, -25, 0 }, RightElbow = { 55, 0, 0 }, LeftShoulder = { 35, 10, -15 }, LeftElbow = { 60, 0, 0 },
			RightHip = { 30, 0, 8 }, RightKnee = { -65, 0, 0 }, LeftHip = { -10, 0, -8 }, LeftKnee = { -35, 0, 0 },
		},
	},
}

local function getCharacter(): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if character and humanoid and root and humanoid.Health > 0 then
		return character, humanoid, root
	end
	return nil, nil, nil
end

local function stopMotion()
	if active then
		active.Velocity:Destroy()
		active.Attachment:Destroy()
		active = nil
	end
end

function DodgeController:IsDodging(): boolean
	return os.clock() < dodgingUntil
end

function DodgeController:Dodge(): boolean
	local character, humanoid, root = getCharacter()
	if not character or not humanoid or not root then
		return false
	end
	local now = os.clock()
	if now - lastDodge < Balance.Dodge.Cooldown or now < dodgingUntil then
		return false
	end
	if humanoid.FloorMaterial == Enum.Material.Air then
		return false -- rolls start on the ground
	end
	local combat = controllers.CombatController
	if not combat:TrySpend(Balance.Stamina.Dodge) then
		return false
	end
	lastDodge = now
	-- the roll cancels any swing (the "Dodge" event cancels a wind-up on the server)
	combat:CancelSwing(false)

	local move = humanoid.MoveDirection
	local flatMove = Vector3.new(move.X, 0, move.Z)
	local rolling = flatMove.Magnitude > 0.1
	local direction, distance
	if rolling then
		direction = flatMove.Unit
		distance = Balance.Dodge.Distance
		root.CFrame = CFrame.lookAt(root.Position, root.Position + direction)
	else
		local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		direction = if look.Magnitude > 0.01 then -look.Unit else Vector3.new(0, 0, 1)
		distance = Balance.Dodge.BackstepDistance
	end
	local length = if rolling then Balance.Dodge.Duration else Balance.Dodge.Duration * 0.75
	dodgingUntil = now + length

	-- speed eases off through the roll: v(t) = v0 * (1 - 0.75 t/T) covers `distance`
	stopMotion()
	local attachment = Instance.new("Attachment")
	attachment.Name = "DodgeAttachment"
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "DodgeVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.new(1, 0, 0)
	velocity.SecondaryTangentAxis = Vector3.new(0, 0, 1)
	velocity.MaxForce = 1e6
	local speed = distance / length / 0.625
	velocity.PlaneVelocity = Vector2.new(direction.X, direction.Z) * speed
	velocity.Parent = root
	active = { Velocity = velocity, Attachment = attachment, Direction = direction, Speed = speed, Start = now, Length = length }

	controllers.AnimationController:PlayPose(character, if rolling then ROLL else BACKSTEP, length, { Airborne = true })
	controllers.SoundController:Play("Dodge")
	controllers.EffectsController:Shockwave(root.Position - Vector3.new(0, 2.7, 0), Color3.fromRGB(220, 205, 175), 3.5, 0.35, 0.2)
	Net.Event("Dodge"):FireServer(if rolling then direction else nil)
	return true
end

-- Another player's roll (their motion replicates; the pose is drawn here).
local function onDodged(other: Player, kind: string)
	local character = other and other.Character
	if character then
		controllers.AnimationController:PlayPose(character, if kind == "Backstep" then BACKSTEP else ROLL, Balance.Dodge.Duration, { Airborne = true })
	end
end

local lastEvade = 0
local function onEvaded()
	local now = os.clock()
	if now - lastEvade < 0.3 then
		return
	end
	lastEvade = now
	local _, _, root = getCharacter()
	if not root then
		return
	end
	local camera = workspace.CurrentCamera
	local screen, onScreen = camera:WorldToViewportPoint(root.Position + Vector3.new(0, 4, 0))
	local scale = controllers.UIController.Scale
	local pos = if onScreen then Vector2.new(screen.X, screen.Y) / scale else Vector2.new(640, 300)
	controllers.EffectsController:FloatText("DODGED!", Color3.fromRGB(150, 230, 255), pos, 30)
	controllers.SoundController:Play("Evade")
end

function DodgeController:Start(c)
	controllers = c

	UserInputService.InputBegan:Connect(function(input, processed)
		if not isDodgeKey(input.KeyCode) then
			return
		end
		if UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.ButtonB then
			-- Circle also closes menus and backs out of gamepad UI navigation
			if c.MenuManager:IsOpen() or os.clock() - (c.MenuManager.ClosedAt or 0) < 0.2 or GuiService.SelectedObject then
				return
			end
		elseif processed or c.MenuManager:IsOpen() then
			return
		end
		self:Dodge()
	end)

	RunService.Heartbeat:Connect(function()
		local roll = active
		if not roll then
			return
		end
		local t = (os.clock() - roll.Start) / roll.Length
		if t >= 1 or not roll.Velocity.Parent then
			stopMotion()
			return
		end
		local v = roll.Direction * roll.Speed * (1 - 0.75 * t)
		roll.Velocity.PlaneVelocity = Vector2.new(v.X, v.Z)
	end)

	player.CharacterAdded:Connect(function()
		stopMotion()
		dodgingUntil = 0
	end)

	Net.Event("Dodged").OnClientEvent:Connect(onDodged)
	Net.Event("Evaded").OnClientEvent:Connect(onEvaded)
end

return DodgeController
