--[[
	EffectsController: all client-side juice. Damage numbers (pooled billboards),
	hit sparks, death bursts + kill effects, coins flying into the HUD, XP pops,
	shockwaves, pillars of light, and screen-edge vignettes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Particles = require(Shared.Visuals.Particles)
local Format = require(Shared.Util.Format)

local EffectsController = {}

local Kit, Theme, controllers
local fxFolder: Folder
local damagePool: { BillboardGui } = {}
local showDamageNumbers = true
local lowGraphics = false
local vignetteFrames: { Frame } = {}

local rgb = Color3.fromRGB

local function tween(obj, props, t, style, dir)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function fxPart(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Neon
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = fxFolder
	return p
end
EffectsController.Part = fxPart

-- One-shot particle burst at a position.
function EffectsController:Burst(position: Vector3, preset: string, count: number, overrides: { [string]: any }?)
	if lowGraphics then
		count = math.ceil(count * 0.4)
	end
	local holder = fxPart(Vector3.new(0.2, 0.2, 0.2), CFrame.new(position), Color3.new(), Enum.Material.SmoothPlastic)
	holder.Transparency = 1
	local o = overrides and table.clone(overrides) or {}
	o.Rate = 0
	local emitter = Particles.Create(preset, holder, o)
	if emitter then
		emitter:Emit(count)
	end
	Debris:AddItem(holder, 3)
end

-- ===== Damage numbers =====
local function getDamageGui(): BillboardGui
	local gui = table.remove(damagePool)
	if gui then
		return gui
	end
	local g = Instance.new("BillboardGui")
	g.Size = UDim2.fromOffset(220, 70)
	g.AlwaysOnTop = true
	g.LightInfluence = 0
	g.MaxDistance = 150
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Theme.FontTitle
	label.TextScaled = true
	label.Parent = g
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = label
	local scale = Instance.new("UIScale")
	scale.Parent = label
	return g
end

function EffectsController:DamageNumber(position: Vector3, amount: number, crit: boolean, color: Color3?)
	if not showDamageNumbers then
		return
	end
	local gui = getDamageGui()
	local anchor = fxPart(Vector3.new(0.1, 0.1, 0.1), CFrame.new(position + Vector3.new((math.random() - 0.5) * 3, 0, (math.random() - 0.5) * 3)), Color3.new(), Enum.Material.SmoothPlastic)
	anchor.Transparency = 1
	gui.Adornee = anchor
	gui.Parent = fxFolder
	local label = gui:FindFirstChild("Text") :: TextLabel
	local scale = label:FindFirstChildOfClass("UIScale") :: UIScale
	label.Text = (if crit then "💥" else "") .. Format.Abbrev(amount)
	label.TextColor3 = color or (if crit then rgb(255, 214, 60) else rgb(255, 255, 255))
	label.TextTransparency = 0
	gui.Size = if crit then UDim2.fromOffset(260, 84) else UDim2.fromOffset(200, 60)
	gui.StudsOffsetWorldSpace = Vector3.zero
	scale.Scale = if crit then 1.8 else 1.3
	tween(scale, { Scale = 1 }, 0.18, Enum.EasingStyle.Back)
	tween(gui, { StudsOffsetWorldSpace = Vector3.new(0, 3.5, 0) }, 0.8)
	task.delay(0.45, function()
		tween(label, { TextTransparency = 1 }, 0.35)
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 0
			tween(stroke, { Transparency = 1 }, 0.35)
		end
	end)
	task.delay(0.85, function()
		gui.Adornee = nil
		gui.Parent = nil
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 0
		end
		anchor:Destroy()
		if #damagePool < 40 then
			table.insert(damagePool, gui)
		else
			gui:Destroy()
		end
	end)
end

-- ===== Hits =====
function EffectsController:HitSpark(position: Vector3, color: Color3, crit: boolean)
	self:Burst(position, "Sparkle", if crit then 22 else 10, {
		Color = ColorSequence.new(Color3.new(1, 1, 1), color),
		Speed = NumberRange.new(8, 18), Lifetime = NumberRange.new(0.15, 0.35),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, if crit then 0.9 else 0.6), NumberSequenceKeypoint.new(1, 0) }),
	})
	-- slash streak
	local cf = CFrame.new(position) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
	local streak = fxPart(Vector3.new(0.15, 0.15, if crit then 7 else 5), cf, color:Lerp(Color3.new(1, 1, 1), 0.5))
	tween(streak, { Size = Vector3.new(0.02, 0.02, (if crit then 9 else 6.5)), Transparency = 1 }, 0.18)
	Debris:AddItem(streak, 0.25)
	if crit then
		local flash = fxPart(Vector3.new(1, 1, 1), CFrame.new(position), rgb(255, 230, 120), Enum.Material.Neon, Enum.PartType.Ball)
		flash.Transparency = 0.2
		tween(flash, { Size = Vector3.new(5, 5, 5), Transparency = 1 }, 0.22)
		Debris:AddItem(flash, 0.3)
	end
end

function EffectsController:Shockwave(position: Vector3, color: Color3, radius: number, duration: number?, height: number?)
	local ring = fxPart(Vector3.new(height or 0.4, 1, 1), CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2), color, Enum.Material.Neon, Enum.PartType.Cylinder)
	ring.Transparency = 0.1
	tween(ring, { Size = Vector3.new(height or 0.4, radius * 2, radius * 2), Transparency = 1 }, duration or 0.45)
	Debris:AddItem(ring, (duration or 0.45) + 0.1)
end

function EffectsController:Pillar(position: Vector3, color: Color3, height: number, duration: number?)
	local p = fxPart(Vector3.new(height, 3, 3), CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), color, Enum.Material.Neon, Enum.PartType.Cylinder)
	p.Transparency = 0.2
	tween(p, { Size = Vector3.new(height, 0.2, 0.2), Transparency = 1 }, duration or 0.8)
	Debris:AddItem(p, (duration or 0.8) + 0.1)
end

function EffectsController:Sphere(position: Vector3, color: Color3, fromSize: number, toSize: number, duration: number, material: Enum.Material?)
	local s = fxPart(Vector3.new(fromSize, fromSize, fromSize), CFrame.new(position), color, material or Enum.Material.ForceField, Enum.PartType.Ball)
	s.Transparency = 0.1
	tween(s, { Size = Vector3.new(toSize, toSize, toSize), Transparency = 1 }, duration)
	Debris:AddItem(s, duration + 0.1)
end

-- ===== Deaths =====
local KILL_EFFECTS = {
	kill_sakura = function(self, pos)
		self:Burst(pos, "Petals", 40, { Speed = NumberRange.new(6, 14), Lifetime = NumberRange.new(0.8, 1.4) })
	end,
	kill_lightning = function(self, pos)
		local bolt = fxPart(Vector3.new(0.8, 60, 0.8), CFrame.new(pos + Vector3.new(0, 30, 0)), rgb(200, 240, 255))
		tween(bolt, { Transparency = 1, Size = Vector3.new(0.1, 60, 0.1) }, 0.3)
		Debris:AddItem(bolt, 0.35)
		self:Burst(pos, "Lightning", 30)
		controllers.CameraController:Shake(0.2)
	end,
	kill_gold = function(self, pos)
		self:Burst(pos, "Radiance", 40, { Speed = NumberRange.new(10, 20) })
		for _ = 1, 8 do
			local coin = fxPart(Vector3.new(0.2, 1.2, 1.2), CFrame.new(pos) * CFrame.Angles(0, math.random() * 6, 0), rgb(255, 205, 60), Enum.Material.Foil, Enum.PartType.Cylinder)
			local target = pos + Vector3.new((math.random() - 0.5) * 12, math.random() * 6 + 2, (math.random() - 0.5) * 12)
			tween(coin, { CFrame = CFrame.new(target) * CFrame.Angles(math.random() * 6, math.random() * 6, 0), Transparency = 1 }, 0.7)
			Debris:AddItem(coin, 0.75)
		end
	end,
	kill_void = function(self, pos)
		local s = fxPart(Vector3.new(12, 12, 12), CFrame.new(pos), rgb(200, 60, 255), Enum.Material.ForceField, Enum.PartType.Ball)
		tween(s, { Size = Vector3.new(0.5, 0.5, 0.5), Transparency = 0.6 }, 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Debris:AddItem(s, 0.4)
		task.delay(0.35, function()
			self:Burst(pos, "Void", 40, { Speed = NumberRange.new(8, 16) })
		end)
	end,
}

function EffectsController:FadeModel(model: Model, duration: number)
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		elseif d:IsA("ParticleEmitter") then
			d.Enabled = false
		end
	end
	local start = os.clock()
	task.spawn(function()
		while os.clock() - start < duration do
			local k = (os.clock() - start) / duration
			for _, p in ipairs(parts) do
				p.LocalTransparencyModifier = k
			end
			task.wait()
		end
		for _, p in ipairs(parts) do
			p.LocalTransparencyModifier = 1
		end
	end)
end

function EffectsController:EnemyDied(info)
	local pos = info.Position
	local color = info.Color or rgb(255, 255, 255)
	local model = controllers.AnimationController:GetEnemyModel(info.Uid)
	if model then
		task.delay(0.35, function()
			if model.Parent then
				self:FadeModel(model, 0.6)
			end
		end)
	end
	local center = pos + Vector3.new(0, (info.Height or 5) * 0.3, 0)
	self:Burst(center, "Smoke", if info.IsBoss then 40 else 14, { Color = ColorSequence.new(rgb(240, 240, 240)), Speed = NumberRange.new(4, 9), Lifetime = NumberRange.new(0.5, 0.9) })
	self:Burst(center, "Sparkle", if info.IsBoss then 60 else 18, { Color = ColorSequence.new(Color3.new(1, 1, 1), color), Speed = NumberRange.new(8, 16) })
	self:Shockwave(pos + Vector3.new(0, 0.3, 0), color, if info.IsBoss then 40 else 10, if info.IsBoss then 0.9 else 0.4)
	-- rising soul orb
	local orb = fxPart(Vector3.new(1.2, 1.2, 1.2), CFrame.new(center), color, Enum.Material.Neon, Enum.PartType.Ball)
	tween(orb, { CFrame = CFrame.new(center + Vector3.new(0, 7, 0)), Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1 }, 0.7)
	Debris:AddItem(orb, 0.75)
	local killEffect = KILL_EFFECTS[info.KillEffect]
	if killEffect then
		killEffect(self, center)
	end
	if info.IsBoss then
		controllers.CameraController:Shake(0.7)
		self:Pillar(pos, color, 120, 1.5)
		self:Sphere(center, color, 4, 60, 1.2)
	end
end

-- ===== HUD-bound effects =====
function EffectsController:CoinFly(worldPos: Vector3, amount: number)
	local hud = controllers.HUD
	if not hud then
		return
	end
	local target = hud:GetCoinTarget()
	local camera = workspace.CurrentCamera
	local screen, onScreen = camera:WorldToViewportPoint(worldPos)
	local root = controllers.UIController:Root("Overlay")
	local scale = controllers.UIController.Scale
	local start = if onScreen then Vector2.new(screen.X, screen.Y) / scale else Vector2.new(640, 360)
	local count = math.clamp(math.floor(math.log10(math.max(amount, 1)) * 2) + 2, 3, if lowGraphics then 4 else 9)
	for i = 1, count do
		local coin = Kit.Icon(root, "Coin", {
			Size = UDim2.fromOffset(38, 38), AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(start.X, start.Y), ZIndex = 20,
		})
		local burst = start + Vector2.new((math.random() - 0.5) * 140, (math.random() - 0.7) * 110)
		tween(coin, { Position = UDim2.fromOffset(burst.X, burst.Y) }, 0.22, Enum.EasingStyle.Quad)
		task.delay(0.22 + i * 0.045, function()
			local t = tween(coin, { Position = UDim2.fromOffset(target.X, target.Y), Size = UDim2.fromOffset(24, 24) }, 0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			t.Completed:Wait()
			coin:Destroy()
			hud:PulseCoins()
			if i == 1 or i == count then
				controllers.SoundController:Play("Coin")
			end
		end)
	end
end

function EffectsController:FloatText(text: string, color: Color3, screenPos: Vector2, size: number?)
	local root = controllers.UIController:Root("Overlay")
	local label = Kit.Label({
		Text = text, Font = Theme.FontTitle, TextSize = size or 26, Color = color, XAlign = Enum.TextXAlignment.Center,
		Size = UDim2.fromOffset(300, 34), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(screenPos.X, screenPos.Y),
		ZIndex = 20, StrokeThickness = 2, Parent = root,
	})
	local scale = Kit.New("UIScale", { Scale = 0.5, Parent = label })
	tween(scale, { Scale = 1 }, 0.2, Enum.EasingStyle.Back)
	tween(label, { Position = UDim2.fromOffset(screenPos.X, screenPos.Y - 40) }, 0.9)
	task.delay(0.6, function()
		tween(label, { TextTransparency = 1 }, 0.3)
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			tween(stroke, { Transparency = 1 }, 0.3)
		end
		task.wait(0.32)
		label:Destroy()
	end)
end

-- Colored glow on the screen edges (level up = gold, hurt = red, ...)
function EffectsController:Vignette(color: Color3, strength: number, duration: number)
	for _, frame in ipairs(vignetteFrames) do
		frame.BackgroundColor3 = color
		local grad = frame:FindFirstChildOfClass("UIGradient") :: UIGradient
		grad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1 - strength), NumberSequenceKeypoint.new(1, 1),
		})
		frame.BackgroundTransparency = 0
		frame.Visible = true
	end
	task.delay(duration * 0.3, function()
		for _, frame in ipairs(vignetteFrames) do
			tween(frame, { BackgroundTransparency = 1 }, duration * 0.7)
		end
	end)
end

function EffectsController:Flash(color: Color3, duration: number)
	local root = controllers.UIController:Root("Overlay")
	local f = Kit.New("Frame", {
		BackgroundColor3 = color, BackgroundTransparency = 0.1, Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, ZIndex = 30, Parent = root,
	})
	tween(f, { BackgroundTransparency = 1 }, duration)
	Debris:AddItem(f, duration + 0.1)
end

function EffectsController:CharacterBurst(color: Color3, big: boolean?)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local feet = root.Position - Vector3.new(0, 2.8, 0)
	self:Shockwave(feet, color, if big then 30 else 14, if big then 0.8 else 0.5)
	if big then
		task.delay(0.15, function()
			self:Shockwave(feet, Color3.new(1, 1, 1), 22, 0.7)
		end)
	end
	self:Pillar(feet, color, if big then 80 else 30, if big then 1.2 else 0.7)
	self:Burst(root.Position, "Radiance", if big then 90 else 35, { Color = ColorSequence.new(Color3.new(1, 1, 1), color), Speed = NumberRange.new(6, 16) })
end

function EffectsController:Start(c)
	controllers = c
	Kit, Theme = c.Kit, c.Theme
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "ClientFX"
	fxFolder.Parent = workspace

	-- vignette edges
	local root = c.UIController:Root("Overlay")
	local edges = {
		{ Size = UDim2.new(1, 0, 0.22, 0), Position = UDim2.new(), Rotation = 90 },
		{ Size = UDim2.new(1, 0, 0.22, 0), Position = UDim2.new(0, 0, 0.78, 0), Rotation = -90 },
		{ Size = UDim2.new(0.16, 0, 1, 0), Position = UDim2.new(), Rotation = 0 },
		{ Size = UDim2.new(0.16, 0, 1, 0), Position = UDim2.new(0.84, 0, 0, 0), Rotation = 180 },
	}
	for _, e in ipairs(edges) do
		local f = Kit.New("Frame", {
			BackgroundTransparency = 1, BorderSizePixel = 0, Size = e.Size, Position = e.Position, ZIndex = 1, Name = "Vignette", Parent = root,
		})
		Kit.New("UIGradient", { Rotation = e.Rotation, Transparency = NumberSequence.new(0, 1), Parent = f })
		table.insert(vignetteFrames, f)
	end

	c.DataController:OnChange("Settings", function(settings)
		showDamageNumbers = settings.DamageNumbers
		lowGraphics = settings.LowGraphics
	end)
end

return EffectsController
