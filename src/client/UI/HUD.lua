--[[
	HUD, laid out like the big simulator games:
	  top centre     Shop / Teleport / Upgrades buttons, server event pill
	  left           Free Gifts button + a 2-column grid of square menu buttons
	  bottom left    rebirths, coins, shards, friend boost
	  bottom centre  rank + damage, XP bar with the level, health bar
	  right          next-goal card (teaches the loop), active boost timers
	  bottom right   multiplier chips (and the attack button on mobile)
	plus the combo meter and kill-streak callouts.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Tiers = require(Shared.Config.Tiers)
local Zones = require(Shared.Config.Zones)
local Shop = require(Shared.Config.Shop)
local Enemies = require(Shared.Config.Enemies)
local Gifts = require(Shared.Config.Gifts)
local Achievements = require(Shared.Config.Achievements)
local Events = require(Shared.Config.Events)
local Format = require(Shared.Util.Format)
local TableUtil = require(Shared.Util.TableUtil)

local HUD = {}

local Kit, Theme, controllers
local refs: any = {}
local comboHideAt = 0

-- menu buttons: the three big ones on top, the square grid on the left
local TOP_BUTTONS = {
	{ Name = "Shop", Text = "Shop", Icon = "Shop", Color = "Pink", Size = Vector2.new(158, 54) },
	{ Name = "Areas", Text = "Teleport", Icon = "Areas", Color = "Blue", Size = Vector2.new(196, 62) },
	{ Name = "Upgrades", Text = "Upgrades", Icon = "Upgrade", Color = "Green", Size = Vector2.new(176, 54) },
}
local GRID_BUTTONS = {
	{ Name = "Pets", Icon = "Pets", Color = "Orange" },
	{ Name = "Inventory", Icon = "Inventory", Color = "Blue" },
	{ Name = "Hats", Icon = "Crown", Color = "Cyan" },
	{ Name = "Suits", Icon = "Star", Color = "Gold" },
	{ Name = "Trade", Icon = "Friends", Color = "Sky" },
	{ Name = "Rebirth", Icon = "Rebirth", Color = "Purple" },
	{ Name = "Trophies", Icon = "Trophy", Color = "Gold" },
	{ Name = "Hire", Icon = "Friends", Color = "Green" },
	{ Name = "Settings", Icon = "Settings", Color = "Grey" },
}
local BOOST_ICONS = { XP2 = "Book", Coins2 = "Coin", Damage = "Flame", Luck = "Clover", Haste = "Bolt" }

local function open(name: string)
	controllers.MenuManager:Toggle(name)
end

-- Square tile: big icon, name straddling the bottom edge, "!" badge.
local function tileButton(parent: Instance, def, index: number)
	local button = Kit.Button({
		Name = def.Name, Icon = def.Icon, IconSize = 58, Color = def.Color, Size = UDim2.fromOffset(84, 84),
		LayoutOrder = index, Radius = 12, Parent = parent,
		OnClick = function()
			open(def.Name)
		end,
	})
	local icon = button:FindFirstChild("Icon") :: GuiObject?
	if icon then
		icon.Position = UDim2.new(0.5, 0, 0.42, 0)
	end
	Kit.Label({
		Text = def.Name, TextSize = 18, Size = UDim2.new(1, 8, 0, 20), Position = UDim2.new(0.5, 0, 1, -12),
		AnchorPoint = Vector2.new(0.5, 0.5), XAlign = Enum.TextXAlignment.Center, ZIndex = 5, StrokeThickness = 2.5, Parent = button,
	})
	local badge = Kit.Badge(button, {})
	return button, badge
end

-- [icon] number rows for the currency stack
local function currencyRow(parent: Instance, icon: string, color: Color3, iconSize: number, textSize: number, order: number)
	local row = Kit.New("Frame", {
		BackgroundTransparency = 1, Size = UDim2.new(0, 0, 0, iconSize), AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = order, Name = icon .. "Row", Parent = parent,
	})
	Kit.List(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center).Parent = row
	local image = Kit.Icon(row, icon, { Size = UDim2.fromOffset(iconSize, iconSize), LayoutOrder = 1 })
	local amount = Kit.Label({
		Text = "0", Font = Theme.FontNumber, TextSize = textSize, Color = color, AutoX = true,
		Size = UDim2.new(0, 0, 1, 0), LayoutOrder = 2, StrokeThickness = math.max(2.5, textSize / 11), Parent = row,
	})
	return row, amount, image
end

-- ===== Objective logic: always one clear next goal =====
local function currentGoal(data)
	local kills = data.Lifetime.Kills
	if kills < 3 and data.Rebirths == 0 then
		return "Click to slash! Defeat 3 Training Dummies", kills / 3
	end
	if data.Level < 5 and data.Rebirths == 0 then
		return "Keep fighting to reach Level 5", data.Level / 5
	end
	if TableUtil.Count(data.Pets) == 0 then
		local egg = require(Shared.Config.Pets).EggsById.village_egg
		return "Hatch a companion at the Village Egg (" .. Format.Abbrev(egg.Cost) .. " Coins)", math.min(1, data.Coins / egg.Cost)
	end
	local req = Balance.RebirthLevelRequirement(data.Rebirths)
	if data.Level >= req then
		return "REBIRTH is ready! Open the Rebirth menu", 1, "Rebirth"
	end
	for _, zone in ipairs(Zones.List) do
		if not data.Zones[zone.Id] then
			if data.Level >= zone.Level then
				return "Unlock " .. zone.Name .. " (" .. Format.Abbrev(zone.Cost) .. " Coins)", math.min(1, data.Coins / math.max(zone.Cost, 1)), "Areas"
			end
			break
		end
	end
	if data.Lifetime.BossKills == 0 and data.Level >= 7 then
		local boss = Enemies.Get(Zones.List[1].Boss.Enemy)
		return "Defeat " .. boss.Name .. " in the Boss Arena", 0, "Areas"
	end
	local nextTier = Tiers.Next(data.Tier)
	if nextTier and nextTier.Level <= req then
		return "Reach Lv " .. nextTier.Level .. " to become a " .. nextTier.Name, data.Level / nextTier.Level
	end
	return "Reach Lv " .. req .. " to Rebirth", data.Level / req, "Rebirth"
end

function HUD:GetCoinTarget(): Vector2
	local f = refs.CoinIcon :: GuiObject
	local pos = f.AbsolutePosition + f.AbsoluteSize / 2
	return Vector2.new(pos.X, pos.Y) / controllers.UIController.Scale
end

function HUD:PulseCoins()
	local scale = refs.CoinScale :: UIScale
	scale.Scale = 1.15
	Kit.Tween(scale, { Scale = 1 }, 0.2, Enum.EasingStyle.Back)
end

-- The stamina bar shakes when an attack or dodge is tried with an empty pool.
local lastStaminaFlash = 0
function HUD:FlashStamina()
	local now = os.clock()
	if not refs.StaminaScale or now - lastStaminaFlash < 0.6 then
		return
	end
	lastStaminaFlash = now
	refs.StaminaScale.Scale = 1.25
	Kit.Tween(refs.StaminaScale, { Scale = 1 }, 0.25, Enum.EasingStyle.Back)
end

function HUD:SetCombo(n: number)
	if n < 2 then
		return
	end
	refs.Combo.Visible = true
	refs.ComboCount.Text = "x" .. n
	local hue = math.clamp(n / 40, 0, 1)
	refs.ComboCount.TextColor3 = Color3.fromRGB(255, 240, 120):Lerp(Color3.fromRGB(255, 70, 90), hue)
	refs.ComboScale.Scale = 1.35
	Kit.Tween(refs.ComboScale, { Scale = 1 }, 0.15, Enum.EasingStyle.Back)
	comboHideAt = os.clock() + Balance.ComboWindow + 0.3
end

-- Kill streak callouts float up over the player's head and fade (a BillboardGui
-- built from the hidden screen label, so it keeps the HUD's font and outline).
local streakPopup: BillboardGui? = nil
function HUD:ShowStreak(text: string, count: number)
	controllers.CameraController:Shake(0.15)
	local player = Players.LocalPlayer
	local character = player.Character
	local anchor = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not anchor or not anchor:IsA("BasePart") or not playerGui then
		return
	end
	if streakPopup then
		streakPopup:Destroy() -- a newer streak replaces the old one
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "StreakPopup"
	gui.Adornee = anchor
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Size = UDim2.fromOffset(360, 56)
	gui.StudsOffset = Vector3.new(0, 2.4, 0)
	gui.Parent = playerGui
	streakPopup = gui
	local label = (refs.Streak :: TextLabel):Clone()
	label.Size = UDim2.fromScale(1, 1)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.TextSize = if count >= 6 then 40 else 34
	label.Text = text
	label.TextColor3 = if count >= 6 then Theme.Pink else Theme.Gold
	label.TextTransparency = 0
	label.Visible = true
	label.Parent = gui
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
	end
	local scale = label:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 1.7
		Kit.Tween(scale, { Scale = 1 }, 0.25, Enum.EasingStyle.Back)
	end
	-- drift up, then fade the text and its outline and remove it
	Kit.Tween(gui, { StudsOffset = Vector3.new(0, 4.4, 0) }, 1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	task.delay(1, function()
		if streakPopup ~= gui then
			return
		end
		Kit.Tween(label, { TextTransparency = 1 }, 0.45)
		if stroke then
			Kit.Tween(stroke, { Transparency = 1 }, 0.45)
		end
		task.wait(0.5)
		gui:Destroy()
		if streakPopup == gui then
			streakPopup = nil
		end
	end)
end

function HUD:SetBadge(name: string, on: boolean)
	local badge = refs.Badges[name]
	if badge then
		badge.Visible = on
	end
end

-- The touch LOCK button lights up while a target is locked (LockOnController).
function HUD:SetLockOn(on: boolean)
	if refs and refs.LockButton then
		Kit.Api(refs.LockButton).SetColor(if on then "Red" else "Dark")
	end
end

function HUD:GetMenuButton(name: string): GuiObject?
	return refs.MenuButtons[name]
end

local function refreshXP(data)
	local need = Balance.XPToNext(data.Level)
	refs.SetXP(data.XP / need)
	refs.XPText.Text = Format.Abbrev(data.XP) .. " / " .. Format.Abbrev(need) .. " XP"
	refs.LevelText.Text = "Level " .. Format.Abbrev(data.Level)
end

local function refreshRank(data)
	local stats = controllers.DataController:GetStats()
	local tier = Tiers.Get(data.Tier)
	refs.TierName.Text = tier.Name
	refs.TierName.TextColor3 = tier.Color:Lerp(Theme.White, 0.25)
	if stats then
		refs.Damage.Text = Format.Abbrev(stats.Damage) .. " DMG"
		local pets = stats.PetBonus
		refs.Chips.Damage.Text = "x" .. Format.Abbrev(math.floor((1 + pets.Damage) * 100 + 0.5) / 100)
		refs.Chips.Coins.Text = "x" .. Format.Abbrev(math.floor(stats.CoinMult * 100 + 0.5) / 100)
		refs.Chips.Luck.Text = "+" .. math.floor(stats.Luck * 100 + 0.5) .. "%"
	end
	refs.RebirthCount.Text = tostring(data.Rebirths)
end

local function refreshGoal(data)
	local text, progress, menu = currentGoal(data)
	refs.GoalText.Text = text
	refs.GoalMenu = menu
	refs.GoalArrow.Visible = menu ~= nil
	refs.SetGoal(progress, math.floor(math.clamp(progress, 0, 1) * 100) .. "%")
end

local function refreshBadges(data)
	HUD:SetBadge("Rebirth", data.Level >= Balance.RebirthLevelRequirement(data.Rebirths))
	local Upgrades = require(Shared.Config.Upgrades)
	local affordable = false
	if data.Rebirths > 0 then
		for _, u in ipairs(Upgrades.List) do
			local lvl = data.Upgrades[u.Id] or 0
			if lvl < u.Max and data.Shards >= Upgrades.Cost(u, lvl) then
				affordable = true
				break
			end
		end
	end
	HUD:SetBadge("Upgrades", affordable)
	local zoneReady = false
	for _, zone in ipairs(Zones.List) do
		if not data.Zones[zone.Id] then
			zoneReady = data.Level >= zone.Level and data.Coins >= zone.Cost
			break
		end
	end
	HUD:SetBadge("Areas", zoneReady)
end

local function refreshBoosts(data)
	local list = refs.Boosts :: Frame
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for i, def in ipairs(Shop.Boosts) do
		local seconds = data.Boosts[def.Id]
		if seconds and seconds > 0 then
			local pill = Kit.Panel({ Size = UDim2.fromOffset(196, 46), Paint = "Purple", Radius = 10, StrokeThickness = 3, LayoutOrder = i, Parent = list })
			Kit.Paint(pill, { Color3.fromRGB(255, 120, 220), Color3.fromRGB(150, 60, 235) })
			Kit.Icon(pill, BOOST_ICONS[def.Id] or def.Icon, { Size = UDim2.fromOffset(40, 40), Position = UDim2.new(0, -6, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 3, Rotation = -8 })
			Kit.Label({ Text = def.Name, TextSize = 19, Size = UDim2.new(1, -100, 1, 0), Position = UDim2.fromOffset(38, 0), ZIndex = 3, Parent = pill })
			local timer = Kit.Label({
				Name = "Timer", Text = Format.Time(seconds), Font = Theme.FontNumber, TextSize = 19, Size = UDim2.new(0, 60, 1, 0),
				Position = UDim2.new(1, -8, 0, 0), AnchorPoint = Vector2.new(1, 0), XAlign = Enum.TextXAlignment.Right, ZIndex = 3, Parent = pill,
			})
			pill:SetAttribute("EndsAt", os.clock() + seconds)
			timer:SetAttribute("Boost", def.Id)
		end
	end
end

function HUD:Start(c)
	controllers = c
	Kit, Theme = c.Kit, c.Theme
	local root = c.UIController:Root("HUD")
	refs.MenuButtons = {}
	refs.Badges = {}

	-- ===== top centre: Shop / Teleport / Upgrades =====
	local top = Kit.New("Frame", {
		BackgroundTransparency = 1, Size = UDim2.fromOffset(600, 70), Position = UDim2.new(0.5, 0, 0, 8),
		AnchorPoint = Vector2.new(0.5, 0), Name = "TopButtons", Parent = root,
	})
	Kit.List(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top).Parent = top
	for i, def in ipairs(TOP_BUTTONS) do
		local button = Kit.Button({
			Name = def.Name, Text = def.Text, Icon = def.Icon, Color = def.Color, TextSize = if i == 2 then 28 else 25,
			IconSize = if i == 2 then 46 else 40, Size = UDim2.fromOffset(def.Size.X, def.Size.Y), Radius = 12,
			StrokeThickness = 3.5, LayoutOrder = i, Parent = top,
			OnClick = function()
				open(def.Name)
			end,
		})
		refs.MenuButtons[def.Name] = button
		refs.Badges[def.Name] = Kit.Badge(button, {})
	end

	-- admin panel button, top right, only for admins
	local adminButton = Kit.Button({
		Name = "Admin", Text = "Admin", Icon = "Crown", Color = "Purple", TextSize = 20, IconSize = 32,
		Size = UDim2.fromOffset(130, 46), Position = UDim2.new(1, -12, 0, 12), AnchorPoint = Vector2.new(1, 0),
		Radius = 12, StrokeThickness = 3, Parent = root,
		OnClick = function()
			open("Admin")
		end,
	})
	local function showAdmin()
		adminButton.Visible = Players.LocalPlayer:GetAttribute("NinjaAdmin") ~= nil
	end
	showAdmin()
	Players.LocalPlayer:GetAttributeChangedSignal("NinjaAdmin"):Connect(showAdmin)
	refs.MenuButtons.Admin = adminButton

	-- server event + friends bonus, under the top buttons
	local eventPill = Kit.Panel({
		Size = UDim2.fromOffset(400, 40), Position = UDim2.new(0.5, 0, 0, 84), AnchorPoint = Vector2.new(0.5, 0),
		Paint = "Gold", Radius = 10, StrokeThickness = 3, Visible = false, Name = "EventPill", Parent = root,
	})
	refs.EventPill = eventPill
	refs.EventScale = Kit.New("UIScale", { Parent = eventPill })
	Kit.Icon(eventPill, "Flame", { Size = UDim2.fromOffset(44, 44), Position = UDim2.new(0, -14, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Rotation = -10, ZIndex = 4 })
	refs.EventText = Kit.Label({
		Text = "", TextSize = 19, RichText = true, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, -40, 1, 0),
		Position = UDim2.fromOffset(28, 0), ZIndex = 4, StrokeThickness = 2.5, Parent = eventPill,
	})

	-- ===== left: Free Gifts + square menu grid =====
	local left = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(280, 400), Position = UDim2.fromOffset(16, 158), Name = "Left", Parent = root })
	local gifts = Kit.Button({
		Name = "Gifts", Text = "Free Gifts", Icon = "Gift", IconSize = 44, TextSize = 23, Color = "Green",
		Size = UDim2.fromOffset(176, 52), Radius = 12, StrokeThickness = 3.5, Parent = left,
		OnClick = function()
			open("Gifts")
		end,
	})
	refs.MenuButtons.Gifts = gifts
	refs.Badges.Gifts = Kit.Badge(gifts, {})
	-- countdown to the next free gift
	refs.GiftTimer = Kit.Label({
		Text = "", Font = Theme.FontNumber, TextSize = 16, Color = Theme.Gold, XAlign = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 1, 3), Name = "GiftTimer", Parent = gifts,
	})
	-- three columns of tiles (nine menus)
	local grid = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(272, 300), Position = UDim2.fromOffset(0, 80), Name = "Grid", Parent = left })
	Kit.New("UIGridLayout", { CellSize = UDim2.fromOffset(84, 84), CellPadding = UDim2.fromOffset(8, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	for i, def in ipairs(GRID_BUTTONS) do
		local button, badge = tileButton(grid, def, i)
		refs.MenuButtons[def.Name] = button
		refs.Badges[def.Name] = badge
	end

	-- ===== bottom left: rebirths, coins, shards, friend boost =====
	local wallet = Kit.New("Frame", {
		BackgroundTransparency = 1, Size = UDim2.fromOffset(360, 170), Position = UDim2.new(0, 16, 1, -12),
		AnchorPoint = Vector2.new(0, 1), Name = "Wallet", Parent = root,
	})
	Kit.List(Enum.FillDirection.Vertical, 0, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Bottom).Parent = wallet
	local _, rebirthCount = currencyRow(wallet, "Rebirth", Theme.White, 32, 26, 1)
	refs.RebirthCount = rebirthCount
	local coinRow, coins, coinIcon = currencyRow(wallet, "Coin", Theme.Gold, 50, 44, 2)
	refs.CoinPill = coinRow
	refs.CoinIcon = coinIcon
	refs.CoinScale = Kit.New("UIScale", { Parent = coinRow })
	Kit.Button({
		Name = "AddCoins", Text = "+", TextSize = 26, Color = "Green", Size = UDim2.fromOffset(32, 32), Radius = 8,
		LayoutOrder = 3, Parent = coinRow,
		OnClick = function()
			controllers.MenuManager:Open("Shop", "Boosts")
		end,
	})
	local _, shards = currencyRow(wallet, "Shard", Theme.Shard, 38, 32, 3)
	refs.FriendBoost = Kit.Label({
		Text = "Friend Boost: +0%", TextSize = 18, Size = UDim2.fromOffset(300, 24), LayoutOrder = 4, StrokeThickness = 2.5, Parent = wallet,
	})

	-- ===== bottom centre: rank + damage, XP bar, health =====
	local centre = Kit.New("Frame", {
		BackgroundTransparency = 1, Size = UDim2.fromOffset(480, 110), Position = UDim2.new(0.5, 0, 1, -10),
		AnchorPoint = Vector2.new(0.5, 1), Name = "XPPanel", Parent = root,
	})
	refs.TierName = Kit.Label({ Text = "", TextSize = 22, Size = UDim2.new(0.6, 0, 0, 26), Position = UDim2.fromOffset(8, 0), StrokeThickness = 3, Parent = centre })
	local damageRow = Kit.New("Frame", {
		BackgroundTransparency = 1, Size = UDim2.new(0, 0, 0, 30), AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.new(1, -8, 0, -2), AnchorPoint = Vector2.new(1, 0), Parent = centre,
	})
	Kit.List(Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center).Parent = damageRow
	Kit.Icon(damageRow, "Katana", { Size = UDim2.fromOffset(30, 30), LayoutOrder = 1 })
	refs.Damage = Kit.Label({ Text = "", Font = Theme.FontNumber, TextSize = 22, Color = Theme.Gold, AutoX = true, Size = UDim2.new(0, 0, 1, 0), LayoutOrder = 2, StrokeThickness = 3, Parent = damageRow })
	local bar, setXP = Kit.ProgressBar({
		Size = UDim2.new(1, 0, 0, 38), Position = UDim2.fromOffset(0, 30), Light = true, Paint = "Gold", Radius = 10, StrokeThickness = 3.5, Parent = centre,
	})
	refs.XPBar = bar
	refs.SetXP = setXP
	refs.LevelText = Kit.Label({ Text = "Level 1", TextSize = 22, Size = UDim2.new(0.5, -12, 1, 0), Position = UDim2.fromOffset(12, 0), ZIndex = bar.ZIndex + 3, StrokeThickness = 3, Parent = bar })
	refs.XPText = Kit.Label({ Text = "", Font = Theme.FontNumber, TextSize = 20, XAlign = Enum.TextXAlignment.Right, Size = UDim2.new(0.5, -12, 1, 0), Position = UDim2.new(0.5, 0, 0, 0), ZIndex = bar.ZIndex + 3, StrokeThickness = 3, Parent = bar })
	refs.LevelScale = Kit.New("UIScale", { Parent = bar })
	local hp, setHP = Kit.ProgressBar({
		Size = UDim2.new(0.7, 0, 0, 22), Position = UDim2.new(0.5, 0, 0, 73), AnchorPoint = Vector2.new(0.5, 0),
		Paint = "Green", Radius = 8, TextSize = 15, Instant = true, Parent = centre,
	})
	Kit.Icon(centre, "Heart", { Size = UDim2.fromOffset(34, 34), Position = UDim2.new(0.15, -20, 0, 67), ZIndex = 5 })
	refs.SetHP = setHP
	refs.HPBar = hp
	-- stamina (attacks and dodges spend it; CombatController keeps the pool)
	local stamina, setStamina = Kit.ProgressBar({
		Size = UDim2.new(0.6, 0, 0, 11), Position = UDim2.new(0.5, 0, 0, 98), AnchorPoint = Vector2.new(0.5, 0),
		Paint = "Gold", Radius = 5, TextSize = 1, StrokeThickness = 2.5, Instant = true, Name = "Stamina", Parent = centre,
	})
	refs.SetStamina = setStamina
	refs.StaminaBar = stamina
	refs.StaminaScale = Kit.New("UIScale", { Parent = stamina })

	-- ===== right: next goal card + boost timers =====
	local right = Kit.New("Frame", {
		BackgroundTransparency = 1, Size = UDim2.fromOffset(270, 420), Position = UDim2.new(1, -16, 0, 158),
		AnchorPoint = Vector2.new(1, 0), Name = "Right", Parent = root,
	})
	Kit.List(Enum.FillDirection.Vertical, 12, Enum.HorizontalAlignment.Right).Parent = right
	local goal = Kit.Panel({ Size = UDim2.fromOffset(270, 118), Color = Theme.Panel, Radius = 12, StrokeThickness = 3.5, LayoutOrder = 1, Name = "Goal", Parent = right })
	local goalHeader = Kit.Panel({ Size = UDim2.new(1, 0, 0, 34), Paint = "Gold", Radius = 12, Stroke = false, ZIndex = 2, Parent = goal })
	Kit.New("Frame", { BackgroundColor3 = select(2, Kit.PaintColors("Gold")), BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 1, -12), ZIndex = 2, Parent = goalHeader })
	Kit.New("Frame", { BackgroundColor3 = Theme.Ink, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 3), Position = UDim2.new(0, 0, 1, 0), ZIndex = 3, Parent = goalHeader })
	Kit.Icon(goal, "Scroll", { Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(-14, -14), Rotation = -10, ZIndex = 6 })
	Kit.Label({ Text = "NEXT GOAL", TextSize = 21, Size = UDim2.new(1, -40, 0, 34), Position = UDim2.fromOffset(36, 0), ZIndex = 4, StrokeThickness = 2.5, Parent = goal })
	refs.GoalArrow = Kit.Label({ Text = "GO >", TextSize = 17, Color = Theme.White, XAlign = Enum.TextXAlignment.Right, Size = UDim2.fromOffset(70, 34), Position = UDim2.new(1, -10, 0, 0), AnchorPoint = Vector2.new(1, 0), ZIndex = 4, StrokeThickness = 2.5, Parent = goal })
	refs.GoalArrow.Visible = false
	refs.GoalText = Kit.Label({ Text = "", TextSize = 17, Wrapped = true, Size = UDim2.new(1, -24, 0, 44), Position = UDim2.fromOffset(12, 40), YAlign = Enum.TextYAlignment.Center, ZIndex = 2, StrokeThickness = 2, Parent = goal })
	local _, setGoal = Kit.ProgressBar({ Size = UDim2.new(1, -24, 0, 18), Position = UDim2.new(0, 12, 1, -26), Paint = "Gold", TextSize = 13, Radius = 6, StrokeThickness = 2.5, ZIndex = 2, Parent = goal })
	refs.SetGoal = setGoal
	-- the whole card is a shortcut to the menu that finishes the goal (when there is one)
	local goalButton = Kit.New("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 8, Name = "Open", Parent = goal })
	goalButton.Activated:Connect(function()
		if refs.GoalMenu then
			c.MenuManager:Open(refs.GoalMenu)
		end
	end)
	local boosts = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(200, 260), LayoutOrder = 2, Name = "Boosts", Parent = right })
	Kit.List(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Right).Parent = boosts
	refs.Boosts = boosts

	-- ===== bottom right: multiplier chips =====
	local chips = Kit.New("Frame", {
		BackgroundTransparency = 1, Size = UDim2.fromOffset(200, 64), Position = UDim2.new(1, -16, 1, -12),
		AnchorPoint = Vector2.new(1, 1), Name = "Chips", Parent = root,
	})
	Kit.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Bottom).Parent = chips
	refs.Chips = {}
	for i, chip in ipairs({ { "Damage", "Katana" }, { "Coins", "Coin" }, { "Luck", "Clover" } }) do
		local holder = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(54, 64), LayoutOrder = i, Parent = chips })
		Kit.Icon(holder, chip[2], { Size = UDim2.fromOffset(44, 44), Position = UDim2.fromScale(0.5, 0), AnchorPoint = Vector2.new(0.5, 0) })
		refs.Chips[chip[1]] = Kit.Label({ Text = "", Font = Theme.FontNumber, TextSize = 16, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 10, 0, 20), Position = UDim2.new(0.5, 0, 1, -18), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 2, StrokeThickness = 2.5, Parent = holder })
	end

	-- ===== combo + streak =====
	local combo = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(220, 110), Position = UDim2.new(1, -300, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Visible = false, Parent = root })
	refs.ComboCount = Kit.Label({ Text = "x2", Font = Theme.FontBig, TextSize = 64, Size = UDim2.new(1, 0, 0, 68), XAlign = Enum.TextXAlignment.Right, StrokeThickness = 4, Parent = combo })
	refs.ComboScale = Kit.New("UIScale", { Parent = refs.ComboCount })
	Kit.Label({ Text = "COMBO", TextSize = 24, Color = Theme.White, Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 66), XAlign = Enum.TextXAlignment.Right, StrokeThickness = 3, Parent = combo })
	refs.Combo = combo
	local streak = Kit.Label({ Text = "", Font = Theme.FontBig, TextSize = 50, Size = UDim2.fromOffset(700, 64), Position = UDim2.fromScale(0.5, 0.3), AnchorPoint = Vector2.new(0.5, 0.5), XAlign = Enum.TextXAlignment.Center, StrokeThickness = 4, Parent = root })
	streak.Visible = false
	Kit.New("UIScale", { Parent = streak })
	refs.Streak = streak

	-- ===== Mobile attack button =====
	if c.UIController:IsMobile() then
		local attack = Kit.Button({
			Icon = "Katana", IconSize = 80, Color = "Red", Size = UDim2.fromOffset(124, 124), Radius = 62,
			Position = UDim2.new(1, -150, 1, -240), AnchorPoint = Vector2.new(0.5, 0.5), StrokeThickness = 4, Parent = root,
		})
		-- tap for a light attack, hold to charge a heavy one
		attack.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				c.CombatController:PressAttack()
			end
		end)
		attack.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				c.CombatController:ReleaseAttack()
			end
		end)
		-- dodge roll: rolls the way the thumbstick points, or hops back
		local dodge = Kit.Button({
			Text = "ROLL", TextSize = 22, Color = "Sky", Size = UDim2.fromOffset(84, 84), Radius = 42,
			Position = UDim2.new(1, -270, 1, -170), AnchorPoint = Vector2.new(0.5, 0.5), StrokeThickness = 4, Parent = root,
		})
		dodge.MouseButton1Down:Connect(function()
			if c.DodgeController then
				c.DodgeController:Dodge()
			end
		end)
		-- target lock (LockOnController)
		local lock = Kit.Button({
			Text = "LOCK", TextSize = 18, Color = "Dark", Size = UDim2.fromOffset(70, 70), Radius = 35,
			Position = UDim2.new(1, -60, 1, -340), AnchorPoint = Vector2.new(0.5, 0.5), StrokeThickness = 4, Parent = root,
		})
		lock.MouseButton1Down:Connect(function()
			if c.LockOnController then
				c.LockOnController:Toggle()
			end
		end)
		refs.LockButton = lock
	end

	-- ===== Data bindings =====
	local D = c.DataController
	local function full()
		local data = D:Get()
		if not data then
			return
		end
		refreshXP(data)
		refreshRank(data)
		refreshGoal(data)
		refreshBadges(data)
	end
	D:OnChange("XP", full)
	D:OnChange("Level", function()
		full()
	end)
	D:OnChange("__Stats", full)
	D:OnChange("Coins", function(v)
		coins.Text = Format.Commas(v)
		local data = D:Get()
		if data then
			refreshGoal(data)
			refreshBadges(data)
		end
	end)
	D:OnChange("Shards", function(v)
		shards.Text = Format.Commas(v)
		full()
	end)
	D:OnChange("Boosts", function()
		local data = D:Get()
		if data then
			refreshBoosts(data)
		end
	end)
	for _, key in ipairs({ "Pets", "Zones", "Lifetime", "Rebirths", "Tier", "EquippedKatana" }) do
		D:OnChange(key, full)
	end

	-- free gift timers: badge + countdown under the Gifts button, toast when one unlocks.
	-- Also trophies: badge when one can be claimed, toast when one completes.
	local lastReady = 0
	local trophiesSeen: { [string]: boolean }? = nil
	task.spawn(function()
		while true do
			local data = D:Get()
			if data then
				local claimed = data.Achievements or {}
				local ready = {}
				local any = false
				for _, def in ipairs(Achievements.List) do
					if not claimed[def.Id] and Achievements.Progress(def, data) >= def.Target then
						ready[def.Id] = true
						any = true
						if trophiesSeen and not trophiesSeen[def.Id] then
							c.NotificationController:Toast("Trophy complete: " .. def.Name .. "! Claim it in Trophies.", Theme.Gold, "Trophy")
							c.SoundController:Play("LevelUp")
						end
					end
				end
				trophiesSeen = ready
				HUD:SetBadge("Trophies", any)
			end
			-- server event countdown + friends bonus
			local eventId = workspace:GetAttribute("EventId")
			local endsAt = workspace:GetAttribute("EventEndsAt")
			local friends = math.min(Players.LocalPlayer:GetAttribute("FriendBoost") or 0, Events.MaxFriends)
			refs.FriendBoost.Text = string.format("Friend Boost: +%d%%", friends * Events.FriendBonus * 100)
			local eventText
			if eventId and endsAt then
				for _, def in ipairs(Events.List) do
					if def.Id == eventId then
						eventText = string.format('%s  <font color="#fff4a8">%s</font>', def.Name, Format.Time(endsAt - workspace:GetServerTimeNow()))
					end
				end
			end
			refs.EventPill.Visible = eventText ~= nil
			if eventText then
				refs.EventText.Text = eventText
				refs.EventScale.Scale = 1.06
				Kit.Tween(refs.EventScale, { Scale = 1 }, 0.5)
			end
			local start = Players.LocalPlayer:GetAttribute("GiftStart")
			if start then
				local claimed = Gifts.ParseClaimed(Players.LocalPlayer:GetAttribute("GiftsClaimed"))
				local elapsed = workspace:GetServerTimeNow() - start
				local ready = Gifts.ReadyCount(elapsed, claimed)
				HUD:SetBadge("Gifts", ready > 0)
				if ready > lastReady then
					c.NotificationController:Toast("A free gift is ready! Open Gifts to claim it.", Theme.Gold, "Gift")
					c.SoundController:Play("Purchase")
				end
				lastReady = ready
				local nextIn
				for i, gift in ipairs(Gifts.List) do
					if not claimed[i] and elapsed < gift.Minutes * 60 then
						nextIn = gift.Minutes * 60 - elapsed
						break
					end
				end
				refs.GiftTimer.Text = if ready > 0 then "READY!" elseif nextIn then "Next gift " .. Format.Time(nextIn) else ""
			end
			task.wait(1)
		end
	end)

	-- per-frame: health, stamina, combo fade, boost timers
	local lastBoostTick = 0
	local lastStamina = -1
	RunService.RenderStepped:Connect(function()
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			setHP(humanoid.Health / math.max(humanoid.MaxHealth, 1), Format.Abbrev(math.ceil(humanoid.Health)) .. " / " .. Format.Abbrev(humanoid.MaxHealth))
		end
		local combat = c.CombatController
		if combat then
			local ratio = combat:GetStamina() / Balance.Stamina.Max
			if ratio ~= lastStamina then
				lastStamina = ratio
				refs.SetStamina(ratio)
			end
		end
		if refs.Combo.Visible and os.clock() > comboHideAt then
			refs.Combo.Visible = false
		end
		if os.clock() - lastBoostTick > 0.5 then
			lastBoostTick = os.clock()
			for _, p in ipairs(boosts:GetChildren()) do
				if p:IsA("Frame") then
					local timer = p:FindFirstChild("Timer") :: TextLabel?
					local endsAt = p:GetAttribute("EndsAt")
					if timer and endsAt then
						timer.Text = Format.Time(math.max(0, endsAt - os.clock()))
					end
				end
			end
		end
	end)
end

return HUD
