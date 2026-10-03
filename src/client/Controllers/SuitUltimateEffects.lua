--[[
	SuitUltimateEffects: the looks of every suit's own ultimates except the Brown
	Ninja's (Config/Mastery.Sets; server: SuitUltimates). SkillEffects requires this
	and calls Register(E, tools): each ultimate gets { Start, Result, Hit }, drawn in its
	suit's element colour with the shared toolkit and a pose of its own (UltimatePoses).

	Start plays the moment you press the key (pose, wind-up); Result gets the server's
	info (paths, impact points, timings) and draws the rest, timed from the cast
	(ctx.Elapsed is the server's reply time for your own casts). Movement ultimates
	move your own character along the server's path. Hit draws per-hit extras for the
	hits a look can't know in advance (sentinel bolts, clone lightning).
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Mastery = require(Shared.Config.Mastery)
local Poses = require(script.Parent:WaitForChild("UltimatePoses"))

local SuitUltimateEffects = {}

local T -- SkillEffects.Tools
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.fromRGB(12, 8, 18)
local rgb = Color3.fromRGB
local NEON = Enum.Material.Neon
local FORCE = Enum.Material.ForceField
local GLASS = Enum.Material.Glass
local BALL = Enum.PartType.Ball
local CYL = Enum.PartType.Cylinder

-- ===== helpers =====
local function fx()
	return T.fx()
end

local function lighter(c: Color3): Color3
	return c:Lerp(WHITE, 0.45)
end

local function darker(c: Color3): Color3
	return c:Lerp(BLACK, 0.55)
end

local function low(): boolean
	return T.lowGraphics()
end

local function feetAt(p: Vector3): Vector3
	return p - Vector3.new(0, 2.9, 0)
end

local function feetOf(ctx): Vector3
	local root = ctx.Root :: BasePart?
	if root and root.Parent and not ctx.Proc then
		return T.feet(root)
	end
	return feetAt(ctx.Origin)
end

local function rootPos(ctx): Vector3
	local root = ctx.Root :: BasePart?
	return if root and root.Parent then root.Position else ctx.Origin
end

-- Runs fn `t` seconds after the cast (minus the server's reply time for our own).
local function at(ctx, t: number, fn: () -> ())
	task.delay(math.max(0, t - (ctx.Elapsed or 0)), fn)
end

local function fade(p: BasePart, t: number, props: { [string]: any }?)
	local goal = props or {}
	if goal.Transparency == nil then
		goal.Transparency = 1
	end
	T.tween(p, goal, t)
	Debris:AddItem(p, t + 0.05)
end

-- A glowing slab between two points.
local function slab(a: Vector3, b: Vector3, width: number, height: number, color: Color3, life: number, material: Enum.Material?)
	local len = (b - a).Magnitude
	if len < 0.05 then
		return nil
	end
	local p = T.part(Vector3.new(width, height, len), CFrame.lookAt((a + b) / 2, b), color, material)
	p.Transparency = 0.15
	fade(p, life, { Size = Vector3.new(width * 0.2, height * 0.2, len) })
	return p
end

-- A bolt of lightning from the sky onto a point.
local function skyBolt(spot: Vector3, color: Color3, height: number?)
	local top = spot + Vector3.new((math.random() - 0.5) * 6, height or 45, (math.random() - 0.5) * 6)
	T.bolt(top, spot, lighter(color), 0.7, 0.3)
	T.bolt(top, spot, color, 1.4, 0.18)
	T.ring(feetAt(spot + Vector3.new(0, 2.9, 0)), color, 9, 0.35, 1)
	fx():Burst(spot, "Lightning", 10, { Color = ColorSequence.new(WHITE, color) })
end

-- Moves our own character through `points` (root positions), `leg` seconds each.
local function travel(ctx, points: { Vector3 }, leg: number, color: Color3, images: boolean?)
	local root = ctx.Root :: BasePart
	if not ctx.Local or not root or not root.Parent or #points < 2 then
		return
	end
	local total = leg * (#points - 1)
	local y0 = root.Position.Y
	local lastImage = 0
	T.animate(total, function(k)
		local f = k * (#points - 1)
		local i = math.clamp(math.floor(f) + 1, 1, #points - 1)
		local a, b = points[i], points[i + 1]
		local p = a:Lerp(b, math.clamp(f - (i - 1), 0, 1))
		local dir = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local facing = if dir.Magnitude > 0.05 then CFrame.lookAt(Vector3.zero, dir.Unit) else root.CFrame.Rotation
		root.CFrame = CFrame.new(p.X, math.max(y0, p.Y), p.Z) * facing
		root.AssemblyLinearVelocity = Vector3.zero
		if images ~= false and k - lastImage > 0.08 then
			lastImage = k
			T.afterImage(root.CFrame, color, 0.4)
		end
	end)
end

-- A parabolic jump of our own character to `landing` over `time` seconds.
local function leap(ctx, landing: Vector3, time: number, height: number)
	local root = ctx.Root :: BasePart
	if not ctx.Local or not root or not root.Parent then
		return
	end
	local start = root.Position
	local flatDir = Vector3.new(landing.X - start.X, 0, landing.Z - start.Z)
	local facing = if flatDir.Magnitude > 0.05 then CFrame.lookAt(Vector3.zero, flatDir.Unit) else root.CFrame.Rotation
	local finish = Vector3.new(landing.X, start.Y, landing.Z)
	T.animate(time, function(k)
		local p = start:Lerp(finish, k) + Vector3.new(0, 4 * height * k * (1 - k), 0)
		root.CFrame = CFrame.new(p) * facing
		root.AssemblyLinearVelocity = Vector3.zero
	end)
end

-- A neon crescent blade (several short slabs on an arc), facing `dir`.
local function crescent(center: Vector3, dir: Vector3, radius: number, color: Color3, thickness: number): { BasePart }
	local parts = {}
	local segments = if low() then 5 else 9
	local base = math.atan2(dir.X, dir.Z)
	for i = 0, segments - 1 do
		local a0 = base - 1.1 + 2.2 * i / segments
		local a1 = base - 1.1 + 2.2 * (i + 1) / segments
		local p0 = center + Vector3.new(math.sin(a0), 0, math.cos(a0)) * radius
		local p1 = center + Vector3.new(math.sin(a1), 0, math.cos(a1)) * radius
		local mid = 1 - math.abs(i - segments / 2) / segments -- thick in the middle
		local p = T.part(Vector3.new(thickness * (0.4 + mid), 0.35, (p1 - p0).Magnitude + 0.2), CFrame.lookAt((p0 + p1) / 2, p1), color)
		table.insert(parts, p)
	end
	return parts
end

local function fadeGroup(parts: { BasePart }, t: number)
	for _, p in ipairs(parts) do
		fade(p, t)
	end
end

-- An ice crystal shard (a tall glassy block on its point).
local function crystal(spot: Vector3, height: number, color: Color3, life: number)
	local p = T.part(Vector3.new(height * 0.35, height, height * 0.35), CFrame.new(spot + Vector3.new(0, height * 0.4, 0)) * CFrame.Angles(math.rad(math.random(-15, 15)), math.random() * 6, math.rad(math.random(-15, 15))), color, GLASS)
	p.Transparency = 0.25
	p.Size = Vector3.new(height * 0.35, 0.2, height * 0.35)
	T.tween(p, { Size = Vector3.new(height * 0.35, height, height * 0.35) }, 0.18, Enum.EasingStyle.Back)
	task.delay(life, function()
		if p.Parent then
			fade(p, 0.35, { Size = Vector3.new(0.2, 0.2, 0.2) })
		end
	end)
	return p
end

-- per-hit extras drawn from a hit's table tag: frost bolts, chain lightning arcs
local function tagHit(ctx, hit, tag)
	if type(tag) ~= "table" or typeof(hit.Position) ~= "Vector3" then
		return
	end
	local color = ctx.Def.Color
	local target = hit.Position + Vector3.new(0, (hit.Height or 5) * 0.4, 0)
	if tag.K == "Bolt" and typeof(tag.From) == "Vector3" then
		local orb = T.part(Vector3.new(1.4, 1.4, 1.4), CFrame.new(tag.From), lighter(color), NEON, BALL)
		T.addTrail(orb, color, 0.8, 0.2)
		T.animate(0.18, function(k)
			orb.CFrame = CFrame.new(tag.From:Lerp(target, k))
		end, function()
			orb:Destroy()
			fx():Burst(target, "Frost", 8)
		end)
	elseif tag.K == "Arc" and typeof(tag.From) == "Vector3" then
		T.bolt(tag.From + Vector3.new(0, 1.5, 0), target, lighter(color), 0.5, 0.22)
	end
end

local looks = {}

-- ===================================================================
-- Green: Wind
-- ===================================================================
looks.GaleZigzag = {
	Start = function(ctx)
		T.pose(ctx, "GaleRun", 0.6)
		T.sound("Dodge", 1, 0.8)
		fx():Burst(rootPos(ctx), "Petals", 10, { Color = ColorSequence.new(ctx.Def.Color) })
	end,
	Result = function(ctx, info)
		local color = ctx.Def.Color
		local points = info.Points or {}
		travel(ctx, points, info.Leg or 0.13, color)
		for i = 1, #points - 1 do
			at(ctx, (info.Leg or 0.13) * i, function()
				local a, b = points[i], points[i + 1]
				slab(a, b, 2.2, 0.3, lighter(color), 0.5)
				slab(a + Vector3.new(0, 1.6, 0), b + Vector3.new(0, 1.6, 0), 0.8, 0.8, color, 0.4)
				fx():Burst(b, "Petals", 8, { Color = ColorSequence.new(color, WHITE) })
				T.ring(feetAt(b), color, 7, 0.3, 0.6)
				T.sound("Swing", 1, 1.2 + i * 0.1)
			end)
		end
		T.shake(ctx, 0.3)
	end,
}

looks.VacuumBoomerang = {
	Start = function(ctx)
		T.pose(ctx, "BoomerangThrow", 0.7)
		T.sound("Swing", 1, 0.7)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local length, time = info.Length or d.Length, info.Time or d.Time
		local start = ctx.Origin + Vector3.new(0, 0.5, 0)
		local outEnd = start + ctx.Dir * length
		local blade = crescent(start, ctx.Dir, d.Width * 0.5, color, 1.4)
		local inner = crescent(start, ctx.Dir, d.Width * 0.35, WHITE, 0.6)
		local all = table.clone(blade)
		for _, p in ipairs(inner) do
			table.insert(all, p)
		end
		local origins = {}
		for i, p in ipairs(all) do
			origins[i] = CFrame.new(start):ToObjectSpace(p.CFrame)
		end
		local lastWisp = 0
		T.animate(time * 2, function(k)
			local travelK = if k < 0.5 then 1 - (1 - k * 2) ^ 2 else 1 - ((k - 0.5) * 2) ^ 2
			local back = if k >= 0.5 then rootPos(ctx) + Vector3.new(0, 0.5, 0) else start
			local center = back:Lerp(outEnd, travelK)
			local spin = CFrame.new(center) * CFrame.Angles(0, k * 40, 0)
			for i, p in ipairs(all) do
				p.CFrame = spin * origins[i]
			end
			if k - lastWisp > 0.06 then
				lastWisp = k
				fx():Burst(center, "Petals", 3, { Color = ColorSequence.new(color) })
			end
		end, function()
			fadeGroup(all, 0.15)
		end)
		at(ctx, time, function()
			T.ring(feetAt(outEnd), color, 10, 0.35, 0.5)
			T.sound("Swing", 1, 1.4)
		end)
	end,
}

looks.Typhoon = {
	Start = function(ctx)
		T.pose(ctx, "TyphoonSpin", 0.25 + (ctx.Def.Ticks * ctx.Def.Tick))
		T.sound("Finisher", 0.8, 0.6)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local radius = info.Radius or d.Radius
		local span = 0.2 + (info.Ticks or d.Ticks) * (info.Tick or d.Tick)
		local rings = {}
		local count = if low() then 4 else 7
		for i = 1, count do
			local r = radius * (0.35 + 0.65 * i / count)
			local ring = T.part(Vector3.new(0.6 + i * 0.25, r * 2, r * 2), CFrame.new(), if i % 2 == 0 then color else lighter(color), FORCE, CYL)
			ring.Transparency = 0.35
			rings[i] = { Part = ring, R = r, Y = i * 2.6 - 1 }
		end
		T.animate(span, function(k)
			local base = feetOf(ctx)
			local grow = math.min(1, k * 4)
			for i, ring in ipairs(rings) do
				local spin = os.clock() * (4 + i)
				ring.Part.Size = Vector3.new(ring.Part.Size.X, ring.R * 2 * grow, ring.R * 2 * grow)
				ring.Part.CFrame = CFrame.new(base + Vector3.new(0, ring.Y, 0)) * CFrame.Angles(0, spin, math.pi / 2)
			end
		end, function()
			for _, ring in ipairs(rings) do
				fade(ring.Part, 0.3, { Size = Vector3.new(0.1, ring.R * 3, ring.R * 3) })
			end
			local base = feetOf(ctx)
			T.ring(base, lighter(color), radius * 0.9, 0.5, 3)
			fx():Burst(base + Vector3.new(0, 3, 0), "Petals", 40, { Speed = NumberRange.new(30, 50), Color = ColorSequence.new(color, WHITE) })
			T.sound("BossSlam", 1, 1.2)
			T.shake(ctx, 0.5)
		end)
		for i = 1, info.Ticks or d.Ticks do
			at(ctx, 0.2 + (i - 1) * (info.Tick or d.Tick), function()
				T.sound("Swing", 0.7, 0.8 + i * 0.05)
			end)
		end
	end,
}

looks.SkyDancer = {
	Start = function(ctx)
		T.pose(ctx, "SkyDance", 1.2 + ctx.Def.Hover, true)
		T.hop(ctx, 75)
		T.sound("DoubleJump", 1, 0.8)
		T.ring(feetOf(ctx), ctx.Def.Color, 14, 0.4, 1)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local hover = info.Hover or d.Hover
		local root = ctx.Root :: BasePart?
		-- hang in the air a moment (our own character), then drift down
		if ctx.Local and root and root.Parent then
			at(ctx, 0.35, function()
				T.animate(hover, function()
					if root.Parent then
						root.AssemblyLinearVelocity = Vector3.new(0, 1, 0)
					end
				end)
			end)
		end
		-- wind wings while airborne
		local wings = {}
		for side = -1, 1, 2 do
			local w = T.part(Vector3.new(0.2, 3, 7), CFrame.new(), lighter(color), FORCE)
			w.Transparency = 0.3
			table.insert(wings, { Part = w, Side = side })
		end
		T.animate(hover + 0.6, function()
			local r = ctx.Root :: BasePart?
			if not r or not r.Parent then
				return
			end
			local flap = math.sin(os.clock() * 14) * 0.4
			for _, w in ipairs(wings) do
				w.Part.CFrame = r.CFrame * CFrame.new(w.Side * 1.5, 1, 1) * CFrame.Angles(0, w.Side * 0.5, w.Side * (0.9 + flap)) * CFrame.new(0, 0, 3)
			end
		end, function()
			for _, w in ipairs(wings) do
				fade(w.Part, 0.3)
			end
		end)
		for i, target in ipairs(info.Targets or {}) do
			at(ctx, hover * 0.45 + i * 0.07 - 0.15, function()
				local from = rootPos(ctx)
				local to = target.Position
				local blade = T.part(Vector3.new(3, 0.25, 0.8), CFrame.lookAt(from, to), color)
				T.addTrail(blade, lighter(color), 0.6, 0.2)
				T.animate(0.15, function(k)
					blade.CFrame = CFrame.lookAt(from:Lerp(to, k), to) * CFrame.Angles(0, 0, k * 12)
				end, function()
					blade:Destroy()
					fx():Burst(to, "Petals", 8, { Color = ColorSequence.new(color, WHITE) })
					T.sound("Hit", 0.6, 1.3)
				end)
			end)
		end
	end,
}

-- ===================================================================
-- Blue: Ice
-- ===================================================================
looks.GlacialSkate = {
	Start = function(ctx)
		local d = ctx.Def
		T.pose(ctx, "Skate", 0.75)
		T.dash(ctx, d.Length, 0.55, d.Color)
		T.sound("Dodge", 1, 0.6)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local length = info.Length or d.Length
		local base = feetAt(ctx.Origin) + Vector3.new(0, 0.1, 0)
		local road = T.part(Vector3.new(d.Width, 0.25, 0.5), CFrame.lookAt(base, base + ctx.Dir), lighter(color), GLASS)
		road.Transparency = 0.2
		T.animate(0.5, function(k)
			local e = 1 - (1 - k) ^ 2
			road.Size = Vector3.new(d.Width, 0.25, math.max(0.5, length * e))
			road.CFrame = CFrame.lookAt(base + ctx.Dir * length * e / 2, base + ctx.Dir * length)
		end)
		task.delay(info.Trail or d.Trail, function()
			fade(road, 0.6)
		end)
		local n = if low() then 5 else 10
		for i = 1, n do
			at(ctx, 0.3 + i * 0.02, function()
				local spot = base + ctx.Dir * length * (i / n) + T.rotateY(ctx.Dir, math.pi / 2) * (if i % 2 == 0 then 1 else -1) * d.Width * 0.45
				crystal(spot, 4 + math.random() * 3, color, 1.6)
			end)
		end
		at(ctx, 0.3, function()
			T.sound("BossSlam", 0.6, 1.6)
			fx():Burst(base + ctx.Dir * length * 0.5 + Vector3.new(0, 1, 0), "Frost", 25)
		end)
	end,
}

looks.FrostVolley = {
	Start = function(ctx)
		T.pose(ctx, "Volley", 1.0)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		for i, a in ipairs(info.Angles or {}) do
			at(ctx, 0.18 + (i - 1) * (info.Interval or d.Interval), function()
				local from = rootPos(ctx) + Vector3.new(0, 1, 0)
				local dir = T.rotateY(ctx.Dir, math.rad(a))
				local to = from + dir * d.Length
				local lance = T.part(Vector3.new(0.9, 0.9, 7), CFrame.lookAt(from, to), lighter(color), GLASS)
				local tip = T.part(Vector3.new(0.5, 0.5, 2), lance.CFrame * CFrame.new(0, 0, -4), WHITE, NEON)
				T.addTrail(lance, color, 0.8, 0.3)
				T.sound("Swing", 0.9, 1.6)
				T.animate(0.32, function(k)
					local cf = CFrame.lookAt(from:Lerp(to, k), to)
					lance.CFrame = cf
					tip.CFrame = cf * CFrame.new(0, 0, -4)
				end, function()
					lance:Destroy()
					tip:Destroy()
					crystal(feetAt(to + Vector3.new(0, 2.9, 0)), 5, color, 1)
				end)
			end)
		end
	end,
}

looks.PermafrostDome = {
	Start = function(ctx)
		T.pose(ctx, "DomeKneel", 1.0)
		T.sound("TierUp", 0.6, 1.8)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local center = feetAt(info.Center or ctx.Origin)
		local radius = info.Radius or d.Radius
		local freeze = info.Freeze or d.Freeze
		local dome = T.part(Vector3.new(1, 1, 1), CFrame.new(center), lighter(color), GLASS, BALL)
		dome.Transparency = 0.7
		T.tween(dome, { Size = Vector3.new(radius * 2, radius * 1.3, radius * 2) }, 0.35, Enum.EasingStyle.Back)
		local shell = T.part(Vector3.new(radius * 2, radius * 1.3, radius * 2), CFrame.new(center), color, FORCE, BALL)
		shell.Transparency = 0.4
		at(ctx, 0.3, function()
			T.ring(center, WHITE, radius, 0.4, 1.5)
			local n = if low() then 6 else 16
			for i = 1, n do
				local a = i / n * math.pi * 2
				local r = radius * (0.3 + math.random() * 0.65)
				crystal(center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r), 4 + math.random() * 4, color, freeze)
			end
		end)
		at(ctx, 0.3 + freeze, function()
			fade(dome, 0.25, { Size = Vector3.new(radius * 2.4, radius * 1.6, radius * 2.4) })
			fade(shell, 0.25)
			fx():Burst(center + Vector3.new(0, 4, 0), "Frost", 60, { Speed = NumberRange.new(20, 40) })
			for _ = 1, if low() then 6 else 14 do
				local shard = T.part(Vector3.new(0.6, 2.5, 0.6), CFrame.new(center + Vector3.new(0, 4, 0)), lighter(color), GLASS)
				local out = Vector3.new(math.random() - 0.5, math.random() * 0.6, math.random() - 0.5).Unit * radius
				fade(shard, 0.6, { CFrame = CFrame.new(center + out) * CFrame.Angles(math.random() * 6, math.random() * 6, 0) })
			end
			T.sound("BossSlam", 1, 1.5)
			T.shake(ctx, 0.6)
		end)
	end,
}

looks.GlacialSentinel = {
	Start = function(ctx)
		T.pose(ctx, "SentinelSummon", 1.0)
		T.sound("TierUp", 0.7, 1.4)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local spot = info.Spot or feetAt(ctx.Origin + ctx.Dir * 6)
		local duration = info.Duration or d.Duration
		local parts = {}
		local function add(size, offset, c, material, shape)
			local p = T.part(size, CFrame.new(spot + offset), c, material, shape)
			table.insert(parts, p)
			return p
		end
		local body = add(Vector3.new(4, 9, 4), Vector3.new(0, 4.5, 0), lighter(color), GLASS)
		add(Vector3.new(6, 1, 6), Vector3.new(0, 0.5, 0), color, GLASS)
		local head = add(Vector3.new(3, 3, 3), Vector3.new(0, 10, 0), lighter(color), GLASS)
		head.CFrame = head.CFrame * CFrame.Angles(math.rad(45), 0, math.rad(45))
		local eye = add(Vector3.new(1.4, 1.4, 1.4), Vector3.new(0, 9, 0), WHITE, NEON, BALL)
		for i = 1, 4 do
			local a = i / 4 * math.pi * 2
			local s = add(Vector3.new(1, 5, 1), Vector3.new(math.cos(a) * 2.6, 6, math.sin(a) * 2.6), lighter(color), GLASS)
			s.CFrame = s.CFrame * CFrame.Angles(math.cos(a) * 0.5, 0, -math.sin(a) * 0.5)
		end
		for _, p in ipairs(parts) do
			p.Transparency = 0.15
		end
		body.Transparency = 0.25
		-- rise out of the ground
		for _, p in ipairs(parts) do
			local goal = p.CFrame
			p.CFrame = goal - Vector3.new(0, 10, 0)
			T.tween(p, { CFrame = goal }, 0.5, Enum.EasingStyle.Back)
		end
		T.ring(spot, color, 10, 0.5, 2)
		fx():Burst(spot + Vector3.new(0, 2, 0), "Frost", 30)
		T.animate(duration, function()
			eye.Transparency = 0.1 + math.abs(math.sin(os.clock() * 5)) * 0.4
		end, function()
			for _, p in ipairs(parts) do
				fade(p, 0.5, { CFrame = p.CFrame - Vector3.new(0, 4, 0) })
			end
			fx():Burst(spot + Vector3.new(0, 5, 0), "Frost", 30)
		end)
	end,
	Hit = tagHit,
}

-- ===================================================================
-- Purple: Arcane Lightning
-- ===================================================================
looks.LightningStep = {
	Start = function(ctx)
		T.pose(ctx, "Blink", 0.7)
		T.sound("Dodge", 1, 1.4)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local points = info.Points or {}
		local interval = info.Interval or d.Interval
		for i = 2, #points do
			at(ctx, 0.12 + (i - 2) * interval, function()
				local a, b = points[i - 1], points[i]
				T.afterImage(CFrame.lookAt(a, a + ctx.Dir), color, 0.5)
				T.bolt(a + Vector3.new(0, 1, 0), b + Vector3.new(0, 1, 0), lighter(color), 0.8, 0.25)
				skyBolt(b, color)
				T.sound("Hit", 0.9, 1.8)
				if ctx.Local then
					local root = ctx.Root :: BasePart
					if root and root.Parent then
						root.CFrame = CFrame.new(b.X, math.max(root.Position.Y, b.Y), b.Z) * root.CFrame.Rotation
						root.AssemblyLinearVelocity = Vector3.zero
					end
				end
			end)
		end
		T.shake(ctx, 0.35)
	end,
}

looks.RailgunArc = {
	Start = function(ctx)
		local d = ctx.Def
		T.pose(ctx, "Railgun", d.Windup + 0.6)
		fx():Sphere(T.hand(ctx), lighter(d.Color), 0.5, 3, d.Windup, NEON)
		T.sound("TierUp", 0.6, 2)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		at(ctx, info.Windup or d.Windup, function()
			local from = rootPos(ctx) + ctx.Dir * 2 + Vector3.new(0, 1, 0)
			local chain = info.Chain or {}
			local first = if chain[1] then chain[1].Position else from + ctx.Dir * (info.Range or d.Range)
			-- the railgun slug: a straight white-hot beam to the first target
			local core = slab(from, first, 1.2, 1.2, WHITE, 0.35)
			slab(from, first, 3, 3, color, 0.45, FORCE)
			if core then
				T.addTrail(core, color, 1, 0.2)
			end
			T.ring(feetOf(ctx), color, 8, 0.3, 1)
			T.sound("Finisher", 1, 1.5)
			T.shake(ctx, 0.4)
			if ctx.Local then
				T.controllers().CameraController:Punch(-5, 0.25)
			end
			for i = 2, #chain do
				task.delay((i - 1) * 0.05, function()
					T.bolt(chain[i - 1].Position + Vector3.new(0, 1.5, 0), chain[i].Position + Vector3.new(0, 1.5, 0), lighter(color), 0.6, 0.3)
					fx():Burst(chain[i].Position, "Lightning", 6)
				end)
			end
		end)
	end,
}

looks.ThunderCage = {
	Start = function(ctx)
		T.pose(ctx, "CageDrive", 0.8, true)
		T.hop(ctx, 30)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local pillars = info.Pillars or {}
		local span = (info.Ticks or d.Ticks) * (info.Tick or d.Tick) + 0.3
		local posts = {}
		at(ctx, 0.35, function()
			T.sound("BossSlam", 1, 1.3)
			T.shake(ctx, 0.5)
			T.ring(feetAt(info.Center or ctx.Origin), color, d.Radius, 0.4, 2)
			for i, spot in ipairs(pillars) do
				local post = T.part(Vector3.new(1.4, 16, 1.4), CFrame.new(spot + Vector3.new(0, 8, 0)), lighter(color))
				post.Transparency = 0.1
				posts[i] = post
				skyBolt(spot + Vector3.new(0, 16, 0), color, 30)
			end
			T.animate(span, function()
				for _, post in ipairs(posts) do
					post.Transparency = 0.1 + math.abs(math.sin(os.clock() * 12)) * 0.4
				end
				if math.random() < (if low() then 0.15 else 0.45) and #pillars > 1 then
					local a = math.random(1, #pillars)
					local b = (a % #pillars) + 1
					if math.random() < 0.4 then
						b = math.random(1, #pillars)
					end
					local h = 2 + math.random() * 12
					T.bolt(pillars[a] + Vector3.new(0, h, 0), pillars[b] + Vector3.new(0, h, 0), lighter(color), 0.4, 0.15)
				end
			end, function()
				for _, post in ipairs(posts) do
					fade(post, 0.3, { Size = Vector3.new(0.2, 20, 0.2) })
				end
			end)
		end)
	end,
}

looks.StormOverload = {
	Start = function(ctx)
		if ctx.Info and ctx.Info.Bolt then
			return -- an overloaded swing: drawn in Result
		end
		T.pose(ctx, "Overload", 1.0)
		T.sound("TierUp", 1, 0.9)
		fx():Pillar(feetOf(ctx), ctx.Def.Color, 50, 0.8)
		if ctx.Local then
			fx():Flash(lighter(ctx.Def.Color), 0.3)
		end
		-- arcs crawl over the body for the whole overload
		local duration = ctx.Def.Duration
		T.animate(duration, function()
			local root = ctx.Root :: BasePart?
			if root and root.Parent and math.random() < (if low() then 0.08 else 0.25) then
				local a = root.Position + Vector3.new(math.random() - 0.5, math.random() * 2 - 0.5, math.random() - 0.5) * 3
				local b = root.Position + Vector3.new(math.random() - 0.5, math.random() * 2 - 0.5, math.random() - 0.5) * 3
				T.bolt(a, b, lighter(ctx.Def.Color), 0.2, 0.12)
			end
		end)
	end,
	Result = function(ctx, info)
		if typeof(info.Bolt) == "Vector3" then
			at(ctx, 0.12, function()
				skyBolt(info.Bolt, ctx.Def.Color)
				T.sound("Hit", 0.8, 2)
			end)
		end
	end,
}

-- ===================================================================
-- Red: Fire
-- ===================================================================
looks.CometDive = {
	Start = function(ctx)
		T.pose(ctx, "CometLeap", ctx.Def.Air + 0.5, true)
		T.sound("DoubleJump", 1, 0.7)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local landing = info.Landing or ctx.Origin + ctx.Dir * d.Length
		local air = math.max(0.2, (info.Air or d.Air) - (ctx.Elapsed or 0))
		leap(ctx, landing, air, 14)
		local ball = T.part(Vector3.new(5, 5, 5), CFrame.new(rootPos(ctx)), color, NEON, BALL)
		ball.Transparency = 0.35
		local fire = Instance.new("Fire")
		fire.Color = color
		fire.SecondaryColor = rgb(255, 230, 120)
		fire.Size = 8
		fire.Parent = ball
		T.addTrail(ball, color, 3, 0.4)
		T.animate(air, function()
			ball.CFrame = CFrame.new(rootPos(ctx))
		end, function()
			ball:Destroy()
			local spot = feetAt(landing)
			T.ring(spot, color, d.Radius, 0.5, 3)
			fx():Sphere(spot, rgb(255, 220, 120), 4, d.Radius * 2, 0.4, NEON)
			fx():Burst(spot + Vector3.new(0, 2, 0), "Embers", 50, { Speed = NumberRange.new(20, 40) })
			local crater = T.part(Vector3.new(0.3, d.Radius * 1.6, d.Radius * 1.6), CFrame.new(spot + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2), darker(color), NEON, CYL)
			crater.Transparency = 0.3
			task.delay(2, function()
				fade(crater, 0.6)
			end)
			T.sound("BossSlam", 1, 0.9)
			T.shake(ctx, 0.7)
		end)
	end,
}

looks.DragonBreath = {
	Start = function(ctx)
		local d = ctx.Def
		T.pose(ctx, "DragonBreath", 0.25 + d.Ticks * d.Tick + 0.15)
		T.sound("Finisher", 1, 0.5)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local sweep = info.Sweep or d.Sweep
		local span = (info.Ticks or d.Ticks) * (info.Tick or d.Tick)
		local range = info.Range or d.Range
		local lastPuff = 0
		at(ctx, 0.25, function()
			T.animate(span, function(k)
				local a = math.rad(-sweep / 2 + sweep * k)
				local dir = T.rotateY(ctx.Dir, a)
				local mouth = rootPos(ctx) + Vector3.new(0, 1.2, 0) + dir * 2
				if k - lastPuff > (if low() then 0.12 else 0.05) then
					lastPuff = k
					local puff = T.part(Vector3.new(2, 2, 2), CFrame.new(mouth), if math.random() < 0.5 then color else rgb(255, 210, 90), NEON, BALL)
					puff.Transparency = 0.2
					local to = mouth + dir * range + Vector3.new(0, math.random() * 4 - 1, 0)
					fade(puff, 0.45, { CFrame = CFrame.new(to), Size = Vector3.new(9, 9, 9) })
				end
			end)
		end)
	end,
}

looks.VolcanicEruption = {
	Start = function(ctx)
		T.pose(ctx, "EruptionStomp", 0.9)
		T.sound("BossSlam", 1, 0.6)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		at(ctx, 0.3, function()
			T.ring(feetOf(ctx), color, d.Radius, 0.6, 2)
			T.shake(ctx, 0.5)
		end)
		for i, spot in ipairs(info.Spots or {}) do
			-- a glowing crack, then the geyser
			at(ctx, 0.35 + (i - 1) * (info.Interval or d.Interval) - 0.25, function()
				local crack = T.part(Vector3.new(0.2, d.GeyserRadius * 1.4, d.GeyserRadius * 1.4), CFrame.new(spot + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2), color, NEON, CYL)
				crack.Transparency = 0.4
				fade(crack, 0.6)
			end)
			at(ctx, 0.35 + (i - 1) * (info.Interval or d.Interval), function()
				local column = T.part(Vector3.new(4, 2, 4), CFrame.new(spot + Vector3.new(0, 1, 0)), rgb(255, 150, 40), NEON, CYL)
				column.CFrame = CFrame.new(spot + Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
				column.Size = Vector3.new(2, 4, 4)
				T.tween(column, { Size = Vector3.new(22, 5, 5), CFrame = CFrame.new(spot + Vector3.new(0, 11, 0)) * CFrame.Angles(0, 0, math.pi / 2) }, 0.25)
				task.delay(0.3, function()
					fade(column, 0.4, { Size = Vector3.new(24, 0.5, 0.5) })
				end)
				fx():Burst(spot + Vector3.new(0, 4, 0), "Embers", 20, { Speed = NumberRange.new(20, 35) })
				T.sound("Slam", 0.7, 0.9 + math.random() * 0.3)
			end)
		end
	end,
}

looks.PhoenixRebirth = {
	Start = function(ctx)
		if ctx.Info and ctx.Info.Rebirth then
			return
		end
		T.pose(ctx, "PhoenixRise", 1.0)
		T.sound("TierUp", 1, 1.1)
		local color = ctx.Def.Color
		fx():Pillar(feetOf(ctx), color, 40, 0.8)
		-- fiery wings on the back for the duration
		local wings = {}
		for side = -1, 1, 2 do
			for f = 1, 3 do
				local w = T.part(Vector3.new(0.2, 1.2, 4 - f * 0.6), CFrame.new(), if f == 1 then color else rgb(255, 200, 80), NEON)
				w.Transparency = 0.25
				table.insert(wings, { Part = w, Side = side, F = f })
			end
		end
		T.animate(ctx.Def.Duration, function()
			local r = ctx.Root :: BasePart?
			if not r or not r.Parent then
				return
			end
			local flap = math.sin(os.clock() * 4) * 0.25
			for _, w in ipairs(wings) do
				w.Part.CFrame = r.CFrame * CFrame.new(w.Side * 0.8, 1.2, 0.7) * CFrame.Angles(0, w.Side * (0.9 + flap), w.Side * (0.35 + w.F * 0.25)) * CFrame.new(0, 0, 2.2)
			end
		end, function()
			for _, w in ipairs(wings) do
				fade(w.Part, 0.4)
			end
		end)
	end,
	Result = function(ctx, info)
		if not info.Rebirth then
			return
		end
		-- reborn: a burst of phoenix fire and a rising firebird
		local color = ctx.Def.Color
		local spot = feetOf(ctx)
		T.ring(spot, color, ctx.Def.Radius, 0.6, 4)
		fx():Sphere(spot + Vector3.new(0, 3, 0), rgb(255, 230, 140), 3, 30, 0.5, NEON)
		fx():Burst(spot + Vector3.new(0, 3, 0), "Embers", 70, { Speed = NumberRange.new(20, 45) })
		local bird = T.part(Vector3.new(10, 0.4, 4), CFrame.new(spot + Vector3.new(0, 3, 0)), color, NEON)
		fade(bird, 1, { CFrame = CFrame.new(spot + Vector3.new(0, 40, 0)), Size = Vector3.new(24, 0.4, 8) })
		T.sound("Rebirth", 1, 1.2)
		if ctx.Character == Players.LocalPlayer.Character then
			T.controllers().CameraController:Shake(0.6)
			fx():Flash(rgb(255, 200, 120), 0.4)
		end
	end,
}

-- ===================================================================
-- Black: Smoke Storm
-- ===================================================================
looks.ThunderheadSurf = {
	Start = function(ctx)
		local d = ctx.Def
		T.pose(ctx, "CloudSurf", d.Time + 0.3)
		T.dash(ctx, d.Length, d.Time, d.Color)
		T.sound("Dodge", 1, 0.5)
		-- the storm cloud under the feet
		local puffs = {}
		for i = 1, if low() then 3 else 6 do
			local p = T.part(Vector3.new(4, 2.2, 4), CFrame.new(), if i % 2 == 0 then rgb(70, 70, 90) else rgb(120, 122, 145), Enum.Material.SmoothPlastic, BALL)
			p.Transparency = 0.15
			puffs[i] = { Part = p, A = i / 6 * math.pi * 2 }
		end
		T.animate(d.Time + 0.2, function()
			local root = ctx.Root :: BasePart?
			if not root or not root.Parent then
				return
			end
			local base = root.Position - Vector3.new(0, 3, 0)
			for _, p in ipairs(puffs) do
				local a = p.A + os.clock() * 3
				p.Part.CFrame = CFrame.new(base + Vector3.new(math.cos(a) * 2.2, math.sin(a * 2) * 0.3, math.sin(a) * 2.2))
			end
		end, function()
			for _, p in ipairs(puffs) do
				fade(p.Part, 0.4, { Size = Vector3.new(7, 3, 7) })
			end
		end)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local length, time = info.Length or d.Length, info.Time or d.Time
		for i = 1, d.Strikes do
			at(ctx, time * i / d.Strikes, function()
				local spot = ctx.Origin + ctx.Dir * length * i / d.Strikes
				skyBolt(feetAt(spot) + Vector3.new(0, 0.5, 0), color, 14)
				T.sound("Hit", 0.6, 1.6)
			end)
		end
	end,
}

looks.SpearBarrage = {
	Start = function(ctx)
		T.pose(ctx, "SpearCall", 0.9)
		skyBolt(rootPos(ctx) + Vector3.new(0, 4, 0), ctx.Def.Color, 30)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		for i, spot in ipairs(info.Spots or {}) do
			at(ctx, 0.25 + (i - 1) * (info.Interval or d.Interval) - 0.12, function()
				local top = spot + Vector3.new(0, 40, 0)
				local spear = T.part(Vector3.new(0.7, 0.7, 9), CFrame.lookAt(top, spot), lighter(color))
				T.addTrail(spear, color, 0.7, 0.2)
				T.animate(0.12, function(k)
					spear.CFrame = CFrame.lookAt(top:Lerp(spot, k), spot)
				end, function()
					fade(spear, 0.6, { Size = Vector3.new(0.3, 0.3, 9) })
					T.ring(spot + Vector3.new(0, 0.1, 0), color, d.Radius, 0.3, 1)
					fx():Burst(spot, "Lightning", 8)
					T.sound("Hit", 0.5, 1.4 + math.random() * 0.4)
				end)
			end)
		end
	end,
}

looks.BlackTempest = {
	Start = function(ctx)
		T.pose(ctx, "TempestSpin", 1.8)
		T.sound("Finisher", 1, 0.4)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local center = feetAt(info.Center or ctx.Origin)
		local radius = info.Radius or d.Radius
		local wall = T.part(Vector3.new(14, 2, 2), CFrame.new(center + Vector3.new(0, 7, 0)) * CFrame.Angles(0, 0, math.pi / 2), rgb(40, 40, 55), FORCE, CYL)
		wall.Transparency = 0.25
		local inner = T.part(Vector3.new(12, 2, 2), wall.CFrame, color, FORCE, CYL)
		inner.Transparency = 0.5
		T.animate(1.7, function(k)
			-- out to the edge by 0.3s, hold, then back in from 1.2s
			local r
			if k < 0.18 then
				r = radius * (k / 0.18)
			elseif k < 0.7 then
				r = radius
			else
				r = radius * (1 - (k - 0.7) / 0.3) + 2
			end
			local spin = CFrame.Angles(0, os.clock() * 6, 0)
			wall.Size = Vector3.new(14, r * 2, r * 2)
			inner.Size = Vector3.new(12, r * 1.8, r * 1.8)
			wall.CFrame = CFrame.new(center + Vector3.new(0, 7, 0)) * spin * CFrame.Angles(0, 0, math.pi / 2)
			inner.CFrame = wall.CFrame
		end, function()
			fade(wall, 0.3)
			fade(inner, 0.3)
			fx():Sphere(center + Vector3.new(0, 2, 0), rgb(60, 60, 80), 2, 18, 0.4)
			T.sound("BossSlam", 1, 0.7)
			T.shake(ctx, 0.6)
		end)
		at(ctx, 0.3, function()
			T.ring(center, color, radius, 0.4, 3)
			T.sound("BossSlam", 0.8, 1)
		end)
		for i = 1, d.Bolts do
			at(ctx, 0.4 + i * 0.12, function()
				local a, r = math.random() * math.pi * 2, math.random() * radius
				skyBolt(center + Vector3.new(math.cos(a) * r, 0.5, math.sin(a) * r), color, 35)
			end)
		end
	end,
}

looks.StormClones = {
	Start = function(ctx)
		T.pose(ctx, "CloneSplit", 0.8)
		T.sound("Dodge", 1, 0.9)
		fx():Burst(rootPos(ctx), "Smoke", 30)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local clones = info.Clones or d.Clones
		local bodies = {}
		for i = 1, clones do
			local torso = T.part(Vector3.new(2, 2.6, 1.1), CFrame.new(), rgb(40, 40, 58), FORCE)
			local head = T.part(Vector3.new(1.3, 1.3, 1.3), CFrame.new(), rgb(40, 40, 58), FORCE, BALL)
			local legs = T.part(Vector3.new(1.7, 2.2, 1), CFrame.new(), rgb(40, 40, 58), FORCE)
			local eyes = T.part(Vector3.new(0.9, 0.2, 0.2), CFrame.new(), color, NEON)
			bodies[i] = { torso, head, legs, eyes }
		end
		local duration = info.Duration or d.Duration
		T.animate(duration, function()
			local root = ctx.Root :: BasePart?
			if not root or not root.Parent then
				return
			end
			for i, b in ipairs(bodies) do
				local a = (i - 1) / clones * math.pi * 2 + os.clock() * 0.6
				local pos = root.Position + Vector3.new(math.cos(a) * 7, math.sin(os.clock() * 3 + i) * 0.4, math.sin(a) * 7)
				local cf = CFrame.lookAt(pos, pos + root.CFrame.LookVector)
				b[1].CFrame = cf
				b[2].CFrame = cf * CFrame.new(0, 2, 0)
				b[3].CFrame = cf * CFrame.new(0, -2.4, 0)
				b[4].CFrame = cf * CFrame.new(0, 2.1, -0.6)
				if math.random() < (if low() then 0.03 else 0.1) then
					T.bolt(pos + Vector3.new(0, 1, 0), pos + Vector3.new(math.random() - 0.5, math.random(), math.random() - 0.5) * 4, color, 0.15, 0.1)
				end
			end
		end, function()
			for _, b in ipairs(bodies) do
				for _, p in ipairs(b) do
					fade(p, 0.4)
				end
				fx():Burst(b[1].Position, "Smoke", 10)
			end
		end)
	end,
	Hit = tagHit,
}

-- ===================================================================
-- White: Holy Light
-- ===================================================================
looks.RadiantAscension = {
	Start = function(ctx)
		T.pose(ctx, "Ascend", ctx.Def.Air + 0.5, true)
		local color = ctx.Def.Color
		fx():Pillar(feetOf(ctx), color, 60, 0.7)
		T.sound("TierUp", 0.8, 1.6)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local landing = info.Landing or ctx.Origin + ctx.Dir * d.Length
		local air = math.max(0.2, (info.Air or d.Air) - (ctx.Elapsed or 0))
		leap(ctx, landing, air, 22)
		local spot = feetAt(landing)
		-- a target circle of light where it will land
		local mark = T.part(Vector3.new(0.2, d.Radius * 2, d.Radius * 2), CFrame.new(spot + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2), color, NEON, CYL)
		mark.Transparency = 0.6
		task.delay(air, function()
			mark:Destroy()
			local beam = T.part(Vector3.new(80, d.Radius * 1.2, d.Radius * 1.2), CFrame.new(spot + Vector3.new(0, 40, 0)) * CFrame.Angles(0, 0, math.pi / 2), WHITE, NEON, CYL)
			beam.Transparency = 0.1
			fade(beam, 0.6, { Size = Vector3.new(80, 0.5, 0.5) })
			local glow = T.part(Vector3.new(80, d.Radius * 2, d.Radius * 2), beam.CFrame, color, FORCE, CYL)
			fade(glow, 0.7)
			T.ring(spot, color, d.Radius * 1.4, 0.5, 2)
			fx():Burst(spot + Vector3.new(0, 2, 0), "Radiance", 40)
			T.sound("BossSlam", 1, 1.4)
			T.shake(ctx, 0.6)
			if ctx.Local then
				fx():Flash(WHITE, 0.25)
			end
		end)
	end,
}

looks.PrismBeam = {
	Start = function(ctx)
		T.pose(ctx, "PrismCast", 0.9)
		T.sound("TierUp", 0.6, 1.8)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local prism = info.Prism or ctx.Origin + ctx.Dir * d.Length
		local spinner = T.part(Vector3.new(3, 4, 3), CFrame.new(prism + Vector3.new(0, 1, 0)), lighter(color), GLASS)
		spinner.Transparency = 0.2
		T.animate(0.9, function(k)
			spinner.CFrame = CFrame.new(prism + Vector3.new(0, 1, 0)) * CFrame.Angles(0, k * 10, math.rad(45))
		end, function()
			fade(spinner, 0.3)
		end)
		at(ctx, 0.35, function()
			local from = rootPos(ctx) + ctx.Dir * 2 + Vector3.new(0, 1, 0)
			slab(from, prism + Vector3.new(0, 1, 0), 1.6, 1.6, WHITE, 0.45)
			slab(from, prism + Vector3.new(0, 1, 0), 3.5, 3.5, color, 0.5, FORCE)
			T.sound("Finisher", 1, 1.6)
		end)
		local hues = { rgb(255, 120, 140), rgb(255, 250, 200), rgb(140, 200, 255) }
		at(ctx, 0.5, function()
			for i, a in ipairs(info.Angles or {}) do
				local dir = T.rotateY(ctx.Dir, math.rad(a))
				local start = prism + Vector3.new(0, 1, 0)
				local finish = start + dir * (info.SplitLength or d.SplitLength)
				slab(start, finish, 1.2, 1.2, hues[(i - 1) % #hues + 1], 0.45)
				slab(start, finish, 2.6, 2.6, color, 0.5, FORCE)
			end
			fx():Burst(prism + Vector3.new(0, 1, 0), "Radiance", 20)
			T.shake(ctx, 0.35)
		end)
	end,
}

looks.JudgmentSwords = {
	Start = function(ctx)
		T.pose(ctx, "JudgmentRaise", 1.3)
		T.sound("TierUp", 0.8, 1.2)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		for i, spot in ipairs(info.Spots or {}) do
			at(ctx, 0.35 + (i - 1) * 0.08 - 0.15, function()
				local top = spot + Vector3.new(0, 35, 0)
				local blade = T.part(Vector3.new(1.2, 12, 0.4), CFrame.new(top), WHITE, NEON)
				local guard = T.part(Vector3.new(4, 0.6, 0.6), CFrame.new(top + Vector3.new(0, 6, 0)), color, NEON)
				T.animate(0.15, function(k)
					local p = top:Lerp(spot + Vector3.new(0, 4, 0), k * k)
					blade.CFrame = CFrame.new(p)
					guard.CFrame = CFrame.new(p + Vector3.new(0, 6, 0))
				end, function()
					T.ring(spot, color, d.SwordRadius, 0.35, 1)
					fx():Burst(spot + Vector3.new(0, 1, 0), "Radiance", 10)
					T.sound("Slam", 0.7, 1.3)
					task.delay(1, function()
						fade(blade, 0.4)
						fade(guard, 0.4)
					end)
				end)
			end)
		end
		at(ctx, info.Boom or 1.3, function()
			local center = feetAt(info.Center or ctx.Origin)
			fx():Sphere(center + Vector3.new(0, 2, 0), WHITE, 4, d.CenterRadius * 2, 0.5, NEON)
			T.ring(center, color, d.CenterRadius, 0.5, 3)
			fx():Pillar(center, color, 70, 0.8)
			T.sound("BossSlam", 1, 1.2)
			T.shake(ctx, 0.7)
			if ctx.Local then
				fx():Flash(WHITE, 0.3)
			end
		end)
	end,
}

looks.DawnSanctuary = {
	Start = function(ctx)
		T.pose(ctx, "Pray", 1.2)
		T.sound("Rebirth", 0.7, 1.4)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local center = feetAt(info.Center or ctx.Origin)
		local radius = info.Radius or d.Radius
		local floor = T.part(Vector3.new(0.3, radius * 2, radius * 2), CFrame.new(center + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.pi / 2), color, NEON, CYL)
		floor.Transparency = 0.55
		local edge = T.part(Vector3.new(5, radius * 2, radius * 2), CFrame.new(center + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, 0, math.pi / 2), lighter(color), FORCE, CYL)
		edge.Transparency = 0.6
		local motes = 0
		T.animate(info.Duration or d.Duration, function()
			floor.Transparency = 0.5 + math.sin(os.clock() * 3) * 0.1
			motes += 1
			if motes % (if low() then 12 else 4) == 0 then
				local a, r = math.random() * math.pi * 2, math.random() * radius
				fx():Burst(center + Vector3.new(math.cos(a) * r, 0.5, math.sin(a) * r), "Radiance", 2, { Speed = NumberRange.new(3, 6) })
			end
		end, function()
			fade(floor, 0.5)
			fade(edge, 0.5)
		end)
		T.ring(center, WHITE, radius, 0.6, 2)
	end,
}

-- ===================================================================
-- Gold: Sun
-- ===================================================================
looks.SunflareCharge = {
	Start = function(ctx)
		local d = ctx.Def
		T.pose(ctx, "ShoulderCharge", 0.75)
		T.dash(ctx, d.Length, 0.4, d.Color)
		T.sound("Finisher", 1, 0.9)
		local shell = T.part(Vector3.new(6, 6, 6), CFrame.new(rootPos(ctx)), d.Color, FORCE, BALL)
		shell.Transparency = 0.3
		T.animate(0.45, function()
			shell.CFrame = CFrame.new(rootPos(ctx))
		end, function()
			fade(shell, 0.2)
		end)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local length = info.Length or d.Length
		local a = feetAt(ctx.Origin) + Vector3.new(0, 0.2, 0)
		slab(a, a + ctx.Dir * length, d.Width * 0.6, 0.3, color, 0.8)
		at(ctx, 0.42, function()
			local finish = ctx.Origin + ctx.Dir * length
			fx():Sphere(finish, rgb(255, 245, 190), 3, d.EndRadius * 2, 0.4, NEON)
			T.ring(feetAt(finish), color, d.EndRadius, 0.45, 2)
			fx():Burst(finish, "Radiance", 30, { Color = ColorSequence.new(color, WHITE) })
			T.sound("BossSlam", 1, 1.3)
			T.shake(ctx, 0.5)
		end)
	end,
}

looks.SunspearJavelin = {
	Start = function(ctx)
		T.pose(ctx, "Javelin", 0.8)
		T.sound("Swing", 1, 0.8)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local impact = info.Impact or ctx.Origin + ctx.Dir * d.Length
		local flight = math.max(0.05, (info.Flight or 0.4) - (ctx.Elapsed or 0))
		local from = rootPos(ctx) + Vector3.new(0, 2, 0)
		local to = impact + Vector3.new(0, 1, 0)
		local spear = T.part(Vector3.new(0.6, 0.6, 8), CFrame.lookAt(from, to), rgb(255, 245, 200))
		local head = T.part(Vector3.new(1.1, 1.1, 2), CFrame.new(), color)
		T.addTrail(spear, color, 1, 0.3)
		T.animate(flight, function(k)
			local p = from:Lerp(to, k) + Vector3.new(0, 4 * 4 * k * (1 - k), 0)
			spear.CFrame = CFrame.lookAt(p, to)
			head.CFrame = spear.CFrame * CFrame.new(0, 0, -4.5)
		end, function()
			-- pinned and swelling with light until it goes off
			local core = T.part(Vector3.new(2, 2, 2), CFrame.new(to), rgb(255, 250, 220), NEON, BALL)
			T.tween(core, { Size = Vector3.new(6, 6, 6) }, info.Fuse or d.Fuse)
			T.sound("TierUp", 0.6, 2)
			task.delay(info.Fuse or d.Fuse, function()
				spear:Destroy()
				head:Destroy()
				core:Destroy()
				fx():Sphere(to, rgb(255, 240, 170), 4, d.Radius * 2, 0.5, NEON)
				T.ring(feetAt(to + Vector3.new(0, 1.9, 0)), color, d.Radius, 0.5, 3)
				fx():Burst(to, "Radiance", 40, { Speed = NumberRange.new(20, 40) })
				T.sound("BossSlam", 1, 1.1)
				T.shake(ctx, 0.6)
			end)
		end)
	end,
}

looks.Supernova = {
	Start = function(ctx)
		local d = ctx.Def
		T.pose(ctx, "NovaCharge", d.Charge + 0.6)
		T.sound("TierUp", 1, 0.6)
		local orb = T.part(Vector3.new(14, 14, 14), CFrame.new(rootPos(ctx)), d.Color, FORCE, BALL)
		orb.Transparency = 0.6
		T.tween(orb, { Size = Vector3.new(4, 4, 4), Transparency = 0.1 }, d.Charge, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local core = T.part(Vector3.new(1, 1, 1), CFrame.new(rootPos(ctx)), WHITE, NEON, BALL)
		T.tween(core, { Size = Vector3.new(4.5, 4.5, 4.5) }, d.Charge)
		T.animate(d.Charge, function()
			orb.CFrame = CFrame.new(rootPos(ctx))
			core.CFrame = orb.CFrame
		end, function()
			orb:Destroy()
			core:Destroy()
		end)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		at(ctx, info.Charge or d.Charge, function()
			local center = rootPos(ctx)
			local radius = info.Radius or d.Radius
			fx():Sphere(center, rgb(255, 250, 220), 4, radius * 2, 0.6, NEON)
			fx():Sphere(center, color, 4, radius * 2.4, 0.8)
			for i = 1, 3 do
				T.ring(feetAt(center), if i == 2 then WHITE else color, radius * (0.5 + i * 0.25), 0.4 + i * 0.15, 2 + i)
			end
			fx():Burst(center, "Radiance", 80, { Speed = NumberRange.new(30, 60) })
			T.sound("BossSlam", 1, 0.6)
			T.sound("Rebirth", 0.8, 1.4)
			T.shake(ctx, 1)
			if ctx.Local then
				fx():Flash(rgb(255, 245, 210), 0.5)
				T.controllers().CameraController:Punch(-12, 0.5)
			end
		end)
	end,
}

looks.SolarCrown = {
	Start = function(ctx)
		T.pose(ctx, "CrownRaise", 1.1)
		T.sound("TierUp", 1, 1.2)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local duration = info.Duration or d.Duration
		local radius = info.Radius or d.Radius
		local sun = T.part(Vector3.new(3, 3, 3), CFrame.new(), rgb(255, 245, 190), NEON, BALL)
		local halo = T.part(Vector3.new(5, 5, 5), CFrame.new(), color, FORCE, BALL)
		halo.Transparency = 0.4
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 18
		light.Brightness = 2
		light.Parent = sun
		local crown = {}
		for i = 1, 6 do
			local spike = T.part(Vector3.new(0.4, 1.2, 0.4), CFrame.new(), color, NEON)
			crown[i] = spike
		end
		local burnRing = T.part(Vector3.new(0.2, radius * 2, radius * 2), CFrame.new(), color, NEON, CYL)
		burnRing.Transparency = 0.75
		T.animate(duration, function()
			local root = ctx.Root :: BasePart?
			if not root or not root.Parent then
				return
			end
			local t = os.clock()
			sun.CFrame = CFrame.new(root.Position + Vector3.new(math.cos(t * 2.4) * radius * 0.6, 2.5, math.sin(t * 2.4) * radius * 0.6))
			halo.CFrame = sun.CFrame
			halo.Size = Vector3.new(5, 5, 5) * (1 + math.sin(t * 6) * 0.1)
			for i, spike in ipairs(crown) do
				local a = i / 6 * math.pi * 2 + t
				spike.CFrame = CFrame.new(root.Position + Vector3.new(math.cos(a) * 0.9, 3.4, math.sin(a) * 0.9))
			end
			burnRing.CFrame = CFrame.new(T.feet(root) + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		end, function()
			fade(sun, 0.4)
			fade(halo, 0.4)
			fade(burnRing, 0.4)
			for _, spike in ipairs(crown) do
				fade(spike, 0.4)
			end
		end)
	end,
}

-- ===================================================================
-- Crimson: Blood
-- ===================================================================
looks.BloodRend = {
	Start = function(ctx)
		T.pose(ctx, "RendDash", 0.9)
		T.sound("Finisher", 1, 1.3)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local path = info.Path or {}
		local step = info.Step or d.Step
		local points = { ctx.Origin }
		for _, p in ipairs(path) do
			table.insert(points, p)
		end
		travel(ctx, points, step, color)
		for i = 2, #points do
			at(ctx, (i - 1) * step, function()
				local a, b = points[i - 1], points[i]
				slab(a + Vector3.new(0, 1, 0), b + Vector3.new(0, 1, 0), 0.5, 0.5, color, 0.6)
				-- an X of blood where the cut lands
				local mid = b - (b - a).Unit * 3.5 + Vector3.new(0, 1, 0)
				for s = -1, 1, 2 do
					local cut = T.part(Vector3.new(0.3, 0.3, 6), CFrame.new(mid) * CFrame.Angles(0, math.atan2((b - a).X, (b - a).Z), 0) * CFrame.Angles(0, 0, s * 0.8) * CFrame.Angles(math.pi / 2, 0, 0), color)
					fade(cut, 0.4, { Size = Vector3.new(0.1, 0.1, 8) })
				end
				fx():Burst(mid, "BloodFlame", 10)
				T.sound("Hit", 1, 0.9 + i * 0.05)
			end)
		end
	end,
}

looks.HemorrhageScythe = {
	Start = function(ctx)
		T.pose(ctx, "ScytheFling", 0.8)
		T.sound("Swing", 1, 0.6)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local center = (info.Center or ctx.Origin) + Vector3.new(0, 0.8, 0)
		local radius, turns, time = info.Radius or d.Radius, info.Turns or d.Turns, info.Time or d.Time
		local blade = crescent(center, ctx.Dir, 3, color, 1)
		local handle = T.part(Vector3.new(0.4, 0.4, 7), CFrame.new(center), darker(color), Enum.Material.Metal)
		table.insert(blade, handle)
		local origins = {}
		for i, p in ipairs(blade) do
			origins[i] = CFrame.new(center):ToObjectSpace(p.CFrame)
		end
		local lastDrop = 0
		T.animate(time, function(k)
			local spot = center + T.rotateY(ctx.Dir, k * turns * math.pi * 2) * (radius * k)
			local cf = CFrame.new(spot) * CFrame.Angles(0, os.clock() * 18, 0)
			for i, p in ipairs(blade) do
				p.CFrame = cf * origins[i]
			end
			if k - lastDrop > 0.05 then
				lastDrop = k
				local drop = T.part(Vector3.new(0.2, 2.4, 2.4), CFrame.new(feetAt(spot + Vector3.new(0, 2.1, 0))) * CFrame.Angles(0, 0, math.pi / 2), darker(color), NEON, CYL)
				drop.Transparency = 0.3
				task.delay(1.2, function()
					fade(drop, 0.5)
				end)
			end
		end, function()
			fadeGroup(blade, 0.2)
		end)
	end,
}

looks.BloodMoon = {
	Start = function(ctx)
		T.pose(ctx, "MoonCall", 1.2)
		T.sound("Rebirth", 0.8, 0.6)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local span = 0.5 + (info.Ticks or d.Ticks) * (info.Tick or d.Tick)
		local moon = T.part(Vector3.new(14, 14, 14), CFrame.new(rootPos(ctx) + Vector3.new(0, 10, 0)), color, NEON, BALL)
		moon.Transparency = 0.15
		local corona = T.part(Vector3.new(20, 20, 20), moon.CFrame, darker(color), FORCE, BALL)
		corona.Transparency = 0.5
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 60
		light.Brightness = 2.5
		light.Parent = moon
		local start = rootPos(ctx)
		T.animate(span, function(k)
			local rise = math.min(1, k * 3)
			local cf = CFrame.new(start + Vector3.new(0, 10 + rise * 28, 0))
			moon.CFrame = cf
			corona.CFrame = cf
		end, function()
			fade(moon, 0.6)
			fade(corona, 0.6)
		end)
		for i = 1, info.Ticks or d.Ticks do
			at(ctx, 0.5 + (i - 1) * (info.Tick or d.Tick), function()
				T.ring(feetOf(ctx), color, info.Radius or d.Radius, 0.4, 1)
				T.sound("Hit", 0.5, 0.6)
			end)
		end
		if ctx.Local then
			T.controllers().EffectsController:Vignette(color, 0.4, span)
		end
	end,
}

looks.BloodPact = {
	Start = function(ctx)
		if ctx.Info and ctx.Info.Crescent then
			return -- a pact swing: drawn in Result
		end
		T.pose(ctx, "PactCut", 1.0)
		T.sound("Hurt", 1, 0.8)
		local color = ctx.Def.Color
		fx():Burst(rootPos(ctx), "BloodFlame", 30)
		-- a red aura that drips for the duration
		T.animate(ctx.Def.Duration, function()
			local root = ctx.Root :: BasePart?
			if root and root.Parent and math.random() < (if low() then 0.05 else 0.2) then
				fx():Burst(root.Position + Vector3.new(0, math.random() * 2 - 1, 0), "BloodFlame", 2)
			end
		end)
		if ctx.Local then
			T.controllers().EffectsController:Vignette(color, 0.3, 0.8)
		end
	end,
	Result = function(ctx, info)
		if not info.Crescent then
			return
		end
		local color = ctx.Def.Color
		local length = info.Length or ctx.Def.WaveLength
		local start = ctx.Origin + Vector3.new(0, 0.6, 0)
		local blade = crescent(start, ctx.Dir, 3.5, color, 0.9)
		local origins = {}
		for i, p in ipairs(blade) do
			origins[i] = CFrame.new(start):ToObjectSpace(p.CFrame)
		end
		T.animate(0.28, function(k)
			local cf = CFrame.new(start + ctx.Dir * length * k)
			for i, p in ipairs(blade) do
				p.CFrame = cf * origins[i]
				p.Transparency = k * 0.8
			end
		end, function()
			fadeGroup(blade, 0.1)
		end)
	end,
}

-- ===================================================================
-- Shadow: Darkness
-- ===================================================================
looks.ShadowSwap = {
	Start = function(ctx)
		T.pose(ctx, "ShadowSink", 0.8)
		T.sound("Dodge", 1, 0.5)
		local puddle = T.part(Vector3.new(0.2, 6, 6), CFrame.new(feetOf(ctx) + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2), BLACK, NEON, CYL)
		puddle.Transparency = 0.1
		fade(puddle, 0.8, { Size = Vector3.new(0.2, 1, 1) })
	end,
	Result = function(ctx, info)
		local color = ctx.Def.Color
		local to = info.To
		if typeof(to) ~= "Vector3" then
			return
		end
		at(ctx, 0.15, function()
			fx():Burst(rootPos(ctx), "Shadow", 20)
			if ctx.Local then
				local root = ctx.Root :: BasePart
				if root and root.Parent then
					local face = if typeof(info.Target) == "Vector3" then Vector3.new(info.Target.X - to.X, 0, info.Target.Z - to.Z) else ctx.Dir
					root.CFrame = CFrame.new(to.X, math.max(root.Position.Y, to.Y), to.Z) * CFrame.lookAt(Vector3.zero, if face.Magnitude > 0.05 then face.Unit else ctx.Dir)
					root.AssemblyLinearVelocity = Vector3.zero
				end
			end
			local puddle = T.part(Vector3.new(0.2, 6, 6), CFrame.new(feetAt(to) + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2), BLACK, NEON, CYL)
			fade(puddle, 0.6, { Size = Vector3.new(0.2, 9, 9) })
			fx():Burst(to, "Shadow", 25)
		end)
		at(ctx, 0.3, function()
			if typeof(info.Target) == "Vector3" then
				for s = -1, 1, 2 do
					local cut = T.part(Vector3.new(0.4, 0.4, 9), CFrame.new(info.Target + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, math.random() * 6, s * 0.7), color)
					fade(cut, 0.35, { Size = Vector3.new(0.1, 0.1, 12) })
				end
				fx():Burst(info.Target, "Void", 20)
			end
			T.sound("Finisher", 1, 0.8)
			T.shake(ctx, 0.5)
		end)
	end,
}

looks.ShadowSerpent = {
	Start = function(ctx)
		T.pose(ctx, "SerpentCast", 0.9)
		T.sound("Swing", 0.8, 0.5)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local chain = info.Chain or {}
		local route = { rootPos(ctx) + ctx.Dir * 2 }
		for _, c in ipairs(chain) do
			table.insert(route, c.Position + Vector3.new(0, 1, 0))
		end
		if #chain == 0 then
			table.insert(route, ctx.Origin + ctx.Dir * (info.Range or d.Range))
		end
		local segments = {}
		local count = if low() then 6 else 12
		for i = 1, count do
			local s = 1.6 - i * 0.08
			local p = T.part(Vector3.new(s, s, s), CFrame.new(route[1]), if i == 1 then color else BLACK, if i == 1 then NEON else FORCE, BALL)
			p.Transparency = if i == 1 then 0 else 0.2
			segments[i] = p
		end
		local history = {}
		local legs = #route - 1
		local first = 0.3
		local interval = info.Interval or d.Interval
		local total = first + (legs - 1) * interval
		T.animate(total + 0.2, function(k)
			local t = k * (total + 0.2)
			local f = if t < first then t / first else 1 + (t - first) / interval
			local i = math.clamp(math.floor(f) + 1, 1, legs)
			local a, b = route[i], route[i + 1]
			local local01 = math.clamp(f - (i - 1), 0, 1)
			local side = T.rotateY((b - a).Unit, math.pi / 2)
			local head = a:Lerp(b, local01) + side * math.sin(local01 * math.pi * 3) * 1.5
			table.insert(history, 1, head)
			if #history > count * 2 then
				table.remove(history)
			end
			for n, p in ipairs(segments) do
				p.CFrame = CFrame.new(history[math.min(#history, (n - 1) * 2 + 1)])
			end
		end, function()
			fadeGroup(segments, 0.3)
		end)
		for i, c in ipairs(chain) do
			at(ctx, first + (i - 1) * interval, function()
				fx():Burst(c.Position + Vector3.new(0, 1, 0), "Shadow", 12)
				T.sound("Hit", 0.7, 0.7)
			end)
		end
	end,
}

looks.NightFall = {
	Start = function(ctx)
		T.pose(ctx, "NightGrasp", 1.3)
		T.sound("BossSpawn", 0.6, 1.3)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local delay = info.Delay or d.Delay
		local dome = T.part(Vector3.new(4, 4, 4), CFrame.new(rootPos(ctx)), BLACK, FORCE, BALL)
		dome.Transparency = 0.3
		T.tween(dome, { Size = Vector3.new(d.Radius * 2, d.Radius * 1.2, d.Radius * 2) }, 0.35)
		task.delay(0.6 + delay, function()
			fade(dome, 0.5)
		end)
		if ctx.Local then
			T.controllers().EffectsController:Vignette(BLACK, 0.55, 0.6 + delay)
		end
		for _, p in ipairs(info.Points or {}) do
			local base = p.Position - Vector3.new(0, (p.Height or 5) * 0.4, 0)
			at(ctx, 0.3, function()
				-- shadow hands close round the enemy
				for f = 1, 4 do
					local a = f / 4 * math.pi * 2
					local finger = T.part(Vector3.new(0.6, 4, 0.6), CFrame.new(base + Vector3.new(math.cos(a) * 1.6, 2, math.sin(a) * 1.6)) * CFrame.Angles(math.sin(a) * 0.4, 0, -math.cos(a) * 0.4), BLACK, NEON)
					task.delay(delay, function()
						fade(finger, 0.3)
					end)
				end
			end)
			at(ctx, 0.3 + delay, function()
				local spike = T.part(Vector3.new(1.4, 0.5, 1.4), CFrame.new(base), color, NEON)
				T.tween(spike, { Size = Vector3.new(1.2, 12, 1.2), CFrame = CFrame.new(base + Vector3.new(0, 6, 0)) }, 0.12)
				task.delay(0.35, function()
					fade(spike, 0.3, { Size = Vector3.new(0.2, 12, 0.2) })
				end)
			end)
		end
		at(ctx, 0.3 + delay, function()
			T.sound("BossSlam", 1, 0.8)
			T.shake(ctx, 0.6)
		end)
	end,
}

looks.ShadowRealm = {
	Start = function(ctx)
		T.pose(ctx, "RealmStep", 0.9)
		T.sound("BossSpawn", 0.5, 1.6)
		fx():Burst(rootPos(ctx), "Shadow", 30)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local duration = info.Duration or d.Duration
		local character = ctx.Character :: Model?
		-- fade the caster into the dark (locally drawn transparency)
		local saved = {}
		if character then
			for _, p in ipairs(character:GetDescendants()) do
				if p:IsA("BasePart") and p.Transparency < 1 then
					saved[p] = p.Transparency
					p.LocalTransparencyModifier = 0.75
				end
			end
		end
		if ctx.Local then
			T.controllers().EffectsController:Vignette(rgb(60, 20, 110), 0.5, duration)
		end
		T.animate(duration, function()
			local root = ctx.Root :: BasePart?
			if root and root.Parent and math.random() < (if low() then 0.08 else 0.3) then
				fx():Burst(root.Position, "Shadow", 2)
			end
		end, function()
			for p in pairs(saved) do
				if p.Parent then
					p.LocalTransparencyModifier = 0
				end
			end
			local center = feetOf(ctx)
			fx():Sphere(center + Vector3.new(0, 2, 0), BLACK, 4, (info.Radius or d.EndRadius) * 2, 0.4)
			T.ring(center, color, info.Radius or d.EndRadius, 0.45, 3)
			for _ = 1, if low() then 6 else 14 do
				local a, r = math.random() * math.pi * 2, math.random() * (info.Radius or d.EndRadius)
				local spot = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
				local spike = T.part(Vector3.new(1, 10, 1), CFrame.new(spot + Vector3.new(0, 5, 0)) * CFrame.Angles(math.random() - 0.5, 0, math.random() - 0.5), color, NEON)
				fade(spike, 0.5, { Size = Vector3.new(0.2, 12, 0.2) })
			end
			T.sound("BossSlam", 1, 0.7)
			T.shake(ctx, 0.6)
		end)
	end,
}

-- ===================================================================
-- Celestial: Cosmic
-- ===================================================================
local function gate(spot: Vector3, dir: Vector3, color: Color3, life: number)
	local ring = T.part(Vector3.new(0.6, 9, 9), CFrame.lookAt(spot, spot + dir) * CFrame.Angles(0, math.pi / 2, 0), color, NEON, CYL)
	local disc = T.part(Vector3.new(0.3, 8, 8), ring.CFrame, rgb(20, 20, 60), FORCE, CYL)
	disc.Transparency = 0.2
	ring.Size = Vector3.new(0.6, 0.5, 0.5)
	disc.Size = Vector3.new(0.3, 0.4, 0.4)
	T.tween(ring, { Size = Vector3.new(0.6, 9, 9) }, 0.2, Enum.EasingStyle.Back)
	T.tween(disc, { Size = Vector3.new(0.3, 8, 8) }, 0.2, Enum.EasingStyle.Back)
	task.delay(life, function()
		fade(ring, 0.3, { Size = Vector3.new(0.6, 0.2, 0.2) })
		fade(disc, 0.3, { Size = Vector3.new(0.3, 0.2, 0.2) })
	end)
end

looks.WarpGate = {
	Start = function(ctx)
		local d = ctx.Def
		T.pose(ctx, "GateOpen", 0.7)
		gate(rootPos(ctx) + ctx.Dir * 2 + Vector3.new(0, 0.5, 0), ctx.Dir, d.Color, 0.6)
		T.sound("TierUp", 0.6, 2)
		task.delay(0.15, function()
			T.blink(ctx, d.Length, d.Color)
		end)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local exit = info.Exit or ctx.Origin + ctx.Dir * d.Length
		gate(exit + Vector3.new(0, 0.5, 0), ctx.Dir, color, 0.6)
		at(ctx, 0.2, function()
			T.ring(feetAt(ctx.Origin), color, d.Radius, 0.4, 2)
			fx():Burst(ctx.Origin, "Stars", 25)
		end)
		at(ctx, 0.4, function()
			T.ring(feetAt(exit), color, d.Radius, 0.4, 2)
			fx():Burst(exit, "Galaxy", 25)
			T.sound("BossSlam", 0.8, 1.6)
			T.shake(ctx, 0.4)
		end)
	end,
}

looks.StarlightArrow = {
	Start = function(ctx)
		T.pose(ctx, "BowDraw", 1.0)
		T.sound("Swing", 0.8, 0.6)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local center = info.Center or ctx.Origin + ctx.Dir * d.Distance
		local delay = info.Delay or d.Delay
		-- the shot goes up
		at(ctx, 0.3, function()
			local from = rootPos(ctx) + Vector3.new(0, 2, 0)
			local apex = (from + center) / 2 + Vector3.new(0, 45, 0)
			local arrow = T.part(Vector3.new(0.5, 0.5, 5), CFrame.lookAt(from, apex), WHITE)
			T.addTrail(arrow, color, 0.8, 0.4)
			T.animate(math.max(0.1, delay - 0.3), function(k)
				arrow.CFrame = CFrame.lookAt(from:Lerp(apex, k), apex)
			end, function()
				arrow:Destroy()
				fx():Sphere(apex, lighter(color), 2, 14, 0.4, NEON)
				fx():Burst(apex, "Stars", 30)
			end)
			T.sound("Swing", 1, 1.6)
		end)
		local zone = T.part(Vector3.new(0.2, d.Radius * 2, d.Radius * 2), CFrame.new(feetAt(center + Vector3.new(0, 2.9, 0)) + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2), color, NEON, CYL)
		zone.Transparency = 0.75
		task.delay(delay + 1.2, function()
			fade(zone, 0.4)
		end)
		for i, spot in ipairs(info.Spots or {}) do
			at(ctx, delay + (i - 1) * 0.04 - 0.12, function()
				local top = spot + Vector3.new((math.random() - 0.5) * 8, 30, (math.random() - 0.5) * 8)
				local star = T.part(Vector3.new(0.4, 0.4, 4), CFrame.lookAt(top, spot), lighter(color))
				T.addTrail(star, color, 0.4, 0.2)
				T.animate(0.12, function(k)
					star.CFrame = CFrame.lookAt(top:Lerp(spot, k), spot)
				end, function()
					fade(star, 0.4)
					fx():Burst(spot, "Stars", 4)
				end)
			end)
		end
	end,
}

looks.ConstellationCollapse = {
	Start = function(ctx)
		T.pose(ctx, "StarMark", 1.3)
		T.sound("TierUp", 0.7, 1.9)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local stars = info.Stars or {}
		local delay = info.Delay or d.Delay
		local tops = {}
		for i, s in ipairs(stars) do
			tops[i] = s.Position + Vector3.new(0, 14, 0)
			at(ctx, 0.1 + i * 0.04, function()
				local star = T.part(Vector3.new(1.6, 1.6, 1.6), CFrame.new(tops[i]) * CFrame.Angles(0, 0, math.rad(45)), WHITE, NEON)
				local glow = T.part(Vector3.new(3.5, 3.5, 3.5), CFrame.new(tops[i]), color, FORCE, BALL)
				glow.Transparency = 0.4
				if i > 1 then
					slab(tops[i - 1], tops[i], 0.25, 0.25, lighter(color), delay)
				end
				task.delay(math.max(0.05, delay - 0.1 - i * 0.04 + (i - 1) * 0.05), function()
					-- the star falls onto its enemy
					local from, to = tops[i], s.Position
					T.animate(0.1, function(k)
						star.CFrame = CFrame.new(from:Lerp(to, k))
						glow.CFrame = star.CFrame
					end, function()
						star:Destroy()
						glow:Destroy()
						fx():Burst(to, "Stars", 8)
					end)
				end)
			end)
		end
		at(ctx, info.Bang or 1.4, function()
			local center = rootPos(ctx)
			fx():Sphere(center, lighter(color), 3, d.BangRadius * 2, 0.5, NEON)
			fx():Burst(center, "Galaxy", 50, { Speed = NumberRange.new(20, 40) })
			T.ring(feetAt(center), color, d.BangRadius, 0.45, 3)
			T.sound("BossSlam", 1, 1)
			T.shake(ctx, 0.7)
		end)
	end,
}

looks.TimeStop = {
	Start = function(ctx)
		T.pose(ctx, "ClockStop", ctx.Def.Stop + 0.4)
		T.sound("TierUp", 1, 0.4)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local stop = info.Stop or d.Stop
		local radius = info.Radius or d.Radius
		local center = feetOf(ctx)
		-- a clock face spreads over the ground, its hands frozen
		local face = T.part(Vector3.new(0.2, radius * 2, radius * 2), CFrame.new(center + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.pi / 2), color, NEON, CYL)
		face.Transparency = 0.82
		local marks = {}
		for i = 1, 12 do
			local a = i / 12 * math.pi * 2
			local m = T.part(Vector3.new(1, 0.3, if i % 3 == 0 then 6 else 3), CFrame.lookAt(center + Vector3.new(math.cos(a), 0, math.sin(a)) * radius * 0.85 + Vector3.new(0, 0.2, 0), center + Vector3.new(0, 0.2, 0)), lighter(color), NEON)
			marks[i] = m
		end
		local hand1 = T.part(Vector3.new(1.2, 0.3, radius * 0.6), CFrame.new(), WHITE, NEON)
		local hand2 = T.part(Vector3.new(0.8, 0.3, radius * 0.8), CFrame.new(), WHITE, NEON)
		local function place(a1, a2)
			hand1.CFrame = CFrame.new(center + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, a1, 0) * CFrame.new(0, 0, -radius * 0.3)
			hand2.CFrame = CFrame.new(center + Vector3.new(0, 0.35, 0)) * CFrame.Angles(0, a2, 0) * CFrame.new(0, 0, -radius * 0.4)
		end
		place(0, 0)
		if ctx.Local then
			T.controllers().EffectsController:Vignette(rgb(80, 110, 200), 0.45, stop)
			fx():Flash(lighter(color), 0.2)
		end
		-- frozen markers over every stopped enemy
		for _, p in ipairs(info.Points or {}) do
			local cube = T.part(Vector3.new(4, (p.Height or 5) + 1, 4), CFrame.new(p.Position), color, FORCE)
			cube.Transparency = 0.6
			task.delay(stop, function()
				fade(cube, 0.2)
			end)
		end
		T.animate(stop, function(k)
			-- the hands stay frozen until the very end, then spin back to life
			local spin = if k > 0.9 then (k - 0.9) * 10 * math.pi * 4 else 0
			place(spin, spin * 0.2)
		end, function()
			fade(face, 0.4)
			fade(hand1, 0.3)
			fade(hand2, 0.3)
			for _, m in ipairs(marks) do
				fade(m, 0.3)
			end
			T.ring(center, WHITE, radius * 0.6, 0.5, 3)
			fx():Burst(center + Vector3.new(0, 3, 0), "Galaxy", 40, { Speed = NumberRange.new(20, 50) })
			T.sound("BossSlam", 1, 1.2)
			T.shake(ctx, 0.8)
		end)
	end,
}

-- ===================================================================
-- Void: Gravity
-- ===================================================================
looks.GravitySlingshot = {
	Start = function(ctx)
		T.pose(ctx, "Slingshot", 0.9)
		T.sound("Dodge", 1, 0.4)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local landing = info.Landing
		if typeof(landing) ~= "Vector3" then
			return
		end
		local start = ctx.Origin
		-- the sling: a band of void stretching from you to the target, then snapping you along it
		slab(start + Vector3.new(0, 1, 0), landing + Vector3.new(0, 1, 0), 1, 1, color, 0.5, FORCE)
		at(ctx, 0.15, function()
			travel(ctx, { start, landing }, 0.3, color)
		end)
		at(ctx, 0.5, function()
			local spot = feetAt(landing)
			fx():Sphere(landing, BLACK, 3, d.Radius * 2, 0.4)
			T.ring(spot, color, d.Radius, 0.45, 3)
			fx():Burst(landing, "Void", 40, { Speed = NumberRange.new(15, 30) })
			T.sound("BossSlam", 1, 0.8)
			T.shake(ctx, 0.6)
		end)
	end,
}

looks.HorizonBeam = {
	Start = function(ctx)
		local d = ctx.Def
		T.pose(ctx, "HorizonPush", 0.2 + d.PullTime + d.Hits * d.Tick + 0.3)
		T.sound("TierUp", 0.6, 0.5)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local length = info.Length or d.Length
		local lead = info.Lead or (0.2 + d.PullTime)
		local from = ctx.Origin + ctx.Dir * 2 + Vector3.new(0, 1, 0)
		local to = from + ctx.Dir * length
		local cf = CFrame.lookAt((from + to) / 2, to)
		-- the pull: a wide wavering band drags things in, then the crushing core
		local band = T.part(Vector3.new(d.Width * 2.2, 0.4, length), cf, color, FORCE)
		band.Transparency = 0.5
		T.animate(lead, function(k)
			band.Size = Vector3.new(d.Width * 2.2 * (1 - k * 0.6), 0.4 + k * 2, length)
		end, function()
			band:Destroy()
		end)
		at(ctx, lead, function()
			local core = T.part(Vector3.new(d.Width * 0.4, d.Width * 0.4, length), cf, BLACK, NEON)
			local shell = T.part(Vector3.new(d.Width, d.Width, length), cf, color, FORCE)
			shell.Transparency = 0.35
			local span = (info.Hits or d.Hits) * (info.Tick or d.Tick)
			T.animate(span + 0.2, function(k)
				local pulse = 1 + math.sin(k * math.pi * 2 * (info.Hits or d.Hits)) * 0.25
				shell.Size = Vector3.new(d.Width * pulse, d.Width * pulse, length)
			end, function()
				fade(core, 0.2)
				fade(shell, 0.25, { Size = Vector3.new(0.5, 0.5, length) })
			end)
			T.sound("Finisher", 1, 0.5)
			T.shake(ctx, 0.5)
		end)
	end,
}

looks.GravityCrush = {
	Start = function(ctx)
		T.pose(ctx, "GravityLift", 0.3 + ctx.Def.Float + 0.4)
		T.sound("BossSpawn", 0.6, 1.8)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local center = feetAt(info.Center or ctx.Origin)
		local radius = info.Radius or d.Radius
		local float = info.Float or d.Float
		at(ctx, 0.25, function()
			T.ring(center, color, radius, 0.5, 1)
			local field = T.part(Vector3.new(14, radius * 2, radius * 2), CFrame.new(center + Vector3.new(0, 7, 0)) * CFrame.Angles(0, 0, math.pi / 2), color, FORCE, CYL)
			field.Transparency = 0.7
			T.animate(float, function(k)
				field.Size = Vector3.new(14, radius * 2 * (1 - k * 0.3), radius * 2 * (1 - k * 0.3))
				field.Transparency = 0.7 - k * 0.2
			end, function()
				field:Destroy()
			end)
			fx():Burst(center + Vector3.new(0, 4, 0), "Void", 30, { Speed = NumberRange.new(4, 10), Acceleration = Vector3.new(0, 15, 0) })
		end)
		at(ctx, 0.3 + float, function()
			fx():Sphere(center + Vector3.new(0, 1, 0), BLACK, radius * 2, 4, 0.3)
			T.ring(center, color, radius * 0.8, 0.4, 4)
			fx():Burst(center + Vector3.new(0, 1, 0), "Void", 40, { Speed = NumberRange.new(20, 40) })
			T.sound("BossSlam", 1, 0.5)
			T.shake(ctx, 0.9)
		end)
	end,
}

looks.BlackSun = {
	Start = function(ctx)
		T.pose(ctx, "BlackSunHold", 1.4)
		T.sound("BossSpawn", 0.8, 0.7)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local center = info.Center or ctx.Origin + ctx.Dir * d.Distance
		local duration = info.Duration or d.Duration
		local radius = info.Radius or d.Radius
		local core = T.part(Vector3.new(1, 1, 1), CFrame.new(center), BLACK, NEON, BALL)
		local corona = T.part(Vector3.new(1, 1, 1), CFrame.new(center), color, FORCE, BALL)
		corona.Transparency = 0.3
		local disk = T.part(Vector3.new(0.3, 1, 1), CFrame.new(center) * CFrame.Angles(0.3, 0, math.pi / 2), color, NEON, CYL)
		disk.Transparency = 0.4
		T.tween(core, { Size = Vector3.new(9, 9, 9) }, 0.4, Enum.EasingStyle.Back)
		T.tween(corona, { Size = Vector3.new(14, 14, 14) }, 0.4, Enum.EasingStyle.Back)
		T.tween(disk, { Size = Vector3.new(0.3, 24, 24) }, 0.4, Enum.EasingStyle.Back)
		local streaks = 0
		T.animate(0.4 + duration, function()
			disk.CFrame = CFrame.new(center) * CFrame.Angles(0.3, os.clock() * 2, math.pi / 2)
			streaks += 1
			if streaks % (if low() then 10 else 3) == 0 then
				local a = math.random() * math.pi * 2
				local far = center + Vector3.new(math.cos(a) * radius, math.random() * 8 - 4, math.sin(a) * radius)
				T.streak(far, center, lighter(color), 0.3, 0.3)
			end
		end, function()
			-- collapse
			T.tween(core, { Size = Vector3.new(0.5, 0.5, 0.5) }, 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			T.tween(corona, { Size = Vector3.new(0.5, 0.5, 0.5) }, 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			fade(disk, 0.15, { Size = Vector3.new(0.3, 1, 1) })
			task.delay(0.15, function()
				core:Destroy()
				corona:Destroy()
				fx():Sphere(center, lighter(color), 2, radius * 1.4, 0.5, NEON)
				fx():Burst(center, "Void", 60, { Speed = NumberRange.new(25, 50) })
				T.ring(feetAt(center), color, radius * 0.6, 0.5, 4)
				T.sound("BossSlam", 1, 0.6)
				T.shake(ctx, 0.9)
			end)
		end)
	end,
}

function SuitUltimateEffects.Register(E, tools)
	T = tools
	local poses = tools.poses()
	for name, move in pairs(Poses) do
		poses[name] = move
	end
	for id, def in pairs(Mastery.ById) do
		local look = looks[def.Kind]
		if look then
			E[id] = look
		end
	end
end

return SuitUltimateEffects
