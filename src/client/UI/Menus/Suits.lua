--[[
	Suits: pick which ninja suit you wear (any rank you have reached; the suit only
	changes your look) and see each suit's mastery (Config/Mastery): its level and
	progress, the damage bonus it gives while worn, and its four ultimates with the
	mastery level each unlocks at. Keyboard shortcut: N.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tiers = require(Shared.Config.Tiers)
local Mastery = require(Shared.Config.Mastery)

local Menu = {}

function Menu.Build(ctx)
	local Kit, Theme, Common = ctx.Kit, ctx.Theme, ctx.Common
	local DataController = ctx.Controllers.DataController

	local window, content, close = Kit.Window({
		Name = "Suits", Title = "Ninja Suits", Icon = "Star", Accent = "Gold", Size = UDim2.fromOffset(1010, 560), Parent = ctx.Parent,
	})
	local INTRO = "Wear any suit you have reached. The worn suit gains Mastery from kills: +0.5% damage per level, and its own four ultimates at 25, 50, 75 and 100 (Z X C V). Point at one to read it."
	local intro = Kit.Label({
		Text = INTRO, Font = Theme.FontBody, TextSize = 14, Color = Theme.SubText, Wrapped = true, Size = UDim2.new(1, 0, 0, 36), Stroke = false, Parent = content,
	})
	-- pointing at (or tapping) an ultimate shows what it does in the line above the list
	local function describe(chip: GuiObject, def)
		local function show()
			intro.Text = string.format("%s  (%s, Mastery %d):  %s", def.Name, def.Label, def.Level, def.Desc or "")
			intro.TextColor3 = def.Color:Lerp(Theme.White, 0.4)
		end
		chip.MouseEnter:Connect(show)
		chip.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				show()
			end
		end)
		chip.MouseLeave:Connect(function()
			intro.Text = INTRO
			intro.TextColor3 = Theme.SubText
		end)
	end
	local list = Common.Grid(content, { List = true, Gap = 8, Size = UDim2.new(1, 0, 1, -44), Position = UDim2.fromOffset(0, 44) })

	local rows = {}
	local suits = table.clone(Tiers.List)
	for _, tier in ipairs(Tiers.Secret) do
		table.insert(suits, tier)
	end
	for _, tier in ipairs(suits) do
		local row = Kit.Panel({ Size = UDim2.new(1, -8, 0, 96), Color = Theme.Panel2, StrokeThickness = 3, Radius = 12, LayoutOrder = tier.Index, Parent = list })
		local swatch = Kit.Panel({
			Size = UDim2.fromOffset(78, 78), Position = UDim2.new(0, 8, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
			Paint = { tier.Outfit.Trim, tier.Outfit.Primary }, StrokeThickness = 2.5, Radius = 10, ZIndex = 2, Parent = row,
		})
		Kit.Icon(swatch, "Katana", { Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 4 })
		local name = Kit.Label({ Text = tier.Name, TextSize = 22, Color = tier.Color:Lerp(Color3.new(1, 1, 1), 0.3), Size = UDim2.fromOffset(250, 26), Position = UDim2.fromOffset(96, 8), StrokeThickness = 2.5, Parent = row })
		local mastery = Kit.Label({ Text = "", TextSize = 16, Color = Theme.Gold, Size = UDim2.fromOffset(250, 20), Position = UDim2.fromOffset(96, 36), StrokeThickness = 2, Parent = row })
		local _, setProgress = Kit.ProgressBar({ Size = UDim2.fromOffset(240, 16), Position = UDim2.fromOffset(96, 62), Paint = "Gold", TextSize = 11, Instant = true, Parent = row })
		-- the four ultimates
		local chips = {}
		for i, def in ipairs(Mastery.ForSuit(tier.Id)) do
			local chip = Kit.Panel({
				Size = UDim2.fromOffset(86, 78), Position = UDim2.new(0, 346 + (i - 1) * 92, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
				Paint = def.Paint, StrokeThickness = 2.5, Radius = 10, ZIndex = 2, Parent = row,
			})
			local icon = Kit.Icon(chip, def.Icon, { Size = UDim2.fromOffset(34, 34), Position = UDim2.new(0.5, 0, 0, 4), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 4 })
			if icon:IsA("ImageLabel") and def.IconTint then
				icon.ImageColor3 = def.IconTint
			end
			Kit.Label({ Text = def.Name, TextSize = 12, Wrapped = true, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, -6, 0, 26), Position = UDim2.fromOffset(3, 38), ZIndex = 4, StrokeThickness = 1.5, Parent = chip })
			local tag = Kit.Label({ Text = Mastery.Keys[i] .. "  M" .. def.Level, Font = Theme.FontNumber, TextSize = 12, Color = Theme.Gold, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -15), ZIndex = 4, StrokeThickness = 1.5, Parent = chip })
			local shade = Kit.New("Frame", { BackgroundColor3 = Theme.Ink, BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = chip })
			Kit.Corner(10).Parent = shade
			chips[i] = { Shade = shade, Tag = tag, Def = def }
			describe(chip, def)
		end
		local button = Kit.Button({
			Text = "Wear", Color = "Green", TextSize = 20, Size = UDim2.fromOffset(110, 46),
			Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Parent = row,
			OnClick = function()
				if DataController:Request("SetSuit", tier.Id) then
					ctx.Controllers.SoundController:Play("Equip")
				end
			end,
		})
		rows[tier.Id] = { Row = row, Name = name, Mastery = mastery, SetProgress = setProgress, Chips = chips, Button = button, Tier = tier }
	end

	local function refresh()
		local data = DataController:Get()
		if not data then
			return
		end
		local worn = Mastery.WornTier(data)
		for _, r in pairs(rows) do
			local tier = r.Tier
			local unlocked = Tiers.Owned(data, tier)
			local level, points = Mastery.Of(data, tier.Id)
			local api = Kit.Api(r.Button)
			if not unlocked then
				r.Mastery.Text = if tier.Secret then "Secret: Seal Shop" else "Reach Level " .. tier.Level
				r.SetProgress(0, "")
				api.SetText("Locked")
				api.SetColor("Slate")
				api.SetEnabled(false)
			else
				r.Mastery.Text = string.format("Mastery %d   +%g%% damage", level, level * Mastery.DamagePerLevel * 100)
				r.SetProgress(if level >= Mastery.Max then 1 else points / Mastery.ToNext(level), if level >= Mastery.Max then "MAX" else points .. " / " .. Mastery.ToNext(level))
				if worn.Id == tier.Id then
					api.SetText("Worn")
					api.SetColor("Gold")
					api.SetEnabled(false)
				else
					api.SetText("Wear")
					api.SetColor("Green")
					api.SetEnabled(true)
				end
			end
			for _, chip in ipairs(r.Chips) do
				chip.Shade.Visible = not unlocked or level < chip.Def.Level
			end
		end
	end

	for _, key in ipairs({ "Mastery", "Suit", "Tier", "BestTier" }) do
		DataController:OnChange(key, function()
			if window.Visible then
				refresh()
			end
		end)
	end

	return { Window = window, Close = close, OnOpen = refresh }
end

return Menu
