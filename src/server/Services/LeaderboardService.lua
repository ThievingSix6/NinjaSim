--[[
	LeaderboardService: a "Top Ninjas" board by the village spawn. Scores go to
	an OrderedDataStore (Rebirths first, then Level) so it is global across
	servers. If DataStores are unavailable (Studio without API access) it
	falls back to ranking the players in this server.

	Each row shows the ninja's avatar headshot (rbxthumb), and the #1 ninja stands
	beside the board as a full-size statue of their avatar on a gold pedestal.
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Format = require(Shared.Util.Format)

local LeaderboardService = {}

local services
local store: OrderedDataStore? = nil
local rowsFrame: Frame
local boardFrame: CFrame
local folder: Model
local statueOf: number? = nil
local names: { [number]: string } = {}
local REFRESH = 60
local SHOWN = 10
local RANK_COLORS = { Color3.fromRGB(255, 205, 70), Color3.fromRGB(210, 215, 230), Color3.fromRGB(215, 140, 80) }

local function score(data): number
	return data.Rebirths * 10000 + math.min(data.Level, 9999)
end

local function describe(value: number): string
	local rebirths, level = value // 10000, value % 10000
	return (if rebirths > 0 then "🌀 " .. Format.Abbrev(rebirths) .. "   " else "") .. "Lv " .. Format.Abbrev(level)
end

local function nameFor(userId: number): string
	if names[userId] then
		return names[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		names[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	names[userId] = if ok and name then name else "Ninja " .. userId
	return names[userId]
end

local function buildBoard()
	local zone = Zones.List[1]
	local base = Zones.WorldPosition(zone, zone.BoardOffset)
	local faceTo = Vector3.new(zone.Spawn.X, base.Y, zone.Spawn.Z)
	local cf = CFrame.lookAt(base, faceTo)
	folder = Instance.new("Model")
	folder.Name = "Leaderboard"
	boardFrame = cf
	local function part(size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): Part
		local p = Instance.new("Part")
		p.Anchored = true
		p.Size = size
		p.CFrame = cf * offset
		p.Color = color
		p.Material = material
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = folder
		return p
	end
	local wood = Color3.fromRGB(92, 58, 38)
	part(Vector3.new(1.4, 20, 1.4), CFrame.new(-10, 10, 0), wood, Enum.Material.Wood)
	part(Vector3.new(1.4, 20, 1.4), CFrame.new(10, 10, 0), wood, Enum.Material.Wood)
	part(Vector3.new(24, 1.6, 2.4), CFrame.new(0, 20.2, 0), Color3.fromRGB(160, 40, 50), Enum.Material.Wood)
	local board = part(Vector3.new(19, 15, 0.6), CFrame.new(0, 11.5, 0), Color3.fromRGB(30, 26, 46), Enum.Material.SmoothPlastic)
	board.Name = "Board"

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = board
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 90)
	title.Font = Enum.Font.LuckiestGuy
	title.TextScaled = true
	title.Text = "🏆 TOP NINJAS"
	title.TextColor3 = RANK_COLORS[1]
	title.Parent = gui
	rowsFrame = Instance.new("Frame")
	rowsFrame.BackgroundTransparency = 1
	rowsFrame.Size = UDim2.new(1, -40, 1, -110)
	rowsFrame.Position = UDim2.fromOffset(20, 100)
	rowsFrame.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = rowsFrame
	folder.Parent = workspace
end

-- The #1 ninja's avatar as a statue on a gold pedestal beside the board.
local function placeStatue(userId: number)
	if statueOf == userId or userId <= 0 then
		return
	end
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromUserId(userId)
	end)
	if not ok or not model then
		return
	end
	local old = folder:FindFirstChild("TopStatue")
	if old then
		old:Destroy()
	end
	statueOf = userId
	local holder = Instance.new("Model")
	holder.Name = "TopStatue"
	local base = boardFrame * CFrame.new(-14, 0, 0)
	local pedestal = Instance.new("Part")
	pedestal.Size = Vector3.new(6, 2.4, 6)
	pedestal.CFrame = base * CFrame.new(0, 1.2, 0)
	pedestal.Color = Color3.fromRGB(255, 200, 70)
	pedestal.Material = Enum.Material.Foil
	pedestal.Anchored = true
	pedestal.Parent = holder
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	local _, size = model:GetBoundingBox()
	model:PivotTo(base * CFrame.new(0, 2.4 + size.Y / 2, 0))
	model.Name = "#1 " .. nameFor(userId)
	model.Parent = holder
	holder.Parent = folder
end

local function render(entries: { { UserId: number, Value: number } })
	for _, child in ipairs(rowsFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for i, entry in ipairs(entries) do
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 46)
		row.LayoutOrder = i
		row.Parent = rowsFrame
		-- avatar headshot
		local avatar = Instance.new("ImageLabel")
		avatar.Name = "Avatar"
		avatar.BackgroundColor3 = Color3.fromRGB(46, 40, 70)
		avatar.Size = UDim2.fromOffset(44, 44)
		avatar.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", entry.UserId)
		avatar.Parent = row
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = avatar
		local ring = Instance.new("UIStroke")
		ring.Color = RANK_COLORS[i] or Color3.fromRGB(120, 110, 160)
		ring.Thickness = 3
		ring.Parent = avatar
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, -56, 1, 0)
		label.Position = UDim2.fromOffset(56, 0)
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.RichText = true
		label.TextColor3 = RANK_COLORS[i] or Color3.fromRGB(246, 242, 255)
		label.Text = string.format('#%d  %s  <font color="#b2aad2">%s</font>', i, nameFor(entry.UserId), describe(entry.Value))
		label.Parent = row
	end
	if entries[1] then
		task.spawn(placeStatue, entries[1].UserId)
	end
end

local function refresh()
	local entries = {}
	-- push everyone's score, then read the global top
	for _, player in ipairs(Players:GetPlayers()) do
		local data = services.DataService:Get(player)
		if data then
			if store then
				pcall(function()
					(store :: OrderedDataStore):SetAsync(tostring(player.UserId), score(data))
				end)
			end
			table.insert(entries, { UserId = player.UserId, Value = score(data) })
		end
	end
	local global = nil
	if store then
		local ok, pages = pcall(function()
			return (store :: OrderedDataStore):GetSortedAsync(false, SHOWN)
		end)
		if ok and pages then
			global = {}
			for _, item in ipairs(pages:GetCurrentPage()) do
				table.insert(global, { UserId = tonumber(item.key) or 0, Value = item.value })
			end
		end
	end
	if global and #global > 0 then
		entries = global
	else
		table.sort(entries, function(a, b)
			return a.Value > b.Value
		end)
	end
	while #entries > SHOWN do
		table.remove(entries)
	end
	render(entries)
end

function LeaderboardService:Init(registry)
	services = registry
end

function LeaderboardService:Start()
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore("TopNinjas_v1")
	end)
	store = if ok then result else nil
	buildBoard()
	task.spawn(function()
		task.wait(5)
		while true do
			local success, err = pcall(refresh)
			if not success then
				warn("[NinjaSim] leaderboard refresh failed:", err)
			end
			task.wait(REFRESH)
		end
	end)
end

return LeaderboardService
