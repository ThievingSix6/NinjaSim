--[[
	AchievementService: claims trophy rewards (Config/Achievements). Progress
	is derived from the save itself, so the only state is which ones are claimed.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Achievements = require(ReplicatedStorage:WaitForChild("Shared").Config.Achievements)

local AchievementService = {}

local services

function AchievementService:Claim(player: Player, id: any): (boolean, string?)
	local data = services.DataService:Get(player)
	if not data then
		return false, "Still loading"
	end
	local def = type(id) == "string" and Achievements.ById[id]
	if not def then
		return false, "Unknown trophy"
	end
	if data.Achievements[def.Id] then
		return false, "Already claimed"
	end
	if Achievements.Progress(def, data) < def.Target then
		return false, "Not finished yet"
	end
	data.Achievements[def.Id] = true
	services.DataService:Changed(player, "Achievements")
	services.ProgressionService:AddShards(player, def.Shards)
	return true, def.Name .. "  +" .. def.Shards .. " 💎"
end

-- Claims every finished trophy in one request.
function AchievementService:ClaimAll(player: Player): (boolean, string?)
	local data = services.DataService:Get(player)
	if not data then
		return false, "Still loading"
	end
	local count, shards = 0, 0
	for _, def in ipairs(Achievements.List) do
		if not data.Achievements[def.Id] and Achievements.Progress(def, data) >= def.Target then
			data.Achievements[def.Id] = true
			count += 1
			shards += def.Shards
		end
	end
	if count == 0 then
		return false, "Nothing to claim yet"
	end
	services.DataService:Changed(player, "Achievements")
	services.ProgressionService:AddShards(player, shards)
	return true, count .. (if count == 1 then " trophy" else " trophies") .. "  +" .. shards .. " 💎"
end

function AchievementService:Init(registry)
	services = registry
end

function AchievementService:Start() end

return AchievementService
