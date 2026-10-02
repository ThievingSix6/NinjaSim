--[[
	Free gifts for time played in the current session. Coin gifts scale with
	level (worth N kills at your level) so they stay useful all game long.
	The server grants them (GiftService); the client shows timers (Menus/Gifts).
]]

local Balance = require(script.Parent.Balance)
local Shop = require(script.Parent.Shop)
local Format = require(script.Parent.Parent.Util.Format)

local Gifts = {}

Gifts.List = {
	{ Minutes = 2, Kind = "Coins", Kills = 15, Icon = "🪙", Art = "Coin" },
	{ Minutes = 5, Kind = "Boost", Id = "XP2", Seconds = 300, Icon = "📘", Art = "Book" },
	{ Minutes = 8, Kind = "Coins", Kills = 35, Icon = "💰", Art = "Coin" },
	{ Minutes = 12, Kind = "Boost", Id = "Coins2", Seconds = 600, Icon = "🪙", Art = "Coin" },
	{ Minutes = 16, Kind = "Shards", Amount = 2, Icon = "💎", Art = "Shard" },
	{ Minutes = 20, Kind = "Boost", Id = "Luck", Seconds = 900, Icon = "🍀", Art = "Clover" },
	{ Minutes = 30, Kind = "Coins", Kills = 90, Icon = "👑", Art = "Crown" },
	{ Minutes = 45, Kind = "Shards", Amount = 5, Icon = "💠", Art = "Shard" },
}

-- Daily login streak: one reward per day you join, cycling every 7 days.
-- Missing a day resets the streak to Day 1.
Gifts.Daily = {
	{ Kind = "Coins", Kills = 20, Icon = "🪙", Art = "Coin" },
	{ Kind = "Boost", Id = "Coins2", Seconds = 600, Icon = "🪙", Art = "Coin" },
	{ Kind = "Coins", Kills = 40, Icon = "💰", Art = "Coin" },
	{ Kind = "Boost", Id = "XP2", Seconds = 900, Icon = "📘", Art = "Book" },
	{ Kind = "Coins", Kills = 70, Icon = "💰", Art = "Coin" },
	{ Kind = "Boost", Id = "Luck", Seconds = 1200, Icon = "🍀", Art = "Clover" },
	{ Kind = "Shards", Amount = 5, Icon = "💎", Art = "Shard" },
}

function Gifts.DailyFor(streak: number)
	return Gifts.Daily[(math.max(streak, 1) - 1) % #Gifts.Daily + 1]
end

-- Human-readable reward for a gift at the given level.
function Gifts.Describe(gift, level: number): string
	if gift.Kind == "Coins" then
		return Format.Abbrev(Balance.CoinsForKills(level, gift.Kills)) .. " Coins"
	elseif gift.Kind == "Shards" then
		return gift.Amount .. " Spirit Shards"
	elseif gift.Kind == "Boost" then
		local def = Shop.BoostsById[gift.Id]
		return (if def then def.Name else gift.Id) .. " " .. Format.Time(gift.Seconds)
	end
	return "?"
end

-- Parses the "1,3,5" attribute the server publishes into a set.
function Gifts.ParseClaimed(text: string?): { [number]: boolean }
	local set = {}
	for part in string.gmatch(text or "", "%d+") do
		set[tonumber(part) :: number] = true
	end
	return set
end

-- Number of gifts that are ready but not yet claimed.
function Gifts.ReadyCount(elapsed: number, claimed: { [number]: boolean }): number
	local n = 0
	for i, gift in ipairs(Gifts.List) do
		if not claimed[i] and elapsed >= gift.Minutes * 60 then
			n += 1
		end
	end
	return n
end

return Gifts
