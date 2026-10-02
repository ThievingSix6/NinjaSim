--[[
	BossController: the boss health bar (with trailing damage and an ENRAGED
	tag), boss spawn / defeat banners, and the telegraphed attack visuals:
	  Circle   filling red disc, then slam shockwave
	  Ring     donut danger zone with a safe centre
	  Meteor   target circle + falling meteor from the sky
	  Line     dash lane that fills toward the far end
	  Summon   dark pillar where minions appear
	Telegraphs are purely visual; damage is resolved on the server.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Zones = require(ReplicatedStorage.Shared.Config.Zones)

local BossController = {}

local controllers, Kit, Theme
local fxFolder: Folder
local bar: Frame
local nameLabel: TextLabel
local hpLabel: TextLabel
local fill: Frame
local chunk: Frame
local enragedTag: TextLabel
local tracked: Model? = nil
local shownRatio = 1

local rgb = Color3.fromRGB
local localPlayer = Players.LocalPlayer

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.RespectCanCollide = true

local function groundAt(pos: Vector3): number
	local list = { workspace.Terrain }
	local world = workspace:FindFirstChild("World")
	if world then
		table.insert(list, world)
	end
	rayParams.FilterDescendantsInstances = list
	local hit = workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -80, 0), rayParams)
	return if hit then hit.Position.Y else pos.Y - 4
end

local function fxPart(props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	p.Parent = fxFolder
	return p
end

local function disc(center: Vector3, radius: number, color: Color3, transparency: number, thickness: number?): BasePart
	return fxPart({
		Shape = Enum.PartType.Cylinder, Size = Vector3.new(thickness or 0.2, radius * 2, radius * 2),
		CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), Color = color, Transparency = transparency,
	})
end

local function near(pos: Vector3, radius: number): boolean
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root ~= nil and (root.Position - pos).Magnitude < radius
end

local function impact(pos: Vector3, color: Color3, radius: number)
	controllers.EffectsController:Shockwave(pos, color, radius, 0.45)
	controllers.EffectsController:Burst(pos + Vector3.new(0, 1, 0), "Smoke", 18, { Color = ColorSequence.new(color:Lerp(rgb(60, 50, 50), 0.5)) })
	if near(pos, radius + 30) then
		controllers.SoundController:Play("BossSlam")
		controllers.CameraController:Shake(0.35)
	end
end

local telegraphs = {}

function telegraphs.Circle(t)
	local y = groundAt(t.Position)
	local center = Vector3.new(t.Position.X, y + 0.12, t.Position.Z)
	local outline = disc(center, t.Radius, t.Color, 0.55)
	local inner = disc(center + Vector3.new(0, 0.03, 0), 0.1, rgb(255, 60, 40), 0.25, 0.22)
	Kit.Tween(inner, { Size = Vector3.new(0.22, t.Radius * 2, t.Radius * 2) }, t.Duration, Enum.EasingStyle.Linear)
	task.wait(t.Duration)
	outline:Destroy()
	inner:Destroy()
	impact(center, t.Color, t.Radius * 1.1)
end

function telegraphs.Ring(t)
	local y = groundAt(t.Position)
	local center = Vector3.new(t.Position.X, y + 0.12, t.Position.Z)
	local danger = disc(center, t.Radius, rgb(255, 60, 40), 0.55)
	local safe = disc(center + Vector3.new(0, 0.04, 0), t.Inner, rgb(90, 255, 140), 0.45, 0.24)
	local pulse = true
	task.spawn(function()
		while pulse do
			Kit.Tween(danger, { Transparency = 0.25 }, 0.18)
			task.wait(0.2)
			Kit.Tween(danger, { Transparency = 0.6 }, 0.18)
			task.wait(0.2)
		end
	end)
	task.wait(t.Duration)
	pulse = false
	danger:Destroy()
	safe:Destroy()
	controllers.EffectsController:Shockwave(center, t.Color, t.Radius, 0.5, 3)
	impact(center, t.Color, t.Radius)
end

function telegraphs.Meteor(t)
	local y = groundAt(t.Position)
	local center = Vector3.new(t.Position.X, y + 0.12, t.Position.Z)
	local outline = disc(center, t.Radius, rgb(255, 120, 40), 0.4)
	local rock = fxPart({
		Shape = Enum.PartType.Ball, Size = Vector3.new(4, 4, 4), Color = t.Color, Material = Enum.Material.Neon,
		CFrame = CFrame.new(center + Vector3.new(18, 90, 10)),
	})
	local fire = Instance.new("Fire")
	fire.Size = 8
	fire.Heat = 12
	fire.Color = t.Color
	fire.SecondaryColor = rgb(255, 230, 120)
	fire.Parent = rock
	Kit.Tween(rock, { CFrame = CFrame.new(center + Vector3.new(0, 1.5, 0)) }, t.Duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	Kit.Tween(outline, { Transparency = 0.1 }, t.Duration)
	task.wait(t.Duration)
	rock:Destroy()
	outline:Destroy()
	controllers.EffectsController:Sphere(center, rgb(255, 150, 60), 2, t.Radius * 2, 0.35)
	impact(center, t.Color, t.Radius * 1.2)
end

function telegraphs.Line(t)
	local y = groundAt(t.Position)
	local start = Vector3.new(t.Position.X, y + 0.14, t.Position.Z)
	local dir = Vector3.new(t.Direction.X, 0, t.Direction.Z).Unit
	local base = CFrame.lookAt(start, start + dir)
	local lane = fxPart({
		Size = Vector3.new(t.Width, 0.2, t.Length), CFrame = base * CFrame.new(0, 0, -t.Length / 2),
		Color = rgb(255, 60, 40), Transparency = 0.6,
	})
	local filler = fxPart({
		Size = Vector3.new(t.Width, 0.24, 0.1), CFrame = base * CFrame.new(0, 0.02, -0.05),
		Color = rgb(255, 60, 40), Transparency = 0.25,
	})
	Kit.Tween(filler, { Size = Vector3.new(t.Width, 0.24, t.Length), CFrame = base * CFrame.new(0, 0.02, -t.Length / 2) }, t.Duration, Enum.EasingStyle.Linear)
	task.wait(t.Duration)
	lane:Destroy()
	filler:Destroy()
	-- dust trail along the charge
	for i = 0, 4 do
		local p = start + dir * (t.Length * i / 4)
		task.delay(i * 0.05, function()
			controllers.EffectsController:Burst(p + Vector3.new(0, 1, 0), "Smoke", 8, { Color = ColorSequence.new(t.Color:Lerp(rgb(80, 70, 60), 0.6)) })
		end)
	end
	if near(start + dir * t.Length / 2, t.Length) then
		controllers.SoundController:Play("BossSlam", 0.7, 1.2)
		controllers.CameraController:Shake(0.25)
	end
end

function telegraphs.Summon(t)
	local y = groundAt(t.Position)
	local center = Vector3.new(t.Position.X, y + 0.12, t.Position.Z)
	local ring = disc(center, t.Radius, rgb(120, 40, 200), 0.3)
	controllers.EffectsController:Pillar(center, rgb(120, 40, 200), 40, t.Duration + 0.3)
	task.wait(t.Duration)
	ring:Destroy()
	controllers.EffectsController:Burst(center + Vector3.new(0, 2, 0), "Shadow", 30)
end

-- ===== Boss bar =====
local function findNearestBoss(): Model?
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local best, bestDist = nil, 150
	for _, model in ipairs(CollectionService:GetTagged("Enemy")) do
		if model:IsA("Model") and model:GetAttribute("IsBoss") and not model:GetAttribute("Dead") and model.PrimaryPart then
			local d = (model.PrimaryPart.Position - root.Position).Magnitude
			if d < bestDist then
				best, bestDist = model, d
			end
		end
	end
	return best
end

local function setTracked(model: Model?)
	if model == tracked then
		return
	end
	tracked = model
	if model then
		nameLabel.Text = "👹 " .. tostring(model:GetAttribute("DisplayName") or "Boss") .. "  Lv " .. tostring(model:GetAttribute("Level") or "?")
		shownRatio = 1
		chunk.Size = UDim2.fromScale(1, 1)
		bar.Visible = true
		local scale = bar:FindFirstChildOfClass("UIScale") :: UIScale
		scale.Scale = 0.6
		Kit.Tween(scale, { Scale = 1 }, 0.3, Enum.EasingStyle.Back)
	else
		bar.Visible = false
	end
end

local function updateBar()
	local model = tracked
	if not model then
		return
	end
	local hp = model:GetAttribute("Health") or 0
	local max = model:GetAttribute("MaxHealth") or 1
	local ratio = math.clamp(hp / max, 0, 1)
	fill.Size = UDim2.fromScale(ratio, 1)
	hpLabel.Text = Format.Abbrev(hp) .. " / " .. Format.Abbrev(max)
	if ratio < shownRatio - 0.001 then
		shownRatio = ratio
		task.delay(0.3, function()
			if tracked == model then
				Kit.Tween(chunk, { Size = UDim2.fromScale(shownRatio, 1) }, 0.4)
			end
		end)
	elseif ratio > shownRatio then
		shownRatio = ratio
		chunk.Size = UDim2.fromScale(ratio, 1)
	end
	enragedTag.Visible = model:GetAttribute("Enraged") == true
end

local function buildBar()
	local root = controllers.UIController:Root("HUD")
	bar = Kit.Panel({
		Name = "BossBar", Size = UDim2.fromOffset(560, 64), Position = UDim2.new(0.5, 0, 0, 96), AnchorPoint = Vector2.new(0.5, 0),
		Color = Theme.Bg, Transparency = 0.2, StrokeColor = rgb(200, 50, 60), StrokeThickness = 2.5, Radius = 14, Visible = false, Parent = root,
	})
	Kit.New("UIScale", { Parent = bar })
	nameLabel = Kit.Label({ Text = "", Font = Theme.FontTitle, TextSize = 22, Color = rgb(255, 110, 110), XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 4), StrokeThickness = 2, Parent = bar })
	local back = Kit.New("Frame", { BackgroundColor3 = rgb(20, 14, 24), BorderSizePixel = 0, Size = UDim2.new(1, -24, 0, 20), Position = UDim2.fromOffset(12, 34), ClipsDescendants = true, Parent = bar })
	Kit.Corner(8).Parent = back
	chunk = Kit.New("Frame", { BackgroundColor3 = rgb(255, 240, 200), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = back })
	Kit.Corner(8).Parent = chunk
	fill = Kit.New("Frame", { BackgroundColor3 = rgb(230, 40, 60), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = back })
	Kit.Corner(8).Parent = fill
	Kit.Gradient(rgb(255, 90, 100), rgb(170, 20, 40)).Parent = fill
	hpLabel = Kit.Label({ Text = "", Font = Theme.FontNumber, TextSize = 14, XAlign = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = back })
	enragedTag = Kit.Label({ Text = "ENRAGED", Font = Theme.FontTitle, TextSize = 18, Color = rgb(255, 60, 40), Size = UDim2.fromOffset(100, 24), Position = UDim2.new(1, -12, 0, 4), AnchorPoint = Vector2.new(1, 0), XAlign = Enum.TextXAlignment.Right, Visible = false, Parent = bar })
end

function BossController:Start(c)
	controllers = c
	Kit, Theme = c.Kit, c.Theme
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "BossFX"
	fxFolder.Parent = workspace
	buildBar()

	Net.Event("BossTelegraph").OnClientEvent:Connect(function(t)
		local fn = telegraphs[t.Kind]
		if fn then
			task.spawn(fn, t)
		end
	end)

	Net.Event("BossEvent").OnClientEvent:Connect(function(info)
		local color = info.Color or Theme.Accent
		if info.Type == "Spawn" then
			local data = c.DataController:Get()
			local here = data and data.LastZone == info.ZoneId
			if here then
				c.SoundController:Play("BossSpawn")
				c.NotificationController:Banner("BOSS APPEARED", info.Name .. " in " .. info.Zone, color, 3)
				c.CameraController:Shake(0.3)
			else
				c.NotificationController:Toast("👹 " .. info.Name .. " appeared in " .. info.Zone, color)
			end
			if c.HUD then
				c.HUD:SetBadge("Areas", true)
			end
		elseif info.Type == "Defeated" then
			local by = if info.By and info.By ~= "" then "Defeated by " .. info.By else "Defeated!"
			local data = c.DataController:Get()
			local zone = data and Zones.Get(data.LastZone)
			if zone and zone.Name == info.Zone then
				c.NotificationController:Callout(info.Name .. " has fallen", by, Theme.Gold, "Trophy", 4)
			else
				c.NotificationController:Callout(info.Name .. " was defeated", info.Zone, Theme.Gold, "Trophy", 3)
			end
		elseif info.Type == "Enrage" then
			c.NotificationController:Banner("ENRAGED!", info.Name .. " grows stronger", rgb(255, 60, 40), 1.8)
			c.EffectsController:Vignette(rgb(255, 40, 20), 0.5, 1)
			c.CameraController:Shake(0.3)
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.5 then
			acc = 0
			setTracked(findNearestBoss())
		end
		if tracked and (not tracked.Parent or tracked:GetAttribute("Dead")) then
			setTracked(nil)
		end
		updateBar()
	end)
end

return BossController
