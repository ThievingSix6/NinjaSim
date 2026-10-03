--[[
	BossService: one boss per zone, spawned on a timer in the zone's arena and
	announced server-wide. Bosses fight with telegraphed attacks that players can
	dodge (the server resolves damage using the same shapes the client draws):

	  Slam       - circle around the boss
	  Shockwave  - ring (safe right next to the boss or far away)
	  Barrage    - circles dropped on every player's position
	  Dash       - line charge toward the target
	  Summon     - calls minions at 66% and 33% health

	Below 35% health the boss enrages: faster attacks and movement.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Enemies = require(Shared.Config.Enemies)
local Net = require(Shared.Net)

local BossService = {}
BossService.Active = {} :: { [string]: any } -- zoneId -> boss enemy

local services
local timers: { [string]: number } = {}
local ARENA_RADIUS = 75
local FIRST_SPAWN_DELAY = 30

-- Ground distance; things on different levels (the Cursed Temple's halls under the
-- valley) never count as near.
local function flat(a: Vector3, b: Vector3): number
	if math.abs(a.Y - b.Y) > 60 then
		return math.huge
	end
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function playersNear(position: Vector3, radius: number): { Player }
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 and flat(root.Position, position) <= radius then
			table.insert(list, player)
		end
	end
	return list
end

local function hurt(player: Player, amount: number, from: Vector3, knock: number?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 or (character :: Model):FindFirstChildOfClass("ForceField") then
		return
	end
	if services.CombatService:IsInvulnerable(player) then
		return -- rolled through it
	end
	if services.CombatService:Guarded(player, humanoid, amount) then
		return -- Phoenix Rebirth took the blow
	end
	humanoid:TakeDamage(amount)
	Net.Event("PlayerHurt"):FireClient(player, amount, from, true)
	if knock and knock > 0 then
		local dir = Vector3.new(root.Position.X - from.X, 0, root.Position.Z - from.Z)
		dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.new(1, 0, 0)
		root.AssemblyLinearVelocity = dir * knock + Vector3.new(0, knock * 0.8, 0)
	end
end

local function telegraph(boss, payload)
	payload.Uid = boss.Uid
	payload.Color = boss.Def.Colors.Accent
	for _, player in ipairs(playersNear(boss.Home, ARENA_RADIUS + 80)) do
		Net.Event("BossTelegraph"):FireClient(player, payload)
	end
end

local function holdStill(boss, seconds: number)
	if boss.Humanoid then
		boss.Humanoid.WalkSpeed = 0
		boss.Humanoid:MoveTo(boss.Root.Position)
	end
	task.wait(seconds)
	if boss.Humanoid and not boss.Dead then
		boss.Humanoid.WalkSpeed = boss.Def.Speed * (if boss.Enraged then 1.35 else 1)
	end
end

local attacks = {}

function attacks.Slam(boss)
	local radius = 14 + boss.Def.Scale * 1.5
	local windup = if boss.Enraged then 0.9 else 1.2
	local center = boss.Root.Position
	boss.Model:SetAttribute("AttackTick", (boss.Model:GetAttribute("AttackTick") or 0) + 1)
	telegraph(boss, { Kind = "Circle", Position = center, Radius = radius, Duration = windup })
	holdStill(boss, windup)
	if boss.Dead then
		return
	end
	for _, player in ipairs(playersNear(center, radius)) do
		hurt(player, boss.Damage * 2.2, center, 45)
	end
end

function attacks.Shockwave(boss)
	local inner, outer = 9, 34
	local windup = if boss.Enraged then 1.1 else 1.4
	local center = boss.Root.Position
	boss.Model:SetAttribute("AttackTick", (boss.Model:GetAttribute("AttackTick") or 0) + 1)
	telegraph(boss, { Kind = "Ring", Position = center, Inner = inner, Radius = outer, Duration = windup })
	holdStill(boss, windup)
	if boss.Dead then
		return
	end
	for _, player in ipairs(playersNear(center, outer)) do
		local root = (player.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart
		if flat(root.Position, center) >= inner then
			hurt(player, boss.Damage * 1.8, center, 35)
		end
	end
end

function attacks.Barrage(boss)
	local windup = if boss.Enraged then 1.0 else 1.3
	local radius = 8
	local points = {}
	for _, player in ipairs(playersNear(boss.Home, ARENA_RADIUS)) do
		local root = (player.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart
		table.insert(points, Vector3.new(root.Position.X, boss.Home.Y, root.Position.Z))
		if #points >= 6 then
			break
		end
	end
	for _ = 1, (if boss.Enraged then 5 else 3) do
		local a = math.random() * math.pi * 2
		local r = math.random() * ARENA_RADIUS * 0.6
		table.insert(points, boss.Home + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
	end
	for _, p in ipairs(points) do
		p = Vector3.new(p.X, services.ZoneService:GroundHeight(p), p.Z)
		telegraph(boss, { Kind = "Meteor", Position = p, Radius = radius, Duration = windup })
	end
	boss.Model:SetAttribute("AttackTick", (boss.Model:GetAttribute("AttackTick") or 0) + 1)
	holdStill(boss, windup)
	if boss.Dead then
		return
	end
	for _, p in ipairs(points) do
		for _, player in ipairs(playersNear(p, radius)) do
			hurt(player, boss.Damage * 1.6, p, 25)
		end
	end
end

function attacks.Dash(boss)
	local target = boss.Target
	local character = target and target.Character
	local troot = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not troot then
		return attacks.Slam(boss)
	end
	local start = boss.Root.Position
	local dir = Vector3.new(troot.Position.X - start.X, 0, troot.Position.Z - start.Z)
	dir = if dir.Magnitude > 0.1 then dir.Unit else boss.Root.CFrame.LookVector
	local length, width = 46, 11
	local windup = if boss.Enraged then 0.7 else 0.95
	boss.Root.CFrame = CFrame.lookAt(start, start + dir)
	telegraph(boss, { Kind = "Line", Position = start, Direction = dir, Length = length, Width = width, Duration = windup })
	holdStill(boss, windup)
	if boss.Dead then
		return
	end
	-- charge: move the boss along the line quickly
	local finish = start + dir * length
	local steps = 8
	for i = 1, steps do
		if boss.Dead then
			return
		end
		local p = start:Lerp(finish, i / steps)
		boss.Root.CFrame = CFrame.lookAt(Vector3.new(p.X, boss.Root.Position.Y, p.Z), Vector3.new(p.X, boss.Root.Position.Y, p.Z) + dir)
		task.wait(0.03)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local c = player.Character
		local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local rel = root.Position - start
			if math.abs(rel.Y) > 60 then
				continue -- another level (the temple halls below)
			end
			local along = rel:Dot(dir)
			local side = (rel - dir * along)
			side = Vector3.new(side.X, 0, side.Z)
			if along >= -2 and along <= length + 2 and side.Magnitude <= width / 2 + 1 then
				hurt(player, boss.Damage * 2, root.Position - dir * 3, 40)
			end
		end
	end
end

function attacks.Summon(boss)
	local minionId = boss.Def.Minion
	if not minionId or not Enemies.Get(minionId) then
		return
	end
	boss.Model:SetAttribute("AttackTick", (boss.Model:GetAttribute("AttackTick") or 0) + 1)
	telegraph(boss, { Kind = "Summon", Position = boss.Root.Position, Radius = 12, Duration = 1 })
	holdStill(boss, 1)
	if boss.Dead then
		return
	end
	boss.Minions = boss.Minions or {}
	for i = 1, 3 do
		local a = i * math.pi * 2 / 3
		local pos = boss.Root.Position + Vector3.new(math.cos(a) * 9, 0, math.sin(a) * 9)
		local minion = services.EnemyService:Spawn(minionId, math.max(1, boss.Level - 8), boss.Zone, pos, { Minion = true })
		if minion then
			minion.Target = boss.Target
			table.insert(boss.Minions, minion)
		end
	end
end

local function chooseAttack(boss): string
	local list = boss.Def.Attacks or { "Slam" }
	local options = {}
	for _, name in ipairs(list) do
		if name ~= "Summon" and name ~= boss.LastAttackName then
			table.insert(options, name)
		end
	end
	if #options == 0 then
		return list[1]
	end
	return options[math.random(1, #options)]
end

function BossService:SpawnBoss(zone)
	local bossInfo = zone.Boss
	local pos = Zones.WorldPosition(zone, zone.BossOffset)
	local boss = services.EnemyService:Spawn(bossInfo.Enemy, bossInfo.Level, zone, pos, {})
	if not boss then
		return
	end
	boss.Home = Vector3.new(pos.X, boss.Home.Y, pos.Z)
	boss.NextSpecial = os.clock() + 3
	boss.Busy = false
	boss.SummonStage = 0
	boss.Enraged = false
	self.Active[zone.Id] = boss
	-- only the players in that area hear about it
	for _, player in ipairs(services.ZoneService.PlayersIn[zone.Id] or {}) do
		Net.Event("BossEvent"):FireClient(player, {
			Type = "Spawn", Name = boss.Def.Name, Zone = zone.Name, ZoneId = zone.Id, Color = boss.Def.Colors.Accent,
		})
	end
end

-- Floor bosses of the Cursed Temple (TempleService): stepped with the zone bosses but
-- not tied to a zone's arena or respawn timer.
local managed: { any } = {}
function BossService:Manage(boss)
	boss.NextSpecial = os.clock() + 3
	boss.Busy = false
	boss.SummonStage = 0
	boss.Enraged = false
	boss.Managed = true
	table.insert(managed, boss)
end

function BossService:OnBossDefeated(boss, rewarded)
	if boss.Managed then
		local i = table.find(managed, boss)
		if i then
			table.remove(managed, i)
		end
		if boss.Minions then
			for _, minion in ipairs(boss.Minions) do
				if not minion.Dead then
					services.EnemyService:Kill(minion, nil)
				end
			end
		end
		return
	end
	local zone = boss.Zone
	self.Active[zone.Id] = nil
	timers[zone.Id] = os.clock() + zone.Boss.Respawn
	if boss.Minions then
		for _, minion in ipairs(boss.Minions) do
			if not minion.Dead then
				services.EnemyService:Kill(minion, nil)
			end
		end
	end
	local names = {}
	for player in pairs(rewarded) do
		table.insert(names, player.DisplayName)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		Net.Event("BossEvent"):FireClient(player, {
			Type = "Defeated", Name = boss.Def.Name, Zone = zone.Name, Color = boss.Def.Colors.Accent,
			By = table.concat(names, ", "),
		})
	end
end

function BossService:TimeUntilSpawn(zoneId: string): number
	if self.Active[zoneId] then
		return 0
	end
	return math.max(0, (timers[zoneId] or 0) - os.clock())
end

local function stepBoss(boss, now: number)
	if boss.Dead or boss.Busy then
		return
	end
	-- enrage
	local ratio = boss.Health / boss.MaxHealth
	if not boss.Enraged and ratio < 0.35 then
		boss.Enraged = true
		boss.Model:SetAttribute("Enraged", true)
		if boss.Humanoid then
			boss.Humanoid.WalkSpeed = boss.Def.Speed * 1.35
		end
		for _, player in ipairs(playersNear(boss.Home, ARENA_RADIUS + 80)) do
			Net.Event("BossEvent"):FireClient(player, { Type = "Enrage", Name = boss.Def.Name, Color = boss.Def.Colors.Accent })
		end
	end
	-- summon thresholds
	local hasSummon = table.find(boss.Def.Attacks or {}, "Summon") ~= nil
	if hasSummon and ((boss.SummonStage == 0 and ratio < 0.66) or (boss.SummonStage == 1 and ratio < 0.33)) then
		boss.SummonStage += 1
		boss.Busy = true
		task.spawn(function()
			attacks.Summon(boss)
			boss.Busy = false
		end)
		return
	end

	local fighters = playersNear(boss.Home, ARENA_RADIUS)
	if #fighters == 0 then
		boss.Target = nil
		if flat(boss.Root.Position, boss.Home) > 5 and boss.Humanoid then
			boss.Humanoid:MoveTo(boss.Home)
		end
		-- slowly heal when nobody is fighting
		if boss.Health < boss.MaxHealth then
			boss.Health = math.min(boss.MaxHealth, boss.Health + boss.MaxHealth * 0.01)
			boss.Model:SetAttribute("Health", boss.Health)
		end
		return
	end

	-- target: keep current if still in the arena, else nearest
	local current = boss.Target
	if not (current and table.find(fighters, current)) then
		local best, bestDist = nil, math.huge
		for _, player in ipairs(fighters) do
			local root = (player.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart
			local d = flat(root.Position, boss.Root.Position)
			if d < bestDist then
				best, bestDist = player, d
			end
		end
		boss.Target = best
	end
	local troot = boss.Target and (boss.Target.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
	if not troot then
		return
	end

	if now >= boss.NextSpecial then
		local name = chooseAttack(boss)
		boss.LastAttackName = name
		boss.Busy = true
		task.spawn(function()
			local ok, err = pcall(attacks[name], boss)
			if not ok then
				warn("[BossService] " .. name .. " failed: " .. tostring(err))
			end
			boss.Busy = false
			boss.NextSpecial = os.clock() + (if boss.Enraged then 2 else 3.2) + math.random()
		end)
		return
	end

	local dist = flat(troot.Position, boss.Root.Position)
	if dist > boss.Radius + 6 then
		if boss.Humanoid then
			boss.Humanoid:MoveTo(troot.Position)
		end
	elseif now - boss.LastAttack >= boss.Def.AttackCooldown then
		services.EnemyService:EnemyAttack(boss, boss.Target)
	end
end

function BossService:Init(registry)
	services = registry
end

function BossService:Start()
	for _, zone in ipairs(Zones.List) do
		if zone.Boss then
			timers[zone.Id] = os.clock() + FIRST_SPAWN_DELAY + (zone.Index - 1) * 5
		end
	end
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.2 then
			return
		end
		acc = 0
		local now = os.clock()
		for i = #managed, 1, -1 do
			local boss = managed[i]
			if boss.Dead or not boss.Model.Parent then
				table.remove(managed, i)
			else
				local ok, err = pcall(stepBoss, boss, now)
				if not ok then
					warn("[BossService] " .. tostring(err))
				end
			end
		end
		for _, zone in ipairs(Zones.List) do
			local boss = self.Active[zone.Id]
			if boss then
				local ok, err = pcall(stepBoss, boss, now)
				if not ok then
					warn("[BossService] " .. tostring(err))
				end
			elseif zone.Boss and timers[zone.Id] and now >= timers[zone.Id] then
				timers[zone.Id] = nil
				self:SpawnBoss(zone)
			end
		end
	end)
end

return BossService
