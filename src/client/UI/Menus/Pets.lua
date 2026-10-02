--[[
	Pets: every companion you own. Equip / unequip, Equip Best, favourite
	(protects from deletion), sort, and a multi-select delete mode.
	Cards are kept per pet uid and diffed, so hatching doesn't rebuild the grid.
	Mutated pets (Config/Mutations) show their mutation's name, multiplier and
	odds; Select All skips them and deleting one asks first.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Pets = require(Shared.Config.Pets)
local Rarity = require(Shared.Config.Rarity)
local Format = require(Shared.Util.Format)
local TableUtil = require(Shared.Util.TableUtil)
local Mutations = require(Shared.Config.Mutations)

local Menu = {}

function Menu.Build(ctx)
	local Kit, Theme, Common = ctx.Kit, ctx.Theme, ctx.Common
	local DataController = ctx.Controllers.DataController

	local window, content, close = Kit.Window({
		Name = "Pets", Title = "Pets", Icon = "Pets", Accent = "Orange", Size = UDim2.fromOffset(880, 560), Parent = ctx.Parent,
	})
	local left, right = Common.Split(content, 50)
	local grid = Common.Grid(left, { CellSize = UDim2.fromOffset(100, 118), Size = UDim2.new(1, 0, 1, -34) })
	local detail = Common.Detail(right)

	-- top bar
	local function chipRow(parent: Instance, props): Frame
		local row = Kit.New("Frame", { BackgroundTransparency = 1, Size = props.Size, Position = props.Position or UDim2.new(), Parent = parent })
		Kit.List(Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center).Parent = row
		return row
	end
	local function chip(row: Frame, order: number, icon: string, color: Color3, size: number): TextLabel
		Kit.Icon(row, icon, { Size = UDim2.fromOffset(size + 10, size + 10), LayoutOrder = order * 2 - 1 })
		return Kit.Label({
			Text = "", TextSize = size, Color = color, AutoX = true, Size = UDim2.new(0, 0, 1, 0), LayoutOrder = order * 2,
			StrokeThickness = 2, Parent = row,
		})
	end
	local countRow = chipRow(content, { Size = UDim2.fromOffset(270, 40) })
	local equippedCount = chip(countRow, 1, "Pets", Theme.Text, 19)
	Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(8, 10), LayoutOrder = 4, Parent = countRow })
	local storageCount = chip(countRow, 3, "Inventory", Theme.Text, 19)
	local bonusRow = chipRow(left, { Size = UDim2.new(1, 0, 0, 28), Position = UDim2.new(0, 0, 1, -28) })
	local teamLabel = Kit.Label({ Text = "Team bonus", TextSize = 16, Color = Theme.SubText, AutoX = true, Size = UDim2.new(0, 0, 1, 0), StrokeThickness = 2, Parent = bonusRow })
	teamLabel.LayoutOrder = 0
	local bonusText = {
		Damage = chip(bonusRow, 1, "Katana", Theme.Red, 16),
		XP = chip(bonusRow, 2, "Book", Theme.XP, 16),
		Coins = chip(bonusRow, 3, "Coin", Theme.Gold, 16),
		Luck = chip(bonusRow, 4, "Clover", Theme.Green, 16),
	}
	local sortMode = "Best"
	local deleteMode = false
	local marked: { [string]: boolean } = {}
	local selectedUid: string? = nil
	local cards: { [string]: any } = {}

	local deleteButton, equipBestButton, sortButton, selectAllButton, clearButton
	local refreshCards, showDetail

	local function markedCount(): number
		return TableUtil.Count(marked)
	end

	-- "x2 • 1/40" for a mutation's card pill
	local function mutationPill(m): string
		return Format.Mult(m.Mult) .. " • " .. Common.OddsText(m.OneIn, true)
	end

	local function updateDeleteButton()
		local api = Kit.Api(deleteButton)
		if deleteMode then
			local n = markedCount()
			api.SetText(if n > 0 then "Delete " .. n else "Cancel")
			api.SetColor(if n > 0 then Common.Colors.Danger else "Grey")
		else
			api.SetText("Multi Delete")
			api.SetColor("Red")
		end
		-- in select mode the sort / equip buttons make room for Select All and Clear
		if sortButton then
			sortButton.Visible = not deleteMode
			equipBestButton.Visible = not deleteMode
			selectAllButton.Visible = deleteMode
			clearButton.Visible = deleteMode
		end
	end

	local function selectItem(uid: string)
		if deleteMode then
			local data = DataController:Get()
			local pet = data and data.Pets[uid]
			if pet and pet.Fav then
				ctx.Controllers.NotificationController:Toast("Favourited pets are protected", Theme.Gold, "Star")
				return
			end
			marked[uid] = if marked[uid] then nil else true
			refreshCards()
			updateDeleteButton()
			return
		end
		selectedUid = uid
		for id, card in pairs(cards) do
			card.SetSelected(id == uid)
		end
		showDetail(uid)
	end

	function showDetail(uid: string)
		local data = DataController:Get()
		local owned = data and data.Pets[uid]
		if not owned then
			detail:Clear()
			return
		end
		local def = Pets.ById[owned.Id]
		local mutation = Mutations.Get(owned.Mutation)
		local name = Pets.DisplayName(def, owned.Mutation)
		local equipped = table.find(data.EquippedPets, uid) ~= nil
		local lines = Common.BonusLines(Pets.BonusOf(def, owned.Mutation))
		if mutation then
			table.insert(lines, 1, { "Mutation", mutation.Name .. " " .. Format.Mult(mutation.Mult), mutation.Color, "Sparkle" })
			table.insert(lines, 2, { "Mutation odds", Common.OddsText(mutation.OneIn), mutation.Color })
		end
		local sameCount = 0
		for _, p in pairs(data.Pets) do
			if p.Id == owned.Id then
				sameCount += 1
			end
		end
		local oneIn = Pets.OneIn(owned.Id)
		if oneIn then
			table.insert(lines, { "Odds", Common.OddsText(oneIn), Rarity.Color(def.Rarity) })
		end
		local combined = mutation and Pets.MutatedOneIn(owned.Id, owned.Mutation)
		if combined then
			table.insert(lines, { "Together", Common.OddsText(combined), mutation.Color })
		end
		table.insert(lines, { "You own", tostring(sameCount), Theme.SubText })
		detail:Show({
			Title = name, Rarity = def.Rarity, Model = Common.PetModel(owned.Id, owned.Mutation), Zoom = Common.PetZoom(1.1, owned.Mutation),
			Lines = lines,
			Actions = {
				{
					Text = if equipped then "Unequip" else "Equip", Color = if equipped then "Grey" else Common.Colors.Equip,
					OnClick = function()
						if DataController:Request(if equipped then "UnequipPet" else "EquipPet", uid) then
							ctx.Controllers.SoundController:Play("Equip")
						end
					end,
				},
				{
					Text = "", Icon = "Star", IconSize = 34, Color = if owned.Fav then "Gold" else "Grey",
					OnClick = function()
						DataController:Request("FavoritePet", uid)
					end,
				},
				{
					Text = "", Icon = "Trash", IconSize = 34, Color = Common.Colors.Danger, Enabled = not owned.Fav,
					OnClick = function()
						local warning = if mutation then " It's a " .. mutation.Name .. " mutation (" .. Format.Mult(mutation.Mult) .. ", 1 in " .. Format.Commas(mutation.OneIn) .. ")!" else ""
						Common.Confirm(ctx.Parent, "Delete pet?", "Delete " .. name .. "?" .. warning .. " This can't be undone.", "Delete", Common.Colors.Danger, function()
							DataController:Request("DeletePets", { uid })
						end)
					end,
				},
			},
		})
	end

	local function sortKey(data, uid: string)
		local owned = data.Pets[uid]
		local def = Pets.ById[owned.Id]
		local equipped = table.find(data.EquippedPets, uid) ~= nil
		local primary
		if sortMode == "Rarity" then
			primary = Rarity.Index(def.Rarity) * 1e6 + Pets.Score(def, owned.Mutation)
		elseif sortMode == "Newest" then
			primary = tonumber(uid) or 0
		else
			primary = Pets.Score(def, owned.Mutation)
		end
		-- equipped first, then favourites, then by the chosen key
		return (if equipped then 2e12 else 0) + (if owned.Fav then 1e12 else 0) + primary
	end

	function refreshCards()
		local data = DataController:Get()
		if not data then
			return
		end
		-- remove cards for pets we no longer own
		for uid, card in pairs(cards) do
			if not data.Pets[uid] then
				card.Frame:Destroy()
				cards[uid] = nil
				marked[uid] = nil
			end
		end
		-- add new ones
		for uid, owned in pairs(data.Pets) do
			if not cards[uid] then
				local def = Pets.ById[owned.Id]
				if def then
					local mutation = Mutations.Get(owned.Mutation)
					cards[uid] = Common.Card({
						Title = Pets.DisplayName(def, owned.Mutation), Rarity = def.Rarity, Parent = grid,
						Model = Common.PetModel(owned.Id, owned.Mutation), Zoom = Common.PetZoom(1.15, owned.Mutation),
						Sub = if mutation then mutationPill(mutation) else Common.OddsText(Pets.OneIn(owned.Id), true),
						SubColor = if mutation then mutation.Color else Rarity.Color(def.Rarity),
						OnClick = function()
							selectItem(uid)
						end,
					})
					if mutation then
						-- the mutation's name as a tilted tag over the pet
						Kit.Label({
							Name = "MutationTag", Text = string.upper(mutation.Name), Font = Theme.FontHeavy, TextSize = 14, Color = mutation.Color,
							XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 1, -62),
							Rotation = -5, StrokeThickness = 2, ZIndex = 6, Parent = cards[uid].Frame,
						})
					end
				end
			end
		end
		-- order + badges
		local uids = {}
		for uid in pairs(cards) do
			table.insert(uids, uid)
		end
		table.sort(uids, function(a, b)
			return sortKey(data, a) > sortKey(data, b)
		end)
		for i, uid in ipairs(uids) do
			local card = cards[uid]
			local owned = data.Pets[uid]
			card.Frame.LayoutOrder = i
			local equipped = table.find(data.EquippedPets, uid) ~= nil
			card.SetBadge(if equipped then "✅" else nil)
			card.SetBadge2(if owned.Fav then "⭐" else nil)
			card.SetLocked(if marked[uid] then "DELETE" else nil)
			card.SetSelected(uid == selectedUid and not deleteMode)
		end
		local empty = grid:FindFirstChild("Empty")
		if #uids == 0 and not empty then
			Common.EmptyNote(grid, "No pets yet! Walk up to an egg in any area to hatch one.")
		elseif #uids > 0 and empty then
			empty:Destroy()
		end

		local stats = DataController:GetStats()
		equippedCount.Text = string.format("%d/%d equipped", #data.EquippedPets, stats.PetSlots)
		storageCount.Text = string.format("%d/%d", #uids, stats.PetStorage)
		local b = stats.PetBonus
		for key, label in pairs(bonusText) do
			label.Text = Format.Percent(1 + b[key]) .. "  "
		end
		if selectedUid and not data.Pets[selectedUid] then
			selectedUid = nil
		end
		if not deleteMode then
			if selectedUid then
				showDetail(selectedUid)
			elseif uids[1] then
				selectItem(uids[1])
			else
				detail:Clear()
			end
		end
	end

	-- toolbar buttons (right-aligned above the grid)
	local toolbar = Kit.New("Frame", {
		BackgroundTransparency = 1, Size = UDim2.new(1, -270, 0, 40), Position = UDim2.fromOffset(270, 0), Parent = content,
	})
	Kit.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right).Parent = toolbar
	sortButton = Common.Cycle(toolbar, { "Best", "Rarity", "Newest" }, "Sort: ", function(mode)
		sortMode = mode
		refreshCards()
	end, { Size = UDim2.fromOffset(140, 38), LayoutOrder = 1 })
	equipBestButton = Kit.Button({
		Text = "Equip Best", Icon = "Star", IconSize = 28, Color = Common.Colors.Equip, TextSize = 17, Size = UDim2.fromOffset(160, 40), LayoutOrder = 2, Parent = toolbar,
		OnClick = function()
			if DataController:Request("EquipBestPets") then
				ctx.Controllers.SoundController:Play("Equip")
			end
		end,
	})
	deleteButton = Kit.Button({
		Text = "Multi Delete", Icon = "Trash", IconSize = 28, Color = "Red", TextSize = 17, Size = UDim2.fromOffset(170, 40), LayoutOrder = 3, Parent = toolbar,
		OnClick = function()
			if not deleteMode then
				deleteMode = true
				table.clear(marked)
				ctx.Controllers.NotificationController:Toast("Tap pets to select them, or press Select All", Theme.SubText, "Trash")
			elseif markedCount() == 0 then
				deleteMode = false
			else
				local list = {}
				local mutated = 0
				local data = DataController:Get()
				for uid in pairs(marked) do
					table.insert(list, uid)
					local owned = data and data.Pets[uid]
					if owned and owned.Mutation then
						mutated += 1
					end
				end
				local warning = if mutated > 0 then " Includes " .. mutated .. " MUTATED pet" .. (if mutated > 1 then "s" else "") .. "!" else ""
				Common.Confirm(ctx.Parent, "Delete " .. #list .. " pets?", "They'll be gone for good." .. warning .. " Favourited pets are never deleted.", "Delete", Common.Colors.Danger, function()
					if DataController:Request("DeletePets", list) then
						deleteMode = false
						table.clear(marked)
						updateDeleteButton()
					end
				end)
			end
			updateDeleteButton()
			refreshCards()
		end,
	})
	-- select mode: mark every pet that isn't equipped or favourited in one tap
	selectAllButton = Kit.Button({
		Text = "Select All", Icon = "Check", IconSize = 26, Color = "Orange", TextSize = 17, Size = UDim2.fromOffset(150, 40), LayoutOrder = 1, Visible = false, Parent = toolbar,
		OnClick = function()
			local data = DataController:Get()
			if not data then
				return
			end
			-- mutated pets are skipped too; tap them one by one to delete them
			local skipped = 0
			for uid, owned in pairs(data.Pets) do
				if owned.Mutation then
					skipped += if marked[uid] then 0 else 1
				elseif not owned.Fav and not table.find(data.EquippedPets, uid) then
					marked[uid] = true
				end
			end
			if skipped > 0 then
				ctx.Controllers.NotificationController:Toast(skipped .. " mutated pets skipped. Tap one to select it", Theme.Gold, "Sparkle")
			end
			refreshCards()
			updateDeleteButton()
		end,
	})
	clearButton = Kit.Button({
		Text = "Clear", Color = "Grey", TextSize = 17, Size = UDim2.fromOffset(100, 40), LayoutOrder = 2, Visible = false, Parent = toolbar,
		OnClick = function()
			table.clear(marked)
			refreshCards()
			updateDeleteButton()
		end,
	})
	updateDeleteButton()

	for _, key in ipairs({ "Pets", "EquippedPets", "__Stats" }) do
		DataController:OnChange(key, function()
			if window.Visible then
				refreshCards()
			end
		end)
	end

	return {
		Window = window,
		Close = close,
		OnOpen = function()
			refreshCards()
		end,
		OnClose = function()
			deleteMode = false
			table.clear(marked)
			updateDeleteButton()
		end,
	}
end

return Menu
