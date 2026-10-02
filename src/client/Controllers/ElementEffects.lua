--[[
	ElementEffects: the looks of the elemental tier skills (Config/ElementSkills),
	client side only. SkillEffects requires this and calls Register(E, tools), which
	adds a { Start, Result, Hit } entry per skill to its table, drawing with the same
	toolkit (neon parts, particle bursts, trails, poses, camera shake, dashes).

	Every effect is coloured from its skill's Color (element colours). Positions:
	  self-centred skills draw at the caster's feet (or the proc point, ctx.Proc)
	  placed skills draw at info.Center from the server (Result)
	  hits get small extras by tag (Freeze ice blocks, Root vines, Grab hands, ...)
	ctx.Elapsed (seconds the server answer took) keeps Result timings in sync.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Skills = require(Shared.Config.Skills)
local Particles = require(Shared.Visuals.Particles)

local ElementEffects = {}

local T -- SkillEffects.Tools
local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local UP = Vector3.yAxis

-- ===== helpers =====
local function fx()
	return T.fx()
end

local function low(): boolean
	return T.lowGraphics()
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
local function groundAt(p: Vector3): Vector3
	local filter: { Instance } = { workspace.Terrain }
	local world = workspace:FindFirstChild("World")
	if world then
		table.insert(filter, world)
	end
	rayParams.FilterDescendantsInstances = filter
	local hit = workspace:Raycast(p + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), rayParams)
	return if hit then hit.Position else p - Vector3.new(0, 2.9, 0)
end

local function rootAlive(ctx): boolean
	return ctx.Root ~= nil and (ctx.Root :: BasePart).Parent ~= nil
end

-- Where a self-centred skill draws: the caster's feet, or the proc point.
local function centerOf(ctx): Vector3
	if ctx.Proc or not rootAlive(ctx) then
		return groundAt(ctx.Origin)
	end
	return T.feet(ctx.Root)
end

local function handOf(ctx): Vector3
	if ctx.Proc or not rootAlive(ctx) then
		return ctx.Origin + Vector3.new(0, 1, 0)
	end
	return T.hand(ctx)
end

-- seconds to wait so something lands `t` seconds after the cast (Result runs late)
local function at(ctx, t: number): number
	return math.max(0, t - (ctx.Elapsed or 0))
end

local function fade(p: BasePart, t: number, delay: number?)
	task.delay(delay or 0, function()
		if p.Parent then
			T.tween(p, { Transparency = 1 }, t)
			Debris:AddItem(p, t + 0.05)
		end
	end)
end

local function disc(center: Vector3, radius: number, color: Color3, transparency: number, material: Enum.Material?): BasePart
	local p = T.part(Vector3.new(0.2, radius * 2, radius * 2), CFrame.new(center + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.pi / 2), color, material, Enum.PartType.Cylinder)
	p.Transparency = transparency
	return p
end

local function light(p: BasePart, color: Color3, range: number, brightness: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = p
	return l
end

-- An invisible anchor that emits a particle preset over its own volume.
local function emitter(cf: CFrame, size: Vector3, preset: string, overrides: { [string]: any }, life: number): BasePart
	local anchor = T.part(size, cf, WHITE, Enum.Material.SmoothPlastic)
	anchor.Transparency = 1
	Particles.Create(preset, anchor, overrides)
	Debris:AddItem(anchor, life)
	return anchor
end

-- A rock shard that bursts out of the ground, holds, then sinks.
local function rockSpike(base: Vector3, h: number, w: number, color: Color3, hold: number, tilt: CFrame, material: Enum.Material?)
	local rock = T.part(Vector3.new(w, h, w), CFrame.new(base - Vector3.new(0, h, 0)) * tilt, color, material or Enum.Material.Slate)
	T.tween(rock, { CFrame = CFrame.new(base + Vector3.new(0, h * 0.3, 0)) * tilt }, 0.12, Enum.EasingStyle.Back)
	task.delay(hold, function()
		if rock.Parent then
			T.tween(rock, { CFrame = CFrame.new(base - Vector3.new(0, h, 0)) * tilt, Transparency = 1 }, 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			Debris:AddItem(rock, 0.45)
		end
	end)
	return rock
end

local enemyCache: { [number]: Model } = {}
local function enemyModel(uid: number?): Model?
	if not uid then
		return nil
	end
	local m = enemyCache[uid]
	if m and m.Parent then
		return m
	end
	for _, model in ipairs(CollectionService:GetTagged("Enemy")) do
		if model:GetAttribute("Uid") == uid then
			enemyCache[uid] = model
			return model
		end
	end
	return nil
end

local function enemyRoot(uid: number?): BasePart?
	local m = enemyModel(uid)
	return m and m.PrimaryPart
end

-- Nearest enemy roughly in front (client guess for dives; the server decides hits).
local function frontEnemy(origin: Vector3, dir: Vector3, range: number, arc: number): Vector3?
	local best, bestD = nil, range
	for _, model in ipairs(CollectionService:GetTagged("Enemy")) do
		if model:IsA("Model") and model.PrimaryPart and not model:GetAttribute("Dead") then
			local to = model.PrimaryPart.Position - origin
			to = Vector3.new(to.X, 0, to.Z)
			local d = to.Magnitude
			if d < bestD and d > 0.1 and dir:Dot(to.Unit) >= arc then
				best, bestD = model.PrimaryPart.Position, d
			end
		end
	end
	return best
end

local function sideOf(dir: Vector3): Vector3
	local side = dir:Cross(UP)
	return if side.Magnitude > 0.01 then side.Unit else Vector3.xAxis
end

local function randomIn(center: Vector3, radius: number): Vector3
	local a = math.random() * math.pi * 2
	local r = math.sqrt(math.random()) * radius
	return center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
end

-- one effect per tag table (a strike's hits share one tag)
local seenTags = setmetatable({}, { __mode = "k" })
local function firstFor(tag): boolean
	if type(tag) ~= "table" then
		return true
	end
	if seenTags[tag] then
		return false
	end
	seenTags[tag] = true
	return true
end

local function level(ctx): number
	return math.clamp(ctx.Level or 1, 1, Skills.MaxLevel)
end

local function fieldTime(ctx): number
	return (ctx.Def.Field or 0) + 0.5 * (level(ctx) - 1)
end

local E = {}

-- ===================== EARTH (Brown) =====================
E.stone_spikes = {
	Start = function(ctx)
		local d = ctx.Def
		T.pose(ctx, "Slam", 0.75)
		local dir = ctx.Dir
		local origin = if ctx.Proc then ctx.Origin - dir * 6 else ctx.Origin
		local side = sideOf(dir)
		task.delay(0.12, function()
			T.sound("Slam", 1, 0.7)
			T.shake(ctx, 0.35)
			local segments = 6
			local per = if low() then 1 else 3
			for g = 1, segments do
				task.delay(0.02 + (g - 1) * 0.06, function()
					local along = (g - 0.5) / segments * d.Length
					local base = groundAt(origin + dir * along)
					-- a glowing crack on the ground under the wave
					local crack = T.part(Vector3.new(0.5, 0.15, d.Length / segments + 0.6), CFrame.lookAt(base + Vector3.new(0, 0.1, 0), base + dir + Vector3.new(0, 0.1, 0)), rgb(255, 170, 80))
					fade(crack, 0.6, 0.5)
					for i = 1, per do
						local off = (if per == 1 then 0 else (i - (per + 1) / 2) / ((per - 1) / 2)) * d.Width * 0.38 + (math.random() - 0.5) * 1.5
						local spot = groundAt(base + side * off)
						local h = 4.5 + math.random() * 3.5 + g * 0.35
						local w = 1.4 + math.random() * 1.2
						local tilt = CFrame.Angles((math.random() - 0.5) * 0.5 - 0.25, math.random() * 6, (math.random() - 0.5) * 0.5)
						rockSpike(spot, h, w, rgb(150 + math.random(0, 30), 104 + math.random(0, 20), 64), 0.85, tilt)
					end
					fx():Burst(base + Vector3.new(0, 1, 0), "Smoke", 10, {
						Color = ColorSequence.new(rgb(190, 150, 100)), Speed = NumberRange.new(6, 14), Size = NumberSequence.new(1.5, 4),
						Lifetime = NumberRange.new(0.5, 0.9), SpreadAngle = Vector2.new(70, 70),
					})
				end)
			end
		end)
	end,
	Hit = function(_ctx, hit)
		fx():Burst(hit.Position, "Smoke", 6, { Color = ColorSequence.new(rgb(170, 130, 90)), Speed = NumberRange.new(3, 8), Size = NumberSequence.new(1, 2.5) })
	end,
}

E.earth_wall = {
	Start = function(ctx)
		local d = ctx.Def
		T.pose(ctx, "Roar", 0.7)
		local dir = ctx.Dir
		local center = if ctx.Proc then groundAt(ctx.Origin) else groundAt(ctx.Origin + dir * d.Range)
		local side = sideOf(dir)
		local hold = d.Field
		task.delay(0.1, function()
			T.sound("BossSlam", 0.9, 0.8)
			T.shake(ctx, 0.45)
			local slabs = if low() then 5 else 9
			local w = d.Width / slabs
			for i = 1, slabs do
				local off = (i - (slabs + 1) / 2) * w
				-- a gentle curve that hugs the caster
				local spot = groundAt(center + side * off - dir * (off * off) / (d.Width * 1.6))
				local h = 7 + math.random() * 2.5 - math.abs(off) * 0.12
				local face = CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles((math.random() - 0.5) * 0.12, 0, (math.random() - 0.5) * 0.16)
				local slab = T.part(Vector3.new(w + 0.8, h, 3.2), CFrame.new(spot - Vector3.new(0, h, 0)) * face, rgb(140 + math.random(0, 25), 100 + math.random(0, 15), 64), Enum.Material.Slate)
				task.delay(math.abs(off) / 60, function()
					T.tween(slab, { CFrame = CFrame.new(spot + Vector3.new(0, h * 0.42, 0)) * face }, 0.16, Enum.EasingStyle.Back)
				end)
				task.delay(hold, function()
					if slab.Parent then
						T.tween(slab, { CFrame = CFrame.new(spot - Vector3.new(0, h, 0)) * face, Transparency = 1 }, 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
						Debris:AddItem(slab, 0.55)
					end
				end)
				-- loose rocks crown the wall
				if not low() and i % 2 == 0 then
					local top = T.part(Vector3.new(1.6, 1.4, 1.6), CFrame.new(spot + Vector3.new(0, h * 0.92, 0)) * CFrame.Angles(math.random(), math.random(), math.random()), rgb(120, 86, 56), Enum.Material.Rock)
					top.Transparency = 1
					task.delay(0.18, function()
						top.Transparency = 0
					end)
					fade(top, 0.4, hold)
				end
			end
			fx():Burst(center + Vector3.new(0, 1, 0), "Smoke", if low() then 14 else 34, {
				Color = ColorSequence.new(rgb(200, 160, 110)), Speed = NumberRange.new(8, 18), Size = NumberSequence.new(2, 5),
				Lifetime = NumberRange.new(0.6, 1.1), SpreadAngle = Vector2.new(80, 20),
			})
			T.ring(center, d.Color, d.Width * 0.6, 0.4, 0.3)
		end)
	end,
}

-- ===================== WIND / NATURE (Green) =====================
E.razor_gale = {
	Start = function(ctx)
		local d = ctx.Def
		T.pose(ctx, "Cast", 0.6)
		T.sound("DoubleJump", 1, 0.7)
		local dir = ctx.Dir
		local travel = (ctx.Info and ctx.Info.Time) or 1.2
		local start = groundAt(ctx.Origin + dir * 3)
		local rings, leaves = {}, {}
		for i = 1, 5 do
			local r = 1.4 + i * 0.9
			local p = T.part(Vector3.new(0.35, r * 2, r * 2), CFrame.new(start), d.Color, Enum.Material.ForceField, Enum.PartType.Cylinder)
			p.Transparency = 0.25
			rings[i] = { Part = p, Height = (i - 1) * 2.2 + 0.5 }
		end
		for i = 1, (if low() then 5 else 12) do
			local leaf = T.part(Vector3.new(0.9, 0.12, 0.5), CFrame.new(start), if i % 3 == 0 then rgb(220, 255, 160) else rgb(90, 200, 90))
			T.addTrail(leaf, d.Color, 0.25, 0.12)
			leaves[i] = { Part = leaf, Height = math.random() * 10, Radius = 1.5 + math.random() * 4, Phase = math.random() * 6 }
		end
		local cutAt = 0
		T.animate(travel + 0.2, function(k)
			local t = k * (travel + 0.2)
			local pos = groundAt(start + dir * ((d.Length - 3) * math.min(1, t / travel)))
			local fadeK = math.max(0, (t - travel) / 0.2)
			for i, r in ipairs(rings) do
				r.Part.CFrame = CFrame.new(pos + Vector3.new(math.sin(t * 9 + i) * 0.4, r.Height, math.cos(t * 9 + i) * 0.4)) * CFrame.Angles(0, 0, math.pi / 2)
				r.Part.Transparency = 0.25 + 0.75 * fadeK
			end
			for _, l in ipairs(leaves) do
				local a = l.Phase + t * 14
				l.Part.CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * l.Radius, l.Height, math.sin(a) * l.Radius)) * CFrame.Angles(a, a * 0.7, 0)
				l.Part.Transparency = fadeK
			end
			if t - cutAt > 0.3 then
				cutAt = t
				T.sound("Swing", 0.7, 1.3)
			end
		end, function()
			for _, r in ipairs(rings) do
				r.Part:Destroy()
			end
			for _, l in ipairs(leaves) do
				l.Part:Destroy()
			end
		end)
	end,
	Hit = function(ctx, hit)
		local c = hit.Position + Vector3.new(0, (hit.Height or 5) * 0.2, 0)
		local a = math.random() * math.pi
		local v = Vector3.new(math.cos(a), (math.random() - 0.5), math.sin(a)) * 2.5
		T.streak(c - v, c + v, ctx.Def.Color, 0.25, 0.2)
	end,
}

E.vine_snare = {
	Start = function(ctx)
		T.pose(ctx, "Point", 0.6)
		T.sound("Equip", 0.8, 0.7)
	end,
	Result = function(ctx, info)
		local d = ctx.Def
		local center = info.Center
		if typeof(center) ~= "Vector3" then
			return
		end
		local hold = d.Root + 0.25 * (level(ctx) - 1)
		local mark = disc(center, d.Radius, rgb(70, 140, 50), 0.6, Enum.Material.Grass)
		fade(mark, 0.5, hold)
		task.delay(at(ctx, 0.3), function()
			T.sound("Slam", 0.8, 1.1)
			T.ring(center, d.Color, d.Radius, 0.35, 0.3)
			fx():Burst(center + Vector3.new(0, 1, 0), "Petals", if low() then 10 else 30, {
				Color = ColorSequence.new(rgb(150, 240, 110), rgb(60, 160, 60)), Speed = NumberRange.new(6, 14), Lifetime = NumberRange.new(0.8, 1.4),
			})
			for _ = 1, (if low() then 6 else 14) do
				local base = groundAt(randomIn(center, d.Radius))
				local h = 3 + math.random() * 4
				local tilt = CFrame.Angles((math.random() - 0.5) * 0.7, math.random() * 6, (math.random() - 0.5) * 0.7)
				local vine = rockSpike(base, h, 0.6 + math.random() * 0.4, rgb(50, 120 + math.random(0, 40), 50), hold, tilt, Enum.Material.Grass)
				-- a few thorns
				local thorn = T.part(Vector3.new(0.25, 0.9, 0.25), vine.CFrame, rgb(170, 255, 120))
				thorn.Transparency = 1
				task.delay(0.13, function()
					if vine.Parent then
						thorn.CFrame = vine.CFrame * CFrame.new(0.4, h * 0.2, 0) * CFrame.Angles(0, 0, -0.9)
						thorn.Transparency = 0
					end
				end)
				fade(thorn, 0.3, hold)
			end
		end)
	end,
	Hit = function(ctx, hit, tag)
		if tag ~= "Root" then
			return
		end
		local hold = ctx.Def.Root + 0.25 * (level(ctx) - 1)
		local h = hit.Height or 5
		local base = groundAt(hit.Position)
		for i = 1, 2 do
			local coil = T.part(Vector3.new(0.5, h * 0.55, h * 0.55), CFrame.new(base + Vector3.new(0, h * (0.15 + 0.25 * i), 0)) * CFrame.Angles(0, 0, math.pi / 2), rgb(60, 150, 60), Enum.Material.Grass, Enum.PartType.Cylinder)
			coil.Transparency = 0.15
			fade(coil, 0.3, hold)
		end
	end,
}

-- ===================== ICE (Blue) =====================
E.frost_nova = {
	Start = function(ctx)
		local d = ctx.Def
		T.pose(ctx, "Roar", 0.6)
		task.delay(0.2, function()
			local center = centerOf(ctx)
			T.sound("Crit", 1, 1.7)
			T.sound("Slam", 0.7, 1.2)
			T.ring(center, d.Color, d.Radius, 0.45, 0.5)
			T.ring(center, WHITE, d.Radius * 0.6, 0.35, 0.3)
			fx():Sphere(center + Vector3.new(0, 1.5, 0), rgb(200, 240, 255), 3, d.Radius * 2, 0.5)
			fx():Burst(center + Vector3.new(0, 2, 0), "Frost", if low() then 20 else 60, {
				Speed = NumberRange.new(14, 26), Lifetime = NumberRange.new(0.6, 1.1), Size = NumberSequence.new(0.6, 0), SpreadAngle = Vector2.new(180, 20),
			})
			local shards = if low() then 8 else 16
			for i = 1, shards do
				local a = (i / shards) * math.pi * 2 + math.random() * 0.2
				local r = d.Radius * (0.55 + math.random() * 0.4)
				local base = groundAt(center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
				local tilt = CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, -0.35)
				task.delay(r / 70, function()
					local shard = rockSpike(base, 3 + math.random() * 3, 1.1 + math.random() * 0.8, rgb(170, 225, 255), 1.3, tilt, Enum.Material.Ice)
					shard.Transparency = 0.2
				end)
			end
			T.shake(ctx, 0.35)
			if ctx.Local then
				fx():Flash(rgb(200, 240, 255), 0.18)
			end
		end)
	end,
	Hit = function(ctx, hit, tag)
		if tag ~= "Freeze" then
			return
		end
		local h = hit.Height or 5
		local hold = ctx.Def.Freeze + 0.2 * (level(ctx) - 1)
		local block = T.part(Vector3.new(h * 0.75, h * 1.1, h * 0.75), CFrame.new(hit.Position + Vector3.new(0, h * 0.02, 0)) * CFrame.Angles(0, math.random() * 6, (math.random() - 0.5) * 0.15), rgb(170, 225, 255), Enum.Material.Ice)
		block.Transparency = 0.4
		task.delay(hold, function()
			if block.Parent then
				fx():Burst(block.Position, "Frost", 14, { Speed = NumberRange.new(6, 12), Size = NumberSequence.new(0.5, 0) })
				block:Destroy()
			end
		end)
	end,
}

E.blizzard_gust = {
	Start = function(ctx)
		local d = ctx.Def
		T.pose(ctx, "Cast", 0.6)
		task.delay(0.14, function()
			T.sound("Swing", 1, 0.55)
			T.shake(ctx, 0.2)
			local from = handOf(ctx)
			local half = math.acos(d.Arc)
			for _ = 1, (if low() then 6 else 16) do
				local dir = T.rotateY(ctx.Dir, (math.random() * 2 - 1) * half * 0.9)
				local to = from + dir * d.Range * (0.7 + math.random() * 0.3) + Vector3.new(0, (math.random() - 0.4) * 3, 0)
				local puff = T.part(Vector3.new(1.2, 1.2, 1.2), CFrame.new(from), rgb(235, 248, 255), Enum.Material.Neon, Enum.PartType.Ball)
				puff.Transparency = 0.2
				local grow = 4 + math.random() * 3
				T.animate(0.45 + math.random() * 0.1, function(k)
					puff.CFrame = CFrame.new(from:Lerp(to, k))
					local s = 1.2 + (grow - 1.2) * k
					puff.Size = Vector3.new(s, s, s)
					puff.Color = rgb(235, 248, 255):Lerp(rgb(130, 200, 255), k)
					puff.Transparency = 0.2 + 0.78 * k
				end, function()
					puff:Destroy()
				end)
			end
			for i = 1, (if low() then 3 else 7) do
				local dir = T.rotateY(ctx.Dir, (math.random() * 2 - 1) * half * 0.8)
				local a = from + dir * 3 + Vector3.new(0, (math.random() - 0.5) * 2, 0)
				task.delay(i * 0.03, function()
					T.streak(a, a + dir * d.Range * 0.9, WHITE, 0.25, 0.35)
				end)
			end
			for i = 1, 4 do
				fx():Burst(from + ctx.Dir * (d.Range * i / 5), "Frost", 12, { Speed = NumberRange.new(4, 10), SpreadAngle = Vector2.new(60, 60) })
			end
		end)
	end,
	Hit = function(ctx, hit, tag)
		if tag ~= "Chill" or low() then
			return
		end
		local r = enemyRoot(hit.Uid)
		if r then
			local e = Particles.Create("Frost", r, { Rate = 14 })
			if e then
				Debris:AddItem(e, ctx.Def.SlowTime + 0.5 * (level(ctx) - 1))
			end
		end
	end,
}

-- ===================== ARCANE LIGHTNING (Purple) =====================
E.arcane_storm = {
	Start = function(ctx)
		local d = ctx.Def
		T.pose(ctx, "Point", 0.7)
		T.sound("TierUp", 0.7, 1.8)
		local center = centerOf(ctx)
		local bolts = d.Bolts + (level(ctx) - 1)
		local span = 0.2 + bolts * 0.14 + 0.3
		-- a turning arcane circle overhead
		local sky = center + Vector3.new(0, 20, 0)
		local halo = T.part(Vector3.new(0.4, d.Radius * 1.2, d.Radius * 1.2), CFrame.new(sky) * CFrame.Angles(0, 0, math.pi / 2), d.Color, Enum.Material.Neon, Enum.PartType.Cylinder)
		halo.Transparency = 0.55
		local bars = {}
		for i = 1, 3 do
			local bar = T.part(Vector3.new(d.Radius * 1.1, 0.3, 0.6), CFrame.new(sky), rgb(240, 200, 255))
			bar.Transparency = 0.3
			bars[i] = bar
		end
		T.animate(span, function(k)
			for i, bar in ipairs(bars) do
				bar.CFrame = CFrame.new(sky) * CFrame.Angles(0, k * 6 + i * math.pi / 3, 0)
			end
			halo.Transparency = 0.55 + 0.45 * math.max(0, (k - 0.8) / 0.2)
		end, function()
			halo:Destroy()
			for _, bar in ipairs(bars) do
				bar:Destroy()
			end
		end)
		-- a few stray bolts for show
		for i = 1, (if low() then 1 else 3) do
			task.delay(0.25 + i * 0.3, function()
				local spot = groundAt(randomIn(center, d.Radius))
				T.bolt(sky, spot, d.Color, 0.35, 0.2)
			end)
		end
	end,
	Hit = function(ctx, _hit, tag)
		if type(tag) ~= "table" or typeof(tag.Bolt) ~= "Vector3" or not firstFor(tag) then
			return
		end
		local d = ctx.Def
		local spot = groundAt(tag.Bolt)
		T.bolt(spot + Vector3.new(0, 40, 0), spot + Vector3.new(0, 1, 0), d.Color, 0.6, 0.25)
		T.bolt(spot + Vector3.new(0, 40, 0), spot + Vector3.new(0, 1, 0), WHITE, 0.25, 0.2)
		T.ring(spot, d.Color, d.BoltRadius, 0.3)
		fx():Burst(spot + Vector3.new(0, 1, 0), "Lightning", 12, { Color = ColorSequence.new(WHITE, d.Color) })
		T.sound("Crit", 0.6, 1.5)
		T.shake(ctx, 0.12)
	end,
}

E.arcane_blink = {
	Start = function(ctx)
		local d = ctx.Def
		T.pose(ctx, "Draw", 0.45)
		local origin = centerOf(ctx)
		-- the rune left behind
		local rune = disc(origin, d.Radius * 0.6, d.Color, 0.4)
		local star = {}
		for i = 1, 2 do
			local bar = T.part(Vector3.new(d.Radius * 1.05, 0.15, 0.5), CFrame.new(origin + Vector3.new(0, 0.2, 0)), rgb(240, 210, 255))
			star[i] = bar
		end
		T.animate(0.6, function(k)
			for i, bar in ipairs(star) do
				bar.CFrame = CFrame.new(origin + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, k * 4 + i * math.pi / 2, 0)
			end
			rune.Transparency = 0.4 + 0.3 * math.sin(k * 20) ^ 2
		end, function()
			rune:Destroy()
			for _, bar in ipairs(star) do
				bar:Destroy()
			end
			T.sound("Slam", 0.7, 1.5)
			fx():Sphere(origin + Vector3.new(0, 1, 0), d.Color, 2, d.Radius * 2, 0.45)
			fx():Pillar(origin, d.Color, 24, 0.5)
			fx():Burst(origin + Vector3.new(0, 1, 0), "Void", 24, { Speed = NumberRange.new(8, 16) })
		end)
		T.sound("DoubleJump", 1, 0.8)
		local land
		if ctx.Local then
			local length = d.Length
			local front = frontEnemy((ctx.Root :: BasePart).Position, ctx.Dir, d.Length, 0.6)
			if front then
				local to = front - (ctx.Root :: BasePart).Position
				length = math.min(length, Vector3.new(to.X, 0, to.Z).Magnitude + 3)
			end
			T.blink(ctx, length, d.Color)
			land = T.feet(ctx.Root)
		else
			local length = (ctx.Info and ctx.Info.Length) or (if ctx.Proc then 0 else d.Length)
			land = groundAt(ctx.Origin + ctx.Dir * length)
			if rootAlive(ctx) and not ctx.Proc then
				T.afterImage((ctx.Root :: BasePart).CFrame, d.Color, 0.4)
			end
		end
		T.streak(origin + Vector3.new(0, 3, 0), land + Vector3.new(0, 3, 0), d.Color, 1.2, 0.3)
		task.delay(0.12, function()
			T.ring(land, d.Color, d.Radius, 0.35, 0.4)
			fx():Sphere(land + Vector3.new(0, 1.5, 0), rgb(230, 190, 255), 2, d.Radius * 1.8, 0.35, Enum.Material.Neon)
			fx():Burst(land + Vector3.new(0, 1, 0), "Lightning", 18, { Color = ColorSequence.new(WHITE, d.Color) })
			T.shake(ctx, 0.25)
		end)
	end,
}

-- ===================== FIRE (Red) =====================
E.phoenix_dive = {
	Start = function(ctx)
		local d = ctx.Def
		T.pose(ctx, "Slam", 0.8, true)
		T.sound("Finisher", 1, 0.8)
		local root = ctx.Root :: BasePart
		if ctx.Local then
			local length = d.Length
			local front = frontEnemy(root.Position, ctx.Dir, d.Length, 0.6)
			if front then
				local to = front - root.Position
				length = math.min(length, math.max(0, Vector3.new(to.X, 0, to.Z).Magnitude - 3))
			end
			T.hop(ctx, 34)
			task.delay(0.06, function()
				T.dash(ctx, length, 0.34, d.Color)
			end)
		end
		-- flaming wings while diving
		if rootAlive(ctx) and not ctx.Proc then
			local flame = Particles.Create("Embers", root, { Rate = 70, Size = NumberSequence.new(1.6, 0), Speed = NumberRange.new(2, 6) })
			if flame then
				Debris:AddItem(flame, 0.5)
			end
			local wings = {}
			for i = 1, 2 do
				local wing = T.part(Vector3.new(0.3, 2.2, 5), root.CFrame, rgb(255, 160, 60))
				wing.Transparency = 0.2
				T.addTrail(wing, rgb(255, 90, 30), 2, 0.2)
				wings[i] = wing
			end
			T.animate(0.42, function(k)
				if not root.Parent then
					return
				end
				for i, wing in ipairs(wings) do
					local s = if i == 1 then 1 else -1
					wing.CFrame = root.CFrame * CFrame.new(s * 2.4, 1, 0.6) * CFrame.Angles(0, 0, s * (0.5 + math.sin(k * 18) * 0.35)) * CFrame.new(s * 1.2, 0, 0)
					wing.Transparency = 0.2 + 0.7 * k
				end
			end, function()
				for _, wing in ipairs(wings) do
					wing:Destroy()
				end
			end)
		end
		task.delay(0.42, function()
			local land
			if ctx.Info and typeof(ctx.Info.Center) == "Vector3" then
				land = groundAt(ctx.Info.Center)
			elseif rootAlive(ctx) and not ctx.Proc then
				land = T.feet(root)
			else
				land = groundAt(ctx.Origin)
			end
			T.sound("BossSlam", 1, 1)
			fx():Sphere(land + Vector3.new(0, 2, 0), rgb(255, 170, 60), 3, d.Radius * 2, 0.5, Enum.Material.Neon)
			T.ring(land, rgb(255, 80, 30), d.Radius, 0.5, 0.6)
			T.ring(land, rgb(255, 220, 120), d.Radius * 0.6, 0.4)
			fx():Pillar(land, rgb(255, 120, 40), 30, 0.6)
			fx():Burst(land + Vector3.new(0, 1, 0), "Embers", if low() then 24 else 70, {
				Speed = NumberRange.new(12, 28), Size = NumberSequence.new(1.8, 0), Lifetime = NumberRange.new(0.5, 1), SpreadAngle = Vector2.new(180, 40),
			})
			local glow = T.part(Vector3.new(1, 1, 1), CFrame.new(land + Vector3.new(0, 3, 0)), rgb(255, 140, 40))
			glow.Transparency = 1
			light(glow, rgb(255, 140, 50), d.Radius * 1.5, 4)
			Debris:AddItem(glow, 0.6)
			T.shake(ctx, 0.55)
			if ctx.Local then
				T.controllers().CameraController:Punch(-6, 0.3)
			end
		end)
	end,
	Hit = function(_ctx, hit, tag)
		if tag == "Burn" then
			fx():Burst(hit.Position, "Embers", 6, { Speed = NumberRange.new(2, 6), Size = NumberSequence.new(0.8, 0) })
		end
	end,
}

E.ring_of_fire = {
	Start = function(ctx)
		local d = ctx.Def
		T.pose(ctx, "Roar", 0.7)
		local duration = fieldTime(ctx)
		task.delay(0.2, function()
			local center = centerOf(ctx)
			T.sound("Slam", 1, 0.6)
			T.ring(center, rgb(255, 200, 80), d.Radius, 0.4, 0.4)
			local floor = disc(center, d.Radius, rgb(255, 90, 30), 0.82)
			light(floor, rgb(255, 120, 40), d.Radius * 1.6, 2.5)
			local count = if low() then 10 else 22
			local flames = {}
			for i = 1, count do
				local a = (i / count) * math.pi * 2
				local base = groundAt(center + Vector3.new(math.cos(a) * d.Radius, 0, math.sin(a) * d.Radius))
				local f = T.part(Vector3.new(1.8, 0.2, 1.8), CFrame.new(base), rgb(255, 150, 50))
				f.Transparency = 0.15
				flames[i] = { Part = f, Base = base, Phase = math.random() * 6, Height = 4 + math.random() * 3 }
				if not low() and i % 3 == 0 then
					Particles.Create("Embers", f, { Rate = 10, Speed = NumberRange.new(3, 7), Size = NumberSequence.new(1.2, 0) })
				end
			end
			T.animate(duration, function(k)
				local t = k * duration
				local grow = math.min(1, t / 0.25) * (1 - math.max(0, (t - duration + 0.4) / 0.4))
				for _, f in ipairs(flames) do
					local h = math.max(0.1, f.Height * grow * (0.75 + 0.25 * math.sin(t * 12 + f.Phase)))
					f.Part.Size = Vector3.new(1.8, h, 1.8)
					f.Part.CFrame = CFrame.new(f.Base + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, t * 2 + f.Phase, 0)
					f.Part.Color = rgb(255, 200, 70):Lerp(rgb(230, 40, 20), (math.sin(t * 7 + f.Phase) + 1) / 2)
				end
				floor.Transparency = 0.82 + 0.18 * (1 - grow)
			end, function()
				floor:Destroy()
				for _, f in ipairs(flames) do
					f.Part:Destroy()
				end
			end)
			T.shake(ctx, 0.2)
		end)
	end,
	Hit = function(_ctx, hit, tag)
		if tag == "Burn" and math.random() < 0.5 then
			fx():Burst(hit.Position, "Embers", 4, { Speed = NumberRange.new(2, 5), Size = NumberSequence.new(0.8, 0) })
		end
	end,
}

-- ===================== SMOKE STORM (Black) =====================
E.storm_cloud = {
	Start = function(ctx)
		T.pose(ctx, "Point", 0.7)
		T.sound("Slam", 0.6, 0.5)
	end,
	Result = function(ctx, info)
		local d = ctx.Def
		local center = info.Center
		if typeof(center) ~= "Vector3" then
			return
		end
		local duration = (info.Duration or 3.5) + 0.3
		local sky = center + Vector3.new(0, 22, 0)
		local puffs = {}
		for i = 1, (if low() then 6 else 12) do
			local off = randomIn(Vector3.zero, d.Radius * 0.9) + Vector3.new(0, (math.random() - 0.5) * 3, 0)
			local s = 6 + math.random() * 6
			local puff = T.part(Vector3.new(0.5, 0.5, 0.5), CFrame.new(sky + off), rgb(52 + math.random(0, 20), 52 + math.random(0, 20), 66), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
			puff.Transparency = 0.1
			T.tween(puff, { Size = Vector3.new(s, s * 0.7, s) }, 0.4, Enum.EasingStyle.Back)
			puffs[i] = puff
		end
		local shadow = disc(center, d.Radius, rgb(20, 20, 30), 0.7, Enum.Material.SmoothPlastic)
		local glow = T.part(Vector3.new(1, 1, 1), CFrame.new(sky), WHITE)
		glow.Transparency = 1
		local flashLight = light(glow, rgb(200, 220, 255), d.Radius * 2, 0)
		emitter(CFrame.new(sky - Vector3.new(0, 2, 0)), Vector3.new(d.Radius * 1.6, 0.5, d.Radius * 1.6), "Droplets", {
			Rate = if low() then 20 else 70, Speed = NumberRange.new(30, 40), Acceleration = Vector3.new(0, -30, 0),
			EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(4, 4), Lifetime = NumberRange.new(0.5, 0.7),
			Color = ColorSequence.new(rgb(170, 190, 230)),
		}, duration)
		T.animate(duration, function(k)
			local t = k * duration
			flashLight.Brightness = if math.random() < 0.08 then 6 else flashLight.Brightness * 0.8
			for i, puff in ipairs(puffs) do
				puff.CFrame = puff.CFrame * CFrame.new(math.sin(t * 2 + i) * 0.03, 0, math.cos(t * 2 + i) * 0.03)
			end
			if t > duration - 0.4 then
				local f = (t - duration + 0.4) / 0.4
				for _, puff in ipairs(puffs) do
					puff.Transparency = 0.1 + 0.9 * f
				end
				shadow.Transparency = 0.7 + 0.3 * f
			end
		end, function()
			for _, puff in ipairs(puffs) do
				puff:Destroy()
			end
			shadow:Destroy()
			glow:Destroy()
		end)
		-- a strike every tick even when nothing stands below
		for i = 1, d.Hits do
			task.delay(at(ctx, 0.5 + (i - 1) * d.Tick), function()
				local spot = groundAt(randomIn(center, d.Radius))
				T.bolt(sky + randomIn(Vector3.zero, 4), spot, rgb(220, 230, 255), 0.45, 0.22)
				T.sound("Crit", 0.7, 1.2 + math.random() * 0.3)
				T.shake(ctx, 0.15)
			end)
		end
	end,
	Hit = function(ctx, hit, tag)
		if type(tag) ~= "table" or not tag.Strike then
			return
		end
		local d = ctx.Def
		local center = ctx.Info and ctx.Info.Center
		local top = if typeof(center) == "Vector3" then center + Vector3.new(0, 22, 0) else hit.Position + Vector3.new(0, 22, 0)
		if math.random() < 0.6 then
			T.bolt(top + randomIn(Vector3.zero, 5), hit.Position, rgb(210, 220, 255), 0.35, 0.2)
		end
		fx():Burst(hit.Position, "Lightning", 6, { Color = ColorSequence.new(WHITE, d.Color) })
	end,
}

E.smoke_cyclone = {
	Start = function(ctx)
		local d = ctx.Def
		T.pose(ctx, "Spin", 0.7)
		T.sound("DoubleJump", 1, 0.6)
		local center = centerOf(ctx)
		local balls = {}
		for i = 1, (if low() then 8 else 20) do
			local b = T.part(Vector3.new(3, 3, 3), CFrame.new(center), rgb(60 + math.random(0, 40), 60 + math.random(0, 40), 80), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
			b.Transparency = 0.35
			balls[i] = { Part = b, Phase = (i / 10) * math.pi * 2, Height = math.random() * 6, Size = 2 + math.random() * 3 }
		end
		T.animate(0.65, function(k)
			local r = d.Radius * (1 - k * 0.85)
			for _, b in ipairs(balls) do
				local a = b.Phase + k * 10
				b.Part.CFrame = CFrame.new(center + Vector3.new(math.cos(a) * r, b.Height + k * 5, math.sin(a) * r))
				local s = b.Size * (1 + k)
				b.Part.Size = Vector3.new(s, s, s)
			end
		end, function()
			for _, b in ipairs(balls) do
				T.tween(b.Part, { Transparency = 1, CFrame = b.Part.CFrame + Vector3.new(0, 14, 0) }, 0.5)
				Debris:AddItem(b.Part, 0.55)
			end
			T.sound("BossSlam", 0.9, 1.4)
			fx():Pillar(center, rgb(150, 150, 180), 40, 0.6)
			fx():Burst(center + Vector3.new(0, 2, 0), "Smoke", if low() then 20 else 50, {
				Color = ColorSequence.new(rgb(110, 110, 130), rgb(40, 40, 50)), Speed = NumberRange.new(20, 40), Size = NumberSequence.new(3, 7),
				Lifetime = NumberRange.new(0.8, 1.3), SpreadAngle = Vector2.new(20, 20), Acceleration = Vector3.new(0, 10, 0),
			})
			for _ = 1, (if low() then 2 else 5) do
				local a = center + randomIn(Vector3.zero, 3) + Vector3.new(0, 2, 0)
				T.bolt(a, a + Vector3.new((math.random() - 0.5) * 6, 18 + math.random() * 10, (math.random() - 0.5) * 6), rgb(220, 225, 255), 0.3, 0.25)
			end
			T.ring(center, d.Color, d.Radius * 0.5, 0.35, 0.4)
			T.shake(ctx, 0.5)
		end)
	end,
}

-- ===================== HOLY LIGHT (White) =====================
E.holy_judgment = {
	Start = function(ctx)
		T.pose(ctx, "Point", 0.8)
		T.sound("TierUp", 0.8, 1.3)
	end,
	Result = function(ctx, info)
		local d = ctx.Def
		local center = info.Center
		if typeof(center) ~= "Vector3" then
			return
		end
		local mark = disc(center, d.Radius, rgb(255, 245, 200), 0.6)
		local sigils = {}
		for i = 1, 3 do
			local bar = T.part(Vector3.new(d.Radius * 1.9, 0.12, 0.45), CFrame.new(center + Vector3.new(0, 0.25, 0)), rgb(255, 220, 130))
			bar.Transparency = 0.3
			sigils[i] = bar
		end
		local guide = T.part(Vector3.new(0.4, 60, 0.4), CFrame.new(center + Vector3.new(0, 30, 0)), rgb(255, 250, 220))
		guide.Transparency = 0.5
		local lead = at(ctx, 0.6)
		T.animate(lead + 0.05, function(k)
			for i, bar in ipairs(sigils) do
				bar.CFrame = CFrame.new(center + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, -k * 3 + i * math.pi / 3, 0)
			end
		end, function()
			for _, bar in ipairs(sigils) do
				bar:Destroy()
			end
			guide:Destroy()
			fade(mark, 0.4)
			local pillar = T.part(Vector3.new(90, d.Radius * 1.8, d.Radius * 1.8), CFrame.new(center + Vector3.new(0, 120, 0)) * CFrame.Angles(0, 0, math.pi / 2), rgb(255, 252, 230), Enum.Material.Neon, Enum.PartType.Cylinder)
			pillar.Transparency = 0.1
			T.tween(pillar, { CFrame = CFrame.new(center + Vector3.new(0, 45, 0)) * CFrame.Angles(0, 0, math.pi / 2) }, 0.08, Enum.EasingStyle.Linear)
			task.delay(0.12, function()
				T.tween(pillar, { Size = Vector3.new(90, 0.5, 0.5), Transparency = 1 }, 0.6)
				Debris:AddItem(pillar, 0.65)
			end)
			light(pillar, rgb(255, 245, 210), 40, 5)
			T.sound("BossSlam", 1, 1.3)
			T.ring(center, rgb(255, 230, 150), d.Radius * 1.4, 0.5, 0.6)
			T.ring(center, WHITE, d.Radius, 0.35)
			fx():Burst(center + Vector3.new(0, 2, 0), "Radiance", if low() then 20 else 60, { Speed = NumberRange.new(14, 28), SpreadAngle = Vector2.new(180, 30) })
			T.shake(ctx, 0.55)
			if ctx.Local then
				fx():Flash(rgb(255, 250, 225), 0.25)
				T.controllers().CameraController:Punch(-5, 0.25)
			end
		end)
	end,
}

E.sanctuary = {
	Start = function(ctx)
		local d = ctx.Def
		T.pose(ctx, "Roar", 0.85)
		local duration = fieldTime(ctx)
		task.delay(0.2, function()
			local center = centerOf(ctx)
			T.sound("TierUp", 0.9, 1.5)
			T.ring(center, rgb(255, 230, 150), d.Radius, 0.5, 0.4)
			local floor = disc(center, d.Radius, rgb(255, 240, 190), 0.75)
			light(floor, rgb(255, 240, 200), d.Radius * 1.5, 1.5)
			local rim = T.part(Vector3.new(1.4, d.Radius * 2, d.Radius * 2), CFrame.new(center + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.pi / 2), rgb(255, 220, 120), Enum.Material.ForceField, Enum.PartType.Cylinder)
			rim.Transparency = 0.2
			local cross = {}
			for i = 1, 2 do
				local bar = T.part(Vector3.new(d.Radius * 1.5, 0.12, 1.2), CFrame.new(center + Vector3.new(0, 0.3, 0)), rgb(255, 250, 220))
				bar.Transparency = 0.35
				cross[i] = bar
			end
			emitter(CFrame.new(center + Vector3.new(0, 0.5, 0)), Vector3.new(d.Radius * 1.6, 0.2, d.Radius * 1.6), "Radiance", {
				Rate = if low() then 8 else 26, Speed = NumberRange.new(3, 6), EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(5, 5),
				Lifetime = NumberRange.new(1, 1.6),
			}, duration)
			if ctx.Local and rootAlive(ctx) then
				local aura = Particles.Create("Spirit", ctx.Root, { Rate = 12, Color = ColorSequence.new(rgb(255, 250, 220), rgb(255, 210, 120)) })
				if aura then
					Debris:AddItem(aura, duration)
				end
			end
			T.animate(duration, function(k)
				local t = k * duration
				for i, bar in ipairs(cross) do
					bar.CFrame = CFrame.new(center + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, t * 0.8 + i * math.pi / 2, 0)
				end
				local f = math.max(0, (t - duration + 0.5) / 0.5)
				floor.Transparency = 0.75 + 0.25 * f
				rim.Transparency = 0.2 + 0.8 * f
			end, function()
				floor:Destroy()
				rim:Destroy()
				for _, bar in ipairs(cross) do
					bar:Destroy()
				end
			end)
		end)
	end,
	Hit = function(_ctx, hit, tag)
		if tag == "Holy" and math.random() < 0.5 then
			fx():Burst(hit.Position, "Radiance", 5, { Speed = NumberRange.new(2, 5) })
		end
	end,
}

-- ===================== SUN (Gold) =====================
E.solar_flare = {
	Start = function(ctx)
		local d = ctx.Def
		T.pose(ctx, "Roar", 0.95)
		T.sound("TierUp", 0.8, 1.1)
		local center = centerOf(ctx)
		local sunPos = center + Vector3.new(0, 11, 0)
		local sun = T.part(Vector3.new(0.5, 0.5, 0.5), CFrame.new(sunPos), rgb(255, 230, 120), Enum.Material.Neon, Enum.PartType.Ball)
		local glow = light(sun, rgb(255, 220, 120), 30, 0)
		local rays = {}
		for i = 1, (if low() then 4 else 8) do
			local ray = T.part(Vector3.new(0.4, 0.4, 6), CFrame.new(sunPos), rgb(255, 200, 60))
			ray.Transparency = 0.3
			rays[i] = ray
		end
		T.animate(0.7, function(k)
			local s = 0.5 + k * 4.5
			sun.Size = Vector3.new(s, s, s)
			glow.Brightness = k * 6
			for i, ray in ipairs(rays) do
				local a = i / #rays * math.pi * 2 + k * 3
				ray.CFrame = CFrame.new(sunPos) * CFrame.Angles(0, a, 0) * CFrame.Angles(0.5 * math.sin(i), 0, 0) * CFrame.new(0, 0, -(s / 2 + 3))
			end
		end, function()
			sun:Destroy()
			for _, ray in ipairs(rays) do
				ray:Destroy()
			end
			T.sound("BossSlam", 1, 1.2)
			fx():Sphere(sunPos, rgb(255, 220, 90), 5, d.Radius * 2, 0.55, Enum.Material.Neon)
			T.ring(center, rgb(255, 200, 60), d.Radius, 0.5, 0.6)
			T.ring(center, rgb(255, 250, 200), d.Radius * 0.65, 0.4)
			fx():Burst(sunPos, "Radiance", if low() then 30 else 90, { Speed = NumberRange.new(20, 40), Lifetime = NumberRange.new(0.5, 1), SpreadAngle = Vector2.new(180, 180) })
			for _ = 1, (if low() then 4 else 10) do
				local dir = Vector3.new(math.random() - 0.5, math.random() * 0.4, math.random() - 0.5)
				if dir.Magnitude > 0.05 then
					T.streak(sunPos, sunPos + dir.Unit * d.Radius, rgb(255, 240, 160), 0.6, 0.35)
				end
			end
			T.shake(ctx, 0.7)
			if ctx.Local then
				fx():Flash(rgb(255, 245, 190), 0.4)
				T.controllers().CameraController:Punch(-6, 0.3)
			end
		end)
	end,
}

E.sunbeam = {
	Start = function(ctx)
		local d = ctx.Def
		T.pose(ctx, "Cast", 1.6)
		local dir = ctx.Dir
		local duration = 0.25 + d.Hits * d.Tick
		task.delay(0.18, function()
			local from = handOf(ctx)
			local to = from + dir * d.Length
			local mid = (from + to) / 2
			local look = CFrame.lookAt(mid, to)
			local core = T.part(Vector3.new(d.Width * 0.35, d.Width * 0.35, d.Length), look, rgb(255, 255, 230))
			core.Transparency = 0.05
			local outer = T.part(Vector3.new(d.Width, d.Width, d.Length), look, rgb(255, 200, 60), Enum.Material.ForceField)
			outer.Transparency = 0.1
			local flare = T.part(Vector3.new(4, 4, 4), CFrame.new(from), rgb(255, 240, 160), Enum.Material.Neon, Enum.PartType.Ball)
			light(flare, rgb(255, 220, 120), 30, 4)
			local tip = T.part(Vector3.new(5, 5, 5), CFrame.new(to), rgb(255, 220, 110), Enum.Material.Neon, Enum.PartType.Ball)
			tip.Transparency = 0.3
			emitter(look, Vector3.new(d.Width * 0.6, d.Width * 0.6, d.Length), "Radiance", {
				Rate = if low() then 12 else 40, Speed = NumberRange.new(2, 6),
			}, duration)
			T.sound("Crit", 1, 0.6)
			local lastTick = 0
			T.animate(duration, function(k)
				local t = k * duration
				local pulse = 1 + 0.15 * math.sin(t * 30)
				local thin = 1 - math.max(0, (t - duration + 0.3) / 0.3)
				core.Size = Vector3.new(d.Width * 0.35 * pulse * thin + 0.05, d.Width * 0.35 * pulse * thin + 0.05, d.Length)
				outer.Size = Vector3.new(d.Width * thin + 0.05, d.Width * thin + 0.05, d.Length)
				tip.Size = Vector3.new(5, 5, 5) * (pulse * thin + 0.05)
				flare.Size = Vector3.new(4, 4, 4) * (pulse * thin + 0.05)
				if t - lastTick > d.Tick then
					lastTick = t
					T.sound("Hit", 0.6, 0.8)
					T.shake(ctx, 0.1)
				end
			end, function()
				core:Destroy()
				outer:Destroy()
				flare:Destroy()
				tip:Destroy()
			end)
		end)
	end,
}

-- ===================== BLOOD (Crimson) =====================
E.crimson_crescent = {
	Start = function(ctx)
		local d = ctx.Def
		T.pose(ctx, "Draw", 0.65)
		local dir = ctx.Dir
		task.delay(0.16, function()
			T.sound("Finisher", 1, 0.6)
			T.shake(ctx, 0.3)
			local from = handOf(ctx) - Vector3.new(0, 0.5, 0)
			local side = sideOf(dir)
			local count = if low() then 7 else 13
			local pieces = {}
			for i = 1, count do
				local u = (i - 1) / (count - 1) * 2 - 1 -- -1 .. 1 across the arc
				local thick = 1.6 * (1 - u * u) + 0.25
				local p = T.part(Vector3.new(d.Width / count * 1.5, thick, thick * 0.5), CFrame.new(from), if math.abs(u) < 0.4 then rgb(255, 90, 110) else rgb(200, 10, 40))
				p.Transparency = 0.05
				if i % 3 == 1 then
					T.addTrail(p, rgb(160, 0, 30), thick, 0.25)
				end
				pieces[i] = { Part = p, U = u }
			end
			local travel = 0.5
			T.animate(travel, function(k)
				local center = from + dir * (d.Length * k)
				for _, piece in ipairs(pieces) do
					local u = piece.U
					local pos = center + side * (u * d.Width / 2) - dir * (u * u * d.Width * 0.3) + Vector3.new(0, 1 - u * u, 0)
					piece.Part.CFrame = CFrame.lookAt(pos, pos + side) * CFrame.Angles(0, 0, u * 0.6)
					piece.Part.Transparency = 0.05 + 0.9 * math.max(0, (k - 0.75) / 0.25)
				end
			end, function()
				for _, piece in ipairs(pieces) do
					piece.Part:Destroy()
				end
			end)
		end)
	end,
	Hit = function(_ctx, hit, tag)
		local burst = if tag == "Bleed" then 4 else 10
		fx():Burst(hit.Position, "Droplets", burst, {
			Color = ColorSequence.new(rgb(230, 20, 50), rgb(120, 0, 20)), Speed = NumberRange.new(6, 12), Size = NumberSequence.new(0.5, 0),
			Acceleration = Vector3.new(0, -40, 0), SpreadAngle = Vector2.new(70, 70),
		})
	end,
}

E.life_drain = {
	Start = function(ctx)
		T.pose(ctx, "Cast", 2)
		T.sound("Equip", 0.9, 0.5)
		if rootAlive(ctx) and not ctx.Proc then
			fx():Burst((ctx.Root :: BasePart).Position, "BloodFlame", 20, { Speed = NumberRange.new(4, 10) })
		end
	end,
	Result = function(ctx, info)
		local d = ctx.Def
		local targets = if type(info.Targets) == "table" then info.Targets else {}
		local duration = (info.Duration or 2.3) + 0.1
		local root = ctx.Root :: BasePart
		local links = {}
		for i, t in ipairs(targets) do
			if typeof(t.Position) == "Vector3" then
				local tether = T.part(Vector3.new(0.35, 0.35, 1), CFrame.new(t.Position), rgb(220, 20, 60))
				tether.Transparency = 0.25
				local orb = T.part(Vector3.new(0.9, 0.9, 0.9), CFrame.new(t.Position), rgb(255, 80, 110), Enum.Material.Neon, Enum.PartType.Ball)
				links[i] = { Tether = tether, Orb = orb, Uid = t.Uid, Last = t.Position, Phase = math.random() }
			end
		end
		T.animate(duration, function(k)
			local t = k * duration
			local to = if rootAlive(ctx) and not ctx.Proc then root.Position else ctx.Origin + Vector3.new(0, 2, 0)
			for _, link in ipairs(links) do
				local er = enemyRoot(link.Uid)
				if er then
					link.Last = er.Position
				end
				local a = link.Last
				local len = (to - a).Magnitude
				local wobble = 0.35 + 0.15 * math.sin(t * 20 + link.Phase * 6)
				link.Tether.Size = Vector3.new(wobble, wobble, math.max(0.1, len))
				link.Tether.CFrame = CFrame.lookAt((a + to) / 2, to)
				link.Tether.Transparency = 0.25 + 0.75 * math.max(0, (k - 0.85) / 0.15)
				local f = (t * 1.6 + link.Phase) % 1
				link.Orb.CFrame = CFrame.new(a:Lerp(to, f))
				link.Orb.Transparency = link.Tether.Transparency
			end
		end, function()
			for _, link in ipairs(links) do
				link.Tether:Destroy()
				link.Orb:Destroy()
			end
		end)
		if #targets > 0 then
			for i = 1, d.Hits do
				task.delay(at(ctx, 0.3 + (i - 1) * d.Tick), function()
					if rootAlive(ctx) and not ctx.Proc then
						fx():Burst(root.Position, "BloodFlame", 6, { Speed = NumberRange.new(2, 5) })
					end
					T.sound("Hit", 0.5, 0.7)
				end)
			end
		end
	end,
}

-- ===================== DARKNESS (Shadow) =====================
local function shadowHand(base: Vector3, size: number, face: number): { BasePart }
	local dark = rgb(24, 10, 44)
	local edge = rgb(170, 90, 255)
	local cf = CFrame.new(base) * CFrame.Angles(0, face, 0)
	local palm = T.part(Vector3.new(size * 0.9, size * 0.9, size * 0.35), cf, dark, Enum.Material.SmoothPlastic)
	local parts = { palm }
	for _ = 1, 4 do
		local finger = T.part(Vector3.new(size * 0.18, size * 0.85, size * 0.18), cf, dark, Enum.Material.SmoothPlastic)
		table.insert(parts, finger)
	end
	local glow = T.part(Vector3.new(size * 0.95, 0.2, size * 0.4), cf, edge)
	table.insert(parts, glow)
	return parts
end

local function placeHand(parts: { BasePart }, cf: CFrame, size: number, curl: number)
	parts[1].CFrame = cf
	for i = 2, 5 do
		local x = (i - 3.5) * size * 0.24
		parts[i].CFrame = cf * CFrame.new(x, size * 0.45, 0) * CFrame.Angles(-curl, 0, 0) * CFrame.new(0, size * 0.4, 0)
	end
	parts[6].CFrame = cf * CFrame.new(0, -size * 0.45, 0)
end

E.umbral_grasp = {
	Start = function(ctx)
		local d = ctx.Def
		T.pose(ctx, "Slam", 0.8)
		T.sound("Slam", 0.8, 0.6)
		task.delay(0.15, function()
			local center = centerOf(ctx)
			local pool = disc(center, 2, rgb(16, 6, 30), 0.25, Enum.Material.SmoothPlastic)
			T.tween(pool, { Size = Vector3.new(0.2, d.Radius * 2, d.Radius * 2) }, 0.3)
			fade(pool, 0.5, 1.4)
			T.ring(center, d.Color, d.Radius, 0.4, 0.3)
			fx():Burst(center + Vector3.new(0, 1, 0), "Shadow", if low() then 10 else 30, { Speed = NumberRange.new(6, 14) })
		end)
	end,
	Result = function(ctx, info)
		local targets = if type(info.Targets) == "table" then info.Targets else {}
		local max = if low() then 6 else 14
		for i, t in ipairs(targets) do
			if i > max or typeof(t.Position) ~= "Vector3" then
				break
			end
			local size = math.clamp((t.Height or 5) * 0.75, 3, 9)
			local base = groundAt(t.Position)
			local face = math.random() * 6
			local hand = shadowHand(base - Vector3.new(0, size, 0), size, face)
			local holdUntil = 1.35
			local start = math.max(0, 0.3 - (ctx.Elapsed or 0))
			T.animate(start + holdUntil + 0.2, function(k)
				local tt = k * (start + holdUntil + 0.2)
				local rise = math.clamp((tt - start) / 0.15, 0, 1)
				local curl = if tt < start + holdUntil - 0.3 then 0.3 + 0.5 * rise else 0.8 + 0.9 * math.min(1, (tt - start - holdUntil + 0.3) / 0.25)
				local cf = CFrame.new(base + Vector3.new(0, -size + rise * size * 1.1, 0)) * CFrame.Angles(0, face, 0)
				placeHand(hand, cf, size, curl)
			end, function()
				fx():Burst(base + Vector3.new(0, size * 0.6, 0), "Void", 14, { Speed = NumberRange.new(6, 12) })
				for _, p in ipairs(hand) do
					T.tween(p, { Transparency = 1, CFrame = p.CFrame - Vector3.new(0, size, 0) }, 0.35)
					Debris:AddItem(p, 0.4)
				end
			end)
		end
		task.delay(at(ctx, 1.35), function()
			T.sound("BossSlam", 0.9, 0.9)
			T.shake(ctx, 0.45)
		end)
	end,
}

E.eclipse = {
	Start = function(ctx)
		local d = ctx.Def
		T.pose(ctx, "Roar", 0.85)
		local duration = fieldTime(ctx)
		task.delay(0.2, function()
			local center = centerOf(ctx)
			T.sound("TierUp", 0.8, 0.5)
			local dome = T.part(Vector3.new(2, 2, 2), CFrame.new(center), rgb(20, 8, 40), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
			dome.Transparency = 0.55
			T.tween(dome, { Size = Vector3.new(d.Radius * 2, d.Radius * 2, d.Radius * 2) }, 0.4, Enum.EasingStyle.Back)
			local shell = T.part(Vector3.new(2, 2, 2), CFrame.new(center), d.Color, Enum.Material.ForceField, Enum.PartType.Ball)
			shell.Transparency = 0.2
			T.tween(shell, { Size = Vector3.new(d.Radius * 2.05, d.Radius * 2.05, d.Radius * 2.05) }, 0.4, Enum.EasingStyle.Back)
			-- the black sun above
			local sunPos = center + Vector3.new(0, d.Radius + 6, 0)
			local blackSun = T.part(Vector3.new(7, 7, 7), CFrame.new(sunPos), rgb(5, 0, 10), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
			local corona = T.part(Vector3.new(8.4, 8.4, 8.4), CFrame.new(sunPos), rgb(190, 110, 255), Enum.Material.ForceField, Enum.PartType.Ball)
			emitter(CFrame.new(center + Vector3.new(0, 1, 0)), Vector3.new(d.Radius * 1.4, 2, d.Radius * 1.4), "Shadow", {
				Rate = if low() then 6 else 20, Speed = NumberRange.new(1, 3), Size = NumberSequence.new(2, 4),
			}, duration)
			local tint
			if ctx.Local then
				tint = Instance.new("ColorCorrectionEffect")
				tint.Name = "EclipseTint"
				tint.Brightness = 0
				tint.TintColor = WHITE
				tint.Parent = Lighting
				T.tween(tint, { Brightness = -0.12, TintColor = rgb(200, 180, 255), Saturation = -0.3 }, 0.4)
			end
			T.animate(duration, function(k)
				local t = k * duration
				local f = math.max(0, (t - duration + 0.5) / 0.5)
				dome.Transparency = 0.55 + 0.45 * f
				shell.Transparency = 0.2 + 0.8 * f
				corona.Transparency = 0.1 + 0.3 * math.sin(t * 4) ^ 2 + 0.6 * f
				blackSun.Transparency = f
			end, function()
				dome:Destroy()
				shell:Destroy()
				blackSun:Destroy()
				corona:Destroy()
				if tint then
					T.tween(tint, { Brightness = 0, TintColor = WHITE, Saturation = 0 }, 0.4)
					Debris:AddItem(tint, 0.45)
				end
			end)
		end)
	end,
	Hit = function(_ctx, hit, tag)
		if tag == "Shadow" and math.random() < 0.4 then
			fx():Burst(hit.Position, "Shadow", 4, { Speed = NumberRange.new(1, 3) })
		end
	end,
}

-- ===================== COSMIC (Celestial) =====================
E.starfall = {
	Start = function(ctx)
		T.pose(ctx, "Point", 0.9)
		T.sound("TierUp", 0.8, 1.6)
	end,
	Result = function(ctx, info)
		local d = ctx.Def
		local impacts = if type(info.Impacts) == "table" then info.Impacts else {}
		local leadT, step = info.Lead or 0.55, info.Step or 0.18
		if typeof(info.Center) == "Vector3" then
			local zone = disc(info.Center, d.Radius, rgb(60, 80, 180), 0.75)
			fade(zone, 0.5, leadT + #impacts * step)
		end
		for i, spot in ipairs(impacts) do
			if typeof(spot) == "Vector3" then
				local mark = disc(spot, d.MeteorRadius * 0.6, d.Color, 0.6)
				local landAt = leadT + (i - 1) * step
				fade(mark, 0.2, at(ctx, landAt))
				task.delay(at(ctx, landAt - 0.32), function()
					local from = spot + Vector3.new((math.random() - 0.5) * 30, 75, (math.random() - 0.5) * 30)
					local star = T.part(Vector3.new(3, 3, 3), CFrame.new(from), rgb(230, 245, 255), Enum.Material.Neon, Enum.PartType.Ball)
					local shell = T.part(Vector3.new(4.4, 4.4, 4.4), CFrame.new(from), d.Color, Enum.Material.ForceField, Enum.PartType.Ball)
					T.addTrail(star, d.Color, 2.6, 0.3)
					T.animate(0.32, function(k)
						local p = from:Lerp(spot, k * k)
						star.CFrame = CFrame.new(p)
						shell.CFrame = CFrame.new(p)
					end, function()
						star:Destroy()
						shell:Destroy()
						T.sound("Slam", 0.7, 1.1 + math.random() * 0.3)
						fx():Sphere(spot + Vector3.new(0, 1, 0), rgb(200, 230, 255), 2, d.MeteorRadius * 2, 0.4, Enum.Material.Neon)
						T.ring(spot, d.Color, d.MeteorRadius, 0.35, 0.4)
						fx():Burst(spot + Vector3.new(0, 1, 0), "Stars", if low() then 6 else 16, { Speed = NumberRange.new(8, 18), Lifetime = NumberRange.new(0.5, 1) })
						T.shake(ctx, 0.2)
					end)
				end)
			end
		end
	end,
}

E.constellation = {
	Start = function(ctx)
		T.pose(ctx, "Point", 0.8)
	end,
	Result = function(ctx, info)
		local d = ctx.Def
		local chain = if type(info.Chain) == "table" then info.Chain else {}
		local delayT = at(ctx, info.Delay or 0.9)
		local stars, lines = {}, {}
		local prev = if not ctx.Proc and rootAlive(ctx) then handOf(ctx) else nil
		for i, link in ipairs(chain) do
			if typeof(link.Position) == "Vector3" then
				local p = link.Position + Vector3.new(0, (link.Height or 5) * 0.75 + 1, 0)
				local appear = math.min(delayT * 0.7, (i - 1) * 0.05)
				local star = T.part(Vector3.new(1.4, 1.4, 1.4), CFrame.new(p), WHITE, Enum.Material.Neon, Enum.PartType.Ball)
				star.Transparency = 1
				local spikes = {}
				for j = 1, 2 do
					local s = T.part(Vector3.new(3.2, 0.2, 0.2), CFrame.new(p) * CFrame.Angles(0, 0, j * math.pi / 2 + math.pi / 4), d.Color)
					s.Transparency = 1
					spikes[j] = s
				end
				local a = prev
				task.delay(appear, function()
					star.Transparency = 0
					for _, s in ipairs(spikes) do
						s.Transparency = 0.1
					end
					T.sound("Coin", 0.6, 1.4 + i * 0.05)
					if a then
						local len = (p - a).Magnitude
						local line = T.part(Vector3.new(0.18, 0.18, len), CFrame.lookAt((a + p) / 2, p), d.Color)
						line.Transparency = 0.2
						table.insert(lines, line)
					end
				end)
				table.insert(stars, { Star = star, Spikes = spikes, Pos = p })
				prev = p
			end
		end
		task.delay(delayT, function()
			T.sound("Crit", 1, 1.6)
			T.shake(ctx, 0.35)
			for _, s in ipairs(stars) do
				fx():Sphere(s.Pos, rgb(200, 230, 255), 1, 9, 0.35, Enum.Material.Neon)
				fx():Burst(s.Pos, "Stars", if low() then 4 else 12, { Speed = NumberRange.new(6, 14) })
				s.Star:Destroy()
				for _, sp in ipairs(s.Spikes) do
					sp:Destroy()
				end
			end
			for _, line in ipairs(lines) do
				line.Color = WHITE
				fade(line, 0.3)
			end
			if ctx.Local then
				fx():Flash(rgb(200, 225, 255), 0.15)
			end
		end)
	end,
}

-- ===================== VOID GRAVITY (Void) =====================
E.black_hole = {
	Start = function(ctx)
		T.pose(ctx, "Cast", 0.9)
		T.sound("TierUp", 0.8, 0.45)
	end,
	Result = function(ctx, info)
		local d = ctx.Def
		local center = info.Center
		if typeof(center) ~= "Vector3" then
			return
		end
		local duration = at(ctx, info.Duration or 2.7)
		local core = center + Vector3.new(0, 4, 0)
		local hole = T.part(Vector3.new(0.5, 0.5, 0.5), CFrame.new(core), rgb(0, 0, 0), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		local shell = T.part(Vector3.new(0.5, 0.5, 0.5), CFrame.new(core), d.Color, Enum.Material.ForceField, Enum.PartType.Ball)
		local disk = T.part(Vector3.new(0.3, 12, 12), CFrame.new(core), rgb(230, 120, 255), Enum.Material.Neon, Enum.PartType.Cylinder)
		disk.Transparency = 0.45
		local orbiters = {}
		for i = 1, (if low() then 4 else 10) do
			local o = T.part(Vector3.new(0.8, 0.8, 0.8), CFrame.new(core), if i % 2 == 0 then rgb(255, 160, 255) else rgb(150, 60, 255), Enum.Material.Neon, Enum.PartType.Ball)
			T.addTrail(o, d.Color, 0.6, 0.25)
			orbiters[i] = { Part = o, Phase = math.random() * 6, Radius = 4 + math.random() * (d.Radius * 0.5) }
		end
		emitter(CFrame.new(core), Vector3.new(d.Radius * 1.4, 4, d.Radius * 1.4), "Void", {
			Rate = if low() then 10 else 40, Speed = NumberRange.new(-14, -8), Lifetime = NumberRange.new(0.6, 1),
		}, duration + 0.3)
		local lastPulse = 0
		T.animate(duration, function(k)
			local t = k * duration
			local s = math.min(1, t / 0.3) * 6
			hole.Size = Vector3.new(s, s, s)
			shell.Size = Vector3.new(s * 1.35, s * 1.35, s * 1.35)
			disk.CFrame = CFrame.new(core) * CFrame.Angles(0.35, t * 3, math.pi / 2 + 0.2)
			for _, o in ipairs(orbiters) do
				local r = o.Radius * (1 - ((t * 0.7 + o.Phase) % 1))
				local a = o.Phase + t * 7
				o.Part.CFrame = CFrame.new(core + Vector3.new(math.cos(a) * r, math.sin(a * 0.5) * 1.5, math.sin(a) * r))
			end
			if t - lastPulse > 0.4 then
				lastPulse = t
				-- a ring that shrinks into the hole
				local pr = T.part(Vector3.new(0.3, d.Radius * 2, d.Radius * 2), CFrame.new(center + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2), d.Color, Enum.Material.Neon, Enum.PartType.Cylinder)
				pr.Transparency = 0.6
				T.tween(pr, { Size = Vector3.new(0.3, 1, 1), Transparency = 0.95 }, 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				Debris:AddItem(pr, 0.45)
				T.shake(ctx, 0.08)
			end
		end, function()
			T.tween(hole, { Size = Vector3.new(0.2, 0.2, 0.2) }, 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			Debris:AddItem(hole, 0.16)
			shell:Destroy()
			disk:Destroy()
			for _, o in ipairs(orbiters) do
				o.Part:Destroy()
			end
			task.delay(0.15, function()
				T.sound("BossSlam", 1, 0.8)
				fx():Sphere(core, d.Color, 2, d.Radius * 1.6, 0.5)
				fx():Sphere(core, rgb(255, 220, 255), 1, d.Radius, 0.3, Enum.Material.Neon)
				T.ring(center, d.Color, d.Radius, 0.5, 0.6)
				fx():Burst(core, "Void", if low() then 20 else 60, { Speed = NumberRange.new(14, 30) })
				T.shake(ctx, 0.7)
				if ctx.Local then
					fx():Flash(rgb(200, 100, 255), 0.25)
					T.controllers().CameraController:Punch(-6, 0.3)
				end
			end)
		end)
	end,
}

E.zero_gravity = {
	Start = function(ctx)
		local d = ctx.Def
		T.pose(ctx, "Roar", 0.9)
		T.sound("TierUp", 0.8, 0.7)
		local center = centerOf(ctx)
		task.delay(0.15, function()
			T.ring(center, d.Color, d.Radius, 0.6, 0.4)
			fx():Sphere(center + Vector3.new(0, 1, 0), d.Color, 4, d.Radius * 2, 0.6)
		end)
		local hang = 1.8 + 0.1 * (level(ctx) - 1)
		-- loose rocks float up with the enemies
		for _ = 1, (if low() then 4 else 12) do
			local spot = groundAt(randomIn(center, d.Radius))
			local s = 0.8 + math.random() * 1.4
			local rock = T.part(Vector3.new(s, s * 0.8, s), CFrame.new(spot), rgb(110, 90, 120), Enum.Material.Slate)
			local rise = 4 + math.random() * 6
			local spin = Vector3.new(math.random(), math.random(), math.random()) * 2
			local fall = 0.2 + hang
			T.animate(fall + 0.3, function(k)
				local t = k * (fall + 0.3)
				local y = if t < fall then rise * math.sin(math.min(1, t / 0.8) * math.pi / 2) else rise * (1 - (t - fall) / 0.3)
				rock.CFrame = CFrame.new(spot + Vector3.new(0, y + s / 2, 0)) * CFrame.Angles(spin.X * t, spin.Y * t, spin.Z * t)
			end, function()
				fade(rock, 0.3)
			end)
		end
	end,
	Result = function(ctx, info)
		local d = ctx.Def
		local hang = info.Hang or 1.8
		local targets = if type(info.Targets) == "table" then info.Targets else {}
		if not low() then
			for i, t in ipairs(targets) do
				if i > 16 then
					break
				end
				local r = enemyRoot(t.Uid)
				if r then
					local e = Particles.Create("Void", r, { Rate = 10 })
					if e then
						Debris:AddItem(e, hang + 0.3)
					end
				end
			end
		end
		task.delay(at(ctx, 0.2 + hang + 0.25), function()
			T.sound("BossSlam", 1, 0.7)
			T.shake(ctx, 0.6)
			for i, t in ipairs(targets) do
				if i > 16 then
					break
				end
				local r = enemyRoot(t.Uid)
				local p = groundAt(if r then r.Position else t.Position)
				T.ring(p, d.Color, 5, 0.35, 0.4)
				fx():Burst(p + Vector3.new(0, 1, 0), "Smoke", 8, { Color = ColorSequence.new(rgb(150, 120, 170)), Speed = NumberRange.new(6, 12), Size = NumberSequence.new(1.5, 3) })
			end
			if ctx.Local then
				T.controllers().CameraController:Punch(-5, 0.25)
			end
		end)
	end,
}

function ElementEffects.Register(effects: { [string]: any }, tools)
	T = tools
	for id, e in pairs(E) do
		if effects[id] == nil then
			effects[id] = e
		end
	end
end

ElementEffects.Effects = E

return ElementEffects
