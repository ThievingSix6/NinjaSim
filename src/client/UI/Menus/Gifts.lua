--[[
	Gifts: free rewards for time played this session. Each card counts down to
	its gift (red timer button), then turns into a pulsing green CLAIM button. The server checks the timer
	(GiftService); this menu only reads the GiftStart / GiftsClaimed attributes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Gifts = require(Shared.Config.Gifts)
local Format = require(Shared.Util.Format)

local Menu = {}

local localPlayer = Players.LocalPlayer

local CARD_PAINT = { "Sky", "Blue", "Green", "Pink", "Purple", "Orange", "Red", "Gold" }

function Menu.Build(ctx)
	local Kit, Theme = ctx.Kit, ctx.Theme
	local DataController = ctx.Controllers.DataController

	local window, content, close = Kit.Window({
		Name = "Gifts", Title = "Free Gifts", Icon = "Gift", Accent = "Blue", Size = UDim2.fromOffset(652, 548), Parent = ctx.Parent,
	})
	-- daily streak strip
	local strip = Kit.Panel({ Size = UDim2.new(1, 0, 0, 40), Color = Theme.Well, StrokeThickness = 2.5, Radius = 10, Name = "StreakStrip", Parent = content })
	Kit.Icon(strip, "Flame", { Size = UDim2.fromOffset(36, 36), Position = UDim2.new(0, 6, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 2 })
	local streak = Kit.Label({
		Text = "Play for a few minutes to unlock free gifts!", TextSize = 18, RichText = true,
		Size = UDim2.new(1, -54, 1, 0), Position = UDim2.fromOffset(46, 0), ZIndex = 2, StrokeThickness = 2, Name = "Streak", Parent = strip,
	})
	local grid = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -52), Position = UDim2.fromOffset(0, 52), Name = "Grid", Parent = content })
	Kit.New("UIGridLayout", {
		CellSize = UDim2.fromOffset(142, 190), CellPadding = UDim2.fromOffset(12, 14), SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = grid,
	})

	local cards = {}
	local refresh

	local function claim(index: number, quiet: boolean?): boolean
		local ok, message = DataController:Request("ClaimGift", index)
		if ok then
			ctx.Controllers.SoundController:Play("Purchase")
			ctx.Controllers.NotificationController:Toast(tostring(message or "Gift claimed!"), Theme.Gold, Gifts.List[index].Art)
			local card = cards[index]
			if card then
				card.Scale.Scale = 1.12
				Kit.Tween(card.Scale, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)
			end
		elseif not quiet then
			ctx.Controllers.NotificationController:Toast(tostring(message or "Not ready yet"), Theme.Red, "Clock")
		end
		refresh()
		return ok
	end

	-- CLAIM ALL in the header, like the daily rewards reference
	local claimAll = Kit.Button({
		Name = "ClaimAll", Text = "CLAIM ALL", Color = "Gold", TextSize = 22, Size = UDim2.fromOffset(152, 44),
		Position = UDim2.new(1, -68, 0.5, -2), AnchorPoint = Vector2.new(1, 0.5), ZIndex = 6, Radius = 10,
		Parent = window:FindFirstChild("Header"),
		OnClick = function()
			local any = false
			for i in ipairs(Gifts.List) do
				local c = cards[i]
				if c and c.State == "ready" then
					any = claim(i, true) or any
				end
			end
			if not any then
				ctx.Controllers.NotificationController:Toast("No gifts are ready yet", Theme.SubText, "Clock")
			end
		end,
	})

	for i, gift in ipairs(Gifts.List) do
		local paint = CARD_PAINT[(i - 1) % #CARD_PAINT + 1]
		local frame = Kit.Panel({
			Size = UDim2.fromOffset(142, 190), Paint = paint, StrokeThickness = 3, Radius = 14, LayoutOrder = i,
			StripeTransparency = 0.84, Name = "Gift" .. i, Parent = grid,
		})
		local scale = Kit.New("UIScale", { Parent = frame })
		Kit.Label({
			Text = "GIFT " .. i, Font = Theme.FontBig, TextSize = 25, XAlign = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 6), ZIndex = 4, StrokeThickness = 3, Name = "Title", Parent = frame,
		})
		Kit.Rays(frame, { Size = UDim2.fromOffset(130, 130), Position = UDim2.new(0.5, 0, 0, 76), ZIndex = 2, Transparency = 0.5 })
		local icon = Kit.Icon(frame, gift.Art or gift.Icon, {
			Size = UDim2.fromOffset(78, 78), Position = UDim2.new(0.5, 0, 0, 76), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 3,
		})
		local reward = Kit.Label({
			Text = "", TextSize = 16, Scaled = true, MaxTextSize = 16, Wrapped = true, XAlign = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, -12, 0, 36), Position = UDim2.fromOffset(6, 112), ZIndex = 4, StrokeThickness = 2, Parent = frame,
		})
		local button = Kit.Button({
			Name = "Claim", Text = "LOCKED", Icon = "Clock", Color = "Red", TextSize = 18, IconSize = 24, Gap = 4,
			Size = UDim2.new(1, -16, 0, 34), Position = UDim2.new(0, 8, 1, -42), ZIndex = 4, Parent = frame,
			OnClick = function()
				claim(i)
			end,
		})
		if i == #Gifts.List then
			local tag = Kit.Label({
				Text = "BEST!", Font = Theme.FontBig, TextSize = 24, Color = Theme.Gold, Rotation = 14, XAlign = Enum.TextXAlignment.Center,
				Size = UDim2.fromOffset(70, 28), Position = UDim2.new(1, 8, 0, -12), AnchorPoint = Vector2.new(1, 0), ZIndex = 9,
				StrokeThickness = 3.5, Parent = frame,
			})
			Kit.New("UIScale", { Parent = tag })
		end
		cards[i] = { Frame = frame, Icon = icon, Reward = reward, Button = button, Scale = scale, State = "" }
	end

	local function setState(card, state: string, text: string)
		local api = Kit.Api(card.Button)
		api.SetText(text)
		if card.State == state then
			return
		end
		card.State = state
		if state == "claimed" then
			api.SetColor("Grey")
			api.SetIcon("Check")
		elseif state == "ready" then
			api.SetColor("Green")
			api.SetIcon("Gift")
		else
			api.SetColor("Red")
			api.SetIcon("Clock")
		end
		local dim = state == "claimed"
		card.Frame.BackgroundTransparency = if dim then 0.45 else 0
		if card.Icon:IsA("ImageLabel") then
			card.Icon.ImageTransparency = if dim then 0.45 else 0
		elseif card.Icon:IsA("TextLabel") then
			card.Icon.TextTransparency = if dim then 0.45 else 0
		end
	end

	function refresh()
		local data = DataController:Get()
		if data and data.Daily and data.Daily.Streak > 0 then
			local tomorrow = Gifts.DailyFor(data.Daily.Streak + 1)
			streak.Text = string.format(
				'Daily streak: <font color="#ffd640">Day %d</font>     Tomorrow: <font color="#9cf0ff">%s</font>',
				data.Daily.Streak, Gifts.Describe(tomorrow, data.Level)
			)
		end
		local start = localPlayer:GetAttribute("GiftStart")
		local claimed = Gifts.ParseClaimed(localPlayer:GetAttribute("GiftsClaimed"))
		local elapsed = if start then workspace:GetServerTimeNow() - start else 0
		local pulse = 1 + math.sin(os.clock() * 6) * 0.04
		local ready = 0
		for i, gift in ipairs(Gifts.List) do
			local card = cards[i]
			card.Reward.Text = string.upper(Gifts.Describe(gift, if data then data.Level else 1))
			local remaining = gift.Minutes * 60 - elapsed
			if claimed[i] then
				setState(card, "claimed", "CLAIMED")
				card.Scale.Scale = 1
			elseif remaining <= 0 then
				setState(card, "ready", "CLAIM")
				card.Scale.Scale = pulse
				ready += 1
			else
				setState(card, "locked", Format.Time(remaining))
				card.Scale.Scale = 1
			end
		end
		Kit.Api(claimAll).SetColor(if ready > 0 then "Gold" else "Dark")
	end

	local generation = 0
	return {
		Window = window,
		Close = close,
		OnOpen = function()
			generation += 1
			local mine = generation
			refresh()
			task.spawn(function()
				while mine == generation do
					task.wait(0.2)
					if mine == generation then
						refresh()
					end
				end
			end)
		end,
		OnClose = function()
			generation += 1
		end,
	}
end

return Menu
