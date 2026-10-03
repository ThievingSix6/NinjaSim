--[[
	CompanionController: the client side of hired ninjas (CompanionService). Their rigs
	are animated by AnimationController like enemies ("Companion" tag); this adds the
	nameplate (name, whose ninja, a health bar), their thrown shurikens, the skill
	effects, hit sparks and numbers, and greys a knocked-out ninja until it gets up.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local CompanionController = {}

local player = Players.LocalPlayer
local controllers
local rgb = Color3.fromRGB

local function nameplate(model: Instance)
	if not model:IsA("Model") or model:FindFirstChild("CompanionPlate") then
		return
	end
	local head = model:FindFirstChild("Head") or model.PrimaryPart
	if not head then
		task.delay(0.5, nameplate, model)
		return
	end
	local mine = model:GetAttribute("Owner") == player.UserId
	local owner = Players:GetPlayerByUserId(model:GetAttribute("Owner") or 0)
	local gui = Instance.new("BillboardGui")
	gui.Name = "CompanionPlate"
	gui.Size = UDim2.fromOffset(160, 40)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.Adornee = head
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 18)
	name.Font = Enum.Font.GothamBold
	name.TextSize = 14
	name.TextColor3 = if mine then rgb(140, 255, 160) else rgb(200, 230, 255)
	name.TextStrokeTransparency = 0.4
	name.Text = tostring(model:GetAttribute("DisplayName") or model.Name)
	name.Parent = gui
	local sub = name:Clone()
	sub.Position = UDim2.fromOffset(0, 16)
	sub.Size = UDim2.new(1, 0, 0, 12)
	sub.TextSize = 11
	sub.Font = Enum.Font.Gotham
	sub.Text = if mine then "your ninja" elseif owner then owner.Name .. "'s ninja" else ""
	sub.Parent = gui
	local back = Instance.new("Frame")
	back.BackgroundColor3 = rgb(30, 26, 40)
	back.BorderSizePixel = 0
	back.Size = UDim2.new(0.7, 0, 0, 6)
	back.Position = UDim2.new(0.15, 0, 0, 31)
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = rgb(110, 230, 120)
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = back
	local function update()
		local max = model:GetAttribute("MaxHealth") or 1
		local hp = model:GetAttribute("Health") or max
		local k = math.clamp(hp / math.max(1, max), 0, 1)
		fill.Size = UDim2.fromScale(k, 1)
		fill.BackgroundColor3 = if k > 0.5 then rgb(110, 230, 120) elseif k > 0.25 then rgb(255, 200, 60) else rgb(255, 80, 80)
	end
	model:GetAttributeChangedSignal("Health"):Connect(update)
	model:GetAttributeChangedSignal("MaxHealth"):Connect(update)
	update()
	gui.Parent = model
end

local function setDown(model: Instance?, down: boolean)
	if not model then
		return
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			if down then
				if d:GetAttribute("BaseT") == nil then
					d:SetAttribute("BaseT", d.Transparency)
				end
				d.Transparency = math.max(d.Transparency, 0.65)
			elseif d:GetAttribute("BaseT") ~= nil then
				d.Transparency = d:GetAttribute("BaseT")
			end
		end
	end
end

local function shuriken(from: Vector3, to: Vector3, color: Color3?)
	local fx = controllers.EffectsController
	local star = fx.Part(Vector3.new(1.4, 0.2, 1.4), CFrame.new(from), color or rgb(200, 210, 230), Enum.Material.Metal)
	local travel = math.clamp((to - from).Magnitude / 70, 0.12, 0.5)
	local spin = 0
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		local t = math.min(1, (os.clock() - start) / travel)
		spin += dt * 30
		star.CFrame = CFrame.new(from:Lerp(to + Vector3.new(0, 1.5, 0), t)) * CFrame.Angles(0, spin, 0)
		if t >= 1 then
			conn:Disconnect()
			star:Destroy()
		end
	end)
end

local function onEvent(payload)
	local fx = controllers.EffectsController
	if payload.Type == "Hit" and typeof(payload.Position) == "Vector3" then
		fx:HitSpark(payload.Position + Vector3.new(0, 2, 0), if payload.Crit then rgb(255, 210, 60) else rgb(200, 255, 210), payload.Crit)
		if payload.Owner == player.UserId then
			fx:DamageNumber(payload.Position + Vector3.new(0, 4, 0), payload.Damage, payload.Crit, rgb(150, 255, 170))
		end
		if payload.Uid then
			controllers.AnimationController:HitEnemy(payload.Uid)
		end
	elseif payload.Type == "Shuriken" then
		if typeof(payload.From) == "Vector3" and typeof(payload.To) == "Vector3" then
			shuriken(payload.From, payload.To)
		end
	elseif payload.Type == "Skill" then
		local pos = payload.Position
		if typeof(pos) ~= "Vector3" then
			return
		end
		local kind = payload.Kind
		if kind == "Whirlwind" then
			fx:Shockwave(pos - Vector3.new(0, 2.5, 0), rgb(220, 230, 255), payload.Radius or 12, 0.35, 0.4)
			controllers.SoundController:Play("Swing", 0.7, 0.8)
		elseif kind == "Fan" then
			for _, target in ipairs(payload.Targets or {}) do
				shuriken(pos + Vector3.new(0, 1.5, 0), target, rgb(140, 230, 255))
			end
			controllers.SoundController:Play("Swing", 0.6, 1.4)
		elseif kind == "Fire" then
			fx:Shockwave(pos - Vector3.new(0, 2.5, 0), rgb(255, 120, 40), payload.Radius or 10, 0.45, 0.3)
			task.delay(0.4, function()
				fx:Pillar(pos - Vector3.new(0, 2.5, 0), rgb(255, 110, 30), 22, 0.6)
				fx:Burst(pos, "Sparkle", 24, { Color = ColorSequence.new(rgb(255, 140, 40)) })
				controllers.SoundController:Play("Slam", 0.7, 0.9)
			end)
		elseif kind == "Shadow" then
			fx:Burst(pos, "Shadow", 16)
			if typeof(payload.To) == "Vector3" then
				fx:Burst(payload.To, "Shadow", 16)
			end
			controllers.SoundController:Play("Evade", 0.6, 0.8)
		elseif kind == "Slam" then
			fx:Shockwave(pos - Vector3.new(0, 2.8, 0), rgb(230, 200, 120), payload.Radius or 14, 0.5, 0.5)
			controllers.SoundController:Play("Slam")
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root and (root.Position - pos).Magnitude < 40 then
				controllers.CameraController:Shake(0.25)
			end
		elseif kind == "Heal" then
			fx:Pillar(pos - Vector3.new(0, 3, 0), rgb(120, 255, 150), 12, 0.6)
			fx:Burst(pos, "Sparkle", 18, { Color = ColorSequence.new(rgb(140, 255, 160)) })
			controllers.SoundController:Play("LevelUp", 0.4, 1.4)
		end
	elseif payload.Type == "Hurt" then
		local model = payload.Model
		if typeof(model) == "Instance" and model:IsA("Model") and model.PrimaryPart then
			fx:HitSpark(model.PrimaryPart.Position, rgb(255, 90, 90), false)
		end
	elseif payload.Type == "Down" then
		setDown(payload.Model, true)
	elseif payload.Type == "Up" then
		setDown(payload.Model, false)
		if typeof(payload.Model) == "Instance" and payload.Model:IsA("Model") and payload.Model.PrimaryPart then
			fx:Burst(payload.Model.PrimaryPart.Position, "Sparkle", 14)
		end
	end
end

function CompanionController:Start(c)
	controllers = c
	CollectionService:GetInstanceAddedSignal("Companion"):Connect(nameplate)
	for _, model in ipairs(CollectionService:GetTagged("Companion")) do
		nameplate(model)
	end
	Net.Event("Companion").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		local ok, err = pcall(onEvent, payload)
		if not ok then
			warn("[CompanionController] " .. tostring(err))
		end
	end)
end

return CompanionController
