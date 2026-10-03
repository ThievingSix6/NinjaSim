--[[
	CombatController: player input -> the 4-hit katana combo (Config/Combo). Holding
	attack chains the moves; pausing past the chain window starts over. The client
	animates instantly for responsiveness and tells the server "I swung"; the server
	decides what was hit. Results come back as CombatResult / EnemyDied and drive
	the feedback (damage numbers, sparks, hit stop, shake, coins, XP pops, kill
	streaks), timed to the moment the blade lands in the animation.

	Souls-style pacing (2026-10-02): each swing spends stamina (Util/Stamina; the HUD
	shows this client's copy of the pool, the server keeps the real one), a press
	during a swing is buffered and plays as soon as the move allows, and the player
	walks slowly while a swing plays (MovementController reads IsAttacking).

	Fluid combat: a dodge or a jump cancels the swing (CancelSwing). Cancelled in
	its wind-up, the server drops the swing too (it resolves hits when the blade lands)
	and the combo starts over; cancelled in its recovery, the hits already landed.

	Light and heavy (2026-10-03): a tap of attack is a light attack (the combo, chained
	by tapping again). Holding it past Combo.Heavy.HoldDelay charges a heavy attack
	instead (a braced wind-up with a glow that builds); releasing strikes with the
	weapon's finisher, harder the longer it charged (Combo.HeavyMove). Every strike
	carries momentum: it steps in, keeps some of your running speed, and glides on
	a little after the hit (Combo.Momentum).
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Balance = require(Shared.Config.Balance)
local Combo = require(Shared.Config.Combo)
local Format = require(Shared.Util.Format)
local Stamina = require(Shared.Util.Stamina)

local CombatController = {}

local controllers
local player = Players.LocalPlayer
local nextSwing = 0 -- earliest time the next move may start
local chainOpenUntil = 0 -- after this the combo starts over at move 1
local combo = 0
local lastWeapon = "Katana"
local hitMoment = 0 -- when the current move's blade lands
local holding = false
local bufferedUntil = 0 -- a press during a swing plays when the move allows, until then
local attackingUntil = 0 -- the player is committed to the current swing until then
local BUFFER = 0.45
local swingToken = 0 -- bumps on every swing and cancel, so a cancelled swing's delayed effects stay quiet
local ignoreResultsUntil = 0 -- a result for a swing cancelled in its wind-up can still be in flight
local streak = 0
local lastKill = 0
local pressAt = 0 -- when the attack button went down (0 = not held)
local charging = false
local chargeStart = 0
local chargeFull = false
local chargeFx: Attachment? = nil

local STREAK_NAMES = { [2] = "DOUBLE KILL!", [3] = "TRIPLE KILL!", [4] = "MULTI KILL!", [6] = "RAMPAGE!", [10] = "UNSTOPPABLE!", [15] = "LEGENDARY!" }

local function getRoot(): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Nearest living enemy within `range` studs (client-side, for aim assist / auto swing).
local function nearestEnemy(range: number): (Model?, number)
	local root = getRoot()
	if not root then
		return nil, math.huge
	end
	local best, bestDist = nil, range
	for _, model in ipairs(CollectionService:GetTagged("Enemy")) do
		if model:IsA("Model") and not model:GetAttribute("Dead") then
			local primary = model.PrimaryPart
			if primary then
				local d = Vector3.new(primary.Position.X - root.Position.X, 0, primary.Position.Z - root.Position.Z).Magnitude
				if d < bestDist then
					best, bestDist = model, d
				end
			end
		end
	end
	return best, bestDist
end

CombatController.Stamina = Stamina.new(os.clock())

-- The local player's stamina right now (0..Balance.Stamina.Max).
function CombatController:GetStamina(): number
	return Stamina.Get(self.Stamina, os.clock())
end

-- Spends stamina if there is any left; false when the pool is empty.
function CombatController:TrySpend(cost: number): boolean
	local now = os.clock()
	if not Stamina.CanAct(self.Stamina, now) then
		if controllers.HUD and controllers.HUD.FlashStamina then
			controllers.HUD:FlashStamina()
		end
		return false
	end
	Stamina.Spend(self.Stamina, now, cost)
	return true
end

-- True while a swing is still playing out (the player is committed to it) or a
-- heavy attack is charging.
function CombatController:IsAttacking(): boolean
	return charging or os.clock() < attackingUntil
end

-- True while a heavy attack is charging; the charge so far (0..1).
function CombatController:IsCharging(): (boolean, number)
	return charging, if charging then math.clamp((os.clock() - chargeStart) / Combo.Heavy.ChargeTime, 0, 1) else 0
end

local function clearChargeFx()
	if chargeFx then
		chargeFx:Destroy()
		chargeFx = nil
	end
end

-- The charge glow: sparks drawn in round the player and a light that swells, gold
-- once fully charged.
local function makeChargeFx(root: BasePart)
	clearChargeFx()
	local attachment = Instance.new("Attachment")
	attachment.Name = "HeavyCharge"
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Sparks"
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	sparks.Transparency = NumberSequence.new(0.2)
	sparks.Lifetime = NumberRange.new(0.3, 0.5)
	sparks.Speed = NumberRange.new(-9, -6) -- drawn inward
	sparks.Shape = Enum.ParticleEmitterShape.Sphere
	sparks.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	sparks.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	sparks.Rate = 30
	sparks.Parent = attachment
	local light = Instance.new("PointLight")
	light.Name = "Glow"
	light.Color = Color3.fromRGB(255, 255, 255)
	light.Range = 6
	light.Brightness = 1
	light.Parent = attachment
	attachment.Parent = root
	chargeFx = attachment
end

local function stepChargeFx(k: number)
	if not chargeFx then
		return
	end
	local color = Color3.fromRGB(255, 255, 255):Lerp(Color3.fromRGB(255, 200, 60), k)
	local sparks = chargeFx:FindFirstChild("Sparks") :: ParticleEmitter?
	local light = chargeFx:FindFirstChild("Glow") :: PointLight?
	if sparks then
		sparks.Rate = 30 + 70 * k
		sparks.Color = ColorSequence.new(color)
	end
	if light then
		light.Range = 6 + 8 * k
		light.Brightness = 1 + 2 * k
		light.Color = color
	end
end

-- True until the current swing's blade lands: a dodge can't cut that short.
function CombatController:InWindup(): boolean
	return os.clock() < hitMoment
end

-- Called by DodgeController: a roll cancels any buffered swing.
function CombatController:ClearBuffer()
	bufferedUntil = 0
end

-- Stops the current swing (dodge or jump). In its wind-up the swing is cancelled on
-- the server too: `tellServer` false when the caller's own event already does that
-- (a dodge). The next swing may start as soon as the dodge or jump allows.
-- Returns true if a swing was cut short.
function CombatController:CancelSwing(tellServer: boolean?): boolean
	local now = os.clock()
	holding, pressAt = false, 0 -- a press held through a dodge or jump doesn't swing on release
	if charging then
		charging = false
		clearChargeFx()
		attackingUntil, hitMoment, bufferedUntil = 0, 0, 0
		if tellServer ~= false then
			Net.Event("CancelAttack"):FireServer()
		end
		local character = player.Character
		if character then
			controllers.AnimationController:CancelSwing(character)
		end
		return true
	end
	if now >= attackingUntil and now >= hitMoment then
		bufferedUntil = 0
		return false
	end
	local inWindup = now < hitMoment
	attackingUntil, hitMoment, bufferedUntil = 0, 0, 0
	nextSwing = now
	swingToken += 1
	if inWindup then
		combo = 0 -- the server starts the chain over as well
		ignoreResultsUntil = now + 0.5
		if tellServer ~= false then
			Net.Event("CancelAttack"):FireServer()
		end
	end
	local character = player.Character
	if character then
		controllers.AnimationController:CancelSwing(character)
	end
	return true
end

-- Aim assist and the strike's step: turns toward the target in reach and works out
-- how far the strike carries the player (lunge + momentum, short of the target and walls).
local function aimAndStep(root: BasePart, move): (Vector3, number, number)
	-- aim assist: turn toward the closest enemy in reach, but only one already
	-- roughly in front (no snapping round to cut what's behind you)
	local target, dist = nearestEnemy(Balance.AttackRange + math.max(3, move.Reach))
	local locked = controllers.LockOnController and controllers.LockOnController:Target()
	if locked and locked.PrimaryPart then
		-- a locked target is always the one you swing at, wherever it is in reach
		local lp = locked.PrimaryPart.Position
		local d = Vector3.new(lp.X - root.Position.X, 0, lp.Z - root.Position.Z).Magnitude
		if d <= Balance.AttackRange + math.max(3, move.Reach) + 4 then
			target, dist = locked, d
		end
	end
	if target and target ~= locked and target.PrimaryPart then
		local tp = target.PrimaryPart.Position
		local to = Vector3.new(tp.X - root.Position.X, 0, tp.Z - root.Position.Z)
		local facing = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		if to.Magnitude > 0.5 and facing.Magnitude > 0.01 and facing.Unit:Dot(to.Unit) < 0.17 then
			target = nil
		end
	end
	if target and target.PrimaryPart and dist > 0.5 then
		local tp = target.PrimaryPart.Position
		local flatTarget = Vector3.new(tp.X, root.Position.Y, tp.Z)
		root.CFrame = CFrame.lookAt(root.Position, flatTarget)
	end

	-- step into the strike, but stop short of the target and of walls
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	local studs = if target then math.clamp(dist - 4, 0, move.Lunge) else move.Lunge * 0.6
	-- momentum: running into the strike carries some of that speed into it
	local m = Combo.Momentum
	local velocity = root.AssemblyLinearVelocity
	local carry = math.min(m.CarryMax, math.max(0, velocity.X * look.X + velocity.Z * look.Z) * m.Carry)
	studs = if target then math.min(studs + carry, math.max(0, dist - 3.5)) else studs + carry
	-- and the body glides on a little after the hit (not into the one it struck)
	local follow = if target then math.clamp(dist - 3.5 - studs, 0, studs * m.Follow) else studs * m.Follow
	if studs + follow > 0 then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { player.Character :: Model }
		local wall = workspace:Raycast(root.Position, look * (studs + follow + 1.5), params)
		if wall then
			local room = math.max(0, wall.Distance - 1.5)
			studs = math.min(studs, room)
			follow = math.clamp(room - studs, 0, follow)
		end
	end
	return look, studs, follow
end


function CombatController:Swing(buffer: boolean?)
	local root = getRoot()
	local data = controllers.DataController:Get()
	if not root or not data then
		return
	end
	local stats = controllers.DataController:GetStats()
	local interval = if stats then stats.AttackInterval else Balance.BaseAttackInterval
	local now = os.clock()
	if now < nextSwing or (controllers.DodgeController and controllers.DodgeController:IsDodging()) then
		if buffer then
			bufferedUntil = now + BUFFER
		end
		return
	end
	bufferedUntil = 0
	local weapon = Combo.WeaponOf(player.Character)
	local upcoming = if weapon == lastWeapon and combo > 0 and now <= chainOpenUntil then (combo % #Combo.MovesFor(weapon)) + 1 else 1
	if not self:TrySpend(Stamina.MoveCost(Combo.Get(upcoming, weapon))) then
		return
	end
	local weapon = Combo.WeaponOf(player.Character)
	if weapon ~= lastWeapon then
		lastWeapon = weapon
		combo = 0
	end
	combo = if combo > 0 and now <= chainOpenUntil then (combo % #Combo.MovesFor(weapon)) + 1 else 1
	local move = Combo.Get(combo, weapon)
	-- faster attack speed plays the moves faster too
	local duration = move.Duration * math.clamp(interval / Balance.BaseAttackInterval, 0.45, 1)
	nextSwing = now + interval * move.Cooldown
	chainOpenUntil = nextSwing + Combo.ChainWindow
	hitMoment = now + move.HitAt * duration
	attackingUntil = now + math.min(duration * 0.85, interval * move.Cooldown)

	local look, studs, follow = aimAndStep(root, move)

	local character = player.Character :: Model
	controllers.AnimationController:PlaySwing(character, combo, duration, { Direction = look, Studs = studs, Follow = follow })
	swingToken += 1
	local token = swingToken
	task.delay(move.Trail[1] * duration, function()
		if token == swingToken then
			controllers.SoundController:Play(if move.Finisher then "Finisher" else "Swing")
		end
	end)
	if move.Finisher then
		-- the finisher always lands with a ground slam, hit or miss
		task.delay(move.HitAt * duration, function()
			local r = getRoot()
			if not r or token ~= swingToken then
				return
			end
			local fwd = Vector3.new(r.CFrame.LookVector.X, 0, r.CFrame.LookVector.Z).Unit
			controllers.EffectsController:Shockwave(r.Position + fwd * (4 + math.max(0, move.Reach - 3) * 0.6) - Vector3.new(0, 2.8, 0), Color3.fromRGB(255, 240, 200), 9, 0.4, 0.3)
			controllers.SoundController:Play("Slam")
			controllers.CameraController:Shake(0.3)
		end)
	end
	Net.Event("Attack"):FireServer(combo)
end

-- Starts charging a heavy attack (the attack button held past Combo.Heavy.HoldDelay).
function CombatController:BeginCharge(): boolean
	local root = getRoot()
	local now = os.clock()
	if charging or not root or now < attackingUntil or (controllers.DodgeController and controllers.DodgeController:IsDodging()) then
		return false
	end
	if not Stamina.CanAct(self.Stamina, now) then
		if controllers.HUD and controllers.HUD.FlashStamina then
			controllers.HUD:FlashStamina()
		end
		return false
	end
	-- the server only allows the release once the last swing's recovery has run
	local stats = controllers.DataController:GetStats()
	local interval = if stats then stats.AttackInterval else Balance.BaseAttackInterval
	if now < nextSwing - interval * 0.2 then
		return false
	end
	charging, chargeStart, chargeFull = true, now, false
	bufferedUntil = 0
	local character = player.Character :: Model
	controllers.AnimationController:PlayPose(character, Combo.ChargePose(Combo.WeaponOf(character)), Combo.Heavy.MaxHold + 0.6)
	makeChargeFx(root)
	controllers.SoundController:Play("Swing", 0.5, 0.6)
	Net.Event("HeavyCharge"):FireServer()
	return true
end

-- Releases the charge: the heavy strike, harder the longer it charged.
function CombatController:ReleaseHeavy()
	if not charging then
		return
	end
	charging = false
	clearChargeFx()
	local root = getRoot()
	local character = player.Character
	local now = os.clock()
	local charge = math.clamp((now - chargeStart) / Combo.Heavy.ChargeTime, 0, 1)
	if not root or not character or not self:TrySpend(Balance.Stamina.Heavy) then
		if character then
			controllers.AnimationController:CancelSwing(character)
		end
		Net.Event("CancelAttack"):FireServer()
		return
	end
	local stats = controllers.DataController:GetStats()
	local interval = if stats then stats.AttackInterval else Balance.BaseAttackInterval
	local weapon = Combo.WeaponOf(character)
	local move = Combo.HeavyMove(weapon, charge)
	local duration = move.Duration * math.clamp(interval / Balance.BaseAttackInterval, 0.45, 1)
	combo = 0 -- the next light attack opens a fresh combo
	chainOpenUntil = 0
	nextSwing = now + interval * move.Cooldown
	hitMoment = now + move.HitAt * duration
	attackingUntil = now + math.min(duration * 0.9, interval * move.Cooldown)
	local look, studs, follow = aimAndStep(root, move)
	controllers.AnimationController:PlaySwing(character, move, duration, { Direction = look, Studs = studs, Follow = follow })
	swingToken += 1
	local token = swingToken
	task.delay(move.Trail[1] * duration, function()
		if token == swingToken then
			controllers.SoundController:Play("Finisher", 1, 0.85)
		end
	end)
	task.delay(move.HitAt * duration, function()
		local r = getRoot()
		if not r or token ~= swingToken then
			return
		end
		local fwd = Vector3.new(r.CFrame.LookVector.X, 0, r.CFrame.LookVector.Z).Unit
		local color = Color3.fromRGB(255, 255, 255):Lerp(Color3.fromRGB(255, 200, 60), charge)
		controllers.EffectsController:Shockwave(r.Position + fwd * 4.5 - Vector3.new(0, 2.8, 0), color, 10 + 6 * charge, 0.45, 0.4)
		controllers.SoundController:Play("Slam")
		controllers.CameraController:Shake(0.35 + 0.25 * charge)
	end)
	Net.Event("HeavyAttack"):FireServer()
end

-- The attack button (mouse, R2, F, the touch button): down ...
function CombatController:PressAttack()
	holding = true
	pressAt = os.clock()
end

-- ... and up: a tap (released before HoldDelay) is a light attack, a hold that
-- started charging strikes the heavy attack.
function CombatController:ReleaseAttack()
	if not holding then
		return
	end
	holding = false
	pressAt = 0
	if charging then
		self:ReleaseHeavy()
	else
		self:Swing(true)
	end
end

local function showHits(result)
	local move = if result.Heavy then Combo.HeavyMove(Combo.WeaponOf(player.Character), 1) else Combo.Get(result.Move or 1, Combo.WeaponOf(player.Character))
	controllers.AnimationController:HitStop(player.Character, if result.Heavy then 0.2 elseif move.Finisher then 0.15 else 0.07)
	local anyCrit = false
	for _, hit in ipairs(result.Hits) do
		local top = hit.Position + Vector3.new(0, (hit.Height or 5) * 0.75, 0)
		controllers.EffectsController:DamageNumber(top, hit.Damage, hit.Crit)
		controllers.EffectsController:HitSpark(hit.Position + Vector3.new(0, (hit.Height or 5) * 0.45, 0), if hit.Crit then Color3.fromRGB(255, 210, 60) else Color3.fromRGB(255, 255, 255), hit.Crit)
		controllers.AnimationController:HitEnemy(hit.Uid)
		anyCrit = anyCrit or hit.Crit
	end
	controllers.SoundController:Play(if anyCrit then "Crit" else "Hit")
	controllers.CameraController:Shake(if result.Heavy then 0.55 elseif move.Finisher then 0.4 elseif anyCrit then 0.28 else 0.1)
	if anyCrit or move.Finisher then
		controllers.CameraController:Punch(if result.Heavy then -6 else -4, 0.25)
	end
	if controllers.HUD then
		controllers.HUD:SetCombo(result.Combo)
	end
end

-- The server answers as soon as the swing starts; show the hits when the blade
-- actually lands in the animation.
local function onCombatResult(result)
	if os.clock() < ignoreResultsUntil then
		return
	end
	local wait = hitMoment - os.clock()
	if wait > 0.01 then
		task.delay(wait, showHits, result)
	else
		showHits(result)
	end
end

local function onEnemyDied(info)
	controllers.EffectsController:EnemyDied(info)
	local rewards = info.Rewards
	if not rewards then
		return
	end
	controllers.SoundController:Play("Kill")
	if rewards.Coins > 0 then
		controllers.EffectsController:CoinFly(info.Position + Vector3.new(0, 3, 0), rewards.Coins)
	end
	local camera = workspace.CurrentCamera
	local screen, onScreen = camera:WorldToViewportPoint(info.Position + Vector3.new(0, (info.Height or 5) + 1, 0))
	local scale = controllers.UIController.Scale
	local pos = if onScreen then Vector2.new(screen.X, screen.Y) / scale else Vector2.new(640, 300)
	controllers.EffectsController:FloatText("+" .. Format.Abbrev(rewards.XP) .. " XP", controllers.Theme.XP, pos)
	if rewards.Double then
		controllers.EffectsController:FloatText("DOUBLE DROP!", controllers.Theme.Gold, pos - Vector2.new(0, 34), 30)
	end
	if rewards.Shards then
		controllers.EffectsController:FloatText("+" .. rewards.Shards .. " 💎", controllers.Theme.Shard, pos + Vector2.new(0, 34), 30)
	end
	-- kill streaks
	local now = os.clock()
	streak = if now - lastKill < 3 then streak + 1 else 1
	lastKill = now
	local name = STREAK_NAMES[streak]
	if name and controllers.HUD then
		controllers.HUD:ShowStreak(name, streak)
	end
end

function CombatController:Start(c)
	controllers = c

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 or input.KeyCode == Enum.KeyCode.F then
			self:PressAttack()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 or input.KeyCode == Enum.KeyCode.F then
			self:ReleaseAttack()
		end
	end)

	RunService.Heartbeat:Connect(function()
		local data = c.DataController:Get()
		local now = os.clock()
		if charging then
			local k = math.clamp((now - chargeStart) / Combo.Heavy.ChargeTime, 0, 1)
			stepChargeFx(k)
			if k >= 1 and not chargeFull then
				chargeFull = true
				c.SoundController:Play("Crit", 0.6, 1.3)
				c.EffectsController:CharacterBurst(Color3.fromRGB(255, 200, 60), false)
			end
			if now - chargeStart >= Combo.Heavy.MaxHold then
				holding, pressAt = false, 0
				self:ReleaseHeavy()
			end
		elseif holding and pressAt > 0 and now - pressAt >= Combo.Heavy.HoldDelay then
			self:BeginCharge()
		elseif now < bufferedUntil then
			self:Swing()
		elseif data and data.Settings.AutoSwing and (data.Utility.auto_swing or 0) > 0 then
			local target = nearestEnemy(Balance.AttackRange)
			if target then
				self:Swing()
			end
		end
	end)

	player.CharacterAdded:Connect(function()
		Stamina.Refill(self.Stamina, os.clock())
		attackingUntil, bufferedUntil = 0, 0
		charging, holding, pressAt = false, false, 0
		clearChargeFx()
	end)

	Net.Event("CombatResult").OnClientEvent:Connect(onCombatResult)
	Net.Event("EnemyDied").OnClientEvent:Connect(onEnemyDied)
	Net.Event("Swing").OnClientEvent:Connect(function(other: Player, otherCombo: number)
		if other and other.Character and type(otherCombo) == "number" then
			c.AnimationController:PlaySwing(other.Character, otherCombo, Combo.Get(otherCombo, Combo.WeaponOf(other.Character)).Duration * 0.85)
		end
	end)
	Net.Event("EnemyHit").OnClientEvent:Connect(function(uid: number, crit: boolean)
		c.AnimationController:HitEnemy(uid)
		local model = c.AnimationController:GetEnemyModel(uid)
		if model and model.PrimaryPart then
			c.EffectsController:HitSpark(model.PrimaryPart.Position, Color3.new(1, 1, 1), crit)
		end
	end)
	Net.Event("PlayerHurt").OnClientEvent:Connect(function(amount: number, _from: Vector3, heavy: boolean?)
		c.EffectsController:Vignette(Color3.fromRGB(255, 30, 30), if heavy then 0.7 else 0.4, 0.5)
		c.CameraController:Shake(if heavy then 0.45 else 0.15)
		c.SoundController:Play("Hurt")
		local root = getRoot()
		if root then
			c.EffectsController:DamageNumber(root.Position + Vector3.new(0, 3, 0), amount, false, Color3.fromRGB(255, 80, 80))
		end
	end)
end

return CombatController
