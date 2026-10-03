--[[
	Inventory: the Diablo II style "ragdoll" inventory. Keyboard shortcut: I.

	Left, the paper doll: your ninja with the gear slots around it. Head (your hat,
	opens Hats), Weapon (your katana, opens the Armory), Body (your suit, opens Suits)
	and the pet slots (open Pets), with what your charm grid adds up to underneath.

	Middle, the charm grid (Config/Charms, 10 x 4). Only charms in the grid count.
	Click a charm to pick it up, then click a cell to put it down there (its top cell
	goes where you click; the cells it would cover light green, or red when it doesn't
	fit). Below it, the stash: charms you own that sit outside the grid.

	Right, the picked charm's details, with To Stash / Place, Lock and Salvage.

	Hired ninjas (Config/Hires) each have their own paper doll and charm grid: the
	arrows by the doll's title switch between you and them. Their charms power them,
	and half of the stats go to you while that ninja is the one fighting.
	Open with a hire's id (MenuManager:Open("Inventory", id)) to start on their doll.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Charms = require(Shared.Config.Charms)
local Hats = require(Shared.Config.Hats)
local Skills = require(Shared.Config.Skills)
local Katanas = require(Shared.Config.Katanas)
local Pets = require(Shared.Config.Pets)
local Mastery = require(Shared.Config.Mastery)
local Mutations = require(Shared.Config.Mutations)
local HatBuilder = require(Shared.Visuals.HatBuilder)
local CharmBuilder = require(Shared.Visuals.CharmBuilder)
local EnemyBuilder = require(Shared.Visuals.EnemyBuilder)
local Hires = require(Shared.Config.Hires)
local Format = require(Shared.Util.Format)

local Menu = {}

local CELL = 48
local GAP = 3
local AFFIX = Color3.fromRGB(130, 165, 255) -- Diablo's magic blue for affix lines
local rgb = Color3.fromRGB

function Menu.Build(ctx)
	local Kit, Theme, Common = ctx.Kit, ctx.Theme, ctx.Common
	local C = ctx.Controllers
	local DataController = C.DataController

	local window, content, close = Kit.Window({
		Name = "Inventory", Title = "Inventory", Icon = "Inventory", Accent = "Blue", Size = UDim2.fromOffset(1100, 640), Parent = ctx.Parent,
	})

	local selected: string? = nil
	local owner: string? = nil -- whose doll and grid: nil = yours, else a hire id
	local hoverCell: Vector2? = nil
	local refresh, paintHover

	-- a label that grows to fit its wrapped text
	local function tall(props)
		local label = Kit.Label(props)
		label.AutomaticSize = Enum.AutomaticSize.Y
		return label
	end

	local function act(action: string, ...)
		local ok, message = DataController:Request(action, ...)
		if not ok and type(message) == "string" then
			C.NotificationController:Toast(message, Theme.Red, "Lock")
		end
		return ok, message
	end

	-- ===== left: the paper doll =====
	local doll = Kit.Panel({ Size = UDim2.new(0, 290, 1, 0), Color = Theme.Panel, Radius = 14, Parent = content })
	Kit.Paint(doll, { rgb(46, 40, 58), rgb(22, 18, 30) })
	local dollTitle = Kit.Label({ Text = "Equipment", TextSize = 18, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, -70, 0, 26), Position = UDim2.fromOffset(35, 6), StrokeThickness = 2, Scaled = true, MaxTextSize = 18, Parent = doll })
	-- you and your hired ninjas, in order
	local function owners(): { string | false }
		local data = DataController:Get()
		local list: { string | false } = { false }
		for _, def in ipairs(Hires.List) do
			if data and type(data.Hires) == "table" and data.Hires[def.Id] then
				table.insert(list, def.Id)
			end
		end
		return list
	end
	local showFigure
	local function cycle(step: number)
		local list = owners()
		local index = table.find(list, owner or false) or 1
		local nextOwner = list[((index - 1 + step) % #list) + 1]
		owner = if nextOwner then nextOwner :: string else nil
		selected = nil
		C.SoundController:Play("Click")
		showFigure()
		refresh()
	end
	local prevOwner = Kit.Button({ Text = "<", Color = "Dark", TextSize = 16, Size = UDim2.fromOffset(28, 26), Position = UDim2.fromOffset(6, 6), ZIndex = 4, Parent = doll,
		OnClick = function()
			cycle(-1)
		end })
	local nextOwnerButton = Kit.Button({ Text = ">", Color = "Dark", TextSize = 16, Size = UDim2.new(0, 28, 0, 26), Position = UDim2.new(1, -34, 0, 6), ZIndex = 4, Parent = doll,
		OnClick = function()
			cycle(1)
		end })
	local figure = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(150, 240), Position = UDim2.new(0.5, 0, 0, 40), AnchorPoint = Vector2.new(0.5, 0), Parent = doll })

	local slots = {}
	local function slot(name: string, label: string, size: Vector2, position: UDim2, menu: string)
		local button = Kit.New("TextButton", {
			Name = name, Text = "", AutoButtonColor = true, BackgroundColor3 = rgb(16, 14, 22), Size = UDim2.fromOffset(size.X, size.Y),
			Position = position, ZIndex = 3, Parent = doll,
		})
		Kit.Corner(8).Parent = button
		local stroke = Kit.Stroke(rgb(150, 120, 70), 2.5)
		stroke.Parent = button
		local caption = Kit.Label({
			Text = label, Font = Theme.FontBody, TextSize = 11, Color = Theme.Muted, XAlign = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -15), ZIndex = 6, Stroke = false, Parent = button,
		})
		button.MouseButton1Click:Connect(function()
			C.MenuManager:Open(menu)
		end)
		slots[name] = { Button = button, Stroke = stroke, Caption = caption, Label = label }
		return button
	end
	slot("Head", "Head", Vector2.new(72, 72), UDim2.new(0.5, -36, 0, 34), "Hats")
	slot("Weapon", "Weapon", Vector2.new(66, 132), UDim2.fromOffset(12, 96), "Armory")
	slot("Body", "Body", Vector2.new(66, 132), UDim2.new(1, -78, 0, 96), "Suits")
	local petRow = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -24, 0, 64), Position = UDim2.fromOffset(12, 290), Parent = doll })
	Kit.List(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center).Parent = petRow
	-- a hired ninja's fighting stats, where your pets go on your doll
	local hireInfo = Kit.Label({ Text = "", Font = Theme.FontBody, TextSize = 13, Color = Theme.Text, Wrapped = true, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, -24, 0, 64), Position = UDim2.fromOffset(12, 290), Visible = false, StrokeThickness = 1.5, Parent = doll })
	local summaryTitle = Kit.Label({ Text = "From your charms", TextSize = 16, Color = Theme.Gold, Size = UDim2.new(1, -24, 0, 20), Position = UDim2.fromOffset(12, 362), StrokeThickness = 2, Scaled = true, MaxTextSize = 16, Parent = doll })
	local summary = Kit.New("ScrollingFrame", {
		BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, -24, 1, -392), Position = UDim2.fromOffset(12, 386),
		ScrollBarThickness = 4, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = doll,
	})
	Kit.List(Enum.FillDirection.Vertical, 2).Parent = summary

	local function clearViews(frame: Instance)
		for _, c in ipairs(frame:GetChildren()) do
			if c:IsA("ViewportFrame") or c.Name == "Icon" or c.Name == "Swatch" then
				c:Destroy()
			end
		end
	end

	function showFigure()
		clearViews(figure)
		local hire = Hires.Get(owner)
		if hire then
			local ok, model = pcall(EnemyBuilder.Build, Hires.RigDef(hire), 1)
			if ok and model then
				model:SetAttribute("ViewRotation", CFrame.Angles(0, math.pi, 0))
				Kit.Viewport(figure, model, { Size = UDim2.fromScale(1, 1), Zoom = 1.05, ZIndex = 2 })
			end
			return
		end
		local character = Players.LocalPlayer.Character
		local clone
		if character then
			local ok = pcall(function()
				local was = character.Archivable
				character.Archivable = true
				clone = character:Clone()
				character.Archivable = was
			end)
			if not ok then
				clone = nil
			end
		end
		if clone then
			for _, d in ipairs(clone:GetDescendants()) do
				if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Sound") then
					d:Destroy()
				end
			end
			clone:SetAttribute("ViewRotation", CFrame.Angles(0, math.pi, 0))
			Kit.Viewport(figure, clone, { Size = UDim2.fromScale(1, 1), Zoom = 1.05, ZIndex = 2 })
		else
			Kit.Icon(figure, "Shuriken", { Size = UDim2.fromOffset(110, 110), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 2 })
		end
	end

	local function showSlots(data)
		local hire = Hires.Get(owner)
		for _, s in pairs(slots) do
			s.Button.Visible = hire == nil
		end
		petRow.Visible = hire == nil
		hireInfo.Visible = hire ~= nil
		dollTitle.Text = if hire then hire.Name else "Equipment"
		local many = #owners() > 1
		prevOwner.Visible, nextOwnerButton.Visible = many, many
		if hire then
			local stats = DataController:GetStats()
			local hs = stats and Hires.Stats(hire, stats, Charms.Bonus(data, hire.Id))
			local fighting = data.ActiveHire == hire.Id
			hireInfo.Text = if hs
				then string.format("%s  ·  %s Dmg  ·  %s HP  ·  %d%% Crit\n%s: %s\n%s", hire.Role, Format.Abbrev(hs.Damage), Format.Abbrev(hs.MaxHealth), math.floor(hs.Crit * 100), hire.Skill.Name, hire.Skill.Text, if fighting then "Fighting beside you" else "Resting (pick them in the Hire menu)")
				else hire.Role
			return
		end
		-- head: the worn hat
		local head = slots.Head
		clearViews(head.Button)
		local hat = Hats.Equipped(data)
		if hat then
			local model = HatBuilder.Build(hat)
			if model then
				Kit.Viewport(head.Button, model, { Size = UDim2.new(1, -6, 1, -14), Zoom = 1.1, ZIndex = 4 })
			end
			head.Stroke.Color = Hats.Rarity(hat.R).Color
		else
			head.Stroke.Color = rgb(150, 120, 70)
		end
		-- weapon: the katana
		local weapon = slots.Weapon
		clearViews(weapon.Button)
		local katana = Katanas.ById[data.EquippedKatana]
		local model = katana and Common.KatanaModel(katana.Id)
		if model then
			Kit.Viewport(weapon.Button, model, { Size = UDim2.new(1, -6, 1, -14), Zoom = 1.0, ZIndex = 4 })
		end
		-- body: the worn suit's colours
		local body = slots.Body
		clearViews(body.Button)
		local suit = Mastery.WornTier(data)
		local swatch = Kit.Panel({ Name = "Swatch", Size = UDim2.new(1, -14, 1, -26), Position = UDim2.fromOffset(7, 6), Paint = { suit.Outfit.Trim, suit.Outfit.Primary }, StrokeThickness = 2, Radius = 6, ZIndex = 4, Parent = body.Button })
		Kit.Icon(swatch, "Star", { Size = UDim2.fromOffset(30, 30), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 5 })
		body.Caption.Text = suit.Name
		body.Stroke.Color = suit.Color
		-- pets
		for _, c in ipairs(petRow:GetChildren()) do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local stats = DataController:GetStats()
		local count = math.clamp(stats and stats.PetSlots or 3, 1, 4)
		for i = 1, count do
			local uid = data.EquippedPets[i]
			local owned = uid and data.Pets[uid]
			local cell = Kit.New("TextButton", {
				Text = "", AutoButtonColor = true, BackgroundColor3 = rgb(16, 14, 22), Size = UDim2.fromOffset(60, 60), LayoutOrder = i, Parent = petRow,
			})
			Kit.Corner(8).Parent = cell
			local stroke = Kit.Stroke(rgb(150, 120, 70), 2.5)
			stroke.Parent = cell
			if owned and Pets.ById[owned.Id] then
				local m = Mutations.Get(owned.Mutation)
				stroke.Color = if m then m.Color else ctx.Theme.Gold
				local petModel = Common.PetModel(owned.Id, owned.Mutation)
				if petModel then
					Kit.Viewport(cell, petModel, { Size = UDim2.fromScale(1, 1), Zoom = Common.PetZoom(1.2, owned.Mutation), ZIndex = 3 })
				end
			else
				Kit.Label({ Text = "Pet", Font = Theme.FontBody, TextSize = 12, Color = Theme.Muted, XAlign = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Stroke = false, Parent = cell })
			end
			cell.MouseButton1Click:Connect(function()
				C.MenuManager:Open("Pets")
			end)
		end
	end

	local function showSummary(data)
		for _, c in ipairs(summary:GetChildren()) do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local b = Charms.Bonus(data, owner)
		local lines = {}
		summaryTitle.Text = if owner then "From its charms (half to you)" else "From your charms"
		if b.AllSkills > 0 then
			table.insert(lines, { string.format("+%d to All Skills", b.AllSkills), Theme.Gold })
		end
		local skillIds = {}
		for id in pairs(b.Skills) do
			table.insert(skillIds, id)
		end
		table.sort(skillIds)
		for _, id in ipairs(skillIds) do
			table.insert(lines, { string.format("+%d to %s", b.Skills[id], Skills.Get(id).Name), Theme.Gold })
		end
		for _, affix in ipairs(Hats.Affixes) do
			local v = b[affix.Id]
			if type(v) == "number" and v ~= 0 then
				table.insert(lines, { Hats.StatText(affix.Id, v), AFFIX })
			end
		end
		if b.Hexfire > 0 then
			table.insert(lines, { string.format("%d%% chance on attack to cast Hexfire", b.Hexfire * 100), Charms.Hexfire.Color })
		end
		if owner then
			-- skills and the torch only work for you
			for i = #lines, 1, -1 do
				if lines[i][2] == Theme.Gold then
					table.remove(lines, i)
				end
			end
		else
			local hire = Hires.Get(data.ActiveHire)
			if hire and data.Hires and data.Hires[hire.Id] and next(Charms.Active(data, hire.Id)) then
				table.insert(lines, { string.format("+ half the stats of %s's charms", hire.Name), Theme.Green })
			end
		end
		if #lines == 0 then
			table.insert(lines, { if owner then "Charms here power this ninja, and half their stats go to you while they fight." else "Put charms in the grid. Enemies drop them (very rarely).", Theme.Muted })
		end
		for i, line in ipairs(lines) do
			tall({
				Text = line[1], Font = Theme.FontBody, TextSize = 13, Color = line[2], Wrapped = true, Size = UDim2.new(1, -6, 0, 0),
				LayoutOrder = i, Stroke = false, Parent = summary,
			})
		end
	end

	-- ===== middle: the charm grid =====
	local gridW = Charms.Cols * CELL + (Charms.Cols - 1) * GAP
	local gridH = Charms.Rows * CELL + (Charms.Rows - 1) * GAP
	local middle = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0, gridW + 20, 1, 0), Position = UDim2.fromOffset(302, 0), Parent = content })
	local gridTitle = Kit.Label({ Text = "Charm Grid", TextSize = 18, Size = UDim2.new(1, 0, 0, 24), StrokeThickness = 2, Parent = middle })
	local countLabel = Kit.Label({ Text = "", Font = Theme.FontNumber, TextSize = 15, Color = Theme.SubText, XAlign = Enum.TextXAlignment.Right, Size = UDim2.new(1, 0, 0, 24), StrokeThickness = 1.5, Parent = middle })
	local gridPanel = Kit.Panel({ Size = UDim2.fromOffset(gridW + 20, gridH + 20), Position = UDim2.fromOffset(0, 28), Radius = 10, Parent = middle })
	Kit.Paint(gridPanel, { rgb(34, 30, 42), rgb(18, 16, 24) })
	local board = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(gridW, gridH), Position = UDim2.fromOffset(10, 10), Parent = gridPanel })
	local cells: { [number]: Frame } = {}
	local tiles = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = board })

	local function cellPos(x: number, y: number): UDim2
		return UDim2.fromOffset((x - 1) * (CELL + GAP), (y - 1) * (CELL + GAP))
	end
	local function tileSize(charm): UDim2
		local size = Charms.Size(charm)
		return UDim2.fromOffset(size.W * CELL + (size.W - 1) * GAP, size.H * CELL + (size.H - 1) * GAP)
	end

	for y = 1, Charms.Rows do
		for x = 1, Charms.Cols do
			local cell = Kit.New("TextButton", {
				Name = string.format("Cell%d_%d", x, y), Text = "", AutoButtonColor = false, BackgroundColor3 = rgb(10, 9, 14), BackgroundTransparency = 0.1,
				Size = UDim2.fromOffset(CELL, CELL), Position = cellPos(x, y), ZIndex = 2, Parent = board,
			})
			Kit.Corner(4).Parent = cell
			Kit.Stroke(rgb(70, 62, 84), 1).Parent = cell
			cells[(y - 1) * Charms.Cols + x] = cell
			cell.MouseEnter:Connect(function()
				hoverCell = Vector2.new(x, y)
				paintHover()
			end)
			cell.SelectionGained:Connect(function()
				hoverCell = Vector2.new(x, y)
				paintHover()
			end)
			cell.MouseLeave:Connect(function()
				if hoverCell and hoverCell.X == x and hoverCell.Y == y then
					hoverCell = nil
					paintHover()
				end
			end)
			cell.MouseButton1Click:Connect(function()
				if selected then
					local uid = selected
					if act("PlaceCharm", uid, x, y, owner) then
						C.SoundController:Play("Equip")
					end
				end
			end)
		end
	end

	-- the selected charm's footprint under the cursor: green fits, red doesn't
	function paintHover()
		for _, cell in pairs(cells) do
			cell.BackgroundColor3 = rgb(10, 9, 14)
		end
		local data = DataController:Get()
		if not data or not selected or not hoverCell or not data.Charms[selected] then
			return
		end
		local charm = data.Charms[selected]
		local fits = Charms.Fits(data, selected, hoverCell.X, hoverCell.Y, owner)
		local size = Charms.Size(charm)
		for dx = 0, size.W - 1 do
			for dy = 0, size.H - 1 do
				local x, y = hoverCell.X + dx, hoverCell.Y + dy
				if x <= Charms.Cols and y <= Charms.Rows then
					cells[(y - 1) * Charms.Cols + x].BackgroundColor3 = if fits then rgb(40, 150, 70) else rgb(170, 40, 50)
				end
			end
		end
	end

	-- one charm drawn at its size: rarity colours, its icon, "+N" for skill charms
	local function charmTile(parent: Instance, uid: string, charm, size: UDim2, position: UDim2?, z: number)
		local rarity = Charms.Rarity(charm.R)
		local tile = Kit.New("TextButton", {
			Name = "Charm" .. uid, Text = "", AutoButtonColor = true, Size = size, Position = position or UDim2.new(), ZIndex = z, Parent = parent,
		})
		Kit.Paint(tile, rarity.Paint)
		Kit.Corner(6).Parent = tile
		local stroke = Kit.Stroke(if selected == uid then Theme.White else Theme.Ink, if selected == uid then 3 else 2)
		stroke.Parent = tile
		local icon = Kit.Icon(tile, Charms.Icon(charm), {
			Size = UDim2.fromOffset(34, 34), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = z + 1,
		})
		local skill = charm.S and Skills.Get(charm.S.K)
		if icon:IsA("ImageLabel") and skill then
			icon.ImageColor3 = skill.Color:Lerp(Color3.new(1, 1, 1), 0.3)
		end
		if charm.S then
			Kit.Label({
				Text = "+" .. charm.S.N, Font = Theme.FontNumber, TextSize = 14, Color = Theme.Gold, XAlign = Enum.TextXAlignment.Right,
				Size = UDim2.new(1, -4, 0, 16), Position = UDim2.fromOffset(0, 2), ZIndex = z + 2, StrokeThickness = 2, Parent = tile,
			})
		end
		if charm.Lock then
			Kit.Icon(tile, "Lock", { Size = UDim2.fromOffset(14, 14), Position = UDim2.new(0, 3, 1, -17), ZIndex = z + 2 })
		end
		tile.MouseButton1Click:Connect(function()
			selected = if selected == uid then nil else uid
			C.SoundController:Play("Click")
			refresh()
		end)
		return tile
	end

	-- ===== the stash, under the grid =====
	local stashTitle = Kit.Label({ Text = "Stash", TextSize = 16, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, gridH + 56), StrokeThickness = 2, Parent = middle })
	Kit.Label({
		Text = "Charms out here don't count. Pick one, then click a grid cell.", Font = Theme.FontBody, TextSize = 13, Color = Theme.SubText,
		XAlign = Enum.TextXAlignment.Right, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, gridH + 56), Stroke = false, Parent = middle,
	})
	local stash = Common.Grid(middle, { CellSize = UDim2.fromOffset(CELL, CELL * 2 + GAP), Gap = 6, Size = UDim2.new(1, 0, 1, -(gridH + 82)), Position = UDim2.fromOffset(0, gridH + 82) })

	-- ===== right: details of the picked charm =====
	local detail = Kit.Panel({ Size = UDim2.new(1, -(302 + gridW + 20 + 12), 1, 0), Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0), Color = Theme.Panel, Radius = 14, Parent = content })
	Kit.Paint(detail, { rgb(30, 26, 38), rgb(14, 12, 20) })
	local preview = Kit.New("Frame", { BackgroundColor3 = rgb(8, 8, 12), Size = UDim2.new(1, -20, 0, 130), Position = UDim2.fromOffset(10, 10), ClipsDescendants = true, ZIndex = 2, Parent = detail })
	Kit.Corner(10).Parent = preview
	Kit.Stroke(Theme.Ink, 2.5).Parent = preview
	local nameLabel = Kit.Label({ Text = "", TextSize = 17, Wrapped = true, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, -16, 0, 42), Position = UDim2.fromOffset(8, 144), StrokeThickness = 2, Parent = detail })
	local kindLabel = Kit.Label({ Text = "", Font = Theme.FontBody, TextSize = 13, Color = Theme.SubText, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(8, 186), Stroke = false, Parent = detail })
	local lineBox = Kit.New("ScrollingFrame", {
		BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, -16, 1, -330), Position = UDim2.fromOffset(8, 210),
		ScrollBarThickness = 4, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = detail,
	})
	Kit.List(Enum.FillDirection.Vertical, 3).Parent = lineBox
	local stateLabel = Kit.Label({ Text = "", TextSize = 14, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, -16, 0, 18), Position = UDim2.new(0, 8, 1, -116), StrokeThickness = 1.5, Parent = detail })
	local moveButton = Kit.Button({
		Text = "To Stash", Color = "Blue", TextSize = 16, Size = UDim2.new(1, -20, 0, 40), Position = UDim2.new(0, 10, 1, -94), Parent = detail,
		OnClick = function()
			local data = DataController:Get()
			local charm = data and selected and data.Charms[selected]
			if not charm then
				return
			end
			if charm.X then
				act("StashCharm", selected)
			else
				local x, y = Charms.FreeSpot(data, selected :: string, owner)
				if not x then
					C.NotificationController:Toast("No room in the grid for that charm", Theme.Red, "Lock")
					return
				end
				if act("PlaceCharm", selected, x, y, owner) then
					C.SoundController:Play("Equip")
				end
			end
		end,
	})
	local lockButton = Kit.Button({
		Text = "Lock", Icon = "Lock", Color = "Dark", TextSize = 15, Size = UDim2.new(0.5, -14, 0, 40), Position = UDim2.new(0, 10, 1, -48), Parent = detail,
		OnClick = function()
			if selected then
				act("LockCharm", selected)
			end
		end,
	})
	local salvageButton = Kit.Button({
		Text = "Salvage", Icon = "Trash", Color = "Red", TextSize = 15, Size = UDim2.new(0.5, -14, 0, 40), Position = UDim2.new(1, -10, 1, -48), AnchorPoint = Vector2.new(1, 0), Parent = detail,
		OnClick = function()
			local data = DataController:Get()
			local uid = selected
			local charm = data and uid and data.Charms[uid]
			if not charm then
				return
			end
			local function go()
				local ok, message = act("SalvageCharm", uid)
				if ok then
					selected = nil
					C.SoundController:Play("Purchase")
					if type(message) == "string" then
						C.NotificationController:Toast(message, Theme.Gold, "Shard")
					end
				end
			end
			if Charms.Rarity(charm.R).Index >= 3 or charm.S then
				Common.Confirm(window, "Salvage " .. Charms.Name(charm) .. "?", string.format("It breaks into %d Spirit Shards. This can't be undone.", Charms.SalvageValue(charm)), "Salvage", "Red", go)
			else
				go()
			end
		end,
	})
	local preview3d: Instance? = nil

	local function showDetail(data)
		if preview3d then
			preview3d:Destroy()
			preview3d = nil
		end
		for _, c in ipairs(lineBox:GetChildren()) do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local charm = selected and data.Charms[selected]
		local has = charm ~= nil and Charms.Valid(charm)
		moveButton.Visible, lockButton.Visible, salvageButton.Visible = has, has, has
		if not has then
			selected = nil
			nameLabel.Text = "Pick a charm"
			nameLabel.TextColor3 = Theme.Text
			kindLabel.Text = "Small 1x1, Large 1x2, Grand 1x3"
			stateLabel.Text = ""
			tall({
				Text = "Charms drop very rarely from any enemy (0.3%). Grand charms can roll +levels to a skill, the only way past the skill level cap. Bosses can drop the Hexfire Torch (0.01%).",
				Font = Theme.FontBody, TextSize = 13, Color = Theme.SubText, Wrapped = true, Size = UDim2.new(1, -4, 0, 0), Stroke = false, Parent = lineBox,
			})
			return
		end
		local rarity = Charms.Rarity(charm.R)
		local model = CharmBuilder.Build(charm)
		if model then
			preview3d = Kit.Viewport(preview, model, { Size = UDim2.fromScale(1, 1), Zoom = 1.2, ZIndex = 3, Spin = true })
		end
		nameLabel.Text = Charms.Name(charm)
		nameLabel.TextColor3 = rarity.Color
		kindLabel.Text = string.format("%s %s  ·  iLvl %d", rarity.Name, Charms.Size(charm).Name, charm.L)
		for i, line in ipairs(Charms.Lines(charm)) do
			tall({
				Text = line[1], Font = Theme.FontHeavy, TextSize = 14, Color = line[2] or AFFIX, Wrapped = true, XAlign = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, -4, 0, 0), LayoutOrder = i, StrokeThickness = 1.5, Parent = lineBox,
			})
		end
		if charm.U and Charms.Uniques[charm.U] then
			tall({
				Text = Charms.Uniques[charm.U].Desc, Font = Theme.FontBody, TextSize = 12, Color = Theme.SubText, Wrapped = true, XAlign = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, -4, 0, 0), LayoutOrder = 99, Stroke = false, Parent = lineBox,
			})
		end
		local where = Hires.Get(charm.G)
		local active = Charms.Active(data, charm.G)[selected :: string] == true
		stateLabel.Text = if not active then "In the stash: not active" elseif where then "In " .. where.Name .. "'s grid" else "In your grid: active"
		stateLabel.TextColor3 = if active then Theme.Green else Theme.Muted
		Kit.Api(moveButton).SetText(if charm.X then "To Stash" else "Place in Grid")
		Kit.Api(moveButton).SetColor(if charm.X then "Blue" else "Green")
		Kit.Api(lockButton).SetText(if charm.Lock then "Unlock" else "Lock")
		Kit.Api(salvageButton).SetEnabled(not charm.Lock)
	end

	function refresh()
		local data = DataController:Get()
		if not data then
			return
		end
		data.Charms = data.Charms or {}
		-- grid tiles
		for _, c in ipairs(tiles:GetChildren()) do
			c:Destroy()
		end
		if owner and not (type(data.Hires) == "table" and data.Hires[owner]) then
			owner = nil
		end
		local active = Charms.Active(data, owner)
		local activeCount = 0
		for uid in pairs(active) do
			activeCount += 1
			local charm = data.Charms[uid]
			charmTile(tiles, uid, charm, tileSize(charm), cellPos(charm.X, charm.Y), 6)
		end
		-- charms in anyone's grid stay out of the stash
		local inUse = table.clone(active)
		for _, id in ipairs(owners()) do
			for uid in pairs(Charms.Active(data, if id then id :: string else nil)) do
				inUse[uid] = true
			end
		end
		-- stash
		Common.ClearGrid(stash)
		local list = {}
		local total = 0
		for uid, charm in pairs(data.Charms) do
			total += 1
			if Charms.Valid(charm) and not inUse[uid] then
				table.insert(list, { Uid = uid, Order = -Charms.Rarity(charm.R).Index * 100 - (if charm.S then 50 else 0) - Charms.Size(charm).Index })
			end
		end
		table.sort(list, function(a, b)
			return if a.Order == b.Order then a.Uid < b.Uid else a.Order < b.Order
		end)
		for i, entry in ipairs(list) do
			local tile = charmTile(stash, entry.Uid, data.Charms[entry.Uid], UDim2.fromScale(1, 1), nil, 3)
			tile.LayoutOrder = i
		end
		if #list == 0 then
			Common.EmptyNote(stash, if total == 0 then "No charms yet. Every enemy has a tiny chance to drop one." else "Every charm you own is in the grid.")
		end
		gridTitle.Text = string.format("Charm Grid  (%d active)", activeCount)
		countLabel.Text = string.format("%d / %d charms", total, Charms.Storage)
		stashTitle.Text = string.format("Stash  (%d)", #list)
		showSlots(data)
		showSummary(data)
		showDetail(data)
		paintHover()
	end

	for _, key in ipairs({ "Charms", "EquippedHat", "Hats", "EquippedKatana", "EquippedPets", "Suit", "Hires", "ActiveHire" }) do
		DataController:OnChange(key, function()
			if window.Visible then
				refresh()
			end
		end)
	end

	return {
		Window = window, Close = close,
		OnOpen = function(arg)
			local data = DataController:Get()
			owner = if type(arg) == "string" and data and type(data.Hires) == "table" and data.Hires[arg] then arg else nil
			selected = nil
			showFigure()
			refresh()
		end,
		OnClose = function()
			selected = nil
		end,
	}
end

return Menu
