--[[
	Egg: opened from an egg stand's prompt. Shows every pet the egg can hatch
	with its chance (your Luck applied), the price, and Hatch x1 / x3 buttons.
	A strip under the grid lists the mutation odds (Config/Mutations, Luck applied).
	Closes itself if you walk away from the egg.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Pets = require(Shared.Config.Pets)
local TableUtil = require(Shared.Util.TableUtil)
local Format = require(Shared.Util.Format)
local Mutations = require(Shared.Config.Mutations)

local Menu = {}

function Menu.Build(ctx)
	local Kit, Theme, Common = ctx.Kit, ctx.Theme, ctx.Common
	local DataController = ctx.Controllers.DataController
	local window, content, close = Kit.Window({
		Name = "Egg", Title = "Egg", Icon = "Egg", Accent = "Gold", Size = UDim2.fromOffset(740, 512), Parent = ctx.Parent,
	})
	local titleLabel = window:FindFirstChild("Header"):FindFirstChild("Title") :: TextLabel?
	local grid = Common.Grid(content, { CellSize = UDim2.fromOffset(112, 132), Size = UDim2.new(1, 0, 1, -118) })
	-- mutation odds strip: one pill per mutation, "Golden x2" over "1/40" (Luck applied)
	local mutationRow = Kit.New("Frame", { Name = "Mutations", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 38), Position = UDim2.new(0, 0, 1, -112), Parent = content })
	Kit.New("UIGridLayout", {
		CellSize = UDim2.new(1 / #Mutations.List, -4, 1, 0), CellPadding = UDim2.fromOffset(4, 0),
		SortOrder = Enum.SortOrder.LayoutOrder, Parent = mutationRow,
	})
	local mutationLabels = {}
	for i, m in ipairs(Mutations.List) do
		local pill = Kit.New("Frame", { BackgroundColor3 = Theme.Ink, BackgroundTransparency = 0.25, LayoutOrder = i, Parent = mutationRow })
		Kit.Corner(8).Parent = pill
		Kit.Label({
			Text = m.Name .. " " .. Format.Mult(m.Mult), TextSize = 13, Scaled = true, MaxTextSize = 13, Color = m.Color, XAlign = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, -6, 0, 16), Position = UDim2.fromOffset(3, 3), StrokeThickness = 1.5, ZIndex = 2, Parent = pill,
		})
		mutationLabels[m.Id] = Kit.Label({
			Text = "", Font = Theme.FontNumber, TextSize = 12, Color = Theme.SubText, XAlign = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, -6, 0, 15), Position = UDim2.fromOffset(3, 20), StrokeThickness = 1.5, ZIndex = 2, Parent = pill,
		})
	end
	local bottom = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 64), Position = UDim2.new(0, 0, 1, -64), Parent = content })
	local infoTop = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -370, 0, 32), Parent = bottom })
	Kit.List(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center).Parent = infoTop
	local _, setPrice = Common.PriceTag(infoTop, "Coins", "", { Size = UDim2.new(0, 0, 1, 0), TextSize = 24, Align = Enum.HorizontalAlignment.Left, LayoutOrder = 1 })
	infoTop:FindFirstChild("Price").AutomaticSize = Enum.AutomaticSize.X
	Kit.Label({ Text = "each", TextSize = 18, Color = Theme.SubText, AutoX = true, Size = UDim2.new(0, 0, 1, 0), LayoutOrder = 2, StrokeThickness = 2, Parent = infoTop })
	local luckIcon = Kit.Icon(infoTop, "Clover", { Size = UDim2.fromOffset(28, 28), LayoutOrder = 3 })
	local luckText = Kit.Label({ Text = "", TextSize = 18, Color = Theme.Green, AutoX = true, Size = UDim2.new(0, 0, 1, 0), LayoutOrder = 4, StrokeThickness = 2, Parent = infoTop })
	local infoBottom = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -370, 0, 28), Position = UDim2.fromOffset(0, 34), Parent = bottom })
	Kit.List(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center).Parent = infoBottom
	Kit.Icon(infoBottom, "Inventory", { Size = UDim2.fromOffset(26, 26), LayoutOrder = 1 })
	local storageText = Kit.Label({ Text = "", TextSize = 16, AutoX = true, Size = UDim2.new(0, 0, 1, 0), LayoutOrder = 2, StrokeThickness = 2, Parent = infoBottom })
	Kit.Label({ Text = "  Tap a pet to auto-delete it", TextSize = 14, Color = Theme.Muted, AutoX = true, Size = UDim2.new(0, 0, 1, 0), LayoutOrder = 3, StrokeThickness = 1.5, Parent = infoBottom })

	local eggId: string? = nil
	local open = false

	local function hatch(count: number)
		if not eggId then
			return
		end
		if DataController:Request("Hatch", eggId, count) then
			ctx.Close()
		end
	end
	local hatch1 = Kit.Button({ Text = "Hatch x1", Icon = "Egg", IconSize = 34, Color = "Green", TextSize = 22, Size = UDim2.fromOffset(176, 60), Position = UDim2.new(1, -180, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Parent = bottom, OnClick = function()
		hatch(1)
	end })
	local hatch3 = Kit.Button({ Text = "Hatch x3", Icon = "Egg", IconSize = 34, Color = "Purple", TextSize = 22, Size = UDim2.fromOffset(176, 60), Position = UDim2.new(1, 0, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Parent = bottom, OnClick = function()
		hatch(3)
	end })

	-- price line + hatch buttons (cheap; runs on every currency change)
	local function refreshButtons()
		local data = DataController:Get()
		local stats = DataController:GetStats()
		local egg = eggId and Pets.EggsById[eggId]
		if not data or not stats or not egg then
			return
		end
		local affordable1 = Common.CanAfford(data, egg.Currency, egg.Cost)
		local affordable3 = Common.CanAfford(data, egg.Currency, egg.Cost * 3)
		local hasTriple = (data.Utility.triple_hatch or 0) > 0
		setPrice(Common.Price(egg.Currency, egg.Cost), if affordable1 then Common.CurrencyColor(egg.Currency) else Theme.Red, egg.Currency)
		luckIcon.Visible = stats.Luck > 0
		luckText.Text = if stats.Luck > 0 then "Luck " .. Format.Percent(1 + stats.Luck) else ""
		storageText.Text = string.format("%d/%d pets", TableUtil.Count(data.Pets), stats.PetStorage)
		Kit.Api(hatch1).SetEnabled(affordable1)
		Kit.Api(hatch3).SetEnabled(hasTriple and affordable3)
		Kit.Api(hatch3).SetText(if hasTriple then "Hatch x3" else "x3 in Shop")
		Kit.Api(hatch3).SetIcon(if hasTriple then "Egg" else "Lock")
	end

	-- chance cards (viewports; only when pets or luck change)
	local function refresh()
		local data = DataController:Get()
		local stats = DataController:GetStats()
		local egg = eggId and Pets.EggsById[eggId]
		if not data or not stats or not egg then
			return
		end
		if titleLabel then
			titleLabel.Text = egg.Name
		end
		for _, m in ipairs(Mutations.List) do
			local oneIn = Mutations.OneIn(m.Id, stats.Luck) or m.OneIn
			mutationLabels[m.Id].Text = Common.OddsText(oneIn, true)
		end
		Common.ClearGrid(grid)
		for i, entry in ipairs(Pets.Chances(egg, stats.Luck)) do
			local pet = entry.Pet
			local card = Common.Card({
				Title = pet.Name, Rarity = pet.Rarity, Model = Common.PetModel(pet.Id), Zoom = 1.15, LayoutOrder = i, Parent = grid,
				Sub = Common.OddsText(math.max(1, math.floor(100 / entry.Chance + 0.5)), true),
				-- click a pet to toggle auto-delete for it
				OnClick = function()
					local current = DataController:Get()
					local on = not (current and current.AutoDelete[pet.Id])
					local ok, message = DataController:Request("SetAutoDelete", pet.Id, on)
					ctx.Controllers.NotificationController:Toast(tostring(message), if ok then Theme.Text else Theme.Red, if ok and on then "Trash" else nil)
				end,
			})
			if data.AutoDelete[pet.Id] then
				card.SetBadge("🗑️")
				card.SetLocked("AUTO-DELETE")
			end
			local owned = false
			for _, p in pairs(data.Pets) do
				if p.Id == pet.Id then
					owned = true
					break
				end
			end
			if not owned then
				card.SetBadge2("❔")
			end
		end
		refreshButtons()
	end

	for _, key in ipairs({ "Pets", "__Stats", "AutoDelete" }) do
		DataController:OnChange(key, function()
			if window.Visible then
				refresh()
			end
		end)
	end
	for _, key in ipairs({ "Coins", "Shards", "Utility" }) do
		DataController:OnChange(key, function()
			if window.Visible then
				refreshButtons()
			end
		end)
	end

	return {
		Window = window,
		Close = close,
		OnOpen = function(id)
			eggId = id
			open = true
			refresh()
			-- auto-close when the player walks away from the egg
			local egg = eggId and Pets.EggsById[eggId]
			if not egg then
				return
			end
			local eggPos = Pets.EggPosition(egg)
			while open and window.Visible do
				task.wait(0.4)
				local character = Players.LocalPlayer.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if open and root and (root.Position - eggPos).Magnitude > 45 then
					ctx.Close()
					break
				end
			end
		end,
		OnClose = function()
			open = false
		end,
	}
end

return Menu
