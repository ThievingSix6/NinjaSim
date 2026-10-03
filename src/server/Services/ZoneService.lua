--[[
	ZoneService: tracks which zone each player is in, handles zone unlock purchases
	and teleports, and enforces locked zones + basic movement sanity on the server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)

local ZoneService = {}
ZoneService.PlayersIn = {} :: { [string]: { Player } }

local services
local lastPositions: { [Player]: Vector3 } = {}
local teleportGrace: { [Player]: number } = {}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.RespectCanCollide = true

function ZoneService:GroundHeight(position: Vector3): number
	local filter = { workspace.Terrain }
	local world = workspace:FindFirstChild("World")
	if world then
		table.insert(filter, world)
	end
	rayParams.FilterDescendantsInstances = filter
	-- far below the valley (the Cursed Temple's halls): the floor just under the point
	if position.Y < Zones.GroundY - 100 then
		local below = workspace:Raycast(position + Vector3.new(0, 20, 0), Vector3.new(0, -120, 0), rayParams)
		if below then
			return below.Position.Y
		end
	end
	local result = workspace:Raycast(Vector3.new(position.X, 300, position.Z), Vector3.new(0, -600, 0), rayParams)
	return if result then result.Position.Y else Zones.GroundY
end

function ZoneService:GetZone(player: Player)
	return Zones.Get(player:GetAttribute("Zone") or "village") or Zones.List[1]
end

function ZoneService:MarkTeleported(player: Player)
	teleportGrace[player] = os.clock() + 2
end

function ZoneService:CanUnlock(player: Player, zone): (boolean, string?)
	local data = services.DataService:Get(player)
	if not data then
		return false, "Data not loaded"
	end
	if data.Zones[zone.Id] then
		return false, "Already unlocked"
	end
	local previous = Zones.List[zone.Index - 1]
	if previous and not zone.Standalone and not data.Zones[previous.Id] then
		return false, "Unlock " .. previous.Name .. " first"
	end
	if data.Level < zone.Level then
		return false, "Requires Level " .. zone.Level
	end
	if data.Coins < zone.Cost then
		return false, "Need " .. Format.Abbrev(zone.Cost) .. " Coins"
	end
	return true
end

function ZoneService:Unlock(player: Player, zoneId: string): (boolean, string?)
	local zone = Zones.Get(zoneId)
	if not zone then
		return false, "Unknown zone"
	end
	local ok, reason = self:CanUnlock(player, zone)
	if not ok then
		return false, reason
	end
	if not services.DataService:Spend(player, "Coins", zone.Cost) then
		return false, "Not enough Coins"
	end
	local data = services.DataService:Get(player)
	data.Zones[zone.Id] = true
	services.DataService:Changed(player, "Zones")
	Net.Event("Notify"):FireClient(player, { Text = zone.Name .. " unlocked!", Color = zone.Theme.Accent, Big = true })
	return true
end

function ZoneService:Teleport(player: Player, zoneId: string): (boolean, string?)
	local data = services.DataService:Get(player)
	local zone = Zones.Get(zoneId)
	if not data or not zone then
		return false, "Unknown zone"
	end
	if not data.Zones[zone.Id] then
		return false, "Zone is locked"
	end
	self:MarkTeleported(player)
	services.CharacterService:SpawnAtZone(player, zone.Id)
	return true
end

local function setPlayerZone(player: Player, zone)
	local previous = player:GetAttribute("Zone")
	if previous == zone.Id then
		return
	end
	player:SetAttribute("Zone", zone.Id)
	local data = services.DataService:Get(player)
	if data and data.LastZone ~= zone.Id then
		data.LastZone = zone.Id
		services.DataService:Changed(player, "LastZone")
	end
	Net.Event("ZoneChanged"):FireClient(player, zone.Id)
end

local function tick()
	local buckets = {}
	for _, zone in ipairs(Zones.List) do
		buckets[zone.Id] = {}
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local data = services.DataService:Get(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if data and root then
			local pos = root.Position
			-- Movement sanity: large instant horizontal jumps that the server did not cause are reverted.
			local last = lastPositions[player]
			local graceUntil = teleportGrace[player] or 0
			if last and os.clock() > graceUntil then
				local flat = Vector3.new(pos.X - last.X, 0, pos.Z - last.Z).Magnitude
				if flat > 90 then
					root.CFrame = CFrame.new(last + Vector3.new(0, 3, 0))
					pos = last
				end
			end
			lastPositions[player] = pos

			local zone = Zones.At(pos)
			if data.Zones[zone.Id] then
				setPlayerZone(player, zone)
				table.insert(buckets[zone.Id], player)
			else
				-- walked into a locked zone (e.g. slipped past the gate): send back
				Net.Event("Notify"):FireClient(player, { Text = "🔒 " .. zone.Name .. " is locked. Unlock it from the Areas menu!", Color = Color3.fromRGB(255, 120, 120) })
				ZoneService:MarkTeleported(player)
				services.CharacterService:SpawnAtZone(player, player:GetAttribute("Zone"))
			end
		end
	end
	ZoneService.PlayersIn = buckets
end

function ZoneService:Init(registry)
	services = registry
end

function ZoneService:Start()
	Players.PlayerRemoving:Connect(function(player)
		lastPositions[player] = nil
		teleportGrace[player] = nil
	end)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			lastPositions[player] = nil
			ZoneService:MarkTeleported(player)
		end)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function()
			lastPositions[player] = nil
			ZoneService:MarkTeleported(player)
		end)
	end
	task.spawn(function()
		while true do
			task.wait(0.5)
			local ok, err = pcall(tick)
			if not ok then
				warn("[ZoneService] " .. tostring(err))
			end
		end
	end)
end

return ZoneService
