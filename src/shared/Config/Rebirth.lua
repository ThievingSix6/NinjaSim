--[[
	Rebirth milestones: extra content unlocked at specific rebirth counts.
	Formulas (requirement, bonus, shards) live in Balance.

	What rebirth resets:  Level, XP, Coins, current Ninja tier, unlocked zones.
	What rebirth keeps:   Shards, upgrades, pets, katanas (re-locked by tier until
	                      re-earned), cosmetics, boosts, codes, settings, stats.
]]

local Rebirth = {}

Rebirth.Milestones = {
	{ Rebirths = 1, Text = "Unlocks Spirit Upgrades + Auto Swing" },
	{ Rebirths = 2, Text = "Unlocks the Spirit Egg" },
	{ Rebirths = 3, Text = "Unlocks the Spirit Flame aura" },
	{ Rebirths = 5, Text = "Unlocks the Reborn title" },
	{ Rebirths = 10, Text = "Unlocks the Soul Trail" },
	{ Rebirths = 15, Text = "Unlocks the Reborn Legend title" },
}

function Rebirth.NextMilestone(rebirths: number)
	for _, m in ipairs(Rebirth.Milestones) do
		if m.Rebirths > rebirths then
			return m
		end
	end
	return nil
end

return Rebirth
