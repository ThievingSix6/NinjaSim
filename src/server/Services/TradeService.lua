--[[
	TradeService: player-to-player trades of pets, hats and charms, decided on the server.

	  Request(player, targetUserId)        invite someone in the server (expires after
	                                       Trade.InviteSeconds)
	  Respond(player, fromUserId, accept)  accept or decline an invite: accepting opens
	                                       a trade between the two
	  Offer(player, kind, uid, add)        put a pet ("Pet"), hat ("Hat") or charm ("Charm") you own on
	                                       the table, or take it back (MaxItems each)
	  SetReady(player, ready)              when both are ready a short countdown runs;
	                                       any change to either offer un-readies both
	  Cancel(player)                       end the trade (leaving or dying cancels too)

	When the countdown ends with both still ready, everything is checked again
	(ownership, room in pet, hat and charm storage) and the items move in one step: each
	gets a fresh uid on its new owner, equipped items are unequipped (charms arrive in
	the stash, outside the grid), and both saves
	are written straight away. The "Trade" event keeps both clients in sync:
	{ Type = "Invite" | "Declined" | "State" | "Closed" | "Done", ... }.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Hats = require(Shared.Config.Hats)
local Charms = require(Shared.Config.Charms)
local TableUtil = require(Shared.Util.TableUtil)
local Net = require(Shared.Net)

local TradeService = {}

TradeService.InviteSeconds = 30
TradeService.MaxItems = 9
TradeService.Countdown = 3

local services
type Offer = { Pet: { string }, Hat: { string }, Charm: { string } }
type Session = { A: Player, B: Player, Offers: { [Player]: Offer }, Ready: { [Player]: boolean }, Version: number, CountdownAt: number?, Closed: boolean }
local sessions: { [Player]: Session } = {}
local invites: { [Player]: { [Player]: number } } = {} -- invites[target][from] = expires at
local lastInvite: { [Player]: number } = {}

local function event(player: Player, payload)
	Net.Event("Trade"):FireClient(player, payload)
end

local function partnerOf(session: Session, player: Player): Player
	return if session.A == player then session.B else session.A
end

-- What a side offers, as records the other client can draw.
local function describe(player: Player, offer: Offer)
	local data = services.DataService:Get(player)
	local out = { Pet = {}, Hat = {}, Charm = {} }
	if not data then
		return out
	end
	for _, uid in ipairs(offer.Charm) do
		local charm = data.Charms[uid]
		if charm then
			table.insert(out.Charm, { Uid = uid, Charm = charm })
		end
	end
	for _, uid in ipairs(offer.Pet) do
		local pet = data.Pets[uid]
		if pet then
			table.insert(out.Pet, { Uid = uid, Id = pet.Id, Mutation = pet.Mutation })
		end
	end
	for _, uid in ipairs(offer.Hat) do
		local hat = data.Hats[uid]
		if hat then
			table.insert(out.Hat, { Uid = uid, Hat = hat })
		end
	end
	return out
end

local function sync(session: Session)
	for _, me in ipairs({ session.A, session.B }) do
		local other = partnerOf(session, me)
		event(me, {
			Type = "State", Partner = other.UserId, PartnerName = other.DisplayName,
			Mine = describe(me, session.Offers[me]), Theirs = describe(other, session.Offers[other]),
			MyReady = session.Ready[me], TheirReady = session.Ready[other],
			Countdown = if session.CountdownAt then math.max(0, session.CountdownAt - os.clock()) else nil,
			Version = session.Version,
		})
	end
end

local function close(session: Session, reason: string)
	if session.Closed then
		return
	end
	session.Closed = true
	for _, p in ipairs({ session.A, session.B }) do
		if sessions[p] == session then
			sessions[p] = nil
		end
		if p.Parent then
			event(p, { Type = "Closed", Reason = reason })
		end
	end
end

local function unready(session: Session)
	session.Ready[session.A] = false
	session.Ready[session.B] = false
	session.CountdownAt = nil
	session.Version += 1
end

function TradeService:Request(player: Player, targetId: any): (boolean, string?)
	local target = type(targetId) == "number" and Players:GetPlayerByUserId(targetId)
	if not target or target == player then
		return false, "Pick another player"
	end
	if sessions[player] then
		return false, "You're already trading"
	end
	if sessions[target] then
		return false, target.DisplayName .. " is busy trading"
	end
	if lastInvite[player] and os.clock() - lastInvite[player] < 3 then
		return false, "Wait a moment before inviting again"
	end
	if not services.DataService:Get(player) or not services.DataService:Get(target) then
		return false, "Still loading"
	end
	lastInvite[player] = os.clock()
	invites[target] = invites[target] or {}
	invites[target][player] = os.clock() + TradeService.InviteSeconds
	event(target, { Type = "Invite", From = player.UserId, FromName = player.DisplayName, Seconds = TradeService.InviteSeconds })
	return true, "Trade request sent to " .. target.DisplayName
end

function TradeService:Respond(player: Player, fromId: any, accept: any): (boolean, string?)
	local from = type(fromId) == "number" and Players:GetPlayerByUserId(fromId)
	local mine = invites[player]
	if not from or not mine or not mine[from] or os.clock() > mine[from] then
		return false, "That trade request expired"
	end
	mine[from] = nil
	if accept ~= true then
		event(from, { Type = "Declined", By = player.DisplayName })
		return true, nil
	end
	if sessions[player] or sessions[from] then
		return false, "One of you is already trading"
	end
	local session: Session = {
		A = from, B = player,
		Offers = { [from] = { Pet = {}, Hat = {}, Charm = {} }, [player] = { Pet = {}, Hat = {}, Charm = {} } },
		Ready = { [from] = false, [player] = false }, Version = 1, Closed = false,
	}
	sessions[from] = session
	sessions[player] = session
	sync(session)
	return true, nil
end

function TradeService:Offer(player: Player, kind: any, uid: any, add: any): (boolean, string?)
	local session = sessions[player]
	if not session or session.Closed then
		return false, "You're not trading"
	end
	if kind ~= "Pet" and kind ~= "Hat" and kind ~= "Charm" or type(uid) ~= "string" then
		return false, "Pick a pet, a hat or a charm"
	end
	local data = services.DataService:Get(player)
	if not data then
		return false, "Still loading"
	end
	local list = session.Offers[player][kind]
	local at = table.find(list, uid)
	if add == true then
		if at then
			return true, nil
		end
		local owned = if kind == "Pet" then data.Pets[uid] elseif kind == "Hat" then data.Hats[uid] else data.Charms[uid]
		if not owned then
			return false, "You don't own that"
		end
		local mine = session.Offers[player]
		if #mine.Pet + #mine.Hat + #mine.Charm >= TradeService.MaxItems then
			return false, "At most " .. TradeService.MaxItems .. " items per trade"
		end
		table.insert(list, uid)
	elseif at then
		table.remove(list, at)
	end
	unready(session)
	sync(session)
	return true, nil
end

-- Moves every offered item. Called with both sides ready and the countdown over.
local function execute(session: Session): (boolean, string?)
	local a, b = session.A, session.B
	local da, db = services.DataService:Get(a), services.DataService:Get(b)
	local sa, sb = services.StatService:Get(a), services.StatService:Get(b)
	if not da or not db or not sa or not sb then
		return false, "Someone's save isn't loaded"
	end
	-- check everything before moving anything
	for _, side in ipairs({ { a, da }, { b, db } }) do
		local offer = session.Offers[side[1]]
		for _, uid in ipairs(offer.Pet) do
			if not side[2].Pets[uid] then
				return false, side[1].DisplayName .. " no longer has an offered pet"
			end
		end
		for _, uid in ipairs(offer.Hat) do
			if not Hats.Valid(side[2].Hats[uid]) then
				return false, side[1].DisplayName .. " no longer has an offered hat"
			end
		end
		for _, uid in ipairs(offer.Charm) do
			if not Charms.Valid(side[2].Charms[uid]) then
				return false, side[1].DisplayName .. " no longer has an offered charm"
			end
		end
	end
	local function room(data, stats, gainsPets, losesPets, gainsHats, losesHats, gainsCharms, losesCharms): string?
		if TableUtil.Count(data.Pets) - losesPets + gainsPets > stats.PetStorage then
			return "pet storage"
		end
		if TableUtil.Count(data.Hats) - losesHats + gainsHats > Hats.Storage then
			return "hat storage"
		end
		if TableUtil.Count(data.Charms) - losesCharms + gainsCharms > Charms.Storage then
			return "charm storage"
		end
		return nil
	end
	local oa, ob = session.Offers[a], session.Offers[b]
	local fullA = room(da, sa, #ob.Pet, #oa.Pet, #ob.Hat, #oa.Hat, #ob.Charm, #oa.Charm)
	if fullA then
		return false, a.DisplayName .. "'s " .. fullA .. " is full"
	end
	local fullB = room(db, sb, #oa.Pet, #ob.Pet, #oa.Hat, #ob.Hat, #oa.Charm, #ob.Charm)
	if fullB then
		return false, b.DisplayName .. "'s " .. fullB .. " is full"
	end
	-- take everything out first, then hand it over (no item can exist twice)
	local moving = { [a] = { Pet = {}, Hat = {}, Charm = {} }, [b] = { Pet = {}, Hat = {}, Charm = {} } }
	for _, side in ipairs({ { a, da }, { b, db } }) do
		local p, data = side[1], side[2]
		for _, uid in ipairs(session.Offers[p].Pet) do
			table.insert(moving[p].Pet, data.Pets[uid])
			data.Pets[uid] = nil
			local i = table.find(data.EquippedPets, uid)
			if i then
				table.remove(data.EquippedPets, i)
			end
		end
		for _, uid in ipairs(session.Offers[p].Hat) do
			table.insert(moving[p].Hat, data.Hats[uid])
			data.Hats[uid] = nil
			if data.EquippedHat == uid then
				data.EquippedHat = ""
			end
		end
		for _, uid in ipairs(session.Offers[p].Charm) do
			table.insert(moving[p].Charm, data.Charms[uid])
			data.Charms[uid] = nil
		end
	end
	for _, side in ipairs({ { a, db }, { b, da } }) do
		local giver, receiver = side[1], side[2]
		for _, pet in ipairs(moving[giver].Pet) do
			receiver.PetSerial += 1
			pet.Fav = false
			receiver.Pets[tostring(receiver.PetSerial)] = pet
		end
		for _, hat in ipairs(moving[giver].Hat) do
			receiver.HatSerial += 1
			hat.Lock = nil
			receiver.Hats[tostring(receiver.HatSerial)] = hat
		end
		for _, charm in ipairs(moving[giver].Charm) do
			receiver.CharmSerial = (tonumber(receiver.CharmSerial) or 0) + 1
			charm.Lock, charm.X, charm.Y = nil, nil, nil -- arrives in the stash
			receiver.Charms[tostring(receiver.CharmSerial)] = charm
		end
	end
	for _, p in ipairs({ a, b }) do
		for _, key in ipairs({ "Pets", "EquippedPets", "PetSerial", "Hats", "EquippedHat", "HatSerial", "Charms", "CharmSerial" }) do
			services.DataService:Changed(p, key)
		end
		if services.LootService then
			services.LootService:ApplyHat(p)
		end
		task.spawn(function()
			services.DataService:SaveNow(p)
		end)
	end
	print(string.format("[TradeService] %s <-> %s: %d pets + %d hats + %d charms for %d pets + %d hats + %d charms", a.Name, b.Name, #oa.Pet, #oa.Hat, #oa.Charm, #ob.Pet, #ob.Hat, #ob.Charm))
	return true, nil
end

function TradeService:SetReady(player: Player, ready: any): (boolean, string?)
	local session = sessions[player]
	if not session or session.Closed then
		return false, "You're not trading"
	end
	session.Ready[player] = ready == true
	session.CountdownAt = nil
	if session.Ready[session.A] and session.Ready[session.B] then
		local version = session.Version
		session.CountdownAt = os.clock() + TradeService.Countdown
		task.delay(TradeService.Countdown, function()
			if session.Closed or session.Version ~= version or not (session.Ready[session.A] and session.Ready[session.B]) then
				return
			end
			local ok, reason = execute(session)
			if ok then
				for _, p in ipairs({ session.A, session.B }) do
					event(p, { Type = "Done", Partner = partnerOf(session, p).DisplayName })
				end
				close(session, "done")
			else
				unready(session)
				sync(session)
				for _, p in ipairs({ session.A, session.B }) do
					Net.Event("Notify"):FireClient(p, { Text = "Trade stopped: " .. (reason or "something changed"), Color = Color3.fromRGB(255, 120, 120) })
				end
			end
		end)
	end
	sync(session)
	return true, nil
end

function TradeService:Cancel(player: Player): (boolean, string?)
	local session = sessions[player]
	if session then
		close(session, player.DisplayName .. " cancelled the trade")
	end
	return true, nil
end

-- Items in an open trade can't be deleted, salvaged or mutated from under it.
function TradeService:IsOffered(player: Player, kind: string, uid: string): boolean
	local session = sessions[player]
	return session ~= nil and session.Offers[player][kind] ~= nil and table.find(session.Offers[player][kind], uid) ~= nil
end

function TradeService:Init(registry)
	services = registry
end

function TradeService:Start()
	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player]
		if session then
			close(session, player.DisplayName .. " left")
		end
		invites[player] = nil
		lastInvite[player] = nil
		for _, list in pairs(invites) do
			list[player] = nil
		end
	end)
	local function hook(player: Player)
		player.CharacterAdded:Connect(function()
			local session = sessions[player]
			if session then
				close(session, "the trade ended when " .. player.DisplayName .. " respawned")
			end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in ipairs(Players:GetPlayers()) do
		hook(player)
	end
end

return TradeService
