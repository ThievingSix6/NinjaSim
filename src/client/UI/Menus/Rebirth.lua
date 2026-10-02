--[[
	Rebirth: shows the requirement, Spirit Shards you'd earn, bonus before ->
	after, what resets vs what stays, and upcoming milestones. Confirms first.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Rebirth = require(Shared.Config.Rebirth)
local Format = require(Shared.Util.Format)

local Menu = {}

function Menu.Build(ctx)
	local Kit, Theme, Common = ctx.Kit, ctx.Theme, ctx.Common
	local DataController = ctx.Controllers.DataController

	local window, content, close = Kit.Window({
		Name = "Rebirth", Title = "Rebirth", Icon = "Rebirth", Accent = "Purple", Size = UDim2.fromOffset(800, 540), Parent = ctx.Parent,
	})

	-- left: before -> after, requirement bar, reward, big button
	local main = Kit.Panel({ Size = UDim2.new(0.57, -6, 1, 0), Color = Theme.Panel2, Radius = 14, Parent = content })

	local function bonusBox(position: UDim2, paint: string): (TextLabel, TextLabel)
		local caption = Kit.Label({
			Text = "", TextSize = 18, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(0.5, -40, 0, 22),
			Position = position, StrokeThickness = 2, Parent = main,
		})
		local box = Kit.Panel({
			Size = UDim2.new(0.5, -40, 0, 58), Position = position + UDim2.fromOffset(0, 24), Paint = paint, StrokeThickness = 3,
			Radius = 10, Parent = main,
		})
		local value = Kit.Label({
			Text = "", Font = Theme.FontBig, TextSize = 28, XAlign = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1),
			ZIndex = 3, StrokeThickness = 3.5, Parent = box,
		})
		return caption, value
	end
	local nowCaption, nowValue = bonusBox(UDim2.fromOffset(16, 10), "Green")
	local nextCaption, nextValue = bonusBox(UDim2.new(0.5, 24, 0, 10), "Green")
	local arrow = Kit.Panel({
		Size = UDim2.fromOffset(44, 36), Position = UDim2.new(0.5, 0, 0, 63), AnchorPoint = Vector2.new(0.5, 0.5), Paint = "Sky",
		StrokeThickness = 3, Radius = 8, Stripes = false, Parent = main,
	})
	Kit.Label({ Text = ">", Font = Theme.FontBig, TextSize = 30, XAlign = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = arrow })
	Kit.Label({
		Text = "bonus to XP, Coins and Damage", TextSize = 15, Color = Theme.SubText, XAlign = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 96), StrokeThickness = 1.5, Parent = main,
	})

	local req = Kit.Well({ Size = UDim2.new(1, -32, 0, 96), Position = UDim2.fromOffset(16, 122), Parent = main })
	Kit.Label({ Text = "Requirements:", TextSize = 20, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 6), ZIndex = 2, Parent = req })
	local reqText = Kit.Label({
		Text = "", TextSize = 16, Color = Theme.SubText, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 30), ZIndex = 2, StrokeThickness = 1.5, Parent = req,
	})
	local _, setBar = Kit.ProgressBar({
		Size = UDim2.new(1, -24, 0, 28), Position = UDim2.fromOffset(12, 56), Paint = "Orange", TextSize = 16, ZIndex = 2, Parent = req,
	})

	local earn = Kit.Panel({ Size = UDim2.new(1, -32, 0, 48), Position = UDim2.fromOffset(16, 230), Paint = "Cyan", StrokeThickness = 3, Radius = 10, Parent = main })
	Kit.Label({ Text = "You earn", TextSize = 20, Size = UDim2.new(0.4, 0, 1, 0), Position = UDim2.fromOffset(14, 0), ZIndex = 3, StrokeThickness = 2.5, Parent = earn })
	local _, setEarn = Common.PriceTag(earn, "Shards", "", {
		Size = UDim2.new(0.6, -14, 1, 0), Position = UDim2.new(0.4, 0, 0, 0), TextSize = 26, Align = Enum.HorizontalAlignment.Right, ZIndex = 3,
	})

	local function note(y: number, icon: string, text: string)
		Kit.Icon(main, icon, { Size = UDim2.fromOffset(24, 24), Position = UDim2.fromOffset(18, y) })
		Kit.Label({
			Text = text, TextSize = 14, Color = Theme.SubText, Wrapped = true, Size = UDim2.new(1, -66, 0, 24),
			Position = UDim2.fromOffset(48, y), StrokeThickness = 1.5, Parent = main,
		})
	end
	note(290, "Rebirth", "Resets Level, XP, Coins, Ninja tier and areas")
	note(316, "Check", "Keeps Shards, upgrades, pets, katanas and boosts")

	local rebirthButton
	rebirthButton = Kit.Button({
		Text = "Rebirth", Icon = "Rebirth", Color = "Green", TextSize = 32, IconSize = 44, Size = UDim2.new(1, -32, 0, 62),
		Position = UDim2.new(0, 16, 1, -74), Radius = 12, StrokeThickness = 3.5, Parent = main,
		OnClick = function()
			local data = DataController:Get()
			if not data then
				return
			end
			local shards = Balance.RebirthShards(data.Level, data.Rebirths, DataController:GetStats().ShardMult)
			Common.Confirm(ctx.Parent, "Rebirth?", "You'll go back to Level 1 in the Ninja Village and earn " .. shards .. " Spirit Shards plus a permanent bonus.", "Rebirth!", "Purple", function()
				local ok = DataController:Request("Rebirth")
				if ok then
					ctx.Close()
				end
			end)
		end,
	})

	-- right: milestones + upgrades shortcut
	local side = Kit.Panel({ Size = UDim2.new(0.43, -6, 1, 0), Position = UDim2.new(0.57, 6, 0, 0), Color = Theme.Panel2, Radius = 14, Parent = content })
	Kit.Label({ Text = "Milestones", Font = Theme.FontTitle, TextSize = 26, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 32), Position = UDim2.fromOffset(0, 8), StrokeThickness = 3, Parent = side })
	local list = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -24, 1, -118), Position = UDim2.fromOffset(12, 46), Parent = side })
	Kit.List(Enum.FillDirection.Vertical, 6).Parent = list
	local rows = {}
	for i, m in ipairs(Rebirth.Milestones) do
		local row = Kit.Panel({ Size = UDim2.new(1, 0, 0, 44), Color = Theme.Well, StrokeThickness = 2.5, Radius = 10, LayoutOrder = i, Parent = list })
		local check = Kit.Icon(row, "Lock", { Size = UDim2.fromOffset(30, 30), Position = UDim2.new(0, 6, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 3 })
		local title = Kit.Label({ Text = "Rebirth " .. m.Rebirths, TextSize = 15, Color = Theme.Purple, Size = UDim2.new(1, -46, 0, 18), Position = UDim2.fromOffset(42, 3), ZIndex = 3, StrokeThickness = 2, Parent = row })
		Kit.Label({ Text = m.Text, TextSize = 13, Size = UDim2.new(1, -46, 0, 18), Position = UDim2.fromOffset(42, 22), ZIndex = 3, StrokeThickness = 1.5, Scaled = true, MaxTextSize = 13, Parent = row })
		rows[i] = { Row = row, Check = check, Title = title, Def = m, Done = nil }
	end
	Kit.Button({
		Text = "Spirit Upgrades", Icon = "Shard", Color = "Cyan", TextSize = 20, IconSize = 32,
		Size = UDim2.new(1, -24, 0, 52), Position = UDim2.new(0, 12, 1, -62), Parent = side,
		OnClick = function()
			ctx.Controllers.MenuManager:Open("Upgrades")
		end,
	})

	local function refresh()
		local data = DataController:Get()
		local stats = DataController:GetStats()
		if not data or not stats then
			return
		end
		local required = Balance.RebirthLevelRequirement(data.Rebirths)
		local ready = data.Level >= required
		reqText.Text = if ready then "Ready to rebirth!" else "Reach Level " .. required
		reqText.TextColor3 = if ready then Theme.Green else Theme.SubText
		setBar(data.Level / required, "Level " .. data.Level .. " / " .. required)
		local shards = Balance.RebirthShards(data.Level, data.Rebirths, stats.ShardMult)
		setEarn("+" .. Format.Abbrev(if ready then shards else Balance.RebirthShards(required, data.Rebirths, stats.ShardMult)))
		nowCaption.Text = "Rebirth " .. data.Rebirths
		nextCaption.Text = "Rebirth " .. data.Rebirths + 1
		nowValue.Text = Format.Percent(1 + Balance.RebirthBonus(data.Rebirths))
		nextValue.Text = Format.Percent(1 + Balance.RebirthBonus(data.Rebirths + 1))
		Kit.Api(rebirthButton).SetEnabled(ready)
		for _, r in ipairs(rows) do
			local done = data.Rebirths >= r.Def.Rebirths
			if r.Done ~= done then
				r.Done = done
				Kit.SetIcon(r.Check, if done then "Check" else "Lock")
				if done then
					Kit.Paint(r.Row, "Green")
				else
					Kit.Paint(r.Row, { Theme.Well, Theme.Well })
				end
				r.Title.TextColor3 = if done then Theme.Text else Theme.Purple
			end
		end
	end

	for _, key in ipairs({ "Level", "Rebirths", "__Stats" }) do
		DataController:OnChange(key, function()
			if window.Visible then
				refresh()
			end
		end)
	end

	return { Window = window, Close = close, OnOpen = refresh }
end

return Menu
