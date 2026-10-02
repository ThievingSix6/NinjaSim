--[[
	NotificationController: stacked toasts under the XP bar, plus big centre
	banners for important moments (zone entered, boss spawned, unlocks).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Net = require(ReplicatedStorage.Shared.Net)

local NotificationController = {}

local Kit, Theme
local stack: Frame
local bannerHolder: Frame
local activeBanner: Frame? = nil

-- Leading emoji in older messages ("🏆 Trophy!") become atlas icons.
local EMOJI_ICON: { [string]: string } = {}
local function splitIcon(text: string): (string, string?)
	for emoji, name in pairs(EMOJI_ICON) do
		if string.sub(text, 1, #emoji) == emoji then
			local rest = string.gsub(string.sub(text, #emoji + 1), "^[%s\239\184\143]+", "")
			return rest, name
		end
	end
	return text, nil
end

-- Chunky dark pill with an icon, sliding in under the top buttons.
function NotificationController:Toast(text: string, color: Color3?, icon: string?)
	local accent = color or Theme.Text
	local body, fromEmoji = splitIcon(text)
	local iconName = icon or fromEmoji
	local iconSpace = if iconName then 40 else 0
	local width = TextService:GetTextSize(body, 20, Theme.FontBold, Vector2.new(900, 40)).X + 44 + iconSpace
	local toast = Kit.Panel({
		Size = UDim2.fromOffset(width, 44), Paint = { Theme.Body, Theme.BodyDark }, Stripes = false,
		StrokeThickness = 3, Radius = 22, Parent = stack,
	})
	toast.LayoutOrder = -math.floor(os.clock() * 100)
	if iconName then
		Kit.Icon(toast, iconName, {
			Size = UDim2.fromOffset(40, 40), Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 2,
		})
	end
	Kit.Label({
		Text = body, Color = accent, TextSize = 20, XAlign = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, -iconSpace, 1, 0), Position = UDim2.fromOffset(iconSpace, 0), StrokeThickness = 2.5, ZIndex = 2, Parent = toast,
	})
	local scale = Kit.New("UIScale", { Scale = 0.6, Parent = toast })
	Kit.Tween(scale, { Scale = 1 }, 0.25, Enum.EasingStyle.Back)
	task.delay(2.8, function()
		Kit.Tween(scale, { Scale = 0.85 }, 0.3)
		for _, d in ipairs(toast:GetDescendants()) do
			if d:IsA("TextLabel") then
				Kit.Tween(d, { TextTransparency = 1 }, 0.3)
			elseif d:IsA("ImageLabel") then
				Kit.Tween(d, { ImageTransparency = 1 }, 0.3)
			elseif d:IsA("UIStroke") then
				Kit.Tween(d, { Transparency = 1 }, 0.3)
			end
		end
		Kit.Tween(toast, { BackgroundTransparency = 1 }, 0.3)
		task.wait(0.32)
		toast:Destroy()
	end)
	-- keep the stack short
	local toasts = {}
	for _, c in ipairs(stack:GetChildren()) do
		if c:IsA("Frame") then
			table.insert(toasts, c)
		end
	end
	if #toasts > 5 then
		table.sort(toasts, function(a, b)
			return a.LayoutOrder > b.LayoutOrder
		end)
		toasts[1]:Destroy()
	end
end

-- Big banner: title + subtitle sweeping across the middle of the screen.
function NotificationController:Banner(title: string, subtitle: string?, color: Color3?, duration: number?)
	if activeBanner then
		activeBanner:Destroy()
	end
	local accent = color or Theme.Accent
	local banner = Kit.New("Frame", {
		BackgroundColor3 = Theme.Ink, BackgroundTransparency = 0.35, BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 112), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = bannerHolder,
	})
	Kit.New("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.2),
			NumberSequenceKeypoint.new(0.8, 0.2), NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = banner,
	})
	for _, y in ipairs({ 0, 1 }) do
		local line = Kit.New("Frame", {
			BackgroundColor3 = accent, BorderSizePixel = 0, Size = UDim2.new(0, 0, 0, 4),
			Position = UDim2.new(0.5, 0, y, if y == 0 then 0 else -4), AnchorPoint = Vector2.new(0.5, 0), Parent = banner,
		})
		Kit.Tween(line, { Size = UDim2.new(0.7, 0, 0, 4) }, 0.4)
	end
	local titleLabel = Kit.Label({
		Text = string.upper(title), Font = Theme.FontBig, TextSize = 60, Color = accent, XAlign = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 64), Position = UDim2.fromOffset(0, 8), StrokeThickness = 5, Parent = banner,
	})
	if subtitle then
		Kit.Label({
			Text = subtitle, Font = Theme.FontBold, TextSize = 24, Color = Theme.Text, XAlign = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 74), StrokeThickness = 3, Parent = banner,
		})
	end
	local scale = Kit.New("UIScale", { Scale = 1.4, Parent = titleLabel })
	Kit.Tween(scale, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)
	activeBanner = banner
	task.delay(duration or 2.6, function()
		if banner.Parent then
			for _, d in ipairs(banner:GetDescendants()) do
				if d:IsA("TextLabel") then
					Kit.Tween(d, { TextTransparency = 1 }, 0.4)
				elseif d:IsA("UIStroke") then
					Kit.Tween(d, { Transparency = 1 }, 0.4)
				elseif d:IsA("Frame") then
					Kit.Tween(d, { BackgroundTransparency = 1 }, 0.4)
				end
			end
			Kit.Tween(banner, { BackgroundTransparency = 1 }, 0.4)
			task.wait(0.45)
			banner:Destroy()
			if activeBanner == banner then
				activeBanner = nil
			end
		end
	end)
end

function NotificationController:Start(controllers)
	Kit, Theme = controllers.Kit, controllers.Theme
	for emoji, name in pairs(Kit.IconAliases) do
		EMOJI_ICON[emoji] = name
	end
	local root = controllers.UIController:Root("Toasts")
	stack = Kit.New("Frame", {
		BackgroundTransparency = 1, Size = UDim2.fromOffset(700, 260),
		Position = UDim2.new(0.5, 0, 0, 132), AnchorPoint = Vector2.new(0.5, 0), Name = "Toasts", Parent = root,
	})
	Kit.List(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center).Parent = stack
	bannerHolder = Kit.New("Frame", {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 140),
		Position = UDim2.fromScale(0.5, 0.42), AnchorPoint = Vector2.new(0.5, 0.5), Name = "Banners", Parent = root,
	})

	controllers.DataController:SetFeedback(function(text, color)
		self:Toast(text, color)
	end, function()
		controllers.SoundController:Play("Error")
	end)

	Net.Event("Notify").OnClientEvent:Connect(function(info)
		if info.Big then
			self:Banner(info.Text, nil, info.Color, 2.4)
		else
			self:Toast(info.Text, info.Color, info.Icon)
		end
	end)
end

return NotificationController
