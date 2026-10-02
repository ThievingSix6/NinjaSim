--[[
	SkillController: skill hotkeys and casting (Config/Skills).

	Keys 1-4 (gamepad LB, RB, Y, LT; the HUD skill bar for touch) cast the skill
	in that slot. The client checks its own cooldown, aims (nearest enemy in reach,
	else where the camera looks; dashes go where you are moving), turns the
	character, plays the effects right away (SkillEffects) and asks the server
	("CastSkill"), which decides what is hit. Hits come back as SkillHits:
	damage numbers, sparks and flinches. Other players' casts arrive as SkillCast.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Skills = require(Shared.Config.Skills)
local Mastery = require(Shared.Config.Mastery)
local Net = require(Shared.Net)
local SkillEffects = require(script.Parent:WaitForChild("SkillEffects"))

local SkillController = {}
SkillController.Keys = {
	{ Enum.KeyCode.One, Enum.KeyCode.ButtonL1 },
	{ Enum.KeyCode.Two, Enum.KeyCode.ButtonR1 },
	{ Enum.KeyCode.Three, Enum.KeyCode.ButtonY },
	{ Enum.KeyCode.Four, Enum.KeyCode.ButtonL2 },
}
SkillController.KeyText = { "1", "2", "3", "4" }
SkillController.PadText = { "LB", "RB", "Y", "LT" }

local controllers
local player = Players.LocalPlayer
local readyAt: { [string]: number } = {}
local totals: { [string]: number } = {}
local nextAny = 0
local castListeners: { (number, string) -> () } = {}
local lastHitSound = 0

local function getRoot(): (BasePart?, Humanoid?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil, nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?, humanoid
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function cameraLook(): Vector3
	local camera = workspace.CurrentCamera
	local look = if camera then flat(camera.CFrame.LookVector) else Vector3.zero
	return if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
end

local function nearestEnemy(root: BasePart, range: number): Vector3?
	local best, bestDist = nil, range
	for _, model in ipairs(CollectionService:GetTagged("Enemy")) do
		if model:IsA("Model") and not model:GetAttribute("Dead") and model.PrimaryPart then
			local d = flat(model.PrimaryPart.Position - root.Position).Magnitude
			if d < bestDist then
				best, bestDist = model.PrimaryPart.Position, d
			end
		end
	end
	return best
end

-- Where a skill goes: dashes follow the stick / keys, attacks the nearest enemy in reach.
local function aim(def, root: BasePart, humanoid: Humanoid): Vector3
	local moving = flat(humanoid.MoveDirection)
	if def.Id == "wind_step" or def.Id == "smoke_bomb" then
		return if moving.Magnitude > 0.1 then moving.Unit else cameraLook()
	end
	local reach = (def.Range or def.Length or def.Radius or 20) + 4
	local target = nearestEnemy(root, reach)
	if target then
		local to = flat(target - root.Position)
		if to.Magnitude > 0.5 then
			return to.Unit
		end
	end
	if moving.Magnitude > 0.1 and def.Kind == "Mobility" then
		return moving.Unit
	end
	return cameraLook()
end

-- Seconds left and total cooldown for the skill in `slot` (0, 0 when ready / empty).
function SkillController:GetCooldown(slot: number): (number, number)
	local data = controllers.DataController:Get()
	local id = data and data.SkillSlots and data.SkillSlots[slot]
	if not id or id == "" then
		return 0, 0
	end
	local left = (readyAt[id] or 0) - os.clock()
	return math.max(0, left), totals[id] or 0
end

function SkillController:OnCast(fn: (number, string) -> ())
	table.insert(castListeners, fn)
end

function SkillController:Cast(slot: number): boolean
	local data = controllers.DataController:Get()
	if not data or not data.SkillSlots then
		return false
	end
	local id = data.SkillSlots[slot]
	local def = Skills.Get(id)
	if not def or not data.Skills[def.Id] then
		controllers.NotificationController:Toast("Slot " .. slot .. " is empty. Pick a skill in Skills (K)!", controllers.Theme.Purple, "Shuriken")
		return false
	end
	local root, humanoid = getRoot()
	if not root or not humanoid then
		return false
	end
	local now = os.clock()
	if now < (readyAt[def.Id] or 0) or now < nextAny then
		controllers.SoundController:Play("Error")
		return false
	end
	local level = data.Skills[def.Id]
	local cooldown = Skills.Cooldown(def, level)
	readyAt[def.Id] = now + cooldown
	totals[def.Id] = cooldown
	nextAny = now + Skills.GlobalCooldown

	local dir = aim(def, root, humanoid)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	local ctx = {
		Character = player.Character, Root = root, Dir = dir, Origin = root.Position, Def = def, Level = level, Local = true,
	}
	SkillEffects:Start(ctx)
	for _, fn in ipairs(castListeners) do
		task.spawn(fn, slot, def.Id)
	end
	task.spawn(function()
		local ok, result = controllers.DataController:Request("CastSkill", slot, dir)
		if ok and type(result) == "table" then
			ctx.Info = result.Info
			ctx.Elapsed = os.clock() - now
			SkillEffects:Result(ctx, result.Info)
		else
			-- refused (out of sync): let the player try again shortly
			readyAt[def.Id] = math.min(readyAt[def.Id] or 0, os.clock() + 0.6)
		end
	end)
	return true
end

local function contextFor(caster: Player?, skillId: string, level: number?)
	local def = Skills.Get(skillId) or Mastery.Get(skillId) -- skills, or suit mastery ultimates
	local character = caster and caster.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not def or not character or not root then
		return nil
	end
	local look = flat(root.CFrame.LookVector)
	return {
		Character = character, Root = root, Dir = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1),
		Origin = root.Position, Def = def, Level = level or 1, Local = caster == player,
	}
end

-- Damage-over-time ticks (by hit tag) get coloured numbers and no spark.
local DOT_COLORS: { [string]: Color3 } = {
	Burn = Color3.fromRGB(255, 150, 60),
	Bleed = Color3.fromRGB(255, 60, 90),
	Drain = Color3.fromRGB(255, 90, 120),
	Thorns = Color3.fromRGB(140, 230, 100),
	Holy = Color3.fromRGB(255, 240, 170),
	Shadow = Color3.fromRGB(180, 120, 255),
	Gravity = Color3.fromRGB(220, 120, 255),
}

local function onSkillHits(payload)
	if type(payload) ~= "table" or type(payload.Hits) ~= "table" then
		return
	end
	local mine = payload.Caster == player.UserId
	local caster = Players:GetPlayerByUserId(payload.Caster or 0)
	local ctx = contextFor(caster, payload.Skill)
	local fx = controllers.EffectsController
	local anyCrit, kills = false, 0
	for _, hit in ipairs(payload.Hits) do
		controllers.AnimationController:HitEnemy(hit.Uid)
		local center = hit.Position + Vector3.new(0, (hit.Height or 5) * 0.45, 0)
		if mine then
			local dot = if type(payload.Tag) == "string" then DOT_COLORS[payload.Tag] else nil
			fx:DamageNumber(hit.Position + Vector3.new(0, (hit.Height or 5) * 0.75, 0), hit.Damage, hit.Crit, dot)
			if not dot then
				fx:HitSpark(center, if hit.Crit then Color3.fromRGB(255, 210, 60) else (ctx and ctx.Def.Color or Color3.new(1, 1, 1)), hit.Crit)
			end
			anyCrit = anyCrit or hit.Crit
			if hit.Killed then
				kills += 1
			end
		else
			fx:HitSpark(center, Color3.new(1, 1, 1), false)
		end
		if ctx then
			SkillEffects:Hit(ctx, hit, payload.Tag)
		end
	end
	if mine and os.clock() - lastHitSound > 0.08 then
		lastHitSound = os.clock()
		controllers.SoundController:Play(if anyCrit then "Crit" else "Hit")
		if #payload.Hits >= 4 or kills >= 3 then
			controllers.CameraController:Shake(math.min(0.15 + #payload.Hits * 0.02, 0.5))
		end
	end
end

function SkillController:Start(c)
	controllers = c
	SkillEffects:Init(c)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if c.MenuManager and c.MenuManager:IsOpen() then
			return
		end
		for slot, keys in ipairs(SkillController.Keys) do
			if input.KeyCode == keys[1] or input.KeyCode == keys[2] then
				self:Cast(slot)
				return
			end
		end
	end)

	Net.Event("SkillHits").OnClientEvent:Connect(onSkillHits)
	Net.Event("SkillCast").OnClientEvent:Connect(function(payload)
		-- our own casts play from SkillController:Cast; our procs (SkillService:CastAt) come here
		if type(payload) ~= "table" or (payload.Player == player and not payload.Proc) then
			return
		end
		local ctx = contextFor(payload.Player, payload.Skill, payload.Level)
		if not ctx then
			return
		end
		if payload.Proc then
			ctx.Proc = true
			ctx.Local = false -- a proc never moves the caster
		end
		if typeof(payload.Dir) == "Vector3" then
			ctx.Dir = payload.Dir
		end
		if typeof(payload.Origin) == "Vector3" then
			ctx.Origin = payload.Origin
		end
		ctx.Info = payload.Info
		SkillEffects:Start(ctx)
		SkillEffects:Result(ctx, payload.Info or {})
	end)

	-- a fresh character starts with no cooldowns showing stale state
	player.CharacterAdded:Connect(function()
		nextAny = 0
	end)
end

return SkillController
