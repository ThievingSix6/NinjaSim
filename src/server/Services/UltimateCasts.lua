--[[
	UltimateCasts: the server side of the suit mastery ultimates (Config/Mastery),
	cast through SkillService:CastUltimate with SkillService's own helpers (the kit:
	Strike, Circle, Line, Later, Iframes, RootOf, ClearDistance, Services).

	Damage is x the player's hit damage x the suit's Scale (ctx.Power). Each cast
	returns an info table for the client looks (Controllers/UltimateEffects).
	The Avatar keeps a per-player state: while awake, every sword swing throws a
	wave (SkillService:AvatarSwing, called by CombatService) and hits heal.
]]

local UltimateCasts = {}

local K -- kit from SkillService
local avatars: { [Player]: { Until: number, Def: any } } = {}

local function svc()
	return K.Services()
end

local function heal(player: Player, fraction: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * fraction)
	end
end

local U = {}

-- Lv 25: rush through everything, untouchable, and burst at the end.
function U.Rush(ctx)
	local d = ctx.Def
	local length = K.ClearDistance(ctx.Origin, ctx.Dir, d.Length)
	local targets = K.Line(ctx.Player, ctx.Origin, ctx.Dir, length, d.Width, d.MaxTargets)
	svc().ZoneService:MarkTeleported(ctx.Player)
	K.Iframes(ctx.Player, d.Iframes)
	local finish = ctx.Origin + ctx.Dir * length
	K.Later(0.3, function()
		K.Strike(ctx, targets, d.Damage, { From = ctx.Origin, Knockback = 1.6, Stun = 0.8 })
	end)
	K.Later(0.42, function()
		K.Strike(ctx, K.Circle(ctx.Player, finish, d.BurstRadius, d.MaxTargets), d.BurstDamage, { From = finish, Knockback = 2.4, Stun = 1, Tag = "Burst" })
	end)
	return { Length = length }
end

-- Lv 50: a huge piercing beam that ticks Hits times from wherever you stand.
function U.Lance(ctx)
	local d = ctx.Def
	for i = 1, d.Hits do
		K.Later(d.Windup + (i - 1) * d.Tick, function()
			local root = K.RootOf(ctx.Player)
			if not root or ctx.Player.Character ~= ctx.Character then
				return
			end
			K.Strike(ctx, K.Line(ctx.Player, root.Position, ctx.Dir, d.Length, d.Width, d.MaxTargets), d.Damage, {
				From = root.Position, Knockback = if i == d.Hits then 1.8 else 0.2, Stun = 0.4,
			})
		end)
	end
	return { Length = d.Length, Windup = d.Windup, Tick = d.Tick, Hits = d.Hits }
end

-- Lv 75: three expanding shockwaves around you.
function U.Cataclysm(ctx)
	local d = ctx.Def
	K.Iframes(ctx.Player, 0.6)
	for i, radius in ipairs(d.Radii) do
		K.Later(0.35 + (i - 1) * d.Interval, function()
			local root = K.RootOf(ctx.Player)
			local center = if root then root.Position else ctx.Origin
			K.Strike(ctx, K.Circle(ctx.Player, center, radius, d.MaxTargets), d.Damage, { From = center, Knockback = 2.6, Stun = 1.2, Tag = "Quake" })
		end)
	end
	return { Radii = d.Radii, Interval = d.Interval }
end

-- Lv 100: awaken. Damage, speed and swing speed for Duration seconds; swings throw waves.
function U.Avatar(ctx)
	local d = ctx.Def
	avatars[ctx.Player] = { Until = os.clock() + d.Duration, Def = d }
	svc().StatService:SetModifier(ctx.Player, "mastery_avatar", {
		Damage = d.DamageMult, WalkSpeed = d.SpeedMult, AttackInterval = 1 / d.AttackSpeed, Avatar = d.SuitIndex,
	}, d.Duration)
	K.Iframes(ctx.Player, 1)
	heal(ctx.Player, 0.25)
	return { Duration = d.Duration }
end

function UltimateCasts.Cast(ctx)
	local fn = U[ctx.Def.Kind]
	return if fn then fn(ctx) else nil
end

-- The awake Avatar's def, or nil.
function UltimateCasts.Avatar(player: Player)
	local a = avatars[player]
	if a and os.clock() < a.Until then
		return a.Def
	end
	avatars[player] = nil
	return nil
end

-- A sword swing while awake: a wave down the swing's line; every hit heals. Returns info.
function UltimateCasts.Wave(ctx)
	local d = ctx.Def
	local origin, dir = ctx.Origin, ctx.Dir
	local targets = K.Line(ctx.Player, origin, dir, d.WaveLength, d.WaveWidth, d.MaxTargets)
	K.Later(0.12, function()
		local results = K.Strike(ctx, targets, d.WaveDamage, { From = origin, Knockback = 0.8, Stun = 0.3, Tag = "Wave" })
		if #results > 0 then
			heal(ctx.Player, math.min(0.08, d.Heal * #results))
		end
	end)
	return { Wave = true, Length = d.WaveLength }
end

function UltimateCasts.Clear(player: Player)
	avatars[player] = nil
end

function UltimateCasts.Init(kit)
	K = kit
end

return UltimateCasts
