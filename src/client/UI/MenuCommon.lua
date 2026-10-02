--[[
	MenuCommon: building blocks shared by the menus, so each menu is just data
	wiring. Item grids in dark wells, bright rarity cards with light rays behind a
	3D preview, a detail side panel, price tags with currency icons, cycling
	buttons and confirm dialogs.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rarity = require(Shared.Config.Rarity)
local Katanas = require(Shared.Config.Katanas)
local Pets = require(Shared.Config.Pets)
local Format = require(Shared.Util.Format)
local KatanaBuilder = require(Shared.Visuals.KatanaBuilder)
local PetBuilder = require(Shared.Visuals.PetBuilder)
local MutationLook = require(Shared.Visuals.MutationLook)

local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local Common = {}

-- ===== model templates (built once, cloned per viewport) =====
local templates: { [string]: Model } = {}

local function stripForViewport(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") or d:IsA("Light") then
			d:Destroy()
		end
	end
end

function Common.KatanaModel(id: string): Model?
	local key = "katana:" .. id
	if not templates[key] then
		local def = Katanas.Get(id)
		if not def then
			return nil
		end
		local model = KatanaBuilder.Build(def, 1)
		stripForViewport(model)
		-- stand the blade upright and tilted for a showcase angle (read by Kit.Viewport)
		model:SetAttribute("ViewRotation", CFrame.Angles(0, 0, math.rad(-35)) * CFrame.Angles(math.rad(90), 0, 0))
		templates[key] = model
	end
	return templates[key]:Clone()
end

-- `mutation` (optional, Config/Mutations) dresses it up; animated looks (Rainbow) animate in the viewport.
function Common.PetModel(id: string, mutation: string?): Model?
	local key = "pet:" .. id .. ":" .. (mutation or "")
	if not templates[key] then
		local def = Pets.ById[id]
		if not def then
			return nil
		end
		local model = PetBuilder.Build(def, 1, mutation)
		stripForViewport(model)
		-- pets face -Z; turn them to face Kit.Viewport's camera (it showed their backs)
		model:SetAttribute("ViewRotation", CFrame.Angles(0, math.pi, 0))
		templates[key] = model
	end
	local clone = templates[key]:Clone()
	if mutation then
		MutationLook.Drive(clone)
	end
	return clone
end

-- Viewport zoom for a pet card: bigger mutations fill more of the frame so they read as big.
function Common.PetZoom(base: number, mutation: string?): number
	local m = Pets.Mutations.Get(mutation)
	return if m and m.Scale > 1 then base / (1 + (m.Scale - 1) * 0.35) else base
end

-- ===== currencies =====
function Common.CurrencyIconName(currency: string): string
	return if currency == "Shards" then "Shard" elseif currency == "Rebirth" then "Rebirth" else "Coin"
end

-- Emoji form, for the few places that can only show text.
function Common.CurrencyIcon(currency: string): string
	return Kit.IconNames[Common.CurrencyIconName(currency)] or ""
end

function Common.CurrencyColor(currency: string): Color3
	return if currency == "Shards" then Theme.Shard elseif currency == "Rebirth" then Theme.Purple else Theme.Gold
end

-- Price as plain text ("1.4K", "Rebirth 3"); pair it with Common.PriceTag's icon.
function Common.Price(currency: string, amount: number): string
	if currency == "Rebirth" then
		return "Rebirth " .. amount
	end
	return Format.Abbrev(amount)
end

function Common.CanAfford(data, currency: string, amount: number): boolean
	if currency == "Rebirth" then
		return data.Rebirths >= amount
	end
	return (data[currency] or 0) >= amount
end

-- [icon] amount, centred in its frame. Returns the frame and a setter(text, color?, currency?).
function Common.PriceTag(parent: Instance, currency: string?, text: string, props: { [string]: any }?)
	local p = props or {}
	local size = p.TextSize or 16
	local frame = Kit.New("Frame", {
		Name = p.Name or "Price", BackgroundTransparency = 1, Size = p.Size or UDim2.new(1, 0, 0, size + 6),
		Position = p.Position or UDim2.new(), AnchorPoint = p.AnchorPoint or Vector2.zero, ZIndex = p.ZIndex or 3,
		LayoutOrder = p.LayoutOrder or 0, Parent = parent,
	})
	Kit.List(Enum.FillDirection.Horizontal, 4, p.Align or Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center).Parent = frame
	local icon
	if currency then
		icon = Kit.Icon(frame, Common.CurrencyIconName(currency), {
			Size = UDim2.fromOffset(size + 6, size + 6), ZIndex = (p.ZIndex or 3) + 1, LayoutOrder = 1,
		})
	end
	local label = Kit.Label({
		Text = text, Font = Theme.FontNumber, TextSize = size, Color = p.Color or Theme.Text, AutoX = true,
		Size = UDim2.new(0, 0, 1, 0), ZIndex = (p.ZIndex or 3) + 1, LayoutOrder = 2, Parent = frame,
	})
	local function set(t: string, color: Color3?, newCurrency: string?)
		label.Text = t
		if color then
			label.TextColor3 = color
		end
		if icon and newCurrency then
			Kit.SetIcon(icon, Common.CurrencyIconName(newCurrency))
		end
	end
	return frame, set
end

-- "1 in 1,000,000" (full) or "1/1M" (compact, for small card pills).
function Common.OddsText(oneIn: number?, compact: boolean?): string
	if not oneIn then
		return ""
	end
	if compact then
		return "1/" .. (if oneIn < 100000 then Format.Commas(oneIn) else Format.Abbrev(oneIn))
	end
	return "1 in " .. Format.Commas(oneIn)
end

local STAT_ICONS = { Damage = "Katana", XP = "Book", Coins = "Coin", Luck = "Clover" }
function Common.BonusLines(bonus: { [string]: number }): { any }
	local lines = {}
	local colors = { Damage = Theme.Red, XP = Theme.XP, Coins = Theme.Gold, Luck = Theme.Green }
	for _, key in ipairs(Pets.StatKeys) do
		if bonus[key] then
			table.insert(lines, { key, "+" .. math.floor(bonus[key] * 100 + 0.5) .. "%", colors[key], STAT_ICONS[key] })
		end
	end
	return lines
end
Common.StatIcons = STAT_ICONS

-- ===== layout =====
-- Scrolling grid (or list) in a dark well that grows with its content.
function Common.Grid(parent: Instance, props: { [string]: any }): ScrollingFrame
	local scroll = Kit.New("ScrollingFrame", {
		Name = props.Name or "Grid",
		BackgroundColor3 = Theme.Well, BackgroundTransparency = 0, BorderSizePixel = 0,
		Size = props.Size or UDim2.fromScale(1, 1), Position = props.Position or UDim2.new(),
		ScrollBarThickness = 8, ScrollBarImageColor3 = Theme.Muted,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = parent,
	})
	Kit.Corner(12).Parent = scroll
	Kit.Stroke(Theme.Ink, 2.5).Parent = scroll
	Kit.New("UIPadding", {
		PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 14), Parent = scroll,
	})
	if props.List then
		Kit.List(Enum.FillDirection.Vertical, props.Gap or 8).Parent = scroll
	else
		Kit.New("UIGridLayout", {
			CellSize = props.CellSize or UDim2.fromOffset(108, 128),
			CellPadding = UDim2.fromOffset(props.Gap or 10, props.Gap or 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = scroll,
		})
	end
	return scroll
end

-- Standard split: grid on the left, detail panel on the right.
function Common.Split(parent: Instance, topOffset: number, detailWidth: number?): (Frame, Frame)
	local w = detailWidth or 270
	local left = Kit.New("Frame", {
		BackgroundTransparency = 1, Size = UDim2.new(1, -(w + 14), 1, -topOffset),
		Position = UDim2.fromOffset(0, topOffset), Name = "Left", Parent = parent,
	})
	local right = Kit.New("Frame", {
		BackgroundTransparency = 1, Size = UDim2.new(0, w, 1, -topOffset),
		Position = UDim2.new(1, -w, 0, topOffset), Name = "Right", Parent = parent,
	})
	return left, right
end

-- ===== item card =====
-- props: Title, Rarity, Paint, Model, Icon, Sub, SubColor, Currency, LayoutOrder, OnClick, Parent
function Common.Card(props: { [string]: any })
	local paint = props.Paint or props.Color or (if props.Rarity then Kit.RarityPaint(props.Rarity) else "Dark")
	local card = Kit.New("TextButton", {
		Name = props.Name or "Card", Text = "", AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = props.LayoutOrder or 0, Parent = props.Parent,
	})
	Kit.Corner(12).Parent = card
	Kit.Paint(card, paint)
	Kit.Stripes(card, { Radius = 12, Size = Vector2.new(108, 128), Transparency = 0.84 })
	local stroke = Kit.Stroke(Theme.Ink, 3)
	stroke.Parent = card
	local scale = Kit.New("UIScale", { Parent = card })

	Kit.Rays(card, { Size = UDim2.new(1.1, 0, 0.85, 0), Position = UDim2.new(0.5, 0, 0.4, 0), ZIndex = 2, Transparency = 0.45 })
	if props.Model then
		Kit.Viewport(card, props.Model, {
			Size = UDim2.new(1, -10, 1, -44), Position = UDim2.fromOffset(5, 5), Zoom = props.Zoom or 0.95, ZIndex = 3,
		})
	elseif props.Icon then
		Kit.Icon(card, props.Icon, {
			Size = UDim2.new(0.62, 0, 0.5, 0), Position = UDim2.new(0.5, 0, 0.4, 0), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 3,
		})
	end
	local title = Kit.Label({
		Text = props.Title or "", TextSize = 15, Scaled = true, MaxTextSize = 15, StrokeThickness = 2,
		XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, -8, 0, 17),
		Position = UDim2.new(0, 4, 1, -44), ZIndex = 5, Parent = card,
	})
	-- bottom pill: price (with currency icon) or a short status
	local pill = Kit.New("Frame", {
		Name = "Pill", BackgroundColor3 = Theme.Ink, BackgroundTransparency = 0.35, Size = UDim2.new(1, -10, 0, 22),
		Position = UDim2.new(0, 5, 1, -26), ZIndex = 4, Parent = card,
	})
	Kit.Corner(7).Parent = pill
	local _, setSub = Common.PriceTag(pill, props.Currency, props.Sub or (props.Rarity or ""), {
		Size = UDim2.fromScale(1, 1), TextSize = 14, Color = props.SubColor or Theme.Text, ZIndex = 5,
	})
	-- corner badges (equipped / favourite / multiplier)
	local badge = Kit.Icon(card, "Check", { Size = UDim2.fromOffset(26, 26), Position = UDim2.fromOffset(-6, -6), ZIndex = 7 })
	badge.Visible = false
	local badge2 = Kit.Label({
		Text = "", TextSize = 14, Size = UDim2.fromOffset(60, 20), Position = UDim2.new(1, -5, 0, 4),
		AnchorPoint = Vector2.new(1, 0), XAlign = Enum.TextXAlignment.Right, ZIndex = 7, StrokeThickness = 2, Parent = card,
	})
	local shade = Kit.New("Frame", {
		BackgroundColor3 = Theme.Ink, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 8, Parent = card,
	})
	Kit.Corner(12).Parent = shade
	local lock = Kit.Icon(shade, "Lock", { Size = UDim2.fromOffset(38, 38), Position = UDim2.new(0.5, 0, 0.36, 0), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 9 })
	lock.Visible = false
	local shadeText = Kit.Label({
		Text = "", TextSize = 14, XAlign = Enum.TextXAlignment.Center, Wrapped = true, StrokeThickness = 2,
		Size = UDim2.new(1, -8, 0, 40), Position = UDim2.new(0, 4, 0.56, 0), ZIndex = 9, Parent = shade,
	})

	card.MouseEnter:Connect(function()
		Kit.Tween(scale, { Scale = 1.05 }, 0.1)
	end)
	card.MouseLeave:Connect(function()
		Kit.Tween(scale, { Scale = 1 }, 0.1)
	end)
	card.Activated:Connect(function()
		Kit.Sound("Click")
		scale.Scale = 0.93
		Kit.Tween(scale, { Scale = 1 }, 0.2, Enum.EasingStyle.Back)
		if props.OnClick then
			props.OnClick()
		end
	end)

	local api = { Frame = card }
	function api.SetSelected(on: boolean)
		stroke.Thickness = if on then 4 else 3
		stroke.Color = if on then Theme.White else Theme.Ink
	end
	-- truthy text shows the check badge (kept for callers that passed an emoji)
	function api.SetBadge(text: string?)
		badge.Visible = text ~= nil and text ~= ""
		if text and (Kit.IconNames[text] or Kit.IconAliases[text]) then
			Kit.SetIcon(badge, text)
		end
	end
	function api.SetBadge2(text: string?)
		badge2.Text = text or ""
	end
	function api.SetSub(text: string, color: Color3?)
		setSub(text, color or props.SubColor or Theme.Text)
	end
	function api.SetTitle(text: string)
		title.Text = text
	end
	function api.SetLocked(text: string?)
		shade.BackgroundTransparency = if text then 0.35 else 1
		shadeText.Text = text or ""
		lock.Visible = text ~= nil and text ~= ""
	end
	return api
end

-- ===== detail panel =====
-- Returns an object with :Show(info) and :Clear().
-- info: Title, Rarity, Paint, Model, Icon, Desc, Tag, Lines {{label, value, color, icon}}, Actions {{Text, Color, OnClick, Enabled, Icon}}
function Common.Detail(parent: Instance)
	local panel = Kit.Panel({ Size = UDim2.fromScale(1, 1), Color = Theme.Panel, Radius = 14, Parent = parent })
	local preview = Kit.New("Frame", {
		Name = "Preview", BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, -20, 0, 132),
		Position = UDim2.fromOffset(10, 10), ZIndex = 2, ClipsDescendants = true, Parent = panel,
	})
	Kit.Corner(12).Parent = preview
	Kit.Stroke(Theme.Ink, 3).Parent = preview
	Kit.Paint(preview, "Dark")
	Kit.Stripes(preview, { Radius = 12, ZIndex = 2, Size = Vector2.new(250, 132), Transparency = 0.84 })
	Kit.Rays(preview, { Size = UDim2.fromScale(1.3, 1.3), ZIndex = 2, Spin = 12, Transparency = 0.4 })
	local title = Kit.Label({
		Text = "", Font = Theme.FontTitle, TextSize = 26, Scaled = true, MaxTextSize = 26,
		XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 146),
		StrokeThickness = 3, Parent = panel,
	})
	local tag = Kit.New("Frame", {
		Name = "Tag", BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromOffset(120, 24),
		Position = UDim2.new(0.5, 0, 0, 178), AnchorPoint = Vector2.new(0.5, 0), Parent = panel,
	})
	Kit.Corner(8).Parent = tag
	Kit.Stroke(Theme.Ink, 2.5).Parent = tag
	Kit.Paint(tag, "Grey")
	local tagText = Kit.Label({ Text = "", TextSize = 15, XAlign = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 2, StrokeThickness = 2, Parent = tag })
	local body = Kit.New("ScrollingFrame", {
		BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, -20, 1, -282),
		Position = UDim2.fromOffset(10, 212), ScrollBarThickness = 4, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = panel,
	})
	Kit.List(Enum.FillDirection.Vertical, 5).Parent = body
	local actions = Kit.New("Frame", {
		BackgroundTransparency = 1, Size = UDim2.new(1, -20, 0, 50), Position = UDim2.new(0, 10, 1, -60), Parent = panel,
	})
	Kit.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center).Parent = actions
	local empty = Kit.Label({
		Text = "Select an item", Color = Theme.Muted, TextSize = 18, XAlign = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1), Parent = panel,
	})

	local detail = {}
	function detail:Clear()
		for _, c in ipairs(preview:GetChildren()) do
			if c:IsA("ViewportFrame") or c.Name == "Icon" then
				c:Destroy()
			end
		end
		for _, c in ipairs(body:GetChildren()) do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		for _, c in ipairs(actions:GetChildren()) do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		title.Text = ""
		tag.Visible = false
		preview.Visible = false
		empty.Visible = true
	end
	function detail:Show(info)
		self:Clear()
		empty.Visible = false
		preview.Visible = true
		local paint = info.Paint or info.Color or (if info.Rarity then Kit.RarityPaint(info.Rarity) else "Dark")
		Kit.Paint(preview, paint)
		if info.Model then
			Kit.Viewport(preview, info.Model, { Spin = true, Zoom = info.Zoom or 0.9, ZIndex = 3 })
		elseif info.Icon then
			Kit.Icon(preview, info.Icon, {
				Size = UDim2.fromOffset(96, 96), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 3,
			})
		end
		title.Text = info.Title or ""
		local tagLabel = if info.Rarity then string.upper(info.Rarity) else info.Tag
		tag.Visible = tagLabel ~= nil
		if tagLabel then
			tagText.Text = tagLabel
			Kit.Paint(tag, paint)
		end
		local order = 0
		if info.Desc then
			order += 1
			Kit.Label({
				Text = info.Desc, Font = Theme.FontBody, TextSize = 14, Color = Theme.SubText, Wrapped = true,
				XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, -6, 0, 0), LayoutOrder = order, Stroke = false, Parent = body,
			}).AutomaticSize = Enum.AutomaticSize.Y
		end
		for _, line in ipairs(info.Lines or {}) do
			order += 1
			local row = Kit.New("Frame", {
				BackgroundColor3 = Theme.Well, Size = UDim2.new(1, -6, 0, 30), LayoutOrder = order, Parent = body,
			})
			Kit.Corner(8).Parent = row
			Kit.Stroke(Theme.Ink, 1.5).Parent = row
			local x = 8
			if line[4] then
				Kit.Icon(row, line[4], { Size = UDim2.fromOffset(24, 24), Position = UDim2.new(0, 5, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 2 })
				x = 34
			end
			Kit.Label({ Text = line[1], TextSize = 15, Color = Theme.SubText, Size = UDim2.new(0.6, -x, 1, 0), Position = UDim2.fromOffset(x, 0), StrokeThickness = 1.5, ZIndex = 2, Parent = row })
			Kit.Label({ Text = line[2], Font = Theme.FontNumber, TextSize = 16, Color = line[3] or Theme.Text, XAlign = Enum.TextXAlignment.Right, Size = UDim2.new(0.4, -8, 1, 0), Position = UDim2.new(0.6, 0, 0, 0), ZIndex = 2, Parent = row })
		end
		local count = #(info.Actions or {})
		for i, action in ipairs(info.Actions or {}) do
			local b = Kit.Button({
				Text = action.Text, Icon = action.Icon, Color = action.Color or "Green", TextSize = if count > 1 then 17 else 22,
				Size = UDim2.new(1 / count, -((count - 1) * 8) / count, 1, 0), LayoutOrder = i, Parent = actions,
				OnClick = action.OnClick,
			})
			if action.Enabled == false then
				Kit.Api(b).SetEnabled(false)
			end
		end
	end
	detail:Clear()
	return detail
end

-- A button that cycles through options, e.g. sort modes. Returns button, getter.
function Common.Cycle(parent: Instance, options: { string }, prefix: string, onChange: (string) -> (), props: { [string]: any }?)
	props = props or {}
	local index = 1
	local button
	button = Kit.Button({
		Text = prefix .. options[1], Color = "Dark", TextSize = 16,
		Size = props.Size or UDim2.fromOffset(150, 38), Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero, LayoutOrder = props.LayoutOrder or 0, Parent = parent,
		OnClick = function()
			index = index % #options + 1
			Kit.Api(button).SetText(prefix .. options[index])
			onChange(options[index])
		end,
	})
	return button, function()
		return options[index]
	end
end

-- Modal confirm dialog over the menus layer. color is a paint name or Color3.
function Common.Confirm(parent: Instance, title: string, text: string, confirmText: string, color: any?, onConfirm: () -> ())
	local paint = color or "Pink"
	local blocker = Kit.New("TextButton", {
		Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.4,
		Size = UDim2.fromScale(1, 1), ZIndex = 50, Parent = parent,
	})
	local box = Kit.New("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromOffset(440, 250), Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 51, Parent = blocker,
	})
	Kit.Corner(16).Parent = box
	Kit.Paint(box, { Theme.Body, Theme.BodyDark })
	Kit.Stroke(Theme.Ink, 4).Parent = box
	local header = Kit.New("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, 0, 0, 56), ZIndex = 52, Parent = box })
	Kit.Corner(16).Parent = header
	Kit.Paint(header, paint)
	local _, bottom = Kit.PaintColors(paint)
	Kit.New("Frame", { BackgroundColor3 = bottom, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 1, -16), ZIndex = 52, Parent = header })
	Kit.Stripes(header, { Radius = 16, ZIndex = 53, Size = Vector2.new(440, 56) })
	Kit.New("Frame", { BackgroundColor3 = Theme.Ink, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 4), Position = UDim2.new(0, 0, 1, 0), ZIndex = 54, Parent = header })
	local scale = Kit.New("UIScale", { Scale = 0.7, Parent = box })
	Kit.Tween(scale, { Scale = 1 }, 0.25, Enum.EasingStyle.Back)
	Kit.Label({ Text = title, Font = Theme.FontTitle, TextSize = 32, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 1, -4), ZIndex = 55, StrokeThickness = 3, Parent = header })
	Kit.Label({ Text = text, TextSize = 18, Color = Theme.SubText, Wrapped = true, XAlign = Enum.TextXAlignment.Center, YAlign = Enum.TextYAlignment.Center, Size = UDim2.new(1, -40, 0, 100), Position = UDim2.fromOffset(20, 66), ZIndex = 52, StrokeThickness = 2, Parent = box })
	local function close()
		blocker:Destroy()
	end
	Kit.Button({ Text = "Cancel", Color = "Dark", Size = UDim2.fromOffset(180, 50), Position = UDim2.new(0.5, -8, 1, -16), AnchorPoint = Vector2.new(1, 1), ZIndex = 52, Parent = box, OnClick = close })
	Kit.Button({
		Text = confirmText, Color = "Green", Size = UDim2.fromOffset(180, 50), Position = UDim2.new(0.5, 8, 1, -16),
		AnchorPoint = Vector2.new(0, 1), ZIndex = 52, Parent = box,
		OnClick = function()
			close()
			onConfirm()
		end,
	})
	blocker.Activated:Connect(close)
	return blocker
end

-- Empty-state label inside a grid.
function Common.EmptyNote(parent: Instance, text: string): TextLabel
	return Kit.Label({
		Text = text, Color = Theme.SubText, TextSize = 18, Wrapped = true, XAlign = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 60), LayoutOrder = 9999, Name = "Empty", Parent = parent,
	})
end

function Common.ClearGrid(grid: Instance)
	for _, c in ipairs(grid:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

Common.RarityColor = Rarity.Color
Common.RarityIndex = Rarity.Index
Common.Colors = { Buy = "Green", Equip = "Blue", Danger = "Red" }

return Common
