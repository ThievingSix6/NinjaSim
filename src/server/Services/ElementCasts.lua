--[[
	ElementCasts: the server side of the elemental tier skills (Config/ElementSkills).
	Not a service: SkillService requires it and calls Register(CAST, kit), which adds
	one cast function per skill to SkillService's table, sharing its helpers (target
	shapes, strike, later, iframes). Every cast returns the info table its client
	effect needs (centres, lengths, impact points).

	ctx (from SkillService): Player, Character, Def, Level, Power, Origin, Dir,
	plus Proc = true and Target = the point when cast through SkillService:CastAt
	(no movement then, and point skills land on Target).

	Extra enemy effects, applied here on top of EnemyService:Damage:
	  slow      Humanoid.WalkSpeed x factor for a few seconds, then restored
	  knock-up  upward launch; pull = velocity toward a centre
	  float     a VectorForce cancels gravity for a moment (Zero Gravity)
	  blind     regular enemies lose their target (Solar Flare, Eclipse)
	Bosses and static enemies take the damage but ignore the movement effects.
]]

local Debris = game:GetService("Debris")

local ElementCasts = {}

local K -- SkillService helpers (see Register)

local function svc()
	return K.Services()
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function ground(p: Vector3): Vector3
	return Vector3.new(p.X, svc().ZoneService:GroundHeight(p), p.Z)
end

local function movable(enemy): boolean
	return not enemy.Dead and not enemy.IsBoss and not enemy.Def.Static and enemy.Humanoid ~= nil and enemy.Model.Parent ~= nil
end

local function living(list)
	local out = {}
	for _, enemy in ipairs(list) do
		if not enemy.Dead and enemy.Model.Parent then
			table.insert(out, enemy)
		end
	end
	return out
end

-- Walk speed x factor for `seconds`; overlapping slows keep the strongest and longest.
local function slow(enemy, factor: number, seconds: number)
	if not movable(enemy) then
		return
	end
	local humanoid = enemy.Humanoid :: Humanoid
	if not enemy.SkillSlowBase then
		enemy.SkillSlowBase = humanoid.WalkSpeed
	end
	local now = os.clock()
	local active = (enemy.SkillSlowUntil or 0) > now
	enemy.SkillSlowFactor = math.min(if active then (enemy.SkillSlowFactor or 1) else 1, factor)
	enemy.SkillSlowUntil = math.max(enemy.SkillSlowUntil or 0, now + seconds)
	humanoid.WalkSpeed = enemy.SkillSlowBase * enemy.SkillSlowFactor
	task.delay(seconds + 0.05, function()
		if enemy.SkillSlowBase and os.clock() >= (enemy.SkillSlowUntil or 0) then
			if not enemy.Dead and enemy.Humanoid then
				enemy.Humanoid.WalkSpeed = enemy.SkillSlowBase
			end
			enemy.SkillSlowBase = nil
			enemy.SkillSlowFactor = nil
		end
	end)
end

local function knockUp(enemy, vy: number, push: Vector3?)
	if movable(enemy) then
		enemy.Root.AssemblyLinearVelocity = (push or Vector3.zero) + Vector3.new(0, vy, 0)
	end
end

-- Velocity toward `center`, strong enough to arrive in about `time` seconds.
local function pull(enemy, center: Vector3, time: number)
	if not movable(enemy) then
		return
	end
	local to = flat(center - enemy.Root.Position)
	if to.Magnitude > 2.5 then
		local speed = math.min(to.Magnitude / time, 70)
		enemy.Root.AssemblyLinearVelocity = to.Unit * speed + Vector3.new(0, 6, 0)
	end
end

local function blind(enemy)
	if not enemy.IsBoss and not enemy.Dead then
		enemy.Target = nil
	end
end

-- Cancels gravity on an enemy for `seconds` (it drifts up with `rise` studs/s).
local function float(enemy, seconds: number, rise: number)
	if not movable(enemy) then
		return
	end
	local root = enemy.Root :: BasePart
	local attachment = Instance.new("Attachment")
	attachment.Name = "ZeroGravity"
	attachment.Parent = root
	local force = Instance.new("VectorForce")
	force.Name = "ZeroGravity"
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Force = Vector3.new(0, root.AssemblyMass * workspace.Gravity, 0)
	force.Parent = root
	root.AssemblyLinearVelocity = Vector3.new(0, rise, 0)
	Debris:AddItem(force, seconds)
	Debris:AddItem(attachment, seconds)
end

local function heal(player: Player, fraction: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * fraction)
	end
end

local function points(list)
	local out = {}
	for _, enemy in ipairs(list) do
		table.insert(out, { Uid = enemy.Uid, Position = enemy.Root.Position, Height = enemy.Height })
	end
	return out
end

-- Where a placed skill lands: the proc point, else the nearest enemy roughly in
-- front within `range`, else a spot ahead.
local function placed(ctx, range: number): Vector3
	if ctx.Target then
		return ground(ctx.Target)
	end
	local center = ctx.Origin + ctx.Dir * math.min(16, range)
	local front = K.Cone(ctx.Player, ctx.Origin, ctx.Dir, range, 0.3, 1)[1]
	if front then
		center = front.Root.Position
	end
	return ground(center)
end

-- The centre of a self-centred skill: the caster (or the proc point).
local function selfCenter(ctx): Vector3
	return if ctx.Target then ground(ctx.Target) else ctx.Origin
end

local function fieldTime(def, level: number): number
	return (def.Field or 0) + 0.5 * (math.clamp(level, 1, 5) - 1)
end

-- Runs fn(i) every `tick` seconds for `duration` (starting after `lead`), while the caster is here.
local function every(ctx, lead: number, tick: number, duration: number, fn: (number) -> ())
	local count = math.max(1, math.floor(duration / tick + 0.001))
	for i = 1, count do
		K.Later(lead + (i - 1) * tick, function()
			if ctx.Player.Parent then
				fn(i)
			end
		end)
	end
	return count
end

local function strike(ctx, enemies, mult: number, from: Vector3, knockback: number?, stun: number?, tag: any?)
	return K.Strike(ctx, living(enemies), mult, { From = from, Knockback = knockback or 0, Stun = stun or 0, Tag = tag })
end

local function dots(ctx, enemies, def, from: Vector3)
	for i = 1, def.DotTicks or 0 do
		K.Later(0.5 * i, function()
			if ctx.Player.Parent then
				strike(ctx, enemies, def.Dot, from, 0, 0, def.DotTag)
			end
		end)
	end
end

-- ===== the casts =====
local C = {}

-- Earth: a wave of spikes along a line, launching what it passes.
function C.stone_spikes(ctx)
	local d = ctx.Def
	local origin = if ctx.Proc then ctx.Origin - ctx.Dir * 6 else ctx.Origin
	local targets = K.Line(ctx.Player, origin, ctx.Dir, d.Length, d.Width, d.MaxTargets)
	local segments = 6
	local groups = {}
	for _, enemy in ipairs(targets) do
		local along = flat(enemy.Root.Position - origin):Dot(ctx.Dir)
		local g = math.clamp(math.floor(along / d.Length * segments) + 1, 1, segments)
		groups[g] = groups[g] or {}
		table.insert(groups[g], enemy)
	end
	for g = 1, segments do
		local group = groups[g]
		if group then
			K.Later(0.14 + (g - 1) * 0.06, function()
				strike(ctx, group, d.Damage, origin, 0, d.Stun)
				for _, enemy in ipairs(group) do
					knockUp(enemy, d.KnockUp, ctx.Dir * 6)
				end
			end)
		end
	end
	return { Length = d.Length, Origin = origin }
end

-- Earth: a wall rises ahead and shoves the enemies in front of it back, pinned.
function C.earth_wall(ctx)
	local d = ctx.Def
	local center = if ctx.Target then ground(ctx.Target) else ctx.Origin + ctx.Dir * d.Range
	local from = center - ctx.Dir * d.Range
	K.Later(0.15, function()
		local targets = K.Line(ctx.Player, from + ctx.Dir * 2, ctx.Dir, d.Range + d.Depth, d.Width, d.MaxTargets)
		strike(ctx, targets, d.Damage, from, d.Knockback, d.Stun + 0.2 * (ctx.Level - 1))
	end)
	return { Center = center, Duration = d.Field }
end

-- Wind: a tornado travels forward, cutting four times and dragging enemies along.
function C.razor_gale(ctx)
	local d = ctx.Def
	local travel = 1.2
	local start = ctx.Origin + ctx.Dir * 3
	for i = 1, d.Hits do
		local t = 0.15 + (i - 1) * 0.3
		K.Later(t, function()
			local pos = start + ctx.Dir * ((d.Length - 3) * math.min(1, t / travel))
			strike(ctx, K.Circle(ctx.Player, pos, d.Radius, d.MaxTargets), d.Damage, pos - ctx.Dir * 6, d.Knockback, d.Stun)
		end)
	end
	return { Length = d.Length, Time = travel }
end

-- Wind/Nature: vines root everything in a patch under the nearest crowd.
function C.vine_snare(ctx)
	local d = ctx.Def
	local center = placed(ctx, d.Range)
	K.Later(0.3, function()
		local targets = K.Circle(ctx.Player, center, d.Radius, d.MaxTargets)
		strike(ctx, targets, d.Damage, center, 0, d.Root + 0.25 * (ctx.Level - 1), "Root")
		dots(ctx, targets, d, center)
	end)
	return { Center = center }
end

-- Ice: a frost ring freezes everything around you.
function C.frost_nova(ctx)
	local d = ctx.Def
	local center = selfCenter(ctx)
	K.Later(0.22, function()
		strike(ctx, K.Circle(ctx.Player, center, d.Radius, d.MaxTargets), d.Damage, center, 0, d.Freeze + 0.2 * (ctx.Level - 1), "Freeze")
	end)
	return { Center = center }
end

-- Ice: a cone of freezing wind that slows.
function C.blizzard_gust(ctx)
	local d = ctx.Def
	local targets = K.Cone(ctx.Player, ctx.Origin, ctx.Dir, d.Range, d.Arc, d.MaxTargets)
	K.Later(0.2, function()
		local hit = living(targets)
		strike(ctx, hit, d.Damage, ctx.Origin, d.Knockback, d.Stun, "Chill")
		for _, enemy in ipairs(hit) do
			slow(enemy, d.Slow, d.SlowTime + 0.5 * (ctx.Level - 1))
		end
	end)
	return {}
end

-- Lightning: bolts strike random enemies around you, one after another.
function C.arcane_storm(ctx)
	local d = ctx.Def
	local center = selfCenter(ctx)
	local bolts = d.Bolts + (ctx.Level - 1)
	for i = 1, bolts do
		K.Later(0.2 + (i - 1) * 0.14, function()
			if not ctx.Player.Parent then
				return
			end
			local near = K.Circle(ctx.Player, center, d.Radius, 40)
			local victim = near[math.random(1, math.max(1, #near))]
			if victim then
				local at = victim.Root.Position
				strike(ctx, K.Circle(ctx.Player, at, d.BoltRadius, d.MaxTargets), d.Damage, at, d.Knockback, d.Stun, { Bolt = at })
			end
		end)
	end
	return { Center = center, Bolts = bolts }
end

-- Lightning: blink forward; both ends of the jump explode.
function C.arcane_blink(ctx)
	local d = ctx.Def
	local length = if ctx.Proc then 0 else K.ClearDistance(ctx.Origin, ctx.Dir, d.Length)
	if not ctx.Proc then
		-- blink into the enemy ahead (just past it), so the landing blast lands on the crowd
		local front = K.Cone(ctx.Player, ctx.Origin, ctx.Dir, d.Length, 0.6, 1)[1]
		if front then
			length = math.min(length, flat(front.Root.Position - ctx.Origin).Magnitude + 3)
		end
		svc().ZoneService:MarkTeleported(ctx.Player)
		K.Iframes(ctx.Player, 0.5)
	end
	local land = ctx.Origin + ctx.Dir * length
	K.Later(0.12, function()
		strike(ctx, K.Circle(ctx.Player, land, d.Radius, d.MaxTargets), d.Damage, land, d.Knockback, d.Stun)
	end)
	K.Later(0.6, function()
		strike(ctx, K.Circle(ctx.Player, ctx.Origin, d.Radius, d.MaxTargets), d.Damage, ctx.Origin, d.Knockback, d.Stun)
	end)
	return { Length = length }
end

-- Fire: dive onto the enemy ahead and explode, burning the crowd.
function C.phoenix_dive(ctx)
	local d = ctx.Def
	local length = 0
	if not ctx.Proc then
		length = K.ClearDistance(ctx.Origin, ctx.Dir, d.Length)
		local front = K.Cone(ctx.Player, ctx.Origin, ctx.Dir, d.Length, 0.6, 1)[1]
		if front then
			length = math.min(length, math.max(0, flat(front.Root.Position - ctx.Origin).Magnitude - 3))
		end
		svc().ZoneService:MarkTeleported(ctx.Player)
		K.Iframes(ctx.Player, 0.8)
	end
	local land = if ctx.Target then ground(ctx.Target) else ctx.Origin + ctx.Dir * length
	K.Later(0.42, function()
		local targets = K.Circle(ctx.Player, land, d.Radius, d.MaxTargets)
		strike(ctx, targets, d.Damage, land, d.Knockback, d.Stun)
		dots(ctx, targets, d, land)
	end)
	return { Length = length, Center = land }
end

-- Fire: a burning ring that slows and scorches whatever is inside.
function C.ring_of_fire(ctx)
	local d = ctx.Def
	local center = selfCenter(ctx)
	local duration = fieldTime(d, ctx.Level)
	every(ctx, 0.3, d.Tick, duration, function()
		local inside = K.Circle(ctx.Player, center, d.Radius, d.MaxTargets)
		strike(ctx, inside, d.Damage, center, 0, 0, d.DotTag)
		for _, enemy in ipairs(inside) do
			slow(enemy, d.Slow, d.SlowTime)
		end
	end)
	return { Center = center, Duration = duration }
end

-- Storm: a thundercloud over the crowd strikes again and again.
function C.storm_cloud(ctx)
	local d = ctx.Def
	local center = placed(ctx, d.Range)
	every(ctx, 0.5, d.Tick, d.Hits * d.Tick, function(i)
		strike(ctx, K.Circle(ctx.Player, center, d.Radius, d.MaxTargets), d.Damage, center, d.Knockback, d.Stun, { Strike = i })
	end)
	return { Center = center, Duration = d.Hits * d.Tick + 0.5 }
end

-- Storm: a smoke cyclone pulls enemies in, then throws them into the air.
function C.smoke_cyclone(ctx)
	local d = ctx.Def
	local center = selfCenter(ctx)
	local targets = K.Circle(ctx.Player, center, d.Radius, d.MaxTargets)
	K.Later(0.1, function()
		for _, enemy in ipairs(living(targets)) do
			if enemy.Humanoid and not enemy.IsBoss then
				enemy.StunUntil = math.max(enemy.StunUntil or 0, os.clock() + 0.7)
			end
			pull(enemy, center, 0.45)
		end
	end)
	K.Later(0.65, function()
		local hit = living(targets)
		strike(ctx, hit, d.Damage, center, 0, d.Stun)
		for _, enemy in ipairs(hit) do
			knockUp(enemy, d.KnockUp)
		end
	end)
	return { Center = center }
end

-- Light: a pillar of holy light crashes down on the crowd.
function C.holy_judgment(ctx)
	local d = ctx.Def
	local center = placed(ctx, d.Range)
	K.Later(0.6, function()
		strike(ctx, K.Circle(ctx.Player, center, d.Radius, d.MaxTargets), d.Damage, center, d.Knockback, d.Stun)
	end)
	return { Center = center }
end

-- Light: a blessed circle heals you while you stand in it and sears enemies.
function C.sanctuary(ctx)
	local d = ctx.Def
	local center = selfCenter(ctx)
	local duration = fieldTime(d, ctx.Level)
	local healPerTick = d.Heal * ctx.Power
	every(ctx, 0.2, d.Tick, duration, function()
		local root = K.RootOf(ctx.Player)
		if root and flat(root.Position - center).Magnitude <= d.Radius + 2 then
			heal(ctx.Player, healPerTick)
		end
		strike(ctx, K.Circle(ctx.Player, center, d.Radius, d.MaxTargets), d.Damage, center, 0, 0, d.DotTag)
	end)
	return { Center = center, Duration = duration }
end

-- Sun: a tiny sun over your head bursts, blinding and scorching a huge circle.
function C.solar_flare(ctx)
	local d = ctx.Def
	local center = selfCenter(ctx)
	K.Later(0.7, function()
		local targets = K.Circle(ctx.Player, center, d.Radius, d.MaxTargets)
		for _, enemy in ipairs(targets) do
			blind(enemy)
		end
		strike(ctx, targets, d.Damage, center, d.Knockback, d.Stun + 0.2 * (ctx.Level - 1))
	end)
	return { Center = center }
end

-- Sun: a beam straight ahead that hits five times.
function C.sunbeam(ctx)
	local d = ctx.Def
	local length = d.Length
	for i = 1, d.Hits do
		K.Later(0.25 + (i - 1) * d.Tick, function()
			strike(ctx, K.Line(ctx.Player, ctx.Origin, ctx.Dir, length, d.Width, d.MaxTargets), d.Damage, ctx.Origin, d.Knockback, d.Stun)
		end)
	end
	return { Length = length, Duration = 0.25 + d.Hits * d.Tick }
end

-- Blood: a flying crescent splits the crowd and makes it bleed.
function C.crimson_crescent(ctx)
	local d = ctx.Def
	local targets = K.Line(ctx.Player, ctx.Origin, ctx.Dir, d.Length, d.Width, d.MaxTargets)
	local segments = 4
	local groups = {}
	for _, enemy in ipairs(targets) do
		local along = flat(enemy.Root.Position - ctx.Origin):Dot(ctx.Dir)
		local g = math.clamp(math.floor(along / d.Length * segments) + 1, 1, segments)
		groups[g] = groups[g] or {}
		table.insert(groups[g], enemy)
	end
	for g = 1, segments do
		local group = groups[g]
		if group then
			K.Later(0.2 + (g - 1) * 0.1, function()
				strike(ctx, group, d.Damage, ctx.Origin, d.Knockback, d.Stun)
				dots(ctx, group, d, ctx.Origin)
			end)
		end
	end
	return { Length = d.Length }
end

-- Blood: tethers drain the enemies around you and heal you.
function C.life_drain(ctx)
	local d = ctx.Def
	local center = selfCenter(ctx)
	local targets = K.Circle(ctx.Player, center, d.Radius, d.MaxTargets)
	for i = 1, d.Hits do
		K.Later(0.3 + (i - 1) * d.Tick, function()
			if not ctx.Player.Parent then
				return
			end
			local hits = strike(ctx, targets, d.Damage, center, 0, d.Stun, d.DotTag)
			if #hits > 0 then
				heal(ctx.Player, math.min(0.08, d.Heal * #hits * ctx.Power))
			end
		end)
	end
	return { Targets = points(targets), Duration = 0.3 + d.Hits * d.Tick }
end

-- Darkness: hands rise under every enemy around you, hold them, then crush.
function C.umbral_grasp(ctx)
	local d = ctx.Def
	local center = selfCenter(ctx)
	local targets = K.Circle(ctx.Player, center, d.Radius, d.MaxTargets)
	K.Later(0.35, function()
		strike(ctx, targets, d.Damage, center, 0, d.Stun + 0.2 * (ctx.Level - 1), "Grab")
	end)
	K.Later(1.35, function()
		strike(ctx, targets, d.FinalDamage, center, 0.8, 0.4, "Crush")
	end)
	return { Targets = points(targets) }
end

-- Darkness: a dome of night blinds, slows and withers the enemies inside.
function C.eclipse(ctx)
	local d = ctx.Def
	local center = selfCenter(ctx)
	local duration = fieldTime(d, ctx.Level)
	every(ctx, 0.3, d.Tick, duration, function()
		local inside = K.Circle(ctx.Player, center, d.Radius, d.MaxTargets)
		for _, enemy in ipairs(inside) do
			blind(enemy)
			slow(enemy, d.Slow, d.SlowTime)
		end
		strike(ctx, inside, d.Damage, center, 0, 0, d.DotTag)
	end)
	return { Center = center, Duration = duration }
end

-- Cosmic: a shower of stars lands on the crowd, one blast each.
function C.starfall(ctx)
	local d = ctx.Def
	local center = placed(ctx, d.Range)
	local count = d.Meteors + (ctx.Level - 1)
	local near = K.Circle(ctx.Player, center, d.Radius, count)
	local impacts = {}
	for i = 1, count do
		local spot
		if near[i] and i % 3 ~= 0 then
			spot = near[i].Root.Position
		else
			local a = math.random() * math.pi * 2
			local r = math.sqrt(math.random()) * d.Radius
			spot = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		end
		spot = ground(spot)
		impacts[i] = spot
		K.Later(0.55 + (i - 1) * 0.18, function()
			if ctx.Player.Parent then
				strike(ctx, K.Circle(ctx.Player, spot, d.MeteorRadius, d.MaxTargets), d.Damage, spot, d.Knockback, d.Stun, { Meteor = i })
			end
		end)
	end
	return { Center = center, Impacts = impacts, Lead = 0.55, Step = 0.18 }
end

-- Cosmic: link a chain of enemies into a constellation, then burst it.
function C.constellation(ctx)
	local d = ctx.Def
	local first
	if ctx.Target then
		first = K.Circle(ctx.Player, ctx.Target, d.ChainRange, 1)[1]
	else
		first = K.Cone(ctx.Player, ctx.Origin, ctx.Dir, d.Range, d.Arc, 1)[1]
	end
	local chain, used = {}, {}
	local current = first
	local maxChain = math.min(d.MaxTargets, d.Chain + ctx.Level - 1)
	while current and #chain < maxChain do
		used[current] = true
		table.insert(chain, current)
		local nextEnemy = nil
		for _, entry in ipairs(svc().EnemyService:InRange(svc().ZoneService:GetZone(ctx.Player).Id, current.Root.Position, d.ChainRange)) do
			if not used[entry.Enemy] then
				nextEnemy = entry.Enemy
				break
			end
		end
		current = nextEnemy
	end
	-- held in place while the stars are drawn, then the burst
	for _, enemy in ipairs(chain) do
		if enemy.Humanoid and not enemy.IsBoss then
			enemy.StunUntil = math.max(enemy.StunUntil or 0, os.clock() + 1)
		end
	end
	K.Later(0.9, function()
		local from = if chain[1] then chain[1].Root.Position else ctx.Origin
		strike(ctx, chain, d.Damage, from, d.Knockback, d.Stun)
	end)
	return { Chain = points(chain), Delay = 0.9 }
end

-- Gravity: a black hole drags the crowd in, grinds it, then collapses in a blast.
function C.black_hole(ctx)
	local d = ctx.Def
	local center = placed(ctx, d.Range)
	every(ctx, 0.3, d.Tick, d.Field, function()
		local inside = K.Circle(ctx.Player, center, d.Radius, d.MaxTargets)
		strike(ctx, inside, d.Damage, center, 0, d.Stun, "Gravity")
		for _, enemy in ipairs(inside) do
			pull(enemy, center, 0.35)
		end
	end)
	K.Later(0.3 + d.Field, function()
		if ctx.Player.Parent then
			strike(ctx, K.Circle(ctx.Player, center, d.Radius * 0.75, d.MaxTargets), d.FinalDamage, center, d.Knockback, 0.6, "Collapse")
		end
	end)
	return { Center = center, Duration = d.Field + 0.3 }
end

-- Gravity: enemies float up helplessly, then slam back down.
function C.zero_gravity(ctx)
	local d = ctx.Def
	local center = selfCenter(ctx)
	local targets = K.Circle(ctx.Player, center, d.Radius, d.MaxTargets)
	local hang = 1.8 + 0.1 * (ctx.Level - 1)
	K.Later(0.2, function()
		local hit = living(targets)
		strike(ctx, hit, d.Damage, center, 0, d.Stun + 0.1 * (ctx.Level - 1), "Lift")
		for _, enemy in ipairs(hit) do
			float(enemy, hang, 7 + math.random() * 5)
		end
	end)
	K.Later(0.2 + hang, function()
		local hit = living(targets)
		for _, enemy in ipairs(hit) do
			knockUp(enemy, -90)
		end
		K.Later(0.25, function()
			strike(ctx, hit, d.FinalDamage, center, 0.6, 0.5, "Slam")
		end)
	end)
	return { Center = center, Hang = hang, Targets = points(targets) }
end

ElementCasts.Casts = C

-- kit: { Strike, Circle, Cone, Line, Later, Iframes, RootOf, ClearDistance, Services }
function ElementCasts.Register(cast: { [string]: any }, kit)
	K = kit
	for id, fn in pairs(C) do
		if cast[id] == nil then
			cast[id] = fn
		end
	end
end

return ElementCasts
