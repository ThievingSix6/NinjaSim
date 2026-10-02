--[[
	Mutate: the Mutation Machine's menu (opened at the machine by the village spawn).
	Pick one of your pets or hats, see its current mutation and the machine's odds,
	then roll for Coins, or roll lucky for Spirit Shards (the rare results three times
	as likely). Every roll replaces the mutation, so a good one can be lost: rolling a
	pet or hat that already has Rainbow or better asks first. Secret only comes from here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Pets = require(Shared.Config.Pets)
local Hats = require(Shared.Config.Hats)
local Rarity = require(Shared.Config.Rarity)
local Mutations = require(Shared.Config.Mutations)
local Format = require(Shared.Util.Format)
local HatBuilder = require(Shared.Visuals.HatBuilder)

local Menu = {}

function Menu.Build(ctx)
	local Kit, Theme, Common = ctx.Kit, ctx.Theme, ctx.Common
	local C = ctx.Controllers
	local DataController = C.DataController

	local window, content, close = Kit.Window({
		Name = "Mutate", Title = "Mutation Machine", Icon = "Potion", Accent = "Pink", Size = UDim2.fromOffset(940, 580), Parent = ctx.Parent,
	})
	local kind = "Pet"
	local selected: string? = nil
	local busy = false

	local left, right = Common.Split(content, 52, 330)
	local grid = Common.Grid(left, { CellSize = UDim2.fromOffset(108, 128) })
	local refresh

	Kit.Tabs(content, { { Name = "Pets", Icon = "Pets" }, { Name = "Hats", Icon = "Crown" } }, function(name)
		kind = if name == "Hats" then "Hat" else "Pet"
		selected = nil
		refresh()
	end, "Pink")

	-- right: the chosen item, its mutation, the odds and the roll buttons
	local panel = Kit.Panel({ Size = UDim2.fromScale(1, 1), Color = Theme.Panel, Radius = 14, Parent = right })
	local preview = Kit.New("Frame", {
		Name = "Preview", BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, -20, 0, 150), Position = UDim2.fromOffset(10, 10), ClipsDescendants = true, ZIndex = 2, Parent = panel,
	})
	Kit.Corner(12).Parent = preview
	Kit.Stroke(Theme.Ink, 3).Parent = preview
	Kit.Paint(preview, "Dark")
	local title = Kit.Label({ Text = "Pick a pet or a hat", TextSize = 20, XAlign = Enum.TextXAlignment.Center, Wrapped = true, Size = UDim2.new(1, -16, 0, 44), Position = UDim2.fromOffset(8, 164), StrokeThickness = 2.5, Parent = panel })
	local current = Kit.Label({ Text = "", TextSize = 16, Color = Theme.SubText, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, -16, 0, 20), Position = UDim2.fromOffset(8, 208), StrokeThickness = 2, Parent = panel })
	local odds = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -20, 0, 156), Position = UDim2.fromOffset(10, 232), Parent = panel })
	Kit.New("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 16), CellPadding = UDim2.fromOffset(8, 1), SortOrder = Enum.SortOrder.LayoutOrder, Parent = odds })
	local oddsRows = {}
	for i, w in ipairs(Mutations.Machine.Weights) do
		local m = Mutations.Get(w.Id) :: any
		oddsRows[w.Id] = Kit.Label({ Text = "", Font = Theme.FontBody, TextSize = 13, Color = m.Color, LayoutOrder = i, Size = UDim2.fromScale(1, 1), StrokeThickness = 1.5, Parent = odds })
	end
	local function roll(lucky: boolean)
		if busy or not selected then
			return
		end
		busy = true
		local ok, result = DataController:Request("MutateItem", kind, selected, lucky)
		if ok and type(result) == "table" then
			local m = Mutations.Get(result.Mutation) :: any
			C.SoundController:Play(if m.Shout then "TierUp" else "EggHatch")
			C.EffectsController:CharacterBurst(m.Color, m.Shout)
			C.NotificationController:Callout(m.Name .. "!", Format.Mult(if kind == "Pet" then m.Mult else m.HatMult) .. (if kind == "Pet" then " pet stats" else " hat stats"), m.Color, "Potion", 3)
		end
		task.delay(0.4, function()
			busy = false
		end)
	end
	-- the risky case: rolling away a rare mutation asks first
	local function guarded(lucky: boolean)
		local data = DataController:Get()
		local item = data and selected and (if kind == "Pet" then data.Pets[selected] else data.Hats[selected])
		local id = item and (if kind == "Pet" then item.Mutation else item.M)
		local m = Mutations.Get(id)
		if m and m.Shout then
			Common.Confirm(window, "Reroll " .. m.Name .. "?", "This " .. m.Name .. " mutation will be replaced by a new roll, which can be worse.", "Roll", "Pink", function()
				roll(lucky)
			end)
		else
			roll(lucky)
		end
	end
	local rollButton = Kit.Button({
		Text = "Roll", Icon = "Coin", Color = "Green", TextSize = 20, IconSize = 28, Size = UDim2.new(1, -20, 0, 50),
		Position = UDim2.new(0, 10, 1, -114), Parent = panel,
		OnClick = function()
			guarded(false)
		end,
	})
	local luckyButton = Kit.Button({
		Text = "Lucky Roll", Icon = "Shard", Color = "Purple", TextSize = 20, IconSize = 28, Size = UDim2.new(1, -20, 0, 50),
		Position = UDim2.new(0, 10, 1, -58), Parent = panel,
		OnClick = function()
			guarded(true)
		end,
	})

	local viewport: Instance? = nil
	local function showItem()
		local data = DataController:Get()
		if viewport then
			viewport:Destroy()
			viewport = nil
		end
		local item = data and selected and (if kind == "Pet" then data.Pets[selected] else data.Hats[selected])
		if not data or not item then
			title.Text = if kind == "Pet" then "Pick a pet" else "Pick a hat"
			current.Text = "Every roll gives a mutation. Secret only comes from this machine."
			Kit.Api(rollButton).SetEnabled(false)
			Kit.Api(luckyButton).SetEnabled(false)
			Kit.Api(rollButton).SetText("Roll")
			return
		end
		local mutationId = if kind == "Pet" then item.Mutation else item.M
		local m = Mutations.Get(mutationId)
		local model, step
		if kind == "Pet" then
			local def = Pets.ById[item.Id]
			title.Text = Pets.DisplayName(def, mutationId)
			model = Common.PetModel(item.Id, mutationId)
			step = Rarity.Index(def.Rarity)
		else
			title.Text = Hats.Name(item)
			model = HatBuilder.Build(item)
			step = Hats.Rarity(item.R).Index
		end
		if model then
			viewport = Kit.Viewport(preview, model, { Size = UDim2.fromScale(1, 1), Zoom = 1.1, ZIndex = 3, Spin = true })
		end
		current.Text = if m then "Now: " .. m.Name .. "  " .. Format.Mult(if kind == "Pet" then m.Mult else m.HatMult) else "Now: no mutation"
		current.TextColor3 = if m then m.Color else Theme.SubText
		local price = Mutations.MachinePrice(data.Level, step)
		local rollApi, luckyApi = Kit.Api(rollButton), Kit.Api(luckyButton)
		rollApi.SetText("Roll  " .. Format.Abbrev(price))
		rollApi.SetEnabled(data.Coins >= price)
		luckyApi.SetText("Lucky Roll  " .. Mutations.Machine.LuckyShards)
		luckyApi.SetEnabled(data.Shards >= Mutations.Machine.LuckyShards)
	end

	local function showOdds()
		local stats = DataController:GetStats()
		local luck = stats and stats.Luck or 0
		local normal, lucky = Mutations.MachineOdds(false, luck), Mutations.MachineOdds(true, luck)
		for id, label in pairs(oddsRows) do
			local function pct(v: number): string
				return if v < 0.01 then string.format("%.2f%%", v * 100) else string.format("%.1f%%", v * 100)
			end
			label.Text = string.format("%s  %s  (%s)", Mutations.Get(id).Name, pct(normal[id]), pct(lucky[id]))
		end
	end

	local cards = {}
	function refresh()
		local data = DataController:Get()
		if not data then
			return
		end
		Common.ClearGrid(grid)
		table.clear(cards)
		local list = {}
		if kind == "Pet" then
			for uid, owned in pairs(data.Pets) do
				local def = Pets.ById[owned.Id]
				if def then
					table.insert(list, { Uid = uid, Order = -Rarity.Index(def.Rarity) * 100 - (Mutations.Get(owned.Mutation) and Mutations.Get(owned.Mutation).Order or 0) })
				end
			end
		else
			for uid, hat in pairs(data.Hats) do
				if Hats.Valid(hat) then
					table.insert(list, { Uid = uid, Order = -Hats.Rarity(hat.R).Index * 100 - (Mutations.Get(hat.M) and Mutations.Get(hat.M).Order or 0) })
				end
			end
		end
		table.sort(list, function(a, b)
			return if a.Order == b.Order then a.Uid < b.Uid else a.Order < b.Order
		end)
		for i, entry in ipairs(list) do
			local uid = entry.Uid
			local props
			if kind == "Pet" then
				local owned = data.Pets[uid]
				local def = Pets.ById[owned.Id]
				local m = Mutations.Get(owned.Mutation)
				props = {
					Title = Pets.DisplayName(def, owned.Mutation), Rarity = def.Rarity, Model = Common.PetModel(owned.Id, owned.Mutation),
					Zoom = Common.PetZoom(1.15, owned.Mutation), Sub = if m then m.Name else def.Rarity, SubColor = if m then m.Color else Rarity.Color(def.Rarity),
				}
			else
				local hat = data.Hats[uid]
				local rarity = Hats.Rarity(hat.R)
				local m = Mutations.Get(hat.M)
				props = {
					Title = Hats.Name(hat), Paint = rarity.Paint, Model = HatBuilder.Build(hat), Zoom = 1.05,
					Sub = if m then m.Name else rarity.Name, SubColor = if m then m.Color else rarity.Color,
				}
			end
			props.Parent = grid
			props.LayoutOrder = i
			props.OnClick = function()
				selected = uid
				for id, card in pairs(cards) do
					card.SetSelected(id == uid)
				end
				showItem()
			end
			cards[uid] = Common.Card(props)
			cards[uid].SetSelected(uid == selected)
		end
		if #list == 0 then
			Common.EmptyNote(grid, if kind == "Pet" then "No pets yet. Hatch some at an egg!" else "No hats yet. Enemies drop them (1% per kill).")
		end
		showItem()
		showOdds()
	end

	for _, key in ipairs({ "Pets", "Hats", "Coins", "Shards" }) do
		DataController:OnChange(key, function()
			if window.Visible then
				refresh()
			end
		end)
	end

	return { Window = window, Close = close, OnOpen = refresh }
end

return Menu
