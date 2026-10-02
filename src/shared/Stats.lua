--[[
	Derives a player's live stats from their save data. Used by the server for all
	authoritative math and by the client for display, so both always agree.
]]

local Config = script.Parent.Config
local Balance = require(Config.Balance)
local Tiers = require(Config.Tiers)
local Katanas = require(Config.Katanas)
local Pets = require(Config.Pets)
local Upgrades = require(Config.Upgrades)
local Shop = require(Config.Shop)
local Mastery = require(Config.Mastery)

local Stats = {}

local function upgradeValue(data, id: string): number
	local def = Upgrades.ById[id]
	return (data.Upgrades[id] or 0) * def.Per
end

function Stats.PetBonus(data)
	local bonus = { Damage = 0, XP = 0, Coins = 0, Luck = 0 }
	for _, uid in ipairs(data.EquippedPets) do
		local owned = data.Pets[uid]
		local pet = owned and Pets.ById[owned.Id]
		if pet then
			-- a mutation multiplies the whole bonus (Config/Mutations)
			for stat, value in pairs(Pets.BonusOf(pet, owned.Mutation)) do
				bonus[stat] = (bonus[stat] or 0) + value
			end
		end
	end
	return bonus
end

function Stats.BoostMultipliers(data)
	local m = { XP = 1, Coins = 1, Damage = 1, Luck = 0, AttackSpeed = 0 }
	for id, seconds in pairs(data.Boosts) do
		local effect = Shop.BoostEffects[id]
		if effect and seconds > 0 then
			for stat, value in pairs(effect) do
				if stat == "Luck" or stat == "AttackSpeed" then
					m[stat] += value
				else
					m[stat] *= value
				end
			end
		end
	end
	return m
end

function Stats.Compute(data)
	local tier = Tiers.Get(data.Tier)
	local katana = Katanas.ById[data.EquippedKatana] or Katanas.ById.brown_katana
	local pets = Stats.PetBonus(data)
	local boosts = Stats.BoostMultipliers(data)
	local rebirth = Balance.RebirthBonus(data.Rebirths)
	local suit = Mastery.WornTier(data)
	local mastery = Mastery.Of(data, suit.Id)

	local damage = Balance.BaseDamage(data.Level)
		* tier.Power
		* katana.Mult
		* (1 + rebirth * 0.5)
		* (1 + upgradeValue(data, "Damage"))
		* (1 + pets.Damage)
		* boosts.Damage
		* (1 + Mastery.DamagePerLevel * mastery)

	local attackSpeed = (1 + upgradeValue(data, "AttackSpeed")) * (1 + boosts.AttackSpeed)
	local sandals = if (data.Utility.swift_sandals or 0) > 0 then 3 else 0

	return {
		Damage = math.floor(damage),
		XPMult = (1 + rebirth) * (1 + upgradeValue(data, "XP")) * (1 + pets.XP) * boosts.XP,
		CoinMult = (1 + rebirth) * (1 + upgradeValue(data, "Coins")) * (1 + pets.Coins) * boosts.Coins,
		Luck = upgradeValue(data, "Luck") + pets.Luck + boosts.Luck,
		AttackInterval = math.max(Balance.MinAttackInterval, Balance.BaseAttackInterval / attackSpeed),
		CritChance = Balance.BaseCritChance + upgradeValue(data, "Crit"),
		CritMult = Balance.CritMultiplier,
		WalkSpeed = Balance.BaseWalkSpeed + tier.SpeedBonus + upgradeValue(data, "Speed") + sandals,
		MaxHealth = Balance.PlayerMaxHealth(data.Level, tier.HealthMult),
		-- out-of-combat regen (HealthService): fraction of MaxHealth per second, after
		-- RegenDelay seconds without taking damage. Items can raise / shorten these.
		HealthRegen = Balance.HealthRegen,
		RegenDelay = Balance.RegenDelay,
		RespawnMult = 1 - upgradeValue(data, "Respawn"),
		ExtraChance = upgradeValue(data, "Extra"),
		ShardMult = 1 + upgradeValue(data, "Shards"),
		PetSlots = Pets.BaseSlots + (data.Utility.pet_slot or 0),
		PetStorage = Pets.BaseStorage + 40 * (data.Utility.pet_storage or 0),
		RebirthBonus = rebirth,
		PetBonus = pets,
		TierName = tier.Name,
		Suit = suit.Id,
		Mastery = mastery,
		KatanaName = katana.Name,
	}
end

-- Damage a given katana would give, holding everything else equal (for compare UI).
function Stats.DamageWith(data, katanaId: string): number
	local current = Katanas.ById[data.EquippedKatana] or Katanas.ById.brown_katana
	local other = Katanas.ById[katanaId]
	if not other then
		return 0
	end
	return math.floor(Stats.Compute(data).Damage / current.Mult * other.Mult)
end

-- ===== Hats (Config/Hats, LootService) =====
-- The equipped hat's base stats and affixes: Damage, CritChance, MaxHealth, WalkSpeed,
-- AttackInterval, XPMult, CoinMult, Luck, HealthRegen, RegenDelay, plus LifeSteal
-- (% of max HP healed per kill) and HatProcs ({ Skill, Chance } on-hit procs).
local Hats = require(Config.Hats)
local computeBase = Stats.Compute
function Stats.Compute(data)
	return Hats.ApplyToStats(computeBase(data), data, Balance)
end
-- ===== end Hats =====

return Stats
