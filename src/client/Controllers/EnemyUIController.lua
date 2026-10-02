--[[
	EnemyUIController: overhead name / level / health bars for enemies.
	Colour tells you how dangerous they are compared to your level, the bar
	has a trailing "damage chunk", and bars only show within range.
	Bosses get their name here; their big health bar lives in BossController.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local EnemyUIController = {}

local controllers, Kit, Theme
local holder: Folder
local bars: { [Model]: any } = {}

local rgb = Color3.fromRGB

local function difficultyColor(enemyLevel: number): Color3
	local data = controllers.DataController:Get()
	local myLevel = if data then data.Level else 1
	local diff = enemyLevel - myLevel
	if diff >= 8 then
		return rgb(255, 70, 70)
	elseif diff >= 3 then
		return rgb(255, 170, 60)
	elseif diff >= -5 then
		return rgb(255, 255, 255)
	end
	return rgb(140, 220, 140)
end

local function register(model: Instance)
	if not model:IsA("Model") or bars[model] then
		return
	end
	local adornee = model.PrimaryPart or model:WaitForChild("HumanoidRootPart", 5)
	if not adornee or not model.Parent then
		return
	end
	local isBoss = model:GetAttribute("IsBoss") == true
	local height = model:GetAttribute("Height") or 5
	local gui = Kit.New("BillboardGui", {
		Name = "EnemyBar", Adornee = adornee, AlwaysOnTop = false, LightInfluence = 0,
		Size = if isBoss then UDim2.fromOffset(230, 38) else UDim2.fromOffset(128, 32),
		StudsOffsetWorldSpace = Vector3.new(0, height * 0.55 + 1.8, 0),
		MaxDistance = if isBoss then 220 else 85, ResetOnSpawn = false, Parent = holder,
	})
	local level = model:GetAttribute("Level") or 1
	local name = model:GetAttribute("DisplayName") or model.Name
	local label = Kit.Label({
		Text = (if isBoss then "👹 " else "") .. name .. "  Lv " .. level, Font = Theme.FontHeavy, TextSize = if isBoss then 15 else 11, -- small, so crowds stay readable (2026-10-02)
		Color = if isBoss then rgb(255, 90, 90) else difficultyColor(level), XAlign = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 16), StrokeThickness = 1.5, Parent = gui,
	})
	local back, fill, chunk
	if not isBoss then
		back = Kit.New("Frame", { BackgroundColor3 = rgb(20, 16, 28), BorderSizePixel = 0, Size = UDim2.new(1, -20, 0, 7), Position = UDim2.fromOffset(10, 19), Parent = gui })
		Kit.Corner(4).Parent = back
		Kit.Stroke(rgb(0, 0, 0), 1.5).Parent = back
		chunk = Kit.New("Frame", { BackgroundColor3 = rgb(255, 240, 200), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = back })
		Kit.Corner(4).Parent = chunk
		fill = Kit.New("Frame", { BackgroundColor3 = rgb(90, 220, 90), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = back })
		Kit.Corner(4).Parent = fill
		back.Visible = false -- the bar appears once damaged; name + level always show
	end
	local entry = { Gui = gui, Back = back, Label = label, Fill = fill, Chunk = chunk, IsBoss = isBoss, Level = level, LastHit = 0 }
	bars[model] = entry

	local function update()
		if isBoss then
			return
		end
		local hp = model:GetAttribute("Health") or 0
		local max = model:GetAttribute("MaxHealth") or 1
		local ratio = math.clamp(hp / max, 0, 1)
		if ratio < 1 then
			back.Visible = true
			entry.LastHit = os.clock()
		end
		fill.Size = UDim2.fromScale(ratio, 1)
		fill.BackgroundColor3 = if ratio > 0.5 then rgb(90, 220, 90) elseif ratio > 0.25 then rgb(255, 200, 60) else rgb(255, 80, 60)
		task.delay(0.25, function()
			if chunk.Parent then
				Kit.Tween(chunk, { Size = UDim2.fromScale(ratio, 1) }, 0.35)
			end
		end)
		if ratio >= 1 then
			chunk.Size = UDim2.fromScale(1, 1)
		end
	end
	model:GetAttributeChangedSignal("Health"):Connect(update)
	model:GetAttributeChangedSignal("Dead"):Connect(function()
		if model:GetAttribute("Dead") then
			gui.Enabled = false
		else
			gui.Enabled = true
			update()
		end
	end)
	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			gui:Destroy()
			bars[model] = nil
		end
	end)
	update()
end

local function unregister(model: Instance)
	local entry = bars[model :: Model]
	if entry then
		entry.Gui:Destroy()
		bars[model :: Model] = nil
	end
end

function EnemyUIController:Start(c)
	controllers = c
	Kit, Theme = c.Kit, c.Theme
	holder = Instance.new("Folder")
	holder.Name = "EnemyBars"
	holder.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	CollectionService:GetInstanceAddedSignal("Enemy"):Connect(function(m)
		task.spawn(register, m)
	end)
	CollectionService:GetInstanceRemovedSignal("Enemy"):Connect(unregister)
	for _, m in ipairs(CollectionService:GetTagged("Enemy")) do
		task.spawn(register, m)
	end

	-- recolour names when the player levels; hide bars of healed enemies after a while
	c.DataController:OnChange("Level", function()
		for _, entry in pairs(bars) do
			if not entry.IsBoss then
				entry.Label.TextColor3 = difficultyColor(entry.Level)
			end
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 1 then
			return
		end
		acc = 0
		local now = os.clock()
		for model, entry in pairs(bars) do
			if not entry.IsBoss and entry.Back.Visible and now - entry.LastHit > 8 then
				local hp = model:GetAttribute("Health") or 0
				local max = model:GetAttribute("MaxHealth") or 1
				if hp >= max then
					entry.Back.Visible = false
				end
			end
		end
	end)
end

return EnemyUIController
