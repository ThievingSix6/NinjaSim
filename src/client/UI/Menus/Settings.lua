--[[
	Settings (saved per player) and lifetime stats.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Util.Format)
local Achievements = require(Shared.Config.Achievements)
local TableUtil = require(Shared.Util.TableUtil)

local Menu = {}

local TOGGLES = {
	{ Key = "Guide", Name = "Goal Guide", Desc = "Glowing trail to your next goal" },
	{ Key = "DamageNumbers", Name = "Damage Numbers", Desc = "Floating numbers when you hit" },
	{ Key = "ScreenShake", Name = "Screen Shake", Desc = "Camera shake on crits and boss attacks" },
	{ Key = "OtherPets", Name = "Show Other Pets", Desc = "Render other players' companions" },
	{ Key = "LowGraphics", Name = "Low Graphics", Desc = "Fewer particles and shadows for weaker devices" },
	{ Key = "AutoSwing", Name = "Auto Swing", Desc = "Swing automatically near enemies (Shop utility)" },
}
local SLIDERS = {
	{ Key = "Music", Name = "Music Volume" },
	{ Key = "SFX", Name = "Sound Effects" },
}

function Menu.Build(ctx)
	local Kit, Theme, Common = ctx.Kit, ctx.Theme, ctx.Common
	local DataController = ctx.Controllers.DataController
	local window, content, close = Kit.Window({
		Name = "Settings", Title = "Settings", Icon = "Settings", Accent = "Grey", Size = UDim2.fromOffset(800, 540), Parent = ctx.Parent,
	})
	local list = Common.Grid(content, { List = true, Gap = 8, Size = UDim2.new(0.6, -6, 1, 0) })
	local statsPanel = Kit.Panel({ Size = UDim2.new(0.4, -6, 1, 0), Position = UDim2.new(0.6, 6, 0, 0), Color = Theme.Panel2, Radius = 14, Parent = content })
	Kit.Label({ Text = "Your Stats", Font = Theme.FontTitle, TextSize = 26, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 8), StrokeThickness = 3, Parent = statsPanel })
	local statsList = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -20, 1, -104), Position = UDim2.fromOffset(10, 46), Name = "Stats", Parent = statsPanel })
	-- codes moved here from the HUD (its tile became Hire)
	Kit.Button({
		Text = "Redeem Codes", Icon = "Codes", Color = "Pink", TextSize = 16, Size = UDim2.new(1, -20, 0, 42), Position = UDim2.new(0, 10, 1, -52), Parent = statsPanel,
		OnClick = function()
			ctx.Controllers.MenuManager:Open("Codes")
		end,
	})
	Kit.List(Enum.FillDirection.Vertical, 4).Parent = statsList
	local STATS = {
		{ "Katana", "Enemies defeated" }, { "Oni", "Bosses defeated" }, { "Egg", "Eggs opened" }, { "Coin", "Coins earned" },
		{ "Star", "Highest level" }, { "Rebirth", "Rebirths" }, { "Clock", "Time played" }, { "Trophy", "Trophies" }, { "Flame", "Daily streak" },
	}
	local statValues = {}
	for i, stat in ipairs(STATS) do
		local row = Kit.Panel({ Size = UDim2.new(1, 0, 0, 36), Color = Theme.Well, StrokeThickness = 2, Radius = 8, LayoutOrder = i, Parent = statsList })
		Kit.Icon(row, stat[1], { Size = UDim2.fromOffset(28, 28), Position = UDim2.new(0, 5, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 2 })
		Kit.Label({ Text = stat[2], TextSize = 15, Color = Theme.SubText, Size = UDim2.new(0.62, -38, 1, 0), Position = UDim2.fromOffset(38, 0), ZIndex = 2, StrokeThickness = 1.5, Parent = row })
		statValues[i] = Kit.Label({ Text = "", TextSize = 17, XAlign = Enum.TextXAlignment.Right, Size = UDim2.new(0.38, -8, 1, 0), Position = UDim2.new(0.62, 0, 0, 0), ZIndex = 2, StrokeThickness = 2, Parent = row })
	end

	local setters = {}
	local function setSetting(key: string, value: any)
		local data = DataController:Get()
		if not data then
			return
		end
		local previous = data.Settings[key]
		data.Settings[key] = value -- optimistic, server echoes the real value back
		if not DataController:Request("SetSetting", key, value) then
			data.Settings[key] = previous
			if setters[key] then
				setters[key](previous)
			end
		end
	end

	local order = 0
	for _, s in ipairs(SLIDERS) do
		order += 1
		local row = Kit.Panel({ Size = UDim2.new(1, -10, 0, 62), Color = Theme.Panel2, StrokeThickness = 3, Radius = 12, LayoutOrder = order, Parent = list })
		Kit.Label({ Text = s.Name, TextSize = 20, Size = UDim2.new(0.4, 0, 1, 0), Position = UDim2.fromOffset(14, 0), StrokeThickness = 2.5, Parent = row })
		local track = Kit.New("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = Theme.Well, Size = UDim2.new(0.44, 0, 0, 16), Position = UDim2.new(0.42, 0, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Parent = row })
		Kit.Corner(8).Parent = track
		Kit.Stroke(Theme.Ink, 2.5).Parent = track
		local fill = Kit.New("Frame", { BackgroundColor3 = Theme.White, BorderSizePixel = 0, Size = UDim2.fromScale(0.5, 1), Parent = track })
		Kit.Corner(8).Parent = fill
		Kit.Paint(fill, "Blue")
		local knob = Kit.New("Frame", { BackgroundColor3 = Theme.White, Size = UDim2.fromOffset(28, 28), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 2, Parent = track })
		Kit.Corner(14).Parent = knob
		Kit.Stroke(Theme.Ink, 3).Parent = knob
		local valueLabel = Kit.Label({ Text = "", TextSize = 17, XAlign = Enum.TextXAlignment.Right, Size = UDim2.fromOffset(50, 62), Position = UDim2.new(1, -60, 0, 0), StrokeThickness = 2, Parent = row })
		local function show(v: number)
			fill.Size = UDim2.fromScale(v, 1)
			knob.Position = UDim2.fromScale(v, 0.5)
			valueLabel.Text = math.floor(v * 100 + 0.5) .. "%"
		end
		setters[s.Key] = show
		local dragging = false
		local function fromInput(x: number): number
			return math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		end
		track.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				show(fromInput(input.Position.X))
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				local v = fromInput(input.Position.X)
				show(v)
				-- live preview of the volume while dragging
				local data = DataController:Get()
				if data then
					local music = if s.Key == "Music" then v else data.Settings.Music
					local sfx = if s.Key == "SFX" then v else data.Settings.SFX
					ctx.Controllers.SoundController:SetVolumes(sfx, music)
				end
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
				dragging = false
				local v = math.floor(fromInput(input.Position.X) * 20 + 0.5) / 20
				show(v)
				setSetting(s.Key, v)
			end
		end)
	end
	for _, t in ipairs(TOGGLES) do
		order += 1
		local row = Kit.Panel({ Size = UDim2.new(1, -10, 0, 62), Color = Theme.Panel2, StrokeThickness = 3, Radius = 12, LayoutOrder = order, Parent = list })
		Kit.Label({ Text = t.Name, TextSize = 20, Size = UDim2.new(1, -120, 0, 26), Position = UDim2.fromOffset(14, 6), StrokeThickness = 2.5, Parent = row })
		Kit.Label({ Text = t.Desc, Font = Theme.FontBody, TextSize = 13, Color = Theme.SubText, Size = UDim2.new(1, -120, 0, 18), Position = UDim2.fromOffset(14, 36), Stroke = false, Parent = row })
		local toggle
		toggle = Kit.Button({
			Text = "", Color = "Green", TextSize = 20, Size = UDim2.fromOffset(92, 42), Position = UDim2.new(1, -12, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Parent = row,
			OnClick = function()
				local data = DataController:Get()
				if data then
					local v = not data.Settings[t.Key]
					setters[t.Key](v)
					setSetting(t.Key, v)
				end
			end,
		})
		setters[t.Key] = function(on: boolean)
			local api = Kit.Api(toggle)
			api.SetText(if on then "ON" else "OFF")
			api.SetColor(if on then "Green" else "Red")
		end
	end
	order += 1
	Kit.Label({ Text = "Controls: Click / F to attack (hold to keep swinging) • G Shop • P Pets • I Inventory • R Rebirth • U Upgrades • M Areas • Esc closes menus", Font = Theme.FontBody, TextSize = 13, Color = Theme.SubText, Wrapped = true, Stroke = false, Size = UDim2.new(1, -10, 0, 48), LayoutOrder = order, Parent = list })

	local function refresh()
		local data = DataController:Get()
		if not data then
			return
		end
		for key, set in pairs(setters) do
			if data.Settings[key] ~= nil then
				set(data.Settings[key])
			end
		end
		local l = data.Lifetime
		local values = {
			Format.Commas(l.Kills), Format.Commas(l.BossKills), Format.Commas(l.EggsOpened), Format.Abbrev(l.CoinsEarned),
			Format.Commas(l.HighestLevel), Format.Commas(data.Rebirths), Format.Time(l.PlayTime),
			TableUtil.Count(data.Achievements or {}) .. " / " .. #Achievements.List, "Day " .. (if data.Daily then data.Daily.Streak else 0),
		}
		for i, v in ipairs(values) do
			statValues[i].Text = v
		end
	end
	DataController:OnChange("Settings", function()
		if window.Visible then
			refresh()
		end
	end)

	return { Window = window, Close = close, OnOpen = refresh }
end

return Menu
