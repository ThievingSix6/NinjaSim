--[[
	Skills: learn, upgrade and equip ninja / samurai skills (Config/Skills).
	Top: your four hotkey slots (click one to choose where Equip puts a skill) and
	your Coins / Shards. Two tabs: "Ninja Arts" (the 12 base skills as cards) and
	"Elements" (one block per ninja tier: its element, the rank that unlocks it and
	its two skills). A detail panel shows the numbers and the Learn / Equip / Upgrade
	buttons. Free skills unlock by level or ninja tier on their own; the rest are
	bought with Coins or Spirit Shards.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Skills = require(Shared.Config.Skills)
local Format = require(Shared.Util.Format)
local Tiers = require(Shared.Config.Tiers)

local Menu = {}

local KIND_TAG = {
	Damage = "ATTACK", Control = "CONTROL", Mobility = "MOVEMENT", Buff = "BUFF", Ultimate = "ULTIMATE",
}

-- Short shape text for the detail panel.
local function areaText(def): string
	if def.AreaText then
		return def.AreaText
	elseif def.Chain then
		return "Chains to " .. def.Chain .. "+ foes"
	elseif def.Clones then
		return def.Clones .. " clones, " .. def.Radius .. " studs"
	elseif def.Length and not def.Radius then
		return def.Length .. " stud dash"
	elseif def.Arc then
		return def.Range .. " stud cone"
	elseif def.Range and def.Radius then
		return def.Radius .. " stud blast"
	elseif def.Radius then
		return def.Radius .. " studs around you"
	end
	return "-"
end

-- Requirement in a few words for the card pill (element blocks already name the rank).
local function shortReason(def): string
	local u = def.Unlock
	if u.Kind == "Tier" and def.Element then
		return "Lv " .. Tiers.Get(u.Tier).Level
	elseif u.Kind == "Tier" then
		return Tiers.Get(u.Tier).Name
	elseif u.Kind == "Shards" then
		return "Rebirth " .. (u.Rebirths or 0)
	end
	return "Lv " .. (u.Level or 1)
end

local function damageText(def, level: number): string
	local power = Skills.Power(level)
	local mult = def.Damage * power
	if def.Id == "whirlwind_slash" then
		return string.format("2 x %.1f", mult)
	elseif def.Id == "kunai_rain" then
		return string.format("3 x %.1f", mult)
	elseif def.Id == "thousand_cuts" then
		return string.format("%.1f + %.1f", mult, def.FinalDamage * power)
	elseif def.Burn then
		return string.format("%.1f + burn", mult)
	elseif def.Field and def.Tick then
		return string.format("%.2f / %.1fs", mult, def.Tick)
	elseif def.Hits and def.FinalDamage then
		return string.format("%d x %.1f + %.1f", def.Hits, mult, def.FinalDamage * power)
	elseif def.FinalDamage then
		return string.format("%.1f + %.1f", mult, def.FinalDamage * power)
	elseif def.Hits then
		return string.format("%d x %.1f", def.Hits, mult)
	elseif def.Bolts then
		return string.format("x%.1f / bolt", mult)
	elseif def.Meteors then
		return string.format("x%.1f / star", mult)
	elseif def.Dot then
		return string.format("%.1f + %d x %.1f", mult, def.DotTicks, def.Dot * power)
	end
	return string.format("x%.1f", mult)
end

-- Tints an atlas icon (skills with IconTint); emoji fallbacks stay as they are.
local function tintIcon(icon: Instance?, def)
	if icon and icon:IsA("ImageLabel") then
		icon.ImageColor3 = def and def.IconTint or Color3.new(1, 1, 1)
	end
end

function Menu.Build(ctx)
	local Kit, Theme, Common = ctx.Kit, ctx.Theme, ctx.Common
	local DataController = ctx.Controllers.DataController

	local window, content, close = Kit.Window({
		Name = "Skills", Title = "Ninja Skills", Icon = "Shuriken", Accent = "Purple", Size = UDim2.fromOffset(880, 690), Parent = ctx.Parent,
	})

	local selected: string? = nil
	local targetSlot: number? = nil
	local cards = {}
	local refresh
	local selectTab: (string) -> () = function(_name: string) end
	local currentTab = "Ninja Arts"

	-- ===== top: loadout slots + balances =====
	local top = Kit.Well({ Size = UDim2.new(1, -250, 0, 84), Parent = content })
	Kit.Label({
		Text = "HOTKEYS", TextSize = 18, Color = Theme.SubText, Rotation = 0, Size = UDim2.fromOffset(92, 24),
		Position = UDim2.new(0, 12, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), StrokeThickness = 2, ZIndex = 3, Parent = top,
	})
	local slotButtons = {}
	for i = 1, Skills.Slots do
		local b = Kit.Button({
			Name = "Slot" .. i, Icon = "Shuriken", IconSize = 50, Color = "Slate", Size = UDim2.fromOffset(66, 66),
			Position = UDim2.new(0, 108 + (i - 1) * 80, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Radius = 12, ZIndex = 3, Parent = top,
			OnClick = function()
				targetSlot = i
				local data = DataController:Get()
				local id = data and data.SkillSlots[i]
				if id and id ~= "" then
					selected = id
					local def = Skills.Get(id)
					selectTab(if def and def.Element then "Elements" else "Ninja Arts")
				end
				refresh()
			end,
		})
		local chip = Kit.New("Frame", { BackgroundColor3 = Theme.Ink, Size = UDim2.fromOffset(24, 22), Position = UDim2.fromOffset(-6, -6), ZIndex = 8, Parent = b })
		Kit.Corner(7).Parent = chip
		Kit.Stroke(Theme.White, 1.5).Parent = chip
		Kit.Label({ Text = tostring(i), TextSize = 15, XAlign = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 9, StrokeThickness = 1.5, Parent = chip })
		local plus = b:FindFirstChild("Text") :: TextLabel
		plus.TextXAlignment = Enum.TextXAlignment.Center
		plus.TextSize = 34
		plus.TextColor3 = Theme.Muted
		slotButtons[i] = b
	end
	local hint = Kit.Label({
		Text = "", TextSize = 15, Color = Theme.SubText, Wrapped = true, Size = UDim2.new(1, -440, 1, -12),
		Position = UDim2.new(0, 432, 0, 6), StrokeThickness = 2, ZIndex = 3, Parent = top,
	})

	local wallet = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(236, 84), Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0), Parent = content })
	local coinPill = Kit.Panel({ Size = UDim2.fromOffset(236, 38), Paint = "Gold", StrokeThickness = 3, Radius = 10, Parent = wallet })
	local _, setCoins = Common.PriceTag(coinPill, "Coins", "0", { Size = UDim2.fromScale(1, 1), TextSize = 21, ZIndex = 3 })
	local shardPill = Kit.Panel({ Size = UDim2.fromOffset(236, 38), Position = UDim2.fromOffset(0, 46), Paint = "Cyan", StrokeThickness = 3, Radius = 10, Parent = wallet })
	local _, setShards = Common.PriceTag(shardPill, "Shards", "0", { Size = UDim2.fromScale(1, 1), TextSize = 21, ZIndex = 3 })

	-- ===== tabs: base skills | elemental tier skills =====
	local tabRow = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 42), Position = UDim2.fromOffset(0, 94), Parent = content })
	local tabHint = Kit.Label({
		Text = "", TextSize = 15, Color = Theme.SubText, Size = UDim2.new(1, -360, 1, 0), Position = UDim2.fromOffset(352, 0),
		StrokeThickness = 2, Parent = tabRow,
	})

	-- ===== grid + detail =====
	local left, right = Common.Split(content, 146, 280)
	local grid = Common.Grid(left, { CellSize = UDim2.fromOffset(112, 132) })
	local elementGrid = Common.Grid(left, { Name = "Elements", CellSize = UDim2.fromOffset(254, 178), Gap = 10 })
	elementGrid.Visible = false
	local detail = Common.Detail(right)

	local _, select = Kit.Tabs(tabRow, { { Name = "Ninja Arts", Icon = "Shuriken" }, { Name = "Elements", Icon = "Sparkle" } }, function(name)
		currentTab = name
		grid.Visible = name == "Ninja Arts"
		elementGrid.Visible = name == "Elements"
		tabHint.Text = if name == "Elements" then "Every ninja rank unlocks two skills of its element." else "Ninja and samurai arts: learn them with Coins or by rank."
		-- keep the detail panel on a skill from this tab (the newest one you own, else the first)
		local wantElement = name == "Elements"
		local current = Skills.Get(selected)
		if not current or (current.Element ~= nil) ~= wantElement then
			local data = DataController:Get()
			local pick = nil
			for _, def in ipairs(Skills.List) do
				if (def.Element ~= nil) == wantElement and (not pick or (data and data.Skills[def.Id])) then
					pick = def
				end
			end
			selected = pick and pick.Id
			if refresh then
				refresh()
			end
		end
	end, "Purple")
	selectTab = select

	local function act(action: string, ...)
		local ok = DataController:Request(action, ...)
		if ok then
			ctx.Controllers.SoundController:Play(if action == "EquipSkill" then "Equip" else "Purchase")
		end
		return ok
	end

	local function showDetail(data, def)
		local level = data.Skills[def.Id]
		local owned = level ~= nil
		-- charm levels (Config/Charms) count in every number shown
		local effective = Skills.Effective(level, DataController:GetStats(), def.Id)
		local shownLevel = effective or 1
		local meets, reason = Skills.MeetsRequirement(def, data)
		local lines = {
			{ "Damage", damageText(def, shownLevel), Theme.Red, "Katana" },
			{ "Cooldown", string.format("%.1fs", Skills.Cooldown(def, shownLevel)), Theme.XP, "Clock" },
			{ "Area", areaText(def), Theme.Text, "Areas" },
		}
		if def.Effect then
			local element = Skills.ElementById[def.Element]
			table.insert(lines, { "Effect", def.Effect, if element then element.Color:Lerp(Theme.White, 0.3) else Theme.Purple, "Sparkle" })
		elseif def.Kind == "Buff" then
			table.insert(lines, { "Buff", string.format("+%d%% DMG, %.0fs", (def.DamageBuff - 1) * Skills.Power(shownLevel) * 100, Skills.Duration(def, shownLevel)), Theme.Orange, "Heart" })
		elseif def.Stun and def.Stun >= 1 then
			table.insert(lines, { "Stun", string.format("%.1fs", def.Stun), Theme.Purple, "Star" })
		elseif def.Duration then
			table.insert(lines, { "Lasts", string.format("%.0fs", Skills.Duration(def, shownLevel)), Theme.Green, "Clock" })
		end
		local levelText = if owned then level .. " / " .. Skills.MaxLevel else "Not learned"
		if owned and effective and effective > level then
			levelText = string.format("%d  (+%d charms)", effective, effective - level)
		end
		table.insert(lines, 1, { "Level", levelText, if owned then Theme.Gold else Theme.Muted, "Star" })

		local actions = {}
		if not owned then
			local currency, price = Skills.Price(def)
			if not meets and def.Unlock.Kind == "Tier" then
				local tier = Tiers.Get(def.Unlock.Tier)
				table.insert(lines, { tier.Name, "Lv " .. tier.Level, Theme.Gold, "Lock" })
				table.insert(actions, { Text = "Unlocks at Lv " .. tier.Level, Color = "Dark", Enabled = false })
			elseif not meets then
				table.insert(lines, { "Unlock", reason or "", Theme.Gold, "Lock" })
				table.insert(actions, { Text = reason or "Locked", Color = "Dark", Enabled = false })
			elseif currency and price then
				table.insert(actions, {
					Text = "Learn " .. Format.Abbrev(price), Icon = Common.CurrencyIconName(currency), Color = "Green",
					Enabled = (data[currency] or 0) >= price,
					OnClick = function()
						if act("BuySkill", def.Id) then
							selected = def.Id
						end
					end,
				})
			else
				table.insert(actions, { Text = "Unlocking...", Color = "Dark", Enabled = false })
			end
		else
			local slot = table.find(data.SkillSlots, def.Id)
			if slot then
				table.insert(actions, {
					Text = "Unequip", Color = "Red",
					OnClick = function()
						act("UnequipSkill", slot)
					end,
				})
			else
				local into = targetSlot or table.find(data.SkillSlots, "") or 1
				table.insert(actions, {
					Text = "Equip " .. into, Color = "Blue",
					OnClick = function()
						act("EquipSkill", def.Id, into)
					end,
				})
			end
			if level < Skills.MaxLevel then
				local currency, cost = Skills.UpgradeCost(def, level, data.Level)
				table.insert(actions, {
					Text = Format.Abbrev(cost), Icon = Common.CurrencyIconName(currency), Color = "Green",
					Enabled = (data[currency] or 0) >= cost,
					OnClick = function()
						act("UpgradeSkill", def.Id)
					end,
				})
			else
				table.insert(actions, { Text = "MAX", Icon = "Star", Color = "Gold", Enabled = false })
			end
		end
		detail:Show({
			Title = def.Name, Icon = def.Icon, Paint = def.Paint,
			Tag = string.upper(def.Element or def.Theme) .. " " .. (KIND_TAG[def.Kind] or ""),
			Desc = def.Desc, Lines = lines, Actions = actions,
		})
		local preview = right:FindFirstChild("Preview", true)
		tintIcon(preview and preview:FindFirstChild("Icon"), def)
	end

	local function makeCard(def, parent: Instance)
		local currency = Skills.Price(def)
		local card = Common.Card({
			Title = def.Name, Paint = def.Paint, Icon = def.Icon, Currency = currency, Sub = "", LayoutOrder = def.Order, Parent = parent,
			OnClick = function()
				selected = def.Id
				refresh()
			end,
		})
		tintIcon(card.Frame:FindFirstChild("Icon"), def)
		cards[def.Id] = card
		return card
	end

	for _, def in ipairs(Skills.List) do
		if not def.Element then
			makeCard(def, grid)
		end
	end

	-- one block per element: header (element, rank chip, lock) and its two skill cards
	local blocks = {}
	for _, element in ipairs(Skills.Elements) do
		local tier = Tiers.Get(element.Tier)
		local list = Skills.ForTier(element.Tier)
		local block = Kit.Panel({ Name = element.Id, Color = Theme.Panel, Radius = 12, StrokeThickness = 2.5, LayoutOrder = element.Tier, Parent = elementGrid })
		local header = Kit.Panel({
			Paint = element.Paint, Size = UDim2.new(1, -12, 0, 30), Position = UDim2.fromOffset(6, 6), Radius = 9, StrokeThickness = 2,
			ZIndex = 2, Parent = block,
		})
		Kit.Icon(header, element.Icon, { Size = UDim2.fromOffset(38, 38), Position = UDim2.new(0, -6, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 5, Color = element.IconTint })
		Kit.Label({
			Text = string.upper(element.Id), TextSize = 18, Scaled = true, MaxTextSize = 18, Size = UDim2.new(1, -128, 1, -6),
			Position = UDim2.fromOffset(36, 3), StrokeThickness = 2.5, ZIndex = 5, Parent = header,
		})
		local chip = Kit.New("Frame", {
			BackgroundColor3 = Theme.Ink, BackgroundTransparency = 0.25, Size = UDim2.fromOffset(84, 22), Position = UDim2.new(1, -5, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5), ZIndex = 4, Parent = header,
		})
		Kit.Corner(7).Parent = chip
		Kit.Stroke(tier.Color:Lerp(Color3.new(1, 1, 1), 0.25), 1.5).Parent = chip
		Kit.Label({
			Text = (string.gsub(tier.Name, " Ninja", "")), TextSize = 14, Scaled = true, MaxTextSize = 14, XAlign = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, -8, 1, 0), Position = UDim2.fromOffset(4, 0), StrokeThickness = 1.5, ZIndex = 5, Parent = chip,
		})
		local lock = Kit.Icon(header, "Lock", { Size = UDim2.fromOffset(22, 22), Position = UDim2.new(1, -92, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), ZIndex = 5 })
		lock.Visible = false
		for i, def in ipairs(list) do
			local card = makeCard(def, block)
			card.Frame.Size = UDim2.fromOffset(112, 132)
			card.Frame.Position = UDim2.fromOffset(10 + (i - 1) * 122, 40)
			card.Frame.ZIndex = 2
		end
		blocks[element.Id] = { Lock = lock, First = list[1] }
	end

	function refresh()
		local data = DataController:Get()
		if not data or not data.SkillSlots then
			return
		end
		setCoins(Format.Commas(data.Coins))
		setShards(Format.Commas(data.Shards))
		for i, b in ipairs(slotButtons) do
			local def = Skills.Get(data.SkillSlots[i])
			local api = Kit.Api(b)
			local icon = b:FindFirstChild("Icon") :: GuiObject?
			local plus = b:FindFirstChild("Text") :: TextLabel?
			if def then
				api.SetColor(def.Paint)
				api.SetIcon(def.Icon)
				tintIcon(icon, def)
			else
				api.SetColor("Slate")
			end
			if icon then
				icon.Visible = def ~= nil
			end
			if plus then
				plus.Text = if def then "" else "+"
			end
			local stroke = b:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if targetSlot == i then Theme.White else Theme.Ink
				stroke.Thickness = if targetSlot == i then 4 else 3
			end
		end
		hint.Text = if targetSlot then "Equip puts a skill on key " .. targetSlot .. "." else "Press 1-4 to use. Click a key to pick where Equip goes."
		for _, def in ipairs(Skills.List) do
			local card = cards[def.Id]
			local level = data.Skills[def.Id]
			local slot = table.find(data.SkillSlots, def.Id)
			card.SetSelected(selected == def.Id)
			card.SetBadge(if slot then "Check" else nil)
			card.SetBadge2(if slot then "[" .. slot .. "]" else "")
			local pill = card.Frame:FindFirstChild("Pill")
			local tag = pill and pill:FindFirstChild("Price")
			local coin = tag and tag:FindFirstChild("Icon")
			local meets = level ~= nil or Skills.MeetsRequirement(def, data)
			if coin then
				(coin :: GuiObject).Visible = level == nil and meets
			end
			if level then
				card.SetLocked(nil)
				local effective = Skills.Effective(level, DataController:GetStats(), def.Id) or level
				if effective > level then
					card.SetSub("Lv " .. effective .. " (+" .. (effective - level) .. ")", Theme.Orange)
				else
					card.SetSub("Lv " .. level .. (if level >= Skills.MaxLevel then " MAX" else ""), Theme.Gold)
				end
			else
				local currency, price = Skills.Price(def)
				-- a lock over the card, the requirement in its pill, the title left readable
				card.SetLocked(if meets then nil else " ")
				if not meets then
					card.SetSub(shortReason(def), Theme.Gold)
				elseif currency and price then
					card.SetSub(Format.Abbrev(price), if (data[currency] or 0) >= price then Theme.Text else Theme.Red)
				else
					card.SetSub("Free", Theme.Green)
				end
			end
		end
		for _, b in pairs(blocks) do
			b.Lock.Visible = b.First ~= nil and not data.Skills[b.First.Id] and not Skills.MeetsRequirement(b.First, data)
		end
		local def = Skills.Get(selected)
		if def then
			showDetail(data, def)
		else
			detail:Clear()
		end
	end

	for _, key in ipairs({ "Skills", "SkillSlots", "Coins", "Shards", "Level", "BestTier", "Rebirths", "Charms" }) do
		DataController:OnChange(key, function()
			if window.Visible then
				refresh()
			end
		end)
	end

	return {
		Window = window,
		Close = close,
		OnOpen = function(arg)
			targetSlot = if type(arg) == "table" and arg.Slot then arg.Slot else nil
			local data = DataController:Get()
			if not selected and data then
				selected = if targetSlot then nil else data.SkillSlots[1]
				if selected == "" then
					selected = nil
				end
			end
			if not selected then
				selected = Skills.List[1].Id
			end
			local def = Skills.Get(selected)
			selectTab(if type(arg) == "table" and arg.Tab then arg.Tab elseif def and def.Element then "Elements" else currentTab)
			local bar = ctx.Controllers.SkillBar
			if bar and bar.Badge then
				bar.Badge.Visible = false
			end
			refresh()
		end,
	}
end

return Menu
