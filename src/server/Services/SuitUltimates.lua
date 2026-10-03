--[[
	SuitUltimates: the server side of every suit's own ultimates except the Brown
	Ninja's (Config/Mastery.Sets). Not a service: SkillService requires it, calls
	Init(kit, tools) and registers Casts / Swings with UltimateCasts.

	Every cast gets ctx (Player, Character, Def, Power = the suit's Scale, Origin, Dir),
	finds its own targets with the kit shapes, deals damage through the kit's Strike
	(x your hit damage x Power) and returns the info its look needs (paths, impact
	points, timings: Controllers/SuitUltimateEffects).

	Some hits carry a table tag ({ K = "Arc", From = position } and friends) so the
	client can draw that hit from the right place (bolts from a sentinel, chain arcs).
	Movement casts mark the player as teleported (the zone check allows the jump)
	and the client moves its own character along the returned path.
]]

local SuitUltimates = {}

local K -- SkillService's kit: Strike, Circle, Cone, Line, Later, Iframes, RootOf, ClearDistance, Services
local T -- ElementCasts.Tools: slow, knockUp, pull, blind, float, heal, points, ground, movable, living

local function svc()
	return K.Services()
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function rotY(v: Vector3, degrees: number): Vector3
	local a = math.rad(degrees)
	local c, s = math.cos(a), math.sin(a)
	return Vector3.new(v.X * c - v.Z * s, 0, v.X * s + v.Z * c)
end

local function alive(player: Player, character: Model?): boolean
	return player.Parent ~= nil and player.Character == character and K.RootOf(player) ~= nil
end

-- The caster's live position (they move), else where the cast started.
local function here(ctx): Vector3
	local root = K.RootOf(ctx.Player)
	return if root then root.Position else ctx.Origin
end

local function moved(ctx)
	svc().ZoneService:MarkTeleported(ctx.Player)
end

local function hit(ctx, enemies, mult: number, from: Vector3?, knockback: number?, stun: number?, tag: any?)
	return K.Strike(ctx, T.living(enemies), mult, { From = from, Knockback = knockback or 0, Stun = stun or 0, Tag = tag })
end

-- Enemies within `range` of `center`, nearest first.
local function nearest(ctx, center: Vector3, range: number, max: number)
	local list = K.Circle(ctx.Player, center, range, 200)
	table.sort(list, function(a, b)
		return flat(a.Root.Position - center).Magnitude < flat(b.Root.Position - center).Magnitude
	end)
	local out = {}
	for i = 1, math.min(max, #list) do
		out[i] = list[i]
	end
	return out
end

-- Where a leap comes down: on the nearest enemy roughly ahead within `range`, else
-- `range` studs ahead (short of walls).
local function landingSpot(ctx, range: number): Vector3
	local best, bestDist = nil, math.huge
	for _, enemy in ipairs(K.Cone(ctx.Player, ctx.Origin, ctx.Dir, range, 0.5, 60)) do
		local dist = flat(enemy.Root.Position - ctx.Origin).Magnitude
		if dist < bestDist then
			best, bestDist = enemy, dist
		end
	end
	local dir = if best and bestDist > 1 then flat(best.Root.Position - ctx.Origin).Unit else ctx.Dir
	local distance = if best then bestDist else range
	return ctx.Origin + dir * K.ClearDistance(ctx.Origin, dir, distance)
end

-- Runs fn(i) every `tick` seconds, `count` times, after `lead`, while the caster is here.
local function every(ctx, lead: number, tick: number, count: number, fn: (number) -> ())
	for i = 1, count do
		K.Later(lead + (i - 1) * tick, function()
			if ctx.Player.Parent then
				fn(i)
			end
		end)
	end
end

local S = {} -- casts by Kind
local W = {} -- awakened swings by Kind

-- ===================== Green: Wind =====================
-- Three zig-zag dashes, each cutting what it crosses.
function S.GaleZigzag(ctx)
	local d = ctx.Def
	local points = { ctx.Origin }
	local pos = ctx.Origin
	for i = 1, d.Dashes do
		local dir = rotY(ctx.Dir, if i % 2 == 1 then d.Angle else -d.Angle)
		local length = K.ClearDistance(pos, dir, d.Leg)
		local targets = K.Line(ctx.Player, pos, dir, length, d.Width, d.MaxTargets)
		local from = pos
		K.Later(0.13 * i, function()
			hit(ctx, targets, d.Damage, from, 1.2, 0.5)
		end)
		pos += dir * length
		table.insert(points, pos)
	end
	moved(ctx)
	K.Iframes(ctx.Player, d.Iframes)
	return { Points = points, Leg = 0.13 }
end

-- A crescent of wind that flies out and back.
function S.VacuumBoomerang(ctx)
	local d = ctx.Def
	local length = d.Length
	local seg = length / d.Steps
	local out, back = {}, {}
	for i = 1, d.Steps do
		local function step(set, index: number, delay: number)
			K.Later(delay, function()
				local from = ctx.Origin + ctx.Dir * seg * (index - 1)
				local fresh = {}
				for _, enemy in ipairs(K.Line(ctx.Player, from, ctx.Dir, seg, d.Width, d.MaxTargets)) do
					if not set[enemy] then
						set[enemy] = true
						table.insert(fresh, enemy)
					end
				end
				if #fresh > 0 then
					hit(ctx, fresh, d.Damage, from, 0.6, 0.3)
				end
			end)
		end
		step(out, i, d.Time * i / d.Steps)
		step(back, d.Steps - i + 1, d.Time + d.Time * i / d.Steps)
	end
	return { Length = length, Time = d.Time }
end

-- Drag everything into a spinning wall around you, then blow it away.
function S.Typhoon(ctx)
	local d = ctx.Def
	every(ctx, 0.2, d.Tick, d.Ticks, function()
		local center = here(ctx)
		local list = K.Circle(ctx.Player, center, d.Radius, d.MaxTargets)
		for _, enemy in ipairs(list) do
			if flat(enemy.Root.Position - center).Magnitude > 8 then
				T.pull(enemy, center, 0.45)
			end
		end
		hit(ctx, list, d.Damage, center, 0, 0.35)
	end)
	K.Later(0.2 + d.Tick * d.Ticks, function()
		local center = here(ctx)
		local list = K.Circle(ctx.Player, center, d.Radius * 0.6, d.MaxTargets)
		hit(ctx, list, d.BlastDamage, center, 3, 0.8)
		for _, enemy in ipairs(list) do
			T.knockUp(enemy, 45, flat(enemy.Root.Position - center).Unit * 40)
		end
	end)
	return { Radius = d.Radius, Ticks = d.Ticks, Tick = d.Tick }
end

-- Leap into the sky and loose homing blades at the nearest enemies.
function S.SkyDancer(ctx)
	local d = ctx.Def
	K.Iframes(ctx.Player, d.Iframes)
	local targets = nearest(ctx, ctx.Origin, d.Range, d.Blades)
	for i, enemy in ipairs(targets) do
		K.Later(d.Hover * 0.45 + i * 0.07, function()
			hit(ctx, { enemy }, d.Damage, ctx.Origin + Vector3.new(0, 20, 0), 0.8, 0.5)
		end)
	end
	return { Targets = T.points(targets), Hover = d.Hover }
end

-- ===================== Blue: Ice =====================
-- Skate a road of ice that freezes, then keeps slowing.
function S.GlacialSkate(ctx)
	local d = ctx.Def
	local length = K.ClearDistance(ctx.Origin, ctx.Dir, d.Length)
	local targets = K.Line(ctx.Player, ctx.Origin, ctx.Dir, length, d.Width, d.MaxTargets)
	moved(ctx)
	K.Iframes(ctx.Player, d.Iframes)
	K.Later(0.3, function()
		hit(ctx, targets, d.Damage, ctx.Origin, 0.3, d.Freeze, "Freeze")
	end)
	every(ctx, 0.5, 0.5, math.floor(d.Trail / 0.5), function()
		for _, enemy in ipairs(K.Line(ctx.Player, ctx.Origin, ctx.Dir, length, d.Width, d.MaxTargets)) do
			T.slow(enemy, d.Slow, 0.8)
		end
	end)
	return { Length = length, Trail = d.Trail }
end

-- Five ice lances in a fan, one after another.
function S.FrostVolley(ctx)
	local d = ctx.Def
	local angles = {}
	for i = 1, d.Spears do
		local a = math.deg(-d.Spread / 2 + d.Spread * (i - 1) / math.max(1, d.Spears - 1))
		-- middle out: 0, +, -, ++, --
		angles[i] = a
	end
	table.sort(angles, function(a, b)
		return math.abs(a) < math.abs(b)
	end)
	for i, a in ipairs(angles) do
		K.Later(0.18 + (i - 1) * d.Interval, function()
			local from = here(ctx)
			local dir = rotY(ctx.Dir, a)
			hit(ctx, K.Line(ctx.Player, from, dir, d.Length, d.Width, d.MaxTargets), d.Damage, from, 0.4, d.Freeze, "Freeze")
		end)
	end
	return { Angles = angles, Interval = d.Interval }
end

-- Freeze everything in a dome, then shatter it.
function S.PermafrostDome(ctx)
	local d = ctx.Def
	local center = ctx.Origin
	local frozen = {}
	K.Later(0.3, function()
		frozen = K.Circle(ctx.Player, center, d.Radius, d.MaxTargets)
		hit(ctx, frozen, d.Damage, center, 0, d.Freeze + 0.3, "Freeze")
	end)
	K.Later(0.3 + d.Freeze, function()
		hit(ctx, frozen, d.ShatterDamage, center, 1.6, 0.4)
	end)
	return { Center = center, Radius = d.Radius, Freeze = d.Freeze }
end

-- An ice sentinel that fires frost bolts at the nearest enemies.
function S.GlacialSentinel(ctx)
	local d = ctx.Def
	local spot = ctx.Origin + ctx.Dir * 6
	spot = T.ground(spot)
	local eye = spot + Vector3.new(0, 9, 0)
	every(ctx, 0.6, d.Interval, math.floor(d.Duration / d.Interval), function()
		local targets = nearest(ctx, spot, d.Range, 1)
		if targets[1] then
			hit(ctx, targets, d.Damage, eye, 0.3, d.Freeze, { K = "Bolt", From = eye })
		end
	end)
	return { Spot = spot, Duration = d.Duration }
end

-- ===================== Purple: Arcane Lightning =====================
-- Blink three times, a thunderclap at every landing.
function S.LightningStep(ctx)
	local d = ctx.Def
	local points = { ctx.Origin }
	local pos = ctx.Origin
	for i = 1, d.Blinks do
		pos += ctx.Dir * K.ClearDistance(pos, ctx.Dir, d.Leg)
		table.insert(points, pos)
		local at = pos
		K.Later(0.12 + (i - 1) * d.Interval, function()
			hit(ctx, K.Circle(ctx.Player, at, d.Radius, d.MaxTargets), d.Damage, at, 1, 0.6, { K = "Strike", At = at })
		end)
	end
	moved(ctx)
	K.Iframes(ctx.Player, d.Iframes)
	return { Points = points, Interval = d.Interval }
end

-- A railgun shot that arcs on from enemy to enemy.
function S.RailgunArc(ctx)
	local d = ctx.Def
	local first = K.Cone(ctx.Player, ctx.Origin, ctx.Dir, d.Range, 0.6, 1)[1]
	local chain = {}
	if first then
		local seen = { [first] = true }
		chain[1] = first
		while #chain < d.Chain do
			local last = chain[#chain]
			local nextOne = nil
			for _, enemy in ipairs(nearest(ctx, last.Root.Position, d.Hop, 12)) do
				if not seen[enemy] then
					nextOne = enemy
					break
				end
			end
			if not nextOne then
				break
			end
			seen[nextOne] = true
			table.insert(chain, nextOne)
		end
	end
	local from = ctx.Origin + Vector3.new(0, 1, 0)
	for i, enemy in ipairs(chain) do
		local prev = from
		if i > 1 then
			prev = chain[i - 1].Root.Position
		end
		K.Later(d.Windup + (i - 1) * 0.05, function()
			hit(ctx, { enemy }, d.Damage, prev, 0.8, 0.5, { K = "Arc", From = prev })
		end)
	end
	return { Chain = T.points(chain), Windup = d.Windup, Range = d.Range }
end

-- Eight lightning pillars; arcs between them shock everything inside.
function S.ThunderCage(ctx)
	local d = ctx.Def
	local center = ctx.Origin
	local pillars = {}
	for i = 1, d.Pillars do
		local a = (i - 1) / d.Pillars * math.pi * 2
		pillars[i] = T.ground(center + Vector3.new(math.cos(a) * d.Radius, 0, math.sin(a) * d.Radius))
	end
	every(ctx, 0.35, d.Tick, d.Ticks, function(i)
		local list = K.Circle(ctx.Player, center, d.Radius, d.MaxTargets)
		hit(ctx, list, d.Damage, center, 0, if i == 1 then d.Stun else 0.4)
	end)
	return { Center = center, Pillars = pillars, Ticks = d.Ticks, Tick = d.Tick }
end

-- Overload: harder, faster swings that each call down a bolt.
function S.StormOverload(ctx)
	local d = ctx.Def
	svc().StatService:SetModifier(ctx.Player, "mastery_overload", { Damage = d.DamageMult, AttackInterval = 1 / d.AttackSpeed }, d.Duration)
	SuitUltimates.Awaken(ctx.Player, d, d.Duration)
	return { Duration = d.Duration }
end
function W.StormOverload(ctx)
	local d = ctx.Def
	local target = K.Cone(ctx.Player, ctx.Origin, ctx.Dir, d.Reach, 0.4, 1)[1]
	if not target then
		return {}
	end
	local at = target.Root.Position
	K.Later(0.12, function()
		hit(ctx, K.Circle(ctx.Player, at, d.BoltRadius, d.MaxTargets), d.BoltDamage, at, 0.6, 0.4, { K = "Strike", At = at })
	end)
	return { Bolt = at }
end

-- ===================== Red: Fire =====================
-- Leap and crash ahead as a comet; the crater burns.
function S.CometDive(ctx)
	local d = ctx.Def
	local landing = landingSpot(ctx, d.Length)
	moved(ctx)
	K.Iframes(ctx.Player, d.Air + 0.25)
	K.Later(d.Air, function()
		local list = K.Circle(ctx.Player, landing, d.Radius, d.MaxTargets)
		hit(ctx, list, d.Damage, landing, 2, 0.8)
		for _, enemy in ipairs(list) do
			T.knockUp(enemy, 40)
		end
	end)
	every(ctx, d.Air + 0.5, 0.5, d.BurnTicks, function()
		hit(ctx, K.Circle(ctx.Player, landing, d.Radius * 0.8, d.MaxTargets), d.Burn, landing, 0, 0, "Burn")
	end)
	return { Landing = landing, Air = d.Air, Radius = d.Radius }
end

-- A sweeping torrent of dragon fire.
function S.DragonBreath(ctx)
	local d = ctx.Def
	local slice = d.Sweep / d.Ticks
	local arc = math.cos(math.rad(slice * 0.75))
	every(ctx, 0.25, d.Tick, d.Ticks, function(i)
		local a = -d.Sweep / 2 + slice * (i - 0.5)
		local from = here(ctx)
		hit(ctx, K.Cone(ctx.Player, from, rotY(ctx.Dir, a), d.Range, arc, d.MaxTargets), d.Damage, from, 0.3, 0.2, "Burn")
	end)
	return { Sweep = d.Sweep, Ticks = d.Ticks, Tick = d.Tick, Range = d.Range }
end

-- Lava geysers burst up around you (on enemies first, then anywhere).
function S.VolcanicEruption(ctx)
	local d = ctx.Def
	local spots = {}
	for _, enemy in ipairs(nearest(ctx, ctx.Origin, d.Radius, math.floor(d.Geysers / 2))) do
		table.insert(spots, T.ground(enemy.Root.Position))
	end
	local rng = Random.new()
	while #spots < d.Geysers do
		local a, r = rng:NextNumber() * math.pi * 2, 8 + rng:NextNumber() * (d.Radius - 8)
		table.insert(spots, T.ground(ctx.Origin + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)))
	end
	for i, spot in ipairs(spots) do
		K.Later(0.35 + (i - 1) * d.Interval, function()
			local list = K.Circle(ctx.Player, spot, d.GeyserRadius, d.MaxTargets)
			hit(ctx, list, d.Damage, spot, 0, 0.6, "Burn")
			for _, enemy in ipairs(list) do
				T.knockUp(enemy, d.KnockUp)
			end
		end)
	end
	return { Spots = spots, Interval = d.Interval }
end

-- Phoenix fire: regenerate, and the first deadly blow rebirths you instead.
function S.PhoenixRebirth(ctx)
	local d = ctx.Def
	local player, character = ctx.Player, ctx.Character
	every(ctx, 0.5, 0.5, math.floor(d.Duration / 0.5), function()
		if alive(player, character) then
			T.heal(player, d.Regen * 0.5)
		end
	end)
	local untilAt = os.clock() + d.Duration
	svc().CombatService:SetDeathGuard(player, function(p: Player, humanoid: Humanoid)
		if os.clock() > untilAt or p.Character ~= character then
			return false
		end
		humanoid.Health = humanoid.MaxHealth
		K.Iframes(p, 1.5)
		local at = here(ctx)
		hit(ctx, K.Circle(p, at, d.Radius, d.MaxTargets), d.Damage, at, 3, 1, "Burn")
		SuitUltimates.Announce(ctx, { Rebirth = true })
		return true
	end)
	K.Later(d.Duration, function()
		if os.clock() >= untilAt then
			svc().CombatService:SetDeathGuard(player, nil)
		end
	end)
	return { Duration = d.Duration }
end

-- ===================== Black: Smoke Storm =====================
-- Surf a storm cloud forward; lightning lashes the ground the whole way.
function S.ThunderheadSurf(ctx)
	local d = ctx.Def
	local length = K.ClearDistance(ctx.Origin, ctx.Dir, d.Length)
	moved(ctx)
	K.Iframes(ctx.Player, d.Time + 0.2)
	for i = 1, d.Strikes do
		local at = ctx.Origin + ctx.Dir * length * i / d.Strikes
		K.Later(d.Time * i / d.Strikes, function()
			hit(ctx, K.Circle(ctx.Player, at, d.Radius, d.MaxTargets), d.Damage, at, 0.8, 0.4, { K = "Strike", At = at })
		end)
	end
	return { Length = length, Time = d.Time }
end

-- Lightning spears rain down along a line, one after another.
function S.SpearBarrage(ctx)
	local d = ctx.Def
	local spots = {}
	local rng = Random.new()
	for i = 1, d.Spears do
		local along = 8 + (d.Length - 8) * (i - 1) / math.max(1, d.Spears - 1)
		local side = rotY(ctx.Dir, 90) * (rng:NextNumber() - 0.5) * 8
		local spot = T.ground(ctx.Origin + ctx.Dir * along + side)
		spots[i] = spot
		K.Later(0.25 + (i - 1) * d.Interval, function()
			hit(ctx, K.Circle(ctx.Player, spot, d.Radius, d.MaxTargets), d.Damage, spot, 0.5, 0.4)
		end)
	end
	return { Spots = spots, Interval = d.Interval }
end

-- A black hurricane: out, then back in under lightning.
function S.BlackTempest(ctx)
	local d = ctx.Def
	local center = ctx.Origin
	K.Later(0.3, function()
		hit(ctx, K.Circle(ctx.Player, center, d.Radius, d.MaxTargets), d.Damage, center, 3, 0.6)
	end)
	K.Later(1.2, function()
		for _, enemy in ipairs(K.Circle(ctx.Player, center, d.Radius * 1.4, d.MaxTargets)) do
			T.pull(enemy, center, 0.4)
		end
	end)
	K.Later(1.65, function()
		hit(ctx, K.Circle(ctx.Player, center, d.Radius * 0.5, d.MaxTargets), d.PullDamage, center, 0, 1)
	end)
	for i = 1, d.Bolts do
		K.Later(0.4 + i * 0.12, function()
			local list = K.Circle(ctx.Player, center, d.Radius, d.MaxTargets)
			local enemy = list[math.random(1, math.max(1, #list))]
			if enemy then
				local at = enemy.Root.Position
				hit(ctx, { enemy }, d.BoltDamage, at, 0, 0.3, { K = "Strike", At = at })
			end
		end)
	end
	return { Center = center, Radius = d.Radius }
end

-- Three storm clones around you hurl chain lightning every second.
function S.StormClones(ctx)
	local d = ctx.Def
	local function clonePos(i: number): Vector3
		local a = (i - 1) / d.Clones * math.pi * 2
		return here(ctx) + Vector3.new(math.cos(a) * 7, 0, math.sin(a) * 7)
	end
	every(ctx, 0.6, d.Interval, math.floor(d.Duration / d.Interval), function(tick)
		for i = 1, d.Clones do
			K.Later((i - 1) * 0.12, function()
				local from = clonePos(i + tick * 0.15)
				local seen = {}
				local prev = from
				for _ = 1, d.Chain do
					local found = nil
					for _, enemy in ipairs(nearest(ctx, prev, if prev == from then d.Range else 16, 6)) do
						if not seen[enemy] then
							found = enemy
							break
						end
					end
					if not found then
						break
					end
					seen[found] = true
					hit(ctx, { found }, d.Damage, prev, 0.3, 0.3, { K = "Arc", From = prev })
					prev = found.Root.Position
				end
			end)
		end
	end)
	return { Duration = d.Duration, Clones = d.Clones }
end

-- ===================== White: Holy Light =====================
-- Rise in light and come down ahead as a pillar from the sky.
function S.RadiantAscension(ctx)
	local d = ctx.Def
	local landing = landingSpot(ctx, d.Length)
	moved(ctx)
	K.Iframes(ctx.Player, d.Iframes)
	K.Later(d.Air, function()
		local list = K.Circle(ctx.Player, landing, d.Radius, d.MaxTargets)
		hit(ctx, list, d.Damage, landing, 1.6, 1)
		for _, enemy in ipairs(K.Circle(ctx.Player, landing, d.Radius * 2, d.MaxTargets)) do
			T.blind(enemy)
		end
	end)
	return { Landing = landing, Air = d.Air, Radius = d.Radius }
end

-- A beam into a prism that fans into three.
function S.PrismBeam(ctx)
	local d = ctx.Def
	local from = ctx.Origin
	local prism = from + ctx.Dir * d.Length
	local angles = {}
	for i = 1, d.Splits do
		angles[i] = math.deg(-d.SplitAngle + 2 * d.SplitAngle * (i - 1) / math.max(1, d.Splits - 1))
	end
	K.Later(0.35, function()
		hit(ctx, K.Line(ctx.Player, from, ctx.Dir, d.Length, d.Width, d.MaxTargets), d.Damage, from, 1, 0.4)
	end)
	K.Later(0.5, function()
		local done = {}
		for _, a in ipairs(angles) do
			local fresh = {}
			for _, enemy in ipairs(K.Line(ctx.Player, prism, rotY(ctx.Dir, a), d.SplitLength, d.Width * 0.8, d.MaxTargets)) do
				if not done[enemy] then
					done[enemy] = true
					table.insert(fresh, enemy)
				end
			end
			hit(ctx, fresh, d.SplitDamage, prism, 1, 0.4)
		end
	end)
	return { Prism = prism, Angles = angles, Length = d.Length, SplitLength = d.SplitLength }
end

-- A ring of falling swords, then judgment from the centre.
function S.JudgmentSwords(ctx)
	local d = ctx.Def
	local center = ctx.Origin
	local spots = {}
	for i = 1, d.Swords do
		local a = (i - 1) / d.Swords * math.pi * 2
		local spot = T.ground(center + Vector3.new(math.cos(a) * d.Ring, 0, math.sin(a) * d.Ring))
		spots[i] = spot
		K.Later(0.35 + (i - 1) * 0.08, function()
			hit(ctx, K.Circle(ctx.Player, spot, d.SwordRadius, d.MaxTargets), d.Damage, spot, 0.5, 0.6)
		end)
	end
	local boom = 0.35 + d.Swords * 0.08 + 0.35
	K.Later(boom, function()
		local list = K.Circle(ctx.Player, center, d.CenterRadius, d.MaxTargets)
		hit(ctx, list, d.CenterDamage, center, 2.4, 1)
		for _, enemy in ipairs(list) do
			T.blind(enemy)
		end
	end)
	return { Center = center, Spots = spots, Boom = boom }
end

-- Holy ground: you heal inside, enemies burn and slow.
function S.DawnSanctuary(ctx)
	local d = ctx.Def
	local center = ctx.Origin
	local player, character = ctx.Player, ctx.Character
	every(ctx, 0.3, d.Tick, math.floor(d.Duration / d.Tick), function()
		if alive(player, character) and flat(here(ctx) - center).Magnitude <= d.Radius then
			T.heal(player, d.Heal * d.Tick)
		end
		local list = K.Circle(player, center, d.Radius, d.MaxTargets)
		hit(ctx, list, d.Damage, center, 0, 0, "Holy")
		for _, enemy in ipairs(list) do
			T.slow(enemy, d.Slow, d.Tick + 0.3)
		end
	end)
	return { Center = center, Radius = d.Radius, Duration = d.Duration }
end

-- ===================== Gold: Sun =====================
-- Charge in sunfire, throwing enemies aside, and flare at the end.
function S.SunflareCharge(ctx)
	local d = ctx.Def
	local length = K.ClearDistance(ctx.Origin, ctx.Dir, d.Length)
	local targets = K.Line(ctx.Player, ctx.Origin, ctx.Dir, length, d.Width, d.MaxTargets)
	moved(ctx)
	K.Iframes(ctx.Player, d.Iframes)
	K.Later(0.25, function()
		for _, enemy in ipairs(T.living(targets)) do
			-- pushed out sideways from the charge's line
			local rel = flat(enemy.Root.Position - ctx.Origin)
			local onLine = ctx.Origin + ctx.Dir * rel:Dot(ctx.Dir)
			hit(ctx, { enemy }, d.Damage, onLine, 2.6, 0.5)
		end
	end)
	local finish = ctx.Origin + ctx.Dir * length
	K.Later(0.42, function()
		local list = K.Circle(ctx.Player, finish, d.EndRadius, d.MaxTargets)
		hit(ctx, list, d.EndDamage, finish, 1.6, 0.6)
		for _, enemy in ipairs(list) do
			T.blind(enemy)
		end
	end)
	return { Length = length }
end

-- A javelin of sunlight pins the first enemy, then detonates.
function S.SunspearJavelin(ctx)
	local d = ctx.Def
	local from = ctx.Origin
	local best, bestAlong = nil, math.huge
	for _, enemy in ipairs(K.Line(ctx.Player, from, ctx.Dir, d.Length, d.Width, 60)) do
		local along = flat(enemy.Root.Position - from):Dot(ctx.Dir)
		if along < bestAlong then
			best, bestAlong = enemy, along
		end
	end
	local distance = if best then math.max(4, bestAlong) else K.ClearDistance(from, ctx.Dir, d.Length)
	local impact = if best then best.Root.Position else T.ground(from + ctx.Dir * distance)
	local flight = 0.15 + distance / 160
	if best then
		K.Later(flight, function()
			hit(ctx, { best }, d.Damage, from, 0, d.Fuse + 0.2)
		end)
	end
	K.Later(flight + d.Fuse, function()
		local list = K.Circle(ctx.Player, impact, d.Radius, d.MaxTargets)
		hit(ctx, list, d.BlastDamage, impact, 2.6, 0.8)
		for _, enemy in ipairs(list) do
			T.blind(enemy)
		end
	end)
	return { Impact = impact, Flight = flight, Fuse = d.Fuse }
end

-- Gather the sun's light, untouchable, then go supernova.
function S.Supernova(ctx)
	local d = ctx.Def
	K.Iframes(ctx.Player, d.Iframes)
	K.Later(d.Charge, function()
		local center = here(ctx)
		local list = K.Circle(ctx.Player, center, d.Radius, d.MaxTargets)
		hit(ctx, list, d.Damage, center, 3, 1)
		for _, enemy in ipairs(list) do
			T.blind(enemy)
			T.knockUp(enemy, 30)
		end
	end)
	return { Charge = d.Charge, Radius = d.Radius }
end

-- A small sun circles you, scorching everything close; +damage while it lasts.
function S.SolarCrown(ctx)
	local d = ctx.Def
	svc().StatService:SetModifier(ctx.Player, "mastery_crown", { Damage = d.DamageMult }, d.Duration)
	every(ctx, 0.5, d.Tick, math.floor(d.Duration / d.Tick), function()
		local center = here(ctx)
		hit(ctx, K.Circle(ctx.Player, center, d.Radius, d.MaxTargets), d.Damage, center, 0, 0, "Burn")
	end)
	return { Duration = d.Duration, Radius = d.Radius }
end

-- ===================== Crimson: Blood =====================
-- Flash from enemy to enemy; each cut bleeds and heals you.
function S.BloodRend(ctx)
	local d = ctx.Def
	local path, picked = {}, {}
	local pos = ctx.Origin
	local seen = {}
	for _ = 1, d.Targets do
		local found = nil
		for _, enemy in ipairs(nearest(ctx, pos, if #picked == 0 then d.Range else 30, 10)) do
			if not seen[enemy] then
				found = enemy
				break
			end
		end
		if not found then
			break
		end
		seen[found] = true
		table.insert(picked, found)
		local to = flat(found.Root.Position - pos)
		local beyond = found.Root.Position + (if to.Magnitude > 0.1 then to.Unit else ctx.Dir) * 3.5
		pos = Vector3.new(beyond.X, ctx.Origin.Y, beyond.Z)
		table.insert(path, pos)
	end
	if #picked == 0 then
		-- nothing near: a straight rend forward
		pos = ctx.Origin + ctx.Dir * K.ClearDistance(ctx.Origin, ctx.Dir, 24)
		table.insert(path, pos)
	end
	moved(ctx)
	K.Iframes(ctx.Player, #path * d.Step + 0.4)
	for i, enemy in ipairs(picked) do
		K.Later(i * d.Step, function()
			local results = hit(ctx, { enemy }, d.Damage, path[i], 0.4, 0.6, "Rend")
			if #results > 0 then
				T.heal(ctx.Player, d.Heal)
			end
		end)
		every(ctx, i * d.Step + 0.5, 0.5, d.BleedTicks, function()
			hit(ctx, { enemy }, d.Bleed, nil, 0, 0, "Bleed")
		end)
	end
	return { Path = path, Step = d.Step }
end

-- A blood scythe spirals outward, slicing each enemy a few times.
function S.HemorrhageScythe(ctx)
	local d = ctx.Def
	local counts = {}
	local center = ctx.Origin
	for s = 1, d.Steps do
		local k = s / d.Steps
		local spot = center + rotY(ctx.Dir, k * d.Turns * 360) * (d.Radius * k)
		K.Later(d.Time * k, function()
			local fresh = {}
			for _, enemy in ipairs(K.Circle(ctx.Player, spot, 7 + 4 * k, d.MaxTargets)) do
				if (counts[enemy] or 0) < d.PerEnemy then
					counts[enemy] = (counts[enemy] or 0) + 1
					table.insert(fresh, enemy)
				end
			end
			hit(ctx, fresh, d.Damage, spot, 0.4, 0.3, "Bleed")
		end)
	end
	return { Center = center, Radius = d.Radius, Turns = d.Turns, Time = d.Time }
end

-- A blood moon: everything under it bleeds, and the blood heals you.
function S.BloodMoon(ctx)
	local d = ctx.Def
	every(ctx, 0.5, d.Tick, d.Ticks, function()
		local center = here(ctx)
		local results = hit(ctx, K.Circle(ctx.Player, center, d.Radius, d.MaxTargets), d.Damage, center, 0, 0.2, "Bleed")
		if #results > 0 then
			T.heal(ctx.Player, math.min(0.05, d.Heal * #results))
		end
	end)
	return { Radius = d.Radius, Ticks = d.Ticks, Tick = d.Tick }
end

-- Pay health for power: +damage, and every swing throws a crescent that heals.
function S.BloodPact(ctx)
	local d = ctx.Def
	local character = ctx.Player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = math.max(1, humanoid.Health - humanoid.MaxHealth * d.Cost)
	end
	svc().StatService:SetModifier(ctx.Player, "mastery_pact", { Damage = d.DamageMult }, d.Duration)
	SuitUltimates.Awaken(ctx.Player, d, d.Duration)
	return { Duration = d.Duration }
end
function W.BloodPact(ctx)
	local d = ctx.Def
	local targets = K.Line(ctx.Player, ctx.Origin, ctx.Dir, d.WaveLength, d.WaveWidth, 20)
	K.Later(0.1, function()
		local results = hit(ctx, targets, d.WaveDamage, ctx.Origin, 0.6, 0.2, "Bleed")
		if #results > 0 then
			T.heal(ctx.Player, math.min(d.HealCap, d.SwingHeal * #results))
		end
	end)
	return { Crescent = true, Length = d.WaveLength }
end

-- ===================== Shadow: Darkness =====================
-- Rise behind the farthest enemy in reach and strike from the dark.
function S.ShadowSwap(ctx)
	local d = ctx.Def
	local list = nearest(ctx, ctx.Origin, d.Range, 60)
	local target = list[#list]
	local behind, at
	if target then
		at = target.Root.Position
		local away = flat(at - ctx.Origin)
		away = if away.Magnitude > 0.1 then away.Unit else ctx.Dir
		behind = at + away * (target.Radius + 3)
		behind = Vector3.new(behind.X, at.Y, behind.Z)
	else
		behind = ctx.Origin + ctx.Dir * K.ClearDistance(ctx.Origin, ctx.Dir, 30)
		at = behind + ctx.Dir * 4
	end
	moved(ctx)
	K.Iframes(ctx.Player, 0.6)
	K.Later(0.3, function()
		if target then
			hit(ctx, { target }, d.Damage, behind, 1.4, 1.2)
		end
		hit(ctx, K.Circle(ctx.Player, at, d.SplashRadius, d.MaxTargets), d.Splash, behind, 0.8, 0.5)
	end)
	return { To = behind, Target = at }
end

-- A shadow serpent hunts down enemies one after another.
function S.ShadowSerpent(ctx)
	local d = ctx.Def
	local first = K.Cone(ctx.Player, ctx.Origin, ctx.Dir, d.Range, 0.3, 1)[1]
	local chain = {}
	if first then
		local seen = { [first] = true }
		chain[1] = first
		while #chain < d.Bites do
			local found = nil
			for _, enemy in ipairs(nearest(ctx, chain[#chain].Root.Position, d.Hop, 8)) do
				if not seen[enemy] then
					found = enemy
					break
				end
			end
			if not found then
				break
			end
			seen[found] = true
			table.insert(chain, found)
		end
	end
	for i, enemy in ipairs(chain) do
		K.Later(0.3 + (i - 1) * d.Interval, function()
			hit(ctx, { enemy }, d.Damage, nil, 0.6, 0.6, "Shadow")
		end)
	end
	return { Chain = T.points(chain), Interval = d.Interval, Range = d.Range }
end

-- Night falls: hands grab every enemy, then spikes of darkness.
function S.NightFall(ctx)
	local d = ctx.Def
	local list = K.Circle(ctx.Player, ctx.Origin, d.Radius, d.MaxTargets)
	K.Later(0.3, function()
		hit(ctx, list, 0.4, nil, 0, d.Root + d.Delay, "Shadow")
	end)
	K.Later(0.3 + d.Delay, function()
		hit(ctx, list, d.Damage, nil, 0, 0.6)
		for _, enemy in ipairs(T.living(list)) do
			T.knockUp(enemy, 30)
		end
	end)
	return { Points = T.points(list), Delay = d.Delay, Radius = d.Radius }
end

-- The shadow realm: untouchable and fast, then everything near is torn apart.
function S.ShadowRealm(ctx)
	local d = ctx.Def
	K.Iframes(ctx.Player, d.Duration)
	svc().StatService:SetModifier(ctx.Player, "mastery_realm", { WalkSpeed = d.SpeedMult }, d.Duration)
	for _, enemy in ipairs(K.Circle(ctx.Player, ctx.Origin, 60, 200)) do
		T.blind(enemy)
	end
	K.Later(d.Duration, function()
		local center = here(ctx)
		hit(ctx, K.Circle(ctx.Player, center, d.EndRadius, d.MaxTargets), d.EndDamage, center, 2.4, 1)
	end)
	return { Duration = d.Duration, Radius = d.EndRadius }
end

-- ===================== Celestial: Cosmic =====================
-- Step through a gate in space; both gates blast.
function S.WarpGate(ctx)
	local d = ctx.Def
	local length = K.ClearDistance(ctx.Origin, ctx.Dir, d.Length)
	local exit = ctx.Origin + ctx.Dir * length
	moved(ctx)
	K.Iframes(ctx.Player, d.Iframes)
	K.Later(0.2, function()
		hit(ctx, K.Circle(ctx.Player, ctx.Origin, d.Radius, d.MaxTargets), d.Damage, ctx.Origin, 1.4, 0.6)
	end)
	K.Later(0.4, function()
		hit(ctx, K.Circle(ctx.Player, exit, d.Radius, d.MaxTargets), d.Damage, exit, 1.4, 0.6)
	end)
	return { Length = length, Exit = exit }
end

-- An arrow into the sky bursts into a rain of star arrows ahead.
function S.StarlightArrow(ctx)
	local d = ctx.Def
	local front = K.Cone(ctx.Player, ctx.Origin, ctx.Dir, d.Distance + 20, 0.5, 1)[1]
	local center = T.ground(if front then front.Root.Position else ctx.Origin + ctx.Dir * d.Distance)
	local spots = {}
	for _, enemy in ipairs(nearest(ctx, center, d.Radius, math.floor(d.Arrows / 2))) do
		table.insert(spots, T.ground(enemy.Root.Position))
	end
	local rng = Random.new()
	while #spots < d.Arrows do
		local a, r = rng:NextNumber() * math.pi * 2, rng:NextNumber() * d.Radius
		table.insert(spots, T.ground(center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)))
	end
	for i, spot in ipairs(spots) do
		K.Later(d.Delay + (i - 1) * 0.04, function()
			hit(ctx, K.Circle(ctx.Player, spot, 5, d.MaxTargets), d.Damage, spot + Vector3.new(0, 10, 0), 0, 0.3)
		end)
	end
	return { Center = center, Spots = spots, Delay = d.Delay }
end

-- Enemies become a constellation, then every star falls.
function S.ConstellationCollapse(ctx)
	local d = ctx.Def
	local stars = nearest(ctx, ctx.Origin, d.Radius, d.Stars)
	K.Later(0.1, function()
		hit(ctx, stars, 0.3, nil, 0, d.Delay + 0.2)
	end)
	for i, enemy in ipairs(stars) do
		K.Later(d.Delay + (i - 1) * 0.05, function()
			hit(ctx, { enemy }, d.Damage, nil, 0, 0.5)
		end)
	end
	local bang = d.Delay + #stars * 0.05 + 0.25
	K.Later(bang, function()
		local center = here(ctx)
		hit(ctx, K.Circle(ctx.Player, center, d.BangRadius, d.MaxTargets), d.BangDamage, center, 2.4, 0.8)
	end)
	return { Stars = T.points(stars), Delay = d.Delay, Bang = bang }
end

-- Stop time around you; when it starts again all the damage lands.
function S.TimeStop(ctx)
	local d = ctx.Def
	local list = K.Circle(ctx.Player, ctx.Origin, d.Radius, d.MaxTargets)
	hit(ctx, list, 0.2, nil, 0, d.Stop, "Stop")
	K.Later(d.Stop, function()
		hit(ctx, list, d.Damage, ctx.Origin, 1.4, 0.6)
	end)
	return { Stop = d.Stop, Radius = d.Radius, Points = T.points(list) }
end

-- ===================== Void: Gravity =====================
-- Slingshot at the farthest enemy, dragging everything along.
function S.GravitySlingshot(ctx)
	local d = ctx.Def
	local list = K.Cone(ctx.Player, ctx.Origin, ctx.Dir, d.Range, 0.5, 60)
	local far, farDist = nil, 0
	for _, enemy in ipairs(list) do
		local dist = flat(enemy.Root.Position - ctx.Origin).Magnitude
		if dist > farDist then
			far, farDist = enemy, dist
		end
	end
	local dir = if far then flat(far.Root.Position - ctx.Origin).Unit else ctx.Dir
	local distance = if far then math.max(4, farDist - 3) else K.ClearDistance(ctx.Origin, ctx.Dir, d.Range * 0.6)
	distance = math.min(distance, K.ClearDistance(ctx.Origin, dir, distance))
	local landing = ctx.Origin + dir * distance
	moved(ctx)
	K.Iframes(ctx.Player, d.Iframes)
	K.Later(0.15, function()
		for _, enemy in ipairs(K.Line(ctx.Player, ctx.Origin, dir, distance, d.Width, d.MaxTargets)) do
			T.pull(enemy, landing, 0.3)
		end
	end)
	K.Later(0.5, function()
		local hits = K.Circle(ctx.Player, landing, d.Radius, d.MaxTargets)
		hit(ctx, hits, d.Damage, landing, 0.4, 0.8)
		for _, enemy in ipairs(hits) do
			T.knockUp(enemy, 30)
		end
	end)
	return { Landing = landing, Dir = dir }
end

-- A beam that pulls enemies onto it, then crushes them.
function S.HorizonBeam(ctx)
	local d = ctx.Def
	local from = ctx.Origin
	K.Later(0.2, function()
		for _, enemy in ipairs(K.Line(ctx.Player, from, ctx.Dir, d.Length, d.Width * 2.2, d.MaxTargets)) do
			local along = math.clamp(flat(enemy.Root.Position - from):Dot(ctx.Dir), 0, d.Length)
			T.pull(enemy, from + ctx.Dir * along, d.PullTime)
		end
	end)
	local lead = 0.2 + d.PullTime
	for i = 1, d.Hits do
		K.Later(lead + (i - 1) * d.Tick, function()
			hit(ctx, K.Line(ctx.Player, from, ctx.Dir, d.Length, d.Width, d.MaxTargets), d.Damage, from, 0, 0.4)
		end)
	end
	return { Length = d.Length, Lead = lead, Hits = d.Hits, Tick = d.Tick }
end

-- Lift everything, crush it in the air, then slam it down.
function S.GravityCrush(ctx)
	local d = ctx.Def
	local center = ctx.Origin
	local list = K.Circle(ctx.Player, center, d.Radius, d.MaxTargets)
	K.Later(0.25, function()
		for _, enemy in ipairs(T.living(list)) do
			T.float(enemy, d.Float, 9)
		end
	end)
	for i = 1, d.Ticks do
		K.Later(0.35 + (i - 1) * d.Float / d.Ticks, function()
			hit(ctx, list, d.Damage, nil, 0, 0.5, "Gravity")
		end)
	end
	K.Later(0.3 + d.Float, function()
		for _, enemy in ipairs(T.living(list)) do
			T.knockUp(enemy, -90)
		end
		hit(ctx, list, d.Slam, nil, 0, 1)
	end)
	return { Center = center, Radius = d.Radius, Float = d.Float }
end

-- A black sun ahead drags everything in, then collapses.
function S.BlackSun(ctx)
	local d = ctx.Def
	local center = T.ground(ctx.Origin + ctx.Dir * K.ClearDistance(ctx.Origin, ctx.Dir, d.Distance)) + Vector3.new(0, 4, 0)
	every(ctx, 0.4, d.Tick, math.floor(d.Duration / d.Tick), function()
		local list = K.Circle(ctx.Player, center, d.Radius, d.MaxTargets)
		for _, enemy in ipairs(list) do
			if flat(enemy.Root.Position - center).Magnitude > 5 then
				T.pull(enemy, center, 0.7)
			end
		end
		hit(ctx, list, d.Damage, nil, 0, 0.3, "Gravity")
	end)
	K.Later(0.4 + d.Duration, function()
		local list = K.Circle(ctx.Player, center, d.Radius * 0.6, d.MaxTargets)
		hit(ctx, list, d.Collapse, center, 3, 1)
		for _, enemy in ipairs(list) do
			T.knockUp(enemy, 50)
		end
	end)
	return { Center = center, Radius = d.Radius, Duration = d.Duration }
end

SuitUltimates.Casts = S
SuitUltimates.Swings = W

-- Set by Init: UltimateCasts.Awaken (the every-swing state) and a way to tell
-- nearby clients about a mid-ultimate event (Phoenix Rebirth's revive).
SuitUltimates.Awaken = function(_player: Player, _def, _duration: number) end
SuitUltimates.Announce = function(_ctx, _info) end

function SuitUltimates.Init(kit, tools, awaken, announce)
	K = kit
	T = tools
	SuitUltimates.Awaken = awaken
	SuitUltimates.Announce = announce
end

return SuitUltimates
