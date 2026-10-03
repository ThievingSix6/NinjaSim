--[[
	Hire: hired ninjas (Config/Hires, CompanionService). Hire one for Coins once you
	reach its level, pick who fights beside you (one at a time) or send them home, and
	open their own paper doll and charm grid (Inventory). Keyboard shortcut: J.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Hires = require(Shared.Config.Hires)
local Charms = require(Shared.Config.Charms)
local Format = require(Shared.Util.Format)
local EnemyBuilder = require(Shared.Visuals.EnemyBuilder)

local Menu = {}

function Menu.Build(ctx)
	local Kit, Theme, Common = ctx.Kit, ctx.Theme, ctx.Common
	local C = ctx.Controllers
	local DataController = C.DataController
	local window, content, close = Kit.Window({
		Name = "Hire", Title = "Ninjas for Hire", Icon = "Friends", Accent = "Green", Size = UDim2.fromOffset(900, 580), Parent = ctx.Parent,
	})
	local list = Common.Grid(content, { List = true, Gap = 8 })
	local rows = {}
	for _, def in ipairs(Hires.List) do
		local row = Kit.Panel({ Size = UDim2.new(1, -10, 0, 104), Color = Theme.Panel2, StrokeThickness = 3, Radius = 12, LayoutOrder = def.Order, Parent = list })
		local view = Kit.New("Frame", { BackgroundColor3 = Color3.fromRGB(20, 18, 28), Size = UDim2.fromOffset(84, 92), Position = UDim2.fromOffset(6, 6), ZIndex = 2, Parent = row })
		Kit.Corner(8).Parent = view
		local ok, model = pcall(EnemyBuilder.Build, Hires.RigDef(def), 1)
		if ok and model then
			model:SetAttribute("ViewRotation", CFrame.Angles(0, math.pi, 0))
			Kit.Viewport(view, model, { Size = UDim2.fromScale(1, 1), Zoom = 1.1, ZIndex = 3 })
		end
		Kit.Label({ Text = def.Name .. "  ·  " .. def.Role, Font = Theme.FontTitle, TextSize = 22, Size = UDim2.new(1, -480, 0, 28), Position = UDim2.fromOffset(100, 6), StrokeThickness = 2.5, Parent = row })
		local info = Kit.Label({ Text = "", Font = Theme.FontBody, TextSize = 13, Color = Theme.SubText, Wrapped = true, Size = UDim2.new(1, -480, 0, 64), Position = UDim2.fromOffset(100, 36), Stroke = false, Parent = row })
		local main = Kit.Button({ Text = "", Color = "Green", TextSize = 16, Size = UDim2.fromOffset(170, 44), Position = UDim2.new(1, -190, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Parent = row,
			OnClick = function()
				local data = DataController:Get()
				if not data then
					return
				end
				if not data.Hires[def.Id] then
					local okHire, message = DataController:Request("HireNinja", def.Id)
					if okHire then
						C.SoundController:Play("TierUp")
						C.NotificationController:Toast(tostring(message), Theme.Green, "Friends")
					end
				elseif data.ActiveHire == def.Id then
					DataController:Request("SetActiveHire", "")
				else
					DataController:Request("SetActiveHire", def.Id)
					C.SoundController:Play("Equip")
				end
			end })
		local charms = Kit.Button({ Text = "Charms", Icon = "Inventory", Color = "Blue", TextSize = 16, Size = UDim2.fromOffset(160, 44), Position = UDim2.new(1, -12, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Parent = row,
			OnClick = function()
				C.MenuManager:Open("Inventory", def.Id)
			end })
		rows[def.Id] = { Info = info, Main = main, Charms = charms }
	end

	local function refresh()
		local data = DataController:Get()
		local stats = DataController:GetStats()
		if not data or not stats then
			return
		end
		for _, def in ipairs(Hires.List) do
			local r = rows[def.Id]
			local owned = data.Hires[def.Id] == true
			local hs = Hires.Stats(def, stats, Charms.Bonus(data, def.Id))
			r.Info.Text = string.format("%s Dmg  ·  %s HP  ·  %d%% Crit  ·  drops %s tokens\n%s: %s (every %ds)",
				Format.Abbrev(hs.Damage), Format.Abbrev(hs.MaxHealth), math.floor(hs.Crit * 100), def.Token, def.Skill.Name, def.Skill.Text, def.Skill.Cooldown)
			local api = Kit.Api(r.Main)
			r.Charms.Visible = owned
			if not owned then
				local price = Hires.Price(def)
				api.SetText(if data.Level < def.Level then "Level " .. def.Level else "Hire  " .. Format.Abbrev(price))
				api.SetColor("Gold")
				api.SetEnabled(data.Level >= def.Level and data.Coins >= price)
			elseif data.ActiveHire == def.Id then
				api.SetText("Send Home")
				api.SetColor("Dark")
				api.SetEnabled(true)
			else
				api.SetText("Fight With Me")
				api.SetColor("Green")
				api.SetEnabled(true)
			end
		end
	end
	for _, key in ipairs({ "Hires", "ActiveHire", "Coins", "Level", "Charms" }) do
		DataController:OnChange(key, function()
			if window.Visible then
				refresh()
			end
		end)
	end
	return { Window = window, Close = close, OnOpen = refresh }
end

return Menu
