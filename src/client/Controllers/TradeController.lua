--[[
	TradeController: the client side of trading (TradeService). Keeps the open trade's
	state from the "Trade" event for the Trade menu, pops an invite card with Accept /
	Decline when someone asks to trade, opens the Trade menu when a trade starts and
	says how it ended.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)

local TradeController = {}

local controllers
local state = nil
local listeners: { () -> () } = {}

function TradeController:GetState()
	return state
end

function TradeController:OnChange(fn: () -> ())
	table.insert(listeners, fn)
end

local function changed()
	for _, fn in ipairs(listeners) do
		task.spawn(fn)
	end
end

-- The invite card: bottom right, Accept / Decline, gone after `seconds`.
local function inviteCard(fromId: number, fromName: string, seconds: number)
	local Kit, Theme = controllers.Kit, controllers.Theme
	local root = controllers.UIController:Root("Toasts")
	local old = root:FindFirstChild("TradeInvite")
	if old then
		old:Destroy()
	end
	local card = Kit.Panel({
		Name = "TradeInvite", Size = UDim2.fromOffset(330, 124), Position = UDim2.new(1, -24, 1, -260), AnchorPoint = Vector2.new(1, 1),
		Paint = { Theme.Body, Theme.BodyDark }, StrokeThickness = 3, Radius = 14, Parent = root,
	})
	Kit.Icon(card, "Friends", { Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(10, 8), ZIndex = 3 })
	Kit.Label({ Text = fromName .. " wants to trade", TextSize = 19, Wrapped = true, Size = UDim2.new(1, -70, 0, 48), Position = UDim2.fromOffset(62, 6), ZIndex = 3, StrokeThickness = 2, Parent = card })
	local function answer(accept: boolean)
		card:Destroy()
		controllers.DataController:Request("TradeRespond", fromId, accept)
	end
	Kit.Button({ Text = "Decline", Color = "Dark", TextSize = 18, Size = UDim2.fromOffset(145, 44), Position = UDim2.new(0, 10, 1, -10), AnchorPoint = Vector2.new(0, 1), ZIndex = 3, Parent = card,
		OnClick = function()
			answer(false)
		end })
	Kit.Button({ Text = "Accept", Color = "Green", TextSize = 18, Size = UDim2.fromOffset(145, 44), Position = UDim2.new(1, -10, 1, -10), AnchorPoint = Vector2.new(1, 1), ZIndex = 3, Parent = card,
		OnClick = function()
			answer(true)
		end })
	task.delay(seconds, function()
		if card.Parent then
			card:Destroy()
		end
	end)
end

function TradeController:Start(c)
	controllers = c
	Net.Event("Trade").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		local nc = c.NotificationController
		if payload.Type == "Invite" then
			c.SoundController:Play("Purchase")
			inviteCard(payload.From, payload.FromName or "Someone", payload.Seconds or 30)
		elseif payload.Type == "Declined" then
			nc:Toast((payload.By or "They") .. " declined your trade", c.Theme.SubText, "Friends")
		elseif payload.Type == "State" then
			local opening = state == nil
			state = payload
			changed()
			if opening and not c.MenuManager:IsOpen("Trade") then
				c.MenuManager:Open("Trade")
			end
		elseif payload.Type == "Closed" then
			state = nil
			changed()
			if payload.Reason ~= "done" then
				nc:Toast("Trade closed: " .. tostring(payload.Reason), c.Theme.SubText, "Friends")
			end
		elseif payload.Type == "Done" then
			state = nil
			changed()
			c.SoundController:Play("TierUp")
			nc:Callout("Trade complete", "with " .. tostring(payload.Partner), c.Theme.Gold, "Friends", 3)
		end
	end)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		if state then
			state = nil
			changed()
		end
	end)
end

return TradeController
