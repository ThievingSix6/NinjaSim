--[[
	Shop: Weapons, Boosts, Cosmetics, Utility. Everything costs Coins or Spirit
	Shards earned in game; prices are computed with the same shared formulas the
	server validates against, so what you see is what you pay.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Katanas = require(Shared.Config.Katanas)
local Combo = require(Shared.Config.Combo)
local Tiers = require(Shared.Config.Tiers)
local Shop = require(Shared.Config.Shop)
local Stats = require(Shared.Stats)
local Format = require(Shared.Util.Format)

local Menu = {}

function Menu.Build(ctx)
	local Kit, Theme, Common = ctx.Kit, ctx.Theme, ctx.Common
	local DataController = ctx.Controllers.DataController
	local accent = Theme.Pink

	local window, content, close = Kit.Window({
		Name = "Shop", Title = "Shop", Icon = "Shop", Accent = "Pink", Size = UDim2.fromOffset(880, 540), Parent = ctx.Parent,
	})
	local left, right = Common.Split(content, 50)
	local grid = Common.Grid(left, { CellSize = UDim2.fromOffset(112, 132) })
	local detail = Common.Detail(right)

	local currentTab = "Weapons"
	local selectedId: string? = nil
	local cards = {}
	local prices = {} -- id -> { currency, amount, affordable, recolour } for unowned items

	local function priceOfKatana(def)
		return Balance.CoinsForKills(def.CostLevel, def.CostKills)
	end

	local function buy(action: string, id: string, successText: string)
		local ok = DataController:Request(action, id)
		if ok then
			ctx.Controllers.SoundController:Play("Purchase")
			ctx.Controllers.NotificationController:Toast(successText, Theme.Green, "Check")
			ctx.Controllers.EffectsController:CharacterBurst(accent, false)
		end
	end

	local showDetail -- forward

	local function selectItem(id: string)
		selectedId = id
		for cardId, card in pairs(cards) do
			card.SetSelected(cardId == id)
		end
		showDetail(id)
	end

	-- ===== detail views =====
	function showDetail(id: string)
		local data = DataController:Get()
		if not data then
			return
		end
		if currentTab == "Weapons" then
			local def = Katanas.Get(id)
			local owned = data.Katanas[id] == true
			local price = priceOfKatana(def)
			local tierOk = data.Tier >= def.RequiredTier
			local current = Katanas.Get(data.EquippedKatana)
			local newDamage = Stats.DamageWith(data, id)
			local curDamage = DataController:GetStats().Damage
			local diff = newDamage - curDamage
			detail:Show({
				Title = def.Name, Rarity = def.Rarity, Model = Common.KatanaModel(id),
				Lines = {
					{ "Damage Multiplier", Format.Mult(def.Mult), Theme.Gold },
					{ "Style", Combo.StyleText(def.Weapon), Theme.SubText },
					{ "Your Damage", Format.Abbrev(newDamage), if diff > 0 then Theme.Green elseif diff < 0 then Theme.Red else Theme.Text },
					{ "vs " .. (if current then current.Name else "current"), (if diff >= 0 then "+" else "") .. Format.Abbrev(diff), if diff > 0 then Theme.Green elseif diff < 0 then Theme.Red else Theme.SubText },
					{ "Requires", Tiers.Get(def.RequiredTier).Name, if tierOk then Theme.Green else Theme.Red },
					{ "Price", Common.Price("Coins", price), Theme.Gold },
				},
				Actions = {
					if owned
						then { Text = "Owned", Icon = "Check", Color = "Grey", Enabled = false }
						else {
							Text = if tierOk then "Buy" else "Tier Locked", Icon = if tierOk then "Coin" else "Lock", Color = "Green",
							Enabled = tierOk and data.Coins >= price,
							OnClick = function()
								buy("BuyKatana", id, def.Name .. " purchased!")
							end,
						},
				},
			})
		elseif currentTab == "Boosts" then
			local def = Shop.BoostsById[id]
			local price = Balance.CoinsForKills(data.Level, def.CostKills)
			local active = data.Boosts[id] or 0
			local full = active + def.Duration > Shop.MaxBoostSeconds
			detail:Show({
				Title = def.Name, Icon = def.Icon, Color = def.Color, Tag = "BOOST", Desc = def.Desc,
				Lines = {
					{ "Duration", "+" .. Format.Time(def.Duration) },
					{ "Active", if active > 0 then Format.Time(active) else "No", if active > 0 then Theme.Green else Theme.SubText },
					{ "Stacks up to", Format.Time(Shop.MaxBoostSeconds) },
					{ "Price", Common.Price("Coins", price), Theme.Gold },
				},
				Actions = {
					{
						Text = if full then "Maxed" else (if active > 0 then "Extend" else "Buy"), Icon = "Coin", Color = "Green",
						Enabled = not full and data.Coins >= price,
						OnClick = function()
							buy("BuyBoost", id, def.Name .. " active!")
						end,
					},
				},
			})
		elseif currentTab == "Cosmetics" then
			local def = Shop.CosmeticsById[id]
			local owned = data.Cosmetics[id] == true
			local equipped = data.Equipped[def.Kind] == id
			local kindText = ({ Aura = "Aura", Trail = "Trail", KillEffect = "Kill Effect", Title = "Title" })[def.Kind]
			local action
			if owned then
				action = {
					Text = if equipped then "Unequip" else "Equip", Color = if equipped then "Grey" else Common.Colors.Equip,
					OnClick = function()
						DataController:Request("EquipCosmetic", def.Kind, if equipped then "" else id)
					end,
				}
			elseif def.Currency == "Rebirth" then
				action = { Text = "Unlocks at Rebirth " .. def.Cost, Color = "Purple", Enabled = false }
			else
				action = {
					Text = "Buy", Icon = Common.CurrencyIconName(def.Currency), Color = "Green", Enabled = Common.CanAfford(data, def.Currency, def.Cost),
					OnClick = function()
						buy("BuyCosmetic", id, def.Name .. " unlocked!")
					end,
				}
			end
			detail:Show({
				Title = def.Name, Rarity = def.Rarity, Icon = ({ Aura = "Sparkle", Trail = "Star", KillEffect = "Flame", Title = "Scroll" })[def.Kind],
				Desc = if def.Kind == "Title" then "Shows \"" .. def.Name .. "\" above your head." else "A " .. string.lower(kindText) .. " cosmetic. Purely visual.",
				Lines = {
					{ "Type", kindText },
					{ "Price", Common.Price(def.Currency, def.Cost), Common.CurrencyColor(def.Currency) },
					{ "Status", if equipped then "Equipped" elseif owned then "Owned" else "Not owned", if owned then Theme.Green else Theme.SubText },
				},
				Actions = { action },
			})
		elseif currentTab == "Utility" then
			local def = Shop.UtilityById[id]
			local owned = data.Utility[id] or 0
			local maxed = owned >= def.MaxOwned
			local price = Shop.UtilityCost(def, owned)
			local locked = def.RequiredRebirths and data.Rebirths < def.RequiredRebirths
			detail:Show({
				Title = def.Name, Icon = def.Icon, Paint = "Green", Tag = "UTILITY", Desc = def.Desc,
				Lines = {
					{ "Owned", owned .. " / " .. def.MaxOwned },
					{ "Price", if maxed then "-" else Common.Price(def.Currency, price), Common.CurrencyColor(def.Currency) },
					if def.RequiredRebirths then { "Requires", "Rebirth " .. def.RequiredRebirths, if locked then Theme.Red else Theme.Green } else nil,
				},
				Actions = {
					{
						Text = if maxed then "Maxed" elseif locked then "Locked" else "Buy", Icon = if maxed then "Check" elseif locked then "Lock" else Common.CurrencyIconName(def.Currency), Color = "Green",
						Enabled = not maxed and not locked and Common.CanAfford(data, def.Currency, price),
						OnClick = function()
							buy("BuyUtility", id, def.Name .. " purchased!")
						end,
					},
				},
			})
		end
	end

	-- ===== grids =====
	local function rebuild()
		local data = DataController:Get()
		if not data then
			return
		end
		Common.ClearGrid(grid)
		table.clear(cards)
		table.clear(prices)
		if currentTab == "Weapons" then
			for i, def in ipairs(Katanas.List) do
				if def.Source == "Shop" then
					local owned = data.Katanas[def.Id]
					local price = priceOfKatana(def)
					local card = Common.Card({
						Title = def.Name, Rarity = def.Rarity, Model = Common.KatanaModel(def.Id), LayoutOrder = i, Parent = grid,
						Sub = if owned then "Owned" else Common.Price("Coins", price), Currency = if owned then nil else "Coins",
						SubColor = if owned then Theme.Green elseif data.Coins >= price then Theme.Gold else Theme.Red,
						OnClick = function()
							selectItem(def.Id)
						end,
					})
					card.SetBadge2(Format.Mult(def.Mult))
					if data.Tier < def.RequiredTier and not owned then
						card.SetLocked(Tiers.Get(def.RequiredTier).Name)
					end
					if not owned then
						prices[def.Id] = { "Coins", price, data.Coins >= price, true }
					end
					cards[def.Id] = card
				end
			end
		elseif currentTab == "Boosts" then
			for i, def in ipairs(Shop.Boosts) do
				local price = Balance.CoinsForKills(data.Level, def.CostKills)
				local active = data.Boosts[def.Id]
				local card = Common.Card({
					Title = def.Name, Icon = def.Icon, Color = def.Color, LayoutOrder = i, Parent = grid, Currency = "Coins",
					Sub = Common.Price("Coins", price), SubColor = if data.Coins >= price then Theme.Gold else Theme.Red,
					OnClick = function()
						selectItem(def.Id)
					end,
				})
				if active then
					card.SetBadge("Clock")
				end
				prices[def.Id] = { "Coins", price, data.Coins >= price, true }
				cards[def.Id] = card
			end
		elseif currentTab == "Cosmetics" then
			local kindIcon = { Aura = "Sparkle", Trail = "Star", KillEffect = "Flame", Title = "Scroll" }
			for _, def in ipairs(Shop.Cosmetics) do
				local owned = data.Cosmetics[def.Id]
				local card = Common.Card({
					Title = def.Name, Rarity = def.Rarity, Icon = kindIcon[def.Kind], LayoutOrder = def.Order, Parent = grid,
					Sub = if owned then (if data.Equipped[def.Kind] == def.Id then "Equipped" else "Owned") else Common.Price(def.Currency, def.Cost),
					Currency = if owned then nil else def.Currency,
					SubColor = if owned then Theme.Green else Common.CurrencyColor(def.Currency),
					OnClick = function()
						selectItem(def.Id)
					end,
				})
				if not owned then
					prices[def.Id] = { def.Currency, def.Cost, Common.CanAfford(data, def.Currency, def.Cost), false }
				end
				cards[def.Id] = card
			end
		elseif currentTab == "Utility" then
			for i, def in ipairs(Shop.Utility) do
				local owned = data.Utility[def.Id] or 0
				local maxed = owned >= def.MaxOwned
				local card = Common.Card({
					Title = def.Name, Icon = def.Icon, Paint = "Green", LayoutOrder = i, Parent = grid,
					Sub = if maxed then "Maxed" else Common.Price(def.Currency, Shop.UtilityCost(def, owned)),
					Currency = if maxed then nil else def.Currency,
					SubColor = if maxed then Theme.Green else Common.CurrencyColor(def.Currency),
					OnClick = function()
						selectItem(def.Id)
					end,
				})
				if def.MaxOwned > 1 then
					card.SetBadge2(owned .. "/" .. def.MaxOwned)
				end
				if not maxed then
					local cost = Shop.UtilityCost(def, owned)
					prices[def.Id] = { def.Currency, cost, Common.CanAfford(data, def.Currency, cost), false }
				end
				cards[def.Id] = card
			end
		end
		if selectedId and cards[selectedId] then
			selectItem(selectedId)
		else
			selectedId = nil
			local first = nil
			for id, card in pairs(cards) do
				if not first or card.Frame.LayoutOrder < cards[first].Frame.LayoutOrder then
					first = id
				end
			end
			if first then
				selectItem(first)
			else
				detail:Clear()
			end
		end
	end

	local _, selectTab = Kit.Tabs(content, {
		{ Name = "Weapons", Icon = "Katana" }, { Name = "Boosts", Icon = "Potion" }, { Name = "Cosmetics", Icon = "Sparkle" }, { Name = "Utility", Icon = "Inventory" },
	}, function(name)
		if name ~= currentTab then
			selectedId = nil
		end
		currentTab = name
		rebuild()
	end, "Pink")

	local function refreshIfOpen()
		if window.Visible then
			rebuild()
		end
	end
	for _, key in ipairs({ "Katanas", "Boosts", "Cosmetics", "Equipped", "Utility", "Tier", "Rebirths" }) do
		DataController:OnChange(key, refreshIfOpen)
	end
	-- Currency changes happen every kill, so they only recolour prices (no
	-- viewport rebuilds) and refresh the detail panel when the selected item
	-- becomes (un)affordable. Level changes reprice boosts, throttled.
	local function recolour()
		local data = DataController:Get()
		if not data or not window.Visible then
			return
		end
		for id, p in pairs(prices) do
			local can = Common.CanAfford(data, p[1], p[2])
			if can ~= p[3] then
				p[3] = can
				if p[4] and cards[id] then
					cards[id].SetSub(Common.Price(p[1], p[2]), if can then Theme.Gold else Theme.Red)
				end
				if id == selectedId then
					showDetail(id)
				end
			end
		end
	end
	local pending = false
	for _, key in ipairs({ "Coins", "Shards" }) do
		DataController:OnChange(key, function()
			if window.Visible and not pending then
				pending = true
				task.delay(0.25, function()
					pending = false
					recolour()
				end)
			end
		end)
	end
	local levelPending = false
	DataController:OnChange("Level", function()
		if window.Visible and currentTab == "Boosts" and not levelPending then
			levelPending = true
			task.delay(1, function()
				levelPending = false
				refreshIfOpen()
			end)
		end
	end)

	return {
		Window = window,
		Close = close,
		OnOpen = function(tab)
			selectTab(if type(tab) == "string" then tab else currentTab)
		end,
	}
end

return Menu
