--[[
	GiftService: free gifts for time spent in this session (Config/Gifts).
	Session start and claimed gifts are published as player attributes
	("GiftStart" in server time, "GiftsClaimed" as "1,3,..") so the client can
	show timers without extra remotes. Claims are validated here.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Gifts = require(Shared.Config.Gifts)
local Balance = require(Shared.Config.Balance)
local Net = require(Shared.Net)

local GiftService = {}

local services
local sessions: { [Player]: { Start: number, Claimed: { [number]: boolean } } } = {}

local function grant(player: Player, level: number, gift)
	if gift.Kind == "Coins" then
		services.ProgressionService:AddCoins(player, Balance.CoinsForKills(level, gift.Kills))
	elseif gift.Kind == "Shards" then
		services.ProgressionService:AddShards(player, gift.Amount)
	elseif gift.Kind == "Boost" then
		services.ShopService:AddBoost(player, gift.Id, gift.Seconds)
	end
end

-- Daily streak: granted once per UTC day on join, shown as a popup.
local function checkDaily(player: Player, data)
	local today = math.floor(os.time() / 86400)
	local daily = data.Daily
	if daily.Day >= today then
		return -- already rewarded today (or another server's clock is ahead)
	end
	daily.Streak = if daily.Day == today - 1 then daily.Streak + 1 else 1
	daily.Day = today
	local gift = Gifts.DailyFor(daily.Streak)
	grant(player, data.Level, gift)
	services.DataService:Changed(player, "Daily")
	local text = gift.Icon .. " " .. Gifts.Describe(gift, data.Level)
	local tomorrow = Gifts.DailyFor(daily.Streak + 1)
	-- give the client time to finish loading before the popup
	task.delay(6, function()
		if player.Parent then
			Net.Event("Reward"):FireClient(player, {
				Title = "Daily Reward: Day " .. daily.Streak .. " 🔥",
				Text = text .. "\nCome back tomorrow for " .. Gifts.Describe(tomorrow, data.Level) .. "!",
			})
		end
	end)
end

local function publish(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	local claimed = {}
	for index in pairs(session.Claimed) do
		table.insert(claimed, tostring(index))
	end
	table.sort(claimed)
	player:SetAttribute("GiftsClaimed", table.concat(claimed, ","))
end

function GiftService:Claim(player: Player, index: any): (boolean, string?)
	local session = sessions[player]
	local data = services.DataService:Get(player)
	if not session or not data then
		return false, "Still loading"
	end
	if type(index) ~= "number" or index % 1 ~= 0 then
		return false, "Unknown gift"
	end
	local gift = Gifts.List[index]
	if not gift then
		return false, "Unknown gift"
	end
	if session.Claimed[index] then
		return false, "Already claimed"
	end
	if workspace:GetServerTimeNow() - session.Start < gift.Minutes * 60 - 1 then
		return false, "Not ready yet"
	end
	session.Claimed[index] = true
	local text = Gifts.Describe(gift, data.Level)
	grant(player, data.Level, gift)
	publish(player)
	return true, "Gift: " .. text
end

function GiftService:Init(registry)
	services = registry
end

function GiftService:Start()
	services.DataService:OnLoaded(function(player, data)
		checkDaily(player, data)
		local start = workspace:GetServerTimeNow()
		sessions[player] = { Start = start, Claimed = {} }
		player:SetAttribute("GiftStart", start)
		publish(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)
end

return GiftService
