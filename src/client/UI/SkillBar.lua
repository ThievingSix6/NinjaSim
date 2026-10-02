--[[
	SkillBar: the four skill slots on the HUD, bottom centre just above the rank /
	XP panel, plus the Skills menu button. Each slot shows its skill's icon in the
	skill's paint, the key that casts it (1-4, or the gamepad button), and a dark
	cooldown sweep that drains from the top with the seconds left. Tapping a slot
	casts it (touch / mouse); an empty slot opens the Skills menu.
]]

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Skills = require(Shared.Config.Skills)

local SkillBar = {}

local SLOT = 74
local GAP = 10

function SkillBar:Start(c)
	local Kit, Theme = c.Kit, c.Theme
	local root = c.UIController:Root("HUD")
	local SkillController = c.SkillController

	local width = Skills.Slots * SLOT + (Skills.Slots - 1) * GAP + 18 + 66
	local bar = Kit.New("Frame", {
		Name = "SkillBar", BackgroundTransparency = 1, Size = UDim2.fromOffset(width, SLOT),
		Position = UDim2.new(0.5, 0, 1, -132), AnchorPoint = Vector2.new(0.5, 1), Parent = root,
	})
	self.Frame = bar

	local slots = {}
	for i = 1, Skills.Slots do
		local button
		button = Kit.Button({
			Name = "Slot" .. i, Icon = "Shuriken", IconSize = 52, Color = "Dark", Size = UDim2.fromOffset(SLOT, SLOT),
			Position = UDim2.fromOffset((i - 1) * (SLOT + GAP), 0), Radius = 14, StrokeThickness = 3.5, Parent = bar,
			OnClick = function()
				local data = c.DataController:Get()
				local id = data and data.SkillSlots and data.SkillSlots[i]
				if id and id ~= "" then
					SkillController:Cast(i)
				else
					c.MenuManager:Open("Skills", { Slot = i })
				end
			end,
		})
		local icon = button:FindFirstChild("Icon") :: GuiObject
		local plus = button:FindFirstChild("Text") :: TextLabel
		plus.Text = ""
		plus.TextSize = 40
		plus.TextXAlignment = Enum.TextXAlignment.Center
		plus.TextColor3 = Theme.SubText
		-- cooldown sweep: a dark shade anchored to the bottom that shrinks as it recovers
		local shade = Kit.New("Frame", {
			Name = "Cooldown", BackgroundColor3 = Theme.Ink, BackgroundTransparency = 0.3, BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0), ZIndex = 6, Parent = button,
		})
		Kit.Corner(14).Parent = shade
		local seconds = Kit.Label({
			Name = "Seconds", Text = "", Font = Theme.FontNumber, TextSize = 30, XAlign = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1), ZIndex = 7, StrokeThickness = 3, Parent = button,
		})
		-- key chip in the top-left corner
		local chip = Kit.New("Frame", {
			Name = "Key", BackgroundColor3 = Theme.Ink, Size = UDim2.fromOffset(28, 26), Position = UDim2.fromOffset(-8, -8), ZIndex = 8, Parent = button,
		})
		Kit.Corner(8).Parent = chip
		Kit.Stroke(Theme.White, 2).Parent = chip
		local keyText = Kit.Label({ Text = tostring(i), TextSize = 17, XAlign = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 9, StrokeThickness = 1.5, Parent = chip })
		local scale = button:FindFirstChildOfClass("UIScale") :: UIScale
		slots[i] = { Button = button, Icon = icon, Plus = plus, Shade = shade, Seconds = seconds, Chip = chip, KeyText = keyText, Scale = scale, Cooling = false }
	end

	-- the Skills menu button
	local menuButton = Kit.Button({
		Name = "Skills", Icon = "Scroll", IconSize = 50, Color = "Purple", Size = UDim2.fromOffset(66, 66),
		Position = UDim2.new(1, 0, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Radius = 14, StrokeThickness = 3.5, Parent = bar,
		OnClick = function()
			c.MenuManager:Toggle("Skills")
		end,
	})
	local menuIcon = menuButton:FindFirstChild("Icon") :: GuiObject?
	if menuIcon then
		menuIcon.Position = UDim2.new(0.5, 0, 0.42, 0)
	end
	Kit.Label({
		Text = "Skills", TextSize = 17, Size = UDim2.new(1, 10, 0, 20), Position = UDim2.new(0.5, 0, 1, -10),
		AnchorPoint = Vector2.new(0.5, 0.5), XAlign = Enum.TextXAlignment.Center, ZIndex = 5, StrokeThickness = 2.5, Parent = menuButton,
	})
	local badge = Kit.Badge(menuButton, {})
	self.MenuButton = menuButton
	self.Badge = badge

	-- which key labels to show: number keys, gamepad buttons, or none on touch
	local function refreshKeys()
		local last = UserInputService:GetLastInputType()
		local pad = last.Name:sub(1, 7) == "Gamepad"
		local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not pad
		for i, s in ipairs(slots) do
			s.Chip.Visible = not touchOnly
			s.KeyText.Text = if pad then SkillController.PadText[i] else SkillController.KeyText[i]
			s.Chip.Size = UDim2.fromOffset(if pad then 34 else 28, 26)
		end
	end
	refreshKeys()
	UserInputService.LastInputTypeChanged:Connect(refreshKeys)

	local function refresh()
		local data = c.DataController:Get()
		if not data or not data.SkillSlots then
			return
		end
		for i, s in ipairs(slots) do
			local def = Skills.Get(data.SkillSlots[i])
			local api = Kit.Api(s.Button)
			if def and data.Skills[def.Id] then
				api.SetColor(def.Paint)
				api.SetIcon(def.Icon)
				if s.Icon:IsA("ImageLabel") then
					s.Icon.ImageColor3 = def.IconTint or Color3.new(1, 1, 1) -- elemental skills tint their icon
				end
				s.Icon.Visible = true
				s.Plus.Text = ""
			else
				api.SetColor("Slate")
				s.Icon.Visible = false
				s.Plus.Text = "+"
			end
		end
		-- badge: a skill you can learn right now, or an empty slot with a learned skill to fill it
		local show = false
		local learnedSpare = false
		for _, def in ipairs(Skills.List) do
			if data.Skills[def.Id] then
				if not table.find(data.SkillSlots, def.Id) then
					learnedSpare = true
				end
			elseif not Skills.IsFree(def) and Skills.MeetsRequirement(def, data) then
				local currency, price = Skills.Price(def)
				if currency and price and (data[currency] or 0) >= price then
					show = true
				end
			end
		end
		if learnedSpare and table.find(data.SkillSlots, "") then
			show = true
		end
		badge.Visible = show and not c.MenuManager:IsOpen("Skills")
	end
	for _, key in ipairs({ "Skills", "SkillSlots", "Coins", "Shards", "Level", "Rebirths", "BestTier" }) do
		c.DataController:OnChange(key, refresh)
	end
	c.DataController:OnReady(refresh)

	-- cooldown sweeps
	RunService.RenderStepped:Connect(function()
		for i, s in ipairs(slots) do
			local left, total = SkillController:GetCooldown(i)
			if left > 0 and total > 0 then
				s.Shade.Size = UDim2.fromScale(1, math.clamp(left / total, 0, 1))
				s.Seconds.Text = if left >= 1 then tostring(math.ceil(left)) else string.format("%.1f", left)
				s.Cooling = true
			elseif s.Cooling then
				s.Cooling = false
				s.Shade.Size = UDim2.fromScale(1, 0)
				s.Seconds.Text = ""
				-- ready again: a little pop
				s.Scale.Scale = 1.18
				Kit.Tween(s.Scale, { Scale = 1 }, 0.25, Enum.EasingStyle.Back)
			end
		end
	end)

	-- pressing a key pops its slot even before the server answers
	SkillController:OnCast(function(slot)
		local s = slots[slot]
		if s then
			s.Scale.Scale = 0.86
			Kit.Tween(s.Scale, { Scale = 1 }, 0.2, Enum.EasingStyle.Back)
		end
	end)
end

return SkillBar
