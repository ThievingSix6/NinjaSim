--[[
	UI toolkit: every screen is built from these helpers so the whole game shares
	one look: candy gradient buttons with diagonal shine stripes and thick ink
	outlines, dark slate windows with a coloured striped header and a big icon
	breaking out of the corner, white rounded text with a dark stroke.

	Icons come from the Blender-rendered atlas (Visuals/IconAtlas) once the asset
	pack is imported; until then Kit.Icon falls back to emoji.
]]

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent.Theme)
local Visuals = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Visuals")
local Assets = require(Visuals:WaitForChild("Assets"))
local atlasModule = Visuals:FindFirstChild("IconAtlas")
local Atlas = if atlasModule then require(atlasModule) :: any else nil

local Kit = {}

Kit.Sound = function(_name: string) end -- set by SoundController

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

function Kit.New(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	if props then
		local parent = props.Parent
		for k, v in pairs(props) do
			if k ~= "Parent" then
				(inst :: any)[k] = v
			end
		end
		if children then
			for _, child in ipairs(children) do
				child.Parent = inst
			end
		end
		if parent then
			inst.Parent = parent
		end
	elseif children then
		for _, child in ipairs(children) do
			child.Parent = inst
		end
	end
	return inst
end
local New = Kit.New

function Kit.Tween(obj: Instance, props: { [string]: any }, time: number?, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local tween = TweenService:Create(obj, TweenInfo.new(time or 0.2, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	tween:Play()
	return tween
end

function Kit.Corner(radius: number?): UICorner
	return New("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Radius) })
end

-- Ink outline around a box.
function Kit.Stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return New("UIStroke", {
		Color = color or Theme.Ink,
		Thickness = thickness or 2.5,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

function Kit.TextStroke(color: Color3?, thickness: number?): UIStroke
	return New("UIStroke", { Color = color or Theme.Ink, Thickness = thickness or 2, LineJoinMode = Enum.LineJoinMode.Round })
end

function Kit.Gradient(top: Color3, bottom: Color3, rotation: number?): UIGradient
	return New("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = rotation or 90 })
end

-- ===== paint: a {top, bottom} gradient on a white background (so colours aren't multiplied) =====
function Kit.PaintColors(paint: any): (Color3, Color3)
	if type(paint) == "string" then
		local pair = Theme.Paint[paint] or Theme.Paint.Dark
		return pair[1], pair[2]
	elseif type(paint) == "table" then
		return paint[1], paint[2]
	end
	local c = paint :: Color3
	return c:Lerp(WHITE, 0.28), c:Lerp(BLACK, 0.14)
end

function Kit.Paint(obj: GuiObject, paint: any)
	local top, bottom = Kit.PaintColors(paint)
	obj.BackgroundColor3 = WHITE
	local grad = obj:FindFirstChild("Paint") :: UIGradient?
	if not grad then
		grad = New("UIGradient", { Name = "Paint", Rotation = 90, Parent = obj })
	end
	(grad :: UIGradient).Color = ColorSequence.new(top, bottom)
end

function Kit.RarityPaint(rarity: string?): string
	return Theme.RarityPaint[rarity or ""] or "Grey"
end

-- Diagonal shine bands like the references' buttons and headers. UIGradient works
-- in the box's own 0-1 space, so the rotation is recomputed from its pixel size to
-- keep the bands at the same steep angle on any shape.
local STRIPES = (function()
	local bands = { { 0.06, 0.2 }, { 0.26, 0.31 }, { 0.6, 0.76 }, { 0.82, 0.86 } }
	local keys = { NumberSequenceKeypoint.new(0, 1) }
	for _, b in ipairs(bands) do
		table.insert(keys, NumberSequenceKeypoint.new(b[1], 1))
		table.insert(keys, NumberSequenceKeypoint.new(b[1] + 0.002, 0))
		table.insert(keys, NumberSequenceKeypoint.new(b[2], 0))
		table.insert(keys, NumberSequenceKeypoint.new(b[2] + 0.002, 1))
	end
	table.insert(keys, NumberSequenceKeypoint.new(1, 1))
	return NumberSequence.new(keys)
end)()

local function stripeRotation(size: Vector2): number
	local w, h = math.max(size.X, 1), math.max(size.Y, 1)
	local theta = math.rad(62)
	return math.deg(math.atan2(math.cos(theta) / w, math.sin(theta) / h))
end

function Kit.Stripes(parent: GuiObject, props: { [string]: any }?): Frame
	local p = props or {}
	local stripes = New("Frame", {
		Name = "Stripes",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = p.Transparency or 0.8,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = p.ZIndex or parent.ZIndex,
		Parent = parent,
	})
	Kit.Corner(p.Radius or Theme.RadiusSmall).Parent = stripes
	local grad = New("UIGradient", { Transparency = STRIPES, Parent = stripes })
	local function fit()
		local size = parent.AbsoluteSize
		if size.X > 0 and size.Y > 0 then
			grad.Rotation = stripeRotation(size)
		end
	end
	grad.Rotation = stripeRotation(p.Size or Vector2.new(160, 48))
	parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	task.defer(fit)
	return stripes
end

function Kit.Padding(all: number, horizontal: number?): UIPadding
	local h = horizontal or all
	return New("UIPadding", {
		PaddingTop = UDim.new(0, all), PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, h), PaddingRight = UDim.new(0, h),
	})
end

function Kit.List(direction: Enum.FillDirection?, padding: number?, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?): UIListLayout
	return New("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 8),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

-- ===== text =====
-- White rounded text with an ink stroke that thickens with size.
function Kit.Label(props: { [string]: any }): TextLabel
	local size = props.TextSize or 18
	local label = New("TextLabel", {
		BackgroundTransparency = 1,
		Font = props.Font or Theme.FontBold,
		Text = props.Text or "",
		TextColor3 = props.Color or Theme.Text,
		TextSize = size,
		TextScaled = props.Scaled or false,
		TextWrapped = props.Wrapped or false,
		TextXAlignment = props.XAlign or Enum.TextXAlignment.Left,
		TextYAlignment = props.YAlign or Enum.TextYAlignment.Center,
		Size = props.Size or UDim2.new(1, 0, 0, 24),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		RichText = props.RichText or false,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Rotation = props.Rotation or 0,
		Name = props.Name or "Label",
		Parent = props.Parent,
	})
	if props.AutoX then
		label.AutomaticSize = Enum.AutomaticSize.X
	end
	if props.Stroke ~= false then
		local thickness = props.StrokeThickness or math.clamp(size / 9, 1.5, 4)
		Kit.TextStroke(props.StrokeColor, thickness).Parent = label
	end
	if props.Scaled and props.MaxTextSize then
		New("UITextSizeConstraint", { MaxTextSize = props.MaxTextSize, Parent = label })
	end
	return label
end

-- ===== icons =====
local EMOJI = {
	Coin = "🪙", Shard = "💎", Shop = "🛒", Areas = "⛩️", Upgrade = "⬆️", Pets = "🐾", Inventory = "🎒",
	Rebirth = "🌀", Trophy = "🏆", Codes = "🎟️", Settings = "⚙️", Gift = "🎁", Egg = "🥚", Katana = "🗡️",
	Clover = "🍀", Heart = "❤️", Star = "⭐", Bolt = "⚡", Lock = "🔒", Check = "✅", Calendar = "📅",
	Oni = "👹", Shuriken = "✴️", Book = "📘", Crown = "👑", Sparkle = "✨", Scroll = "📜", Trash = "🗑️",
	Potion = "🧪", Boot = "👟", Mystery = "❓", Flame = "🔥", Friends = "👥", Clock = "⏰",
}
Kit.IconNames = EMOJI

-- Emoji still used in config files, mapped to the closest atlas icon, so
-- Kit.Icon("📘") draws the 3D book once the atlas is imported.
local ALIASES: { [string]: string } = {
	["💰"] = "Coin", ["⚔️"] = "Katana", ["⚔"] = "Katana", ["💨"] = "Boot", ["🎯"] = "Shuriken", ["⏱️"] = "Clock",
	["🥷"] = "Shuriken", ["🗺️"] = "Areas", ["📦"] = "Inventory", ["🤖"] = "Bolt", ["💠"] = "Shard", ["🔄"] = "Rebirth",
	["⏳"] = "Clock", ["💀"] = "Oni", ["🧰"] = "Inventory", ["🌠"] = "Star", ["💥"] = "Flame", ["🏷️"] = "Scroll", ["🔑"] = "Codes", ["📍"] = "Areas", ["📈"] = "Upgrade", ["🌸"] = "Sparkle", ["🌟"] = "Star", ["🎉"] = "Sparkle", ["🧧"] = "Gift",
}
for name, emoji in pairs(EMOJI) do
	ALIASES[emoji] = name
end
Kit.IconAliases = ALIASES

local function resolve(name: string): string
	return if EMOJI[name] then name else (ALIASES[name] or name)
end

local function atlasRect(name: string): { number }?
	if not Atlas or not Atlas.Icons then
		return nil
	end
	return Atlas.Icons[name]
end

function Kit.HasIcons(): boolean
	return Assets.IconImage() ~= nil and Atlas ~= nil
end

-- An icon by atlas name ("Coin", "Gift", ...) or a raw emoji string. Returns an
-- ImageLabel when the atlas is imported, else an emoji TextLabel.
function Kit.Icon(parent: Instance?, name: string, props: { [string]: any }?): GuiObject
	local p = props or {}
	name = resolve(name)
	local image = Assets.IconImage()
	local rect = atlasRect(name)
	local common = {
		Name = p.Name or "Icon",
		BackgroundTransparency = 1,
		Size = p.Size or UDim2.fromOffset(40, 40),
		Position = p.Position or UDim2.new(),
		AnchorPoint = p.AnchorPoint or Vector2.zero,
		Rotation = p.Rotation or 0,
		ZIndex = p.ZIndex or 1,
		LayoutOrder = p.LayoutOrder or 0,
	}
	local icon
	if image and rect then
		icon = New("ImageLabel", common)
		icon.Image = image
		icon.ImageRectOffset = Vector2.new(rect[1], rect[2])
		icon.ImageRectSize = Vector2.new(rect[3], rect[4])
		icon.ScaleType = Enum.ScaleType.Fit
		if p.Color then
			icon.ImageColor3 = p.Color
		end
		if p.Transparency then
			icon.ImageTransparency = p.Transparency
		end
	else
		icon = New("TextLabel", common)
		icon.Text = if name == "Rays" or name == "Glow" then "" else (EMOJI[name] or name)
		icon.TextScaled = true
		icon.Font = Theme.FontBold
		icon.TextColor3 = WHITE
		if p.Transparency then
			icon.TextTransparency = p.Transparency
		end
	end
	icon:SetAttribute("IconName", name)
	icon.Parent = parent
	return icon
end

-- Swap an icon made by Kit.Icon to another name.
function Kit.SetIcon(icon: GuiObject, name: string)
	name = resolve(name)
	icon:SetAttribute("IconName", name)
	if icon:IsA("ImageLabel") then
		local rect = atlasRect(name)
		if rect then
			icon.ImageRectOffset = Vector2.new(rect[1], rect[2])
			icon.ImageRectSize = Vector2.new(rect[3], rect[4])
		end
	elseif icon:IsA("TextLabel") then
		icon.Text = EMOJI[name] or name
	end
end

-- Light burst behind an item, tinted and optionally spinning. Nil without the atlas.
function Kit.Rays(parent: Instance, props: { [string]: any }?): GuiObject?
	if not Kit.HasIcons() then
		return nil
	end
	local p = props or {}
	local rays = Kit.Icon(parent, "Rays", {
		Name = "Rays", Size = p.Size or UDim2.fromScale(1.1, 1.1), Position = p.Position or UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = p.ZIndex or 1, Color = p.Color, Transparency = p.Transparency or 0.35,
	})
	if p.Spin then
		local conn
		conn = RunService.RenderStepped:Connect(function(dt)
			if not rays.Parent then
				conn:Disconnect()
				return
			end
			rays.Rotation = (rays.Rotation + dt * (p.Spin or 20)) % 360
		end)
	end
	return rays
end

-- Red "!" notification dot for a corner.
function Kit.Badge(parent: Instance, props: { [string]: any }?): Frame
	local p = props or {}
	local badge = New("Frame", {
		Name = p.Name or "Badge", BackgroundColor3 = WHITE, Size = p.Size or UDim2.fromOffset(26, 26),
		Position = p.Position or UDim2.new(1, -14, 0, -10), Visible = p.Visible or false, ZIndex = p.ZIndex or 8, Parent = parent,
	})
	Kit.Paint(badge, "Red")
	Kit.Corner(13).Parent = badge
	Kit.Stroke(Theme.Ink, 2.5).Parent = badge
	Kit.Label({
		Text = p.Text or "!", TextSize = 18, Size = UDim2.fromScale(1, 1), XAlign = Enum.TextXAlignment.Center,
		ZIndex = (p.ZIndex or 8) + 1, StrokeThickness = 2, Parent = badge,
	})
	return badge
end

-- ===== panels =====
-- Panel. props.Paint (name) for bright candy panels, props.Color for a plain tone.
function Kit.Panel(props: { [string]: any }): Frame
	local frame = New("Frame", {
		BackgroundColor3 = props.Color or Theme.Panel,
		BackgroundTransparency = props.Transparency or 0,
		Size = props.Size or UDim2.fromOffset(200, 100),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Name = props.Name or "Panel",
		ClipsDescendants = props.Clip or false,
		Visible = if props.Visible == nil then true else props.Visible,
		Parent = props.Parent,
	})
	Kit.Corner(props.Radius).Parent = frame
	if props.Stroke ~= false then
		Kit.Stroke(props.StrokeColor or Theme.Ink, props.StrokeThickness or 2.5).Parent = frame
	end
	if props.Paint then
		Kit.Paint(frame, props.Paint)
		if props.Stripes ~= false then
			Kit.Stripes(frame, { Radius = props.Radius or Theme.Radius, ZIndex = props.ZIndex, Transparency = props.StripeTransparency })
		end
	elseif props.Gradient ~= false then
		local base = props.Color or Theme.Panel
		Kit.Paint(frame, { base:Lerp(WHITE, 0.05), base:Lerp(BLACK, 0.2) })
	end
	return frame
end

-- Dark inset well that holds lists and grids.
function Kit.Well(props: { [string]: any }): Frame
	props.Color = props.Color or Theme.Well
	props.StrokeThickness = props.StrokeThickness or 2
	props.Radius = props.Radius or 10
	return Kit.Panel(props)
end

-- ===== buttons =====
-- Candy button with hover/press bounce.
-- props: Text, Icon (atlas name or emoji), Color (paint name or Color3), Size, OnClick, TextSize, IconSize
function Kit.Button(props: { [string]: any }): TextButton
	local paint = props.Color or "Green"
	local radius = props.Radius or Theme.RadiusSmall
	local zBase = props.ZIndex or 1
	local button = New("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = WHITE,
		Size = props.Size or UDim2.fromOffset(140, 44),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Text = "",
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = zBase,
		Name = props.Name or "Button",
		Parent = props.Parent,
	})
	Kit.Corner(radius).Parent = button
	Kit.Paint(button, paint)
	local stroke = Kit.Stroke(Theme.Ink, props.StrokeThickness or 3)
	stroke.Parent = button
	local offsetSize = button.Size
	local stripes = Kit.Stripes(button, {
		Radius = radius, ZIndex = zBase, Size = Vector2.new(math.max(offsetSize.X.Offset, 40), math.max(offsetSize.Y.Offset, 30)),
	})
	local scale = New("UIScale", { Parent = button })

	local textSize = props.TextSize or 20
	local text = props.Text or ""
	local label, icon
	if props.Icon and text ~= "" then
		local row = New("Frame", { Name = "Row", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = zBase + 1, Parent = button })
		Kit.List(Enum.FillDirection.Horizontal, props.Gap or 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center).Parent = row
		local iconSize = props.IconSize or math.floor(textSize * 1.6)
		icon = Kit.Icon(row, props.Icon, { Size = UDim2.fromOffset(iconSize, iconSize), ZIndex = zBase + 2, LayoutOrder = 1 })
		label = Kit.Label({
			Text = text, Font = props.Font or Theme.FontBold, TextSize = textSize, XAlign = Enum.TextXAlignment.Center,
			Size = UDim2.new(0, 0, 1, 0), AutoX = true, ZIndex = zBase + 2, LayoutOrder = 2, Name = "Text", Parent = row,
		})
	elseif props.Icon then
		local s = props.IconSize
		icon = Kit.Icon(button, props.Icon, {
			Size = if s then UDim2.fromOffset(s, s) else UDim2.fromScale(0.78, 0.78), Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = zBase + 2,
		})
		label = Kit.Label({ Text = "", TextSize = textSize, Size = UDim2.fromScale(1, 1), ZIndex = zBase + 2, Name = "Text", Parent = button })
	else
		label = Kit.Label({
			Text = text, Font = props.Font or Theme.FontBold, TextSize = textSize, XAlign = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1), ZIndex = zBase + 2, Name = "Text", Parent = button,
		})
		if props.Scaled then
			label.TextScaled = true
			Kit.Padding(6).Parent = label
		end
	end

	local enabled = true
	button.MouseEnter:Connect(function()
		if enabled then
			Kit.Tween(scale, { Scale = 1.06 }, 0.12)
			Kit.Sound("Hover")
		end
	end)
	button.MouseLeave:Connect(function()
		Kit.Tween(scale, { Scale = 1 }, 0.12)
	end)
	button.MouseButton1Down:Connect(function()
		if enabled then
			Kit.Tween(scale, { Scale = 0.92 }, 0.06)
		end
	end)
	button.MouseButton1Up:Connect(function()
		Kit.Tween(scale, { Scale = 1 }, 0.18, Enum.EasingStyle.Back)
	end)
	button.Activated:Connect(function()
		if not enabled then
			Kit.Sound("Error")
			return
		end
		Kit.Sound("Click")
		if props.OnClick then
			props.OnClick()
		end
	end)

	local api = {}
	function api.SetText(t: string)
		label.Text = t
	end
	function api.SetColor(c: any)
		paint = c
		if enabled then
			Kit.Paint(button, c)
		end
	end
	function api.SetIcon(name: string)
		if icon then
			Kit.SetIcon(icon, name)
		end
	end
	function api.SetEnabled(on: boolean)
		enabled = on
		Kit.Paint(button, if on then paint else "Dark")
		stripes.BackgroundTransparency = if on then 0.8 else 0.9
		label.TextTransparency = if on then 0 else 0.25
		label.TextColor3 = if on then Theme.Text else Theme.SubText
	end
	Kit.ButtonApi[button] = api
	return button
end
Kit.ButtonApi = setmetatable({}, { __mode = "k" }) :: { [TextButton]: any }

function Kit.Api(button: TextButton)
	return Kit.ButtonApi[button]
end

-- ===== progress bar =====
-- Returns frame and a setter(ratio, text?). props.Light gives the white HUD track.
function Kit.ProgressBar(props: { [string]: any }): (Frame, (number, string?) -> ())
	local radius = props.Radius or 8
	local back = New("Frame", {
		BackgroundColor3 = WHITE,
		Size = props.Size or UDim2.new(1, 0, 0, 20),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder or 0,
		ClipsDescendants = true,
		ZIndex = props.ZIndex or 1,
		Name = props.Name or "Bar",
		Parent = props.Parent,
	})
	Kit.Paint(back, if props.Light then { Color3.fromRGB(252, 252, 255), Color3.fromRGB(214, 220, 232) } else { Theme.Well, Theme.BodyDark })
	Kit.Corner(radius).Parent = back
	Kit.Stroke(Theme.Ink, props.StrokeThickness or 3).Parent = back
	local fill = New("Frame", {
		BackgroundColor3 = WHITE,
		Size = UDim2.fromScale(0, 1),
		BorderSizePixel = 0,
		ZIndex = back.ZIndex,
		Name = "Fill",
		Parent = back,
	})
	Kit.Corner(radius).Parent = fill
	Kit.Paint(fill, props.Paint or props.Color or "Gold")
	Kit.Stripes(fill, { Radius = radius, ZIndex = back.ZIndex, Transparency = 0.75 })
	local text = Kit.Label({
		Text = "", Font = Theme.FontNumber, TextSize = props.TextSize or 14, XAlign = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1), ZIndex = back.ZIndex + 2, Name = "Text", Parent = back,
	})
	local current = 0
	local function set(ratio: number, label: string?)
		ratio = math.clamp(ratio, 0, 1)
		if ratio < current - 0.001 and props.Instant ~= true then
			-- wrapped (e.g. level up): fill to the end first, then restart
			Kit.Tween(fill, { Size = UDim2.fromScale(1, 1) }, 0.12)
			task.delay(0.13, function()
				fill.Size = UDim2.fromScale(0, 1)
				Kit.Tween(fill, { Size = UDim2.fromScale(ratio, 1) }, 0.25)
			end)
		else
			Kit.Tween(fill, { Size = UDim2.fromScale(ratio, 1) }, if props.Instant then 0 else 0.25)
		end
		current = ratio
		if label then
			text.Text = label
		end
	end
	return back, set
end

-- ===== window =====
-- Dark slate window with a striped colour header, a big icon breaking out of the
-- top-left corner and a red X. Returns window, content frame, close button.
function Kit.Window(props: { [string]: any }): (Frame, Frame, TextButton)
	local accent = props.Accent or "Pink"
	local window = New("Frame", {
		Name = props.Name or "Window",
		BackgroundColor3 = WHITE,
		Size = props.Size or UDim2.fromOffset(760, 480),
		Position = UDim2.fromScale(0.5, 0.52),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		Parent = props.Parent,
	})
	Kit.Corner(16).Parent = window
	Kit.Paint(window, { Theme.Body, Theme.BodyDark })
	Kit.Stroke(Theme.Ink, 4).Parent = window
	New("UIScale", { Name = "OpenScale", Parent = window })

	local header = New("Frame", {
		Name = "Header", BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 0, 62), ZIndex = 2, Parent = window,
	})
	Kit.Corner(16).Parent = header
	Kit.Paint(header, accent)
	local _, bottom = Kit.PaintColors(accent)
	-- square off the header's bottom corners, then an ink rule under it
	New("Frame", {
		Name = "Square", BackgroundColor3 = bottom, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.new(0, 0, 1, -16), ZIndex = 2, Parent = header,
	})
	Kit.Stripes(header, { Radius = 16, ZIndex = 3, Size = Vector2.new(760, 62), Transparency = 0.82 })
	New("Frame", {
		Name = "Rule", BackgroundColor3 = Theme.Ink, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 4),
		Position = UDim2.new(0, 0, 1, 0), ZIndex = 4, Parent = header,
	})
	local hasIcon = props.Icon ~= nil
	if hasIcon then
		Kit.Icon(window, props.Icon, {
			Name = "HeaderIcon", Size = UDim2.fromOffset(86, 86), Position = UDim2.fromOffset(-20, -30), Rotation = -8, ZIndex = 9,
		})
	end
	Kit.Label({
		Name = "Title", Text = props.Title or "", Font = Theme.FontTitle, TextSize = 38,
		Size = UDim2.new(1, -150, 1, -4), Position = UDim2.fromOffset(if hasIcon then 78 else 22, 0),
		ZIndex = 6, StrokeThickness = 3.5, Parent = header,
	})
	local close = Kit.Button({
		Name = "Close", Text = "X", Color = "Red", Size = UDim2.fromOffset(48, 46), TextSize = 30,
		Position = UDim2.new(1, -10, 0.5, -2), AnchorPoint = Vector2.new(1, 0.5), ZIndex = 6, Radius = 10, Parent = header,
	})
	local content = New("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 80),
		Size = UDim2.new(1, -32, 1, -96),
		ZIndex = 2,
		Parent = window,
	})
	return window, content, close
end

-- Horizontal tab strip. Returns frame and select(name) function.
function Kit.Tabs(parent: Instance, tabs: { { Name: string, Icon: string? } }, onSelect: (string) -> (), accent: any?): (Frame, (string) -> ())
	local strip = New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 42),
		Name = "Tabs",
		Parent = parent,
	})
	Kit.List(Enum.FillDirection.Horizontal, 8).Parent = strip
	local buttons = {}
	local function selectTab(name: string)
		for tabName, button in pairs(buttons) do
			local api = Kit.Api(button)
			api.SetColor(if tabName == name then (accent or "Pink") else "Dark")
		end
		onSelect(name)
	end
	for i, tab in ipairs(tabs) do
		local b = Kit.Button({
			Text = tab.Name, Icon = tab.Icon, Color = "Dark", TextSize = 18, IconSize = 28,
			Size = UDim2.fromOffset(math.max(118, #tab.Name * 11 + 64), 40), LayoutOrder = i, Parent = strip,
			OnClick = function()
				selectTab(tab.Name)
			end,
		})
		buttons[tab.Name] = b
	end
	return strip, selectTab
end

-- ViewportFrame showing a model, slowly spinning if spin=true.
function Kit.Viewport(parent: Instance, model: Model, props: { [string]: any }?): ViewportFrame
	props = props or {}
	local vp = New("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Ambient = Color3.fromRGB(210, 210, 220),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-1, -1.2, -0.8),
		ZIndex = props.ZIndex or 2,
		Name = "Viewport",
		Parent = parent,
	})
	local camera = New("Camera", { FieldOfView = 30, Parent = vp })
	vp.CurrentCamera = camera
	local worldModel = New("WorldModel", { Parent = vp })
	local rotation = model:GetAttribute("ViewRotation")
	model:PivotTo(if typeof(rotation) == "CFrame" then rotation else CFrame.new())
	model.Parent = worldModel
	local _, size = model:GetBoundingBox()
	local radius = size.Magnitude / 2
	local distance = radius / math.tan(math.rad(15)) * (props.Zoom or 1.05)
	local angle = props.Angle or math.rad(35)
	local center = model:GetBoundingBox().Position
	local function place(a: number)
		camera.CFrame = CFrame.lookAt(center + Vector3.new(math.sin(a) * distance, radius * 0.35, math.cos(a) * distance), center)
	end
	place(angle)
	if props.Spin then
		local conn
		conn = RunService.RenderStepped:Connect(function()
			if not vp.Parent then
				conn:Disconnect()
				return
			end
			if vp.Visible then
				place(angle + os.clock() * (props.SpinSpeed or 0.8))
			end
		end)
	end
	return vp
end

return Kit
