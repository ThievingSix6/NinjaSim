--[[
	UltimateEffects: the looks of the suit mastery ultimates (Config/Mastery), client
	side only. SkillEffects requires this and calls Register(E, tools), which adds a
	{ Start, Result } entry for every suit's four ultimates, drawn in the suit's
	element colour with the shared toolkit.

	  Rush       dash with after-images, a streak along the path, a burst at the end
	  Lance      charge at the hand, then a huge beam that pulses once per hit
	  Cataclysm  a leap, then three expanding shockwave rings and pillars
	  Avatar     a flash and an elemental aura on the character for the duration;
	             each awakened swing (info.Wave) sends a crescent wave forward
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Mastery = require(Shared.Config.Mastery)
local Particles = require(Shared.Visuals.Particles)

local UltimateEffects = {}

local T -- SkillEffects.Tools
local WHITE = Color3.new(1, 1, 1)

local function fx()
	return T.fx()
end

local function lighter(c: Color3): Color3
	return c:Lerp(WHITE, 0.45)
end

local function feetOf(ctx): Vector3
	local root = ctx.Root :: BasePart?
	if root and root.Parent and not ctx.Proc then
		return T.feet(root)
	end
	return ctx.Origin - Vector3.new(0, 2.9, 0)
end

local looks = {}

looks.Rush = {
	Start = function(ctx)
		local d, color = ctx.Def, ctx.Def.Color
		T.pose(ctx, "Draw", 0.5, true)
		T.sound("Finisher", 1, 0.8)
		T.dash(ctx, d.Length, 0.32, color)
		local from = ctx.Origin
		T.streak(from, from + ctx.Dir * d.Length, lighter(color), 2.4, 0.5)
		T.streak(from + Vector3.new(0, 1.2, 0), from + ctx.Dir * d.Length + Vector3.new(0, 1.2, 0), color, 1.2, 0.7)
		T.shake(ctx, 0.35)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local finish = ctx.Origin + ctx.Dir * (info.Length or d.Length)
		task.delay(math.max(0, 0.42 - (ctx.Elapsed or 0)), function()
			T.ring(finish - Vector3.new(0, 2.8, 0), color, d.BurstRadius, 0.5, 3)
			fx():Sphere(finish, lighter(color), 3, d.BurstRadius * 1.4, 0.45)
			fx():Burst(finish, "Radiance", if T.lowGraphics() then 8 else 22, { Color = ColorSequence.new(WHITE, color) })
			T.sound("BossSlam", 0.9, 1.3)
			T.shake(ctx, 0.5)
		end)
	end,
}

looks.Lance = {
	Start = function(ctx)
		local d, color = ctx.Def, ctx.Def.Color
		T.pose(ctx, "Point", d.Windup + d.Hits * d.Tick + 0.2)
		fx():Sphere(T.hand(ctx), lighter(color), 1, 4, d.Windup, Enum.Material.Neon)
		T.sound("TierUp", 0.6, 1.6)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		local length = info.Length or d.Length
		local wait = math.max(0, (info.Windup or d.Windup) - (ctx.Elapsed or 0))
		task.delay(wait, function()
			local root = ctx.Root :: BasePart?
			local origin = if root and root.Parent and not ctx.Proc then root.Position else ctx.Origin
			local start = origin + ctx.Dir * 2 + Vector3.new(0, 0.6, 0)
			local cf = CFrame.lookAt(start + ctx.Dir * (length / 2), start + ctx.Dir * length)
			local core = T.part(Vector3.new(d.Width * 0.45, d.Width * 0.45, length), cf, WHITE)
			local shell = T.part(Vector3.new(d.Width, d.Width, length), cf, color)
			shell.Transparency = 0.45
			local span = (info.Hits or d.Hits) * (info.Tick or d.Tick)
			T.animate(span + 0.25, function(k)
				local pulse = 1 + math.sin(k * math.pi * 2 * (info.Hits or d.Hits)) * 0.18
				local fade = if k > 0.8 then 1 - (k - 0.8) / 0.2 else 1
				core.Size = Vector3.new(d.Width * 0.45 * pulse * fade, d.Width * 0.45 * pulse * fade, length)
				shell.Size = Vector3.new(d.Width * pulse * fade, d.Width * pulse * fade, length)
				shell.Transparency = 0.45 + (1 - fade) * 0.55
			end, function()
				core:Destroy()
				shell:Destroy()
			end)
			T.ring(start - Vector3.new(0, 3.2, 0), color, 10, 0.4, 2)
			T.sound("Finisher", 1, 0.6)
			T.shake(ctx, 0.45)
			if ctx.Local then
				T.controllers().CameraController:Punch(-6, 0.3)
			end
		end)
	end,
}

looks.Cataclysm = {
	Start = function(ctx)
		T.pose(ctx, "Slam", 0.9, true)
		T.hop(ctx, 60)
		T.sound("Finisher", 1, 0.5)
	end,
	Result = function(ctx, info)
		local d, color = ctx.Def, ctx.Def.Color
		for i, radius in ipairs(info.Radii or d.Radii) do
			task.delay(math.max(0, 0.35 + (i - 1) * (info.Interval or d.Interval) - (ctx.Elapsed or 0)), function()
				local center = feetOf(ctx)
				T.ring(center, color, radius, 0.55, 4 + i * 2)
				T.ring(center, lighter(color), radius * 0.7, 0.45, 2)
				local pillars = if T.lowGraphics() then 4 else 10
				for p = 1, pillars do
					local a = p / pillars * math.pi * 2 + i
					fx():Pillar(center + Vector3.new(math.cos(a) * radius * 0.8, 0, math.sin(a) * radius * 0.8), color, 10 + i * 6, 0.6)
				end
				T.sound("BossSlam", 1, 0.8 + i * 0.12)
				T.shake(ctx, 0.4 + i * 0.15)
				if ctx.Local and i == 3 then
					fx():Flash(lighter(color), 0.25)
				end
			end)
		end
	end,
}

-- the aura worn while an Avatar is awake (one per character)
local auras: { [Model]: { Until: number, Parts: { Instance } } } = {}
local function aura(ctx, duration: number)
	local character = ctx.Character :: Model?
	local root = ctx.Root :: BasePart?
	if not character or not root or not root.Parent then
		return
	end
	local old = auras[character]
	if old then
		for _, inst in ipairs(old.Parts) do
			inst:Destroy()
		end
	end
	local color = ctx.Def.Color
	local made = {}
	local highlight = Instance.new("Highlight")
	highlight.FillColor = color
	highlight.FillTransparency = 0.75
	highlight.OutlineColor = lighter(color)
	highlight.OutlineTransparency = 0.1
	highlight.Parent = character
	table.insert(made, highlight)
	local emitter = Particles.Create("Sparkle", root, { Rate = if T.lowGraphics() then 8 else 30, Color = ColorSequence.new(WHITE, color) })
	if emitter then
		table.insert(made, emitter)
	end
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 14
	light.Brightness = 2
	light.Parent = root
	table.insert(made, light)
	local entry = { Until = os.clock() + duration, Parts = made }
	auras[character] = entry
	task.delay(duration, function()
		if auras[character] == entry then
			auras[character] = nil
			for _, inst in ipairs(made) do
				inst:Destroy()
			end
		end
	end)
end

looks.Avatar = {
	Start = function(ctx)
		if ctx.Info and ctx.Info.Wave then
			return -- an awakened swing: drawn in Result
		end
		local color = ctx.Def.Color
		T.pose(ctx, "Roar", 0.9)
		T.sound("TierUp", 1, 0.7)
		fx():Pillar(feetOf(ctx), color, 60, 1)
		T.ring(feetOf(ctx), color, 24, 0.7, 6)
		T.shake(ctx, 0.6)
		if ctx.Local then
			fx():Flash(lighter(color), 0.35)
		end
		aura(ctx, ctx.Def.Duration)
	end,
	Result = function(ctx, info)
		if not info.Wave then
			return
		end
		-- a crescent of the element that flies down the swing's line
		local d, color = ctx.Def, ctx.Def.Color
		local length = info.Length or d.WaveLength
		local start = ctx.Origin + Vector3.new(0, 0.4, 0)
		local wave = T.part(Vector3.new(d.WaveWidth * 1.4, 1.2, 2.2), CFrame.lookAt(start, start + ctx.Dir), color)
		wave.Transparency = 0.15
		local inner = T.part(Vector3.new(d.WaveWidth * 0.8, 0.6, 1.2), wave.CFrame, WHITE)
		T.animate(0.32, function(k)
			local cf = CFrame.lookAt(start + ctx.Dir * length * k, start + ctx.Dir * (length * k + 1))
			wave.CFrame = cf
			inner.CFrame = cf * CFrame.new(0, 0, -0.4)
			wave.Transparency = 0.15 + k * 0.7
			inner.Transparency = k
		end, function()
			wave:Destroy()
			inner:Destroy()
		end)
		Debris:AddItem(wave, 1)
		Debris:AddItem(inner, 1)
	end,
}

function UltimateEffects.Register(E, tools)
	T = tools
	for id, def in pairs(Mastery.ById) do
		E[id] = looks[def.Kind]
	end
end

return UltimateEffects
