--[[
	Client bootstrap. Builds the controller registry and starts everything in
	dependency order. Every controller gets the registry, so any module can
	reach another as controllers.<Name>.

	To add a controller: create Controllers/<Name>.lua with a :Start(controllers)
	method and add it to ORDER below.
]]

local Players = game:GetService("Players")

local Controllers = script.Parent:WaitForChild("Controllers")
local UI = script.Parent:WaitForChild("UI")

local controllers: { [string]: any } = {
	Kit = require(UI.Kit),
	Theme = require(UI.Theme),
	MenuCommon = require(UI.MenuCommon),
}

local ORDER = {
	{ "DataController", Controllers }, -- first: must be listening for the initial save snapshot
	{ "UIController", Controllers },
	{ "SoundController", Controllers },
	{ "CameraController", Controllers },
	{ "NotificationController", Controllers },
	{ "EffectsController", Controllers },
	{ "AnimationController", Controllers },
	{ "MenuManager", UI },
	{ "HUD", UI },
	{ "Overlays", UI },
	{ "CombatController", Controllers },
	{ "DodgeController", Controllers },
	{ "LockOnController", Controllers },
	{ "SkillController", Controllers },
	{ "SkillBar", UI },
	{ "UltimateController", Controllers },
	{ "UltimateBar", UI },
	{ "TradeController", Controllers },
	{ "DuelController", Controllers },
	{ "PartyController", Controllers },
	{ "TempleController", Controllers },
	{ "MovementController", Controllers },
	{ "NunchakuController", Controllers },
	{ "EnemyUIController", Controllers },
	{ "BossController", Controllers },
	{ "PetController", Controllers },
	{ "LootController", Controllers },
	{ "LightingController", Controllers },
	{ "WorldController", Controllers },
	{ "GuideController", Controllers },
}

-- Friendly loading curtain until the save arrives.
local curtain = Instance.new("ScreenGui")
curtain.Name = "Loading"
curtain.IgnoreGuiInset = true
curtain.DisplayOrder = 100
curtain.ResetOnSpawn = false
local Kit, Theme = controllers.Kit, controllers.Theme
local back = Kit.New("Frame", { BackgroundColor3 = Theme.Bg, Size = UDim2.fromScale(1, 1), Parent = curtain })
Kit.Label({
	Text = "NINJA SIM", Font = Theme.FontTitle, TextSize = 72, Color = Theme.Accent, XAlign = Enum.TextXAlignment.Center,
	Size = UDim2.new(1, 0, 0, 90), Position = UDim2.fromScale(0, 0.38), StrokeThickness = 3, Parent = back,
})
local status = Kit.Label({
	Text = "Loading your ninja...", Font = Theme.FontBold, TextSize = 22, Color = Theme.SubText, XAlign = Enum.TextXAlignment.Center,
	Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromScale(0, 0.52), Parent = back,
})
curtain.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
task.spawn(function()
	local dots = 0
	local started = os.clock()
	while curtain.Parent and not (controllers.DataController and controllers.DataController:IsReady()) do
		dots = dots % 3 + 1
		status.Text = "Loading your ninja" .. string.rep(".", dots)
		if os.clock() - started > 20 then
			-- something is wrong on the server; say so instead of spinning forever
			status.Text = "Still loading... if this doesn't finish, check the Output window for [NinjaSim] errors"
		end
		task.wait(0.4)
	end
end)

for _, entry in ipairs(ORDER) do
	local name, parent = entry[1], entry[2]
	local ok, module = pcall(require, parent:WaitForChild(name))
	if ok then
		controllers[name] = module
	else
		warn(string.format("[NinjaSim] failed to load %s: %s", name, tostring(module)))
	end
end

for _, entry in ipairs(ORDER) do
	local name = entry[1]
	local module = controllers[name]
	if module and module.Start then
		local ok, err = pcall(module.Start, module, controllers)
		if not ok then
			warn(string.format("[NinjaSim] %s failed to start: %s", name, tostring(err)))
		end
	end
end

controllers.DataController:OnReady(function()
	Kit.Tween(back, { BackgroundTransparency = 1 }, 0.6)
	for _, d in ipairs(back:GetDescendants()) do
		if d:IsA("TextLabel") then
			Kit.Tween(d, { TextTransparency = 1 }, 0.6)
		elseif d:IsA("UIStroke") then
			Kit.Tween(d, { Transparency = 1 }, 0.6)
		end
	end
	task.wait(0.7)
	curtain:Destroy()
end)
