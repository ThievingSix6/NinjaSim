--[[
	Areas: all 8 zones in order. Unlock the next one (level + coin gate, same
	checks as the server), teleport to any unlocked zone, and see each boss's
	respawn timer and the enemies you'll find there.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Enemies = require(Shared.Config.Enemies)
local Format = require(Shared.Util.Format)

local Menu = {}

function Menu.Build(ctx)
	local Kit, Theme, Common = ctx.Kit, ctx.Theme, ctx.Common
	local DataController = ctx.Controllers.DataController

	local window, content, close = Kit.Window({
		Name = "Areas", Title = "Teleport", Icon = "Areas", Accent = "Blue", Size = UDim2.fromOffset(840, 560), Parent = ctx.Parent,
	})
	local list = Common.Grid(content, { List = true, Gap = 10 })

	local rows = {}
	local bossTimers: { [string]: number } = {}
	local timersFetchedAt = 0

	for _, zone in ipairs(Zones.List) do
		local color = zone.Theme.Accent
		local row = Kit.Panel({ Size = UDim2.new(1, -10, 0, 96), Paint = color, StrokeThickness = 3, Radius = 14, StripeTransparency = 0.86, LayoutOrder = zone.Index, Parent = list })
		-- numbered tile, like the references' square icon buttons
		local tile = Kit.Panel({
			Size = UDim2.fromOffset(70, 70), Position = UDim2.new(0, 12, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
			Paint = "Ink", Stripes = false, StrokeThickness = 3, Radius = 12, ZIndex = 3, Parent = row,
		})
		local number = Kit.Label({
			Text = tostring(zone.Index), Font = Theme.FontBig, TextSize = 44, Color = color:Lerp(Theme.White, 0.35),
			XAlign = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 4, StrokeThickness = 4, Parent = tile,
		})
		local lock = Kit.Icon(tile, "Lock", { Size = UDim2.fromOffset(46, 46), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 5 })
		Kit.Label({ Text = zone.Name, Font = Theme.FontTitle, TextSize = 28, Size = UDim2.new(0.6, 0, 0, 32), Position = UDim2.fromOffset(96, 6), ZIndex = 3, StrokeThickness = 3.5, Parent = row })
		local names = {}
		for _, camp in ipairs(zone.Camps) do
			local def = Enemies.Get(camp.Enemy)
			table.insert(names, (if def then def.Name else camp.Enemy) .. " Lv" .. camp.Level)
		end
		Kit.Label({ Text = table.concat(names, "  •  "), TextSize = 14, Scaled = true, MaxTextSize = 14, Size = UDim2.new(1, -370, 0, 18), Position = UDim2.fromOffset(96, 40), ZIndex = 3, StrokeThickness = 2, Parent = row })
		local bossDef = Enemies.Get(zone.Boss.Enemy)
		Kit.Icon(row, "Oni", { Size = UDim2.fromOffset(24, 24), Position = UDim2.fromOffset(94, 62), ZIndex = 3 })
		local bossLabel = Kit.Label({ Text = "", TextSize = 15, Color = Color3.fromRGB(255, 226, 226), Scaled = true, MaxTextSize = 15, Size = UDim2.new(1, -396, 0, 22), Position = UDim2.fromOffset(122, 63), ZIndex = 3, StrokeThickness = 2, Parent = row })
		local req = Kit.New("Frame", {
			BackgroundTransparency = 1, Size = UDim2.fromOffset(110, 64), Position = UDim2.new(1, -176, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5),
			ZIndex = 3, Name = "Req", Parent = row,
		})
		Kit.List(Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center).Parent = req
		local reqLevel = Kit.Label({ Text = "", TextSize = 20, XAlign = Enum.TextXAlignment.Right, Size = UDim2.new(1, 0, 0, 26), ZIndex = 4, LayoutOrder = 1, StrokeThickness = 2.5, Parent = req })
		local costTag, setCost = Common.PriceTag(req, "Coins", "", { Size = UDim2.new(1, 0, 0, 26), TextSize = 20, Align = Enum.HorizontalAlignment.Right, ZIndex = 4, LayoutOrder = 2 })
		local button
		button = Kit.Button({
			Text = "Teleport", Icon = "Areas", Color = "Blue", TextSize = 19, IconSize = 30, Gap = 4, Size = UDim2.fromOffset(152, 54),
			Position = UDim2.new(1, -12, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), ZIndex = 3, Parent = row,
			OnClick = function()
				local data = DataController:Get()
				if not data then
					return
				end
				if data.Zones[zone.Id] then
					if DataController:Request("Teleport", zone.Id) then
						ctx.Close()
					end
				elseif DataController:Request("UnlockZone", zone.Id) then
					ctx.Controllers.SoundController:Play("TierUp")
					ctx.Controllers.NotificationController:Banner(zone.Name, "New area unlocked!", color, 2.4)
				end
			end,
		})
		rows[zone.Id] = {
			Row = row, Color = color, Number = number, CostTag = costTag, Lock = lock, ReqLevel = reqLevel, SetCost = setCost, Req = req,
			Button = button, Boss = bossLabel, BossName = if bossDef then bossDef.Name else zone.Boss.Enemy,
		}
	end

	local function refresh()
		local data = DataController:Get()
		if not data then
			return
		end
		local here = data.LastZone
		for _, zone in ipairs(Zones.List) do
			local r = rows[zone.Id]
			local unlocked = data.Zones[zone.Id] == true
			local previous = Zones.List[zone.Index - 1]
			local nextUp = not unlocked and (previous == nil or data.Zones[previous.Id] == true)
			local api = Kit.Api(r.Button)
			r.Number.Visible = unlocked or nextUp
			r.Lock.Visible = not r.Number.Visible
			if unlocked then
				Kit.Paint(r.Row, r.Color)
				r.Req.Visible = false
				r.CostTag.Visible = false
				api.SetText(if zone.Id == here then "Here" else "Teleport")
				api.SetIcon("Areas")
				api.SetColor("Blue")
				api.SetEnabled(true)
			else
				local levelOk = data.Level >= zone.Level
				local coinsOk = data.Coins >= zone.Cost
				Kit.Paint(r.Row, if nextUp then r.Color else "Slate")
				r.Req.Visible = true
				r.ReqLevel.Text = "Level " .. zone.Level
				r.ReqLevel.TextColor3 = if levelOk then Theme.Green else Theme.Red
				r.CostTag.Visible = true
				r.SetCost(Format.Abbrev(zone.Cost), if coinsOk then Theme.Gold else Theme.Red)
				api.SetText(if nextUp then "Unlock" else "Locked")
				api.SetIcon(if nextUp then "Check" else "Lock")
				api.SetColor(if nextUp then "Green" else "Red")
				api.SetEnabled(not nextUp or (levelOk and coinsOk))
			end
			local t = bossTimers[zone.Id]
			local left = if t then math.max(0, t - (os.clock() - timersFetchedAt)) else nil
			r.Boss.Text = r.BossName .. " (Lv " .. zone.Boss.Level .. ")" .. (if left == nil then "" elseif left <= 0 then "  •  ACTIVE NOW" else "  •  spawns in " .. Format.Time(left))
		end
	end

	local open = false
	for _, key in ipairs({ "Zones", "Level", "LastZone", "Coins" }) do
		DataController:OnChange(key, function()
			if window.Visible then
				refresh()
			end
		end)
	end

	return {
		Window = window,
		Close = close,
		OnOpen = function()
			open = true
			refresh()
			local ok, timers = DataController:Request("BossTimers")
			if ok and type(timers) == "table" then
				bossTimers = timers
				timersFetchedAt = os.clock()
			end
			-- live countdown while open
			while open and window.Visible do
				refresh()
				task.wait(1)
			end
		end,
		OnClose = function()
			open = false
		end,
	}
end

return Menu
