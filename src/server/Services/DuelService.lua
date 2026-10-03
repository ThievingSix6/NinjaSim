--[[
	DuelService: one-on-one duels between players, decided on the server.

	  Request(player, targetUserId, wager)  challenge someone in the server (the invite
	                                        expires after Duel.InviteSeconds); wager =
	                                        both put half their levels on the line
	  Respond(player, fromUserId, accept)   accept or decline a challenge
	  Forfeit(player)                       give up (leaving the server or dying forfeits too)

	An accepted duel teleports both to the Duel Dojo, a floating stage high above the
	village, heals them, counts down, then lets them fight with their swords: rolls and
	jumps work as everywhere (a roll's i-frames make a blade miss). Damage is a share of
	the target's max health per hit, nudged by how much stronger the attacker hits, so a
	level gap matters without being hopeless. The first to drop to their last sliver of
	health loses (nobody really dies); after Duel.MaxTime the healthier one wins.

	Wager: the loser loses half their levels (rounded down) and the winner gains half of
	the loser's level. Both had to agree: the challenger picked it, accepting agrees.
	Wagers need both players at Duel.MinWagerLevel or above.

	Afterwards both are healed and sent back where they were. The "Duel" event keeps the
	two clients in sync: { Type = "Invite" | "Declined" | "Start" | "Fight" | "Hit" | "End" }.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Zones = require(Shared.Config.Zones)
local Net = require(Shared.Net)

local DuelService = {}

DuelService.InviteSeconds = 30
DuelService.Countdown = 3
DuelService.MaxTime = 120
DuelService.MinWagerLevel = 10
DuelService.HitShare = 0.07 -- of the target's max health per hit, times the move's Damage
DuelService.ArenaRadius = 46

local services
type Duel = {
	A: Player, B: Player, Wager: boolean, State: string, Started: number,
	Return: { [Player]: CFrame }, Over: boolean,
}
local duels: { [Player]: Duel } = {}
local invites: { [Player]: { [Player]: { Expires: number, Wager: boolean } } } = {}
local arena: Model? = nil
local arenaCenter = Vector3.zero

local function event(player: Player, payload)
	Net.Event("Duel"):FireClient(player, payload)
end

local function humanoidOf(player: Player): (Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 then
		return nil, nil
	end
	return humanoid, root
end

local function opponentOf(duel: Duel, player: Player): Player
	return if duel.A == player then duel.B else duel.A
end

-- ===== the Duel Dojo =====
local function buildArena()
	local village = Zones.List[1]
	arenaCenter = Vector3.new(village.Center.X, 320, village.Center.Z)
	local ok, Props = pcall(require, ServerScriptService:WaitForChild("Server"):WaitForChild("World"):WaitForChild("Props"))
	local world = workspace:FindFirstChild("World") or workspace
	local m = Instance.new("Model")
	m.Name = "DuelDojo"
	local function block(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?)
		local p = Instance.new("Part")
		if shape then
			p.Shape = shape
		end
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material
		p.Anchored = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = m
		return p
	end
	local r = DuelService.ArenaRadius
	-- the stage: a round stone platform with a wooden ring floor and a painted circle
	block(Vector3.new(6, (r + 6) * 2, (r + 6) * 2), CFrame.new(arenaCenter - Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(96, 92, 100), Enum.Material.Slate, Enum.PartType.Cylinder)
	block(Vector3.new(1, r * 2, r * 2), CFrame.new(arenaCenter + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(150, 104, 62), Enum.Material.WoodPlanks, Enum.PartType.Cylinder)
	block(Vector3.new(1.1, r * 1.3, r * 1.3), CFrame.new(arenaCenter + Vector3.new(0, 0.52, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(190, 40, 40), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	block(Vector3.new(1.2, r * 1.2, r * 1.2), CFrame.new(arenaCenter + Vector3.new(0, 0.55, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(150, 104, 62), Enum.Material.WoodPlanks, Enum.PartType.Cylinder)
	-- a low wall of posts all round (invisible barrier above it so nobody falls off)
	for i = 0, 23 do
		local a = i / 24 * math.pi * 2
		local at = arenaCenter + Vector3.new(math.cos(a) * (r + 2), 0, math.sin(a) * (r + 2))
		block(Vector3.new(2, 5, 2), CFrame.new(at + Vector3.new(0, 2.5, 0)), Color3.fromRGB(150, 30, 30), Enum.Material.Wood)
		local wall = block(Vector3.new(14, 30, 1), CFrame.lookAt(at + Vector3.new(0, 15, 0), arenaCenter + Vector3.new(0, 15, 0)), Color3.new(1, 1, 1), Enum.Material.ForceField)
		wall.Transparency = 1
		wall.CanQuery = false
	end
	if ok and Props then
		pcall(function()
			Props.Torii(m, CFrame.new(arenaCenter + Vector3.new(-r + 6, 0.5, 0)) * CFrame.Angles(0, math.pi / 2, 0), 16, 18, Color3.fromRGB(200, 40, 30))
			for _, side in ipairs({ -1, 1 }) do
				Props.StoneLantern(m, CFrame.new(arenaCenter + Vector3.new(r - 8, 0.5, side * 14)))
				Props.Banner(m, CFrame.new(arenaCenter + Vector3.new(0, 0.5, side * (r - 4))), Color3.fromRGB(170, 30, 30), Color3.fromRGB(250, 240, 220))
			end
		end)
	end
	m.Parent = world
	arena = m
end

local function spot(index: number): CFrame
	local x = if index == 1 then -16 else 16
	local p = arenaCenter + Vector3.new(x, 4, 0)
	return CFrame.lookAt(p, arenaCenter + Vector3.new(0, 4, 0))
end

local function place(player: Player, cf: CFrame)
	local character = player.Character
	if character then
		services.ZoneService:MarkTeleported(player)
		character:PivotTo(cf)
	end
end

local function heal(player: Player)
	local humanoid = humanoidOf(player)
	if humanoid then
		humanoid.Health = humanoid.MaxHealth
	end
end

-- ===== flow =====
local function finish(duel: Duel, winner: Player?, reason: string)
	if duel.Over then
		return
	end
	duel.Over = true
	duels[duel.A] = nil
	duels[duel.B] = nil
	local loser = if winner then opponentOf(duel, winner) else nil
	local result = { Type = "End", Reason = reason, Wager = duel.Wager }
	if winner and loser then
		result.Winner = winner.DisplayName
		result.Loser = loser.DisplayName
		if duel.Wager then
			local wd, ld = services.DataService:Get(winner), services.DataService:Get(loser)
			if wd and ld then
				local stake = math.floor(ld.Level / 2)
				result.Gained = stake
				result.Lost = stake
				services.ProgressionService:SetLevel(loser, ld.Level - stake)
				services.ProgressionService:SetLevel(winner, wd.Level + stake)
				for _, p in ipairs({ winner, loser }) do
					task.spawn(function()
						services.DataService:SaveNow(p)
					end)
				end
			end
		end
	end
	for _, p in ipairs({ duel.A, duel.B }) do
		if p.Parent then
			event(p, result)
			task.delay(2.5, function()
				if p.Parent and not duels[p] then
					heal(p)
					local back = duel.Return[p]
					if back then
						place(p, back)
					end
				end
			end)
		end
	end
	-- the whole server hears how it went
	if winner and loser then
		for _, other in ipairs(Players:GetPlayers()) do
			Net.Event("Notify"):FireClient(other, {
				Text = string.format("%s beat %s in a duel%s", winner.DisplayName, loser.DisplayName, if duel.Wager then " and took " .. tostring(result.Gained) .. " levels" else ""),
				Color = Color3.fromRGB(255, 200, 90), Side = true,
			})
		end
	end
end

local function start(a: Player, b: Player, wager: boolean)
	local duel: Duel = { A = a, B = b, Wager = wager, State = "Countdown", Started = os.clock(), Return = {}, Over = false }
	duels[a] = duel
	duels[b] = duel
	invites[a] = nil
	invites[b] = nil
	if not arena then
		buildArena()
	end
	for i, p in ipairs({ a, b }) do
		local _, root = humanoidOf(p)
		if root then
			duel.Return[p] = root.CFrame
		end
		place(p, spot(i))
		heal(p)
		event(p, { Type = "Start", Opponent = opponentOf(duel, p).DisplayName, OpponentId = opponentOf(duel, p).UserId, Wager = wager, Countdown = DuelService.Countdown, MaxTime = DuelService.MaxTime })
	end
	task.delay(DuelService.Countdown, function()
		if duel.Over then
			return
		end
		duel.State = "Fight"
		duel.Started = os.clock()
		for _, p in ipairs({ a, b }) do
			event(p, { Type = "Fight" })
		end
	end)
	task.delay(DuelService.Countdown + DuelService.MaxTime, function()
		if duel.Over then
			return
		end
		-- time: the healthier one (by share of max health) wins, a tie is a draw
		local ha, hb = humanoidOf(a), humanoidOf(b)
		local fa = if ha then ha.Health / ha.MaxHealth else 0
		local fb = if hb then hb.Health / hb.MaxHealth else 0
		if math.abs(fa - fb) < 0.01 then
			finish(duel, nil, "time")
		else
			finish(duel, if fa > fb then a else b, "time")
		end
	end)
end

function DuelService:Request(player: Player, targetId: any, wager: any): (boolean, string?)
	local target = if type(targetId) == "number" then Players:GetPlayerByUserId(targetId) else nil
	if not target or target == player then
		return false, "Pick another player"
	end
	if duels[player] or duels[target] then
		return false, "One of you is already in a duel"
	end
	if services.TempleService and (services.TempleService:RunOf(player) or services.TempleService:RunOf(target)) then
		return false, "One of you is in the Cursed Temple"
	end
	local wants = wager == true
	if wants then
		local mine, theirs = services.DataService:Get(player), services.DataService:Get(target)
		if not mine or not theirs then
			return false, "Still loading"
		end
		if mine.Level < DuelService.MinWagerLevel or theirs.Level < DuelService.MinWagerLevel then
			return false, "Wagers need both of you at Level " .. DuelService.MinWagerLevel .. "+"
		end
	end
	invites[target] = invites[target] or {}
	invites[target][player] = { Expires = os.clock() + DuelService.InviteSeconds, Wager = wants }
	local theirData = services.DataService:Get(player)
	event(target, {
		Type = "Invite", From = player.UserId, FromName = player.DisplayName, Wager = wants,
		Level = theirData and theirData.Level or 0, Seconds = DuelService.InviteSeconds,
	})
	return true, "Challenge sent to " .. target.DisplayName
end

function DuelService:Respond(player: Player, fromId: any, accept: any): (boolean, string?)
	local from = if type(fromId) == "number" then Players:GetPlayerByUserId(fromId) else nil
	local invite = from and invites[player] and invites[player][from]
	if not from or not invite or os.clock() > invite.Expires then
		return false, "That challenge has expired"
	end
	invites[player][from] = nil
	if accept ~= true then
		event(from, { Type = "Declined", By = player.DisplayName })
		return true, nil
	end
	if duels[player] or duels[from] then
		return false, "One of you is already in a duel"
	end
	if services.TempleService and (services.TempleService:RunOf(player) or services.TempleService:RunOf(from)) then
		return false, "One of you is in the Cursed Temple"
	end
	if not humanoidOf(player) or not humanoidOf(from) then
		return false, "Both of you need to be alive"
	end
	start(from, player, invite.Wager)
	return true, nil
end

function DuelService:Forfeit(player: Player): (boolean, string?)
	local duel = duels[player]
	if not duel then
		return false, "You're not in a duel"
	end
	finish(duel, opponentOf(duel, player), "forfeit")
	return true, nil
end

-- True while `player` is dueling (other systems keep out of the way).
function DuelService:InDuel(player: Player): boolean
	return duels[player] ~= nil
end

-- CombatService calls this when a swing's blade lands: hit the opponent if they are in
-- the move's reach and arc. Returns the hit (for the attacker's feedback) or nil.
function DuelService:OnSwing(player: Player, move, look: Vector3)
	local duel = duels[player]
	if not duel or duel.State ~= "Fight" or duel.Over then
		return nil
	end
	local foe = opponentOf(duel, player)
	local _, root = humanoidOf(player)
	local fh, froot = humanoidOf(foe)
	if not root or not fh or not froot then
		return nil
	end
	local to = Vector3.new(froot.Position.X - root.Position.X, 0, froot.Position.Z - root.Position.Z)
	if to.Magnitude > Balance.AttackRange + move.Reach + 1.5 then
		return nil
	end
	if to.Magnitude > 3 and look:Dot(to.Unit) < move.Arc then
		return nil
	end
	if services.CombatService:IsInvulnerable(foe) then
		return nil -- rolled through it
	end
	-- a share of their health, nudged by how much harder the attacker hits (0.6x .. 1.6x)
	local mine, theirs = services.StatService:Get(player), services.StatService:Get(foe)
	local ratio = if mine and theirs and theirs.Damage > 0 then mine.Damage / theirs.Damage else 1
	local crit = mine ~= nil and math.random() < mine.CritChance
	local amount = fh.MaxHealth * DuelService.HitShare * move.Damage * math.clamp(ratio ^ 0.3, 0.6, 1.6) * (if crit then 1.5 else 1)
	amount = math.max(1, math.floor(amount))
	services.HealthService:MarkHurt(foe)
	local lethal = fh.Health - amount <= fh.MaxHealth * 0.01
	if lethal then
		fh.Health = math.max(1, fh.MaxHealth * 0.01)
	else
		fh.Health -= amount
	end
	local hit = { Damage = amount, Crit = crit, Position = froot.Position, Health = fh.Health, MaxHealth = fh.MaxHealth }
	event(player, { Type = "Hit", Target = foe.UserId, Damage = amount, Crit = crit, Position = froot.Position, Health = fh.Health, MaxHealth = fh.MaxHealth })
	event(foe, { Type = "Hit", Target = foe.UserId, Damage = amount, Crit = crit, Position = froot.Position, Health = fh.Health, MaxHealth = fh.MaxHealth })
	Net.Event("PlayerHurt"):FireClient(foe, amount, root.Position, move.Finisher == true)
	if lethal then
		finish(duel, player, "knockout")
	end
	return hit
end

function DuelService:Init(registry)
	services = registry
end

function DuelService:Start()
	Players.PlayerRemoving:Connect(function(player)
		local duel = duels[player]
		if duel then
			finish(duel, opponentOf(duel, player), "left")
		end
		invites[player] = nil
		for _, list in pairs(invites) do
			list[player] = nil
		end
	end)
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
			if humanoid then
				humanoid.Died:Connect(function()
					local duel = duels[player]
					if duel then
						finish(duel, opponentOf(duel, player), "died")
					end
				end)
			end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in ipairs(Players:GetPlayers()) do
		hook(player)
	end
end

return DuelService
