--[[
	Permanent Spirit Shard upgrades. Never reset by rebirth.
	Cost of level n (0-based) = BaseCost * Growth^n, rounded.
]]

local Upgrades = {}

Upgrades.List = {
	{ Id = "XP", Name = "Spirit Wisdom", Icon = "📘", Desc = "+10% XP per level", Per = 0.10, Max = 30, BaseCost = 2, Growth = 1.32 },
	{ Id = "Coins", Name = "Golden Pouch", Icon = "💰", Desc = "+10% Coins per level", Per = 0.10, Max = 30, BaseCost = 2, Growth = 1.32 },
	{ Id = "Damage", Name = "Blade Mastery", Icon = "⚔️", Desc = "+8% Damage per level", Per = 0.08, Max = 40, BaseCost = 3, Growth = 1.3 },
	{ Id = "Speed", Name = "Wind Step", Icon = "💨", Desc = "+2 Walk Speed per level", Per = 2, Max = 10, BaseCost = 2, Growth = 1.45 },
	{ Id = "AttackSpeed", Name = "Flurry", Icon = "🌀", Desc = "+4% Attack Speed per level", Per = 0.04, Max = 15, BaseCost = 4, Growth = 1.4 },
	{ Id = "Crit", Name = "Precision", Icon = "🎯", Desc = "+1% Critical Chance per level", Per = 0.01, Max = 20, BaseCost = 3, Growth = 1.35 },
	{ Id = "Luck", Name = "Fortune", Icon = "🍀", Desc = "+5% Egg Luck per level", Per = 0.05, Max = 20, BaseCost = 3, Growth = 1.38 },
	{ Id = "Respawn", Name = "Hunter's Call", Icon = "⏱️", Desc = "Enemies you defeat respawn 5% faster", Per = 0.05, Max = 10, BaseCost = 3, Growth = 1.45 },
	{ Id = "Extra", Name = "Double Drop", Icon = "🎁", Desc = "+2% chance for double rewards", Per = 0.02, Max = 20, BaseCost = 4, Growth = 1.36 },
	{ Id = "Shards", Name = "Soul Harvest", Icon = "💎", Desc = "+10% Spirit Shards from rebirth", Per = 0.10, Max = 20, BaseCost = 5, Growth = 1.4 },
}

Upgrades.ById = {}
for index, upgrade in ipairs(Upgrades.List) do
	upgrade.Order = index
	Upgrades.ById[upgrade.Id] = upgrade
end

function Upgrades.Cost(upgrade, level: number): number
	return math.floor(upgrade.BaseCost * upgrade.Growth ^ level + 0.5)
end

return Upgrades
