--[[
	CombatController: player input -> the 4-hit katana combo (Config/Combo). Holding
	attack chains the moves; pausing past the chain window starts over. The client
	animates instantly for responsiveness and tells the server "I swung"; the server
	decides what was hit. Results come back as CombatResult / EnemyDied and drive
	the feedback (damage numbers, sparks, hit stop, shake, coins, XP pops, kill
	streaks), timed to the moment the blade lands in the animation.
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

local CombatController = {}

local controllers
local player = Players.LocalPlayer
local nextSwing = 0 -- earliest time the next move may start
local chainOpenUntil = 0 -- after this the combo starts over at move 1
local combo = 0
local lastWeapon = "Katana"
local hitMoment = 0 -- when the current move's blade lands
local holding = false
local streak = 0
local lastKill = 0

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

function CombatController:Swing()
	local root = getRoot()
	local data = controllers.DataController:Get()
	if not root or not data then
		return
	end
	local stats = controllers.DataController:GetStats()
	local interval = if stats then stats.AttackInterval else Balance.BaseAttackInterval
	local now = os.clock()
	if now < nextSwing then
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

	-- aim assist: turn toward the closest enemy in reach so swings feel fair
	local target, dist = nearestEnemy(Balance.AttackRange + math.max(5, move.Reach))
	if target and target.PrimaryPart and dist > 0.5 then
		local tp = target.PrimaryPart.Position
		local flatTarget = Vector3.new(tp.X, root.Position.Y, tp.Z)
		root.CFrame = CFrame.lookAt(root.Position, flatTarget)
	end

	-- step into the strike, but stop short of the target and of walls
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	local studs = if target then math.clamp(dist - 4, 0, move.Lunge) else move.Lunge * 0.6
	if studs > 0 then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { player.Character :: Model }
		local wall = workspace:Raycast(root.Position, look * (studs + 1.5), params)
		if wall then
			studs = math.max(0, wall.Distance - 1.5)
		end
	end

	local character = player.Character :: Model
	controllers.AnimationController:PlaySwing(character, combo, duration, { Direction = look, Studs = studs })
	task.delay(move.Trail[1] * duration, function()
		controllers.SoundController:Play(if move.Finisher then "Finisher" else "Swing")
	end)
	if move.Finisher then
		-- the finisher always lands with a ground slam, hit or miss
		task.delay(move.HitAt * duration, function()
			local r = getRoot()
			if not r then
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

local function showHits(result)
	local move = Combo.Get(result.Move or 1, Combo.WeaponOf(player.Character))
	controllers.AnimationController:HitStop(player.Character, if move.Finisher then 0.12 else 0.05)
	local anyCrit = false
	for _, hit in ipairs(result.Hits) do
		local top = hit.Position + Vector3.new(0, (hit.Height or 5) * 0.75, 0)
		controllers.EffectsController:DamageNumber(top, hit.Damage, hit.Crit)
		controllers.EffectsController:HitSpark(hit.Position + Vector3.new(0, (hit.Height or 5) * 0.45, 0), if hit.Crit then Color3.fromRGB(255, 210, 60) else Color3.fromRGB(255, 255, 255), hit.Crit)
		controllers.AnimationController:HitEnemy(hit.Uid)
		anyCrit = anyCrit or hit.Crit
	end
	controllers.SoundController:Play(if anyCrit then "Crit" else "Hit")
	controllers.CameraController:Shake(if move.Finisher then 0.4 elseif anyCrit then 0.28 else 0.1)
	if anyCrit or move.Finisher then
		controllers.CameraController:Punch(-4, 0.25)
	end
	if controllers.HUD then
		controllers.HUD:SetCombo(result.Combo)
	end
end

-- The server answers as soon as the swing starts; show the hits when the blade
-- actually lands in the animation.
local function onCombatResult(result)
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
			holding = true
			self:Swing()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 or input.KeyCode == Enum.KeyCode.F then
			holding = false
		end
	end)

	RunService.Heartbeat:Connect(function()
		local data = c.DataController:Get()
		if holding then
			self:Swing()
		elseif data and data.Settings.AutoSwing and (data.Utility.auto_swing or 0) > 0 then
			local target = nearestEnemy(Balance.AttackRange)
			if target then
				self:Swing()
			end
		end
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
