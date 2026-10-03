--[[
	Zones (areas). They are laid out west -> east along the X axis, one every
	Zones.Spacing studs, each a valley connected to the next by a gate.
	WorldBuilder generates terrain and props from Theme/Decor and the land shape
	in Config/ZoneLayouts (see shared/Landscape); EnemyService spawns Camps;
	BossService runs Boss.

	To add a zone: append an entry (it is placed automatically after the last one),
	add a layout in Config/ZoneLayouts, a decor function in server/World/ZoneDecor
	if you want a new look, and give it camps using enemy ids from Enemies.lua.

	Offsets are Vector2(x, z) relative to the zone centre. A zone's strip spans
	-Spacing/2 .. Spacing/2 in x (the entrance gate is on the west edge, at height 0)
	and -Depth/2 .. Depth/2 in z. The ground is not flat: Zones.WorldPosition
	returns points on the ground unless you pass a height.
]]

local Balance = require(script.Parent.Balance)
local ZoneLayouts = require(script.Parent.ZoneLayouts)
local Landscape = require(script.Parent.Parent.Landscape)

local Zones = {}

local rgb = Color3.fromRGB
local v2 = Vector2.new

Zones.Spacing = 560 -- centre-to-centre distance; each zone owns a strip this wide
Zones.Depth = 600 -- the land reaches -Depth/2 .. Depth/2 across the row
Zones.GroundY = 0

Zones.List = {
	{
		Id = "village", Name = "Ninja Village", Level = 1, CostLevel = nil,
		Egg = "village_egg", Boss = { Enemy = "BanditKing", Level = 8, Respawn = 150 },
		Camps = {
			{ Enemy = "TrainingDummy", Level = 1, Count = 6, Offset = v2(-125, -95), Radius = 20 },
			{ Enemy = "RogueNinja", Level = 3, Count = 6, Offset = v2(-15, 105), Radius = 24 },
			{ Enemy = "Bandit", Level = 6, Count = 5, Offset = v2(95, -110), Radius = 24 },
		},
		Theme = {
			Ground = Enum.Material.Grass, GroundColor = rgb(106, 160, 72),
			Path = Enum.Material.Cobblestone, PathColor = rgb(150, 140, 125),
			Rock = Enum.Material.Rock, RockColor = rgb(120, 115, 110),
			Accent = rgb(255, 170, 190),
		},
		Decor = "Village",
		Lighting = {
			ClockTime = 14.5, Brightness = 2.6, Ambient = rgb(90, 90, 100), OutdoorAmbient = rgb(140, 135, 130),
			FogColor = rgb(200, 220, 240), Density = 0.25, Haze = 0.5, AtmosphereColor = rgb(200, 215, 235), Glare = 0.2,
			Tint = rgb(255, 250, 245), Saturation = 0.15, Contrast = 0.08,
		},
	},
	{
		Id = "bamboo", Name = "Bamboo Forest", Level = 10, CostLevel = 7, CostKills = 45,
		Egg = "bamboo_egg", Boss = { Enemy = "AncientSamurai", Level = 23, Respawn = 180 },
		Camps = {
			{ Enemy = "BambooBandit", Level = 11, Count = 6, Offset = v2(-120, 110), Radius = 24 },
			{ Enemy = "ForestFox", Level = 15, Count = 6, Offset = v2(0, -115), Radius = 26 },
			{ Enemy = "MantisWarrior", Level = 20, Count = 5, Offset = v2(135, 105), Radius = 24 },
		},
		Theme = {
			Ground = Enum.Material.LeafyGrass, GroundColor = rgb(84, 130, 60),
			Path = Enum.Material.Mud, PathColor = rgb(110, 90, 62),
			Rock = Enum.Material.Slate, RockColor = rgb(96, 104, 96),
			Accent = rgb(150, 220, 120),
		},
		Decor = "Bamboo",
		Lighting = {
			ClockTime = 16, Brightness = 2.2, Ambient = rgb(80, 100, 80), OutdoorAmbient = rgb(110, 140, 110),
			FogColor = rgb(170, 210, 170), Density = 0.4, Haze = 1.6, AtmosphereColor = rgb(170, 220, 170), Glare = 0.1,
			Tint = rgb(240, 255, 240), Saturation = 0.2, Contrast = 0.1,
		},
	},
	{
		Id = "samurai", Name = "Samurai Village", Level = 25, CostLevel = 20, CostKills = 55,
		Egg = "samurai_egg", Boss = { Enemy = "IronShogun", Level = 46, Respawn = 200 },
		Camps = {
			{ Enemy = "Ashigaru", Level = 27, Count = 6, Offset = v2(-110, -100), Radius = 24 },
			{ Enemy = "Samurai", Level = 33, Count = 6, Offset = v2(10, 115), Radius = 24 },
			{ Enemy = "EliteSamurai", Level = 40, Count = 5, Offset = v2(145, -100), Radius = 22 },
		},
		Theme = {
			Ground = Enum.Material.Ground, GroundColor = rgb(150, 125, 90),
			Path = Enum.Material.Pavement, PathColor = rgb(210, 205, 195),
			Rock = Enum.Material.Limestone, RockColor = rgb(170, 160, 145),
			Accent = rgb(220, 50, 50),
		},
		Decor = "Samurai",
		Lighting = {
			ClockTime = 17.4, Brightness = 2.4, Ambient = rgb(110, 90, 80), OutdoorAmbient = rgb(150, 120, 100),
			FogColor = rgb(255, 200, 160), Density = 0.3, Haze = 1.2, AtmosphereColor = rgb(255, 190, 140), Glare = 0.6,
			Tint = rgb(255, 238, 220), Saturation = 0.15, Contrast = 0.1,
		},
	},
	{
		Id = "demon", Name = "Demon Valley", Level = 50, CostLevel = 40, CostKills = 65,
		Egg = "demon_egg", Boss = { Enemy = "DemonLord", Level = 82, Respawn = 220 },
		Camps = {
			{ Enemy = "Imp", Level = 52, Count = 7, Offset = v2(-140, 90), Radius = 26 },
			{ Enemy = "Demon", Level = 60, Count = 6, Offset = v2(-10, -110), Radius = 24 },
			{ Enemy = "OniBrute", Level = 70, Count = 4, Offset = v2(110, 115), Radius = 22 },
		},
		Theme = {
			Ground = Enum.Material.Sand, GroundColor = rgb(92, 40, 36),
			Path = Enum.Material.Brick, PathColor = rgb(78, 42, 38),
			Rock = Enum.Material.Basalt, RockColor = rgb(52, 40, 40),
			Accent = rgb(255, 80, 30), Lava = true,
		},
		Decor = "Demon",
		Lighting = {
			ClockTime = 19, Brightness = 1.6, Ambient = rgb(120, 50, 40), OutdoorAmbient = rgb(140, 60, 50),
			FogColor = rgb(160, 40, 30), Density = 0.45, Haze = 2.5, AtmosphereColor = rgb(200, 60, 40), Glare = 0.4,
			Tint = rgb(255, 220, 210), Saturation = 0.2, Contrast = 0.2,
		},
	},
	{
		Id = "shadow", Name = "Shadow Forest", Level = 90, CostLevel = 70, CostKills = 75,
		Egg = "shadow_egg", Boss = { Enemy = "ShadowMaster", Level = 138, Respawn = 240 },
		Camps = {
			{ Enemy = "ShadowWisp", Level = 92, Count = 7, Offset = v2(-120, -110), Radius = 26 },
			{ Enemy = "ShadowBeast", Level = 105, Count = 5, Offset = v2(0, 115), Radius = 24 },
			{ Enemy = "ShadeAssassin", Level = 120, Count = 5, Offset = v2(135, -105), Radius = 24 },
		},
		Theme = {
			Ground = Enum.Material.Asphalt, GroundColor = rgb(38, 32, 52),
			Path = Enum.Material.Concrete, PathColor = rgb(70, 60, 90),
			Rock = Enum.Material.Asphalt, RockColor = rgb(38, 32, 52),
			Accent = rgb(160, 90, 255),
		},
		Decor = "Shadow",
		Lighting = {
			ClockTime = 0.5, Brightness = 1.2, Ambient = rgb(70, 50, 110), OutdoorAmbient = rgb(80, 60, 130),
			FogColor = rgb(40, 20, 70), Density = 0.5, Haze = 2.2, AtmosphereColor = rgb(80, 50, 140), Glare = 0,
			Tint = rgb(225, 215, 255), Saturation = 0.1, Contrast = 0.2,
		},
	},
	{
		Id = "volcanic", Name = "Volcanic Fortress", Level = 150, CostLevel = 120, CostKills = 85,
		Egg = "magma_egg", Boss = { Enemy = "MagmaWarlord", Level = 218, Respawn = 260 },
		Camps = {
			{ Enemy = "EmberSoldier", Level = 152, Count = 7, Offset = v2(-110, 100), Radius = 26 },
			{ Enemy = "MagmaGolem", Level = 170, Count = 5, Offset = v2(10, -115), Radius = 22 },
			{ Enemy = "FlameSamurai", Level = 195, Count = 5, Offset = v2(145, 100), Radius = 24 },
		},
		Theme = {
			Ground = Enum.Material.Basalt, GroundColor = rgb(52, 40, 40),
			Path = Enum.Material.CrackedLava, PathColor = rgb(255, 90, 20),
			Rock = Enum.Material.Basalt, RockColor = rgb(52, 40, 40),
			Accent = rgb(255, 120, 20), Lava = true,
		},
		Decor = "Volcanic",
		Lighting = {
			ClockTime = 18.2, Brightness = 1.8, Ambient = rgb(120, 60, 40), OutdoorAmbient = rgb(150, 80, 50),
			FogColor = rgb(120, 50, 30), Density = 0.5, Haze = 3, AtmosphereColor = rgb(255, 110, 50), Glare = 1,
			Tint = rgb(255, 225, 200), Saturation = 0.25, Contrast = 0.2,
		},
	},
	{
		Id = "sky", Name = "Sky Temple", Level = 240, CostLevel = 195, CostKills = 95,
		Egg = "sky_egg", Boss = { Enemy = "StormKami", Level = 338, Respawn = 280 },
		Camps = {
			{ Enemy = "CloudMonk", Level = 242, Count = 7, Offset = v2(-140, -90), Radius = 26 },
			{ Enemy = "StormTengu", Level = 270, Count = 6, Offset = v2(-10, 110), Radius = 24 },
			{ Enemy = "ThunderGuardian", Level = 310, Count = 4, Offset = v2(110, -115), Radius = 22 },
		},
		Theme = {
			Ground = Enum.Material.Snow, GroundColor = rgb(236, 242, 255),
			Path = Enum.Material.Sandstone, PathColor = rgb(235, 205, 140),
			Rock = Enum.Material.Glacier, RockColor = rgb(210, 230, 255),
			Accent = rgb(255, 210, 90),
		},
		Decor = "Sky",
		Lighting = {
			ClockTime = 12, Brightness = 3.2, Ambient = rgb(140, 150, 170), OutdoorAmbient = rgb(190, 200, 220),
			FogColor = rgb(220, 235, 255), Density = 0.3, Haze = 0.8, AtmosphereColor = rgb(200, 225, 255), Glare = 1.5,
			Tint = rgb(250, 252, 255), Saturation = 0.1, Contrast = 0.05,
		},
	},
	{
		Id = "void", Name = "Void Realm", Level = 360, CostLevel = 310, CostKills = 110,
		Egg = "void_egg", Boss = { Enemy = "VoidEmperor", Level = 545, Respawn = 300 },
		Camps = {
			{ Enemy = "VoidWraith", Level = 362, Count = 7, Offset = v2(-120, 110), Radius = 26 },
			{ Enemy = "VoidKnight", Level = 420, Count = 5, Offset = v2(0, -115), Radius = 24 },
			{ Enemy = "Voidborn", Level = 490, Count = 4, Offset = v2(135, 105), Radius = 22 },
		},
		Theme = {
			Ground = Enum.Material.Salt, GroundColor = rgb(26, 12, 40),
			Path = Enum.Material.Ice, PathColor = rgb(150, 60, 220),
			Rock = Enum.Material.Salt, RockColor = rgb(26, 12, 40),
			Accent = rgb(230, 80, 255),
		},
		Decor = "Void",
		Lighting = {
			ClockTime = 3, Brightness = 1.4, Ambient = rgb(100, 50, 140), OutdoorAmbient = rgb(90, 40, 130),
			FogColor = rgb(30, 0, 50), Density = 0.45, Haze = 2, AtmosphereColor = rgb(120, 40, 180), Glare = 0.5,
			Tint = rgb(240, 220, 255), Saturation = 0.3, Contrast = 0.25,
		},
	},
	-- The Cursed Temple (2026-10-03): the hardcore endgame. Its own unlock at Level 500
	-- (Standalone: no need to unlock the Void first; reach it from the Areas menu). The
	-- surface is a blighted valley round a ruined temple; its gate leads down into the
	-- 100 floors below (Config/Temple, TempleService).
	{
		Id = "temple", Name = "The Cursed Temple", Level = 500, CostLevel = 480, CostKills = 70, Standalone = true,
		Boss = { Enemy = "CursedAbbot", Level = 600, Respawn = 300 },
		Camps = {
			{ Enemy = "CursedMonk", Level = 502, Count = 6, Offset = v2(-110, -100), Radius = 24 },
			{ Enemy = "TempleGhoul", Level = 515, Count = 6, Offset = v2(10, 115), Radius = 24 },
			{ Enemy = "HollowSamurai", Level = 530, Count = 4, Offset = v2(145, -100), Radius = 22 },
		},
		Theme = {
			Ground = Enum.Material.Mud, GroundColor = rgb(48, 30, 30),
			Path = Enum.Material.Cobblestone, PathColor = rgb(80, 60, 60),
			Rock = Enum.Material.Basalt, RockColor = rgb(40, 28, 30),
			Accent = rgb(255, 50, 40),
		},
		Decor = "Cursed",
		Lighting = {
			ClockTime = 19.2, Brightness = 1.2, Ambient = rgb(110, 50, 50), OutdoorAmbient = rgb(120, 60, 60),
			FogColor = rgb(70, 10, 15), Density = 0.42, Haze = 2.2, AtmosphereColor = rgb(160, 40, 40), Glare = 0.3,
			Tint = rgb(255, 215, 210), Saturation = 0.05, Contrast = 0.25,
		},
	},
}

Zones.ById = {}
for index, zone in ipairs(Zones.List) do
	local layout = ZoneLayouts[zone.Id] or {}
	local spawnX = layout.Spawn or (-Zones.Spacing / 2 + 50)
	zone.Index = index
	zone.Layout = layout
	zone.Center = Vector3.new((index - 1) * Zones.Spacing, Zones.GroundY, 0)
	zone.Spawn = zone.Center + Vector3.new(spawnX, 4, 0)
	zone.EggOffset = layout.Egg or v2(spawnX + 25, -38)
	zone.BoardOffset = layout.Board or v2(spawnX + 20, 36) -- leaderboard (village only)
	zone.BossOffset = layout.Boss or v2(70, 105)
	zone.Cost = if zone.CostLevel then Balance.CoinsForKills(zone.CostLevel, zone.CostKills or 50) else 0
	Landscape.Compile(zone, Zones.Spacing, Zones.Depth, index == 1, index == #Zones.List)
	zone.Spawn = zone.Center + Vector3.new(spawnX, Landscape.Height(zone, spawnX, 0) + 4, 0)
	Zones.ById[zone.Id] = zone
end

function Zones.Get(id: string)
	return Zones.ById[id]
end

-- World position of a zone-local offset; on the ground unless a height is given.
function Zones.WorldPosition(zone, offset: Vector2, y: number?): Vector3
	return zone.Center + Vector3.new(offset.X, y or Landscape.Height(zone, offset.X, offset.Y), offset.Y)
end

-- Ground height (world y) of the designed land at a world position, without a raycast.
function Zones.GroundAt(position: Vector3): number
	local zone = Zones.At(position)
	return zone.Center.Y + Landscape.Height(zone, position.X - zone.Center.X, position.Z - zone.Center.Z)
end

-- Which zone a world position lies in (by x coordinate, gates included).
function Zones.At(position: Vector3)
	local index = math.floor((position.X + Zones.Spacing / 2) / Zones.Spacing) + 1
	return Zones.List[math.clamp(index, 1, #Zones.List)]
end

return Zones
