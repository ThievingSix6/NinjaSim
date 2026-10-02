--[[
	Default save data for a brand-new player. New fields added here are filled
	into existing saves automatically (TableUtil.Reconcile), so it is safe to grow.
	Keep it JSON-friendly: string keys or plain arrays, no Instances, no nil holes.
]]

return {
	Version = 1,

	Level = 1,
	XP = 0,
	Coins = 0,
	Shards = 0,
	Rebirths = 0,

	Tier = 1, -- current ninja tier (resets on rebirth)
	BestTier = 1, -- highest tier ever reached

	Skills = { shuriken_storm = 1 }, -- [skillId] = upgrade level (Config/Skills); present = learned
	SkillSlots = { "shuriken_storm", "", "", "" }, -- skill on each hotkey slot (1-4), "" = empty

	Katanas = { brown_katana = true },
	EquippedKatana = "brown_katana",

	Pets = {}, -- [uid] = { Id = petId, Fav = bool, Mutation = "Golden"? } (Config/Mutations)
	EquippedPets = {}, -- array of uids
	PetSerial = 0,

	Hats = {}, -- [uid] = { Id = baseId, R = rarity, L = itemLevel, A = { { K = affix, V = value } }, P = { S = skill, C = chance }?, Lock = true? } (Config/Hats)
	EquippedHat = "", -- uid of the worn hat, "" = none
	HatSerial = 0,

	Upgrades = {
		XP = 0, Coins = 0, Damage = 0, Speed = 0, AttackSpeed = 0,
		Crit = 0, Luck = 0, Respawn = 0, Extra = 0, Shards = 0,
	},

	Cosmetics = {}, -- [cosmeticId] = true
	Equipped = { Aura = "", Trail = "", KillEffect = "", Title = "" },
	Utility = {}, -- [utilityId] = count
	Boosts = {}, -- [boostId] = seconds remaining (only ticks while online)

	Zones = { village = true },
	LastZone = "village",

	Favorites = {}, -- ["katana:<id>"] / ["cosmetic:<id>"] = true
	Codes = {}, -- [CODE] = true
	Achievements = {}, -- [achievementId] = true once claimed
	AutoDelete = {}, -- [petId] = true: hatches of this pet are turned straight into nothing (keeps storage clean)
	Daily = { Day = 0, Streak = 0 }, -- last login day (unix days) and current streak

	Lifetime = {
		Kills = 0, BossKills = 0, EggsOpened = 0, PlayTime = 0, CoinsEarned = 0, HighestLevel = 1,
	},

	Settings = {
		Music = 0.5, SFX = 0.8, DamageNumbers = true, ScreenShake = true,
		OtherPets = true, LowGraphics = false, AutoSwing = false, Guide = true,
	},
}
