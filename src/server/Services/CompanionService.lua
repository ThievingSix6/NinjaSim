--[[
	CompanionService: hired ninjas (Config/Hires) fighting beside their players.

	Hire(player, id) buys one for good; SetActive(player, id) picks the one who fights
	("" sends them home). The active hire is a rig from EnemyBuilder (tagged
	"Companion": clients animate it like an enemy, it is never a target for your aim)
	that follows you, picks fights within Hires.EngageRange of you, attacks on its own
	beat (melee, or thrown shurikens for Ranged hires) and fires its skill on cooldown.
	Its hits count as yours (EnemyService:Damage with you as the attacker), so kills
	pay you as usual. Enemies can turn on it (EnemyService treats it as a target); at
	0 health it is knocked out for Hires.Respawn seconds, then gets back up at your side.
	Its stats come from yours and its own charm grid (Hires.Stats, Charms.Bonus(data, id)).

	Events: "Companion" { Type = "Attack" | "Shuriken" | "Skill" | "Down" | "Up", ... }
	to players nearby (visuals), and "Hurt" to the owner.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Hires = require(Shared.Config.Hires)
local Charms = require(Shared.Config.Charms)
local Tokens = require(Shared.Config.Tokens)
local EnemyBuilder = require(Shared.Visuals.EnemyBuilder)
local Net = require(Shared.Net)
local Balance = require(Shared.Config.Balance)

local CompanionService = {}

local services
local rng = Random.new()
local TICK = 0.15
local WINDUP = Balance.EnemyWindup -- the swing animation (shared with enemies) lands then

export type Companion = {
	Companion: true, Owner: Player, Def: any, Model: Model, Root: BasePart, Humanoid: Humanoid,
	Health: number, MaxHealth: number, Stats: any, Target: any?, LastAttack: number, SkillReadyAt: number,
	LastMove: number, Dead: boolean, DownUntil: number, Radius: number,
}
local companions: { [Player]: Companion } = {}

local function folder(): Instance
	local f = workspace:FindFirstChild("Companions")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Companions"
		f.Parent = workspace
	end
	return f
end

local function rootOf(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and humanoid and humanoid.Health > 0 then
		return root, humanoid
	end
	return nil, nil
end

local function flat(a: Vector3, b: Vector3): number
	if math.abs(a.Y - b.Y) > 40 then
		return math.huge
	end
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- To players near `position` (visuals).
local function broadcast(position: Vector3, payload)
	for _, player in ipairs(Players:GetPlayers()) do
		local root = rootOf(player)
		if root and (root.Position - position).Magnitude < 160 then
			Net.Event("Companion"):FireClient(player, payload)
		end
	end
end

local function computeStats(player: Player, def)
	local data = services.DataService:Get(player)
	local stats = services.StatService:Get(player)
	if not data or not stats then
		return nil
	end
	return Hires.Stats(def, stats, Charms.Bonus(data, def.Id))
end

local function setHealth(c: Companion, value: number)
	c.Health = math.clamp(value, 0, c.MaxHealth)
	c.Model:SetAttribute("Health", math.floor(c.Health))
	c.Model:SetAttribute("MaxHealth", c.MaxHealth)
end

local function despawn(player: Player)
	local c = companions[player]
	if c then
		companions[player] = nil
		c.Dead = true
		c.Model:Destroy()
	end
end

local function spawnFor(player: Player)
	despawn(player)
	local data = services.DataService:Get(player)
	local def = data and Hires.Get(data.ActiveHire)
	local root = rootOf(player)
	if not def or not root or not data.Hires[def.Id] then
		return
	end
	local stats = computeStats(player, def)
	if not stats then
		return
	end
	local model, info = EnemyBuilder.Build(Hires.RigDef(def), 1)
	model.Name = def.Name
	local mRoot = model.PrimaryPart :: BasePart
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local at = root.Position - root.CFrame.LookVector * 5 + root.CFrame.RightVector * 4
	model:PivotTo(CFrame.new(at.X, root.Position.Y - 3 + mRoot.Position.Y, at.Z))
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Enemies" -- doesn't body-block players
		end
	end
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("HireId", def.Id)
	model:SetAttribute("DisplayName", def.Name)
	model:SetAttribute("Height", info.Height)
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	model.Parent = folder()
	CollectionService:AddTag(model, "Companion")
	pcall(function()
		mRoot:SetNetworkOwner(nil)
	end)
	humanoid.WalkSpeed = stats.Speed
	local c: Companion = {
		Companion = true, Owner = player, Def = def, Model = model, Root = mRoot, Humanoid = humanoid,
		Health = stats.MaxHealth, MaxHealth = stats.MaxHealth, Stats = stats, Target = nil,
		LastAttack = 0, SkillReadyAt = os.clock() + 3, LastMove = 0, Dead = false, DownUntil = 0, Radius = info.Radius,
	}
	companions[player] = c
	setHealth(c, c.MaxHealth)
end

-- ===== requests =====
function CompanionService:Hire(player: Player, id: string?): (boolean, string?)
	local data = services.DataService:Get(player)
	local def = Hires.Get(id)
	if not data or not def then
		return false, "Unknown ninja"
	end
	if data.Hires[def.Id] then
		return false, "Already hired"
	end
	if data.Level < def.Level then
		return false, "Reach Level " .. def.Level .. " to hire " .. def.Name
	end
	if not services.DataService:Spend(player, "Coins", Hires.Price(def)) then
		return false, "Not enough Coins"
	end
	data.Hires[def.Id] = true
	services.DataService:Changed(player, "Hires")
	if data.ActiveHire == "" then
		self:SetActive(player, def.Id)
	end
	return true, def.Name .. " joins you!"
end

function CompanionService:SetActive(player: Player, id: string): (boolean, string?)
	local data = services.DataService:Get(player)
	if not data then
		return false, "Still loading"
	end
	if id ~= "" and not data.Hires[id] then
		return false, "Hire them first"
	end
	data.ActiveHire = id
	services.DataService:Changed(player, "ActiveHire")
	if id == "" then
		despawn(player)
	else
		spawnFor(player)
	end
	return true, nil
end

function CompanionService:Get(player: Player): Companion?
	return companions[player]
end

-- Companions fighting in a zone (EnemyService picks targets from these too).
function CompanionService:InZone(zoneId: string): { Companion }
	local out = {}
	for player, c in pairs(companions) do
		if not c.Dead and player:GetAttribute("Zone") == zoneId then
			table.insert(out, c)
		end
	end
	return out
end

-- An enemy's hit lands on a companion.
function CompanionService:Hurt(c: Companion, amount: number)
	if c.Dead or os.clock() < c.DownUntil then
		return
	end
	setHealth(c, c.Health - amount)
	broadcast(c.Root.Position, { Type = "Hurt", Model = c.Model, Amount = amount })
	if c.Health <= 0 then
		c.DownUntil = os.clock() + Hires.Respawn
		c.Target = nil
		c.Model:SetAttribute("Down", true)
		c.Humanoid:MoveTo(c.Root.Position)
		broadcast(c.Root.Position, { Type = "Down", Model = c.Model })
		if c.Owner.Parent then
			Net.Event("Notify"):FireClient(c.Owner, { Text = c.Def.Name .. " is down! Back in " .. Hires.Respawn .. "s", Color = Color3.fromRGB(255, 150, 120), Side = true })
		end
	end
end

-- ===== combat =====
local function damageEnemy(c: Companion, enemy, mult: number, knockback: number?, stun: number?)
	if enemy.Dead or not c.Owner.Parent then
		return
	end
	local s = c.Stats
	local crit = rng:NextNumber() < s.Crit
	local amount = s.Damage * mult * (0.9 + rng:NextNumber() * 0.2)
	if crit then
		amount *= s.CritMult
	end
	amount = math.max(1, math.floor(amount))
	services.EnemyService:Damage(enemy, c.Owner, amount, c.Root.Position, knockback or 0.3, stun or 0.1, c)
	if s.LifeSteal > 0 then
		setHealth(c, c.Health + amount * s.LifeSteal)
	end
	broadcast(enemy.Root.Position, { Type = "Hit", Position = enemy.Root.Position, Damage = amount, Crit = crit, Uid = enemy.Uid, Owner = c.Owner.UserId })
	-- hired ninjas drop combat tokens too
	if services.TokenService and rng:NextNumber() < (c.Def.TokenChance or 0) * mult ^ 0.5 then
		local kind = if c.Def.RareToken and rng:NextNumber() < 0.08 then c.Def.RareToken else c.Def.Token
		if Tokens.Get(kind) then
			services.TokenService:Spawn(c.Owner, kind, enemy.Root.Position, enemy.Level or 1, c.Def.Name)
		end
	end
end

local function enemiesNear(c: Companion, position: Vector3, radius: number): { any }
	local zone = services.ZoneService:GetZone(c.Owner)
	local out = {}
	for _, entry in ipairs(services.EnemyService:InRange(zone.Id, position, radius)) do
		if not entry.Enemy.Dead and math.abs(entry.Enemy.Root.Position.Y - position.Y) < 30 then
			table.insert(out, entry.Enemy)
		end
	end
	return out
end

local function useSkill(c: Companion, target): boolean
	local skill = c.Def.Skill
	local pos = c.Root.Position
	if skill.Kind == "Heal" then
		local root, humanoid = rootOf(c.Owner)
		if not root or not humanoid or humanoid.Health > humanoid.MaxHealth * 0.7 then
			return false
		end
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * skill.Amount)
		setHealth(c, c.Health + c.MaxHealth * skill.Amount)
		broadcast(pos, { Type = "Skill", Kind = "Heal", Position = root.Position, From = pos, Model = c.Model })
		return true
	end
	if not target or target.Dead then
		return false
	end
	local tpos = target.Root.Position
	if skill.Kind == "Whirlwind" then
		local hits = enemiesNear(c, pos, skill.Radius)
		if #hits == 0 then
			return false
		end
		for _, enemy in ipairs(hits) do
			damageEnemy(c, enemy, skill.Mult, 1, 0.3)
		end
		broadcast(pos, { Type = "Skill", Kind = "Whirlwind", Position = pos, Radius = skill.Radius, Model = c.Model })
	elseif skill.Kind == "Fan" then
		local hits = enemiesNear(c, pos, skill.Radius)
		local targets = {}
		for i = 1, math.min(skill.Targets, #hits) do
			local enemy = hits[i]
			table.insert(targets, enemy.Root.Position)
			task.delay(0.25, function()
				damageEnemy(c, enemy, skill.Mult, 0.4, 0.2)
			end)
		end
		broadcast(pos, { Type = "Skill", Kind = "Fan", Position = pos, Targets = targets, Model = c.Model })
	elseif skill.Kind == "Fire" then
		broadcast(tpos, { Type = "Skill", Kind = "Fire", Position = tpos, Radius = skill.Radius, Model = c.Model })
		task.delay(0.45, function()
			for _, enemy in ipairs(enemiesNear(c, tpos, skill.Radius)) do
				damageEnemy(c, enemy, skill.Mult, 0.8, 0.3)
			end
		end)
	elseif skill.Kind == "Shadow" then
		local behind = tpos + target.Root.CFrame.LookVector * -(target.Radius + 3)
		broadcast(pos, { Type = "Skill", Kind = "Shadow", Position = pos, To = behind, Model = c.Model })
		c.Root.CFrame = CFrame.lookAt(Vector3.new(behind.X, pos.Y, behind.Z), Vector3.new(tpos.X, pos.Y, tpos.Z))
		c.Model:SetAttribute("AttackTick", (c.Model:GetAttribute("AttackTick") or 0) + 1)
		task.delay(0.15, function()
			damageEnemy(c, target, skill.Mult, 1.2, 0.5)
		end)
	elseif skill.Kind == "Slam" then
		local hits = enemiesNear(c, pos, skill.Radius)
		if #hits == 0 then
			return false
		end
		c.Model:SetAttribute("AttackTick", (c.Model:GetAttribute("AttackTick") or 0) + 1)
		broadcast(pos, { Type = "Skill", Kind = "Slam", Position = pos, Radius = skill.Radius, Model = c.Model })
		task.delay(0.3, function()
			for _, enemy in ipairs(hits) do
				damageEnemy(c, enemy, skill.Mult, 1.5, skill.Stun)
				if not enemy.Dead and not enemy.IsBoss then
					services.EnemyService:Taunt(enemy, c)
				end
			end
		end)
	end
	return true
end

local function pickTarget(c: Companion, ownerRoot: BasePart)
	local current = c.Target
	if current and not current.Dead and flat(current.Root.Position, ownerRoot.Position) <= Hires.EngageRange + 10 then
		return current
	end
	local best, bestDist = nil, math.huge
	for _, enemy in ipairs(enemiesNear(c, ownerRoot.Position, Hires.EngageRange)) do
		if not enemy.Def.Static or enemy.Def.Id == "TrainingDummy" then
			local d = flat(enemy.Root.Position, c.Root.Position)
			if d < bestDist then
				best, bestDist = enemy, d
			end
		end
	end
	return best
end

local function step(c: Companion, now: number)
	local owner = c.Owner
	local ownerRoot = rootOf(owner)
	if not ownerRoot then
		return
	end
	local pos = c.Root.Position
	-- knocked out: lie there, then get up beside the owner
	if c.DownUntil > 0 then
		if now < c.DownUntil then
			return
		end
		c.DownUntil = 0
		c.Model:SetAttribute("Down", nil)
		setHealth(c, c.MaxHealth)
		c.Model:PivotTo(CFrame.new(ownerRoot.Position + ownerRoot.CFrame.RightVector * 4 - ownerRoot.CFrame.LookVector * 3))
		broadcast(ownerRoot.Position, { Type = "Up", Model = c.Model })
		return
	end
	-- regen out of combat, and from charms
	if c.Stats.Regen > 0 or not c.Target then
		setHealth(c, c.Health + c.MaxHealth * (c.Stats.Regen + (if c.Target then 0 else 0.02)) * TICK)
	end
	-- left behind (teleports, zones, the temple): catch up at once
	if flat(pos, ownerRoot.Position) > Hires.Leash then
		c.Model:PivotTo(CFrame.new(ownerRoot.Position - ownerRoot.CFrame.LookVector * 4))
		c.Target = nil
		return
	end
	local target = pickTarget(c, ownerRoot)
	c.Target = target
	if now >= c.SkillReadyAt and (target or c.Def.Skill.Kind == "Heal") then
		if useSkill(c, target) then
			c.SkillReadyAt = now + c.Def.Skill.Cooldown
			c.LastAttack = now
			return
		end
	end
	if target then
		local tpos = target.Root.Position
		local dist = flat(tpos, pos)
		local reach = if c.Def.Range then c.Def.Range else target.Radius + (c.Def.Reach or 5) + 1
		if dist > reach then
			if now - c.LastMove > 0.25 then
				c.LastMove = now
				local toward = if c.Def.Range then tpos + (pos - tpos).Unit * (c.Def.Range * 0.7) else tpos
				c.Humanoid:MoveTo(toward)
			end
		else
			if now - c.LastMove > 0.3 then
				c.LastMove = now
				c.Humanoid:MoveTo(pos)
			end
			local look = Vector3.new(tpos.X, pos.Y, tpos.Z)
			if (look - pos).Magnitude > 0.1 then
				c.Root.CFrame = CFrame.lookAt(pos, look)
			end
			if now - c.LastAttack >= c.Stats.Interval then
				c.LastAttack = now
				c.Model:SetAttribute("AttackTick", (c.Model:GetAttribute("AttackTick") or 0) + 1)
				if c.Def.Range then
					broadcast(pos, { Type = "Shuriken", From = pos + Vector3.new(0, 1.5, 0), To = tpos, Model = c.Model })
					task.delay(math.min(0.5, dist / 70), function()
						damageEnemy(c, target, 1, 0.2, 0.05)
					end)
				else
					task.delay(WINDUP, function()
						if not c.Dead and c.DownUntil == 0 and not target.Dead and flat(target.Root.Position, c.Root.Position) <= reach + 3 then
							damageEnemy(c, target, 1, 0.3, 0.1)
						end
					end)
				end
			end
		end
	else
		-- follow: a spot behind and to the side of the owner
		local spot = ownerRoot.Position - ownerRoot.CFrame.LookVector * Hires.FollowDistance + ownerRoot.CFrame.RightVector * 4
		if flat(spot, pos) > 3 and now - c.LastMove > 0.25 then
			c.LastMove = now
			c.Humanoid:MoveTo(spot)
		end
	end
	c.Humanoid.WalkSpeed = c.Stats.Speed * (if flat(pos, ownerRoot.Position) > 25 then 1.5 else 1)
end

-- Recomputes a companion's stats (charms moved, the owner levelled).
function CompanionService:Refresh(player: Player)
	local c = companions[player]
	if not c then
		return
	end
	local stats = computeStats(player, c.Def)
	if stats then
		local ratio = c.Health / c.MaxHealth
		c.Stats = stats
		c.MaxHealth = stats.MaxHealth
		setHealth(c, c.MaxHealth * ratio)
	end
end

function CompanionService:Init(registry)
	services = registry
end

function CompanionService:Start()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < TICK then
			return
		end
		acc = 0
		local now = os.clock()
		for player, c in pairs(companions) do
			if not player.Parent or not c.Model.Parent then
				despawn(player)
			else
				local ok, err = pcall(step, c, now)
				if not ok then
					warn("[CompanionService] " .. tostring(err))
				end
			end
		end
	end)
	local function hook(player: Player)
		player.CharacterAdded:Connect(function()
			task.delay(1, function()
				if player.Parent then
					spawnFor(player)
				end
			end)
		end)
		player.CharacterRemoving:Connect(function()
			despawn(player)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in ipairs(Players:GetPlayers()) do
		hook(player)
	end
	Players.PlayerRemoving:Connect(despawn)
	services.DataService:OnLoaded(function(player)
		task.delay(1, function()
			if player.Parent and not companions[player] then
				spawnFor(player)
			end
		end)
	end)
	-- charms, level and gear change its stats
	services.DataService:AddFlushHook(function(player, keys)
		if keys.Charms or keys.Level or keys.EquippedKatana or keys.Upgrades or keys.Hats or keys.EquippedHat then
			task.defer(function()
				self:Refresh(player)
			end)
		end
	end)
end

return CompanionService
