--[[
	Redeemable codes (case-insensitive). Each can be redeemed once per player.
	Reward keys: Coins, Shards, Boost = {Id, Seconds}, Pet = petId, Cosmetic = id
	Set Expires = os.time() number to retire a code.
]]

return {
	RELEASE = { Coins = 250, Boost = { Id = "XP2", Seconds = 600 } },
	NINJA = { Coins = 500 },
	SHURIKEN = { Boost = { Id = "Coins2", Seconds = 900 } },
	SPIRIT = { Shards = 3 },
	FOXFRIEND = { Pet = "fox" },
}
