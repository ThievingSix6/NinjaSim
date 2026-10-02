--[[
	Spirit Upgrades: permanent upgrades bought with Spirit Shards. Each row shows
	current -> next value, cost and a level pip bar. Unlocks at Rebirth 1.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Upgrades = require(Shared.Config.Upgrades)
local Format = require(Shared.Util.Format)

local Menu = {}

local function valueText(upgrade, level: number): string
	local v = upgrade.Per * level
	if upgrade.Id == "Speed" then
		return "+" .. v
	end
	return Format.Percent(1 + v)
end

local ROW_PAINT = { "Blue", "Gold", "Red", "Sky", "Purple", "Orange", "Green", "Pink", "Gold", "Cyan" }

function Menu.Build(ctx)
	local Kit, Theme, Common = ctx.Kit, ctx.Theme, ctx.Common
	local DataController = ctx.Controllers.DataController

	local window, content, close = Kit.Window({
		Name = "Upgrades", Title = "Spirit Upgrades", Icon = "Upgrade", Accent = "Green", Size = UDim2.fromOffset(800, 548), Parent = ctx.Parent,
	})
	-- shard balance pill + hint
	local balance = Kit.Panel({ Size = UDim2.fromOffset(250, 42), Paint = "Cyan", StrokeThickness = 3, Radius = 10, Parent = content })
	local _, setBalance = Common.PriceTag(balance, "Shards", "0", { Size = UDim2.fromScale(1, 1), TextSize = 22, ZIndex = 3 })
	local hint = Kit.Label({
		Text = "Upgrades are permanent and never reset", TextSize = 16, Color = Theme.SubText, XAlign = Enum.TextXAlignment.Right,
		Size = UDim2.new(1, -260, 0, 42), Position = UDim2.fromOffset(260, 0), StrokeThickness = 2, Parent = content,
	})
	local list = Common.Grid(content, { List = true, Gap = 8, Size = UDim2.new(1, 0, 1, -52), Position = UDim2.fromOffset(0, 52) })

	local locked = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -52), Position = UDim2.fromOffset(0, 52), Visible = false, Name = "Locked", Parent = content })
	Kit.Icon(locked, "Lock", { Size = UDim2.fromOffset(110, 110), Position = UDim2.new(0.5, 0, 0, 40), AnchorPoint = Vector2.new(0.5, 0) })
	Kit.Label({
		Text = "Rebirth once to unlock Spirit Upgrades", Font = Theme.FontTitle, TextSize = 30, XAlign = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 160), StrokeThickness = 3, Parent = locked,
	})
	Kit.Label({
		Text = "Spend Spirit Shards on boosts that last forever", TextSize = 18, Color = Theme.SubText, XAlign = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 202), StrokeThickness = 2, Parent = locked,
	})
	Kit.Button({
		Text = "Go to Rebirth", Icon = "Rebirth", Color = "Purple", TextSize = 24, IconSize = 38, Size = UDim2.fromOffset(260, 58),
		Position = UDim2.new(0.5, 0, 0, 250), AnchorPoint = Vector2.new(0.5, 0), Parent = locked,
		OnClick = function()
			ctx.Controllers.MenuManager:Open("Rebirth")
		end,
	})

	local rows = {}
	for i, upgrade in ipairs(Upgrades.List) do
		local row = Kit.Panel({ Size = UDim2.new(1, -8, 0, 70), Color = Theme.Panel2, StrokeThickness = 3, Radius = 12, LayoutOrder = upgrade.Order or i, Parent = list })
		local tile = Kit.Panel({
			Size = UDim2.fromOffset(58, 58), Position = UDim2.new(0, 6, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
			Paint = ROW_PAINT[(i - 1) % #ROW_PAINT + 1], StrokeThickness = 2.5, Radius = 10, ZIndex = 2, Parent = row,
		})
		Kit.Icon(tile, upgrade.Icon, { Size = UDim2.fromScale(0.86, 0.86), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 4 })
		Kit.Label({ Text = upgrade.Name, TextSize = 21, Size = UDim2.new(0.38, -74, 0, 26), Position = UDim2.fromOffset(74, 8), StrokeThickness = 2.5, Parent = row })
		Kit.Label({ Text = upgrade.Desc, Font = Theme.FontBody, TextSize = 13, Color = Theme.SubText, Scaled = true, MaxTextSize = 13, Size = UDim2.new(0.38, -74, 0, 28), Position = UDim2.fromOffset(74, 36), Wrapped = true, Stroke = false, Parent = row })
		local valueLabel = Kit.Label({
			Text = "", TextSize = 19, Color = Theme.Green, XAlign = Enum.TextXAlignment.Center, RichText = true,
			Size = UDim2.new(0.28, 0, 0, 26), Position = UDim2.new(0.4, 0, 0, 8), StrokeThickness = 2.5, Parent = row,
		})
		local _, setPips = Kit.ProgressBar({ Size = UDim2.new(0.28, 0, 0, 20), Position = UDim2.new(0.4, 0, 0, 38), Paint = "Cyan", TextSize = 13, Instant = true, Parent = row })
		local button
		button = Kit.Button({
			Text = "0", Icon = "Shard", Color = "Green", TextSize = 20, IconSize = 28, Size = UDim2.fromOffset(150, 50),
			Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Parent = row,
			OnClick = function()
				if DataController:Request("BuyUpgrade", upgrade.Id) then
					ctx.Controllers.SoundController:Play("Purchase")
					local s = row:FindFirstChildOfClass("UIStroke")
					if s then
						s.Color = Theme.Shard
						Kit.Tween(s, { Color = Theme.Ink }, 0.5)
					end
				end
			end,
		})
		rows[upgrade.Id] = { Value = valueLabel, SetPips = setPips, Button = button }
	end

	local function refresh()
		local data = DataController:Get()
		if not data then
			return
		end
		setBalance(Format.Commas(data.Shards))
		local unlocked = data.Rebirths >= 1
		list.Visible = unlocked
		locked.Visible = not unlocked
		hint.Visible = unlocked
		for _, upgrade in ipairs(Upgrades.List) do
			local r = rows[upgrade.Id]
			local level = data.Upgrades[upgrade.Id] or 0
			local maxed = level >= upgrade.Max
			r.Value.Text = if maxed then valueText(upgrade, level) else string.format('%s <font color="#ffffff">></font> %s', valueText(upgrade, level), valueText(upgrade, level + 1))
			r.SetPips(level / upgrade.Max, "Lv " .. level .. " / " .. upgrade.Max)
			local api = Kit.Api(r.Button)
			if maxed then
				api.SetText("MAX")
				api.SetIcon("Star")
				api.SetColor("Gold")
				api.SetEnabled(true)
			else
				local cost = Upgrades.Cost(upgrade, level)
				api.SetText(Format.Abbrev(cost))
				api.SetIcon("Shard")
				api.SetColor("Green")
				api.SetEnabled(data.Shards >= cost)
			end
		end
	end

	for _, key in ipairs({ "Upgrades", "Shards", "Rebirths" }) do
		DataController:OnChange(key, function()
			if window.Visible then
				refresh()
			end
		end)
	end

	return { Window = window, Close = close, OnOpen = refresh }
end

return Menu
