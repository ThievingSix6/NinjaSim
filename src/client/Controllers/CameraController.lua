--[[
	CameraController: screen shake (runs right after the default camera update so it
	never fights it), FOV punches, and short scripted "cinematic" orbits used for
	tier transformations.
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local CameraController = {}

local trauma = 0
local shakeEnabled = true
local baseFov = 70
local fovOffset = 0
local sprintFov, sprintTarget = 0, 0
local cinematic: { Start: number, Duration: number, Target: BasePart }? = nil

function CameraController:Shake(amount: number)
	if not shakeEnabled then
		return
	end
	trauma = math.min(1, trauma + amount)
end

function CameraController:Punch(fovDelta: number, duration: number?)
	fovOffset = fovDelta
	local holder = Instance.new("NumberValue")
	holder.Value = fovDelta
	local tween = TweenService:Create(holder, TweenInfo.new(duration or 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = 0 })
	holder.Changed:Connect(function(v)
		fovOffset = v
	end)
	tween:Play()
	tween.Completed:Connect(function()
		holder:Destroy()
	end)
end

-- Widens the view a little while sprinting.
function CameraController:SetSprint(on: boolean)
	sprintTarget = if on then 8 else 0
end

-- Orbit the camera around the local character for `duration` seconds.
function CameraController:Cinematic(duration: number)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	cinematic = { Start = os.clock(), Duration = duration, Target = root }
	workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
	task.delay(duration, function()
		cinematic = nil
		workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	end)
end

function CameraController:Start(controllers)
	controllers.DataController:OnChange("Settings", function(settings)
		shakeEnabled = settings.ScreenShake
	end)
	RunService:BindToRenderStep("NinjaCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local camera = workspace.CurrentCamera
		if cinematic then
			local c = cinematic
			local t = (os.clock() - c.Start) / c.Duration
			local root = c.Target
			local angle = math.rad(200) + t * math.rad(120)
			local dist = 11 - t * 3
			local focus = root.Position + Vector3.new(0, 1.5, 0)
			camera.CFrame = CFrame.lookAt(focus + Vector3.new(math.sin(angle) * dist, 2 + t * 1.5, math.cos(angle) * dist), focus)
		end
		sprintFov += (sprintTarget - sprintFov) * math.min(1, dt * 8)
		camera.FieldOfView = baseFov + fovOffset + sprintFov
		if trauma > 0 then
			local shake = trauma * trauma
			local t = os.clock() * 30
			local offset = CFrame.Angles(
				math.rad(math.noise(t, 1) * 2.2 * shake),
				math.rad(math.noise(t, 2) * 2.2 * shake),
				math.rad(math.noise(t, 3) * 1.4 * shake)
			)
			camera.CFrame *= offset
			trauma = math.max(0, trauma - dt * 1.8)
		end
	end)
end

return CameraController
