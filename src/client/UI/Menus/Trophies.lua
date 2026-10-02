--[[
	Trophies: long-term goals with Spirit Shard rewards (Config/Achievements).
	Rows are built once and re-sorted on refresh: ready to claim first, then
	closest to done, claimed last.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Achievements = require(Shared.Config.Achievements)
local Format = require(Shared.Util.Format)

local Menu = {}

local STAT_PAINT = {
	Kills = "Red", Bosses = "Purple", Eggs = "Sky", Coins = "Gold", Level = "Orange",
	Tier = "Blue", Zones = "Green", Rebirths = "Pink", Katanas = "Cyan",
}

function Menu.Build(ctx)
	local Kit, Theme, Common = ctx.Kit, ctx.Theme, ctx.Common
	local DataController = ctx.Controllers.DataController

	local window, content, close = Kit.Window({
		Name = "Trophies", Title = "Trophies", Icon = "Trophy", Accent = "Gold", Size = UDim2.fromOffset(760, 540), Parent = ctx.Parent,
	})
	local strip = Kit.Panel({ Size = UDim2.new(1, 0, 0, 40), Color = Theme.Well, StrokeThickness = 2.5, Radius = 10, Parent = content })
	local _, setDone = Kit.ProgressBar({ Size = UDim2.new(0, 220, 0, 24), Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Paint = "Gold", TextSize = 15, ZIndex = 2, Parent = strip })
	local summary = Kit.Label({ Text = "", TextSize = 18, RichText = true, XAlign = Enum.TextXAlignment.Right, Size = UDim2.new(1, -250, 1, 0), Position = UDim2.fromOffset(240, 0), ZIndex = 2, StrokeThickness = 2, Parent = strip })
	local list = Common.Grid(content, { List = true, Gap = 8, Size = UDim2.new(1, 0, 1, -50), Position = UDim2.fromOffset(0, 50), Name = "List" })

	local rows = {}
	local refresh
	local claimAll = Kit.Button({
		Name = "ClaimAll", Text = "CLAIM ALL", Color = "Green", TextSize = 22, Size = UDim2.fromOffset(152, 44),
		Position = UDim2.new(1, -68, 0.5, -2), AnchorPoint = Vector2.new(1, 0.5), ZIndex = 6, Radius = 10,
		Parent = window:FindFirstChild("Header"),
		OnClick = function()
			local ok, message = DataController:Request("ClaimAllAchievements")
			if ok then
				ctx.Controllers.SoundController:Play("Purchase")
				ctx.Controllers.NotificationController:Toast(tostring(message), Theme.Gold, "Trophy")
			end
			refresh()
		end,
	})

	for _, def in ipairs(Achievements.List) do
		local row = Kit.Panel({ Size = UDim2.new(1, -10, 0, 70), Color = Theme.Panel2, StrokeThickness = 3, Radius = 12, Name = def.Id, Parent = list })
		local tile = Kit.Panel({
			Size = UDim2.fromOffset(58, 58), Position = UDim2.new(0, 6, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
			Paint = STAT_PAINT[def.Stat] or "Gold", StrokeThickness = 2.5, Radius = 10, ZIndex = 2, Parent = row,
		})
		local icon = Kit.Icon(tile, def.Icon, { Size = UDim2.fromScale(0.86, 0.86), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 4 })
		Kit.Label({ Text = def.Name, TextSize = 21, Size = UDim2.new(1, -440, 0, 26), Position = UDim2.fromOffset(74, 8), StrokeThickness = 2.5, Parent = row })
		Kit.Label({ Text = Achievements.Describe(def), TextSize = 14, Color = Theme.SubText, Scaled = true, MaxTextSize = 14, Size = UDim2.new(1, -440, 0, 20), Position = UDim2.fromOffset(74, 38), StrokeThickness = 1.5, Parent = row })
		local _, setBar = Kit.ProgressBar({ Size = UDim2.fromOffset(170, 24), Position = UDim2.new(1, -350, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Paint = "Gold", TextSize = 13, Radius = 8, Parent = row })
		local reward = Kit.Panel({ Size = UDim2.fromOffset(62, 32), Position = UDim2.new(1, -170, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Paint = "Cyan", Stripes = false, StrokeThickness = 2.5, Radius = 8, Parent = row })
		Common.PriceTag(reward, "Shards", "+" .. def.Shards, { Size = UDim2.fromScale(1, 1), TextSize = 17, ZIndex = 3 })
		local button = Kit.Button({
			Name = "Claim", Text = "CLAIM", Color = "Green", TextSize = 18, Size = UDim2.fromOffset(92, 44), Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Parent = row,
			OnClick = function()
				local ok, message = DataController:Request("ClaimAchievement", def.Id)
				if ok then
					ctx.Controllers.SoundController:Play("Purchase")
					ctx.Controllers.NotificationController:Toast(tostring(message), Theme.Gold, "Trophy")
				else
					ctx.Controllers.NotificationController:Toast(tostring(message or "Not finished yet"), Theme.Red, "Lock")
				end
				refresh()
			end,
		})
		rows[def.Id] = { Row = row, Tile = tile, Icon = icon, SetBar = setBar, Button = button, Stroke = row:FindFirstChildOfClass("UIStroke") }
	end

	function refresh()
		local data = DataController:Get()
		if not data then
			return
		end
		local claimed = data.Achievements or {}
		local done, ready = 0, 0
		for _, def in ipairs(Achievements.List) do
			local r = rows[def.Id]
			local progress = Achievements.Progress(def, data)
			local ratio = math.clamp(progress / def.Target, 0, 1)
			local api = Kit.Api(r.Button)
			if claimed[def.Id] then
				done += 1
				r.SetBar(1, "Complete")
				api.SetText("DONE")
				api.SetColor("Grey")
				api.SetEnabled(true)
				r.Row.BackgroundTransparency = 0.45
				r.Row.LayoutOrder = 2000 + def.Order
				if r.Stroke then
					r.Stroke.Color = Theme.Ink
				end
			else
				r.SetBar(ratio, Format.Abbrev(math.min(progress, def.Target)) .. " / " .. Format.Abbrev(def.Target))
				r.Row.BackgroundTransparency = 0
				if ratio >= 1 then
					ready += 1
					api.SetText("CLAIM")
					api.SetColor("Green")
					api.SetEnabled(true)
					r.Row.LayoutOrder = def.Order
					if r.Stroke then
						r.Stroke.Color = Theme.Gold
					end
				else
					api.SetText(math.floor(ratio * 100) .. "%")
					api.SetColor("Green")
					api.SetEnabled(false)
					-- closest to finishing floats up
					r.Row.LayoutOrder = 100 + math.floor((1 - ratio) * 1000) + def.Order
					if r.Stroke then
						r.Stroke.Color = Theme.Ink
					end
				end
			end
		end
		Kit.Api(claimAll).SetEnabled(ready > 0)
		setDone(done / #Achievements.List, done .. " / " .. #Achievements.List)
		summary.Text = if ready > 0 then '<font color="#82ec46">' .. ready .. " ready to claim!</font>" else "Finish goals to earn Spirit Shards"
	end

	local pending = false
	for _, key in ipairs({ "Achievements", "Lifetime", "Level", "Rebirths", "Tier", "Zones", "Katanas" }) do
		DataController:OnChange(key, function()
			if window.Visible and not pending then
				pending = true
				task.delay(0.4, function()
					pending = false
					refresh()
				end)
			end
		end)
	end

	return { Window = window, Close = close, OnOpen = refresh }
end

return Menu
