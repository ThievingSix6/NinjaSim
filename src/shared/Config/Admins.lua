--[[
	Who runs the admin panel.

	Owners can use every admin command and also appoint or remove admins. The
	game's creator (or the owner of the group that owns the game) is always an
	owner, and in Studio every tester is. Add more owners by user id here.

	Admins appointed in game are saved in a DataStore, so they stay admins in
	every server until an owner removes them. Admins here are permanent ones.
]]

return {
	Owners = {} :: { number }, -- e.g. { 123456789 }
	Admins = {} :: { number },
	ToggleKey = Enum.KeyCode.F2, -- opens the panel (admins only)
	MaxGrant = 1e15, -- the most coins/shards one command can give
}
