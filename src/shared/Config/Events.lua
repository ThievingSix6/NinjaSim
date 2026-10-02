--[[
	Server-wide events: every few minutes the whole server gets a short reward
	frenzy, announced with a banner and a countdown on the HUD. Playing with
	friends also gives a stacking bonus. Tune the numbers here.
]]

return {
	FirstDelay = 180, -- seconds after the server starts before the first event
	Interval = 600, -- seconds between event starts
	Duration = 180,

	List = {
		{ Id = "CoinFrenzy", Name = "COIN FRENZY", Desc = "2x Coins for everyone!", Icon = "🪙", Coins = 2, XP = 1, Color = Color3.fromRGB(255, 202, 60) },
		{ Id = "XPStorm", Name = "XP STORM", Desc = "2x XP for everyone!", Icon = "⚡", Coins = 1, XP = 2, Color = Color3.fromRGB(88, 184, 255) },
		{ Id = "NinjaRush", Name = "NINJA RUSH", Desc = "1.5x Coins and XP!", Icon = "🔥", Coins = 1.5, XP = 1.5, Color = Color3.fromRGB(255, 90, 60) },
	},

	FriendBonus = 0.1, -- +10% Coins and XP per friend in the server
	MaxFriends = 3,
}
