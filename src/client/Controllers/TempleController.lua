--[[
	TempleController: the client side of Cursed Temple runs (TempleService). Using the
	gate in the ruined temple opens the Temple menu (pick a start floor). During a run:
	a banner for each floor, a tracker under the top bar ("Floor 12 • 5 left") with a
	Leave button, a callout when a floor is cleared (the seal is open) and when the run
	ends.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)
local Format = require(ReplicatedStorage.Shared.Util.Format)

local TempleController = {}

local controllers
local tracker: Frame? = nil
local label: TextLabel? = nil
local floorNow = 0

function TempleController:InRun(): boolean
	return tracker ~= nil
end

local function showTracker()
	if tracker then
		return
	end
	local Kit, Theme = controllers.Kit, controllers.Theme
	local root = controllers.UIController:Root("Toasts")
	local frame = Kit.Panel({
		Name = "TempleTracker", Size = UDim2.fromOffset(330, 50), Position = UDim2.new(0.5, 0, 0, 70), AnchorPoint = Vector2.new(0.5, 0),
		Color = Theme.Bg, Transparency = 0.25, StrokeColor = Theme.Red, StrokeThickness = 2.5, Radius = 12, Parent = root,
	})
	label = Kit.Label({ Text = "", TextSize = 20, Size = UDim2.new(1, -112, 1, 0), Position = UDim2.fromOffset(14, 0), StrokeThickness = 2, Parent = frame })
	Kit.Button({
		Text = "Leave", Color = "Dark", TextSize = 16, Size = UDim2.fromOffset(88, 34), Position = UDim2.new(1, -8, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Parent = frame,
		OnClick = function()
			controllers.DataController:Request("TempleLeave")
		end,
	})
	tracker = frame
end

local function hideTracker()
	if tracker then
		tracker:Destroy()
		tracker = nil
		label = nil
	end
end

local function setText(text: string)
	if label then
		label.Text = text
	end
end

local function onEvent(payload)
	local c = controllers
	local nc = c.NotificationController
	local red = Color3.fromRGB(255, 70, 60)
	if payload.Type == "Gate" then
		c.MenuManager:Open("Temple")
	elseif payload.Type == "Floor" then
		if c.MenuManager:IsOpen() then
			c.MenuManager:Close()
		end
		showTracker()
		floorNow = payload.Floor or 1
		setText(string.format("Floor %d  •  %d left", floorNow, payload.Count or 0))
		nc:Banner(
			"Floor " .. floorNow,
			if payload.Boss then "A boss guards this floor!" else string.format("Monsters Lv %d", payload.Level or 0),
			if payload.Boss then Color3.fromRGB(255, 40, 40) else red,
			2
		)
		c.SoundController:Play(if payload.Boss then "BossSpawn" else "Purchase")
	elseif payload.Type == "Left" then
		setText(string.format("Floor %d  •  %d left", floorNow, payload.Count or 0))
	elseif payload.Type == "Cleared" then
		setText(string.format("Floor %d  •  cleared!", floorNow))
		local reward = string.format("+%d Seals, +%d Shards, +%s Coins", payload.Seals or 0, payload.Shards or 0, Format.Abbrev(payload.Coins or 0))
		if payload.Last then
			nc:Callout("The Temple is Conquered!", reward, Color3.fromRGB(255, 210, 60), "Crown", 5)
			c.SoundController:Play("TierUp")
		else
			nc:Callout("Floor Cleared", reward .. (if payload.Checkpoint then "  •  Checkpoint reached!" else "") .. "\nStep on the seal to descend", red, "Oni", 3.5)
			c.SoundController:Play("Finisher")
		end
	elseif payload.Type == "End" then
		hideTracker()
		if payload.Reason == "died" then
			nc:Callout("The Temple Claims You", string.format("You fell on floor %d (deepest: %d)", payload.Floor or 0, payload.Best or 0), red, "Oni", 4)
		elseif payload.Reason == "left" then
			nc:Toast(string.format("You left the temple on floor %d", payload.Floor or 0), c.Theme.SubText, "Oni")
		end
	end
end

function TempleController:Start(c)
	controllers = c
	Net.Event("Temple").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		local ok, err = pcall(onEvent, payload)
		if not ok then
			warn("[TempleController] " .. tostring(err))
		end
	end)
end

return TempleController
