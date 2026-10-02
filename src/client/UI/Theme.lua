--[[
	Visual language for all UI, modelled on bright Roblox simulator menus:
	candy-coloured gradient buttons with diagonal shine stripes, thick ink
	outlines, white rounded text with a dark stroke, and dark slate window
	bodies so the colourful cards pop.

	Paint pairs are {top, bottom} gradient colours; Kit.Paint applies them.
]]
local rgb = Color3.fromRGB

local Theme = {
	-- outlines and dark surfaces
	Ink = rgb(26, 22, 40),
	Body = rgb(52, 64, 82),
	BodyDark = rgb(32, 40, 56),
	Well = rgb(24, 30, 44),
	Tile = rgb(66, 80, 100),

	-- text
	Text = rgb(255, 255, 255),
	SubText = rgb(206, 216, 236),
	Muted = rgb(146, 158, 182),

	-- accents used in text and small highlights
	Gold = rgb(255, 214, 64),
	Shard = rgb(110, 242, 230),
	XP = rgb(100, 200, 255),
	Green = rgb(130, 236, 70),
	Red = rgb(255, 84, 96),
	Purple = rgb(196, 120, 255),
	Pink = rgb(255, 110, 170),
	Orange = rgb(255, 160, 50),
	White = rgb(255, 255, 255),
	Black = rgb(0, 0, 0),

	-- older names still used around the code
	Bg = rgb(24, 30, 44),
	Panel = rgb(44, 55, 72),
	Panel2 = rgb(58, 71, 90),
	Panel3 = rgb(84, 96, 118),
	Stroke = rgb(26, 22, 40),
	Accent = rgb(255, 84, 120),
	AccentDark = rgb(200, 40, 80),

	Paint = {
		Green = { rgb(160, 248, 70), rgb(62, 184, 26) },
		Red = { rgb(255, 104, 104), rgb(214, 32, 48) },
		Pink = { rgb(255, 112, 176), rgb(226, 38, 106) },
		Blue = { rgb(104, 210, 255), rgb(32, 120, 236) },
		Sky = { rgb(150, 226, 255), rgb(64, 168, 244) },
		Gold = { rgb(255, 232, 92), rgb(255, 160, 18) },
		Orange = { rgb(255, 190, 70), rgb(246, 102, 22) },
		Purple = { rgb(214, 130, 255), rgb(132, 52, 228) },
		Cyan = { rgb(120, 248, 236), rgb(24, 170, 204) },
		Grey = { rgb(210, 216, 226), rgb(126, 134, 152) },
		Dark = { rgb(98, 112, 134), rgb(60, 70, 90) },
		Slate = { rgb(52, 64, 82), rgb(32, 40, 56) },
		Ink = { rgb(40, 36, 60), rgb(22, 18, 34) },
	},

	-- rarity -> paint
	RarityPaint = {
		Common = "Grey",
		Uncommon = "Green",
		Rare = "Blue",
		Epic = "Purple",
		Legendary = "Gold",
		Mythic = "Red",
		Divine = "Cyan",
		Secret = "Pink",
	},

	FontTitle = Enum.Font.FredokaOne,
	FontHeavy = Enum.Font.FredokaOne,
	FontBold = Enum.Font.FredokaOne,
	FontBody = Enum.Font.GothamBold,
	FontNumber = Enum.Font.FredokaOne,
	FontBig = Enum.Font.LuckiestGuy,

	Radius = 12,
	RadiusSmall = 9,
}

return Theme
