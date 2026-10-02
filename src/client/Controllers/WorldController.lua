--[[
	WorldController: client side of the world.
	  Zone gates: open (non-colliding, faded, prompt hidden) for zones you've
	  unlocked. The server still enforces locked zones independently.
	  Prompts: egg stands open the Egg menu; gates unlock the next zone.
]]

local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)

local WorldController = {}

local controllers

local function applyGate(gate: Instance)
	if not gate:IsA("BasePart") then
		return
	end
	local data = controllers.DataController:Get()
	local zoneId = gate:GetAttribute("ZoneId")
	local open = data ~= nil and zoneId ~= nil and data.Zones[zoneId] == true
	gate.CanCollide = not open
	gate.Transparency = if open then 1 else 0.2
	for _, child in ipairs(gate:GetChildren()) do
		if child:IsA("SurfaceGui") or child:IsA("ProximityPrompt") then
			(child :: any).Enabled = not open
		end
	end
end

local function applyAllGates()
	for _, gate in ipairs(CollectionService:GetTagged("ZoneGate")) do
		applyGate(gate)
	end
end

function WorldController:Start(c)
	controllers = c

	CollectionService:GetInstanceAddedSignal("ZoneGate"):Connect(applyGate)
	c.DataController:OnChange("Zones", applyAllGates)
	c.DataController:OnReady(applyAllGates)

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local parent = prompt.Parent
		if not parent then
			return
		end
		if prompt.Name == "HatchPrompt" then
			local eggId = parent:GetAttribute("EggId")
			if eggId then
				c.MenuManager:Open("Egg", eggId)
			end
		elseif prompt.Name == "MutatePrompt" then
			c.MenuManager:Open("Mutate")
		elseif prompt.Name == "UnlockPrompt" then
			local zoneId = parent:GetAttribute("ZoneId")
			local zone = zoneId and Zones.Get(zoneId)
			if not zone then
				return
			end
			if c.DataController:Request("UnlockZone", zone.Id) then
				c.SoundController:Play("TierUp")
				c.NotificationController:Banner(zone.Name, "New area unlocked!", zone.Theme.Accent, 2.4)
				c.EffectsController:CharacterBurst(zone.Theme.Accent, true)
			end
		end
	end)
end

return WorldController
