--[[
	PartyController: the client side of parties (PartyService). Invites are sent from
	the Trade menu's player list (Party). This pops the invite card (Accept / Decline),
	keeps the party panel on the left of the HUD (each member's name, level and health,
	the leader's crown, Leave, and Kick for the leader), and shows the XP you get from
	party members' kills.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Format = require(Shared.Util.Format)

local PartyController = {}

local player = Players.LocalPlayer
local controllers
local panel: Frame? = nil
local rows: { { Player: Player?, Fill: Frame, Level: TextLabel } } = {}
local members: { any } = {}
local maxSize = 4

function PartyController:Members(): { any }
	return members
end

local function inviteCard(payload)
	local Kit, Theme = controllers.Kit, controllers.Theme
	local root = controllers.UIController:Root("Toasts")
	local old = root:FindFirstChild("PartyInvite")
	if old then
		old:Destroy()
	end
	local card = Kit.Panel({
		Name = "PartyInvite", Size = UDim2.fromOffset(360, 116), Position = UDim2.new(1, -24, 1, -540), AnchorPoint = Vector2.new(1, 1),
		Paint = { Theme.Body, Theme.BodyDark }, StrokeThickness = 3, Radius = 14, Parent = root,
	})
	Kit.Icon(card, "Pets", { Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(10, 8), ZIndex = 3 })
	Kit.Label({
		Text = string.format("%s (Lv %s) invites you to their party", payload.FromName or "Someone", Format.Abbrev(payload.Level or 0)),
		TextSize = 18, Wrapped = true, Size = UDim2.new(1, -70, 0, 48), Position = UDim2.fromOffset(62, 6), ZIndex = 3, StrokeThickness = 2, Parent = card,
	})
	local function answer(accept: boolean)
		card:Destroy()
		controllers.DataController:Request("PartyRespond", payload.From, accept)
	end
	Kit.Button({ Text = "Decline", Color = "Dark", TextSize = 18, Size = UDim2.fromOffset(160, 44), Position = UDim2.new(0, 10, 1, -10), AnchorPoint = Vector2.new(0, 1), ZIndex = 3, Parent = card,
		OnClick = function()
			answer(false)
		end })
	Kit.Button({ Text = "Join", Color = "Green", TextSize = 18, Size = UDim2.fromOffset(160, 44), Position = UDim2.new(1, -10, 1, -10), AnchorPoint = Vector2.new(1, 1), ZIndex = 3, Parent = card,
		OnClick = function()
			answer(true)
		end })
	task.delay(payload.Seconds or 30, function()
		if card.Parent then
			card:Destroy()
		end
	end)
end

local function clearPanel()
	if panel then
		panel:Destroy()
		panel = nil
	end
	table.clear(rows)
end

-- The party panel: one row per other member, under the menu buttons on the left.
local function buildPanel()
	clearPanel()
	if #members == 0 then
		return
	end
	local Kit, Theme = controllers.Kit, controllers.Theme
	local root = controllers.UIController:Root("HUD")
	local iLead = false
	for _, m in ipairs(members) do
		if m.UserId == player.UserId and m.Leader then
			iLead = true
		end
	end
	local others = {}
	for _, m in ipairs(members) do
		if m.UserId ~= player.UserId then
			table.insert(others, m)
		end
	end
	local height = 34 + #others * 44
	local frame = Kit.Panel({
		Name = "PartyPanel", Size = UDim2.fromOffset(214, height), Position = UDim2.fromOffset(12, 530),
		Color = Theme.Bg, Transparency = 0.3, StrokeColor = Theme.Green, StrokeThickness = 2, Radius = 10, Parent = root,
	})
	Kit.Label({ Text = string.format("PARTY %d/%d", #members, maxSize), TextSize = 14, Color = Theme.Green, Size = UDim2.new(1, -80, 0, 24), Position = UDim2.fromOffset(10, 4), StrokeThickness = 1.5, Parent = frame })
	Kit.Button({
		Text = "Leave", Color = "Dark", TextSize = 12, Size = UDim2.fromOffset(60, 22), Position = UDim2.new(1, -6, 0, 5), AnchorPoint = Vector2.new(1, 0), Parent = frame,
		OnClick = function()
			controllers.DataController:Request("PartyLeave")
		end,
	})
	for i, m in ipairs(others) do
		local y = 30 + (i - 1) * 44
		local name = (if m.Leader then "👑 " else "") .. (m.Name or "?")
		Kit.Label({ Text = name, TextSize = 14, Scaled = true, MaxTextSize = 14, Size = UDim2.new(1, if iLead then -100 else -70, 0, 18), Position = UDim2.fromOffset(10, y), StrokeThickness = 1.5, Parent = frame })
		local level = Kit.Label({ Text = "", TextSize = 12, Color = Theme.Gold, XAlign = Enum.TextXAlignment.Right, Size = UDim2.fromOffset(56, 18), Position = UDim2.new(1, if iLead then -40 else -10, 0, y), AnchorPoint = Vector2.new(1, 0), StrokeThickness = 1.5, Parent = frame })
		local back = Kit.New("Frame", { BackgroundColor3 = Theme.Ink, Size = UDim2.new(1, -20, 0, 10), Position = UDim2.fromOffset(10, y + 21), Parent = frame })
		Kit.Corner(5).Parent = back
		local fill = Kit.New("Frame", { BackgroundColor3 = Theme.Green, Size = UDim2.fromScale(1, 1), Parent = back })
		Kit.Corner(5).Parent = fill
		if iLead then
			Kit.Button({
				Text = "X", Color = "Red", TextSize = 12, Size = UDim2.fromOffset(24, 20), Position = UDim2.new(1, -8, 0, y - 1), AnchorPoint = Vector2.new(1, 0), Parent = frame,
				OnClick = function()
					controllers.DataController:Request("PartyKick", m.UserId)
				end,
			})
		end
		table.insert(rows, { Player = Players:GetPlayerByUserId(m.UserId), Fill = fill, Level = level })
	end
	panel = frame
end

local function onEvent(payload)
	local c = controllers
	if payload.Type == "Invite" then
		c.SoundController:Play("Purchase")
		inviteCard(payload)
	elseif payload.Type == "Declined" then
		c.NotificationController:Toast((payload.By or "They") .. " declined your party invite", c.Theme.SubText, "Pets")
	elseif payload.Type == "Update" then
		local had = #members > 0
		members = payload.Members or {}
		maxSize = payload.Max or maxSize
		buildPanel()
		if not had then
			c.NotificationController:Toast("You're in a party! Kills near each other share XP.", c.Theme.Green, "Pets")
		end
	elseif payload.Type == "Left" then
		members = {}
		clearPanel()
		local text = if payload.Reason == "kicked" then "You were removed from the party" elseif payload.Reason == "disbanded" then "Your party disbanded" else "You left the party"
		c.NotificationController:Toast(text, c.Theme.SubText, "Pets")
	elseif payload.Type == "XP" then
		if typeof(payload.Position) == "Vector3" then
			local camera = workspace.CurrentCamera
			local screen, onScreen = camera:WorldToViewportPoint(payload.Position + Vector3.new(0, 6, 0))
			local scale = c.UIController.Scale
			local pos = if onScreen then Vector2.new(screen.X, screen.Y) / scale else Vector2.new(640, 320)
			c.EffectsController:FloatText("+" .. Format.Abbrev(payload.Amount or 0) .. " XP (party)", c.Theme.XP, pos, 24)
		end
	end
end

function PartyController:Start(c)
	controllers = c
	Net.Event("Party").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		local ok, err = pcall(onEvent, payload)
		if not ok then
			warn("[PartyController] " .. tostring(err))
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.2 or not panel then
			return
		end
		acc = 0
		for _, row in ipairs(rows) do
			local p = row.Player
			local character = p and p.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local ratio = if humanoid and humanoid.MaxHealth > 0 then math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) else 0
			row.Fill.Size = UDim2.fromScale(ratio, 1)
			row.Fill.BackgroundColor3 = if ratio > 0.5 then controllers.Theme.Green elseif ratio > 0.25 then controllers.Theme.Gold else controllers.Theme.Red
			local stats = p and p:FindFirstChild("leaderstats")
			local level = stats and stats:FindFirstChild("Level") :: StringValue?
			row.Level.Text = if level then "Lv " .. level.Value else ""
		end
	end)
end

return PartyController
