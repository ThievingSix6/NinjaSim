--[[
	Temple: the gate of the Cursed Temple (opened by TempleController when you use the
	glowing seal in the ruined temple). Pick a floor to start on: floor 1, or any
	checkpoint (11, 21, ...) you have reached. Shows your deepest floor and what the
	floors hold.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Temple = require(Shared.Config.Temple)
local Enemies = require(Shared.Config.Enemies)

local Menu = {}

function Menu.Build(ctx)
	local Kit, Theme, Common = ctx.Kit, ctx.Theme, ctx.Common
	local DataController = ctx.Controllers.DataController

	local window, content, close = Kit.Window({
		Name = "Temple", Title = "The Cursed Temple", Icon = "Oni", Accent = "Red", Size = UDim2.fromOffset(760, 560), Parent = ctx.Parent,
	})
	local intro = Kit.Label({
		Text = "", Font = Theme.FontBody, TextSize = 16, Wrapped = true, Size = UDim2.new(1, 0, 0, 84), Stroke = false, Parent = content,
	})
	local best = Kit.Label({
		Text = "", TextSize = 22, Color = Theme.Gold, Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 88), StrokeThickness = 2.5, Parent = content,
	})
	local grid = Common.Grid(content, { CellSize = UDim2.fromOffset(160, 118), Gap = 12, Size = UDim2.new(1, 0, 1, -124), Position = UDim2.fromOffset(0, 124) })

	intro.Text = string.format(
		"Descend %d floors beneath the temple. Kill every monster on a floor to open the seal and go deeper. Monsters start at Level %d and grow stronger every floor; every %dth floor holds a boss. Dying or leaving ends the run, but checkpoints let you start deeper next time. Charms drop %dx as often down here.",
		Temple.Floors, Temple.BaseLevel, Temple.CheckpointEvery, Temple.CharmBoost
	)

	local function refresh()
		local data = DataController:Get()
		if not data then
			return
		end
		local deepest = data.TempleBest or 0
		best.Text = if deepest > 0 then string.format("Deepest floor cleared: %d / %d", deepest, Temple.Floors) else "You have not cleared a floor yet"
		for _, child in ipairs(grid:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for i, floor in ipairs(Temple.StartFloors(deepest)) do
			local card = Kit.Panel({ Paint = if floor == 1 then "Red" else "Purple", StrokeThickness = 3, Radius = 12, StripeTransparency = 0.88, LayoutOrder = i, Parent = grid })
			Kit.Label({ Text = "Floor " .. floor, Font = Theme.FontTitle, TextSize = 26, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 6), ZIndex = 3, StrokeThickness = 3, Parent = card })
			local boss = Temple.BossFor(floor + Temple.CheckpointEvery - 1)
			local bossDef = Enemies.Get(boss)
			Kit.Label({
				Text = string.format("Monsters Lv %d\nBoss: %s", Temple.Level(floor), if bossDef then bossDef.Name else boss),
				TextSize = 13, Wrapped = true, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, -10, 0, 34), Position = UDim2.fromOffset(5, 36), ZIndex = 3, StrokeThickness = 1.5, Parent = card,
			})
			Kit.Button({
				Text = "Descend", Color = "Red", TextSize = 18, Size = UDim2.new(1, -16, 0, 36), Position = UDim2.new(0.5, 0, 1, -8), AnchorPoint = Vector2.new(0.5, 1), ZIndex = 3, Parent = card,
				OnClick = function()
					if DataController:Request("TempleStart", floor) then
						ctx.Close()
					end
				end,
			})
		end
	end

	DataController:OnChange("TempleBest", function()
		if window.Visible then
			refresh()
		end
	end)

	return {
		Window = window,
		Close = close,
		OnOpen = refresh,
	}
end

return Menu
