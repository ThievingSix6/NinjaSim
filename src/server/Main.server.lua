--[[
	NinjaSim server bootstrap. Builds the world, then initialises and starts every
	service in dependency order. Services receive a shared registry so they can
	call each other without circular requires.
]]

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Create the remotes first so clients can connect even if something below fails.
require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net")).Event("DataSync")

local Services = script.Parent:WaitForChild("Services")
local World = script.Parent:WaitForChild("World")

-- Collision groups: players pass through each other and through enemies,
-- enemies pass through each other (keeps crowds from jamming).
PhysicsService:RegisterCollisionGroup("Players")
PhysicsService:RegisterCollisionGroup("Enemies")
PhysicsService:CollisionGroupSetCollidable("Players", "Players", false)
PhysicsService:CollisionGroupSetCollidable("Players", "Enemies", false)
PhysicsService:CollisionGroupSetCollidable("Enemies", "Enemies", false)

-- Nothing below is allowed to stop the server: a failure is reported and the
-- rest of the game still starts (a broken prop must never mean "no enemies").
local t0 = os.clock()
local builtOk, buildErr = pcall(function()
	require(World.WorldBuilder).Build()
end)
if builtOk then
	print(string.format("[NinjaSim] World built in %.2fs", os.clock() - t0))
else
	warn("[NinjaSim] World build error (continuing): " .. tostring(buildErr))
end

local ORDER = {
	"DataService",
	"StatService",
	"ZoneService",
	"CharacterService",
	"HealthService",
	"ProgressionService",
	"EnemyService",
	"BossService",
	"CombatService",
	"SkillService",
	"LootService",
	"RebirthService",
	"ShopService",
	"PetService",
	"InventoryService",
	"EventService",
	"GiftService",
	"LeaderboardService",
	"AchievementService",
	"AdminService",
	"RequestService",
}

local registry = {}
for _, name in ipairs(ORDER) do
	local ok, service = pcall(require, Services:WaitForChild(name))
	if ok then
		registry[name] = service
	else
		warn("[NinjaSim] " .. name .. " failed to load: " .. tostring(service))
	end
end
for _, name in ipairs(ORDER) do
	local service = registry[name]
	if service then
		local ok, err = pcall(function()
			service:Init(registry)
		end)
		if not ok then
			warn("[NinjaSim] " .. name .. " failed to init: " .. tostring(err))
		end
	end
end
for _, name in ipairs(ORDER) do
	local ok, err = pcall(function()
		if registry[name] then
			registry[name]:Start()
		end
	end)
	if not ok then
		warn("[NinjaSim] " .. name .. " failed to start: " .. tostring(err))
	end
end
print("[NinjaSim] Server ready")
