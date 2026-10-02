--[[
	GuideController: a glowing trail from your feet to whatever you should do
	next (first dummies, the village egg, the next gate, the first boss) plus a
	bobbing marker with the distance. It follows the same goals as the HUD's
	Next Goal card, hides when you arrive, and can be turned off in Settings.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Zones = require(Shared.Config.Zones)
local Pets = require(Shared.Config.Pets)
local TableUtil = require(Shared.Util.TableUtil)

local GuideController = {}

local controllers
local localPlayer = Players.LocalPlayer
local anchor: Part
local targetAttachment: Attachment
local beam: Beam
local marker: BillboardGui
local markerText: TextLabel
local currentTarget: Vector3? = nil
local currentLabel = ""
local enabled = true

local GOLD = Color3.fromRGB(255, 205, 70)

local function rootPart(): BasePart?
	local character = localPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function nearestEnemy(from: Vector3, filter: (Model) -> boolean): Model?
	local best, bestDist = nil, math.huge
	for _, model in ipairs(CollectionService:GetTagged("Enemy")) do
		if model:IsA("Model") and not model:GetAttribute("Dead") and model.PrimaryPart and filter(model) then
			local d = (model.PrimaryPart.Position - from).Magnitude
			if d < bestDist then
				best, bestDist = model, d
			end
		end
	end
	return best
end

-- Returns a world position + label for the current goal, or nil when the goal isn't a place.
local function findTarget(data): (Vector3?, string)
	local root = rootPart()
	if not root then
		return nil, ""
	end
	local here = root.Position
	local zone = Zones.At(here)
	local fresh = data.Rebirths == 0

	if fresh and data.Lifetime.Kills < 3 then
		local dummy = nearestEnemy(here, function(m)
			return m:GetAttribute("EnemyId") == "TrainingDummy"
		end)
		if dummy then
			return dummy.PrimaryPart.Position, "Training Dummy"
		end
	end
	if TableUtil.Count(data.Pets) == 0 then
		local egg = Pets.EggsById.village_egg
		if data.Coins >= egg.Cost then
			return Pets.EggPosition(egg), egg.Name
		end
	end
	if data.Level >= Balance.RebirthLevelRequirement(data.Rebirths) then
		return nil, ""
	end
	for _, z in ipairs(Zones.List) do
		if not data.Zones[z.Id] then
			if data.Level >= z.Level and data.Coins >= z.Cost then
				return Vector3.new(z.Center.X - Zones.Spacing / 2, 0, 0), "Gate to " .. z.Name
			end
			break
		end
	end
	if fresh and data.Lifetime.BossKills == 0 and data.Level >= 7 and zone.Index == 1 then
		return Zones.WorldPosition(zone, zone.BossOffset), "Boss Arena"
	end
	if fresh and data.Level < 5 then
		local enemy = nearestEnemy(here, function(m)
			return (m:GetAttribute("Level") or 1) <= data.Level + 2 and not m:GetAttribute("IsBoss")
		end)
		if enemy then
			return enemy.PrimaryPart.Position, "Enemy"
		end
	end
	return nil, ""
end

local function setVisible(on: boolean)
	beam.Enabled = on
	marker.Enabled = on
end

local function build()
	anchor = Instance.new("Part")
	anchor.Name = "GuideTarget"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Parent = workspace
	targetAttachment = Instance.new("Attachment")
	targetAttachment.Parent = anchor

	beam = Instance.new("Beam")
	beam.Name = "GuideBeam"
	beam.Color = ColorSequence.new(GOLD, Color3.fromRGB(255, 255, 255))
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(0.15, 0.35),
		NumberSequenceKeypoint.new(0.85, 0.35), NumberSequenceKeypoint.new(1, 0.9),
	})
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Width0 = 0.7
	beam.Width1 = 0.7
	beam.Segments = 1
	beam.Attachment1 = targetAttachment
	beam.Enabled = false
	beam.Parent = anchor

	marker = Instance.new("BillboardGui")
	marker.Name = "GuideMarker"
	marker.Size = UDim2.fromOffset(200, 70)
	marker.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
	marker.AlwaysOnTop = true
	marker.LightInfluence = 0
	marker.MaxDistance = 2000
	marker.Enabled = false
	marker.Adornee = anchor
	marker.Parent = localPlayer:WaitForChild("PlayerGui")
	local Kit, Theme = controllers.Kit, controllers.Theme
	Kit.Label({ Text = "▼", Font = Theme.FontTitle, TextSize = 34, Color = GOLD, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 34), StrokeThickness = 2.5, Parent = marker })
	markerText = Kit.Label({ Text = "", Font = Theme.FontHeavy, TextSize = 16, Color = Theme.Text, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 32), StrokeThickness = 2, Parent = marker })
end

local function attachToCharacter(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not root then
		return
	end
	local a = Instance.new("Attachment")
	a.Name = "GuideAttachment"
	a.Position = Vector3.new(0, -2.4, 0)
	a.Parent = root
	beam.Attachment0 = a
end

function GuideController:Start(c)
	controllers = c
	build()
	localPlayer.CharacterAdded:Connect(attachToCharacter)
	if localPlayer.Character then
		task.spawn(attachToCharacter, localPlayer.Character)
	end
	c.DataController:OnChange("Settings", function(settings)
		enabled = settings.Guide ~= false
	end)

	-- re-evaluate the goal a few times a second; animate every frame
	task.spawn(function()
		while true do
			local data = c.DataController:Get()
			if data and enabled then
				local pos, label = findTarget(data)
				currentTarget, currentLabel = pos, label
			else
				currentTarget = nil
			end
			task.wait(0.3)
		end
	end)
	RunService.RenderStepped:Connect(function()
		local root = rootPart()
		if not currentTarget or not root or not beam.Attachment0 then
			if beam.Enabled then
				setVisible(false)
			end
			return
		end
		local distance = (Vector3.new(currentTarget.X, root.Position.Y, currentTarget.Z) - root.Position).Magnitude
		if distance < 12 then
			setVisible(false)
			return
		end
		local bob = math.sin(os.clock() * 3) * 0.6
		anchor.CFrame = CFrame.new(currentTarget + Vector3.new(0, 1 + bob, 0))
		markerText.Text = currentLabel .. "  •  " .. math.floor(distance) .. "m"
		-- pulse the beam so it reads as "go here"
		local pulse = 0.55 + math.sin(os.clock() * 4) * 0.15
		beam.Width0 = pulse
		beam.Width1 = pulse
		if not beam.Enabled then
			setVisible(true)
		end
	end)
end

return GuideController
