--[[
	LootController: the client side of hat loot (server: LootService).

	Drops are personal: only the player who earned one is told about it (HatLoot
	"Drop"), so this draws it locally: the hat spinning above the ground inside a
	Diablo-style light pillar in its rarity colour, with a sound. Walking within
	Hats.PickupRadius asks the server to pick it up (the server checks the distance);
	after Hats.AutoCollect seconds the server hands it over anyway. "Looted" shows the
	pickup toast with the hat's name in its rarity colour. "Proc" and "Heal" show the
	on-hit procs and life steal.

	Charms (Config/Charms) come the same way with `Charm` in the payload instead of
	`Hat`: the charm object turns in its pillar, and the Hexfire Torch's drop gets a
	screen-wide callout of its own.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Hats = require(Shared.Config.Hats)
local Charms = require(Shared.Config.Charms)
local CharmBuilder = require(Shared.Visuals.CharmBuilder)
local Skills = require(Shared.Config.Skills)
local HatBuilder = require(Shared.Visuals.HatBuilder)
local Net = require(Shared.Net)

local LootController = {}

local player = Players.LocalPlayer
local controllers
local folder: Folder? = nil
type Drop = { Id: number, Hat: any, Position: Vector3, Model: Model?, Holder: Folder, Born: number, AskedAt: number }
local drops: { [number]: Drop } = {}

-- pillar height and sound per rarity (Common .. Mythic)
local PILLAR = { 9, 16, 26, 44, 70 }

local function world(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "HatDrops"
	f.Parent = workspace
	folder = f
	return f
end

local function fxPart(parent: Instance, size: Vector3, cf: CFrame, color: Color3, transparency: number, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Transparency = transparency
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function sound(name: string, volume: number?, pitch: number?)
	if controllers and controllers.SoundController then
		controllers.SoundController:Play(name, volume, pitch)
	end
end

-- What a drop looks like: { Color, Index (1-5 pillar size), Build(scale) }.
local function lookOf(payload)
	if type(payload.Charm) == "table" and Charms.Valid(payload.Charm) then
		local charm = payload.Charm
		local rarity = Charms.Rarity(charm.R)
		return {
			Color = rarity.Color, Index = math.min(5, rarity.Index + 1),
			Build = function(scale: number)
				return CharmBuilder.Build(charm, scale * 0.9)
			end,
		}
	end
	if type(payload.Hat) == "table" and Hats.Valid(payload.Hat) then
		local hat = payload.Hat
		local rarity = Hats.Rarity(hat.R)
		return {
			Color = rarity.Color, Index = rarity.Index,
			Build = function(scale: number)
				return HatBuilder.Build(hat, scale)
			end,
		}
	end
	return nil
end

local function spawnDrop(payload)
	local look = lookOf(payload)
	if not look or typeof(payload.Position) ~= "Vector3" or type(payload.Id) ~= "number" then
		return
	end
	local hat = payload.Hat or payload.Charm
	local rarity = { Index = look.Index }
	local color = look.Color
	local pos = payload.Position
	local holder = Instance.new("Folder")
	holder.Name = "HatDrop" .. payload.Id

	-- the light pillar: a beam from the ground up, a bright core and a ground ring
	local height = PILLAR[rarity.Index] or 12
	local base = fxPart(holder, Vector3.new(0.2, 0.2, 0.2), CFrame.new(pos), color, 1)
	local a0 = Instance.new("Attachment")
	a0.Parent = base
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, height, 0)
	a1.Parent = base
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 3.2 + rarity.Index * 0.4
	beam.Width1 = 1
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(color)
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(0.6, 0.6), NumberSequenceKeypoint.new(1, 1) })
	beam.Segments = 2
	beam.Parent = base
	fxPart(holder, Vector3.new(height * 0.7, 0.35, 0.35), CFrame.new(pos + Vector3.new(0, height * 0.35, 0)) * CFrame.Angles(0, 0, math.pi / 2), color, 0.35, Enum.PartType.Cylinder)
	local ringPart = fxPart(holder, Vector3.new(0.12, 5, 5), CFrame.new(pos + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.pi / 2), color, 0.45, Enum.PartType.Cylinder)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 10 + rarity.Index * 2
	light.Brightness = 1.5
	light.Parent = ringPart
	if rarity.Index >= 4 then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Color = ColorSequence.new(color)
		sparkle.LightEmission = 1
		sparkle.Size = NumberSequence.new(0.35, 0)
		sparkle.Lifetime = NumberRange.new(1.2, 2)
		sparkle.Speed = NumberRange.new(3, 7)
		sparkle.SpreadAngle = Vector2.new(15, 15)
		sparkle.Rate = 12
		sparkle.EmissionDirection = Enum.NormalId.Top
		sparkle.Parent = ringPart
	end

	-- the hat itself, a little bigger than worn, bobbing and turning
	local model = look.Build(1.6)
	if model then
		model:PivotTo(CFrame.new(pos + Vector3.new(0, 2.4, 0)))
		model.Parent = holder
	end
	holder.Parent = world()

	-- drop-in: the pillar grows out of the ground
	beam.Width0 = 0
	TweenService:Create(beam, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Width0 = 3.2 + rarity.Index * 0.4 }):Play()
	if controllers and controllers.EffectsController then
		controllers.EffectsController:Shockwave(pos + Vector3.new(0, 0.2, 0), color, 6 + rarity.Index, 0.6)
	end
	sound("EggHatch", 0.6 + rarity.Index * 0.08, 1.5 - rarity.Index * 0.12)
	if rarity.Index >= 4 then
		sound("TierUp", 0.6, 1.3)
	end

	drops[payload.Id] = { Id = payload.Id, Hat = hat, Position = pos, Model = model, Holder = holder, Born = os.clock(), AskedAt = 0 }
end

local function removeDrop(id: number, flyTo: BasePart?)
	local drop = drops[id]
	if not drop then
		return
	end
	drops[id] = nil
	local holder = drop.Holder
	local model = drop.Model
	if model and flyTo and model.PrimaryPart then
		-- the hat zips into the player
		local start = model:GetPivot()
		local t0 = os.clock()
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local a = math.min(1, (os.clock() - t0) / 0.35)
			if not flyTo.Parent or not model.Parent then
				conn:Disconnect()
				holder:Destroy()
				return
			end
			model:PivotTo(start:Lerp(flyTo.CFrame + Vector3.new(0, 1.5, 0), a * a))
			if a >= 1 then
				conn:Disconnect()
				holder:Destroy()
			end
		end)
	else
		holder:Destroy()
	end
end

local function onCharmLooted(charm, salvaged: boolean)
	if salvaged or not Charms.Valid(charm) then
		return
	end
	local rarity = Charms.Rarity(charm.R)
	local size = Charms.Size(charm)
	local nc = controllers.NotificationController
	local sub = rarity.Name .. " " .. size.Name .. "  -  Inventory (I)"
	if charm.S then
		sub = Charms.Lines(charm)[1][1] .. "  -  Inventory (I)"
	end
	nc:Callout(Charms.Name(charm), sub, rarity.Color, Charms.Icon(charm), if charm.U or charm.S then 6 else 3.5)
	sound(if charm.U or rarity.Index >= 3 then "TierUp" else "Purchase", 0.8, 1.1)
	if charm.U and controllers.EffectsController then
		controllers.EffectsController:Flash(rarity.Color, 0.4)
		controllers.EffectsController:CharacterBurst(Charms.Hexfire.Color, true)
	end
	if controllers.HUD and controllers.HUD.SetBadge then
		controllers.HUD:SetBadge("Inventory", true)
	end
end

local function onLooted(payload)
	local hat = payload.Hat
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if type(payload.Id) == "number" then
		removeDrop(payload.Id, root)
	end
	if type(payload.Charm) == "table" then
		onCharmLooted(payload.Charm, payload.Salvaged == true)
		return
	end
	if type(hat) ~= "table" or not Hats.Valid(hat) then
		return
	end
	local rarity = Hats.Rarity(hat.R)
	local name = Hats.Name(hat)
	local nc = controllers.NotificationController
	if payload.Salvaged then
		return -- the server already said storage was full
	end
	nc:Callout(name, rarity.Name .. " Hat" .. (if rarity.Index >= 4 then "  -  equip it in Hats (H)" else ""), rarity.Color, "Crown", if rarity.Index >= 4 then 4.5 else 3)
	sound("Purchase", 0.7, 1 + rarity.Index * 0.08)
	if controllers.HUD and controllers.HUD.SetBadge then
		controllers.HUD:SetBadge("Hats", true)
	end
end

local function onProc(payload)
	if typeof(payload.Position) ~= "Vector3" then
		return
	end
	local def = Skills.Get(payload.Skill)
	local color = if def then def.Color else Color3.new(1, 0.6, 0.2)
	local fx = controllers.EffectsController
	fx:Shockwave(payload.Position, color, 9, 0.5)
	fx:Pillar(payload.Position, color, 14, 0.5)
	if payload.Caster == player.UserId and def then
		local camera = workspace.CurrentCamera
		if camera then
			local screen, onScreen = camera:WorldToViewportPoint(payload.Position + Vector3.new(0, 7, 0))
			if onScreen then
				fx:FloatText(def.Name .. "!", Hats.Rarity("Legendary").Color, Vector2.new(screen.X, screen.Y), 26)
			end
		end
	end
end

local function onHeal(payload)
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if head and type(payload.Amount) == "number" then
		controllers.EffectsController:DamageNumber(head.Position + Vector3.new(0, 2, 0), payload.Amount, false, Color3.fromRGB(120, 255, 120))
	end
end

-- Distance check for walking over drops; spin and bob the hats.
local lastCheck = 0
local function step()
	local now = os.clock()
	for id, drop in pairs(drops) do
		if now - drop.Born > Hats.AutoCollect + 5 then
			removeDrop(id) -- the server should have handed it over by now
		elseif drop.Model and drop.Model.Parent then
			local t = now - drop.Born
			drop.Model:PivotTo(CFrame.new(drop.Position + Vector3.new(0, 2.4 + math.sin(t * 2.4) * 0.35, 0)) * CFrame.Angles(0, t * 1.6, 0))
		end
	end
	if now - lastCheck < 0.15 then
		return
	end
	lastCheck = now
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	for id, drop in pairs(drops) do
		local flat = Vector3.new(root.Position.X - drop.Position.X, 0, root.Position.Z - drop.Position.Z)
		if flat.Magnitude <= Hats.PickupRadius and now - drop.AskedAt > 1 then
			drop.AskedAt = now
			task.spawn(function()
				controllers.DataController:Request("PickupHat", id)
			end)
		end
	end
end

-- Test hook: the drops currently on the ground ({ id = { Hat, Position } }).
function LootController:Drops()
	return drops
end

function LootController:Start(c)
	controllers = c
	Net.Event("HatLoot").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		local ok, err = pcall(function()
			if payload.Kind == "Drop" then
				spawnDrop(payload)
			elseif payload.Kind == "Looted" then
				onLooted(payload)
			elseif payload.Kind == "Proc" then
				onProc(payload)
			elseif payload.Kind == "Heal" then
				onHeal(payload)
			end
		end)
		if not ok then
			warn("[LootController] " .. tostring(err))
		end
	end)
	RunService.Heartbeat:Connect(step)
end

return LootController
