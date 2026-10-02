--[[
	SkillService: owns the ninja/samurai skills (Config/Skills).

	The client asks "cast the skill in slot N, aiming this way"; the server checks
	the skill is owned and equipped in that slot, that its cooldown is over and the
	character is alive, then finds targets itself (from the server's own position
	of the character, in the skill's circle / cone / line / chain) and deals damage
	through EnemyService:Damage with the same per-hit formula as CombatService
	(player damage x multiplier x variance, crits). Bosses are enemies too, so they
	take skill damage (they ignore knockback and stun, as with sword hits).

	The 24 elemental tier skills (Config/ElementSkills) cast through ElementCasts with
	the same helpers. SkillService:CastAt(player, skillId, position, level?) fires any
	skill at a point with no slot or cooldown (for "chance on hit" procs).

	The suit mastery ultimates (Config/Mastery: Z X C V) cast through CastUltimate and
	UltimateCasts; an awake Avatar turns sword swings into waves (AvatarSwing).

	Requests (RequestService): BuySkill, UpgradeSkill, EquipSkill, UnequipSkill, CastSkill, CastUltimate.
	Events: SkillHits (hit results, to the caster and nearby players),
	        SkillCast (another player cast: plays their effects).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Skills = require(Shared.Config.Skills)
local Tiers = require(Shared.Config.Tiers)
local Mastery = require(Shared.Config.Mastery)
local Net = require(Shared.Net)

local SkillService = {}

local services
type State = { Last: { [string]: number }, LastAny: number, Clones: number }
local state: { [Player]: State } = {}

local NEAR = 150 -- studs: other players closer than this see the cast

local function getState(player: Player): State
	local s = state[player]
	if not s then
		s = { Last = {}, LastAny = 0, Clones = 0 }
		state[player] = s
	end
	return s
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function rootOf(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 then
		return nil, nil
	end
	return root, humanoid
end

local function othersNear(player: Player, position: Vector3): { Player }
	local list = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local r = rootOf(other)
			if r and (r.Position - position).Magnitude <= NEAR then
				table.insert(list, other)
			end
		end
	end
	return list
end

-- ===== target shapes (all from the server's own positions) =====
local function zoneId(player: Player): string
	return services.ZoneService:GetZone(player).Id
end

local function circle(player: Player, center: Vector3, radius: number, max: number)
	local out = {}
	for _, entry in ipairs(services.EnemyService:InRange(zoneId(player), center, radius)) do
		if #out >= max then
			break
		end
		table.insert(out, entry.Enemy)
	end
	return out
end

local function cone(player: Player, origin: Vector3, dir: Vector3, range: number, arc: number, max: number)
	local out = {}
	for _, entry in ipairs(services.EnemyService:InRange(zoneId(player), origin, range)) do
		if #out >= max then
			break
		end
		local enemy = entry.Enemy
		local to = flat(enemy.Root.Position - origin)
		if to.Magnitude < enemy.Radius + 3 or dir:Dot(to.Unit) >= arc then
			table.insert(out, enemy)
		end
	end
	return out
end

local function line(player: Player, origin: Vector3, dir: Vector3, length: number, width: number, max: number)
	local out = {}
	local mid = origin + dir * (length / 2)
	for _, entry in ipairs(services.EnemyService:InRange(zoneId(player), mid, length / 2 + width)) do
		if #out >= max then
			break
		end
		local enemy = entry.Enemy
		local rel = flat(enemy.Root.Position - origin)
		local along = rel:Dot(dir)
		local side = (rel - dir * along).Magnitude
		if along >= -3 and along <= length + 3 and side <= width / 2 + enemy.Radius then
			table.insert(out, enemy)
		end
	end
	return out
end

-- How far the character can travel along `dir` before a wall (for dashes).
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
local function clearDistance(origin: Vector3, dir: Vector3, length: number): number
	local filter = { workspace.Terrain }
	local world = workspace:FindFirstChild("World")
	if world then
		table.insert(filter, world)
	end
	rayParams.FilterDescendantsInstances = filter
	local hit = workspace:Raycast(origin, dir * (length + 2), rayParams)
	if hit then
		return math.max(0, hit.Distance - 2)
	end
	return length
end

-- ===== damage =====
-- Hits each living enemy once with the skill (the CombatService formula without the
-- sword combo bonus) and reports the results. Returns the results.
local function strike(ctx, enemies, mult: number, opts: { From: Vector3?, Knockback: number?, Stun: number?, Tag: any? }?)
	local o = opts or {}
	local player: Player = ctx.Player
	local stats = services.StatService:Get(player)
	local root = rootOf(player)
	if not stats or not root then
		return {}
	end
	local from = o.From or root.Position
	local results = {}
	for _, enemy in ipairs(enemies) do
		if not enemy.Dead and enemy.Model.Parent then
			local crit = math.random() < stats.CritChance
			local amount = stats.Damage * mult * ctx.Power * (0.92 + math.random() * 0.16)
			if crit then
				amount *= stats.CritMult
			end
			amount = math.max(1, math.floor(amount))
			local killed = services.EnemyService:Damage(enemy, player, amount, from, o.Knockback, o.Stun)
			table.insert(results, {
				Uid = enemy.Uid, Damage = amount, Crit = crit, Killed = killed,
				Position = enemy.Root.Position, Height = enemy.Height,
			})
		end
	end
	if #results > 0 then
		local payload = { Skill = ctx.Def.Id, Hits = results, Tag = o.Tag, Caster = player.UserId }
		Net.Event("SkillHits"):FireClient(player, payload)
		for _, other in ipairs(othersNear(player, root.Position)) do
			Net.Event("SkillHits"):FireClient(other, payload)
		end
	end
	return results
end

local function later(seconds: number, fn: () -> ())
	task.delay(seconds, function()
		local ok, err = pcall(fn)
		if not ok then
			warn("[SkillService] " .. tostring(err))
		end
	end)
end

-- Short invulnerability: enemies and bosses skip characters with a ForceField.
local function iframes(player: Player, seconds: number)
	local character = player.Character
	if not character then
		return
	end
	local ff = Instance.new("ForceField")
	ff.Name = "SkillGuard"
	ff.Visible = false
	ff.Parent = character
	task.delay(seconds, function()
		ff:Destroy()
	end)
end

local function alive(ctx): boolean
	return ctx.Player.Parent ~= nil and ctx.Player.Character == ctx.Character and rootOf(ctx.Player) ~= nil
end

-- ===== skills =====
-- Each returns an info table for the client effects (targets, centres, lengths).
local CAST = {}

function CAST.shuriken_storm(ctx)
	local d = ctx.Def
	local targets = cone(ctx.Player, ctx.Origin, ctx.Dir, d.Range, d.Arc, d.MaxTargets)
	later(0.18, function()
		strike(ctx, targets, d.Damage, { Knockback = d.Knockback, Stun = d.Stun })
	end)
	return {}
end

function CAST.whirlwind_slash(ctx)
	local d = ctx.Def
	for i, t in ipairs({ 0.12, 0.42 }) do
		later(t, function()
			if alive(ctx) then
				local root = rootOf(ctx.Player) :: BasePart
				strike(ctx, circle(ctx.Player, root.Position, d.Radius, d.MaxTargets), d.Damage, {
					Knockback = if i == 2 then d.Knockback else 0.3, Stun = d.Stun,
				})
			end
		end)
	end
	return {}
end

function CAST.iaido_dash(ctx)
	local d = ctx.Def
	local length = clearDistance(ctx.Origin, ctx.Dir, d.Length)
	local targets = line(ctx.Player, ctx.Origin, ctx.Dir, length, d.Width, d.MaxTargets)
	services.ZoneService:MarkTeleported(ctx.Player)
	iframes(ctx.Player, 0.5)
	-- the cut lands as the blade clicks home in its sheath
	later(0.38, function()
		strike(ctx, targets, d.Damage, { From = ctx.Origin, Knockback = d.Knockback, Stun = d.Stun })
	end)
	return { Length = length }
end

function CAST.wind_step(ctx)
	local d = ctx.Def
	local length = clearDistance(ctx.Origin, ctx.Dir, d.Length)
	services.ZoneService:MarkTeleported(ctx.Player)
	iframes(ctx.Player, 0.6)
	local duration = Skills.Duration(d, ctx.Level)
	services.StatService:SetModifier(ctx.Player, "wind_step", { WalkSpeed = d.Speed }, duration)
	later(0.1, function()
		strike(ctx, line(ctx.Player, ctx.Origin, ctx.Dir, length, d.Width, d.MaxTargets), d.Damage, {
			From = ctx.Origin, Knockback = d.Knockback, Stun = d.Stun,
		})
	end)
	return { Length = length, Duration = duration }
end

function CAST.smoke_bomb(ctx)
	local d = ctx.Def
	local targets = circle(ctx.Player, ctx.Origin, d.Radius, d.MaxTargets)
	local stun = d.Stun + 0.25 * (ctx.Level - 1)
	for _, enemy in ipairs(targets) do
		if not enemy.IsBoss then
			enemy.Target = nil -- blinded: they lose track of you
		end
	end
	strike(ctx, targets, d.Damage, { Knockback = d.Knockback, Stun = stun })
	local length = clearDistance(ctx.Origin, ctx.Dir, d.Length)
	services.ZoneService:MarkTeleported(ctx.Player)
	iframes(ctx.Player, 1)
	return { Length = length }
end

function CAST.kunai_rain(ctx)
	local d = ctx.Def
	-- aim at the nearest enemy roughly in front, else a spot ahead
	local center = ctx.Origin + ctx.Dir * 16
	local front = cone(ctx.Player, ctx.Origin, ctx.Dir, d.Range, 0.3, 1)
	if front[1] then
		center = front[1].Root.Position
	end
	center = Vector3.new(center.X, services.ZoneService:GroundHeight(center), center.Z)
	for _, t in ipairs({ 0.45, 0.75, 1.05 }) do
		later(t, function()
			if ctx.Player.Parent then
				strike(ctx, circle(ctx.Player, center, d.Radius, d.MaxTargets), d.Damage, { From = center, Knockback = d.Knockback, Stun = d.Stun })
			end
		end)
	end
	return { Center = center }
end

function CAST.dragon_flame(ctx)
	local d = ctx.Def
	local targets = cone(ctx.Player, ctx.Origin, ctx.Dir, d.Range, d.Arc, d.MaxTargets)
	later(0.22, function()
		strike(ctx, targets, d.Damage, { From = ctx.Origin, Knockback = d.Knockback, Stun = d.Stun })
		for tick = 1, d.BurnTicks do
			later(0.5 * tick, function()
				if ctx.Player.Parent then
					strike(ctx, targets, d.Burn, { Tag = "Burn" })
				end
			end)
		end
	end)
	return {}
end

function CAST.oni_quake(ctx)
	local d = ctx.Def
	later(0.45, function()
		if alive(ctx) then
			local root = rootOf(ctx.Player) :: BasePart
			strike(ctx, circle(ctx.Player, root.Position, d.Radius, d.MaxTargets), d.Damage, { Knockback = d.Knockback, Stun = d.Stun })
		end
	end)
	return {}
end

function CAST.lightning_blade(ctx)
	local d = ctx.Def
	local chain = {}
	local first = cone(ctx.Player, ctx.Origin, ctx.Dir, d.Range, d.Arc, 1)[1]
	local used = {}
	local current = first
	local maxChain = math.min(d.MaxTargets, d.Chain + ctx.Level - 1)
	while current and #chain < maxChain do
		used[current] = true
		table.insert(chain, current)
		local nextEnemy = nil
		for _, entry in ipairs(services.EnemyService:InRange(zoneId(ctx.Player), current.Root.Position, d.ChainRange)) do
			if not used[entry.Enemy] then
				nextEnemy = entry.Enemy
				break
			end
		end
		current = nextEnemy
	end
	local points = {}
	for _, enemy in ipairs(chain) do
		table.insert(points, { Uid = enemy.Uid, Position = enemy.Root.Position, Height = enemy.Height })
	end
	later(0.2, function()
		strike(ctx, chain, d.Damage, { Knockback = d.Knockback, Stun = d.Stun })
	end)
	return { Chain = points }
end

function CAST.shadow_clone(ctx)
	local d = ctx.Def
	local duration = Skills.Duration(d, ctx.Level)
	local s = getState(ctx.Player)
	s.Clones += 1
	local run = s.Clones
	task.spawn(function()
		local stop = os.clock() + duration
		task.wait(0.5)
		while os.clock() < stop and s.Clones == run and alive(ctx) do
			local root = rootOf(ctx.Player) :: BasePart
			local near = circle(ctx.Player, root.Position, d.Radius, d.Clones * 3)
			-- each clone takes a different enemy, nearest first
			for i = 1, d.Clones do
				local enemy = near[i] or near[1]
				if enemy then
					local ok, err = pcall(strike, ctx, { enemy }, d.Damage, { From = root.Position, Knockback = d.Knockback, Stun = d.Stun, Tag = { Clone = i } })
					if not ok then
						warn("[SkillService] " .. tostring(err))
					end
				end
			end
			task.wait(d.Interval)
		end
	end)
	return { Duration = duration }
end

function CAST.bushido_spirit(ctx)
	local d = ctx.Def
	local duration = Skills.Duration(d, ctx.Level)
	local power = 1 + (d.DamageBuff - 1) * ctx.Power
	services.StatService:SetModifier(ctx.Player, "bushido_spirit", {
		Damage = power, AttackInterval = 1 / d.AttackSpeedBuff,
	}, duration)
	local humanoid = (ctx.Character :: Model):FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * d.Heal)
	end
	strike(ctx, circle(ctx.Player, ctx.Origin, d.Radius, d.MaxTargets), d.Damage, { Knockback = d.Knockback, Stun = d.Stun })
	return { Duration = duration }
end

function CAST.thousand_cuts(ctx)
	local d = ctx.Def
	local max = d.MaxTargets + 2 * (ctx.Level - 1)
	local targets = circle(ctx.Player, ctx.Origin, d.Radius, max)
	local points = {}
	for _, enemy in ipairs(targets) do
		table.insert(points, { Uid = enemy.Uid, Position = enemy.Root.Position, Height = enemy.Height })
	end
	local total = 0.2 + #targets * Skills.CutStep + 0.35
	iframes(ctx.Player, total + 0.4)
	services.ZoneService:MarkTeleported(ctx.Player)
	for i, enemy in ipairs(targets) do
		later(0.2 + (i - 1) * Skills.CutStep, function()
			services.ZoneService:MarkTeleported(ctx.Player)
			strike(ctx, { enemy }, d.Damage, { Knockback = 0.2, Stun = d.Stun, Tag = { Cut = i } })
		end)
	end
	later(total, function()
		services.ZoneService:MarkTeleported(ctx.Player)
		if alive(ctx) then
			local root = rootOf(ctx.Player) :: BasePart
			strike(ctx, circle(ctx.Player, root.Position, d.Radius, 60), d.FinalDamage, { Knockback = d.Knockback, Stun = d.Stun, Tag = "Final" })
		end
	end)
	return { Targets = points, Step = Skills.CutStep, Total = total }
end

-- Elemental tier skills (Config/ElementSkills): their casts live in ElementCasts and
-- share the helpers above.
local kit = {
	Strike = strike, Circle = circle, Cone = cone, Line = line, Later = later, Iframes = iframes,
	RootOf = rootOf, ClearDistance = clearDistance,
	Services = function()
		return services
	end,
}
require(script.Parent.ElementCasts).Register(CAST, kit)

-- Suit mastery ultimates (Config/Mastery) share the same helpers.
local UltimateCasts = require(script.Parent.UltimateCasts)
UltimateCasts.Init(kit)

-- ===== requests =====
local function notify(player: Player, text: string, color: Color3?, icon: string?)
	Net.Event("Notify"):FireClient(player, { Text = text, Color = color, Icon = icon or "Shuriken" })
end

-- Puts a skill into the first empty slot (if any). Returns the slot.
local function autoEquip(data, id: string): number?
	for i = 1, Skills.Slots do
		if data.SkillSlots[i] == id then
			return i
		end
	end
	for i = 1, Skills.Slots do
		if (data.SkillSlots[i] or "") == "" then
			data.SkillSlots[i] = id
			return i
		end
	end
	return nil
end

local function grant(player: Player, data, def)
	data.Skills[def.Id] = 1
	local slot = autoEquip(data, def.Id)
	services.DataService:Changed(player, "Skills")
	services.DataService:Changed(player, "SkillSlots")
	return slot
end

-- Free unlocks (by level or tier) are granted automatically.
function SkillService:CheckUnlocks(player: Player)
	local data = services.DataService:Get(player)
	if not data then
		return
	end
	if self:Sanitize(data) then
		services.DataService:Changed(player, "SkillSlots")
	end
	local granted = {}
	local lastSlot, lastDef = nil, nil
	local byElement, elementOrder = {}, {} -- elemental tier skills get their own message
	for _, def in ipairs(Skills.List) do
		if Skills.IsFree(def) and not data.Skills[def.Id] and Skills.MeetsRequirement(def, data) then
			local slot = grant(player, data, def)
			if def.Element then
				if not byElement[def.Element] then
					byElement[def.Element] = {}
					table.insert(elementOrder, def.Element)
				end
				table.insert(byElement[def.Element], def.Name)
			else
				lastSlot, lastDef = slot, def
				table.insert(granted, def.Name)
			end
		end
	end
	if #granted == 1 and lastDef then
		notify(player, string.format("New skill: %s! %s", lastDef.Name, if lastSlot then "Press " .. lastSlot .. " to use it." else "Equip it in Skills (K)."), lastDef.Color)
	elseif #granted > 1 then
		notify(player, "New skills: " .. table.concat(granted, ", ") .. "! See them in Skills (K).", Color3.fromRGB(196, 120, 255))
	end
	if #elementOrder >= 1 and #elementOrder <= 2 then
		for _, id in ipairs(elementOrder) do
			local element = Skills.ElementById[id]
			notify(player, string.format("%s unlocked %s skills: %s! See Skills (K).", Tiers.Get(element.Tier).Name, element.Name,
				table.concat(byElement[id], " & ")), element.Color, element.Icon)
		end
	elseif #elementOrder > 2 then
		local names = {}
		for _, id in ipairs(elementOrder) do
			table.insert(names, Skills.ElementById[id].Name)
		end
		notify(player, "New elemental skills: " .. table.concat(names, ", ") .. "! See Skills (K).", Color3.fromRGB(196, 120, 255), "Sparkle")
	end
end

-- Old or hand-edited saves: keep slots a clean 4-entry list of owned skills.
-- Returns true when it had to fix something.
function SkillService:Sanitize(data): boolean
	local changed = false
	if type(data.Skills) ~= "table" then
		data.Skills = {}
		changed = true
	end
	if type(data.SkillSlots) ~= "table" then
		data.SkillSlots = {}
		changed = true
	end
	for i = 1, Skills.Slots do
		local id = data.SkillSlots[i]
		if type(id) ~= "string" or (id ~= "" and not (Skills.Get(id) and data.Skills[id])) then
			data.SkillSlots[i] = ""
			changed = true
		end
	end
	for i = #data.SkillSlots, Skills.Slots + 1, -1 do
		data.SkillSlots[i] = nil
		changed = true
	end
	return changed
end

function SkillService:Buy(player: Player, id: string): (boolean, string?)
	local data = services.DataService:Get(player)
	local def = Skills.Get(id)
	if not data or not def then
		return false, "Unknown skill"
	end
	if data.Skills[def.Id] then
		return false, "Already learned"
	end
	local ok, reason = Skills.MeetsRequirement(def, data)
	if not ok then
		return false, reason
	end
	local currency, price = Skills.Price(def)
	if currency and price then
		if not services.DataService:Spend(player, currency, price) then
			return false, "Not enough " .. (if currency == "Shards" then "Spirit Shards" else "Coins")
		end
	end
	grant(player, data, def)
	return true
end

function SkillService:Upgrade(player: Player, id: string): (boolean, string?)
	local data = services.DataService:Get(player)
	local def = Skills.Get(id)
	if not data or not def or not data.Skills[def.Id] then
		return false, "Learn this skill first"
	end
	local level = data.Skills[def.Id]
	if level >= Skills.MaxLevel then
		return false, "Already max level"
	end
	local currency, cost = Skills.UpgradeCost(def, level, data.Level)
	if not services.DataService:Spend(player, currency, cost) then
		return false, "Not enough " .. (if currency == "Shards" then "Spirit Shards" else "Coins")
	end
	data.Skills[def.Id] = level + 1
	services.DataService:Changed(player, "Skills")
	return true
end

-- slot: 1-4, or nil for the first empty slot (else slot 1). Swaps if already equipped elsewhere.
function SkillService:Equip(player: Player, id: string, slot: number?): (boolean, string?)
	local data = services.DataService:Get(player)
	local def = Skills.Get(id)
	if not data or not def or not data.Skills[def.Id] then
		return false, "Learn this skill first"
	end
	self:Sanitize(data)
	local current = table.find(data.SkillSlots, def.Id)
	local target = slot
	if not target then
		target = table.find(data.SkillSlots, "") or 1
	end
	if current == target then
		return true
	end
	if current then
		data.SkillSlots[current] = data.SkillSlots[target]
	end
	data.SkillSlots[target] = def.Id
	services.DataService:Changed(player, "SkillSlots")
	return true
end

function SkillService:Unequip(player: Player, slot: number): (boolean, string?)
	local data = services.DataService:Get(player)
	if not data then
		return false, "Still loading"
	end
	self:Sanitize(data)
	data.SkillSlots[slot] = ""
	services.DataService:Changed(player, "SkillSlots")
	return true
end

function SkillService:UnlockAll(player: Player): number
	local data = services.DataService:Get(player)
	if not data then
		return 0
	end
	local n = 0
	for _, def in ipairs(Skills.List) do
		if not data.Skills[def.Id] then
			n += 1
		end
		data.Skills[def.Id] = data.Skills[def.Id] or 1
		autoEquip(data, def.Id)
	end
	services.DataService:Changed(player, "Skills")
	services.DataService:Changed(player, "SkillSlots")
	return n
end

function SkillService:Cast(player: Player, slot: number, aim: any): (boolean, any)
	local data = services.DataService:Get(player)
	if not data then
		return false, "Still loading"
	end
	local id = data.SkillSlots[slot]
	local def = Skills.Get(id)
	local level = def and data.Skills[def.Id]
	if not def or not level then
		return false, "No skill in that slot"
	end
	local root = rootOf(player)
	if not root then
		return false, nil
	end
	local s = getState(player)
	local now = os.clock()
	local cooldown = Skills.Cooldown(def, level)
	-- a little latency tolerance, like the sword cadence check
	if now - (s.Last[def.Id] or -math.huge) < cooldown - 0.35 or now - s.LastAny < Skills.GlobalCooldown * 0.5 then
		return false, nil
	end
	s.Last[def.Id] = now
	s.LastAny = now

	-- aim: the client's direction (flattened, unit), else where the character faces
	local dir = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if typeof(aim) == "Vector3" and aim.X == aim.X and aim.Z == aim.Z and flat(aim).Magnitude > 0.01 and flat(aim).Magnitude < 1e4 then
		dir = flat(aim)
	end
	dir = if dir.Magnitude > 0.01 then dir.Unit else Vector3.new(0, 0, -1)

	local ctx = {
		Player = player, Character = player.Character, Def = def, Level = level, Power = Skills.Power(level),
		Origin = root.Position, Dir = dir,
	}
	local info = CAST[def.Id](ctx) or {}
	for _, other in ipairs(othersNear(player, root.Position)) do
		Net.Event("SkillCast"):FireClient(other, { Player = player, Skill = def.Id, Level = level, Origin = root.Position, Dir = dir, Info = info })
	end
	return true, { Skill = def.Id, Cooldown = cooldown, Info = info }
end

-- Fires a skill's effect at a point for `player`, with no slot, ownership or cooldown
-- check (for procs such as "chance on hit to cast <skill>"; the caller rate-limits).
-- Damage still uses the player's hit damage. `level` defaults to the player's level
-- in that skill (or 1). Self-centred skills centre on `position`, placed ones land
-- there, and dashes don't move the player. Skills with `PointCast = true` in
-- Config/ElementSkills read best this way. Everyone nearby (the caster too) sees it.
-- Returns ok, info.
function SkillService:CastAt(player: Player, skillId: string, position: Vector3, level: number?): (boolean, any)
	local def = Skills.Get(skillId)
	local root = rootOf(player)
	if not def or not CAST[def.Id] or not root or typeof(position) ~= "Vector3" then
		return false, nil
	end
	local data = services.DataService:Get(player)
	local lv = math.clamp(level or (data and data.Skills[def.Id]) or 1, 1, Skills.MaxLevel)
	local dir = flat(position - root.Position)
	dir = if dir.Magnitude > 0.01 then dir.Unit else flat(root.CFrame.LookVector).Unit
	local ctx = {
		Player = player, Character = player.Character, Def = def, Level = lv, Power = Skills.Power(lv),
		Origin = position, Dir = dir, Proc = true, Target = position,
	}
	local ok, info = pcall(CAST[def.Id], ctx)
	if not ok then
		warn("[SkillService] CastAt " .. def.Id .. ": " .. tostring(info))
		return false, nil
	end
	info = info or {}
	local payload = { Player = player, Skill = def.Id, Level = lv, Origin = position, Dir = dir, Info = info, Proc = true }
	Net.Event("SkillCast"):FireClient(player, payload)
	for _, other in ipairs(othersNear(player, root.Position)) do
		Net.Event("SkillCast"):FireClient(other, payload)
	end
	return true, info
end

-- Casts the worn suit's ultimate in `slot` (1-4 = Z X C V) if its mastery is reached.
function SkillService:CastUltimate(player: Player, slot: number, aim: any): (boolean, any)
	local data = services.DataService:Get(player)
	if not data then
		return false, "Still loading"
	end
	local def = Mastery.ForSuit(Mastery.WornTier(data).Id)[slot]
	local ok, reason = Mastery.CanUse(data, def)
	if not ok then
		return false, reason
	end
	local root = rootOf(player)
	if not root then
		return false, nil
	end
	local s = getState(player)
	local now = os.clock()
	if now - (s.Last[def.Id] or -math.huge) < def.Cooldown - 0.35 or now - s.LastAny < Skills.GlobalCooldown * 0.5 then
		return false, nil
	end
	s.Last[def.Id] = now
	s.LastAny = now
	local dir = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if typeof(aim) == "Vector3" and aim.X == aim.X and aim.Z == aim.Z and flat(aim).Magnitude > 0.01 and flat(aim).Magnitude < 1e4 then
		dir = flat(aim)
	end
	dir = if dir.Magnitude > 0.01 then dir.Unit else Vector3.new(0, 0, -1)
	local ctx = {
		Player = player, Character = player.Character, Def = def, Level = 1, Power = def.Scale,
		Origin = root.Position, Dir = dir,
	}
	local info = UltimateCasts.Cast(ctx) or {}
	for _, other in ipairs(othersNear(player, root.Position)) do
		Net.Event("SkillCast"):FireClient(other, { Player = player, Skill = def.Id, Level = 1, Origin = root.Position, Dir = dir, Info = info })
	end
	return true, { Skill = def.Id, Cooldown = def.Cooldown, Info = info }
end

-- CombatService calls this on every swing: while an Avatar is awake the swing throws its wave.
function SkillService:AvatarSwing(player: Player, origin: Vector3, dir: Vector3)
	local def = UltimateCasts.Avatar(player)
	if not def then
		return
	end
	local ctx = { Player = player, Character = player.Character, Def = def, Level = 1, Power = def.Scale, Origin = origin, Dir = dir }
	local info = UltimateCasts.Wave(ctx)
	local payload = { Player = player, Skill = def.Id, Level = 1, Origin = origin, Dir = dir, Info = info, Proc = true }
	Net.Event("SkillCast"):FireClient(player, payload)
	for _, other in ipairs(othersNear(player, origin)) do
		Net.Event("SkillCast"):FireClient(other, payload)
	end
end

function SkillService:Init(registry)
	services = registry
end

function SkillService:Start()
	services.DataService:OnLoaded(function(player)
		self:CheckUnlocks(player)
	end)
	services.DataService:AddFlushHook(function(player, keys)
		if keys.Level or keys.Tier or keys.BestTier or keys.Rebirths then
			task.defer(function()
				self:CheckUnlocks(player)
			end)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		state[player] = nil
		UltimateCasts.Clear(player)
	end)
end

return SkillService
