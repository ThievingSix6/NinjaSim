--[[
	DuelController: the client side of duels (DuelService). Challenges are sent from the
	Trade menu's player list (Duel / Wager Duel). This pops the challenge card (Accept /
	Decline, with the wager spelled out), runs the countdown and "FIGHT!", shows the duel
	bar at the top of the screen (both health bars, the time left, a Forfeit button),
	draws the hits, and says who won and what the wager did.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)

local DuelController = {}

local player = Players.LocalPlayer
local controllers
local active: { Opponent: Player?, Name: string, Wager: boolean, EndsAt: number?, Fighting: boolean }? = nil
local bar: Frame? = nil
local refs: any = {}

function DuelController:InDuel(): boolean
	return active ~= nil
end

-- The player you're dueling (lock-on can target them), or nil.
function DuelController:Opponent(): Player?
	return active and active.Opponent or nil
end

-- Challenge card: bottom right, Accept / Decline, gone after `seconds`.
local function inviteCard(payload)
	local Kit, Theme = controllers.Kit, controllers.Theme
	local root = controllers.UIController:Root("Toasts")
	local old = root:FindFirstChild("DuelInvite")
	if old then
		old:Destroy()
	end
	local card = Kit.Panel({
		Name = "DuelInvite", Size = UDim2.fromOffset(360, if payload.Wager then 150 else 124), Position = UDim2.new(1, -24, 1, -400), AnchorPoint = Vector2.new(1, 1),
		Paint = { Theme.Body, Theme.BodyDark }, StrokeThickness = 3, Radius = 14, Parent = root,
	})
	Kit.Icon(card, "Katana", { Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(10, 8), ZIndex = 3 })
	Kit.Label({
		Text = string.format("%s (Lv %d) challenges you to a duel", payload.FromName or "Someone", payload.Level or 0),
		TextSize = 18, Wrapped = true, Size = UDim2.new(1, -70, 0, 48), Position = UDim2.fromOffset(62, 6), ZIndex = 3, StrokeThickness = 2, Parent = card,
	})
	if payload.Wager then
		Kit.Label({
			Text = "WAGER: the loser loses half their levels, the winner gains half the loser's.",
			Font = Theme.FontBody, TextSize = 13, Color = Theme.Red, Wrapped = true, Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 56), ZIndex = 3, Stroke = false, Parent = card,
		})
	end
	local function answer(accept: boolean)
		card:Destroy()
		controllers.DataController:Request("DuelRespond", payload.From, accept)
	end
	Kit.Button({ Text = "Decline", Color = "Dark", TextSize = 18, Size = UDim2.fromOffset(160, 44), Position = UDim2.new(0, 10, 1, -10), AnchorPoint = Vector2.new(0, 1), ZIndex = 3, Parent = card,
		OnClick = function()
			answer(false)
		end })
	Kit.Button({ Text = "Accept", Color = if payload.Wager then "Red" else "Green", TextSize = 18, Size = UDim2.fromOffset(160, 44), Position = UDim2.new(1, -10, 1, -10), AnchorPoint = Vector2.new(1, 1), ZIndex = 3, Parent = card,
		OnClick = function()
			answer(true)
		end })
	task.delay(payload.Seconds or 30, function()
		if card.Parent then
			card:Destroy()
		end
	end)
end

-- The duel bar: you vs them, a health bar each, the time left and Forfeit.
local function healthBar(parent: Instance, x: number, align: Enum.TextXAlignment, name: string, color: Color3)
	local Kit, Theme = controllers.Kit, controllers.Theme
	local holder = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.5, -60, 1, 0), Position = UDim2.new(x, if x > 0 then 60 else 0, 0, 0), Parent = parent })
	Kit.Label({ Text = name, TextSize = 16, XAlign = align, Size = UDim2.new(1, 0, 0, 20), StrokeThickness = 2, Parent = holder })
	local back = Kit.New("Frame", { BackgroundColor3 = Theme.Ink, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 24), Parent = holder })
	Kit.Corner(7).Parent = back
	local fill = Kit.New("Frame", { BackgroundColor3 = color, Size = UDim2.fromScale(1, 1), AnchorPoint = Vector2.new(if x > 0 then 1 else 0, 0), Position = UDim2.fromScale(if x > 0 then 1 else 0, 0), Parent = back })
	Kit.Corner(7).Parent = fill
	return fill
end

local function showBar(opponentName: string, wager: boolean)
	local Kit, Theme = controllers.Kit, controllers.Theme
	if bar then
		bar:Destroy()
	end
	local root = controllers.UIController:Root("Toasts")
	local frame = Kit.Panel({
		Name = "DuelBar", Size = UDim2.fromOffset(560, 86), Position = UDim2.new(0.5, 0, 0, 70), AnchorPoint = Vector2.new(0.5, 0),
		Color = Theme.Bg, Transparency = 0.25, StrokeColor = if wager then Theme.Red else Theme.Gold, StrokeThickness = 2.5, Radius = 12, Parent = root,
	})
	local inner = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -24, 0, 40), Position = UDim2.fromOffset(12, 8), Parent = frame })
	refs.Mine = healthBar(inner, 0, Enum.TextXAlignment.Left, player.DisplayName, Theme.Green)
	refs.Theirs = healthBar(inner, 0.5, Enum.TextXAlignment.Right, opponentName, Theme.Red)
	refs.Clock = Kit.Label({ Text = "", Font = Theme.FontNumber, TextSize = 20, XAlign = Enum.TextXAlignment.Center, Size = UDim2.fromOffset(120, 26), Position = UDim2.new(0.5, 0, 0, 14), AnchorPoint = Vector2.new(0.5, 0), StrokeThickness = 2, Parent = frame })
	Kit.Label({
		Text = if wager then "WAGER DUEL" else "DUEL", TextSize = 13, Color = if wager then Theme.Red else Theme.Gold, XAlign = Enum.TextXAlignment.Center,
		Size = UDim2.fromOffset(120, 16), Position = UDim2.new(0.5, 0, 0, 0), AnchorPoint = Vector2.new(0.5, 0), StrokeThickness = 1.5, Parent = frame,
	})
	Kit.Button({
		Text = "Forfeit", Color = "Dark", TextSize = 14, Size = UDim2.fromOffset(96, 28), Position = UDim2.new(0.5, 0, 1, -6), AnchorPoint = Vector2.new(0.5, 1), Parent = frame,
		OnClick = function()
			controllers.DataController:Request("DuelForfeit")
		end,
	})
	bar = frame
end

local function hide()
	if bar then
		bar:Destroy()
		bar = nil
	end
	active = nil
end

local function onEvent(payload)
	local c = controllers
	local nc = c.NotificationController
	if payload.Type == "Invite" then
		c.SoundController:Play("Purchase")
		inviteCard(payload)
	elseif payload.Type == "Declined" then
		nc:Toast((payload.By or "They") .. " declined your duel", c.Theme.SubText, "Katana")
	elseif payload.Type == "Start" then
		if c.MenuManager:IsOpen() then
			c.MenuManager:Close()
		end
		active = {
			Opponent = Players:GetPlayerByUserId(payload.OpponentId or 0), Name = payload.Opponent or "?", Wager = payload.Wager == true,
			EndsAt = nil, Fighting = false, MaxTime = payload.MaxTime or 120,
		}
		showBar(active.Name, active.Wager)
		c.SoundController:Play("BossSpawn")
		local count = payload.Countdown or 3
		for i = count, 1, -1 do
			task.delay(count - i, function()
				if active and not active.Fighting then
					nc:Banner(tostring(i), "vs " .. active.Name, c.Theme.Gold, 0.8)
				end
			end)
		end
	elseif payload.Type == "Fight" then
		if active then
			active.Fighting = true
			active.EndsAt = os.clock() + (active.MaxTime or 120)
			nc:Banner("FIGHT!", nil, c.Theme.Red, 1)
			c.SoundController:Play("Finisher")
		end
	elseif payload.Type == "Hit" then
		if typeof(payload.Position) == "Vector3" then
			local fx = c.EffectsController
			local top = payload.Position + Vector3.new(0, 3.5, 0)
			fx:HitSpark(payload.Position + Vector3.new(0, 1.5, 0), if payload.Crit then Color3.fromRGB(255, 210, 60) else Color3.new(1, 1, 1), payload.Crit)
			if payload.Target ~= player.UserId then
				fx:DamageNumber(top, payload.Damage, payload.Crit)
				c.SoundController:Play(if payload.Crit then "Crit" else "Hit")
			end
		end
	elseif payload.Type == "End" then
		local won = payload.Winner == player.DisplayName
		local title, sub
		if not payload.Winner then
			title, sub = "Draw", "Time ran out with nobody ahead"
		elseif won then
			title = "Victory!"
			sub = if payload.Wager then string.format("You took %d levels from %s", payload.Gained or 0, payload.Loser or "them") else "You beat " .. tostring(payload.Loser)
		else
			title = "Defeat"
			sub = if payload.Wager then string.format("%s took %d of your levels", payload.Winner, payload.Lost or 0) else tostring(payload.Winner) .. " won the duel"
		end
		if payload.Reason == "forfeit" then
			sub ..= " (forfeit)"
		elseif payload.Reason == "left" then
			sub ..= " (they left)"
		end
		nc:Callout(title, sub, if won then c.Theme.Gold elseif payload.Winner then c.Theme.Red else c.Theme.SubText, "Katana", 4.5)
		c.SoundController:Play(if won then "TierUp" else "Hurt")
		hide()
	end
end

function DuelController:Start(c)
	controllers = c
	Net.Event("Duel").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		local ok, err = pcall(onEvent, payload)
		if not ok then
			warn("[DuelController] " .. tostring(err))
		end
	end)
	RunService.RenderStepped:Connect(function()
		if not active or not bar then
			return
		end
		local function ratio(p: Player?): number
			local character = p and p.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			return if humanoid and humanoid.MaxHealth > 0 then math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) else 0
		end
		refs.Mine.Size = UDim2.fromScale(ratio(player), 1)
		refs.Theirs.Size = UDim2.fromScale(ratio(active.Opponent), 1)
		if active.EndsAt then
			local left = math.max(0, active.EndsAt - os.clock())
			refs.Clock.Text = string.format("%d:%02d", math.floor(left / 60), math.floor(left % 60))
		else
			refs.Clock.Text = "Ready"
		end
	end)
	player.CharacterRemoving:Connect(function()
		if active then
			task.delay(3, function()
				if active and not player.Character then
					hide()
				end
			end)
		end
	end)
end

return DuelController
