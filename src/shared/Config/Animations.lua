--[[
	Movement animations for R15 characters: Roblox's free Ninja Animation Package.
	These are Roblox-owned catalog animations, so any game can play them. The
	server writes them into each character's Animate script when it spawns
	(CharacterService), which also replaces the player's own avatar animations.

	Set Enabled = false to keep players' own animations. The Ninja pack's idles are
	656117400 and 656118341 if you want the crouched stance back. Ids are from
	create.roblox.com/docs/animation/using (catalog animation ids).
]]

return {
	Enabled = true,
	-- Animate script child -> { Animation name = id }
	Sets = {
		-- the Ninja pack's idle is a deep crouch, which looked wrong standing still
		-- (justin, 2026-10-01), so idle stays Roblox's standard standing idle
		idle = { Animation1 = 507766388, Animation2 = 507766666 },
		walk = { WalkAnim = 656121766 },
		run = { RunAnim = 656118852 },
		jump = { JumpAnim = 656117878 },
		fall = { FallAnim = 656115606 },
		climb = { ClimbAnim = 656114359 },
		swim = { Swim = 656119721 },
		swimidle = { SwimIdle = 656121397 },
	},
}
