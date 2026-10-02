--[[
	Trophies: long-term goals that pay Spirit Shards. Progress is read straight
	from the save (lifetime stats, rebirths, best tier...), so nothing extra has
	to be tracked; claiming is validated by AchievementService.
	Add one by appending { Id, Name, Stat, Target, Shards, Icon }.
]]

local Format = require(script.Parent.Parent.Util.Format)
local Tiers = require(script.Parent.Tiers)

local Achievements = {}

local function count(t): number
	local n = 0
	for _, v in pairs(t) do
		if v then
			n += 1
		end
	end
	return n
end

-- Stat readers: save data -> number
Achievements.Stats = {
	Kills = function(d) return d.Lifetime.Kills end,
	Bosses = function(d) return d.Lifetime.BossKills end,
	Eggs = function(d) return d.Lifetime.EggsOpened end,
	Coins = function(d) return d.Lifetime.CoinsEarned end,
	Level = function(d) return math.max(d.Lifetime.HighestLevel or 1, d.Level) end,
	Tier = function(d) return d.BestTier end,
	Zones = function(d) return count(d.Zones) end,
	Rebirths = function(d) return d.Rebirths end,
	Katanas = function(d) return count(d.Katanas) end,
}

local STAT_TEXT = {
	Kills = "Defeat %s enemies", Bosses = "Defeat %s bosses", Eggs = "Hatch %s pets", Coins = "Earn %s Coins",
	Level = "Reach Level %s", Zones = "Unlock %s areas", Rebirths = "Rebirth %s times",
	Katanas = "Own %s katanas",
}

Achievements.List = {
	{ Id = "kills1", Name = "First Blood", Stat = "Kills", Target = 25, Shards = 1, Icon = "⚔️" },
	{ Id = "kills2", Name = "Blade Dancer", Stat = "Kills", Target = 500, Shards = 2, Icon = "⚔️" },
	{ Id = "kills3", Name = "Hundred Cuts", Stat = "Kills", Target = 5000, Shards = 4, Icon = "⚔️" },
	{ Id = "kills4", Name = "Army of One", Stat = "Kills", Target = 50000, Shards = 8, Icon = "⚔️" },
	{ Id = "kills5", Name = "Living Legend", Stat = "Kills", Target = 500000, Shards = 15, Icon = "⚔️" },
	{ Id = "boss1", Name = "Giant Slayer", Stat = "Bosses", Target = 1, Shards = 2, Icon = "👹" },
	{ Id = "boss2", Name = "Boss Hunter", Stat = "Bosses", Target = 10, Shards = 4, Icon = "👹" },
	{ Id = "boss3", Name = "Warlord's Bane", Stat = "Bosses", Target = 50, Shards = 8, Icon = "👹" },
	{ Id = "boss4", Name = "Demon Queller", Stat = "Bosses", Target = 250, Shards = 15, Icon = "👹" },
	{ Id = "eggs1", Name = "New Friend", Stat = "Eggs", Target = 1, Shards = 1, Icon = "🥚" },
	{ Id = "eggs2", Name = "Egg Collector", Stat = "Eggs", Target = 30, Shards = 3, Icon = "🥚" },
	{ Id = "eggs3", Name = "Hatchery", Stat = "Eggs", Target = 300, Shards = 6, Icon = "🥚" },
	{ Id = "eggs4", Name = "Beast Master", Stat = "Eggs", Target = 1500, Shards = 12, Icon = "🥚" },
	{ Id = "coins1", Name = "Pocket Money", Stat = "Coins", Target = 10000, Shards = 1, Icon = "🪙" },
	{ Id = "coins2", Name = "Merchant", Stat = "Coins", Target = 1e7, Shards = 3, Icon = "🪙" },
	{ Id = "coins3", Name = "Treasure Hoard", Stat = "Coins", Target = 1e10, Shards = 6, Icon = "🪙" },
	{ Id = "coins4", Name = "Shogun's Vault", Stat = "Coins", Target = 1e13, Shards = 12, Icon = "🪙" },
	{ Id = "level1", Name = "Getting Started", Stat = "Level", Target = 10, Shards = 1, Icon = "⭐" },
	{ Id = "level2", Name = "Seasoned", Stat = "Level", Target = 50, Shards = 2, Icon = "⭐" },
	{ Id = "level3", Name = "Veteran", Stat = "Level", Target = 150, Shards = 5, Icon = "⭐" },
	{ Id = "level4", Name = "Grandmaster", Stat = "Level", Target = 400, Shards = 10, Icon = "⭐" },
	{ Id = "tier1", Name = "Blue Belt", Stat = "Tier", Target = 3, Shards = 1, Icon = "🥷" },
	{ Id = "tier2", Name = "Shadow Garb", Stat = "Tier", Target = 6, Shards = 3, Icon = "🥷" },
	{ Id = "tier3", Name = "Crimson Oath", Stat = "Tier", Target = 9, Shards = 6, Icon = "🥷" },
	{ Id = "tier4", Name = "Into the Void", Stat = "Tier", Target = 12, Shards = 15, Icon = "🥷" },
	{ Id = "zones1", Name = "Explorer", Stat = "Zones", Target = 3, Shards = 2, Icon = "🗺️" },
	{ Id = "zones2", Name = "Wayfarer", Stat = "Zones", Target = 5, Shards = 4, Icon = "🗺️" },
	{ Id = "zones3", Name = "World Walker", Stat = "Zones", Target = 8, Shards = 10, Icon = "🗺️" },
	{ Id = "reb1", Name = "Reborn", Stat = "Rebirths", Target = 1, Shards = 2, Icon = "🌀" },
	{ Id = "reb2", Name = "Cycle of Spirit", Stat = "Rebirths", Target = 5, Shards = 5, Icon = "🌀" },
	{ Id = "reb3", Name = "Eternal Ninja", Stat = "Rebirths", Target = 20, Shards = 12, Icon = "🌀" },
	{ Id = "kat1", Name = "Collector", Stat = "Katanas", Target = 5, Shards = 2, Icon = "🗡️" },
	{ Id = "kat2", Name = "Armory", Stat = "Katanas", Target = 12, Shards = 5, Icon = "🗡️" },
	{ Id = "kat3", Name = "Blade Museum", Stat = "Katanas", Target = 20, Shards = 12, Icon = "🗡️" },
}

Achievements.ById = {}
for index, def in ipairs(Achievements.List) do
	def.Order = index
	Achievements.ById[def.Id] = def
end

function Achievements.Progress(def, data): number
	local reader = Achievements.Stats[def.Stat]
	return if reader then reader(data) else 0
end

function Achievements.Describe(def): string
	if def.Stat == "Tier" then
		return "Become a " .. Tiers.Get(def.Target).Name
	end
	return string.format(STAT_TEXT[def.Stat] or "%s", Format.Abbrev(def.Target))
end

-- Number of finished-but-unclaimed trophies.
function Achievements.Claimable(data): number
	local n = 0
	local claimed = data.Achievements or {}
	for _, def in ipairs(Achievements.List) do
		if not claimed[def.Id] and Achievements.Progress(def, data) >= def.Target then
			n += 1
		end
	end
	return n
end

return Achievements
