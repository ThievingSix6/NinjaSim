--[[
	PartyService: team up with other players (justin, 2026-10-03: "a party-up system so
	you can team with other players and get xp together").

	Invite a player from the Trade menu's player list; they accept or decline on a card.
	A party holds up to MaxSize players; the leader can kick, anyone can leave, and the
	lead passes on if the leader leaves. Partied players earn XP together: when one of
	you earns a kill, every other member within ShareRange of it gets ShareXP of the
	kill's XP (worked out at their own level), and whoever earned the kill gets a bonus
	of BonusPerMember for each member nearby. Mastery XP is not shared.

	Events: "Party" { Type = "Invite" | "Declined" | "Update" | "Left" | "XP", ... }.
	Requests (RequestService): PartyInvite(userId), PartyRespond(fromId, accept),
	PartyLeave(), PartyKick(userId).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Net = require(Shared.Net)

local PartyService = {}

PartyService.MaxSize = 4
PartyService.InviteSeconds = 30
PartyService.ShareRange = 160 -- studs from the kill
PartyService.ShareXP = 0.75 -- of the kill's XP, for members who didn't earn it themselves
PartyService.BonusPerMember = 0.1 -- extra XP for the one who earned it, per member nearby

local services
type Party = { Id: number, Leader: Player, Members: { Player } }
local partyOf: { [Player]: Party } = {}
local invites: { [Player]: { [Player]: number } } = {} -- invitee -> inviter -> expires
local nextId = 0

local function event(player: Player, payload)
	Net.Event("Party"):FireClient(player, payload)
end

local function broadcast(party: Party)
	local list = {}
	for _, member in ipairs(party.Members) do
		table.insert(list, { UserId = member.UserId, Name = member.DisplayName, Leader = member == party.Leader })
	end
	for _, member in ipairs(party.Members) do
		event(member, { Type = "Update", Members = list, Max = PartyService.MaxSize })
	end
end

local function remove(player: Player, reason: string)
	local party = partyOf[player]
	if not party then
		return
	end
	partyOf[player] = nil
	local index = table.find(party.Members, player)
	if index then
		table.remove(party.Members, index)
	end
	if player.Parent then
		event(player, { Type = "Left", Reason = reason })
	end
	if #party.Members <= 1 then
		-- a party of one is no party
		for _, last in ipairs(party.Members) do
			partyOf[last] = nil
			event(last, { Type = "Left", Reason = "disbanded" })
		end
		table.clear(party.Members)
		return
	end
	if party.Leader == player then
		party.Leader = party.Members[1]
	end
	broadcast(party)
end

function PartyService:Members(player: Player): { Player }
	local party = partyOf[player]
	return if party then party.Members else { player }
end

function PartyService:SameParty(a: Player, b: Player): boolean
	local party = partyOf[a]
	return party ~= nil and partyOf[b] == party
end

function PartyService:Invite(player: Player, targetId: any): (boolean, string?)
	local target = if type(targetId) == "number" then Players:GetPlayerByUserId(targetId) else nil
	if not target or target == player then
		return false, "Pick another player"
	end
	local mine = partyOf[player]
	if mine and partyOf[target] == mine then
		return false, target.DisplayName .. " is already in your party"
	end
	if partyOf[target] then
		return false, target.DisplayName .. " is already in a party"
	end
	if mine and #mine.Members >= PartyService.MaxSize then
		return false, "Your party is full (" .. PartyService.MaxSize .. ")"
	end
	invites[target] = invites[target] or {}
	invites[target][player] = os.clock() + PartyService.InviteSeconds
	local data = services.DataService:Get(player)
	event(target, { Type = "Invite", From = player.UserId, FromName = player.DisplayName, Level = data and data.Level or 0, Seconds = PartyService.InviteSeconds })
	return true, "Party invite sent to " .. target.DisplayName
end

function PartyService:Respond(player: Player, fromId: any, accept: any): (boolean, string?)
	local from = if type(fromId) == "number" then Players:GetPlayerByUserId(fromId) else nil
	local expires = from and invites[player] and invites[player][from]
	if not from or not expires or os.clock() > expires then
		return false, "That invite has expired"
	end
	invites[player][from] = nil
	if accept ~= true then
		event(from, { Type = "Declined", By = player.DisplayName })
		return true, nil
	end
	if partyOf[player] then
		return false, "Leave your party first"
	end
	local party = partyOf[from]
	if not party then
		nextId += 1
		party = { Id = nextId, Leader = from, Members = { from } }
		partyOf[from] = party
	end
	if #party.Members >= PartyService.MaxSize then
		return false, "That party is full"
	end
	table.insert(party.Members, player)
	partyOf[player] = party
	broadcast(party)
	return true, "You joined " .. from.DisplayName .. "'s party"
end

function PartyService:Leave(player: Player): (boolean, string?)
	if not partyOf[player] then
		return false, "You're not in a party"
	end
	remove(player, "left")
	return true, nil
end

function PartyService:Kick(player: Player, targetId: any): (boolean, string?)
	local party = partyOf[player]
	local target = if type(targetId) == "number" then Players:GetPlayerByUserId(targetId) else nil
	if not party or party.Leader ~= player then
		return false, "Only the party leader can kick"
	end
	if not target or partyOf[target] ~= party or target == player then
		return false, "They're not in your party"
	end
	remove(target, "kicked")
	return true, nil
end

local function near(player: Player, position: Vector3): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return root ~= nil and humanoid ~= nil and humanoid.Health > 0 and (root.Position - position).Magnitude <= PartyService.ShareRange
end

-- EnemyService:Kill calls this after paying the kill: partied players nearby share it.
-- `rewarded` maps each player who earned the kill to their reward.
function PartyService:ShareKill(enemy, rewarded: { [Player]: any })
	local position = enemy.Root.Position
	local shared: { [Player]: boolean } = {}
	for earner, reward in pairs(rewarded) do
		local party = partyOf[earner]
		if party and reward then
			local nearby = 0
			for _, member in ipairs(party.Members) do
				if member ~= earner and near(member, position) then
					nearby += 1
					if not rewarded[member] and not shared[member] then
						shared[member] = true
						local data = services.DataService:Get(member)
						local stats = services.StatService:Get(member)
						if data and stats then
							local xp = math.floor(enemy.XP * stats.XPMult * Balance.XPPenalty(data.Level, enemy.Level) * PartyService.ShareXP)
							if xp > 0 then
								services.ProgressionService:AddXP(member, xp)
								event(member, { Type = "XP", Amount = xp, From = earner.DisplayName, Position = position })
							end
						end
					end
				end
			end
			if nearby > 0 and (reward.XP or 0) > 0 then
				local bonus = math.floor(reward.XP * PartyService.BonusPerMember * nearby)
				if bonus > 0 then
					services.ProgressionService:AddXP(earner, bonus)
					reward.PartyBonus = bonus
				end
			end
		end
	end
end

function PartyService:Init(registry)
	services = registry
end

function PartyService:Start()
	Players.PlayerRemoving:Connect(function(player)
		remove(player, "left")
		invites[player] = nil
		for _, list in pairs(invites) do
			list[player] = nil
		end
	end)
end

return PartyService
