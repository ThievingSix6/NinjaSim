--[[
	AnimationController: procedural animation with no animation assets.

	Players: the weapon combos (Config/Combo, posed with Util/Pose) are blended
	over whatever the Animator played this frame (the default walk/idle) and fades
	back into it. It is written through Motor6D.C0 (C0 * pose * Transform⁻¹), which
	the Animator never touches, so it shows no matter when the Animator runs. Full body on R15
	(root, waist, neck, arms, elbows, wrists, legs); R6 folds the missing elbow,
	wrist and waist joints into the joints it has. Spear moves also turn and twirl the
	spear in the hand through its grip weld (applyGrip).

	Enemies: one loop animates every nearby enemy rig (walk cycle from velocity,
	idle bob, attack wind-up/strike, hit recoil). A defeated enemy is swapped for a
	local ragdoll copy (ball-socket joints, knocked away from the player) that fades
	out after a moment; past MAX_RAGDOLLS at once the rest topple over instead.
	Anchored training dummies wobble instead. A rig whose parts haven't streamed in
	yet is retried until they have.
]]

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Balance = require(ReplicatedStorage.Shared.Config.Balance)
local Combo = require(ReplicatedStorage.Shared.Config.Combo)
local Pose = require(ReplicatedStorage.Shared.Util.Pose)

local AnimationController = {}
AnimationController.EnemiesByUid = {} :: { [number]: any }

-- ===== Player combo =====
-- pose joint(s) -> { part, motor }. R6 folds several pose joints into one motor.
local R15_RIG = {
	{ "LowerTorso", "Root", { "Root" } },
	{ "UpperTorso", "Waist", { "Waist" } },
	{ "Head", "Neck", { "Neck" } },
	{ "RightUpperArm", "RightShoulder", { "RightShoulder" } },
	{ "RightLowerArm", "RightElbow", { "RightElbow" } },
	{ "RightHand", "RightWrist", { "RightWrist" } },
	{ "LeftUpperArm", "LeftShoulder", { "LeftShoulder" } },
	{ "LeftLowerArm", "LeftElbow", { "LeftElbow" } },
	{ "LeftHand", "LeftWrist", { "LeftWrist" } },
	{ "RightUpperLeg", "RightHip", { "RightHip" }, true },
	{ "RightLowerLeg", "RightKnee", { "RightKnee" }, true },
	{ "LeftUpperLeg", "LeftHip", { "LeftHip" }, true },
	{ "LeftLowerLeg", "LeftKnee", { "LeftKnee" }, true },
}
local R6_RIG = {
	{ "HumanoidRootPart", "RootJoint", { "Root", "Waist" } },
	{ "Torso", "Neck", { "Neck" } },
	{ "Torso", "Right Shoulder", { "RightShoulder", "RightElbow", "RightWrist" } },
	{ "Torso", "Left Shoulder", { "LeftShoulder", "LeftElbow", "LeftWrist" } },
	{ "Torso", "Right Hip", { "RightHip" }, true },
	{ "Torso", "Left Hip", { "LeftHip" }, true },
}

-- Motor: the joint (Motor6D, or the AnimationConstraint that newer Roblox avatars
-- use for their joints). C0 is the joint's own offset in its parent part: Motor6D.C0,
-- or the CFrame of an AnimationConstraint's Attachment0.
type Joint = { Motor: Instance, Attach: Attachment?, Joints: { string }, Rot: CFrame, Leg: boolean, C0: CFrame }
type Rig = { Joints: { Joint }, R6: boolean }

local rigs: { [Model]: Rig } = setmetatable({}, { __mode = "k" }) :: any
local swings: { [Model]: any } = {}
local warnedRig = false

local function findJoint(character: Model, partName: string, jointName: string): Instance?
	local part = character:FindFirstChild(partName)
	local joint = part and part:FindFirstChild(jointName)
	if joint and (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then
		return joint
	end
	-- some rigs keep their joints elsewhere (or in the other part of the pair)
	for _, d in ipairs(character:GetDescendants()) do
		if d.Name == jointName and (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) then
			return d
		end
	end
	return nil
end

local function jointFrame(j: Joint): CFrame
	return if j.Attach then j.Attach.CFrame else (j.Motor :: Motor6D).C0
end

local function setJointFrame(j: Joint, cf: CFrame)
	if j.Attach then
		j.Attach.CFrame = cf
	else
		(j.Motor :: Motor6D).C0 = cf
	end
end

local function getRig(character: Model): Rig?
	local cached = rigs[character]
	if cached and cached.Joints[1] and cached.Joints[1].Motor.Parent then
		return cached
	end
	local r6 = character:FindFirstChild("UpperTorso") == nil
	local joints = {}
	local kinds = {}
	for _, entry in ipairs(if r6 then R6_RIG else R15_RIG) do
		local motor = findJoint(character, entry[1], entry[2])
		local attach = if motor and motor:IsA("AnimationConstraint") then motor.Attachment0 else nil
		if motor and (motor:IsA("Motor6D") or attach) then
			local j = { Motor = motor, Attach = attach, Joints = entry[3], Leg = entry[4] == true } :: any
			-- the rig's own C0, remembered on the joint so a rebuilt cache never
			-- picks up a posed one
			local c0 = motor:GetAttribute("NinjaC0")
			if typeof(c0) ~= "CFrame" then
				c0 = jointFrame(j)
				motor:SetAttribute("NinjaC0", c0)
			end
			-- pose angles are in character space; a joint whose C0 is turned (R6)
			-- needs them turned into its own frame
			j.C0 = c0
			j.Rot = c0 - c0.Position
			table.insert(joints, j)
			kinds[motor.ClassName] = true
		end
	end
	if #joints == 0 then
		if not warnedRig then
			warnedRig = true
			local found = {}
			for _, d in ipairs(character:GetDescendants()) do
				if d:IsA("JointInstance") or d:IsA("Constraint") then
					table.insert(found, d.ClassName .. " " .. d.Name)
				end
			end
			warn("[NinjaSim] No joints to animate the combo on " .. character.Name .. "; found: " .. table.concat(found, ", "))
		end
		return nil
	end
	local rig = { Joints = joints, R6 = r6 }
	rigs[character] = rig
	if character == Players.LocalPlayer.Character then
		local list = {}
		for k in pairs(kinds) do
			table.insert(list, k)
		end
		print(string.format("[NinjaSim] Combo animates %d %s joints (%s)", #joints, if r6 then "R6" else "R15", table.concat(list, ", ")))
	end
	return rig
end

-- Plays combo move `index` (1-4, or a move table such as Combo.HeavyMove) on
-- `character` over `duration` seconds. `lunge` (local player only) steps the character
-- forward during the strike, then lets it glide on `Follow` studs after the hit.
function AnimationController:PlaySwing(character: Model, index: number | any, duration: number, lunge: { Direction: Vector3, Studs: number, Follow: number? }?)
	local rig = getRig(character)
	if not rig then
		return
	end
	local previous = swings[character]
	local katana = character:FindFirstChild("EquippedKatana")
	local trail = katana and katana:FindFirstChild("SwingTrail", true) :: Trail?
	if previous and previous.Trail and previous.Trail ~= trail then
		previous.Trail.Enabled = false
	end
	local move = if type(index) == "table" then index else Combo.Get(index, Combo.WeaponOf(character))
	swings[character] = {
		Move = move,
		Airborne = move.Airborne == true,
		Duration = math.max(duration, 0.15),
		Elapsed = 0,
		-- start from wherever the last move was, so the combo flows
		From = if previous and previous.LastPose then Pose.Scale(previous.LastPose, previous.LastWeight) else nil,
		Rig = rig,
		Trail = trail,
		Root = character:FindFirstChild("HumanoidRootPart"),
		FreezeUntil = 0,
		Walk = previous and previous.Walk,
		Lunge = if lunge and (lunge.Studs > 0 or (lunge.Follow or 0) > 0) then { Direction = lunge.Direction, Studs = lunge.Studs, Follow = lunge.Follow or 0, Done = 0 } else nil,
	}
	if trail then
		trail.Enabled = false
	end
end

-- Cuts the character's current swing short (a dodge or jump): no more lunge, and the
-- next step ends it (trails out, pose released). A roll's own pose is left alone.
function AnimationController:CancelSwing(character: Model)
	local s = swings[character]
	if not s or s.Move.Name == "Roll" or s.Move.Name == "Backstep" then
		return
	end
	s.Lunge = nil
	s.Elapsed = math.max(s.Elapsed, s.Duration)
end

-- Double jump: a tucked front flip (Root x - turns the body forward).
local FLIP = {
	Name = "Flip",
	Trail = { 2, 2 }, -- never lights the sword trail
	Keys = {
		{
			T = 0.18, Ease = "Out", Root = { -60, 0, 0 }, Waist = { -15, 0, 0 }, Neck = { -10, 0, 0 },
			RightShoulder = { 60, 0, 25 }, RightElbow = { 70, 0, 0 }, LeftShoulder = { 60, 0, -25 }, LeftElbow = { 70, 0, 0 },
			RightHip = { 80, 0, 5 }, RightKnee = { -110, 0, 0 }, LeftHip = { 80, 0, -5 }, LeftKnee = { -110, 0, 0 },
		},
		{
			T = 0.62, Ease = "Linear", Root = { -280, 0, 0 }, Waist = { -20, 0, 0 }, Neck = { -10, 0, 0 },
			RightShoulder = { 70, 0, 20 }, RightElbow = { 80, 0, 0 }, LeftShoulder = { 70, 0, -20 }, LeftElbow = { 80, 0, 0 },
			RightHip = { 100, 0, 5 }, RightKnee = { -120, 0, 0 }, LeftHip = { 100, 0, -5 }, LeftKnee = { -120, 0, 0 },
		},
		{
			T = 0.85, Ease = "Out", Root = { -360, 0, 0 }, Waist = { -5, 0, 0 },
			RightShoulder = { 20, 0, 40 }, RightElbow = { 20, 0, 0 }, LeftShoulder = { 20, 0, -40 }, LeftElbow = { 20, 0, 0 },
			RightHip = { 30, 0, 5 }, RightKnee = { -40, 0, 0 }, LeftHip = { 20, 0, -5 }, LeftKnee = { -30, 0, 0 },
		},
	},
}

-- Flips `character` (double jump). A sword swing in progress wins.
function AnimationController:PlayFlip(character: Model, duration: number?)
	local current = swings[character]
	if current and current.Move ~= FLIP then
		return
	end
	local rig = getRig(character)
	if not rig then
		return
	end
	swings[character] = {
		Move = FLIP,
		Duration = duration or 0.5,
		Elapsed = 0,
		Rig = rig,
		Root = character:FindFirstChild("HumanoidRootPart"),
		FreezeUntil = 0,
		Airborne = true,
	}
end

-- Plays any keyframed move (Util/Pose format: { Keys = {...}, Trail = { from, to }? })
-- on `character`, e.g. a skill's cast pose. Same blending as the combo; a move with
-- a Trail lights the katana trail in that window. opts.Airborne lets the pose own
-- the legs while moving (leaps, dashes).
function AnimationController:PlayPose(character: Model, move: any, duration: number, opts: { Airborne: boolean? }?)
	local rig = getRig(character)
	if not rig or not move or not move.Keys then
		return
	end
	local previous = swings[character]
	local katana = character:FindFirstChild("EquippedKatana")
	local trail = if move.Trail then katana and katana:FindFirstChild("SwingTrail", true) :: Trail? else nil
	if previous and previous.Trail and previous.Trail ~= trail then
		previous.Trail.Enabled = false
	end
	if not move.Trail then
		move.Trail = { 2, 2 } -- stepSwings reads it; never lit
	end
	swings[character] = {
		Move = move,
		Duration = math.max(duration, 0.1),
		Elapsed = 0,
		From = if previous and previous.LastPose then Pose.Scale(previous.LastPose, previous.LastWeight) else nil,
		Rig = rig,
		Trail = trail,
		Root = character:FindFirstChild("HumanoidRootPart"),
		FreezeUntil = 0,
		Walk = previous and previous.Walk,
		Airborne = opts ~= nil and opts.Airborne == true,
	}
	if trail then
		trail.Enabled = false
	end
end

-- The move `character` is playing and how far through it is (0..1), or nil.
function AnimationController:GetSwing(character: Model): (any, number?)
	local s = swings[character]
	if not s then
		return nil, nil
	end
	return s.Move, math.clamp(s.Elapsed / s.Duration, 0, 1)
end

-- Freezes the swing for a moment when the blade lands (hit stop sells the impact).
function AnimationController:HitStop(character: Model?, seconds: number)
	local s = character and swings[character]
	if s then
		s.FreezeUntil = os.clock() + seconds
	end
end

local function applyPose(s, pose, weight: number, dt: number)
	-- how much the character is walking, eased so the legs never snap between
	-- the combo stance and the run cycle when the speed crosses the threshold
	local root = s.Root :: BasePart?
	local speed = 0
	if root then
		local v = root.AssemblyLinearVelocity
		speed = Vector3.new(v.X, 0, v.Z).Magnitude
	end
	local walking = if s.Airborne then 0 else math.clamp((speed - 2) / 6, 0, 1)
	s.Walk = if s.Walk then s.Walk + (walking - s.Walk) * math.min(1, dt * 10) else walking
	local walk = s.Walk :: number
	local rootPos = pose.RootPos
	if not s.Airborne then
		-- no knees to crouch with (R6), and no sinking while the legs are walking
		local sink = math.min(rootPos[2], 0) * (if s.Rig.R6 then 0 else 1 - walk)
		pose = table.clone(pose)
		pose.RootPos = { rootPos[1], math.max(rootPos[2], 0) + sink, rootPos[3] }
	end
	-- while walking the run cycle owns the legs; standing, the combo stance does
	local legWeight = 1 - walk
	for _, j in ipairs(s.Rig.Joints) do
		local motor = j.Motor
		if motor.Parent then
			local cf = CFrame.identity
			for _, name in ipairs(j.Joints) do
				cf *= Pose.CFrame(pose, name)
			end
			local target = j.Rot:Inverse() * cf * j.Rot
			local anim = (motor :: any).Transform :: CFrame
			local blended = anim:Lerp(target, if j.Leg then weight * legWeight else weight)
			setJointFrame(j, j.C0 * blended * anim:Inverse())
		end
	end
end

-- Puts the rig back exactly as the Animator drives it.
local function releasePose(rig)
	for _, j in ipairs(rig.Joints) do
		setJointFrame(j, j.C0)
	end
end

-- ===== Weapon grip =====
-- Spear moves turn the shaft in the hand (the "Grip" pose joint) and twirl it (Spin,
-- Combo.SpinCFrame) by rewriting the grip weld's C0 on this client, on top of the C0
-- the server welded it with. Moves without either leave the weld alone.
local gripBase: { [Weld]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local gripDirty: { [Model]: Weld } = {}
local usesGrip: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function moveUsesGrip(move): boolean
	local cached = usesGrip[move]
	if cached == nil then
		cached = move.Spin ~= nil
		for _, key in ipairs(move.Keys) do
			cached = cached or key.Grip ~= nil
		end
		usesGrip[move] = cached
	end
	return cached
end

local function resetGrip(character: Model)
	local weld = gripDirty[character]
	if weld then
		gripDirty[character] = nil
		local base = gripBase[weld]
		if base and weld.Parent then
			weld.C0 = base
		end
	end
end

local function applyGrip(character: Model, move, t: number, pose, weight: number)
	if not moveUsesGrip(move) then
		resetGrip(character)
		return
	end
	local weapon = character:FindFirstChild("EquippedKatana")
	local grip = weapon and (weapon :: Model).PrimaryPart
	local weld = grip and grip:FindFirstChild("KatanaGrip")
	if not weld or not weld:IsA("Weld") then
		return
	end
	if gripDirty[character] and gripDirty[character] ~= weld then
		resetGrip(character)
	end
	local base = gripBase[weld]
	if not base then
		base = weld.C0
		gripBase[weld] = base
	end
	local turn = CFrame.identity:Lerp(Pose.CFrame(pose, "Grip"), weight)
	local spin = Combo.SpinCFrame(move, t)
	weld.C0 = base * turn * (spin or CFrame.identity)
	gripDirty[character] = weld
end

local function offhandTrail(character: Model): Trail?
	local offhand = character:FindFirstChild("EquippedOffhand")
	local trail = offhand and offhand:FindFirstChild("SwingTrail", true)
	return if trail and trail:IsA("Trail") then trail else nil
end

local function stepSwings(dt: number)
	local now = os.clock()
	for character, s in pairs(swings) do
		if not character.Parent then
			swings[character] = nil
			releasePose(s.Rig)
			gripDirty[character] = nil
			continue
		end
		-- hit stop: the move nearly freezes for a moment
		s.Elapsed += dt * (if now < s.FreezeUntil then 0.05 else 1)
		local t = s.Elapsed / s.Duration
		if t >= 1 then
			swings[character] = nil
			releasePose(s.Rig)
			resetGrip(character)
			if s.Trail then
				s.Trail.Enabled = false
				local second = offhandTrail(character)
				if second then
					second.Enabled = false
				end
			end
			continue
		end
		local move = s.Move
		local pose, weight = Pose.Sample(move, t, s.From)
		s.LastPose, s.LastWeight = pose, weight
		if s.Trail then
			local lit = t >= move.Trail[1] and t <= move.Trail[2]
			-- dual-wielded claws: the left-hand weapon's trail lights with the right's
			for _, trail in ipairs({ s.Trail, offhandTrail(character) }) do
				if lit and not trail.Enabled and trail.Parent then
					-- rarer blades throw a burst of sparks as the cut starts
					local burst = trail.Parent:FindFirstChild("SwingBurst")
					if burst and burst:IsA("ParticleEmitter") then
						burst:Emit(burst:GetAttribute("Burst") or 6)
					end
				end
				trail.Enabled = lit
			end
		end
		applyPose(s, pose, weight, dt)
		applyGrip(character, move, t, pose, weight)

		local lunge = s.Lunge
		local root = s.Root :: BasePart?
		if lunge and root then
			local from, to = move.Trail[1] * 0.6, move.HitAt
			local p = math.clamp((t - from) / (to - from), 0, 1)
			local goal = (1 - (1 - p) ^ 2) * lunge.Studs
			-- momentum: after the blade lands the body glides on, easing to a stop
			if lunge.Follow > 0 and t > to then
				local q = math.clamp((t - to) * s.Duration / Combo.Momentum.FollowTime, 0, 1)
				goal += (1 - (1 - q) ^ 2) * lunge.Follow
			end
			local step = goal - lunge.Done
			if step > 0.001 then
				lunge.Done += step
				root.CFrame += lunge.Direction * step
			end
		end
	end
end

local function easeOut(t: number): number
	return 1 - (1 - t) * (1 - t)
end

-- ===== Enemies =====
local enemies: { [Model]: any } = {}
local waiting: { [Model]: boolean } = {} -- tagged before their parts streamed in

-- ===== Ragdolls =====
local MAX_RAGDOLLS = 24
local RAGDOLL_HOLD = 2 -- seconds a body lies there before fading
local RAGDOLL_FADE = 0.6
local RAGDOLL_RANGE = 150 -- studs from the camera; further away they just topple
local ragdolls: { { Body: Model, Parts: { BasePart }, Start: number } } = {}
AnimationController.RagdollCount = 0 -- total made (for the playtest)

local function hideOriginal(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
		elseif d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") or d:IsA("Light") then
			d.Enabled = false
		end
	end
end

-- Swaps a defeated enemy for a loose local copy that tumbles away from the hit.
local function ragdoll(s): boolean
	if #ragdolls >= MAX_RAGDOLLS or s.Anchored or next(s.Motors) == nil then
		return false
	end
	local model = s.Model :: Model
	local camera = workspace.CurrentCamera
	if camera and ((s.Root :: BasePart).Position - camera.CFrame.Position).Magnitude > RAGDOLL_RANGE then
		return false
	end
	local body = model:Clone()
	if not body then
		return false
	end
	CollectionService:RemoveTag(body, "Enemy")
	local root = body.PrimaryPart or body:FindFirstChild("HumanoidRootPart")
	local limbs: { [BasePart]: boolean } = {}
	for _, d in ipairs(body:GetDescendants()) do
		if d:IsA("Humanoid") or d:IsA("BillboardGui") or d:IsA("ProximityPrompt") or d:IsA("BaseScript") then
			d:Destroy()
		elseif d:IsA("Motor6D") then
			local p0, p1 = d.Part0, d.Part1
			if p0 and p1 and p0 ~= root and p1 ~= root then
				local a0 = Instance.new("Attachment")
				a0.CFrame = d.C0
				a0.Parent = p0
				local a1 = Instance.new("Attachment")
				a1.CFrame = d.C1
				a1.Parent = p1
				local socket = Instance.new("BallSocketConstraint")
				socket.Attachment0 = a0
				socket.Attachment1 = a1
				socket.LimitsEnabled = true
				socket.UpperAngle = 70
				socket.TwistLimitsEnabled = true
				socket.TwistLowerAngle = -40
				socket.TwistUpperAngle = 40
				socket.Parent = p0
				limbs[p0] = true
				limbs[p1] = true
			end
			d:Destroy()
		end
	end
	if root and root:IsA("BasePart") then
		root:Destroy() -- the invisible root box would hold the body up
	end
	local parts: { BasePart } = {}
	local core: BasePart? = nil
	for _, d in ipairs(body:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanTouch = false
			d.CanQuery = false
			-- rig boxes collide with the ground (not with each other or players:
			-- the Enemies collision group); welded meshes and gear ride along
			d.CanCollide = limbs[d] == true
			d.Massless = not limbs[d]
			d.CollisionGroup = "Enemies"
			table.insert(parts, d)
			if limbs[d] and (not core or d.Size.Magnitude > core.Size.Magnitude) then
				core = d
			end
		end
	end
	if not core then
		body:Destroy()
		return false
	end
	body.Name = "Ragdoll"
	body.Parent = workspace
	hideOriginal(model)

	-- knock it away from the local player (or backwards if they're not near)
	local character = Players.LocalPlayer.Character
	local from = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local away = (core :: BasePart).CFrame.LookVector * -1
	if from then
		local d = (core :: BasePart).Position - from.Position
		d = Vector3.new(d.X, 0, d.Z)
		if d.Magnitude > 0.1 then
			away = d.Unit
		end
	end
	local push = away * (24 + math.random() * 10) + Vector3.new(0, 18 + math.random() * 8, 0)
	pcall(function()
		local mass = (core :: BasePart).AssemblyMass
		;(core :: BasePart):ApplyImpulse(push * mass)
		;(core :: BasePart):ApplyAngularImpulse(away:Cross(Vector3.yAxis) * -mass * 6)
	end)
	table.insert(ragdolls, { Body = body, Parts = parts, Start = os.clock() })
	AnimationController.RagdollCount += 1
	return true
end

local function stepRagdolls()
	local now = os.clock()
	for i = #ragdolls, 1, -1 do
		local r = ragdolls[i]
		local fade = (now - r.Start - RAGDOLL_HOLD) / RAGDOLL_FADE
		if fade >= 1 or not r.Body.Parent then
			r.Body:Destroy()
			table.remove(ragdolls, i)
		elseif fade > 0 then
			for _, part in ipairs(r.Parts) do
				part.LocalTransparencyModifier = fade
			end
		end
	end
end

function AnimationController:ActiveRagdolls(): number
	return #ragdolls
end

local function registerEnemy(model: Instance)
	if not model:IsA("Model") or enemies[model] then
		return
	end
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	local motors = {}
	local count = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") then
			motors[d.Name] = d
			count += 1
		end
	end
	-- with streaming on, the tag can arrive before the parts: try again shortly
	if not root or not root:IsA("BasePart") or (count == 0 and not (root :: BasePart).Anchored) then
		waiting[model] = true
		return
	end
	waiting[model] = nil
	local state = {
		Model = model,
		Root = root,
		Motors = motors,
		Phase = math.random() * 10,
		Seed = math.random() * 100,
		AttackStart = -10,
		HitStart = -10,
		DeathStart = nil :: number?,
		Anchored = (root :: BasePart).Anchored,
		BasePivot = model:GetPivot(),
		IsBeast = motors.FrontRight ~= nil,
		IsWisp = model:FindFirstChild("Core") ~= nil and motors.RightHip == nil and motors.FrontRight == nil,
	}
	enemies[model] = state
	local uid = model:GetAttribute("Uid")
	if uid then
		AnimationController.EnemiesByUid[uid] = state
	end
	model:GetAttributeChangedSignal("AttackTick"):Connect(function()
		state.AttackStart = os.clock()
	end)
	local function onDead()
		if model:GetAttribute("Dead") and not state.DeathStart then
			state.DeathStart = os.clock()
			local ok, made = pcall(ragdoll, state)
			state.Ragdolled = ok and made
			if not ok then
				warn("[NinjaSim] Enemy ragdoll failed: " .. tostring(made))
			end
		end
	end
	model:GetAttributeChangedSignal("Dead"):Connect(onDead)
	onDead()
end

local function unregisterEnemy(model: Instance)
	waiting[model :: Model] = nil
	local state = enemies[model :: Model]
	if state then
		local uid = model:GetAttribute("Uid")
		if uid then
			AnimationController.EnemiesByUid[uid] = nil
		end
		enemies[model :: Model] = nil
	end
end

function AnimationController:HitEnemy(uid: number)
	local state = self.EnemiesByUid[uid]
	if state then
		state.HitStart = os.clock()
	end
end

function AnimationController:GetEnemyModel(uid: number): Model?
	local state = self.EnemiesByUid[uid]
	return state and state.Model
end

-- Poses an enemy joint through C0 (base C0 * pose): Transform written from a
-- script gets overwritten by the Humanoid's Animator in a live game, C0 doesn't.
local baseC0: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local function setT(motor: Motor6D?, cf: CFrame)
	if motor then
		local base = baseC0[motor]
		if not base then
			base = motor.C0
			baseC0[motor] = base
		end
		motor.C0 = base * cf
	end
end

-- enemy weapon swing beats (radians / studs)
local ENEMY_REST = { Pitch = 0, Roll = 0, Twist = 0, Lean = 0, Crouch = 0, Left = 0 }
local ENEMY_WINDUP = { Pitch = 2.9, Roll = 0.35, Twist = 0.45, Lean = -0.18, Crouch = 0, Left = 0.6 }
local ENEMY_STRIKE = { Pitch = 0.9, Roll = -0.5, Twist = -0.5, Lean = 0.42, Crouch = 0.25, Left = -0.3 }
local function lerpPose(a, b, k: number)
	local out = {}
	for key, v in pairs(a) do
		out[key] = v + (b[key] - v) * k
	end
	return out
end

local nextRetry = 0
local function stepEnemies(dt: number)
	local camera = workspace.CurrentCamera
	local camPos = camera.CFrame.Position
	local now = os.clock()
	stepRagdolls()
	if now >= nextRetry and next(waiting) then
		nextRetry = now + 0.25
		for model in pairs(waiting) do
			if model.Parent and (CollectionService:HasTag(model, "Enemy") or CollectionService:HasTag(model, "Companion")) then
				registerEnemy(model)
			else
				waiting[model] = nil
			end
		end
	end
	for model, s in pairs(enemies) do
		local root = s.Root :: BasePart
		if not root.Parent or s.Ragdolled then
			continue
		end
		local dist = (root.Position - camPos).Magnitude
		if dist > 160 then
			continue
		end
		local m = s.Motors
		local hit = math.max(0, 1 - (now - s.HitStart) / 0.25)
		local attackT = (now - s.AttackStart) / Balance.EnemyAttackAnim

		if s.Anchored then
			-- training dummy wobble
			if hit > 0 then
				local wobble = math.sin((now - s.HitStart) * 40) * 0.18 * hit
				model:PivotTo(s.BasePivot * CFrame.new(0, -3.6, 0) * CFrame.Angles(wobble, 0, wobble * 0.5) * CFrame.new(0, 3.6, 0))
			elseif s.Wobbling then
				model:PivotTo(s.BasePivot)
			end
			s.Wobbling = hit > 0
			continue
		end

		local vel = root.AssemblyLinearVelocity
		local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
		s.Phase += dt * (4 + speed * 0.55)
		local stride = math.min(speed / 12, 1)
		local swing = math.sin(s.Phase) * 0.75 * stride
		local breathe = math.sin(now * 2 + s.Seed) * 0.04

		local waist = CFrame.new(0, breathe, 0) * CFrame.Angles(0.45 * hit, 0, 0)
		if s.DeathStart then
			local k = math.min(1, (now - s.DeathStart) / 0.45)
			waist = CFrame.new(0, -k * 1.2, 0) * CFrame.Angles(k * 1.35, 0, k * 0.3)
		end

		if s.IsWisp then
			setT(m.Waist, waist * CFrame.new(0, math.sin(now * 2.2 + s.Seed) * 0.5, 0))
			local reach = if attackT < 1 then math.sin(attackT ^ 1.3 * math.pi) * 2.2 else 0
			setT(m.RightShoulder, CFrame.new(math.sin(now * 3) * 0.2, math.cos(now * 3) * 0.3, -reach))
			setT(m.LeftShoulder, CFrame.new(-math.sin(now * 3) * 0.2, -math.cos(now * 3) * 0.3, -reach))
		elseif s.IsBeast then
			-- lunge peaks with the server's hit (attackT ^ 1.3 puts the peak at ~0.59)
			local lunge = if attackT < 1 then math.sin(attackT ^ 1.3 * math.pi) else 0
			setT(m.Waist, waist * CFrame.new(0, 0, -lunge * 1.2) * CFrame.Angles(-lunge * 0.3, 0, 0))
			setT(m.FrontRight, CFrame.Angles(swing, 0, 0))
			setT(m.BackLeft, CFrame.Angles(swing, 0, 0))
			setT(m.FrontLeft, CFrame.Angles(-swing, 0, 0))
			setT(m.BackRight, CFrame.Angles(-swing, 0, 0))
			setT(m.Neck, CFrame.Angles(-lunge * 0.4 + math.sin(now * 1.5 + s.Seed) * 0.05, 0, 0))
			for i = 1, 3 do
				setT(m["Tail" .. i], CFrame.Angles(0, math.sin(now * 4 + i) * 0.35, 0))
			end
		else
			local armSwing = -swing * 0.7
			local right = CFrame.Angles(armSwing, 0, 0)
			local leftPitch = swing * 0.7
			local twist, lean, crouch = 0, 0, 0
			if attackT < 1 then
				-- wind up: weapon raised high behind the shoulder, body coiled back and
				-- held a beat so the player can read it; strike (lands with the server's
				-- hit, Balance.EnemyWindup in): a diagonal chop down and across, body
				-- twisting and leaning into it; then recover
				local p
				local strikeStart = (Balance.EnemyWindup - 0.12) / Balance.EnemyAttackAnim
				local strikeEnd = (Balance.EnemyWindup + 0.04) / Balance.EnemyAttackAnim
				if attackT < strikeStart then
					p = lerpPose(ENEMY_REST, ENEMY_WINDUP, easeOut(math.min(1, attackT / (strikeStart * 0.7))))
				elseif attackT < strikeEnd then
					p = lerpPose(ENEMY_WINDUP, ENEMY_STRIKE, 1 - (1 - (attackT - strikeStart) / (strikeEnd - strikeStart)) ^ 3)
				else
					p = lerpPose(ENEMY_STRIKE, ENEMY_REST, easeOut((attackT - strikeEnd) / (1 - strikeEnd)))
				end
				right = CFrame.Angles(p.Pitch, 0, 0) * CFrame.Angles(0, 0, p.Roll)
				twist, lean, crouch = p.Twist, p.Lean, p.Crouch
				leftPitch = p.Left
				if model:FindFirstChild("Fist") then
					leftPitch = p.Pitch
				end
			end
			setT(m.Waist, waist * CFrame.new(0, -crouch, 0) * CFrame.Angles(-lean, twist, 0))
			setT(m.RightHip, CFrame.Angles(swing + crouch * 1.4, 0, 0))
			setT(m.LeftHip, CFrame.Angles(-swing - crouch * 0.8, 0, 0))
			setT(m.RightShoulder, right)
			setT(m.LeftShoulder, CFrame.Angles(leftPitch, 0, 0))
			setT(m.Neck, CFrame.Angles(math.sin(now * 1.3 + s.Seed) * 0.05 + lean * 0.5, math.sin(now * 0.7 + s.Seed) * 0.1 - twist * 0.6, 0))
		end
	end
end

function AnimationController:Start()
	RunService.Stepped:Connect(function(_, dt)
		stepSwings(dt)
		stepEnemies(dt)
	end)
	-- hired ninjas (CompanionService) move and swing like enemies
	for _, tag in ipairs({ "Enemy", "Companion" }) do
		CollectionService:GetInstanceAddedSignal(tag):Connect(registerEnemy)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(unregisterEnemy)
		for _, model in ipairs(CollectionService:GetTagged(tag)) do
			registerEnemy(model)
		end
	end
	-- models streamed out/destroyed without tag removal
	task.spawn(function()
		while true do
			task.wait(5)
			for model in pairs(enemies) do
				if not model.Parent then
					unregisterEnemy(model)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		if player.Character then
			swings[player.Character] = nil
		end
	end)
end

return AnimationController
