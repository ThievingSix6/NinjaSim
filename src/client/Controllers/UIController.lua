--[[
	UIController: creates the screen layers every UI module draws into and keeps
	them scaled for any screen size (designed at 1280x720, scaled with UIScale).
	Also hides default Roblox chrome we replace (health bar).
]]

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local GuiService = game:GetService("GuiService")

local UIController = {}
UIController.Layers = {} :: { [string]: ScreenGui }
UIController.Scale = 1

local DESIGN = Vector2.new(1280, 720)
local UI_SIZE = 0.88 -- the whole UI a bit smaller than the design so it crowds the view less
-- extra size per layer on top of UI_SIZE: the main-screen HUD 15% smaller again (2026-10-03)
local LAYER_SIZE: { [string]: number } = { HUD = 0.85 }

-- The scale a layer is drawn at (UIController.Scale x its LAYER_SIZE).
function UIController:LayerScale(layerName: string): number
	return self.Scale * (LAYER_SIZE[layerName] or 1)
end

local function makeLayer(name: string, order: number): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	pcall(function()
		-- edge to edge on desktop; still clear of phone notches
		gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	end)
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = order
	local scale = Instance.new("UIScale")
	scale.Name = "AutoScale"
	scale.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

-- The screen in design pixels: the layer's real size divided by the UI scale.
-- Sized in offset (not scale) so that after the UIScale it covers exactly the
-- whole screen, edge to edge, whatever the aspect ratio.
local function fitRoot(layer: ScreenGui, root: Frame, scale: number)
	local size = layer.AbsoluteSize
	if size.X < 2 or size.Y < 2 then
		size = workspace.CurrentCamera.ViewportSize
	end
	root.Size = UDim2.fromOffset(math.ceil(size.X / scale), math.ceil(size.Y / scale))
end

-- A full-screen frame inside a layer that the UIScale applies to.
function UIController:Root(layerName: string): Frame
	local layer = self.Layers[layerName]
	local existing = layer:FindFirstChild("Root")
	if existing then
		return existing :: Frame
	end
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	fitRoot(layer, root, self:LayerScale(layerName))
	root.Parent = layer
	return root
end

function UIController:IsMobile(): boolean
	local UIS = game:GetService("UserInputService")
	return UIS.TouchEnabled and not UIS.KeyboardEnabled
end

function UIController:Start()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
	self.Layers.World = makeLayer("NinjaWorldFX", 0)
	self.Layers.HUD = makeLayer("NinjaHUD", 2)
	self.Layers.Menus = makeLayer("NinjaMenus", 5)
	self.Layers.Overlay = makeLayer("NinjaOverlay", 10)
	self.Layers.Toasts = makeLayer("NinjaToasts", 12)

	local function rescale()
		local camera = workspace.CurrentCamera
		local size = camera.ViewportSize
		local scale = math.clamp(math.min(size.X / DESIGN.X, size.Y / DESIGN.Y) * UI_SIZE, 0.5, 1.25)
		self.Scale = scale
		for name, layer in pairs(self.Layers) do
			local layerScale = self:LayerScale(name);
			(layer:FindFirstChild("AutoScale") :: UIScale).Scale = layerScale
			local root = layer:FindFirstChild("Root")
			if root then
				fitRoot(layer, root :: Frame, layerScale)
			end
		end
	end
	rescale()
	-- the camera object can be replaced (respawns), so follow whichever is current
	local viewportConn: RBXScriptConnection? = nil
	local function watchCamera()
		if viewportConn then
			viewportConn:Disconnect()
		end
		viewportConn = workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
		rescale()
	end
	watchCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	for _, layer in pairs(self.Layers) do
		layer:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
	end
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(rescale)
end

return UIController
