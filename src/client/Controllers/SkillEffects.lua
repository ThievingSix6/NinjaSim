--[[
	SkillEffects: the look of every skill (Config/Skills), client side only.
	Poses (Util/Pose keyframes played through AnimationController:PlayPose), neon
	parts, particle bursts, trails, after-images, camera shake and the local dash
	movement. The server decides what is hit; these only draw it.

	Per skill:
	  Start(ctx)          right away when cast (pose, wind-up, local movement)
	  Result(ctx, info)   when the server's answer arrives (targets, centres)
	  Hit(ctx, hit, tag)  optional: extra effect per enemy hit
	ctx: { Character, Root, Dir, Origin, Def, Level, Local (our own cast) }
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Skills = require(Shared.Config.Skills)
local Particles = require(Shared.Visuals.Particles)

local SkillEffects = {}

local controllers
local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local active: { { Start: number, Duration: number, Fn: (number) -> (), Done: (() -> ())? } } = {}
local clonesBy: { [number]: { Models: { Model }, Busy: { number }, Until: number, Owner: Model } } = {}

-- ===== helpers =====
local function fx(): any
	return controllers.EffectsController
end

local function part(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): BasePart
	return fx().Part(size, cf, color, material, shape)
end

local function tween(obj: Instance, props: { [string]: any }, t: number, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function lowGraphics(): boolean
	local data = controllers.DataController:Get()
	return data ~= nil and data.Settings.LowGraphics == true
end

-- Runs fn(k) every frame for `duration` seconds (k goes 0 -> 1).
local function animate(duration: number, fn: (number) -> (), done: (() -> ())?)
	table.insert(active, { Start = os.clock(), Duration = math.max(duration, 0.01), Fn = fn, Done = done })
end

local warned: { [string]: boolean } = {}
local function step()
	local now = os.clock()
	for i = #active, 1, -1 do
		local a = active[i]
		local k = math.clamp((now - a.Start) / a.Duration, 0, 1)
		local ok, err = pcall(a.Fn, k)
		if not ok and not warned[tostring(err)] then
			warned[tostring(err)] = true
			warn("[SkillEffects] " .. tostring(err))
		end
		if k >= 1 or not ok then
			table.remove(active, i)
			if a.Done then
				pcall(a.Done)
			end
		end
	end
end

local function feet(root: BasePart): Vector3
	return root.Position - Vector3.new(0, 2.9, 0)
end

local function shake(ctx, amount: number)
	if ctx.Local then
		controllers.CameraController:Shake(amount)
	end
end

local function sound(name: string, volume: number?, pitch: number?)
	controllers.SoundController:Play(name, volume, pitch)
end

local function rotateY(v: Vector3, angle: number): Vector3
	local c, s = math.cos(angle), math.sin(angle)
	return Vector3.new(v.X * c - v.Z * s, 0, v.X * s + v.Z * c)
end

local function addTrail(p: BasePart, color: Color3, width: number, life: number)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, width / 2, 0)
	a0.Parent = p
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -width / 2, 0)
	a1.Parent = p
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(WHITE, color)
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.Lifetime = life
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Parent = p
	return trail
end

-- A straight neon streak from a to b that thins and fades.
local function streak(a: Vector3, b: Vector3, color: Color3, width: number, life: number)
	local len = (b - a).Magnitude
	if len < 0.05 then
		return
	end
	local p = part(Vector3.new(width, width, len), CFrame.lookAt((a + b) / 2, b), color)
	p.Transparency = 0.05
	tween(p, { Size = Vector3.new(width * 0.15, width * 0.15, len * 1.05), Transparency = 1 }, life)
	Debris:AddItem(p, life + 0.05)
end

-- A jagged lightning bolt between two points.
local function bolt(a: Vector3, b: Vector3, color: Color3, width: number, life: number)
	local segments = 6
	local prev = a
	local dir = b - a
	local side = dir:Cross(Vector3.yAxis)
	side = if side.Magnitude > 0.01 then side.Unit else Vector3.xAxis
	for i = 1, segments do
		local p = a + dir * (i / segments)
		if i < segments then
			p += side * (math.random() - 0.5) * 3 + Vector3.new(0, (math.random() - 0.5) * 2.4, 0)
		end
		streak(prev, p, color, width, life)
		prev = p
	end
end

-- Neon ring on the ground that grows to `radius`.
local function ring(center: Vector3, color: Color3, radius: number, duration: number, height: number?)
	fx():Shockwave(center + Vector3.new(0, 0.2, 0), color, radius, duration, height)
end

-- Translucent copy of the character's outline left behind on a dash.
local function afterImage(cf: CFrame, color: Color3, life: number)
	local torso = part(Vector3.new(2.2, 2.6, 1.2), cf, color, Enum.Material.ForceField)
	torso.Transparency = 0.2
	local head = part(Vector3.new(1.3, 1.3, 1.3), cf * CFrame.new(0, 2, 0), color, Enum.Material.ForceField, Enum.PartType.Ball)
	head.Transparency = 0.2
	local legs = part(Vector3.new(1.8, 2.2, 1), cf * CFrame.new(0, -2.4, 0), color, Enum.Material.ForceField)
	legs.Transparency = 0.2
	for _, p in ipairs({ torso, head, legs }) do
		tween(p, { Transparency = 1 }, life)
		Debris:AddItem(p, life + 0.05)
	end
end

-- Moves our own character along `dir` (it owns its physics, the server allowed it).
local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Include
local function clearLength(origin: Vector3, dir: Vector3, length: number): number
	local filter: { Instance } = { workspace.Terrain }
	local world = workspace:FindFirstChild("World")
	if world then
		table.insert(filter, world)
	end
	wallParams.FilterDescendantsInstances = filter
	local hit = workspace:Raycast(origin, dir * (length + 2), wallParams)
	return if hit then math.max(0, hit.Distance - 2) else length
end

local function dash(ctx, length: number, duration: number, color: Color3)
	local root = ctx.Root :: BasePart
	if not ctx.Local or not root.Parent then
		return
	end
	length = clearLength(root.Position, ctx.Dir, length)
	local start = root.Position
	local facing = CFrame.lookAt(Vector3.zero, ctx.Dir)
	local lastImage = 0
	animate(duration, function(k)
		local e = 1 - (1 - k) ^ 2
		root.CFrame = CFrame.new(start + ctx.Dir * length * e + Vector3.new(0, root.Position.Y - start.Y, 0)) * facing
		root.AssemblyLinearVelocity = Vector3.new(0, math.min(root.AssemblyLinearVelocity.Y, 0), 0)
		if k - lastImage > 0.2 then
			lastImage = k
			afterImage(root.CFrame, color, 0.35)
		end
	end)
end

local function blink(ctx, length: number, color: Color3)
	local root = ctx.Root :: BasePart
	if not ctx.Local or not root.Parent then
		return
	end
	length = clearLength(root.Position, ctx.Dir, length)
	afterImage(root.CFrame, color, 0.5)
	root.CFrame = CFrame.new(root.Position + ctx.Dir * length) * CFrame.lookAt(Vector3.zero, ctx.Dir)
	root.AssemblyLinearVelocity = Vector3.zero
end

local function hand(ctx): Vector3
	local root = ctx.Root :: BasePart
	return root.Position + ctx.Dir * 1.5 + Vector3.new(0, 0.6, 0)
end

-- ===== poses (Util/Pose sign guide) =====
local STANCE = { RightHip = { 30, 0, 10 }, RightKnee = { -45, 0, 0 }, LeftHip = { -15, 0, -10 }, LeftKnee = { -30, 0, 0 } }
local function withStance(key)
	for k, v in pairs(STANCE) do
		if key[k] == nil then
			key[k] = v
		end
	end
	return key
end

local POSES = {
	Throw = {
		Keys = {
			withStance({ T = 0.3, Ease = "Out", RootPos = { 0, -0.3, 0 }, Root = { 0, 25, 0 }, Waist = { 0, 25, 0 }, Neck = { 0, -30, 0 },
				RightShoulder = { 80, 60, 0 }, RightElbow = { 95, 0, 0 }, LeftShoulder = { 40, 0, -30 }, LeftElbow = { 40, 0, 0 } }),
			withStance({ T = 0.5, Ease = "Snap", RootPos = { 0, -0.4, 0 }, Root = { 0, -20, 0 }, Waist = { -5, -30, 0 }, Neck = { 0, 30, 0 },
				RightShoulder = { 85, -55, 0 }, RightElbow = { 5, 0, 0 }, RightWrist = { -40, 0, 0 }, LeftShoulder = { -20, 0, -45 }, LeftElbow = { 20, 0, 0 } }),
			withStance({ T = 0.8, Ease = "Out", RootPos = { 0, -0.4, 0 }, Root = { 0, -25, 0 }, Waist = { -5, -30, 0 }, Neck = { 0, 30, 0 },
				RightShoulder = { 75, -60, 0 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { -20, 0, -45 }, LeftElbow = { 20, 0, 0 } }),
		},
	},
	Spin = {
		Trail = { 0.1, 0.88 },
		Keys = {
			{ T = 0.12, Ease = "Out", RootPos = { 0, -0.7, 0 }, Root = { 0, 40, 0 }, Waist = { 0, 15, 0 },
				RightShoulder = { 10, 0, 85 }, RightElbow = { 5, 0, 0 }, RightWrist = { -60, 0, 0 }, LeftShoulder = { 10, 0, -85 }, LeftElbow = { 5, 0, 0 },
				RightHip = { 30, 0, 22 }, RightKnee = { -55, 0, 0 }, LeftHip = { 30, 0, -22 }, LeftKnee = { -55, 0, 0 } },
			{ T = 0.5, Ease = "Linear", RootPos = { 0, -0.7, 0 }, Root = { 0, -330, 0 }, Waist = { 0, -15, 0 },
				RightShoulder = { 10, 0, 85 }, RightElbow = { 5, 0, 0 }, RightWrist = { -60, 0, 0 }, LeftShoulder = { 10, 0, -85 }, LeftElbow = { 5, 0, 0 },
				RightHip = { 30, 0, 22 }, RightKnee = { -55, 0, 0 }, LeftHip = { 30, 0, -22 }, LeftKnee = { -55, 0, 0 } },
			{ T = 0.88, Ease = "Out", RootPos = { 0, -0.7, 0 }, Root = { 0, -720, 0 }, Waist = { 0, -15, 0 },
				RightShoulder = { 10, 0, 85 }, RightElbow = { 5, 0, 0 }, RightWrist = { -60, 0, 0 }, LeftShoulder = { 10, 0, -85 }, LeftElbow = { 5, 0, 0 },
				RightHip = { 30, 0, 22 }, RightKnee = { -55, 0, 0 }, LeftHip = { 30, 0, -22 }, LeftKnee = { -55, 0, 0 } },
		},
	},
	Draw = {
		Trail = { 0.22, 0.55 },
		Keys = {
			{ T = 0.22, Ease = "Out", RootPos = { 0, -0.9, 0 }, Root = { -20, 30, 0 }, Waist = { -10, 20, 0 }, Neck = { 10, -25, 0 },
				RightShoulder = { 30, 55, 0 }, RightElbow = { 85, 0, 0 }, RightWrist = { -30, -90, 0 }, LeftShoulder = { 25, -20, 0 }, LeftElbow = { 70, 0, 0 },
				RightHip = { 60, 0, 10 }, RightKnee = { -90, 0, 0 }, LeftHip = { -30, 0, -10 }, LeftKnee = { -30, 0, 0 } },
			{ T = 0.4, Ease = "Snap", RootPos = { 0, -1, 0 }, Root = { -25, -35, 0 }, Waist = { -10, -25, 0 }, Neck = { 10, 40, 0 },
				RightShoulder = { 85, -75, 10 }, RightElbow = { 0, 0, 0 }, RightWrist = { -50, -90, 0 }, LeftShoulder = { -25, 0, -40 }, LeftElbow = { 15, 0, 0 },
				RightHip = { 70, 0, 10 }, RightKnee = { -70, 0, 0 }, LeftHip = { -40, 0, -10 }, LeftKnee = { -20, 0, 0 } },
			{ T = 0.8, Ease = "Out", RootPos = { 0, -1, 0 }, Root = { -20, -40, 0 }, Waist = { -10, -25, 0 }, Neck = { 10, 40, 0 },
				RightShoulder = { 80, -80, 10 }, RightElbow = { 5, 0, 0 }, RightWrist = { -50, -90, 0 }, LeftShoulder = { -25, 0, -40 }, LeftElbow = { 15, 0, 0 },
				RightHip = { 70, 0, 10 }, RightKnee = { -70, 0, 0 }, LeftHip = { -40, 0, -10 }, LeftKnee = { -20, 0, 0 } },
		},
	},
	Slam = {
		Trail = { 0.3, 0.55 },
		Keys = {
			{ T = 0.35, Ease = "Out", Root = { 15, 0, 0 }, Waist = { 10, 0, 0 }, Neck = { -10, 0, 0 },
				RightShoulder = { 170, 0, 15 }, RightElbow = { 20, 0, 0 }, RightWrist = { -40, 0, 0 }, LeftShoulder = { 170, 0, -15 }, LeftElbow = { 20, 0, 0 },
				RightHip = { 60, 0, 5 }, RightKnee = { -100, 0, 0 }, LeftHip = { 60, 0, -5 }, LeftKnee = { -100, 0, 0 } },
			{ T = 0.5, Ease = "Snap", RootPos = { 0, -1.2, 0 }, Root = { -35, 0, 0 }, Waist = { -15, 0, 0 }, Neck = { 15, 0, 0 },
				RightShoulder = { 70, 0, 15 }, RightElbow = { 10, 0, 0 }, RightWrist = { -50, 0, 0 }, LeftShoulder = { 70, 0, -15 }, LeftElbow = { 10, 0, 0 },
				RightHip = { 80, 0, 15 }, RightKnee = { -110, 0, 0 }, LeftHip = { -10, 0, -15 }, LeftKnee = { -60, 0, 0 } },
			{ T = 0.85, Ease = "Out", RootPos = { 0, -1.1, 0 }, Root = { -30, 0, 0 }, Waist = { -15, 0, 0 }, Neck = { 15, 0, 0 },
				RightShoulder = { 65, 0, 15 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 65, 0, -15 }, LeftElbow = { 10, 0, 0 },
				RightHip = { 80, 0, 15 }, RightKnee = { -110, 0, 0 }, LeftHip = { -10, 0, -15 }, LeftKnee = { -60, 0, 0 } },
		},
	},
	Cast = {
		Keys = {
			withStance({ T = 0.3, Ease = "Out", RootPos = { 0, -0.3, 0 }, Neck = { -10, 0, 0 },
				RightShoulder = { 60, 45, 0 }, RightElbow = { 100, 0, 0 }, RightWrist = { 30, 0, 0 }, LeftShoulder = { 60, -45, 0 }, LeftElbow = { 100, 0, 0 } }),
			withStance({ T = 0.5, Ease = "Snap", RootPos = { 0, -0.5, 0 }, Root = { -10, 0, 0 }, Waist = { -10, 0, 0 },
				RightShoulder = { 90, 12, 0 }, RightElbow = { 5, 0, 0 }, RightWrist = { 30, 0, 0 }, LeftShoulder = { 90, -12, 0 }, LeftElbow = { 5, 0, 0 } }),
			withStance({ T = 0.85, Ease = "Out", RootPos = { 0, -0.5, 0 }, Root = { -10, 0, 0 }, Waist = { -10, 0, 0 },
				RightShoulder = { 88, 12, 0 }, RightElbow = { 8, 0, 0 }, LeftShoulder = { 88, -12, 0 }, LeftElbow = { 8, 0, 0 } }),
		},
	},
	Point = {
		Trail = { 0.3, 0.5 },
		Keys = {
			withStance({ T = 0.3, Ease = "Out", RootPos = { 0, -0.2, 0 }, Root = { 10, 0, 0 }, Neck = { -15, 0, 0 },
				RightShoulder = { 170, 0, 10 }, RightElbow = { 10, 0, 0 }, RightWrist = { -60, 0, 0 }, LeftShoulder = { 30, 0, -30 }, LeftElbow = { 30, 0, 0 } }),
			withStance({ T = 0.5, Ease = "Snap", RootPos = { 0, -0.5, 0 }, Root = { -12, 0, 0 }, Waist = { -8, 0, 0 },
				RightShoulder = { 95, 0, 0 }, RightElbow = { 0, 0, 0 }, RightWrist = { -60, 0, 0 }, LeftShoulder = { -20, 0, -40 }, LeftElbow = { 20, 0, 0 },
				RightHip = { 45, 0, 10 }, RightKnee = { -60, 0, 0 } }),
			withStance({ T = 0.85, Ease = "Out", RootPos = { 0, -0.5, 0 }, Root = { -12, 0, 0 }, Waist = { -8, 0, 0 },
				RightShoulder = { 92, 0, 0 }, RightElbow = { 2, 0, 0 }, RightWrist = { -60, 0, 0 }, LeftShoulder = { -20, 0, -40 }, LeftElbow = { 20, 0, 0 },
				RightHip = { 45, 0, 10 }, RightKnee = { -60, 0, 0 } }),
		},
	},
	Roar = {
		Keys = {
			{ T = 0.3, Ease = "Out", RootPos = { 0, -0.7, 0 }, Root = { -20, 0, 0 }, Waist = { -10, 0, 0 }, Neck = { -10, 0, 0 },
				RightShoulder = { 40, 30, 0 }, RightElbow = { 110, 0, 0 }, LeftShoulder = { 40, -30, 0 }, LeftElbow = { 110, 0, 0 },
				RightHip = { 35, 0, 15 }, RightKnee = { -60, 0, 0 }, LeftHip = { 35, 0, -15 }, LeftKnee = { -60, 0, 0 } },
			{ T = 0.5, Ease = "Snap", RootPos = { 0, -0.4, 0 }, Root = { 15, 0, 0 }, Waist = { 10, 0, 0 }, Neck = { 25, 0, 0 },
				RightShoulder = { 25, 0, 75 }, RightElbow = { 55, 0, 0 }, LeftShoulder = { 25, 0, -75 }, LeftElbow = { 55, 0, 0 },
				RightHip = { 20, 0, 22 }, RightKnee = { -35, 0, 0 }, LeftHip = { 20, 0, -22 }, LeftKnee = { -35, 0, 0 } },
			{ T = 0.85, Ease = "Out", RootPos = { 0, -0.4, 0 }, Root = { 12, 0, 0 }, Waist = { 8, 0, 0 }, Neck = { 20, 0, 0 },
				RightShoulder = { 25, 0, 70 }, RightElbow = { 60, 0, 0 }, LeftShoulder = { 25, 0, -70 }, LeftElbow = { 60, 0, 0 },
				RightHip = { 20, 0, 22 }, RightKnee = { -35, 0, 0 }, LeftHip = { 20, 0, -22 }, LeftKnee = { -35, 0, 0 } },
		},
	},
	LeapThrow = {
		Keys = {
			{ T = 0.25, Ease = "Out", Root = { 20, 0, 0 }, Neck = { -15, 0, 0 },
				RightShoulder = { 150, 0, 30 }, RightElbow = { 60, 0, 0 }, LeftShoulder = { 150, 0, -30 }, LeftElbow = { 60, 0, 0 },
				RightHip = { 70, 0, 5 }, RightKnee = { -100, 0, 0 }, LeftHip = { 70, 0, -5 }, LeftKnee = { -100, 0, 0 } },
			{ T = 0.45, Ease = "Snap", Root = { -30, 0, 0 }, Waist = { -10, 0, 0 }, Neck = { 10, 0, 0 },
				RightShoulder = { 60, 0, 35 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 60, 0, -35 }, LeftElbow = { 0, 0, 0 },
				RightHip = { 40, 0, 5 }, RightKnee = { -80, 0, 0 }, LeftHip = { 40, 0, -5 }, LeftKnee = { -80, 0, 0 } },
			{ T = 0.85, Ease = "Out", Root = { -20, 0, 0 },
				RightShoulder = { 50, 0, 35 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 50, 0, -35 }, LeftElbow = { 10, 0, 0 },
				RightHip = { 30, 0, 5 }, RightKnee = { -60, 0, 0 }, LeftHip = { 30, 0, -5 }, LeftKnee = { -60, 0, 0 } },
		},
	},
}
SkillEffects.Poses = POSES

local function pose(ctx, name: string, duration: number, airborne: boolean?)
	if ctx.Character and not ctx.Proc then
		controllers.AnimationController:PlayPose(ctx.Character, POSES[name], duration, { Airborne = airborne })
	end
end

local function hop(ctx, vy: number)
	local root = ctx.Root :: BasePart
	if ctx.Local and root.Parent then
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(v.X, vy, v.Z)
	end
end

-- ===== shuriken / kunai models =====
local function shuriken(cf: CFrame, color: Color3): { BasePart }
	local metal = rgb(205, 210, 222)
	local a = part(Vector3.new(2.6, 0.12, 0.55), cf, metal, Enum.Material.Metal)
	local b = part(Vector3.new(0.55, 0.12, 2.6), cf, metal, Enum.Material.Metal)
	local core = part(Vector3.new(0.16, 0.8, 0.8), cf * CFrame.Angles(0, 0, math.pi / 2), color, Enum.Material.Neon, Enum.PartType.Cylinder)
	addTrail(core, color, 0.5, 0.16)
	return { a, b, core }
end

local function kunai(cf: CFrame, color: Color3): { BasePart }
	local blade = part(Vector3.new(0.25, 0.25, 1.8), cf, rgb(70, 74, 86), Enum.Material.Metal)
	local tip = part(Vector3.new(0.3, 0.3, 0.5), cf * CFrame.new(0, 0, -1.05), color, Enum.Material.Neon)
	addTrail(blade, color, 0.35, 0.12)
	return { blade, tip }
end

local function placeGroup(group: { BasePart }, cf: CFrame, offsets: { CFrame })
	for i, p in ipairs(group) do
		p.CFrame = cf * offsets[i]
	end
end

local function fadeGroup(group: { BasePart }, t: number)
	for _, p in ipairs(group) do
		tween(p, { Transparency = 1 }, t)
		Debris:AddItem(p, t + 0.05)
	end
end

-- ===== the skills =====
local E = {}

E.shuriken_storm = {
	Start = function(ctx)
		pose(ctx, "Throw", 0.55)
		sound("Swing", 1, 1.4)
		local d = ctx.Def
		local count = if lowGraphics() then 5 else 9
		local half = math.acos(d.Arc)
		local from = hand(ctx)
		task.delay(0.12, function()
			for i = 1, count do
				local angle = -half + (2 * half) * (i - 1) / (count - 1)
				local dir = rotateY(ctx.Dir, angle)
				local to = from + dir * d.Range
				local group = shuriken(CFrame.new(from), d.Color)
				local offsets = { CFrame.identity, CFrame.identity, CFrame.Angles(0, 0, math.pi / 2) }
				local spin = math.random() * 6
				animate(0.34 + math.random() * 0.06, function(k)
					placeGroup(group, CFrame.new(from:Lerp(to, k)) * CFrame.Angles(0, spin + k * 30, 0), offsets)
				end, function()
					fx():Burst(to, "Sparkle", 6, { Color = ColorSequence.new(WHITE, d.Color) })
					fadeGroup(group, 0.15)
				end)
			end
		end)
	end,
}

E.whirlwind_slash = {
	Start = function(ctx)
		pose(ctx, "Spin", 0.65)
		local d = ctx.Def
		local root = ctx.Root :: BasePart
		for i, t in ipairs({ 0.12, 0.42 }) do
			task.delay(t, function()
				if not root.Parent then
					return
				end
				sound(if i == 2 then "Finisher" else "Swing", 1, 1.1)
				ring(feet(root), d.Color, d.Radius, 0.4, 0.3)
				-- a sweeping crescent of wind around the body
				local blade = part(Vector3.new(0.3, 0.5, d.Radius), CFrame.new(root.Position), d.Color)
				blade.Transparency = 0.25
				local a0 = math.random() * 6
				animate(0.3, function(k)
					local cf = CFrame.new(root.Position) * CFrame.Angles(0, a0 - k * math.pi * 2, 0)
					blade.CFrame = cf * CFrame.new(0, -0.6, -d.Radius / 2)
					blade.Transparency = 0.25 + 0.75 * k
				end, function()
					blade:Destroy()
				end)
				fx():Burst(root.Position - Vector3.new(0, 2, 0), "Sparkle", 24, {
					Color = ColorSequence.new(WHITE, d.Color), Speed = NumberRange.new(20, 34), Lifetime = NumberRange.new(0.25, 0.45),
					SpreadAngle = Vector2.new(180, 10),
				})
				shake(ctx, if i == 2 then 0.35 else 0.18)
			end)
		end
	end,
}

E.iaido_dash = {
	Start = function(ctx)
		local d = ctx.Def
		local root = ctx.Root :: BasePart
		pose(ctx, "Draw", 0.6, true)
		local start = root.Position
		task.delay(0.12, function()
			sound("Swing", 1, 0.8)
			if ctx.Local then
				dash(ctx, d.Length, 0.14, d.Color)
			end
			task.delay(0.16, function()
				local finish = if ctx.Local then root.Position else start + ctx.Dir * (ctx.Info and ctx.Info.Length or d.Length)
				streak(start, finish, WHITE, 0.6, 0.45)
				streak(start, finish, d.Color, 1.6, 0.25)
			end)
		end)
		task.delay(0.38, function()
			sound("Equip", 1.2, 1.4) -- the sheath click
			shake(ctx, 0.4)
			if ctx.Local then
				controllers.CameraController:Punch(-5, 0.25)
			end
		end)
	end,
	Hit = function(ctx, hit)
		local c = hit.Position + Vector3.new(0, (hit.Height or 5) * 0.5, 0)
		local r = math.random() * 0.6
		streak(c + Vector3.new(-3, 3 + r, 0), c + Vector3.new(3, -3 - r, 0), ctx.Def.Color, 0.4, 0.3)
		streak(c + Vector3.new(3, 3, r), c + Vector3.new(-3, -3, -r), WHITE, 0.3, 0.3)
	end,
}

E.wind_step = {
	Start = function(ctx)
		local d = ctx.Def
		local root = ctx.Root :: BasePart
		pose(ctx, "Draw", 0.45, true)
		sound("DoubleJump", 1, 1.3)
		local start = root.Position
		if ctx.Local then
			dash(ctx, d.Length, 0.16, d.Color)
		end
		task.delay(0.18, function()
			local finish = if ctx.Local then root.Position else start + ctx.Dir * d.Length
			streak(start, finish, d.Color, 1.2, 0.35)
			fx():Burst(finish, "Sparkle", 20, { Color = ColorSequence.new(WHITE, d.Color), Speed = NumberRange.new(8, 16) })
		end)
		-- swift aura while the speed buff lasts
		local emitter = Particles.Create("Sparkle", root, { Color = ColorSequence.new(WHITE, d.Color), Rate = 18, Speed = NumberRange.new(2, 5) })
		if emitter then
			Debris:AddItem(emitter, Skills.Duration(d, ctx.Level))
		end
	end,
}

E.smoke_bomb = {
	Start = function(ctx)
		local d = ctx.Def
		local root = ctx.Root :: BasePart
		pose(ctx, "Throw", 0.45)
		local from = hand(ctx)
		local land = feet(root) + ctx.Dir * 3
		local ball = part(Vector3.new(0.9, 0.9, 0.9), CFrame.new(from), rgb(30, 30, 36), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		animate(0.14, function(k)
			ball.CFrame = CFrame.new(from:Lerp(land, k) + Vector3.new(0, math.sin(k * math.pi) * 1.5, 0))
		end, function()
			ball:Destroy()
			sound("Slam", 0.8, 1.3)
			local center = feet(root) + Vector3.new(0, 2, 0)
			fx():Burst(center, "Smoke", if lowGraphics() then 30 else 80, {
				Color = ColorSequence.new(rgb(120, 120, 135), rgb(50, 50, 60)), Speed = NumberRange.new(10, 24),
				Lifetime = NumberRange.new(1.2, 2), Size = NumberSequence.new(3, 9), Transparency = NumberSequence.new(0.15, 1),
				Acceleration = Vector3.new(0, 1, 0), Drag = 3,
			})
			fx():Burst(center, "Shadow", 30, { Speed = NumberRange.new(6, 14) })
			ring(feet(root), rgb(170, 170, 190), d.Radius, 0.5)
			shake(ctx, 0.25)
			if ctx.Local then
				blink(ctx, d.Length, rgb(90, 90, 110))
				fx():Burst(root.Position, "Smoke", 20, { Color = ColorSequence.new(rgb(120, 120, 135)), Speed = NumberRange.new(3, 8), Size = NumberSequence.new(2, 5) })
				-- half-seen for a moment
				local character = ctx.Character :: Model
				for _, p in ipairs(character:GetDescendants()) do
					if p:IsA("BasePart") then
						p.LocalTransparencyModifier = 0.6
					end
				end
				task.delay(1, function()
					for _, p in ipairs(character:GetDescendants()) do
						if p:IsA("BasePart") then
							p.LocalTransparencyModifier = 0
						end
					end
				end)
			end
		end)
	end,
	Hit = function(_ctx, hit)
		fx():Burst(hit.Position + Vector3.new(0, (hit.Height or 5) + 0.5, 0), "Stars", 8, { Speed = NumberRange.new(1, 3), Lifetime = NumberRange.new(1.5, 2.2) })
	end,
}

E.kunai_rain = {
	Start = function(ctx)
		pose(ctx, "LeapThrow", 0.75, true)
		hop(ctx, 46)
		sound("DoubleJump", 1, 0.9)
	end,
	Result = function(ctx, info)
		local d = ctx.Def
		local center = info.Center
		if typeof(center) ~= "Vector3" then
			return
		end
		local mark = part(Vector3.new(0.3, d.Radius * 2, d.Radius * 2), CFrame.new(center + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.pi / 2), d.Color, Enum.Material.Neon, Enum.PartType.Cylinder)
		mark.Transparency = 0.75
		tween(mark, { Transparency = 1 }, 1.2)
		Debris:AddItem(mark, 1.25)
		local perWave = if lowGraphics() then 4 else 10
		for wave, t in ipairs({ 0.45, 0.75, 1.05 }) do
			task.delay(t - 0.18, function()
				for _ = 1, perWave do
					local a = math.random() * math.pi * 2
					local r = math.sqrt(math.random()) * d.Radius
					local target = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
					local from = target + Vector3.new((math.random() - 0.5) * 6, 38, (math.random() - 0.5) * 6)
					local look = CFrame.lookAt(from, target)
					local group = kunai(look, d.Color)
					local offsets = { CFrame.identity, CFrame.new(0, 0, -1.05) }
					animate(0.18, function(k)
						placeGroup(group, look.Rotation + from:Lerp(target, k), offsets)
					end, function()
						fadeGroup(group, 0.5)
					end)
				end
				task.delay(0.18, function()
					fx():Burst(center + Vector3.new(0, 1, 0), "Smoke", 14, { Color = ColorSequence.new(rgb(200, 190, 170)), Speed = NumberRange.new(4, 10), Size = NumberSequence.new(1, 3) })
					ring(center, d.Color, d.Radius, 0.3)
					sound("Hit", 0.8, 1 + wave * 0.15)
					shake(ctx, 0.15)
				end)
			end)
		end
	end,
}

E.dragon_flame = {
	Start = function(ctx)
		pose(ctx, "Cast", 0.65)
		local d = ctx.Def
		task.delay(0.18, function()
			sound("Slam", 0.9, 0.8)
			shake(ctx, 0.25)
			local from = hand(ctx)
			local half = math.acos(d.Arc)
			local count = if lowGraphics() then 6 else 14
			for i = 1, count do
				local angle = (math.random() * 2 - 1) * half * 0.9
				local dir = rotateY(ctx.Dir, angle)
				local to = from + dir * d.Range * (0.75 + math.random() * 0.25) + Vector3.new(0, (math.random() - 0.3) * 3, 0)
				local ball = part(Vector3.new(1.5, 1.5, 1.5), CFrame.new(from), rgb(255, 200, 80), Enum.Material.Neon, Enum.PartType.Ball)
				ball.Transparency = 0.1
				local grow = 5 + math.random() * 4
				animate(0.42 + i * 0.012, function(k)
					ball.CFrame = CFrame.new(from:Lerp(to, k))
					local s = 1.5 + (grow - 1.5) * k
					ball.Size = Vector3.new(s, s, s)
					ball.Color = rgb(255, 210, 90):Lerp(rgb(220, 40, 20), k)
					ball.Transparency = 0.1 + 0.85 * k
				end, function()
					ball:Destroy()
				end)
			end
			for i = 1, 4 do
				fx():Burst(from + ctx.Dir * (d.Range * i / 5), "Embers", 18, {
					Speed = NumberRange.new(4, 12), Size = NumberSequence.new(1.6, 0), Lifetime = NumberRange.new(0.4, 0.8), SpreadAngle = Vector2.new(60, 60),
				})
			end
		end)
	end,
	Hit = function(_ctx, hit)
		fx():Burst(hit.Position + Vector3.new(0, (hit.Height or 5) * 0.5, 0), "Embers", 8, { Speed = NumberRange.new(2, 6), Size = NumberSequence.new(0.8, 0) })
	end,
}

E.oni_quake = {
	Start = function(ctx)
		pose(ctx, "Slam", 0.9, true)
		hop(ctx, 38)
		local d = ctx.Def
		local root = ctx.Root :: BasePart
		task.delay(0.45, function()
			if not root.Parent then
				return
			end
			if ctx.Local then
				root.AssemblyLinearVelocity = Vector3.new(0, -80, 0)
			end
			task.wait(0.04)
			local center = feet(root)
			sound("BossSlam", 1, 0.9)
			ring(center, d.Color, d.Radius, 0.55, 0.6)
			task.delay(0.12, function()
				ring(center, rgb(255, 230, 190), d.Radius * 0.7, 0.45)
			end)
			fx():Burst(center + Vector3.new(0, 1, 0), "Smoke", if lowGraphics() then 20 else 50, {
				Color = ColorSequence.new(rgb(170, 130, 90)), Speed = NumberRange.new(12, 26), Size = NumberSequence.new(2, 6),
				Lifetime = NumberRange.new(0.6, 1.1), SpreadAngle = Vector2.new(180, 15),
			})
			-- rock spikes burst up in rings
			local spikes = if lowGraphics() then 8 else 18
			for i = 1, spikes do
				local a = (i / spikes) * math.pi * 2 + math.random() * 0.3
				local r = 5 + ((i % 3) / 3) * (d.Radius - 7) + math.random() * 3
				local base = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
				local h = 3 + math.random() * 4
				local w = 1.6 + math.random() * 1.6
				local tilt = CFrame.Angles((math.random() - 0.5) * 0.6, a, (math.random() - 0.5) * 0.6)
				local rock = part(Vector3.new(w, h, w), CFrame.new(base - Vector3.new(0, h, 0)) * tilt, rgb(120, 92, 66), Enum.Material.Slate)
				task.delay(r / 60, function()
					tween(rock, { CFrame = CFrame.new(base + Vector3.new(0, h * 0.35, 0)) * tilt }, 0.12, Enum.EasingStyle.Back)
					task.delay(0.9, function()
						tween(rock, { CFrame = CFrame.new(base - Vector3.new(0, h, 0)) * tilt, Transparency = 1 }, 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
						Debris:AddItem(rock, 0.45)
					end)
				end)
			end
			shake(ctx, 0.65)
			if ctx.Local then
				controllers.CameraController:Punch(-6, 0.3)
			end
		end)
	end,
}

E.lightning_blade = {
	Start = function(ctx)
		pose(ctx, "Point", 0.6)
		local root = ctx.Root :: BasePart
		task.delay(0.15, function()
			if root.Parent then
				-- the blade drinks the lightning first
				bolt(root.Position + Vector3.new(0, 40, 0), root.Position + Vector3.new(0, 4, 0), ctx.Def.Color, 0.5, 0.2)
				fx():Burst(root.Position + Vector3.new(0, 3, 0), "Lightning", 16)
			end
		end)
	end,
	Result = function(ctx, info)
		local d = ctx.Def
		local root = ctx.Root :: BasePart
		task.delay(math.max(0, 0.2 - (ctx.Elapsed or 0)), function()
			local prev = if root.Parent then hand(ctx) else ctx.Origin
			local chain = if type(info.Chain) == "table" then info.Chain else {}
			if #chain == 0 then
				bolt(prev, prev + ctx.Dir * 20, d.Color, 0.5, 0.25)
			end
			for _, link in ipairs(chain) do
				local p = link.Position + Vector3.new(0, (link.Height or 5) * 0.55, 0)
				for _ = 1, 2 do
					bolt(prev, p, d.Color, 0.45, 0.28)
				end
				fx():Burst(p, "Lightning", 10)
				prev = p
			end
			if chain[1] then
				local first = chain[1].Position
				bolt(first + Vector3.new(0, 50, 0), first, WHITE, 0.8, 0.3)
			end
			sound("Crit", 1, 1.4)
			shake(ctx, 0.3)
			if ctx.Local then
				fx():Flash(rgb(200, 245, 255), 0.15)
			end
		end)
	end,
}

-- Shadow clones: copies of the caster's character, tinted, that follow and blink onto targets.
local function makeClone(character: Model): Model?
	local ok, clone = pcall(function()
		local was = character.Archivable
		character.Archivable = true
		local c = character:Clone()
		character.Archivable = was
		return c
	end)
	if not ok or not clone then
		return nil
	end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ForceField") or d:IsA("Sound") or d:IsA("BillboardGui") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			d.Anchored = d.Name == "HumanoidRootPart"
		elseif d:IsA("Humanoid") then
			d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			d.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		end
	end
	local highlight = Instance.new("Highlight")
	highlight.FillColor = rgb(80, 30, 150)
	highlight.FillTransparency = 0.25
	highlight.OutlineColor = rgb(200, 140, 255)
	highlight.OutlineTransparency = 0
	highlight.Parent = clone
	clone.Name = "ShadowClone"
	clone.Parent = workspace:FindFirstChild("ClientFX") or workspace
	return clone
end

E.shadow_clone = {
	Start = function(ctx)
		pose(ctx, "Cast", 0.5)
		local d = ctx.Def
		local character = ctx.Character :: Model
		local root = ctx.Root :: BasePart
		local caster = Players:GetPlayerFromCharacter(character)
		local key = if caster then caster.UserId else 0
		local old = clonesBy[key]
		if old then
			for _, m in ipairs(old.Models) do
				m:Destroy()
			end
		end
		local duration = Skills.Duration(d, ctx.Level)
		local set = { Models = {}, Busy = {}, Until = os.clock() + duration + 0.4, Owner = character }
		clonesBy[key] = set
		task.delay(0.3, function()
			sound("Slam", 0.6, 1.6)
			for i = 1, d.Clones do
				local m = makeClone(character)
				local a = (i / d.Clones) * math.pi * 2
				local spot = root.Position + Vector3.new(math.cos(a) * 5, 0, math.sin(a) * 5)
				fx():Burst(spot, "Smoke", 20, { Color = ColorSequence.new(rgb(120, 80, 170)), Speed = NumberRange.new(4, 10), Size = NumberSequence.new(1.5, 4) })
				if m then
					table.insert(set.Models, m)
					set.Busy[i] = 0
				end
			end
		end)
		-- follow the caster in a slowly turning ring until they vanish
		animate(duration + 0.4, function()
			if not root.Parent then
				return
			end
			local now = os.clock()
			for i, m in ipairs(set.Models) do
				local mroot = m:FindFirstChild("HumanoidRootPart") :: BasePart?
				if mroot and now > (set.Busy[i] or 0) then
					local a = (i / d.Clones) * math.pi * 2 + now * 0.6
					local spot = root.Position + Vector3.new(math.cos(a) * 5, 0, math.sin(a) * 5)
					local current = mroot.Position
					local nextPos = current:Lerp(spot, 0.15)
					mroot.CFrame = CFrame.lookAt(nextPos, nextPos + root.CFrame.LookVector)
				end
			end
		end, function()
			for _, m in ipairs(set.Models) do
				local mroot = m:FindFirstChild("HumanoidRootPart") :: BasePart?
				if mroot then
					fx():Burst(mroot.Position, "Smoke", 16, { Color = ColorSequence.new(rgb(120, 80, 170)), Speed = NumberRange.new(4, 9), Size = NumberSequence.new(1.5, 4) })
				end
				m:Destroy()
			end
			if clonesBy[key] == set then
				clonesBy[key] = nil
			end
		end)
	end,
	Hit = function(ctx, hit, tag)
		if type(tag) ~= "table" or not tag.Clone then
			return
		end
		local character = ctx.Character :: Model
		local caster = Players:GetPlayerFromCharacter(character)
		local set = clonesBy[if caster then caster.UserId else 0]
		local m = set and set.Models[tag.Clone]
		local mroot = m and m:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not set or not m or not mroot then
			return
		end
		set.Busy[tag.Clone] = os.clock() + 0.45
		local target = hit.Position
		local away = Vector3.new(mroot.Position.X - target.X, 0, mroot.Position.Z - target.Z)
		away = if away.Magnitude > 0.1 then away.Unit else Vector3.new(1, 0, 0)
		local spot = Vector3.new(target.X, mroot.Position.Y, target.Z) + away * 3.5
		afterImage(mroot.CFrame, rgb(150, 90, 230), 0.3)
		mroot.CFrame = CFrame.lookAt(spot, Vector3.new(target.X, spot.Y, target.Z))
		controllers.AnimationController:PlaySwing(m, math.random(1, 3), 0.4)
		streak(target + Vector3.new(-2.5, 4, 0), target + Vector3.new(2.5, 1, 0), rgb(200, 140, 255), 0.3, 0.25)
	end,
}

E.bushido_spirit = {
	Start = function(ctx)
		pose(ctx, "Roar", 0.85)
		local d = ctx.Def
		local root = ctx.Root :: BasePart
		task.delay(0.25, function()
			if not root.Parent then
				return
			end
			sound("TierUp", 0.9, 1.1)
			fx():Pillar(feet(root), d.Color, 40, 0.8)
			ring(feet(root), d.Color, d.Radius + 4, 0.5)
			fx():Burst(root.Position, "Radiance", 40, { Color = ColorSequence.new(WHITE, d.Color), Speed = NumberRange.new(10, 20) })
			shake(ctx, 0.35)
			if ctx.Local then
				fx():Vignette(d.Color, 0.6, 0.8)
			end
			local duration = Skills.Duration(d, ctx.Level)
			local flame = Particles.Create("BloodFlame", root, { Rate = 28, Size = NumberSequence.new(1.4, 0) })
			if flame then
				Debris:AddItem(flame, duration)
			end
			local glow = Instance.new("Highlight")
			glow.FillColor = d.Color
			glow.FillTransparency = 0.85
			glow.OutlineColor = rgb(255, 200, 120)
			glow.OutlineTransparency = 0.1
			glow.Parent = ctx.Character
			Debris:AddItem(glow, duration)
		end)
	end,
}

E.thousand_cuts = {
	Start = function(ctx)
		pose(ctx, "Draw", 0.3)
		sound("TierUp", 1, 1.5)
		if ctx.Local then
			fx():Flash(rgb(40, 0, 60), 0.4)
			local tint = Instance.new("ColorCorrectionEffect")
			tint.Name = "ThousandCutsTint"
			tint.Saturation = -0.7
			tint.TintColor = rgb(230, 200, 255)
			tint.Contrast = 0.15
			tint.Parent = Lighting
			task.delay(2.2, function()
				tween(tint, { Saturation = 0, Contrast = 0, TintColor = WHITE }, 0.5)
				Debris:AddItem(tint, 0.6)
			end)
		end
	end,
	Result = function(ctx, info)
		local d = ctx.Def
		local root = ctx.Root :: BasePart
		local targets = if type(info.Targets) == "table" then info.Targets else {}
		local stepTime = info.Step or Skills.CutStep
		local total = info.Total or 0.5
		local baseY = root.Position.Y
		local lead = math.max(0, 0.2 - (ctx.Elapsed or 0))
		for i, t in ipairs(targets) do
			task.delay(lead + (i - 1) * stepTime, function()
				if not root.Parent then
					return
				end
				local target = t.Position
				local a = math.random() * math.pi * 2
				local spot = Vector3.new(target.X + math.cos(a) * 4, baseY, target.Z + math.sin(a) * 4)
				if ctx.Local then
					afterImage(root.CFrame, d.Color, 0.35)
					root.CFrame = CFrame.lookAt(spot, Vector3.new(target.X, baseY, target.Z))
					root.AssemblyLinearVelocity = Vector3.zero
					controllers.AnimationController:PlaySwing(ctx.Character, (i % 2) + 1, 0.22)
				end
				local c = target + Vector3.new(0, (t.Height or 5) * 0.5, 0)
				local dirA = Vector3.new(math.cos(a + 1.2), (math.random() - 0.5) * 1.6, math.sin(a + 1.2)).Unit
				streak(c - dirA * 5, c + dirA * 5, d.Color, 0.45, 0.3)
				streak(c - dirA * 4, c + dirA * 4, WHITE, 0.2, 0.3)
				sound("Swing", 0.7, 1.2 + (i % 4) * 0.1)
			end)
		end
		task.delay(lead + total - 0.2, function()
			if not root.Parent then
				return
			end
			local center = root.Position
			if ctx.Local then
				controllers.AnimationController:PlaySwing(ctx.Character, 4, 0.5)
			end
			task.wait(0.2)
			fx():Sphere(center, d.Color, 4, d.Radius * 2, 0.6)
			ring(feet(root), d.Color, d.Radius, 0.6, 0.6)
			ring(feet(root), WHITE, d.Radius * 0.6, 0.45)
			fx():Pillar(feet(root), d.Color, 70, 1)
			for _ = 1, (if lowGraphics() then 4 else 12) do
				local a = math.random() * math.pi * 2
				local r = math.random() * d.Radius
				local c = center + Vector3.new(math.cos(a) * r, math.random() * 3, math.sin(a) * r)
				local dir = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
				if dir.Magnitude > 0.01 then
					streak(c - dir.Unit * 6, c + dir.Unit * 6, WHITE, 0.35, 0.35)
				end
			end
			sound("BossSlam", 1, 1.1)
			shake(ctx, 0.8)
			if ctx.Local then
				controllers.CameraController:Punch(-8, 0.35)
				fx():Flash(WHITE, 0.25)
			end
		end)
	end,
}

-- Elemental tier skills (Config/ElementSkills) draw with the same toolkit (ElementEffects).
SkillEffects.Tools = {
	fx = fx, part = part, tween = tween, animate = animate, lowGraphics = lowGraphics, feet = feet,
	shake = shake, sound = sound, rotateY = rotateY, addTrail = addTrail, streak = streak, bolt = bolt,
	ring = ring, afterImage = afterImage, dash = dash, blink = blink, hand = hand, pose = pose, hop = hop,
	controllers = function()
		return controllers
	end,
}
require(script.Parent:WaitForChild("ElementEffects")).Register(E, SkillEffects.Tools)
-- Suit mastery ultimates (Config/Mastery) too (UltimateEffects).
require(script.Parent:WaitForChild("UltimateEffects")).Register(E, SkillEffects.Tools)
-- Charm spells (Config/Charms: the Hexfire Torch's Hexfire) too (CharmEffects).
require(script.Parent:WaitForChild("CharmEffects")).Register(E, SkillEffects.Tools)

SkillEffects.Skills = E

-- ===== entry points =====
function SkillEffects:Start(ctx)
	local e = E[ctx.Def.Id]
	if e and e.Start then
		local ok, err = pcall(e.Start, ctx)
		if not ok then
			warn("[SkillEffects] " .. ctx.Def.Id .. ": " .. tostring(err))
		end
	end
end

function SkillEffects:Result(ctx, info)
	local e = E[ctx.Def.Id]
	if e and e.Result and type(info) == "table" then
		local ok, err = pcall(e.Result, ctx, info)
		if not ok then
			warn("[SkillEffects] " .. ctx.Def.Id .. ": " .. tostring(err))
		end
	end
end

function SkillEffects:Hit(ctx, hit, tag)
	local e = E[ctx.Def.Id]
	if e and e.Hit then
		pcall(e.Hit, ctx, hit, tag)
	end
end

function SkillEffects:Init(c)
	controllers = c
	RunService.Heartbeat:Connect(step)
end

return SkillEffects
