--[[
	MenuManager: owns every menu window. Menus are built lazily the first time
	they open, only one is open at a time, and Esc / gamepad B closes it.

	A menu module returns { Build = function(ctx) -> menu } where menu has:
	  Window   the Kit.Window frame
	  Close    its close button
	  OnOpen   optional (arg) -> ()   called every time it opens
	  OnClose  optional () -> ()
	To add a menu: create UI/Menus/<Name>.lua and add it to MENUS below.
]]

local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local AdminConfig = require(game:GetService("ReplicatedStorage").Shared.Config.Admins)

local MenuManager = {}

local MENUS = { "Shop", "Pets", "Inventory", "Rebirth", "Upgrades", "Areas", "Codes", "Gifts", "Trophies", "Settings", "Egg", "Admin", "Skills", "Hats", "Suits", "Mutate", "Trade" }

local controllers, Kit
local root: Frame
local dim: TextButton
local blur: BlurEffect
local modules: { [string]: any } = {}
local built: { [string]: any } = {}
local current: string? = nil
local busy = false

function MenuManager:IsOpen(name: string?): boolean
	if name then
		return current == name
	end
	return current ~= nil
end

function MenuManager:Current(): string?
	return current
end

local function getMenu(name: string)
	if built[name] then
		return built[name]
	end
	local module = modules[name]
	if not module then
		return nil
	end
	local ctx = {
		Controllers = controllers,
		Kit = controllers.Kit,
		Theme = controllers.Theme,
		Common = controllers.MenuCommon,
		Parent = root,
		Name = name,
		Close = function()
			MenuManager:Close()
		end,
	}
	local menu = module.Build(ctx)
	menu.Close.Activated:Connect(function()
		MenuManager:Close()
	end)
	built[name] = menu
	return menu
end

MenuManager.ClosedAt = 0

function MenuManager:Close()
	if not current or busy then
		return
	end
	local menu = built[current]
	current = nil
	self.ClosedAt = os.clock() -- the same Circle press must not also dodge (DodgeController)
	if menu.OnClose then
		task.spawn(menu.OnClose)
	end
	local window = menu.Window
	local scale = window:FindFirstChild("OpenScale") :: UIScale
	Kit.Tween(scale, { Scale = 0.85 }, 0.12)
	Kit.Tween(dim, { BackgroundTransparency = 1 }, 0.15)
	Kit.Tween(blur, { Size = 0 }, 0.15)
	task.delay(0.12, function()
		if current == nil or built[current] ~= menu then
			window.Visible = false
		end
		if current == nil then
			dim.Visible = false
		end
	end)
end

function MenuManager:Open(name: string, arg: any?)
	if name == "Admin" and not game:GetService("Players").LocalPlayer:GetAttribute("NinjaAdmin") then
		return
	end
	local menu = getMenu(name)
	if not menu then
		warn("[MenuManager] unknown menu " .. name)
		return
	end
	if current and current ~= name then
		local previous = built[current]
		previous.Window.Visible = false
		if previous.OnClose then
			task.spawn(previous.OnClose)
		end
	end
	current = name
	dim.Visible = true
	Kit.Tween(dim, { BackgroundTransparency = 0.45 }, 0.15)
	Kit.Tween(blur, { Size = 12 }, 0.2)
	local window = menu.Window
	local scale = window:FindFirstChild("OpenScale") :: UIScale
	scale.Scale = 0.7
	window.Visible = true
	Kit.Tween(scale, { Scale = 1 }, 0.3, Enum.EasingStyle.Back)
	controllers.SoundController:Play("Click", 0.8, 1.15)
	if menu.OnOpen then
		task.spawn(menu.OnOpen, arg)
	end
	if controllers.HUD then
		controllers.HUD:SetBadge(name, false)
	end
end

function MenuManager:Toggle(name: string, arg: any?)
	if current == name then
		self:Close()
	else
		self:Open(name, arg)
	end
end

function MenuManager:Start(c)
	controllers = c
	Kit = c.Kit
	for _, name in ipairs(MENUS) do
		modules[name] = require(script.Parent.Menus:WaitForChild(name))
	end
	root = c.UIController:Root("Menus")
	dim = Kit.New("TextButton", {
		Name = "Dim", Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = root,
	})
	dim.Activated:Connect(function()
		self:Close()
	end)
	blur = Instance.new("BlurEffect")
	blur.Name = "MenuBlur"
	blur.Size = 0
	blur.Parent = Lighting

	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			if current then
				self:Close()
			end
			return
		end
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		-- keyboard shortcuts for the main menus
		local shortcuts = {
			[Enum.KeyCode.G] = "Shop", [Enum.KeyCode.P] = "Pets", [Enum.KeyCode.I] = "Inventory",
			[Enum.KeyCode.R] = "Rebirth", [Enum.KeyCode.U] = "Upgrades", [Enum.KeyCode.M] = "Areas", [Enum.KeyCode.T] = "Trophies",
			[Enum.KeyCode.K] = "Skills",
			[Enum.KeyCode.H] = "Hats",
			[Enum.KeyCode.N] = "Suits",
			[Enum.KeyCode.Y] = "Trade",
		}
		if input.KeyCode == AdminConfig.ToggleKey then
			shortcuts[input.KeyCode] = "Admin"
		end
		local target = shortcuts[input.KeyCode]
		if target then
			self:Toggle(target)
		end
	end)
end

return MenuManager
