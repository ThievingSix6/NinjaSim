--[[
	CombatService: the client only says "I swung". The server checks the swing
	cadence against the player's real attack speed, tracks where the player is in
	the weapon's combo (Config/Combo) itself, finds enemies in that move's reach
	and arc (and Width lane for spear thrusts), computes damage/crits/combo bonus and applies it.
	The hits are worked out when the move's blade lands (HitAt into the swing, the
	moment the client animates it), so a dodge or a jump ("CancelAttack") during the
	wind-up cancels the swing: fluid combat with no free damage from cancelled swings.

	It also keeps each player's stamina (Util/Stamina): every swing and dodge spends it,
	and the server refuses actions the pool can't cover. A dodge ("Dodge" event) opens
	the i-frame window that EnemyService and BossService check with IsInvulnerable.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Combo = require(Shared.Config.Combo)
local Katanas = require(Shared.Config.Katanas)
local Net = require(Shared.Net)
local Stamina = require(Shared.Util.Stamina)

local CombatService = {}

local services
local state: { [Player]: { LastSwing: number, Combo: number, LastHit: number, Burst: number, BurstStart: number, Strikes: number, Chain: number, Weapon: string?, Stamina: Stamina.Pool, LastDodge: number, IFrames: { number }, Pending: any? } } = {}

-- seconds of extra regen the server allows for network jitter between two actions
local STAMINA_SLACK = 0.3
local LANDING_SLACK = 0.05 -- seconds: the server resolves a swing a touch before the client sees the blade land

local function getState(player: Player)
	local s = state[player]
	if not s then
		local now = os.clock()
		s = { LastSwing = 0, Combo = 0, LastHit = 0, Burst = 0, BurstStart = 0, Strikes = 0, Chain = 0, Stamina = Stamina.new(now), LastDodge = 0, IFrames = { 0, 0 } }
		state[player] = s
	end
	return s
end

-- The swing's blade lands: hit what is in front now (live position and facing).
local function resolveSwing(player: Player, move, chain: number)
	local stats = services.StatService:Get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not stats or not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	local s = getState(player)
	local now = os.clock()
	local zone = services.ZoneService:GetZone(player)
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	look = if look.Magnitude > 0 then look.Unit else Vector3.new(0, 0, -1)
	-- an awakened mastery Avatar throws an elemental wave with every swing
	services.SkillService:AvatarSwing(player, root.Position, look)
	-- the Hexfire Torch (Config/Charms): a chance on every attack to roll a tendril of flame
	if (stats.Hexfire or 0) > 0 and math.random() < stats.Hexfire then
		services.SkillService:CastHexfire(player, root.Position, look)
	end
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
	Net.Event("CombatResult"):FireClient(player, { Hits = results, Combo = s.Combo, Move = chain })
	if services.LootService then
		services.LootService:OnHit(player, hits) -- hat procs
	end
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
	if not Stamina.CanAct(s.Stamina, now, STAMINA_SLACK) then
		return -- out of stamina: the client holds swings back too, so this is lag or a cheat
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
	Stamina.Spend(s.Stamina, now, Stamina.MoveCost(move))

	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local oc = other.Character
			local oroot = oc and oc:FindFirstChild("HumanoidRootPart") :: BasePart?
			if oroot and (oroot.Position - root.Position).Magnitude < 120 then
				Net.Event("Swing"):FireClient(other, player, s.Chain)
			end
		end
	end

	-- The blade lands HitAt into the move (the same timing the client animates);
	-- the hits are worked out then, so a dodge or jump before it cancels the swing.
	local duration = move.Duration * math.clamp(stats.AttackInterval / Balance.BaseAttackInterval, 0.45, 1)
	local token = {}
	s.Pending = token
	task.delay(math.max(0, move.HitAt * duration - LANDING_SLACK), function()
		if s.Pending ~= token then
			return -- cancelled by a dodge or a jump
		end
		s.Pending = nil
		resolveSwing(player, move, s.Chain)
	end)
end

-- Cancels a swing whose blade hasn't landed yet (dodge or jump). The combo starts
-- over and the next swing may start right away. Returns true if one was pending.
function CombatService:CancelSwing(player: Player): boolean
	local s = state[player]
	if not s or not s.Pending then
		return false
	end
	s.Pending = nil
	s.Chain = 0
	s.LastSwing = 0
	return true
end

-- Dodge roll: checks cadence and stamina, then opens the i-frame window. The roll
-- itself moves the character on the client (which owns its physics); nearby players
-- get "Dodged" to play the roll pose.
local function onDodge(player: Player, direction: any)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	local s = getState(player)
	local now = os.clock()
	if now - s.LastDodge < Balance.Dodge.Cooldown * 0.75 or not Stamina.CanAct(s.Stamina, now, STAMINA_SLACK) then
		return
	end
	s.LastDodge = now
	Stamina.Spend(s.Stamina, now, Balance.Stamina.Dodge)
	CombatService:CancelSwing(player) -- rolling out of a swing's wind-up cancels it
	-- the server hears about the roll a little late, so its window starts on arrival
	-- and runs the full i-frame length from there
	s.IFrames = { now, now + (Balance.Dodge.IFrameEnd - Balance.Dodge.IFrameStart) }
	local kind = if typeof(direction) == "Vector3" and direction.Magnitude > 0.1 then "Roll" else "Backstep"
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local oc = other.Character
			local oroot = oc and oc:FindFirstChild("HumanoidRootPart") :: BasePart?
			if oroot and (oroot.Position - root.Position).Magnitude < 120 then
				Net.Event("Dodged"):FireClient(other, player, kind)
			end
		end
	end
end

-- True while `player` is inside a dodge's i-frames: enemy and boss hits miss them.
-- A miss tells the client so it can show "DODGED".
-- Death guards (Phoenix Rebirth): fn(player, humanoid) runs instead of the first blow
-- that would kill; it returns true when it saved them. Enemy and boss hits ask Guarded.
local deathGuards: { [Player]: (Player, Humanoid) -> boolean } = {}
function CombatService:SetDeathGuard(player: Player, fn: ((Player, Humanoid) -> boolean)?)
	deathGuards[player] = fn
end

function CombatService:Guarded(player: Player, humanoid: Humanoid, amount: number): boolean
	local fn = deathGuards[player]
	if fn and humanoid.Health - amount <= 0 then
		deathGuards[player] = nil
		return fn(player, humanoid) == true
	end
	return false
end

function CombatService:IsInvulnerable(player: Player): boolean
	local s = state[player]
	if not s then
		return false
	end
	local now = os.clock()
	if now >= s.IFrames[1] and now <= s.IFrames[2] then
		Net.Event("Evaded"):FireClient(player)
		return true
	end
	return false
end

-- The player's current stamina (for tests and the admin panel).
function CombatService:GetStamina(player: Player): number
	return Stamina.Get(getState(player).Stamina, os.clock())
end

function CombatService:RefillStamina(player: Player)
	Stamina.Refill(getState(player).Stamina, os.clock())
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
	Net.Event("Dodge").OnServerEvent:Connect(onDodge)
	Net.Event("CancelAttack").OnServerEvent:Connect(function(player)
		CombatService:CancelSwing(player)
	end)
	local function hook(player: Player)
		player.CharacterAdded:Connect(function()
			CombatService:RefillStamina(player)
		end)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		hook(player)
	end
	Players.PlayerAdded:Connect(hook)
	Players.PlayerRemoving:Connect(function(player)
		deathGuards[player] = nil
		state[player] = nil
	end)
end

return CombatService
