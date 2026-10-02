--[[
	UltimateBar: the worn suit's four mastery ultimates (Config/Mastery), to the right
	of the skill bar, with the suit's mastery level and progress above them. Each slot
	shows its element paint and icon, the key (Z X C V or the d-pad), a lock with the
	mastery level it needs, and a cooldown sweep. Tapping a slot casts it; the header
	opens the Suits menu.
]]

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Mastery = require(Shared.Config.Mastery)

local UltimateBar = {}

local SLOT = 58
local GAP = 8

function UltimateBar:Start(c)
	local Kit, Theme = c.Kit, c.Theme
	local root = c.UIController:Root("HUD")
	local UC = c.UltimateController

	local width = 4 * SLOT + 3 * GAP
	local holder = Kit.New("Frame", {
		Name = "UltimateBar", BackgroundTransparency = 1, Size = UDim2.fromOffset(width, SLOT + 34),
		Position = UDim2.new(0.5, 222, 1, -132), AnchorPoint = Vector2.new(0, 1), Parent = root,
	})
	self.Frame = holder

	-- header: "Brown Suit  M 12" and a thin progress bar; opens the Suits menu
	local header = Kit.New("TextButton", {
		Name = "Header", Text = "", BackgroundTransparency = 1, AutoButtonColor = false, Size = UDim2.new(1, 0, 0, 28), Parent = holder,
	})
	header.Activated:Connect(function()
		c.MenuManager:Toggle("Suits")
	end)
	local title = Kit.Label({ Text = "", TextSize = 15, Size = UDim2.new(1, 0, 0, 16), StrokeThickness = 2, Parent = header })
	local _, setProgress = Kit.ProgressBar({
		Size = UDim2.new(1, 0, 0, 9), Position = UDim2.fromOffset(0, 17), Paint = "Gold", TextSize = 1, Radius = 4, StrokeThickness = 2, Instant = true, Parent = header,
	})

	local slots = {}
	for i = 1, 4 do
		local button = Kit.Button({
			Name = "Ult" .. i, Icon = "Star", IconSize = 40, Color = "Dark", Size = UDim2.fromOffset(SLOT, SLOT),
			Position = UDim2.fromOffset((i - 1) * (SLOT + GAP), 34), Radius = 12, StrokeThickness = 3, Parent = holder,
			OnClick = function()
				UC:Cast(i)
			end,
		})
		local icon = button:FindFirstChild("Icon") :: GuiObject
		local shade = Kit.New("Frame", {
			Name = "Cooldown", BackgroundColor3 = Theme.Ink, BackgroundTransparency = 0.3, BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0), ZIndex = 6, Parent = button,
		})
		Kit.Corner(12).Parent = shade
		local seconds = Kit.Label({ Text = "", Font = Theme.FontNumber, TextSize = 24, XAlign = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 7, StrokeThickness = 2.5, Parent = button })
		local lock = Kit.New("Frame", { Name = "Locked", BackgroundColor3 = Theme.Ink, BackgroundTransparency = 0.35, Size = UDim2.fromScale(1, 1), ZIndex = 8, Visible = false, Parent = button })
		Kit.Corner(12).Parent = lock
		Kit.Icon(lock, "Lock", { Size = UDim2.fromOffset(26, 26), Position = UDim2.new(0.5, 0, 0.38, 0), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 9 })
		local need = Kit.Label({ Text = "", TextSize = 13, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 1, -18), ZIndex = 9, StrokeThickness = 2, Parent = lock })
		local chip = Kit.New("Frame", { Name = "Key", BackgroundColor3 = Theme.Ink, Size = UDim2.fromOffset(24, 22), Position = UDim2.fromOffset(-7, -7), ZIndex = 10, Parent = button })
		Kit.Corner(7).Parent = chip
		Kit.Stroke(Theme.Gold, 2).Parent = chip
		local keyText = Kit.Label({ Text = Mastery.Keys[i], TextSize = 14, XAlign = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 11, StrokeThickness = 1.5, Parent = chip })
		local scale = button:FindFirstChildOfClass("UIScale") :: UIScale
		slots[i] = { Button = button, Icon = icon, Shade = shade, Seconds = seconds, Lock = lock, Need = need, Chip = chip, KeyText = keyText, Scale = scale, Cooling = false }
	end

	local function refreshKeys()
		local last = UserInputService:GetLastInputType()
		local pad = last.Name:sub(1, 7) == "Gamepad"
		local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not pad
		for i, s in ipairs(slots) do
			s.Chip.Visible = not touchOnly
			s.KeyText.Text = if pad then Mastery.PadKeys[i] else Mastery.Keys[i]
			s.Chip.Size = UDim2.fromOffset(if pad then 44 else 24, 22)
		end
	end
	refreshKeys()
	UserInputService.LastInputTypeChanged:Connect(refreshKeys)

	local function refresh()
		local data = c.DataController:Get()
		if not data then
			return
		end
		local suit = Mastery.WornTier(data)
		local level, points = Mastery.Of(data, suit.Id)
		title.Text = string.format("%s Suit  -  Mastery %d", string.gsub(suit.Name, " Ninja$", ""), level)
		title.TextColor3 = suit.Color:Lerp(Color3.new(1, 1, 1), 0.35)
		setProgress(if level >= Mastery.Max then 1 else points / Mastery.ToNext(level))
		for i, s in ipairs(slots) do
			local def = Mastery.ForSuit(suit.Id)[i]
			local api = Kit.Api(s.Button)
			if def then
				api.SetColor(def.Paint)
				api.SetIcon(def.Icon)
				if s.Icon:IsA("ImageLabel") then
					s.Icon.ImageColor3 = def.IconTint or Color3.new(1, 1, 1)
				end
				local unlocked = level >= def.Level
				s.Lock.Visible = not unlocked
				s.Need.Text = "M" .. def.Level
			end
		end
	end
	for _, key in ipairs({ "Mastery", "Suit", "Tier", "BestTier" }) do
		c.DataController:OnChange(key, refresh)
	end
	c.DataController:OnReady(refresh)

	RunService.RenderStepped:Connect(function()
		for i, s in ipairs(slots) do
			local left, total = UC:GetCooldown(i)
			if left > 0 and total > 0 then
				s.Shade.Size = UDim2.fromScale(1, math.clamp(left / total, 0, 1))
				s.Seconds.Text = if left >= 1 then tostring(math.ceil(left)) else string.format("%.1f", left)
				s.Cooling = true
			elseif s.Cooling then
				s.Cooling = false
				s.Shade.Size = UDim2.fromScale(1, 0)
				s.Seconds.Text = ""
				s.Scale.Scale = 1.2
				Kit.Tween(s.Scale, { Scale = 1 }, 0.25, Enum.EasingStyle.Back)
			end
		end
	end)

	UC:OnCast(function(slot)
		local s = slots[slot]
		if s then
			s.Scale.Scale = 0.86
			Kit.Tween(s.Scale, { Scale = 1 }, 0.2, Enum.EasingStyle.Back)
		end
	end)
end

return UltimateBar
