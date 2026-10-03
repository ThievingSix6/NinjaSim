--[[
	NotificationController: stacked toasts under the XP bar, big centre banners for
	important moments (zone entered, boss spawned in your area, unlocks), callouts (a
	translucent glass card for big personal moments), side notes (a small line of
	text at the right edge that fades away: item drops, yours and other players') and
	chat lines (system messages in the Roblox chat: boss kills, in red).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TextChatService = game:GetService("TextChatService")
local StarterGui = game:GetService("StarterGui")

local Net = require(ReplicatedStorage.Shared.Net)

local NotificationController = {}

local Kit, Theme
local stack: Frame
local sideNotes: Frame
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

-- Translucent callout card (boss kills, hat drops): icon, title and subtitle in
-- Gotham, a thin accent bar on the left, slides down from the top and fades.
local callouts: Frame
function NotificationController:Callout(title: string, subtitle: string?, color: Color3?, icon: string?, duration: number?)
	local accent = color or Theme.Gold
	local iconSpace = if icon then 52 else 0
	local titleWidth = TextService:GetTextSize(title, 26, Theme.FontClean, Vector2.new(900, 40)).X
	local subWidth = if subtitle then TextService:GetTextSize(subtitle, 17, Theme.FontCleanBody, Vector2.new(900, 30)).X else 0
	local width = math.clamp(math.max(titleWidth, subWidth) + 56 + iconSpace, 280, 760)
	local card = Kit.New("Frame", {
		BackgroundColor3 = Color3.fromRGB(14, 16, 26), BackgroundTransparency = 0.42, BorderSizePixel = 0,
		Size = UDim2.fromOffset(width, if subtitle then 74 else 52), Name = "Callout", Parent = callouts,
	})
	card.LayoutOrder = -math.floor(os.clock() * 100)
	Kit.Corner(12).Parent = card
	local edge = Kit.New("UIStroke", { Color = accent, Thickness = 1.5, Transparency = 0.35, Parent = card })
	Kit.New("UIGradient", {
		Color = ColorSequence.new(accent:Lerp(Color3.new(0, 0, 0), 0.55), Color3.fromRGB(14, 16, 26)),
		Transparency = NumberSequence.new(0.1, 0.35), Parent = card,
	})
	local bar = Kit.New("Frame", { BackgroundColor3 = accent, BorderSizePixel = 0, Size = UDim2.new(0, 5, 1, -16), Position = UDim2.fromOffset(9, 8), Parent = card })
	Kit.Corner(3).Parent = bar
	if icon then
		Kit.Icon(card, icon, { Size = UDim2.fromOffset(42, 42), Position = UDim2.new(0, 22, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 2 })
	end
	local function text(t: string, font: Enum.Font, size: number, c: Color3, y: number, h: number)
		local label = Kit.New("TextLabel", {
			BackgroundTransparency = 1, Text = t, Font = font, TextSize = size, TextColor3 = c,
			TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -(28 + iconSpace), 0, h),
			Position = UDim2.fromOffset(24 + iconSpace, y), ZIndex = 2, Parent = card,
		})
		-- a soft dark outline keeps light text readable over bright scenery
		Kit.New("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Transparency = 0.55, Parent = label })
		return label
	end
	text(title, Theme.FontClean, 26, accent:Lerp(Color3.new(1, 1, 1), 0.25), if subtitle then 9 else 11, 30)
	if subtitle then
		text(subtitle, Theme.FontCleanBody, 17, Color3.fromRGB(232, 236, 245), 42, 22)
	end
	local scale = Kit.New("UIScale", { Scale = 0.9, Parent = card })
	Kit.Tween(scale, { Scale = 1 }, 0.25, Enum.EasingStyle.Back)
	task.delay(duration or 3.5, function()
		for _, d in ipairs(card:GetDescendants()) do
			if d:IsA("TextLabel") then
				Kit.Tween(d, { TextTransparency = 1 }, 0.4)
			elseif d:IsA("ImageLabel") then
				Kit.Tween(d, { ImageTransparency = 1 }, 0.4)
			elseif d:IsA("UIStroke") then
				Kit.Tween(d, { Transparency = 1 }, 0.4)
			elseif d:IsA("Frame") then
				Kit.Tween(d, { BackgroundTransparency = 1 }, 0.4)
			end
		end
		Kit.Tween(card, { BackgroundTransparency = 1 }, 0.4)
		Kit.Tween(edge, { Transparency = 1 }, 0.4)
		task.wait(0.45)
		card:Destroy()
	end)
	local cards = {}
	for _, child in ipairs(callouts:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(cards, child)
		end
	end
	if #cards > 3 then
		table.sort(cards, function(a, b)
			return a.LayoutOrder > b.LayoutOrder
		end)
		cards[1]:Destroy()
	end
end

-- A small line of text at the right edge of the screen: slides in, holds a moment,
-- fades away. For item drops (yours and other players').
function NotificationController:Side(text: string, color: Color3?, seconds: number?)
	local label = Kit.New("TextLabel", {
		BackgroundTransparency = 1, Text = text, Font = Theme.FontCleanBody, TextSize = 17,
		TextColor3 = color or Theme.Text, TextXAlignment = Enum.TextXAlignment.Right, TextTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 22), Name = "SideNote", Parent = sideNotes,
	})
	label.LayoutOrder = -math.floor(os.clock() * 100)
	local shadow = Kit.New("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1.2, Transparency = 1, Parent = label })
	local pad = Kit.New("UIPadding", { PaddingRight = UDim.new(0, -30), Parent = label })
	Kit.Tween(label, { TextTransparency = 0 }, 0.25)
	Kit.Tween(shadow, { Transparency = 0.45 }, 0.25)
	Kit.Tween(pad, { PaddingRight = UDim.new(0, 0) }, 0.25)
	task.delay(seconds or 3.5, function()
		Kit.Tween(label, { TextTransparency = 1 }, 0.6)
		Kit.Tween(shadow, { Transparency = 1 }, 0.6)
		task.wait(0.65)
		label:Destroy()
	end)
	-- keep the column short
	local notes = {}
	for _, child in ipairs(sideNotes:GetChildren()) do
		if child:IsA("TextLabel") then
			table.insert(notes, child)
		end
	end
	if #notes > 6 then
		table.sort(notes, function(a, b)
			return a.LayoutOrder > b.LayoutOrder
		end)
		notes[1]:Destroy()
	end
end

local function escapeRich(text: string): string
	return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

-- A system message in the Roblox chat window, in `color` (only this player sees it).
function NotificationController:Chat(text: string, color: Color3?)
	local c = color or Theme.Text
	local ok = pcall(function()
		assert(TextChatService.ChatVersion == Enum.ChatVersion.TextChatService, "legacy chat")
		local channels = TextChatService:FindFirstChild("TextChannels")
		local general = channels and channels:FindFirstChild("RBXGeneral")
		assert(general, "no general channel")
		;(general :: TextChannel):DisplaySystemMessage(string.format('<font color="#%s"><b>%s</b></font>', c:ToHex(), escapeRich(text)))
	end)
	if not ok then
		-- the legacy chat
		pcall(function()
			StarterGui:SetCore("ChatMakeSystemMessage", { Text = text, Color = c, Font = Enum.Font.GothamBold })
		end)
	end
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
	callouts = Kit.New("Frame", {
		BackgroundTransparency = 1, Size = UDim2.fromOffset(760, 260),
		Position = UDim2.new(0.5, 0, 0.16, 0), AnchorPoint = Vector2.new(0.5, 0), Name = "Callouts", Parent = root,
	})
	Kit.List(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center).Parent = callouts
	sideNotes = Kit.New("Frame", {
		BackgroundTransparency = 1, Size = UDim2.fromOffset(520, 200),
		Position = UDim2.new(1, -24, 0.4, 0), AnchorPoint = Vector2.new(1, 0), Name = "SideNotes", Parent = root,
	})
	Kit.List(Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Right).Parent = sideNotes
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
		if info.Side then
			self:Side(info.Text, info.Color)
		elseif info.Big then
			self:Banner(info.Text, nil, info.Color, 2.4)
		else
			self:Toast(info.Text, info.Color, info.Icon)
		end
	end)
end

return NotificationController
