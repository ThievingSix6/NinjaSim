--[[
	Trade: trade pets, hats and charms with another player (TradeService, TradeController).
	Shortcut: Y.

	Without an open trade it lists the other players in the server with a Request
	button (invites arrive as a card with Accept / Decline). In a trade it shows your
	offer and theirs side by side, your pets, hats and charms to add (click a card to put it on
	the table or take it back), and Ready. Any change un-readies both sides; when both
	are ready a short countdown runs and the items swap.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Pets = require(Shared.Config.Pets)
local Hats = require(Shared.Config.Hats)
local Rarity = require(Shared.Config.Rarity)
local Mutations = require(Shared.Config.Mutations)
local HatBuilder = require(Shared.Visuals.HatBuilder)
local Charms = require(Shared.Config.Charms)
local CharmBuilder = require(Shared.Visuals.CharmBuilder)

local Menu = {}

function Menu.Build(ctx)
	local Kit, Theme, Common = ctx.Kit, ctx.Theme, ctx.Common
	local C = ctx.Controllers
	local DataController = C.DataController
	local TC = C.TradeController

	local window, content, close = Kit.Window({
		Name = "Trade", Title = "Trade", Icon = "Friends", Accent = "Sky", Size = UDim2.fromOffset(980, 600), Parent = ctx.Parent,
	})

	-- ===== lobby: other players =====
	local lobby = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Name = "Lobby", Parent = content })
	Kit.Label({
		Text = "Trade pets, hats and charms with players in this server, team up in a party (you share XP from kills near each other), or challenge them to a duel (a wager duel puts half your levels on the line). In a trade, both press Ready and the items swap after a 3 second countdown.",
		Font = Theme.FontBody, TextSize = 15, Color = Theme.SubText, Wrapped = true, Size = UDim2.new(1, 0, 0, 40), Stroke = false, Parent = lobby,
	})
	local players = Common.Grid(lobby, { List = true, Gap = 8, Size = UDim2.new(1, 0, 1, -50), Position = UDim2.fromOffset(0, 50) })

	-- ===== session =====
	local session = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Name = "Session", Visible = false, Parent = content })
	local header = Kit.Label({ Text = "", TextSize = 22, Size = UDim2.new(1, -170, 0, 34), StrokeThickness = 2.5, Parent = session })
	Kit.Button({
		Text = "Cancel", Color = "Red", TextSize = 18, Size = UDim2.fromOffset(150, 38), Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0), Parent = session,
		OnClick = function()
			DataController:Request("TradeCancel")
		end,
	})
	local function offerPanel(x: number, title: string)
		local holder = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.5, -6, 0, 206), Position = UDim2.new(x, if x > 0 then 6 else 0, 0, 40), Parent = session })
		local label = Kit.Label({ Text = title, TextSize = 17, Size = UDim2.new(1, 0, 0, 22), StrokeThickness = 2, Parent = holder })
		local grid = Common.Grid(holder, { CellSize = UDim2.fromOffset(88, 106), Gap = 8, Size = UDim2.new(1, 0, 1, -24), Position = UDim2.fromOffset(0, 24) })
		return grid, label
	end
	local mineGrid, mineLabel = offerPanel(0, "Your offer")
	local theirsGrid, theirsLabel = offerPanel(0.5, "Their offer")
	local pickKind = "Pet"
	local refresh
	local tabs = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 42), Position = UDim2.fromOffset(0, 252), Parent = session })
	Kit.Tabs(tabs, { { Name = "Your Pets", Icon = "Pets" }, { Name = "Your Hats", Icon = "Crown" }, { Name = "Your Charms", Icon = "Sparkle" } }, function(name)
		pickKind = if name == "Your Hats" then "Hat" elseif name == "Your Charms" then "Charm" else "Pet"
		refresh()
	end, "Sky")
	local inventory = Common.Grid(session, { CellSize = UDim2.fromOffset(88, 106), Gap = 8, Size = UDim2.new(1, 0, 0, 178), Position = UDim2.fromOffset(0, 298) })
	local status = Kit.Label({ Text = "", TextSize = 18, Size = UDim2.new(1, -200, 0, 44), Position = UDim2.new(0, 0, 1, -44), StrokeThickness = 2, Parent = session })
	local readyButton = Kit.Button({
		Text = "Ready", Color = "Green", TextSize = 22, Size = UDim2.fromOffset(190, 46), Position = UDim2.new(1, 0, 1, 0), AnchorPoint = Vector2.new(1, 1), Parent = session,
		OnClick = function()
			local s = TC:GetState()
			if s then
				DataController:Request("TradeReady", not s.MyReady)
			end
		end,
	})

	local function petCard(parent, entry, order: number, onClick)
		local def = Pets.ById[entry.Id]
		if not def then
			return nil
		end
		local m = Mutations.Get(entry.Mutation)
		return Common.Card({
			Title = Pets.DisplayName(def, entry.Mutation), Rarity = def.Rarity, Model = Common.PetModel(entry.Id, entry.Mutation), Zoom = Common.PetZoom(1.15, entry.Mutation),
			Sub = if m then m.Name else def.Rarity, SubColor = if m then m.Color else Rarity.Color(def.Rarity), LayoutOrder = order, Parent = parent, OnClick = onClick,
		})
	end
	local function hatCard(parent, hat, order: number, onClick)
		if not Hats.Valid(hat) then
			return nil
		end
		local rarity = Hats.Rarity(hat.R)
		local m = Mutations.Get(hat.M)
		return Common.Card({
			Title = Hats.Name(hat), Paint = rarity.Paint, Model = HatBuilder.Build(hat), Zoom = 1.05,
			Sub = if m then m.Name else rarity.Name, SubColor = if m then m.Color else rarity.Color, LayoutOrder = order, Parent = parent, OnClick = onClick,
		})
	end

	local function charmCard(parent, charm, order: number, onClick)
		if not Charms.Valid(charm) then
			return nil
		end
		local rarity = Charms.Rarity(charm.R)
		return Common.Card({
			Title = Charms.Name(charm), Paint = rarity.Paint, Model = CharmBuilder.Build(charm), Zoom = 1.2,
			Sub = if charm.S then Charms.Lines(charm)[1][1] else rarity.Name .. " " .. Charms.Size(charm).Id,
			SubColor = if charm.S then Theme.Gold else rarity.Color, LayoutOrder = order, Parent = parent, OnClick = onClick,
		})
	end

	local function showOffer(grid, offer, mine: boolean)
		Common.ClearGrid(grid)
		local n = 0
		for _, entry in ipairs(offer.Pet or {}) do
			n += 1
			petCard(grid, entry, n, if mine then function()
				DataController:Request("TradeOffer", "Pet", entry.Uid, false)
			end else nil)
		end
		for _, entry in ipairs(offer.Hat or {}) do
			n += 1
			hatCard(grid, entry.Hat, n, if mine then function()
				DataController:Request("TradeOffer", "Hat", entry.Uid, false)
			end else nil)
		end
		for _, entry in ipairs(offer.Charm or {}) do
			n += 1
			charmCard(grid, entry.Charm, n, if mine then function()
				DataController:Request("TradeOffer", "Charm", entry.Uid, false)
			end else nil)
		end
		if n == 0 then
			Common.EmptyNote(grid, if mine then "Click your pets, hats and charms below to offer them" else "Nothing yet")
		end
	end

	local function showInventory(s)
		local data = DataController:Get()
		Common.ClearGrid(inventory)
		if not data then
			return
		end
		local offered = {}
		for _, entry in ipairs(s.Mine[pickKind] or {}) do
			offered[entry.Uid] = true
		end
		local list = {}
		if pickKind == "Pet" then
			for uid, owned in pairs(data.Pets) do
				local def = Pets.ById[owned.Id]
				if def and not offered[uid] then
					table.insert(list, { Uid = uid, Order = -Rarity.Index(def.Rarity) * 100 - (Mutations.Get(owned.Mutation) and Mutations.Get(owned.Mutation).Order or 0) })
				end
			end
		elseif pickKind == "Hat" then
			for uid, hat in pairs(data.Hats) do
				if Hats.Valid(hat) and not offered[uid] then
					table.insert(list, { Uid = uid, Order = -Hats.Rarity(hat.R).Index * 100 - (Mutations.Get(hat.M) and Mutations.Get(hat.M).Order or 0) })
				end
			end
		else
			for uid, charm in pairs(data.Charms or {}) do
				if Charms.Valid(charm) and not offered[uid] then
					table.insert(list, { Uid = uid, Order = -Charms.Rarity(charm.R).Index * 100 - (if charm.S then 50 else 0) - Charms.Size(charm).Index })
				end
			end
		end
		table.sort(list, function(a, b)
			return if a.Order == b.Order then a.Uid < b.Uid else a.Order < b.Order
		end)
		for i, entry in ipairs(list) do
			local uid = entry.Uid
			local add = function()
				DataController:Request("TradeOffer", pickKind, uid, true)
			end
			if pickKind == "Pet" then
				local owned = data.Pets[uid]
				petCard(inventory, { Uid = uid, Id = owned.Id, Mutation = owned.Mutation }, i, add)
			elseif pickKind == "Hat" then
				hatCard(inventory, data.Hats[uid], i, add)
			else
				charmCard(inventory, data.Charms[uid], i, add)
			end
		end
		if #list == 0 then
			Common.EmptyNote(inventory, if pickKind == "Pet" then "No pets left to offer" elseif pickKind == "Hat" then "No hats left to offer" else "No charms left to offer")
		end
	end

	local function showLobby()
		Common.ClearGrid(players)
		local others = 0
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= Players.LocalPlayer then
				others += 1
				local row = Kit.Panel({ Size = UDim2.new(1, -8, 0, 58), Color = Theme.Panel2, StrokeThickness = 3, Radius = 12, LayoutOrder = others, Parent = players })
				Kit.Label({ Text = other.DisplayName, TextSize = 20, Size = UDim2.new(1, -620, 1, 0), Position = UDim2.fromOffset(16, 0), StrokeThickness = 2, Scaled = true, MaxTextSize = 20, Parent = row })
				Kit.Button({
					Text = "Trade", Color = "Sky", TextSize = 17, Size = UDim2.fromOffset(140, 42), Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Parent = row,
					OnClick = function()
						DataController:Request("TradeRequest", other.UserId)
					end,
				})
				-- duels (DuelService): a plain one, or one where half your levels are on the line
				Kit.Button({
					Text = "Wager Duel", Icon = "Katana", Color = "Red", TextSize = 16, Size = UDim2.fromOffset(160, 42), Position = UDim2.new(1, -160, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Parent = row,
					OnClick = function()
						Common.Confirm(window, "Wager duel " .. other.DisplayName .. "?", "If you lose, you lose half your levels. If you win, you gain half of theirs. They have to accept.", "Challenge", "Red", function()
							local ok, message = DataController:Request("DuelRequest", other.UserId, true)
							if ok then
								C.NotificationController:Toast(tostring(message or "Challenge sent"), Theme.Gold, "Katana")
							end
						end)
					end,
				})
				Kit.Button({
					Text = "Duel", Icon = "Katana", Color = "Orange", TextSize = 16, Size = UDim2.fromOffset(120, 42), Position = UDim2.new(1, -330, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Parent = row,
					OnClick = function()
						-- refusals are toasted by DataController
						local ok, message = DataController:Request("DuelRequest", other.UserId, false)
						if ok then
							C.NotificationController:Toast(tostring(message or "Challenge sent"), Theme.Gold, "Katana")
						end
					end,
				})
				-- parties (PartyService): team up and share XP
				Kit.Button({
					Text = "Party", Icon = "Pets", Color = "Green", TextSize = 16, Size = UDim2.fromOffset(130, 42), Position = UDim2.new(1, -460, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Parent = row,
					OnClick = function()
						local ok, message = DataController:Request("PartyInvite", other.UserId)
						if ok then
							C.NotificationController:Toast(tostring(message or "Invite sent"), Theme.Green, "Pets")
						end
					end,
				})
			end
		end
		if others == 0 then
			Common.EmptyNote(players, "Nobody else is in this server yet. Invite a friend!")
		end
	end

	function refresh()
		local s = TC:GetState()
		lobby.Visible = s == nil
		session.Visible = s ~= nil
		if not s then
			showLobby()
			return
		end
		header.Text = "Trading with " .. tostring(s.PartnerName)
		mineLabel.Text = "Your offer" .. (if s.MyReady then "  (ready)" else "")
		theirsLabel.Text = tostring(s.PartnerName) .. "'s offer" .. (if s.TheirReady then "  (ready)" else "")
		mineLabel.TextColor3 = if s.MyReady then Theme.Green else Theme.Text
		theirsLabel.TextColor3 = if s.TheirReady then Theme.Green else Theme.Text
		showOffer(mineGrid, s.Mine, true)
		showOffer(theirsGrid, s.Theirs, false)
		showInventory(s)
		local api = Kit.Api(readyButton)
		api.SetText(if s.MyReady then "Not ready" else "Ready")
		api.SetColor(if s.MyReady then "Orange" else "Green")
		if s.Countdown then
			status.Text = "Both ready: trading in " .. math.ceil(s.Countdown) .. "..."
			status.TextColor3 = Theme.Gold
		elseif s.MyReady then
			status.Text = "Waiting for " .. tostring(s.PartnerName) .. " to press Ready"
			status.TextColor3 = Theme.SubText
		else
			status.Text = "Check both offers, then press Ready"
			status.TextColor3 = Theme.SubText
		end
	end

	TC:OnChange(function()
		if window.Visible then
			refresh()
		end
	end)
	for _, key in ipairs({ "Pets", "Hats", "Charms" }) do
		DataController:OnChange(key, function()
			if window.Visible then
				refresh()
			end
		end)
	end
	Players.PlayerAdded:Connect(function()
		if window.Visible and not TC:GetState() then
			showLobby()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		if window.Visible and not TC:GetState() then
			task.defer(showLobby)
		end
	end)

	return {
		Window = window, Close = close, OnOpen = refresh,
		OnClose = function()
			-- closing the window with a trade open cancels it, so nobody waits on a hidden window
			if TC:GetState() then
				DataController:Request("TradeCancel")
			end
		end,
	}
end

return Menu
