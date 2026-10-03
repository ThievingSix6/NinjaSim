--[[
	UltimateController: the worn suit's mastery ultimates (Config/Mastery).

	Z X C V (gamepad: d-pad up, right, down, left; the HUD ultimate bar on touch) cast
	the ultimate in that slot once the suit's mastery reaches its level. Like skills,
	the client plays the effects right away (SkillEffects -> UltimateEffects) and asks
	the server ("CastUltimate"), which decides what is hit.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Mastery = require(Shared.Config.Mastery)
local SkillEffects = require(script.Parent:WaitForChild("SkillEffects"))

local UltimateController = {}

local function slotOfKey(code: Enum.KeyCode): number?
	if code == Enum.KeyCode.Z or code == Enum.KeyCode.DPadUp then
		return 1
	elseif code == Enum.KeyCode.X or code == Enum.KeyCode.DPadRight then
		return 2
	elseif code == Enum.KeyCode.C or code == Enum.KeyCode.DPadDown then
		return 3
	elseif code == Enum.KeyCode.V or code == Enum.KeyCode.DPadLeft then
		return 4
	end
	return nil
end

local controllers
local player = Players.LocalPlayer
local readyAt: { [string]: number } = {}
local castListeners: { (number) -> () } = {}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function cameraLook(): Vector3
	local camera = workspace.CurrentCamera
	local look = if camera then flat(camera.CFrame.LookVector) else Vector3.zero
	return if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
end

-- The ultimate in `slot` for the worn suit (or nil).
function UltimateController:Get(slot: number)
	local data = controllers.DataController:Get()
	if not data then
		return nil
	end
	return Mastery.ForSuit(Mastery.WornTier(data).Id)[slot]
end

-- Seconds left and total cooldown of the ultimate in `slot`.
function UltimateController:GetCooldown(slot: number): (number, number)
	local def = self:Get(slot)
	if not def then
		return 0, 0
	end
	return math.max(0, (readyAt[def.Id] or 0) - os.clock()), def.Cooldown
end

function UltimateController:OnCast(fn: (number) -> ())
	table.insert(castListeners, fn)
end

-- Dashes (def.Steer) go where you move; the rest at the nearest enemy in reach, else
-- where the camera looks.
local function aim(def, root: BasePart, humanoid: Humanoid): Vector3
	local moving = flat(humanoid.MoveDirection)
	if def.Steer and moving.Magnitude > 0.1 then
		return moving.Unit
	end
	local reach = def.Length or def.Range or def.Distance or 40
	local best, bestDist = nil, reach
	for _, model in ipairs(CollectionService:GetTagged("Enemy")) do
		if model:IsA("Model") and not model:GetAttribute("Dead") and model.PrimaryPart then
			local d = flat(model.PrimaryPart.Position - root.Position).Magnitude
			if d < bestDist then
				best, bestDist = model.PrimaryPart.Position, d
			end
		end
	end
	if best then
		local to = flat(best - root.Position)
		if to.Magnitude > 0.5 then
			return to.Unit
		end
	end
	return cameraLook()
end

function UltimateController:Cast(slot: number): boolean
	local data = controllers.DataController:Get()
	local def = self:Get(slot)
	if not data or not def then
		return false
	end
	local ok, reason = Mastery.CanUse(data, def)
	if not ok then
		controllers.NotificationController:Toast(def.Name .. ": " .. (reason or "locked"), def.Color, "Lock")
		controllers.SoundController:Play("Error")
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 then
		return false
	end
	local now = os.clock()
	if now < (readyAt[def.Id] or 0) then
		controllers.SoundController:Play("Error")
		return false
	end
	readyAt[def.Id] = now + def.Cooldown
	local dir = aim(def, root, humanoid)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	local ctx = { Character = character, Root = root, Dir = dir, Origin = root.Position, Def = def, Level = 1, Local = true }
	SkillEffects:Start(ctx)
	for _, fn in ipairs(castListeners) do
		task.spawn(fn, slot)
	end
	task.spawn(function()
		local okCast, result = controllers.DataController:Request("CastUltimate", slot, dir)
		if okCast and type(result) == "table" then
			ctx.Info = result.Info
			ctx.Elapsed = os.clock() - now
			SkillEffects:Result(ctx, result.Info or {})
		else
			readyAt[def.Id] = math.min(readyAt[def.Id] or 0, os.clock() + 0.6)
		end
	end)
	return true
end

function UltimateController:Start(c)
	controllers = c
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if c.MenuManager and c.MenuManager:IsOpen() then
			return
		end
		local slot = slotOfKey(input.KeyCode)
		if slot then
			self:Cast(slot)
		end
	end)
end

return UltimateController
