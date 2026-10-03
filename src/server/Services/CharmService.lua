--[[
	CharmService: the charm inventory (Config/Charms). Charms drop through LootService
	(the same personal light pillars as hats) and land here via Add.

	Requests (RequestService):
	  PlaceCharm(uid, x, y, grid?)  put a charm in a grid at column x, row y (its top
	                         cell); moving one already in a grid works the same way.
	                         grid: nil = yours, or a hired ninja's id (Config/Hires)
	  StashCharm(uid)        take it out of the grid (it stops counting)
	  LockCharm(uid)         toggle the lock (locked charms can't be salvaged)
	  SalvageCharm(uid)      break it down for Spirit Shards (not locked, not in a trade)
	Admin: DropCharm (AdminService).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Charms = require(Shared.Config.Charms)
local TableUtil = require(Shared.Util.TableUtil)

local CharmService = {}

local services
local rng = Random.new()

local function owned(player: Player, uid: any)
	local data = services.DataService:Get(player)
	if not data or type(uid) ~= "string" or type(data.Charms) ~= "table" then
		return data, nil
	end
	local charm = data.Charms[uid]
	return data, if Charms.Valid(charm) then charm else nil
end

local function inTrade(player: Player, uid: string): boolean
	return services.TradeService ~= nil and services.TradeService:IsOffered(player, "Charm", uid)
end

-- Stores a new charm (dropping it into the first free grid spot, so it works right
-- away). Returns the uid, or nil when storage is full.
function CharmService:Add(player: Player, charm): string?
	local data = services.DataService:Get(player)
	if not data or not Charms.Valid(charm) then
		return nil
	end
	if TableUtil.Count(data.Charms) >= Charms.Storage then
		return nil
	end
	data.CharmSerial = (tonumber(data.CharmSerial) or 0) + 1
	local uid = tostring(data.CharmSerial)
	charm.X, charm.Y, charm.G = nil, nil, nil
	data.Charms[uid] = charm
	local x, y = Charms.FreeSpot(data, uid)
	charm.X, charm.Y = x, y
	services.DataService:Changed(player, "Charms")
	services.DataService:Changed(player, "CharmSerial")
	return uid
end

function CharmService:Place(player: Player, uid: any, x: any, y: any, grid: any): (boolean, string?)
	local data, charm = owned(player, uid)
	if not data or not charm then
		return false, "You don't have that charm"
	end
	if grid ~= nil and (type(grid) ~= "string" or type(data.Hires) ~= "table" or not data.Hires[grid]) then
		return false, "You haven't hired that ninja"
	end
	if type(x) ~= "number" or type(y) ~= "number" or not Charms.Fits(data, uid, x, y, grid) then
		return false, "It doesn't fit there"
	end
	charm.X, charm.Y, charm.G = x, y, grid
	services.DataService:Changed(player, "Charms")
	return true, nil
end

function CharmService:Stash(player: Player, uid: any): (boolean, string?)
	local data, charm = owned(player, uid)
	if not data or not charm then
		return false, "You don't have that charm"
	end
	charm.X, charm.Y, charm.G = nil, nil, nil
	services.DataService:Changed(player, "Charms")
	return true, nil
end

function CharmService:ToggleLock(player: Player, uid: any): (boolean, string?)
	local data, charm = owned(player, uid)
	if not data or not charm then
		return false, "You don't have that charm"
	end
	charm.Lock = if charm.Lock then nil else true
	services.DataService:Changed(player, "Charms")
	return true, nil
end

function CharmService:Salvage(player: Player, uid: any): (boolean, string?)
	local data, charm = owned(player, uid)
	if not data or not charm then
		return false, "You don't have that charm"
	end
	if charm.Lock then
		return false, "Unlock it first"
	end
	if inTrade(player, uid) then
		return false, "Take it out of the trade first"
	end
	data.Charms[uid] = nil
	services.DataService:Changed(player, "Charms")
	local shards = Charms.SalvageValue(charm)
	services.ProgressionService:AddShards(player, shards)
	return true, string.format("Salvaged %s for %d Spirit Shards", Charms.Name(charm), shards)
end

-- Admin / test: drop a charm at the player's feet. kind: a rarity, a size, "Skill"
-- or "Torch" (empty = a normal roll).
function CharmService:AdminDrop(player: Player, kind: string?): (boolean, string?)
	local data = services.DataService:Get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not data or not root then
		return false, "They have no character"
	end
	local stats = services.StatService:Get(player)
	local luck = if stats then stats.Luck else 0
	local charm
	if kind == "Torch" then
		charm = Charms.RollUnique("hexfire", data.Level, rng)
	elseif kind == "Skill" then
		charm = Charms.Roll(data.Level, luck, rng, "Grand", nil, "any") -- any: a random skill
	elseif kind and Charms.SizeById[kind] then
		charm = Charms.Roll(data.Level, luck, rng, kind)
	elseif kind and Charms.RarityByName[kind] then
		charm = Charms.Roll(data.Level, luck, rng, nil, kind)
	else
		charm = Charms.Roll(data.Level, luck, rng)
	end
	local at = root.Position + root.CFrame.LookVector * 6
	services.LootService:Drop(player, Vector3.new(at.X, services.ZoneService:GroundHeight(at), at.Z), charm, "Charm")
	return true, string.format("Dropped %s (%s) for %s", Charms.Name(charm), charm.R, player.DisplayName)
end

-- Old or hand-edited saves: drop malformed charms and clear bad grid spots.
local function sanitize(data): boolean
	local changed = false
	if type(data.Charms) ~= "table" then
		data.Charms = {}
		return true
	end
	for uid, charm in pairs(data.Charms) do
		if not Charms.Valid(charm) then
			data.Charms[uid] = nil
			changed = true
		end
	end
	local active = Charms.Active(data)
	for id in pairs(type(data.Hires) == "table" and data.Hires or {}) do
		for uid in pairs(Charms.Active(data, id)) do
			active[uid] = true
		end
	end
	for uid, charm in pairs(data.Charms) do
		if (charm.X or charm.Y or charm.G) and not active[uid] then
			charm.X, charm.Y, charm.G = nil, nil, nil
			changed = true
		end
	end
	return changed
end

function CharmService:Init(registry)
	services = registry
end

function CharmService:Start()
	services.DataService:OnLoaded(function(player, data)
		if sanitize(data) then
			services.DataService:Changed(player, "Charms")
		end
	end)
end

return CharmService
