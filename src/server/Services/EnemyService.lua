--[[
	EnemyService: spawns enemies into zone camps, runs ONE shared AI loop for all
	of them (no per-NPC scripts or loops), tracks health/damage contributions,
	hands out rewards and respawns.

	Horde battles: every camp holds Count x Balance.EnemyDensity enemies. A zone is
	only populated while players are in it (filled a batch per tick, emptied a while
	after the last player leaves), and at most Balance.MaxAttackers enemies swing at
	one player at a time while the rest of the crowd circles, waiting for a turn.

	Performance notes:
	  * AI only runs for zones that currently contain players (ZoneService.PlayersIn).
	  * Movement uses Humanoid:MoveTo (engine-side), re-issued at most a few times/sec.
	  * Health lives in a Lua table; only a "Health" attribute is replicated for UI.
	  * Hit/death visuals are client-side, driven by small remote events.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enemies = require(Shared.Config.Enemies)
local Zones = require(Shared.Config.Zones)
local Balance = require(Shared.Config.Balance)
local EnemyBuilder = require(Shared.Visuals.EnemyBuilder)
local Net = require(Shared.Net)

local EnemyService = {}
EnemyService.All = {} :: { [number]: any } -- uid -> enemy
EnemyService.ByZone = {} :: { [string]: { any } }
EnemyService.Slots = {} :: { [string]: { any } } -- zone id -> camp slots

local services
local folder: Folder
local nextUid = 0
local AI_TICK = 0.2
local BASE_RESPAWN = 4
local SPAWNS_PER_TICK = 14 -- per populate tick (0.25s), so a zone fills in a few seconds without a hitch
local EMPTY_GRACE = 45 -- seconds a zone stays populated after its last player leaves
local TOKEN_TIME = 2.6 -- seconds an enemy keeps its attack turn before letting another have it
local zoneActiveUntil: { [string]: number } = {}
local attackers: { [Player]: { [any]: number } } = {} -- player -> enemy -> turn expiry

local function zoneFolder(zoneId: string): Folder
	local f = folder:FindFirstChild(zoneId)
	if not f then
		f = Instance.new("Folder")
		f.Name = zoneId
		f.Parent = folder
	end
	return f :: Folder
end

-- Ground distance, ignoring height, except that things on different levels (the
-- Cursed Temple's halls under the valley vs. the valley itself) never count as near.
local LEVEL_GAP = 60
local function flatDistance(a: Vector3, b: Vector3): number
	if math.abs(a.Y - b.Y) > LEVEL_GAP then
		return math.huge
	end
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function randomPointInCircle(center: Vector3, radius: number): Vector3
	local a = math.random() * math.pi * 2
	local r = math.sqrt(math.random()) * radius
	return center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
end

-- opts: { Scale, IsBoss, Slot, Minion, GroundY (spawn on this floor height instead of
-- the terrain: the Cursed Temple's halls), Temple (its run), HealthMult, DamageMult, Aggro }
function EnemyService:Spawn(defId: string, level: number, zone, position: Vector3, opts: any?)
	opts = opts or {}
	local def = Enemies.Get(defId)
	if not def then
		warn("[EnemyService] Unknown enemy " .. tostring(defId))
		return nil
	end
	-- size variety: runts, normal, big and brutes (Balance.EnemySizes); bosses keep theirs
	local size = 1
	if opts.Scale == nil and not def.IsBoss and not def.Static and def.Archetype ~= "Dummy" then
		local roll = math.random()
		for _, band in ipairs(Balance.EnemySizes) do
			roll -= band[1]
			if roll <= 0 then
				size = band[2] + math.random() * (band[3] - band[2])
				break
			end
		end
	end
	local model, info = EnemyBuilder.Build(def, opts.Scale or size)
	local root = model.PrimaryPart :: BasePart
	local ground = opts.GroundY or services.ZoneService:GroundHeight(position)
	local rootLocalY = root.Position.Y
	model:PivotTo(CFrame.new(position.X, ground + rootLocalY + 0.1, position.Z) * CFrame.Angles(0, math.random() * math.pi * 2, 0))

	nextUid += 1
	local maxHealth = Balance.EnemyHealth(level, def.HealthMod)
	if opts.Slot and not def.IsBoss then
		maxHealth = math.max(1, math.floor(maxHealth * Balance.HordeHealth))
	end
	maxHealth = math.max(1, math.floor(maxHealth * size ^ 1.5))
	local regular = not def.IsBoss and not def.Static
	if regular then
		maxHealth = math.floor(maxHealth * Balance.RegularHealthMultiplier)
	end
	maxHealth = math.max(1, math.floor(maxHealth * (opts.HealthMult or 1)))
	local enemy = {
		Uid = nextUid,
		Model = model,
		Root = root,
		Humanoid = model:FindFirstChildOfClass("Humanoid"),
		Def = def,
		Zone = zone,
		Level = level,
		Health = maxHealth,
		MaxHealth = maxHealth,
		Damage = math.max(1, math.floor(Balance.EnemyDamage(level, def.DamageMod) * size * (if regular then Balance.RegularDamageMultiplier else 1) * (opts.DamageMult or 1) + 0.5)),
		Temple = opts.Temple,
		AggroRange = opts.Aggro,
		XP = math.max(1, math.floor(Balance.EnemyXP(level, def.XPMod) * size + 0.5)),
		Coins = Balance.EnemyCoins(level, def.CoinMod) * size * Balance.CoinRewardMultiplier,
		Home = Vector3.new(position.X, ground, position.Z),
		Slot = opts.Slot,
		IsBoss = def.IsBoss == true,
		Minion = opts.Minion == true,
		Radius = info.Radius,
		Height = info.Height,
		Contrib = {},
		LastAttack = 0,
		LastMoveOrder = 0,
		NextWander = os.clock() + math.random() * 4,
		Dead = false,
	}

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Enemies"
		end
	end
	model:SetAttribute("Uid", enemy.Uid)
	model:SetAttribute("EnemyId", def.Id)
	model:SetAttribute("DisplayName", def.Name)
	model:SetAttribute("Level", level)
	model:SetAttribute("Health", maxHealth)
	model:SetAttribute("MaxHealth", maxHealth)
	model:SetAttribute("Height", info.Height)
	model:SetAttribute("Size", size)
	model:SetAttribute("IsBoss", enemy.IsBoss)
	model:SetAttribute("Zone", zone.Id)
	-- with streaming on, send the whole rig at once so clients can animate it
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	model.Parent = zoneFolder(zone.Id)
	CollectionService:AddTag(model, "Enemy")
	if not root.Anchored then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end

	self.All[enemy.Uid] = enemy
	local list = self.ByZone[zone.Id]
	if not list then
		list = {}
		self.ByZone[zone.Id] = list
	end
	table.insert(list, enemy)
	if opts.Slot then
		opts.Slot.Current = enemy
	end
	return enemy
end

local function removeFromZone(enemy)
	local list = EnemyService.ByZone[enemy.Zone.Id]
	if list then
		for i, e in ipairs(list) do
			if e == enemy then
				table.remove(list, i)
				break
			end
		end
	end
end

-- Attack turns: only a few enemies swing at a player at once (see Balance.MaxAttackers).
local function releaseTurn(enemy)
	for _, turns in pairs(attackers) do
		turns[enemy] = nil
	end
	enemy.HasTurn = nil
end

local function takeTurn(enemy, player: Player, now: number): boolean
	local turns = attackers[player]
	if not turns then
		turns = {}
		attackers[player] = turns
	end
	local expiry = turns[enemy]
	if expiry and now < expiry then
		return true
	end
	if expiry then
		-- turn over: step back and give someone else a go
		turns[enemy] = nil
		enemy.TurnCooldown = now + 1 + math.random()
		return false
	end
	if now < (enemy.TurnCooldown or 0) then
		return false
	end
	local count = 0
	for other, t in pairs(turns) do
		if other.Dead or now >= t or other.Target ~= player then
			turns[other] = nil
		else
			count += 1
		end
	end
	if count >= Balance.MaxAttackers then
		return false
	end
	turns[enemy] = now + TOKEN_TIME + math.random()
	return true
end

function EnemyService:Get(uid: number)
	return self.All[uid]
end

-- Living enemies in a zone within `range` (+ their radius) of `position`.
function EnemyService:InRange(zoneId: string, position: Vector3, range: number)
	local results = {}
	local list = self.ByZone[zoneId]
	if not list then
		return results
	end
	for _, enemy in ipairs(list) do
		if not enemy.Dead then
			local dist = flatDistance(enemy.Root.Position, position)
			if dist <= range + enemy.Radius then
				table.insert(results, { Enemy = enemy, Distance = dist })
			end
		end
	end
	table.sort(results, function(a, b)
		return a.Distance < b.Distance
	end)
	return results
end

-- Applies damage. Returns true if this hit killed the enemy. `knockback` scales the
-- push away from `fromPosition` (1 = a normal shove); `stun` stops the enemy moving
-- and attacking for that many seconds (combo hits, finishers).
function EnemyService:Damage(enemy, player: Player, amount: number, fromPosition: Vector3?, knockback: number?, stun: number?): boolean
	if enemy.Dead then
		return false
	end
	amount = math.max(1, math.floor(amount))
	enemy.Health = math.max(0, enemy.Health - amount)
	enemy.Contrib[player] = (enemy.Contrib[player] or 0) + amount
	enemy.Model:SetAttribute("Health", enemy.Health)

	-- aggro onto whoever hits us
	if not enemy.Target and not enemy.Def.Static then
		enemy.Target = player
	end

	-- knockback and hit stun for regular enemies
	if fromPosition and not enemy.IsBoss and not enemy.Def.Static and enemy.Humanoid then
		local k = knockback or 1
		local dir = Vector3.new(enemy.Root.Position.X - fromPosition.X, 0, enemy.Root.Position.Z - fromPosition.Z)
		if dir.Magnitude > 0.01 and k > 0 then
			enemy.Root.AssemblyLinearVelocity = dir.Unit * 22 * k + Vector3.new(0, 8 * math.min(k, 1) + 6 * math.max(k - 1, 0), 0)
		end
		if stun and stun > 0 then
			enemy.StunUntil = math.max(enemy.StunUntil or 0, os.clock() + stun)
		end
	end

	if enemy.Health <= 0 then
		self:Kill(enemy, player)
		return true
	end
	return false
end

function EnemyService:Kill(enemy, killer: Player?)
	if enemy.Dead then
		return
	end
	enemy.Dead = true
	enemy.Model:SetAttribute("Dead", true)
	enemy.Model:SetAttribute("Health", 0)
	if enemy.Humanoid then
		enemy.Humanoid.WalkSpeed = 0
		enemy.Humanoid:MoveTo(enemy.Root.Position)
	end

	-- Rewards: everyone who contributed enough gets the full reward (co-op friendly).
	local threshold = enemy.MaxHealth * (if enemy.IsBoss then Balance.BossShareThreshold else Balance.RewardShareThreshold)
	local rewarded = {}
	for player, dealt in pairs(enemy.Contrib) do
		if player.Parent and (dealt >= threshold or player == killer) then
			rewarded[player] = services.ProgressionService:GrantKill(player, enemy)
		end
	end
	if services.LootService then
		local ok, err = pcall(services.LootService.OnKill, services.LootService, enemy, rewarded, killer) -- hat drops + life steal
		if not ok then
			warn("[EnemyService] loot: " .. tostring(err))
		end
	end
	if services.TokenService and next(rewarded) then
		services.TokenService:OnKill(enemy, rewarded) -- pets' combat tokens
	end
	if services.PartyService and next(rewarded) then
		services.PartyService:ShareKill(enemy, rewarded) -- partied players nearby share the XP
	end

	local position = enemy.Root.Position
	local killEffect = ""
	if killer then
		local data = services.DataService:Get(killer)
		killEffect = if data then data.Equipped.KillEffect else ""
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and (root.Position - position).Magnitude < 200 then
			Net.Event("EnemyDied"):FireClient(player, {
				Uid = enemy.Uid,
				Position = position,
				Height = enemy.Height,
				Killer = if killer then killer.UserId else 0,
				KillEffect = killEffect,
				IsBoss = enemy.IsBoss,
				Rewards = rewarded[player],
				Color = enemy.Def.Colors.Accent,
			})
		end
	end

	if enemy.IsBoss then
		services.BossService:OnBossDefeated(enemy, rewarded)
	end
	if enemy.Temple and services.TempleService then
		services.TempleService:OnEnemyKilled(enemy)
	end

	removeFromZone(enemy)
	self.All[enemy.Uid] = nil
	local model = enemy.Model
	task.delay(1.4, function()
		model:Destroy()
	end)

	releaseTurn(enemy)
	if enemy.Slot then
		local respawnMult = 1
		if killer then
			local stats = services.StatService:Get(killer)
			respawnMult = if stats then stats.RespawnMult else 1
		end
		-- the populate loop brings it back (only while players are in the zone)
		enemy.Slot.Current = nil
		enemy.Slot.ReadyAt = os.clock() + BASE_RESPAWN * respawnMult + math.random() * 1.5
	end
end

function EnemyService:SpawnSlot(slot)
	local position = randomPointInCircle(slot.Center, slot.Radius)
	return self:Spawn(slot.Enemy, slot.Level, slot.Zone, position, { Slot = slot })
end

-- ===== Zone population =====
function EnemyService:Populate(now: number)
	for zoneId, slots in pairs(self.Slots) do
		local players = services.ZoneService.PlayersIn[zoneId]
		if players and #players > 0 then
			zoneActiveUntil[zoneId] = now + EMPTY_GRACE
		end
		if now < (zoneActiveUntil[zoneId] or 0) then
			local budget = SPAWNS_PER_TICK
			for _, slot in ipairs(slots) do
				if budget <= 0 then
					break
				end
				if not slot.Current and now >= slot.ReadyAt then
					budget -= 1
					self:SpawnSlot(slot)
				end
			end
		elseif zoneActiveUntil[zoneId] then
			-- nobody here any more: clear the crowd (bosses are BossService's)
			zoneActiveUntil[zoneId] = nil
			for _, slot in ipairs(slots) do
				local enemy = slot.Current
				if enemy and not enemy.Dead then
					enemy.Dead = true
					releaseTurn(enemy)
					removeFromZone(enemy)
					self.All[enemy.Uid] = nil
					enemy.Model:Destroy()
				end
				slot.Current = nil
				slot.ReadyAt = 0
			end
		end
	end
end

-- ===== AI =====
local function acquireTarget(enemy, players: { Player })
	local pos = enemy.Root.Position
	local best, bestDist = nil, enemy.AggroRange or enemy.Def.AggroRange
	for _, player in ipairs(players) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local d = flatDistance(root.Position, pos)
			if d < bestDist and flatDistance(root.Position, enemy.Home) < 60 then
				best, bestDist = player, d
			end
		end
	end
	return best
end

local function targetRoot(player: Player?): BasePart?
	if not player or not player.Parent then
		return nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function EnemyService:EnemyAttack(enemy, player: Player)
	enemy.LastAttack = os.clock()
	enemy.Model:SetAttribute("AttackTick", (enemy.Model:GetAttribute("AttackTick") or 0) + 1)
	-- the hit lands after a readable windup (Balance.EnemyWindup), in time with the
	-- client's swing animation; a dodge's i-frames make it miss
	task.delay(Balance.EnemyWindup, function()
		if enemy.Dead or os.clock() < (enemy.StunUntil or 0) then
			return -- a finisher or combo hit interrupted the swing
		end
		local root = targetRoot(player)
		if not root then
			return
		end
		if flatDistance(root.Position, enemy.Root.Position) <= enemy.Radius + 6.5 then
			local humanoid = (player.Character :: Model):FindFirstChildOfClass("Humanoid")
			if humanoid and not (player.Character :: Model):FindFirstChildOfClass("ForceField") and not services.CombatService:IsInvulnerable(player)
				and not services.CombatService:Guarded(player, humanoid, enemy.Damage) then
				humanoid:TakeDamage(enemy.Damage)
				Net.Event("PlayerHurt"):FireClient(player, enemy.Damage, enemy.Root.Position)
			end
		end
	end)
end

local function stepEnemy(enemy, players: { Player }, now: number)
	if enemy.Dead or enemy.Def.Static or enemy.IsBoss or not enemy.Humanoid then
		return
	end
	if now < (enemy.StunUntil or 0) then
		return -- reeling from a hit: no walking (it would cancel the knockback) and no attacks
	end
	local pos = enemy.Root.Position

	-- validate / acquire target
	local tRoot = targetRoot(enemy.Target)
	if tRoot and (flatDistance(tRoot.Position, enemy.Home) > 65 or flatDistance(tRoot.Position, pos) > 70) then
		releaseTurn(enemy)
		enemy.Target = nil
		tRoot = nil
	end
	if not tRoot then
		enemy.Target = acquireTarget(enemy, players)
		tRoot = targetRoot(enemy.Target)
	end

	if tRoot then
		local dist = flatDistance(tRoot.Position, pos)
		local reach = enemy.Radius + 4.5
		if dist <= reach + 8 and not takeTurn(enemy, enemy.Target, now) then
			-- waiting for a turn: hold a spot in the ring round the player
			if now - enemy.LastMoveOrder > 0.5 then
				enemy.LastMoveOrder = now
				local away = Vector3.new(pos.X - tRoot.Position.X, 0, pos.Z - tRoot.Position.Z)
				away = if away.Magnitude > 0.1 then away.Unit else Vector3.new(1, 0, 0)
				local ring = reach + 5 + (enemy.Uid % 3) * 3
				local angle = math.rad(((enemy.Uid * 37) % 41) - 20) * 0.5
				local spot = tRoot.Position + (CFrame.Angles(0, angle, 0) * away) * ring
				enemy.Humanoid:MoveTo(spot)
			end
			return
		end
		if dist > reach then
			if now - enemy.LastMoveOrder > 0.3 then
				enemy.LastMoveOrder = now
				enemy.Humanoid:MoveTo(tRoot.Position)
			end
		else
			if now - enemy.LastMoveOrder > 0.3 then
				enemy.LastMoveOrder = now
				enemy.Humanoid:MoveTo(pos)
			end
			local lookAt = Vector3.new(tRoot.Position.X, pos.Y, tRoot.Position.Z)
			if (lookAt - pos).Magnitude > 0.1 then
				enemy.Root.CFrame = CFrame.lookAt(pos, lookAt)
			end
			if now - enemy.LastAttack >= enemy.Def.AttackCooldown then
				EnemyService:EnemyAttack(enemy, enemy.Target)
			end
		end
	else
		local homeDist = flatDistance(pos, enemy.Home)
		if homeDist > 6 and now - enemy.LastMoveOrder > 1 then
			enemy.LastMoveOrder = now
			enemy.Humanoid:MoveTo(enemy.Home)
		elseif now > enemy.NextWander then
			enemy.NextWander = now + 3 + math.random() * 5
			enemy.LastMoveOrder = now
			enemy.Humanoid:MoveTo(randomPointInCircle(enemy.Home, 9))
		end
	end
end

local accumulator = 0
local function aiLoop(dt: number)
	accumulator += dt
	if accumulator < AI_TICK then
		return
	end
	accumulator = 0
	local now = os.clock()
	for zoneId, list in pairs(EnemyService.ByZone) do
		local players = services.ZoneService.PlayersIn[zoneId]
		if players and #players > 0 then
			for i = #list, 1, -1 do
				local enemy = list[i]
				if enemy then
					local ok, err = pcall(stepEnemy, enemy, players, now)
					if not ok then
						warn("[EnemyService] AI error: " .. tostring(err))
					end
				end
			end
		end
	end
end

function EnemyService:Init(registry)
	services = registry
	folder = Instance.new("Folder")
	folder.Name = "Enemies"
	folder.Parent = workspace
end

function EnemyService:Start()
	-- Camp slots for every zone (Count x density; static training dummies stay as they are).
	for _, zone in ipairs(Zones.List) do
		local slots = {}
		for _, camp in ipairs(zone.Camps) do
			local def = Enemies.Get(camp.Enemy)
			local horde = def and not def.Static
			local center = Zones.WorldPosition(zone, camp.Offset)
			local count = if horde then camp.Count * Balance.EnemyDensity else camp.Count
			local radius = if horde then camp.Radius * Balance.CampSpread else camp.Radius
			for _ = 1, count do
				table.insert(slots, { Enemy = camp.Enemy, Level = camp.Level, Zone = zone, Center = center, Radius = radius, ReadyAt = 0 })
			end
		end
		self.Slots[zone.Id] = slots
	end
	RunService.Heartbeat:Connect(aiLoop)

	-- Fill zones with players in them a batch at a time; empty the ones left behind.
	task.spawn(function()
		while true do
			task.wait(0.25)
			local ok, err = pcall(function()
				self:Populate(os.clock())
			end)
			if not ok then
				warn("[EnemyService] populate error: " .. tostring(err))
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		attackers[player] = nil
	end)

	-- Safety net: enemies that fall out of the world or wander far away are recycled.
	task.spawn(function()
		while true do
			task.wait(5)
			for _, enemy in pairs(self.All) do
				if not enemy.Dead and enemy.Root.Parent and (enemy.Root.Position.Y < enemy.Home.Y - 50 or flatDistance(enemy.Root.Position, enemy.Home) > 120) then
					enemy.Root.CFrame = CFrame.new(enemy.Home + Vector3.new(0, 6, 0))
					enemy.Target = nil
				end
			end
		end
	end)
end

return EnemyService
