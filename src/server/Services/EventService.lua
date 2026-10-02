--[[
	EventService: timed server-wide reward events (Config/Events), the friends
	bonus, and server shoutouts. State is published as attributes (workspace
	"EventId"/"EventEndsAt", player "FriendBoost") so the HUD needs no remotes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Events = require(Shared.Config.Events)
local Net = require(Shared.Net)

local EventService = {}

local active = nil
local friendCache: { [Player]: { [number]: boolean } } = {}

local ById = {}
for _, def in ipairs(Events.List) do
	ById[def.Id] = def
end

-- Multipliers applied to kill rewards.
function EventService:Multipliers(player: Player): (number, number)
	local friends = math.min(player:GetAttribute("FriendBoost") or 0, Events.MaxFriends)
	local social = 1 + friends * Events.FriendBonus
	local coins, xp = social, social
	if active and workspace:GetServerTimeNow() < active.EndsAt then
		coins *= active.Def.Coins
		xp *= active.Def.XP
	end
	return coins, xp
end

-- A short message for everyone in the server (rare hatches, boss kills...).
function EventService:Shoutout(text: string, color: Color3?)
	Net.Event("Notify"):FireAllClients({ Text = text, Color = color })
end

function EventService:Begin(eventId: string?)
	local def = ById[eventId or ""] or Events.List[math.random(1, #Events.List)]
	local endsAt = workspace:GetServerTimeNow() + Events.Duration
	active = { Def = def, EndsAt = endsAt }
	workspace:SetAttribute("EventId", def.Id)
	workspace:SetAttribute("EventEndsAt", endsAt)
	Net.Event("Notify"):FireAllClients({ Text = def.Icon .. " " .. def.Name .. "! " .. def.Desc, Color = def.Color, Big = true })
	task.delay(Events.Duration, function()
		if active and active.EndsAt == endsAt then
			active = nil
			workspace:SetAttribute("EventId", nil)
			workspace:SetAttribute("EventEndsAt", nil)
		end
	end)
end

local function isFriend(a: Player, b: Player): boolean
	local cache = friendCache[a]
	if cache and cache[b.UserId] ~= nil then
		return cache[b.UserId]
	end
	local ok, result = pcall(a.IsFriendsWith, a, b.UserId)
	local friends = ok and result == true
	if cache then
		cache[b.UserId] = friends
	end
	return friends
end

local function refreshFriends()
	local players = Players:GetPlayers()
	for _, player in ipairs(players) do
		local count = 0
		for _, other in ipairs(players) do
			if other ~= player and isFriend(player, other) then
				count += 1
			end
		end
		if player:GetAttribute("FriendBoost") ~= count then
			player:SetAttribute("FriendBoost", count)
		end
	end
end

function EventService:Init(_registry) end

function EventService:Start()
	Players.PlayerAdded:Connect(function(player)
		friendCache[player] = {}
		task.defer(refreshFriends)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		friendCache[player] = friendCache[player] or {}
	end
	Players.PlayerRemoving:Connect(function(player)
		friendCache[player] = nil
		task.defer(refreshFriends)
	end)
	task.spawn(refreshFriends)

	-- event loop
	task.spawn(function()
		task.wait(Events.FirstDelay)
		while true do
			self:Begin()
			task.wait(Events.Interval)
		end
	end)
end

return EventService
