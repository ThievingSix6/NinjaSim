--[[
	CharacterService: dresses characters as their ninja tier, welds the equipped
	katana to the right hand (and claws' second model to the left), applies cosmetics (aura, trail, overhead title) and
	spawns players in their last zone. Reacts automatically to data changes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tiers = require(Shared.Config.Tiers)
local Mastery = require(Shared.Config.Mastery)
local Katanas = require(Shared.Config.Katanas)
local Zones = require(Shared.Config.Zones)
local Shop = require(Shared.Config.Shop)
local Animations = require(Shared.Config.Animations)
local Format = require(Shared.Util.Format)
local KatanaBuilder = require(Shared.Visuals.KatanaBuilder)
local OutfitBuilder = require(Shared.Visuals.OutfitBuilder)
local Particles = require(Shared.Visuals.Particles)

local CharacterService = {}

local services

local AURA_PRESETS = {
	aura_sakura = "Petals",
	aura_lightning = "Lightning",
	aura_spirit = "Spirit",
	aura_galaxy = "Galaxy",
}

local function setCollisionGroup(character: Model)
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Players"
		end
	end
end

function CharacterService:ApplyKatana(player: Player)
	local data = services.DataService:Get(player)
	local character = player.Character
	if not data or not character then
		return
	end
	local old = character:FindFirstChild("EquippedKatana")
	if old then
		old:Destroy()
	end
	local oldOffhand = character:FindFirstChild("EquippedOffhand")
	if oldOffhand then
		oldOffhand:Destroy()
	end
	local def = Katanas.Get(data.EquippedKatana) or Katanas.ById.brown_katana
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then
		return
	end
	local model = KatanaBuilder.Build(def)
	model.Name = "EquippedKatana"
	local grip = model.PrimaryPart :: BasePart
	local yOffset = if hand.Name == "Right Arm" then -hand.Size.Y / 2 + 0.1 else -hand.Size.Y * 0.25
	-- katanas tilt -30 degrees in the hand; spears set their own HoldAngle (KatanaBuilder)
	local hold = model:GetAttribute("HoldAngle")
	local offset = CFrame.new(0, yOffset, 0) * CFrame.Angles(math.rad(if type(hold) == "number" then hold else -30), 0, 0)
	model:PivotTo(hand.CFrame * offset)
	local weld = Instance.new("Weld")
	weld.Name = "KatanaGrip"
	weld.Part0 = hand
	weld.Part1 = grip
	weld.C0 = offset
	weld.Parent = grip
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Players"
		end
	end
	model:SetAttribute("KatanaId", def.Id)
	model.Parent = character
	-- dual-wielded weapons (claws): a mirrored second model in the left hand
	local offhand = KatanaBuilder.BuildOffhand(def)
	local leftHand = character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm")
	if offhand and leftHand and leftHand:IsA("BasePart") then
		offhand.Name = "EquippedOffhand"
		local leftGrip = offhand.PrimaryPart :: BasePart
		local leftY = if leftHand.Name == "Left Arm" then -leftHand.Size.Y / 2 + 0.1 else -leftHand.Size.Y * 0.25
		local leftOffset = CFrame.new(0, leftY, 0) * CFrame.Angles(math.rad(if type(hold) == "number" then hold else -30), 0, 0)
		offhand:PivotTo(leftHand.CFrame * leftOffset)
		local leftWeld = Instance.new("Weld")
		leftWeld.Name = "KatanaGrip"
		leftWeld.Part0 = leftHand
		leftWeld.Part1 = leftGrip
		leftWeld.C0 = leftOffset
		leftWeld.Parent = leftGrip
		for _, d in ipairs(offhand:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CollisionGroup = "Players"
			end
		end
		offhand:SetAttribute("KatanaId", def.Id)
		offhand.Parent = character
	elseif offhand then
		offhand:Destroy()
	end
end

function CharacterService:ApplyOutfit(player: Player)
	local data = services.DataService:Get(player)
	local character = player.Character
	if not data or not character then
		return
	end
	OutfitBuilder.Apply(character, Mastery.WornTier(data)) -- the chosen suit (Suits menu), else the rank's
	setCollisionGroup(character)
end

function CharacterService:ApplyCosmetics(player: Player)
	local data = services.DataService:Get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not data or not root then
		return
	end
	for _, name in ipairs({ "CosmeticAura", "CosmeticTrail", "TrailTop", "TrailBottom" }) do
		local existing = root:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end

	local auraId = data.Equipped.Aura
	if auraId ~= "" and AURA_PRESETS[auraId] then
		local emitter = Particles.Create(AURA_PRESETS[auraId], root)
		if emitter then
			emitter.Name = "CosmeticAura"
		end
	end

	local trailId = data.Equipped.Trail
	local trailDef = Shop.CosmeticsById[trailId]
	if trailDef then
		local top = Instance.new("Attachment")
		top.Name = "TrailTop"
		top.Position = Vector3.new(0, 0.6, 0.4)
		top.Parent = root
		local bottom = Instance.new("Attachment")
		bottom.Name = "TrailBottom"
		bottom.Position = Vector3.new(0, -1.6, 0.4)
		bottom.Parent = root
		local trail = Instance.new("Trail")
		trail.Name = "CosmeticTrail"
		trail.Attachment0 = top
		trail.Attachment1 = bottom
		trail.Lifetime = 0.45
		trail.LightEmission = 0.6
		trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		if trailId == "trail_rainbow" then
			trail.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
				ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 60)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 255, 120)),
				ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 160, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 80, 255)),
			})
		else
			trail.Color = ColorSequence.new(trailDef.Color)
		end
		trail.Parent = root
	end
	self:UpdateNameplate(player)
end

-- Overhead plate: title (if any) + "Lv X  Tier Name", visible to everyone.
function CharacterService:UpdateNameplate(player: Player)
	local data = services.DataService:Get(player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not data or not head then
		return
	end
	local gui = head:FindFirstChild("Nameplate") :: BillboardGui?
	if not gui then
		local g = Instance.new("BillboardGui")
		g.Name = "Nameplate"
		g.Size = UDim2.fromOffset(220, 60)
		g.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
		g.AlwaysOnTop = false
		g.MaxDistance = 90
		g.LightInfluence = 0

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.Size = UDim2.new(1, 0, 0.42, 0)
		title.Font = Enum.Font.GothamBlack
		title.TextScaled = true
		title.TextStrokeTransparency = 0.4
		title.Parent = g

		local info = Instance.new("TextLabel")
		info.Name = "Info"
		info.BackgroundTransparency = 1
		info.Position = UDim2.new(0, 0, 0.42, 0)
		info.Size = UDim2.new(1, 0, 0.58, 0)
		info.Font = Enum.Font.LuckiestGuy
		info.TextScaled = true
		info.TextStrokeTransparency = 0.2
		info.Parent = g
		g.Parent = head
		gui = g
	end
	local tier = Tiers.Get(data.Tier)
	local titleDef = Shop.CosmeticsById[data.Equipped.Title]
	local titleLabel = (gui :: BillboardGui):FindFirstChild("Title") :: TextLabel
	local infoLabel = (gui :: BillboardGui):FindFirstChild("Info") :: TextLabel
	titleLabel.Text = if titleDef then "« " .. titleDef.Name .. " »" else ""
	titleLabel.TextColor3 = if titleDef then titleDef.Color else Color3.new(1, 1, 1)
	local rebirthText = if data.Rebirths > 0 then "  ✦" .. Format.Abbrev(data.Rebirths) else ""
	infoLabel.Text = "Lv " .. Format.Abbrev(data.Level) .. "  " .. tier.Name .. rebirthText
	infoLabel.TextColor3 = tier.Color
end

function CharacterService:RefreshAll(player: Player)
	self:ApplyOutfit(player)
	self:ApplyKatana(player)
	self:ApplyCosmetics(player)
	services.StatService:Refresh(player)
end

function CharacterService:SpawnAtZone(player: Player, zoneId: string?)
	local data = services.DataService:Get(player)
	local character = player.Character
	if not data or not character then
		return
	end
	local zone = Zones.Get(zoneId or data.LastZone)
	if not zone or not data.Zones[zone.Id] then
		zone = Zones.List[1]
	end
	services.ZoneService:MarkTeleported(player)
	local offset = Vector3.new(math.random(-6, 6), 3, math.random(-10, 10))
	local ground = services.ZoneService:GroundHeight(zone.Spawn)
	character:PivotTo(CFrame.new(Vector3.new(zone.Spawn.X, ground, zone.Spawn.Z) + offset) * CFrame.Angles(0, -math.pi / 2, 0))
	player:SetAttribute("Zone", zone.Id)
end

-- Roblox's Ninja Animation Package for walking, running, jumping and so on (R15 only).
-- The default Animate script reloads an animation whenever its AnimationId changes.
local function applyNinjaAnimations(character: Model, humanoid: Humanoid)
	if not Animations.Enabled or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return
	end
	local animate = character:WaitForChild("Animate", 5)
	if not animate then
		return
	end
	for setName, anims in pairs(Animations.Sets) do
		local set = animate:FindFirstChild(setName)
		for animName, id in pairs(anims) do
			local anim = set and set:FindFirstChild(animName)
			if anim and anim:IsA("Animation") then
				pcall(function()
					anim.AnimationId = "rbxassetid://" .. id
				end)
			end
		end
	end
	-- restart whatever is playing so the new idle/walk shows straight away
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			track:Stop(0)
		end
	end
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	-- give the avatar a moment to finish loading accessories before we strip them
	if not player:HasAppearanceLoaded() then
		local loaded = false
		local conn = player.CharacterAppearanceLoaded:Connect(function()
			loaded = true
		end)
		local t = os.clock()
		while not loaded and os.clock() - t < 4 do
			task.wait(0.1)
		end
		conn:Disconnect()
	end
	if player.Character ~= character then
		return
	end
	-- after the appearance, which brings the player's own animations with it
	task.spawn(applyNinjaAnimations, character, humanoid)
	-- wait for data (first spawn happens while the profile is loading)
	local t = os.clock()
	while not services.DataService:Get(player) and os.clock() - t < 30 and player.Parent do
		task.wait(0.2)
	end
	if not services.DataService:Get(player) then
		return
	end
	CharacterService:SpawnAtZone(player)
	CharacterService:RefreshAll(player)
	humanoid.Health = humanoid.MaxHealth
end

function CharacterService:Init(registry)
	services = registry
end

function CharacterService:Start()
	services.DataService:AddFlushHook(function(player, keys)
		if keys.Tier or keys.Suit or keys.BestTier then
			self:ApplyOutfit(player)
		end
		if keys.EquippedKatana then
			self:ApplyKatana(player)
		end
		if keys.Equipped then
			self:ApplyCosmetics(player)
		elseif keys.Level or keys.Tier or keys.Rebirths then
			self:UpdateNameplate(player)
		end
	end)

	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in ipairs(Players:GetPlayers()) do
		hook(player)
	end
end

return CharacterService
