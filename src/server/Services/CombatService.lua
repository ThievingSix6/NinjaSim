--[[
	CombatService: the client only says "I swung". The server checks the swing
	cadence against the player's real attack speed, tracks where the player is in
	the weapon's combo (Config/Combo) itself, finds enemies in that move's reach
	and arc (and Width lane for spear thrusts), computes damage/crits/combo bonus and applies it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Combo = require(Shared.Config.Combo)
local Katanas = require(Shared.Config.Katanas)
local Net = require(Shared.Net)

local CombatService = {}

local services
local state: { [Player]: { LastSwing: number, Combo: number, LastHit: number, Burst: number, BurstStart: number, Strikes: number, Chain: number, Weapon: string? } } = {}

local function getState(player: Player)
	local s = state[player]
	if not s then
		s = { LastSwing = 0, Combo = 0, LastHit = 0, Burst = 0, BurstStart = 0, Strikes = 0, Chain = 0 }
		state[player] = s
	end
	return s
end

local function onAttack(player: Player, comboIndex: any)
	local data = services.DataService:Get(player)
	local stats = services.StatService:Get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not data or not stats or not root or not humanoid or humanoid.Health <= 0 then
		return
	end

	local s = getState(player)
	local now = os.clock()
	local equipped = Katanas.Get(data.EquippedKatana)
	local weapon = if equipped and equipped.Weapon then equipped.Weapon else "Katana"
	local moves = Combo.MovesFor(weapon)
	if s.Weapon ~= weapon then
		s.Weapon = weapon
		s.Chain = 0 -- switching weapons starts a fresh combo
	end
	-- Cadence check with latency tolerance (each move has its own recovery, the
	-- finisher the longest), plus a burst cap as a second line of defence.
	local previous = if s.Chain > 0 then Combo.Get(s.Chain, weapon) else nil
	local cooldown = stats.AttackInterval * (if previous then previous.Cooldown else 1)
	if now - s.LastSwing < cooldown * 0.75 then
		s.Strikes += 1
		if s.Strikes == 50 then
			warn(string.format("[CombatService] %s is swinging faster than allowed", player.Name))
		end
		return
	end
	if now - s.BurstStart > 2 then
		s.BurstStart = now
		s.Burst = 0
	end
	s.Burst += 1
	if s.Burst > math.ceil(2 / stats.AttackInterval) + 2 then
		return
	end
	-- Which move of the combo this is comes from the server's own count, so a client
	-- can't claim the finisher every swing; it may only restart the chain early.
	local continues = previous ~= nil and now - s.LastSwing <= cooldown + Combo.ChainWindow + 0.35
	s.Chain = if continues and comboIndex ~= 1 then (s.Chain % #moves) + 1 else 1
	s.LastSwing = now
	local move = Combo.Get(s.Chain, weapon)

	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local oc = other.Character
			local oroot = oc and oc:FindFirstChild("HumanoidRootPart") :: BasePart?
			if oroot and (oroot.Position - root.Position).Magnitude < 120 then
				Net.Event("Swing"):FireClient(other, player, s.Chain)
			end
		end
	end

	local zone = services.ZoneService:GetZone(player)
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	look = if look.Magnitude > 0 then look.Unit else Vector3.new(0, 0, -1)
	local candidates = services.EnemyService:InRange(zone.Id, root.Position, Balance.AttackRange + move.Reach)
	local maxTargets = Balance.MaxTargetsPerSwing + move.ExtraTargets

	local hits = {}
	for _, entry in ipairs(candidates) do
		if #hits >= maxTargets then
			break
		end
		local enemy = entry.Enemy
		local toEnemy = Vector3.new(enemy.Root.Position.X - root.Position.X, 0, enemy.Root.Position.Z - root.Position.Z)
		local inFront = toEnemy.Magnitude < enemy.Radius + 3 or look:Dot(toEnemy.Unit) >= move.Arc
		-- thrusts (spears) hit a narrow lane: no further than Width from the strike line
		if inFront and move.Width and toEnemy.Magnitude >= enemy.Radius + 3 then
			local along = look:Dot(toEnemy)
			inFront = (toEnemy - look * along).Magnitude <= move.Width + enemy.Radius
		end
		if inFront then
			table.insert(hits, enemy)
		end
	end

	if #hits == 0 then
		return
	end

	if now - s.LastHit <= Balance.ComboWindow then
		s.Combo += 1
	else
		s.Combo = 1
	end
	s.LastHit = now
	local comboBonus = math.min(s.Combo * Balance.ComboBonusPerHit, Balance.MaxComboBonus)

	local results = {}
	for _, enemy in ipairs(hits) do
		local crit = math.random() < stats.CritChance
		local amount = stats.Damage * move.Damage * (1 + comboBonus) * (0.92 + math.random() * 0.16)
		if crit then
			amount *= stats.CritMult
		end
		amount = math.max(1, math.floor(amount))
		local killed = services.EnemyService:Damage(enemy, player, amount, root.Position, move.Knockback, move.Stun)
		table.insert(results, { Uid = enemy.Uid, Damage = amount, Crit = crit, Killed = killed, Position = enemy.Root.Position, Height = enemy.Height })
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player then
				local oc = other.Character
				local oroot = oc and oc:FindFirstChild("HumanoidRootPart") :: BasePart?
				if oroot and (oroot.Position - enemy.Root.Position).Magnitude < 120 then
					Net.Event("EnemyHit"):FireClient(other, enemy.Uid, crit)
				end
			end
		end
	end
	Net.Event("CombatResult"):FireClient(player, { Hits = results, Combo = s.Combo, Move = s.Chain })
	if services.LootService then
		services.LootService:OnHit(player, hits) -- hat procs
	end
end

function CombatService:ResetCombo(player: Player)
	local s = getState(player)
	s.Combo = 0
	s.Chain = 0
end

function CombatService:Init(registry)
	services = registry
end

function CombatService:Start()
	Net.Event("Attack").OnServerEvent:Connect(onAttack)
	Players.PlayerRemoving:Connect(function(player)
		state[player] = nil
	end)
end

return CombatService
