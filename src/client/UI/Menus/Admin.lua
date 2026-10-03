--[[
	Admin: the admin panel (admins and owners only; F2 or the Admin button).
	Pick a player on the left, type an amount or message in the box, press a
	command. The server (AdminService) checks the rank on every command.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Events = require(ReplicatedStorage.Shared.Config.Events)

local Menu = {}

local PLAYER_COMMANDS = {
	{ "Coins", "Give Coins", "Gold", "Coin" },
	{ "Shards", "Give Shards", "Cyan", "Shard" },
	{ "Levels", "Add Levels", "Blue", "Star" },
	{ "UnlockZones", "Unlock Areas", "Green", "Areas" },
	{ "Heal", "Heal", "Green", "Heart" },
	{ "God", "God Mode", "Purple", "Sparkle" },
	{ "GoTo", "Go To", "Sky", "Boot" },
	{ "Bring", "Bring", "Sky", "Friends" },
	{ "Kill", "Knock Out", "Orange", "Oni" },
	{ "Kick", "Kick", "Red", "Lock" },
	{ "UnlockSkills", "Unlock Skills", "Pink", "Shuriken" },
	{ "GivePet", "Give Pet", "Orange", "Pets" },
	{ "ResetProgress", "Reset Progress", "Red", "Rebirth" },
	{ "DropHat", "Drop Hat", "Orange", "Crown" }, -- box: rarity (Common..Mythic), empty = normal roll
	{ "DropCharm", "Drop Charm", "Orange", "Sparkle" }, -- box: rarity, size, Skill or Torch; empty = normal roll
	{ "Mastery", "Set Mastery", "Gold", "Star" }, -- box: mastery level (1-100) for the worn suit
}

function Menu.Build(ctx)
	local Kit, Theme = ctx.Kit, ctx.Theme
	local DataController = ctx.Controllers.DataController
	local me = Players.LocalPlayer

	local window, content, close = Kit.Window({
		Name = "Admin", Title = "Admin Panel", Icon = "Crown", Accent = "Purple", Size = UDim2.fromOffset(860, 540), Parent = ctx.Parent,
	})

	local target: Player = me
	local admins = {}
	local refreshPlayers, refreshAdmins

	-- ===== left: players =====
	local left = Kit.Well({ Size = UDim2.new(0, 230, 1, 0), Parent = content })
	Kit.Label({ Text = "Players", TextSize = 20, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 4), StrokeThickness = 2.5, ZIndex = 3, Parent = left })
	local list = Kit.New("ScrollingFrame", {
		BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, -12, 1, -42), Position = UDim2.fromOffset(6, 36),
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, ZIndex = 3, Parent = left,
	})
	Kit.List(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center).Parent = list

	-- ===== right: input, status, tabs =====
	local right = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -246, 1, 0), Position = UDim2.fromOffset(246, 0), Parent = content })
	local targetLabel = Kit.Label({ Text = "", TextSize = 20, Size = UDim2.new(1, 0, 0, 26), StrokeThickness = 2.5, Parent = right })
	local boxFrame = Kit.Panel({ Size = UDim2.new(1, 0, 0, 46), Position = UDim2.fromOffset(0, 30), Paint = { Color3.fromRGB(250, 250, 255), Color3.fromRGB(214, 220, 232) }, Stripes = false, StrokeThickness = 3, Radius = 10, Parent = right })
	local box = Kit.New("TextBox", {
		BackgroundTransparency = 1, Size = UDim2.new(1, -20, 1, 0), Position = UDim2.fromOffset(10, 0), ZIndex = 2,
		Font = Theme.FontBold, TextSize = 20, TextColor3 = Theme.Ink, TextXAlignment = Enum.TextXAlignment.Left,
		PlaceholderText = "Amount, message or kick reason", PlaceholderColor3 = Color3.fromRGB(150, 158, 178),
		Text = "", ClearTextOnFocus = false, Parent = boxFrame,
	})
	local status = Kit.Label({ Text = "", TextSize = 17, Wrapped = true, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 1, -24), StrokeThickness = 2, Parent = right })

	local pages = {}
	local function page(name: string): Frame
		local f = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -168), Position = UDim2.fromOffset(0, 136), Visible = false, Parent = right })
		pages[name] = f
		return f
	end
	local _, selectTab = Kit.Tabs(Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 86), Parent = right }), {
		{ Name = "Player", Icon = "Friends" }, { Name = "Server", Icon = "Bolt" }, { Name = "Admins", Icon = "Crown" },
	}, function(name)
		for n, f in pairs(pages) do
			f.Visible = n == name
		end
	end, "Purple")

	local function run(command: string, value: any?)
		local ok, result = DataController:Request("Admin", command, target.UserId, value)
		if ok and type(result) == "table" then
			admins = result.Admins or admins
			if result.Message then
				status.Text = tostring(result.Message)
				status.TextColor3 = Theme.Green
			end
			refreshAdmins()
		elseif not ok then
			status.Text = tostring(result or "That didn't work")
			status.TextColor3 = Theme.Red
		end
		return ok
	end

	local function grid(parent: Instance)
		Kit.New("UIGridLayout", { CellSize = UDim2.fromOffset(176, 50), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = parent })
	end

	-- player commands
	local playerPage = page("Player")
	grid(playerPage)
	for i, cmd in ipairs(PLAYER_COMMANDS) do
		Kit.Button({
			Text = cmd[2], Icon = cmd[4], Color = cmd[3], TextSize = 18, IconSize = 30, LayoutOrder = i, Size = UDim2.fromOffset(176, 50), Parent = playerPage,
			OnClick = function()
				run(cmd[1], box.Text)
			end,
		})
	end

	-- server commands
	local serverPage = page("Server")
	grid(serverPage)
	for i, def in ipairs(Events.List) do
		Kit.Button({
			Text = def.Name, Color = "Orange", TextSize = 17, LayoutOrder = i, Size = UDim2.fromOffset(176, 50), Parent = serverPage,
			OnClick = function()
				run("Event", def.Id)
			end,
		})
	end
	Kit.Button({
		Text = "Spawn Boss", Icon = "Oni", Color = "Red", TextSize = 18, IconSize = 30, LayoutOrder = 10, Size = UDim2.fromOffset(176, 50), Parent = serverPage,
		OnClick = function()
			run("Boss")
		end,
	})
	Kit.Button({
		Text = "Announce", Icon = "Scroll", Color = "Gold", TextSize = 18, IconSize = 30, LayoutOrder = 11, Size = UDim2.fromOffset(176, 50), Parent = serverPage,
		OnClick = function()
			if run("Announce", box.Text) then
				box.Text = ""
			end
		end,
	})
	Kit.Label({
		Text = "Spawn Boss uses the selected player's area. Announce sends the text in the box to everyone.",
		TextSize = 15, Wrapped = true, Color = Theme.SubText, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 20, StrokeThickness = 0, Parent = serverPage,
	})

	-- admins (appointing is owner only)
	local adminPage = page("Admins")
	local makeAdmin = Kit.Button({
		Text = "Make Admin", Icon = "Crown", Color = "Purple", TextSize = 18, IconSize = 30, Size = UDim2.fromOffset(220, 50), Parent = adminPage,
		OnClick = function()
			run("MakeAdmin")
		end,
	})
	local note = Kit.Label({ Text = "", TextSize = 15, Wrapped = true, Color = Theme.SubText, Size = UDim2.new(1, -236, 0, 50), Position = UDim2.fromOffset(232, 0), StrokeThickness = 0, Parent = adminPage })
	local adminList = Kit.New("ScrollingFrame", {
		BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 1, -62), Position = UDim2.fromOffset(0, 62),
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, Parent = adminPage,
	})
	Kit.List(Enum.FillDirection.Vertical, 6).Parent = adminList

	function refreshAdmins()
		local owner = me:GetAttribute("NinjaAdmin") == "Owner"
		Kit.Api(makeAdmin).SetEnabled(owner)
		note.Text = if owner
			then "Makes the selected player an admin in every server. Owners are set in Config/Admins."
			else "Only owners can appoint or remove admins."
		for _, c in ipairs(adminList:GetChildren()) do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		if #admins == 0 then
			Kit.Label({ Text = "No appointed admins yet.", TextSize = 17, Color = Theme.SubText, Size = UDim2.new(1, 0, 0, 30), StrokeThickness = 0, Parent = adminList })
		end
		for i, entry in ipairs(admins) do
			local row = Kit.Well({ Size = UDim2.new(1, -10, 0, 46), LayoutOrder = i, Parent = adminList })
			Kit.Label({ Text = tostring(entry.Name) .. "  (" .. tostring(entry.UserId) .. ")", TextSize = 18, Size = UDim2.new(1, -130, 1, 0), Position = UDim2.fromOffset(12, 0), ZIndex = 3, StrokeThickness = 2, Parent = row })
			if owner then
				Kit.Button({
					Text = "Remove", Color = "Red", TextSize = 16, Size = UDim2.fromOffset(104, 36), Position = UDim2.new(1, -8, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), ZIndex = 3, Parent = row,
					OnClick = function()
						run("RemoveAdmin", entry.UserId)
					end,
				})
			end
		end
	end

	function refreshPlayers()
		if not target.Parent then
			target = me
		end
		targetLabel.Text = "Selected: " .. target.DisplayName .. (if target == me then " (you)" else "")
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local players = Players:GetPlayers()
		table.sort(players, function(a, b)
			return a.DisplayName < b.DisplayName
		end)
		for i, p in ipairs(players) do
			local rank = p:GetAttribute("NinjaAdmin")
			Kit.Button({
				Text = p.DisplayName .. (if rank then " 👑" else ""), Color = if p == target then "Purple" else "Dark",
				TextSize = 17, LayoutOrder = i, Size = UDim2.new(1, -10, 0, 40), Parent = list,
				OnClick = function()
					target = p
					refreshPlayers()
				end,
			})
		end
	end

	Players.PlayerAdded:Connect(function()
		if window.Visible then
			refreshPlayers()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(function()
			if window.Visible then
				refreshPlayers()
			end
		end)
	end)

	selectTab("Player")
	return {
		Window = window,
		Close = close,
		OnOpen = function()
			status.Text = ""
			refreshPlayers()
			refreshAdmins()
			run("ListAdmins")
		end,
	}
end

return Menu
