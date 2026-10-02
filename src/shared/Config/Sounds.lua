--[[
	All sound ids in one place. The defaults use sounds that ship inside the
	Roblox client (rbxasset://), so they work with no uploads.

	PLACEHOLDER: swap any of these for your own uploaded audio
	("rbxassetid://123...") to upgrade the soundscape. Background music is off
	until ids are added to `Playlist` (or per area in `Music`).
]]

return {
	Swing = { Id = "rbxasset://sounds/swordslash.wav", Volume = 0.45, Pitch = { 0.95, 1.15 } },
	Finisher = { Id = "rbxasset://sounds/swordslash.wav", Volume = 0.7, Pitch = { 0.7, 0.75 } },
	Slam = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.8, Pitch = { 0.45, 0.5 } },
	Hit = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.35, Pitch = { 1.3, 1.6 } },
	Crit = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.6, Pitch = { 0.8, 0.9 } },
	Kill = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.4, Pitch = { 1.4, 1.6 } },
	Coin = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.25, Pitch = { 2.0, 2.4 } },
	LevelUp = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.8, Pitch = { 0.8, 0.8 } },
	TierUp = { Id = "rbxasset://sounds/unsheath.wav", Volume = 1, Pitch = { 0.8, 0.8 } },
	Rebirth = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 1, Pitch = { 0.5, 0.5 } },
	Click = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.25, Pitch = { 2.6, 2.8 } },
	Hover = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.08, Pitch = { 3.2, 3.4 } },
	Error = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.35, Pitch = { 0.45, 0.5 } },
	Purchase = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.5, Pitch = { 1.8, 1.8 } },
	EggShake = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.25, Pitch = { 2.2, 2.6 } },
	EggHatch = { Id = "rbxasset://sounds/unsheath.wav", Volume = 0.8, Pitch = { 1.2, 1.2 } },
	BossSpawn = { Id = "rbxasset://sounds/unsheath.wav", Volume = 1, Pitch = { 0.5, 0.5 } },
	BossSlam = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.9, Pitch = { 0.4, 0.5 } },
	Hurt = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.3, Pitch = { 0.6, 0.7 } },
	DoubleJump = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.35, Pitch = { 1.8, 2.0 } },
	Dodge = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.4, Pitch = { 1.25, 1.4 } },
	Evade = { Id = "rbxasset://sounds/unsheath.wav", Volume = 0.45, Pitch = { 1.6, 1.7 } },
	Equip = { Id = "rbxasset://sounds/unsheath.wav", Volume = 0.5, Pitch = { 1.1, 1.2 } },

	-- Background music: these tracks play one after another and repeat, in every area.
	-- Upload your audio, then paste each id here, e.g. "rbxassetid://1234567890".
	Playlist = {
		"rbxassetid://110448037253151",
		"rbxassetid://108180487728496",
	},
	MusicVolume = 0.5, -- times the player's Music setting

	-- Optional: an area with its own music instead of the playlist. A single id, or a
	-- list of ids that play in turn.
	Music = {
		-- zoneId = "rbxassetid://...",
	},
}
