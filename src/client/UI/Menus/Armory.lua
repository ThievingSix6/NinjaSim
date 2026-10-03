--[[
	Armory: owned katanas and cosmetics (opened from the Inventory's weapon slot). Equip / unequip, compare against
	what's equipped, sort, and favourite (favourites always sort first).
	Scales to any number of items: it's just a grid over the owned sets.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Katanas = require(Shared.Config.Katanas)
local Combo = require(Shared.Config.Combo)
local Tiers = require(Shared.Config.Tiers)
local Shop = require(Shared.Config.Shop)
local Rarity = require(Shared.Config.Rarity)
local Stats = require(Shared.Stats)
local Format = require(Shared.Util.Format)

local Menu = {}

local SOURCE_TEXT = { Tier = "Ninja tier reward", Shop = "Bought in the Shop", Boss = "Boss drop", Secret = "Seal Shop (secret)" }
local KIND_ICON = { Aura = "Sparkle", Trail = "Star", KillEffect = "Flame", Title = "Scroll" }
local KIND_TEXT = { Aura = "Aura", Trail = "Trail", KillEffect = "Kill Effect", Title = "Title" }

function Menu.Build(ctx)
	local Kit, Theme, Common = ctx.Kit, ctx.Theme, ctx.Common
	local DataController = ctx.Controllers.DataController

	local window, content, close = Kit.Window({
		Name = "Armory", Title = "Armory", Icon = "Katana", Accent = "Blue", Size = UDim2.fromOffset(880, 540), Parent = ctx.Parent,
	})
	local left, right = Common.Split(content, 50)
	local grid = Common.Grid(left, { CellSize = UDim2.fromOffset(112, 132) })
	local detail = Common.Detail(right)

	local currentTab = "Katanas"
	local sortMode = "Best"
	local selectedId: string? = nil
	local cards = {}

	local function favKey(id: string): string
		return (if currentTab == "Katanas" then "katana:" else "cosmetic:") .. id
	end

	local showDetail
	local function selectItem(id: string)
		selectedId = id
		for cardId, card in pairs(cards) do
			card.SetSelected(cardId == id)
		end
		showDetail(id)
	end

	function showDetail(id: string)
		local data = DataController:Get()
		if not data then
			return
		end
		local isFav = data.Favorites[favKey(id)] == true
		local favAction = {
			Text = "", Icon = "Star", IconSize = 34, Color = if isFav then "Gold" else "Grey",
			OnClick = function()
				DataController:Request("FavoriteItem", favKey(id))
			end,
		}
		if currentTab == "Katanas" then
			local def = Katanas.Get(id)
			local equipped = data.EquippedKatana == id
			local usable = data.Tier >= def.RequiredTier
			local current = Katanas.Get(data.EquippedKatana)
			local newDamage = Stats.DamageWith(data, id)
			local diff = newDamage - DataController:GetStats().Damage
			detail:Show({
				Title = def.Name, Rarity = def.Rarity, Model = Common.KatanaModel(id),
				Lines = {
					{ "Multiplier", Format.Mult(def.Mult), Theme.Gold },
					{ "Style", Combo.StyleText(def.Weapon), Theme.SubText },
					{ "Damage", Format.Abbrev(newDamage), Theme.Text },
					{ if equipped then "Equipped" else "vs " .. (if current then current.Name else "equipped"), if equipped then "Yes" else (if diff >= 0 then "+" else "") .. Format.Abbrev(diff), if diff > 0 then Theme.Green elseif diff < 0 then Theme.Red else Theme.SubText },
					{ "Requires", Tiers.Get(def.RequiredTier).Name, if usable then Theme.Green else Theme.Red },
					{ "Source", SOURCE_TEXT[def.Source] or def.Source, Theme.SubText },
				},
				Actions = {
					{
						Text = if equipped then "Equipped" elseif usable then "Equip" else "Locked", Color = Common.Colors.Equip,
						Enabled = not equipped and usable,
						OnClick = function()
							if DataController:Request("EquipKatana", id) then
								ctx.Controllers.SoundController:Play("Equip")
							end
						end,
					},
					favAction,
				},
			})
		else
			local def = Shop.CosmeticsById[id]
			local equipped = data.Equipped[def.Kind] == id
			detail:Show({
				Title = def.Name, Rarity = def.Rarity, Icon = KIND_ICON[def.Kind],
				Desc = KIND_TEXT[def.Kind] .. " cosmetic.",
				Lines = {
					{ "Type", KIND_TEXT[def.Kind] },
					{ "Slot", if data.Equipped[def.Kind] ~= "" then (Shop.CosmeticsById[data.Equipped[def.Kind]] or { Name = "?" }).Name else "Empty", Theme.SubText },
				},
				Actions = {
					{
						Text = if equipped then "Unequip" else "Equip", Color = if equipped then "Grey" else Common.Colors.Equip,
						OnClick = function()
							if DataController:Request("EquipCosmetic", def.Kind, if equipped then "" else id) then
								ctx.Controllers.SoundController:Play("Equip")
							end
						end,
					},
					favAction,
				},
			})
		end
	end

	local function rebuild()
		local data = DataController:Get()
		if not data then
			return
		end
		Common.ClearGrid(grid)
		table.clear(cards)
		local items = {}
		if currentTab == "Katanas" then
			for id in pairs(data.Katanas) do
				local def = Katanas.Get(id)
				if def then
					table.insert(items, { Id = id, Def = def, Score = def.Mult, Fav = data.Favorites["katana:" .. id] == true })
				end
			end
		else
			for id in pairs(data.Cosmetics) do
				local def = Shop.CosmeticsById[id]
				if def then
					table.insert(items, { Id = id, Def = def, Score = Rarity.Index(def.Rarity), Fav = data.Favorites["cosmetic:" .. id] == true })
				end
			end
		end
		table.sort(items, function(a, b)
			if a.Fav ~= b.Fav then
				return a.Fav
			end
			if sortMode == "Rarity" then
				local ra, rb = Rarity.Index(a.Def.Rarity), Rarity.Index(b.Def.Rarity)
				if ra ~= rb then
					return ra > rb
				end
			elseif sortMode == "Name" then
				return a.Def.Name < b.Def.Name
			elseif a.Score ~= b.Score then
				return a.Score > b.Score
			end
			return a.Def.Name < b.Def.Name
		end)
		for i, item in ipairs(items) do
			local def = item.Def
			local card
			if currentTab == "Katanas" then
				local equipped = data.EquippedKatana == item.Id
				card = Common.Card({
					Title = def.Name, Rarity = def.Rarity, Model = Common.KatanaModel(item.Id), LayoutOrder = i, Parent = grid,
					Sub = if equipped then "Equipped" else Format.Mult(def.Mult), SubColor = if equipped then Theme.Green else Theme.Gold,
					OnClick = function()
						selectItem(item.Id)
					end,
				})
				if equipped then
					card.SetBadge("✅")
				end
				if data.Tier < def.RequiredTier then
					card.SetLocked(Tiers.Get(def.RequiredTier).Name)
				end
			else
				local equipped = data.Equipped[def.Kind] == item.Id
				card = Common.Card({
					Title = def.Name, Rarity = def.Rarity, Icon = KIND_ICON[def.Kind], LayoutOrder = i, Parent = grid,
					Sub = if equipped then "Equipped" else KIND_TEXT[def.Kind], SubColor = if equipped then Theme.Green else nil,
					OnClick = function()
						selectItem(item.Id)
					end,
				})
				if equipped then
					card.SetBadge("✅")
				end
			end
			if item.Fav then
				card.SetBadge2("⭐")
			end
			cards[item.Id] = card
		end
		if #items == 0 then
			Common.EmptyNote(grid, if currentTab == "Katanas" then "No katanas yet." else "No cosmetics yet. Visit the Shop!")
			detail:Clear()
			return
		end
		if selectedId and cards[selectedId] then
			selectItem(selectedId)
		else
			selectItem(items[1].Id)
		end
	end

	local _, selectTab = Kit.Tabs(content, { { Name = "Katanas", Icon = "Katana" }, { Name = "Cosmetics", Icon = "Sparkle" } }, function(name)
		if name ~= currentTab then
			selectedId = nil
		end
		currentTab = name
		rebuild()
	end, "Blue")
	Common.Cycle(content, { "Best", "Rarity", "Name" }, "Sort: ", function(mode)
		sortMode = mode
		rebuild()
	end, { Position = UDim2.new(1, -282, 0, 2), AnchorPoint = Vector2.new(1, 0) })

	for _, key in ipairs({ "Katanas", "EquippedKatana", "Cosmetics", "Equipped", "Favorites", "Tier" }) do
		DataController:OnChange(key, function()
			if window.Visible then
				rebuild()
			end
		end)
	end

	return {
		Window = window,
		Close = close,
		OnOpen = function(tab)
			selectTab(if type(tab) == "string" then tab else currentTab)
		end,
	}
end

return Menu
