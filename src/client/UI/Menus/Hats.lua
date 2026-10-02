--[[
	Hats: the loot hats you've found (Config/Hats, LootService). A grid of hats in
	their rarity colours and a Diablo-style tooltip card: name, rarity, item level,
	base stats, affixes (blue / yellow / orange / pink by rarity), the on-hit proc,
	and a comparison against the equipped hat (green / red deltas, plus the real
	damage, HP and regen numbers before and after). Equip / Unequip, Lock, Salvage,
	and bulk salvage of unlocked hats up to a rarity. Opens with H or the HUD button.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Hats = require(Shared.Config.Hats)
local Balance = require(Shared.Config.Balance)
local Stats = require(Shared.Stats)
local Format = require(Shared.Util.Format)
local HatBuilder = require(Shared.Visuals.HatBuilder)

local Menu = {}

local GREEN = Color3.fromRGB(120, 240, 110)
local RED = Color3.fromRGB(255, 96, 96)
local PROC = Color3.fromRGB(255, 150, 40)
local TOOLTIP_BG = Color3.fromRGB(22, 20, 32)
local BULK = { "Common", "Magic", "Rare" }

local function statKeys(a, b): { string }
	local keys = {}
	for _, def in ipairs(Hats.Affixes) do
		if (a[def.Id] or 0) ~= 0 or (b[def.Id] or 0) ~= 0 then
			table.insert(keys, def.Id)
		end
	end
	return keys
end

-- Stat lines a hat gives: base first (white), then affixes in the rarity colour.
local function sortedStats(stats: { [string]: number }): { string }
	local keys = {}
	for key in pairs(stats) do
		if Hats.AffixById[key] then
			table.insert(keys, key)
		end
	end
	table.sort(keys, function(x, y)
		return Hats.AffixById[x].Order < Hats.AffixById[y].Order
	end)
	return keys
end

function Menu.Build(ctx)
	local Kit, Theme, Common = ctx.Kit, ctx.Theme, ctx.Common
	local DataController = ctx.Controllers.DataController
	local Sound = ctx.Controllers.SoundController

	local window, content, close = Kit.Window({
		Name = "Hats", Title = "Hats", Icon = "Crown", Accent = "Orange", Size = UDim2.fromOffset(940, 580), Parent = ctx.Parent,
	})
	local left, right = Common.Split(content, 50, 340)
	local grid = Common.Grid(left, { CellSize = UDim2.fromOffset(96, 112) })

	-- ===== top bar =====
	local countRow = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(230, 40), Parent = content })
	Kit.List(Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center).Parent = countRow
	Kit.Icon(countRow, "Crown", { Size = UDim2.fromOffset(32, 32), LayoutOrder = 1 })
	local countLabel = Kit.Label({ Text = "", TextSize = 19, AutoX = true, Size = UDim2.new(0, 0, 1, 0), LayoutOrder = 2, StrokeThickness = 2, Parent = countRow })

	local sortMode = "Rarity"
	local bulkIndex = 1
	local selectedUid: string? = nil
	local cards: { [string]: any } = {}
	local locks: { [string]: GuiObject } = {}
	local refresh, showTooltip

	local toolbar = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -240, 0, 40), Position = UDim2.fromOffset(240, 0), Parent = content })
	Kit.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right).Parent = toolbar
	Common.Cycle(toolbar, { "Rarity", "Newest", "Level" }, "Sort: ", function(mode)
		sortMode = mode
		refresh()
	end, { Size = UDim2.fromOffset(140, 38), LayoutOrder = 1 })
	Common.Cycle(toolbar, { "up to Common", "up to Magic", "up to Rare" }, "Bulk: ", function(mode)
		for i, name in ipairs(BULK) do
			if string.find(mode, name, 1, true) then
				bulkIndex = i
			end
		end
	end, { Size = UDim2.fromOffset(196, 38), LayoutOrder = 2 })
	Kit.Button({
		Text = "Salvage All", Icon = "Trash", IconSize = 26, Color = "Red", TextSize = 17, Size = UDim2.fromOffset(170, 40), LayoutOrder = 3, Parent = toolbar,
		OnClick = function()
			local data = DataController:Get()
			if not data then
				return
			end
			local rarity = BULK[bulkIndex]
			local n, coins, shards = 0, 0, 0
			for uid, hat in pairs(data.Hats) do
				if Hats.Valid(hat) and not hat.Lock and uid ~= data.EquippedHat and Hats.Rarity(hat.R).Index <= bulkIndex then
					n += 1
					local c, s = Hats.SalvageValue(hat, Balance)
					coins += c
					shards += s
				end
			end
			if n == 0 then
				ctx.Controllers.NotificationController:Toast("No unlocked " .. rarity .. (if bulkIndex > 1 then " or lower" else "") .. " hats to salvage", Theme.SubText, "Trash")
				return
			end
			Common.Confirm(ctx.Parent, "Salvage " .. n .. " hats?", string.format("Every unlocked, unequipped %s%s hat, for %s Coins%s. Locked hats are kept.",
				rarity, if bulkIndex > 1 then " or lower" else "", Format.Abbrev(coins), if shards > 0 then " and " .. shards .. " Shards" else ""),
				"Salvage", Common.Colors.Danger, function()
					local ok, message = DataController:Request("SalvageHatsUpTo", rarity)
					if ok then
						Sound:Play("Purchase")
						ctx.Controllers.NotificationController:Toast(tostring(message or "Salvaged"), Theme.Gold, "Coin")
					end
				end)
		end,
	})

	-- ===== tooltip card =====
	local card = Kit.Panel({ Size = UDim2.fromScale(1, 1), Color = TOOLTIP_BG, Radius = 14, StrokeThickness = 3, Parent = right })
	local cardStroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke
	local preview = Kit.New("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromOffset(88, 88), Position = UDim2.fromOffset(10, 10), ZIndex = 2, ClipsDescendants = true, Parent = card,
	})
	Kit.Corner(10).Parent = preview
	Kit.Stroke(Theme.Ink, 2.5).Parent = preview
	local nameLabel = Kit.Label({
		Text = "", Font = Theme.FontTitle, TextSize = 22, Scaled = true, MaxTextSize = 22, Wrapped = true, YAlign = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -118, 0, 50), Position = UDim2.fromOffset(108, 8), StrokeThickness = 2.5, ZIndex = 2, Parent = card,
	})
	local rarityLabel = Kit.Label({ Text = "", TextSize = 16, Size = UDim2.new(1, -118, 0, 20), Position = UDim2.fromOffset(108, 60), StrokeThickness = 2, ZIndex = 2, Parent = card })
	local levelLabel = Kit.Label({ Text = "", TextSize = 15, Color = Theme.Muted, Size = UDim2.new(1, -118, 0, 18), Position = UDim2.fromOffset(108, 80), StrokeThickness = 1.5, ZIndex = 2, Parent = card })
	Kit.New("Frame", { BackgroundColor3 = Theme.Muted, BackgroundTransparency = 0.6, BorderSizePixel = 0, Size = UDim2.new(1, -20, 0, 2), Position = UDim2.fromOffset(10, 106), ZIndex = 2, Parent = card })
	local body = Kit.New("ScrollingFrame", {
		BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, -16, 1, -200), Position = UDim2.fromOffset(10, 114),
		ScrollBarThickness = 4, ScrollBarImageColor3 = Theme.Muted, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 2, Parent = card,
	})
	Kit.List(Enum.FillDirection.Vertical, 3).Parent = body
	local salvageRow = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -20, 0, 24), Position = UDim2.new(0, 10, 1, -84), ZIndex = 2, Parent = card })
	local _, setSalvage = Common.PriceTag(salvageRow, "Coins", "", { Size = UDim2.fromScale(1, 1), TextSize = 15, Color = Theme.Gold, ZIndex = 2 })
	local actions = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -20, 0, 48), Position = UDim2.new(0, 10, 1, -58), ZIndex = 2, Parent = card })
	Kit.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center).Parent = actions
	local empty = Kit.Label({
		Text = "Hats you find show up here.\n\nEvery enemy has a 1% chance to drop one (bosses 25%). Look for the pillar of light!",
		TextSize = 17, Color = Theme.SubText, Wrapped = true, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, -30, 1, -30), Position = UDim2.fromOffset(15, 15), ZIndex = 3, Parent = card,
	})

	local order = 0
	local function line(text: string, color: Color3?, size: number?, font: Enum.Font?)
		order += 1
		local label = Kit.Label({
			Text = text, TextSize = size or 16, Color = color or Theme.Text, Font = font or Theme.FontBold, Wrapped = true,
			Size = UDim2.new(1, -6, 0, 0), LayoutOrder = order, StrokeThickness = 1.5, ZIndex = 3, Parent = body,
		})
		label.AutomaticSize = Enum.AutomaticSize.Y
		return label
	end
	local function heading(text: string)
		order += 1
		Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 4), LayoutOrder = order, Parent = body })
		line(string.upper(text), Theme.Muted, 13)
	end

	local function clearTooltip()
		for _, c in ipairs(preview:GetChildren()) do
			if c:IsA("ViewportFrame") then
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
		order = 0
	end

	local function setVisible(on: boolean)
		for _, c in ipairs(card:GetChildren()) do
			if c:IsA("GuiObject") then
				c.Visible = if c == empty then not on else on
			end
		end
	end

	-- Stats with this hat on instead (same shared formula as the server).
	local function statsWith(data, uid: string)
		local copy = table.clone(data)
		copy.EquippedHat = uid
		return Stats.Compute(copy)
	end

	function showTooltip(uid: string?)
		local data = DataController:Get()
		local hat = data and uid and data.Hats[uid]
		clearTooltip()
		if not hat or not Hats.Valid(hat) then
			setVisible(false)
			cardStroke.Color = Theme.Ink
			return
		end
		setVisible(true)
		local def = Hats.Get(hat.Id)
		local rarity = Hats.Rarity(hat.R)
		local equipped = data.EquippedHat == uid
		cardStroke.Color = rarity.Color
		Kit.Paint(preview, rarity.Paint)
		local model = HatBuilder.Build(hat)
		if model then
			Kit.Viewport(preview, model, { Spin = true, Zoom = 0.95, ZIndex = 3 })
		end
		nameLabel.Text = Hats.Name(hat)
		nameLabel.TextColor3 = rarity.Color
		rarityLabel.Text = rarity.Name .. " Hat" .. (if equipped then "  ·  Equipped" else "") .. (if hat.Lock then "  ·  Locked" else "")
		rarityLabel.TextColor3 = rarity.Color
		levelLabel.Text = "Item Level " .. hat.L .. "  ·  " .. def.Name

		-- base stats (white), affixes (rarity colour), proc (orange)
		heading("Base")
		for _, key in ipairs(sortedStats(def.Stats)) do
			line(Hats.StatText(key, def.Stats[key]), Theme.Text)
		end
		if #hat.A > 0 or hat.P then
			heading("Affixes")
			for _, a in ipairs(hat.A) do
				line(Hats.StatText(a.K, a.V), rarity.Color)
			end
			if hat.P then
				line(Hats.ProcText(hat.P), PROC)
			end
		end
		line(def.Desc, Theme.Muted, 14, Theme.FontBody)

		-- comparison against what's worn now
		local current = Hats.Equipped(data)
		if not equipped then
			heading(if current then "Compared to " .. Hats.Name(current) else "Compared to no hat")
			local mine, worn = Hats.Bonus(hat), Hats.Bonus(current)
			local any = false
			for _, key in ipairs(statKeys(mine, worn)) do
				local delta = (mine[key] or 0) - (worn[key] or 0)
				if math.abs(delta) > 1e-6 then
					any = true
					line(Hats.StatText(key, delta), if delta > 0 then GREEN else RED)
				end
			end
			local mineProc = hat.P and hat.P.S
			local wornProc = current and current.P and current.P.S
			if hat.P and (mineProc ~= wornProc or (current and current.P and current.P.C ~= hat.P.C)) then
				any = true
				line("+ " .. Hats.ProcText(hat.P), GREEN)
			end
			if current and current.P and wornProc ~= mineProc then
				any = true
				line("- " .. Hats.ProcText(current.P), RED)
			end
			if not any then
				line("Same stats", Theme.Muted)
			end
		end
		-- real numbers (the HUD damage readout uses the same formula)
		heading(if equipped then "Your stats" else "Your stats if equipped")
		local now = Stats.Compute(data)
		local after = if equipped then now else statsWith(data, uid)
		local function pair(label: string, a: number, b: number, fmt: (number) -> string, lowerIsBetter: boolean?)
			if equipped or math.abs(a - b) < 1e-6 then
				line(label .. ": " .. fmt(b), Theme.SubText)
			else
				local better = if lowerIsBetter then b < a else b > a
				line(label .. ": " .. fmt(a) .. "  >  " .. fmt(b), if better then GREEN else RED)
			end
		end
		pair("Hit Damage", now.Damage, after.Damage, Format.Abbrev)
		pair("Max HP", now.MaxHealth, after.MaxHealth, Format.Abbrev)
		pair("HP Regen", now.HealthRegen or 0, after.HealthRegen or 0, function(v)
			return Hats.Pct(v) .. "/s"
		end)
		pair("Regen starts after", now.RegenDelay or 0, after.RegenDelay or 0, function(v)
			return string.format("%.1fs", v)
		end, true)

		local coins, shards = Hats.SalvageValue(hat, Balance)
		setSalvage("Salvage for " .. Format.Abbrev(coins) .. (if shards > 0 then " + " .. shards .. " Shards" else ""), Theme.Gold)

		Kit.Button({
			Text = if equipped then "Unequip" else "Equip", Color = if equipped then "Grey" else Common.Colors.Equip, TextSize = 20,
			Size = UDim2.new(1, -124, 1, 0), LayoutOrder = 1, Parent = actions,
			OnClick = function()
				if DataController:Request(if equipped then "UnequipHat" else "EquipHat", uid) then
					Sound:Play("Equip")
				end
			end,
		})
		Kit.Button({
			Text = "", Icon = "Lock", IconSize = 32, Color = if hat.Lock then "Gold" else "Grey", Size = UDim2.fromOffset(54, 48), LayoutOrder = 2, Parent = actions,
			OnClick = function()
				DataController:Request("LockHat", uid)
			end,
		})
		local trash = Kit.Button({
			Text = "", Icon = "Trash", IconSize = 32, Color = Common.Colors.Danger, Size = UDim2.fromOffset(54, 48), LayoutOrder = 3, Parent = actions,
			OnClick = function()
				local function salvage()
					local ok, message = DataController:Request("SalvageHats", { uid })
					if ok then
						Sound:Play("Purchase")
						ctx.Controllers.NotificationController:Toast(tostring(message or "Salvaged"), Theme.Gold, "Coin")
					end
				end
				if rarity.Index >= 3 then
					Common.Confirm(ctx.Parent, "Salvage hat?", "Salvage " .. Hats.Name(hat) .. " for " .. Format.Abbrev(coins) .. " Coins" .. (if shards > 0 then " and " .. shards .. " Shards" else "") .. "? It's gone for good.", "Salvage", Common.Colors.Danger, salvage)
				else
					salvage()
				end
			end,
		})
		if hat.Lock or equipped then
			Kit.Api(trash).SetEnabled(false)
		end
	end

	local function sortKey(data, uid: string): number
		local hat = data.Hats[uid]
		local primary
		if sortMode == "Newest" then
			primary = tonumber(uid) or 0
		elseif sortMode == "Level" then
			primary = hat.L * 10 + Hats.Rarity(hat.R).Index
		else
			primary = Hats.Rarity(hat.R).Index * 1e4 + hat.L
		end
		return (if data.EquippedHat == uid then 1e12 else 0) + primary
	end

	local function selectHat(uid: string)
		selectedUid = uid
		for id, c in pairs(cards) do
			c.SetSelected(id == uid)
		end
		showTooltip(uid)
	end

	function refresh()
		local data = DataController:Get()
		if not data then
			return
		end
		local hats = data.Hats or {}
		for uid, c in pairs(cards) do
			if not Hats.Valid(hats[uid]) then
				c.Frame:Destroy()
				cards[uid] = nil
				locks[uid] = nil
			end
		end
		for uid, hat in pairs(hats) do
			if not cards[uid] and Hats.Valid(hat) then
				local def = Hats.Get(hat.Id)
				local rarity = Hats.Rarity(hat.R)
				local c = Common.Card({
					Title = def.Name, Paint = rarity.Paint, Model = HatBuilder.Build(hat), Zoom = 1.05, Parent = grid,
					Sub = "iLvl " .. hat.L, SubColor = rarity.Color,
					OnClick = function()
						selectHat(uid)
					end,
				})
				cards[uid] = c
				locks[uid] = Kit.Icon(c.Frame, "Lock", { Size = UDim2.fromOffset(24, 24), Position = UDim2.new(1, -4, 0, 4), AnchorPoint = Vector2.new(1, 0), ZIndex = 7 })
			end
		end
		local uids = {}
		for uid in pairs(cards) do
			table.insert(uids, uid)
		end
		table.sort(uids, function(a, b)
			return sortKey(data, a) > sortKey(data, b)
		end)
		for i, uid in ipairs(uids) do
			local c = cards[uid]
			c.Frame.LayoutOrder = i
			c.SetBadge(if data.EquippedHat == uid then "Check" else nil)
			locks[uid].Visible = hats[uid].Lock == true
			c.SetSelected(uid == selectedUid)
		end
		local note = grid:FindFirstChild("Empty")
		if #uids == 0 and not note then
			Common.EmptyNote(grid, "No hats yet! Defeat enemies to find them.")
		elseif #uids > 0 and note then
			note:Destroy()
		end
		countLabel.Text = string.format("%d/%d hats", #uids, Hats.Storage)
		countLabel.TextColor3 = if #uids >= Hats.Storage then Theme.Red else Theme.Text
		if selectedUid and not cards[selectedUid] then
			selectedUid = nil
		end
		if not selectedUid and uids[1] then
			selectHat(uids[1])
		else
			showTooltip(selectedUid)
		end
	end

	for _, key in ipairs({ "Hats", "EquippedHat", "__Stats" }) do
		DataController:OnChange(key, function()
			if window.Visible then
				refresh()
			end
		end)
	end

	return {
		Window = window,
		Close = close,
		OnOpen = function()
			refresh()
		end,
		Select = function(uid: string)
			selectHat(uid)
		end,
	}
end

return Menu
