--[[
	TempleService: runs of the Cursed Temple (Config/Temple), the 100-floor tower under
	the temple valley.

	The gate in the ruined temple (a ProximityPrompt tagged "TempleGate", built by
	ZoneDecor.Cursed) opens the Temple menu on that player's client; StartRun(player, floor)
	begins a run on floor 1 or a checkpoint they have reached. Each run gets its own
	sealed hall (one of Temple.Lanes x Temple.Lanes under the valley, built the first
	time it is needed and reused). A floor's monsters are spawned in the hall
	(EnemyService, tagged with the run); when the last one dies the seal in the middle
	opens with a "Descend" prompt, the floor-clear reward is paid and the best floor
	saved. Descending refills the hall for the next floor (darker and redder the deeper
	you go). Floor 100 cleared, dying, the hall's "Leave" prompt, Leave(player) or
	leaving the server end the run; the player goes back up to the valley.

	Events: "Temple" { Type = "Gate" | "Floor" | "Left" | "Cleared" | "End", ... }.
	Requests (RequestService): TempleStart(floor), TempleLeave().
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Temple = require(Shared.Config.Temple)
local Zones = require(Shared.Config.Zones)
local Balance = require(Shared.Config.Balance)
local Net = require(Shared.Net)

local TempleService = {}

local services
local rgb = Color3.fromRGB
type Run = {
	Player: Player, Lane: number, Floor: number, Alive: { [any]: boolean }, Count: number,
	Cleared: boolean, Over: boolean, Started: number,
}
local runs: { [Player]: Run } = {}
local laneUsed: { [number]: Player } = {}
local halls: { [number]: { Model: Model, Center: Vector3, Seal: BasePart, Glow: BasePart, Prompt: ProximityPrompt, Lights: { PointLight }, Accents: { BasePart } } } = {}

local function zone()
	return Zones.Get("temple")
end

local function event(player: Player, payload)
	Net.Event("Temple"):FireClient(player, payload)
end

-- ===== the halls =====
local function laneCenter(lane: number): Vector3
	local z = zone()
	local n = Temple.Lanes
	local i, j = (lane - 1) % n, math.floor((lane - 1) / n)
	local offset = (n - 1) / 2
	return Vector3.new(
		z.Center.X + (i - offset) * Temple.LaneSpacing,
		Zones.GroundY - Temple.Depth,
		z.Center.Z + (j - offset) * Temple.LaneSpacing
	)
end

local function buildHall(lane: number)
	local center = laneCenter(lane)
	local size = Temple.ChamberSize
	local half = size / 2
	local height = 34
	local m = Instance.new("Model")
	m.Name = "TempleHall" .. lane
	local accents, lights = {}, {}
	local function block(sz: Vector3, cf: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?)
		local p = Instance.new("Part")
		if shape then
			p.Shape = shape
		end
		p.Size = sz
		p.CFrame = cf
		p.Color = color
		p.Material = material
		p.Anchored = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = m
		return p
	end
	local stone, dark = rgb(58, 48, 50), rgb(32, 26, 28)
	block(Vector3.new(size + 8, 4, size + 8), CFrame.new(center - Vector3.new(0, 2, 0)), stone, Enum.Material.Slate)
	block(Vector3.new(size + 8, 4, size + 8), CFrame.new(center + Vector3.new(0, height + 2, 0)), dark, Enum.Material.Slate)
	for _, side in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
		local sx, sz = side[1], side[2]
		local wallSize = if sx ~= 0 then Vector3.new(4, height, size + 8) else Vector3.new(size + 8, height, 4)
		block(wallSize, CFrame.new(center + Vector3.new(sx * (half + 2), height / 2, sz * (half + 2))), stone, Enum.Material.Cobblestone)
	end
	-- floor tiles: a darker cross and a ring of runes round the seal
	block(Vector3.new(size, 0.2, 10), CFrame.new(center + Vector3.new(0, 0.1, 0)), dark, Enum.Material.Slate)
	block(Vector3.new(10, 0.2, size), CFrame.new(center + Vector3.new(0, 0.1, 0)), dark, Enum.Material.Slate)
	-- pillars with braziers, and banners between them
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2 + math.pi / 8
		local at = center + Vector3.new(math.cos(a) * (half - 10), 0, math.sin(a) * (half - 10))
		block(Vector3.new(5, height, 5), CFrame.new(at + Vector3.new(0, height / 2, 0)), dark, Enum.Material.Basalt)
		local flame = block(Vector3.new(2.4, 2.4, 2.4), CFrame.new(at + Vector3.new(0, 8, 0) + (center - at).Unit * 3), rgb(255, 80, 40), Enum.Material.Neon, Enum.PartType.Ball)
		flame.CanCollide = false
		table.insert(accents, flame)
		local light = Instance.new("PointLight")
		light.Color = rgb(255, 90, 50)
		light.Range = 30
		light.Brightness = 2
		light.Parent = flame
		table.insert(lights, light)
	end
	for _, side in ipairs({ -1, 1 }) do
		local banner = block(Vector3.new(10, 18, 0.4), CFrame.new(center + Vector3.new(side * 22, height - 12, -half + 0.4)), rgb(120, 10, 20), Enum.Material.Fabric)
		table.insert(accents, banner)
	end
	-- the seal in the middle (dim until the floor is cleared)
	local seal = block(Vector3.new(0.6, 18, 18), CFrame.new(center + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2), rgb(40, 20, 22), Enum.Material.Slate, Enum.PartType.Cylinder)
	local glow = block(Vector3.new(0.7, 14, 14), CFrame.new(center + Vector3.new(0, 0.35, 0)) * CFrame.Angles(0, 0, math.pi / 2), rgb(90, 20, 20), Enum.Material.Neon, Enum.PartType.Cylinder)
	glow.Transparency = 0.6
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Descend"
	prompt.ObjectText = "The Seal"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt:SetAttribute("TempleDescend", lane)
	prompt.Parent = seal
	-- the way out: an iron door on the south wall
	local door = block(Vector3.new(10, 14, 1), CFrame.new(center + Vector3.new(0, 7, half - 0.5)), rgb(40, 36, 40), Enum.Material.DiamondPlate)
	local leave = Instance.new("ProximityPrompt")
	leave.ActionText = "Leave the Temple"
	leave.ObjectText = "Iron Door"
	leave.HoldDuration = 1
	leave.MaxActivationDistance = 12
	leave.RequiresLineOfSight = false
	leave:SetAttribute("TempleLeave", lane)
	leave.Parent = door
	m.Parent = workspace:FindFirstChild("World") or workspace
	halls[lane] = { Model = m, Center = center, Seal = seal, Glow = glow, Prompt = prompt, Lights = lights, Accents = accents }
end

local function hallOf(lane: number)
	if not halls[lane] then
		buildHall(lane)
	end
	return halls[lane]
end

-- The hall's look for a floor: red at the top, deep purple then black-red at the bottom.
local function tint(lane: number, floor: number)
	local hall = hallOf(lane)
	local k = (floor - 1) / (Temple.Floors - 1)
	local color = rgb(255, 80, 40):Lerp(rgb(170, 40, 255), math.min(1, k * 1.6)):Lerp(rgb(200, 0, 30), math.max(0, k - 0.6) * 2.5)
	for _, p in ipairs(hall.Accents) do
		if p.Material == Enum.Material.Neon then
			p.Color = color
		end
	end
	for _, light in ipairs(hall.Lights) do
		light.Color = color
		light.Brightness = 2 - k
	end
	hall.Glow.Color = rgb(90, 20, 20)
	hall.Glow.Transparency = 0.6
	hall.Prompt.Enabled = false
end

-- ===== runs =====
local function enter(player: Player, lane: number)
	local hall = hallOf(lane)
	local character = player.Character
	if character then
		services.ZoneService:MarkTeleported(player)
		local at = hall.Center + Vector3.new(0, 4, Temple.ChamberSize / 2 - 10)
		character:PivotTo(CFrame.lookAt(at, hall.Center + Vector3.new(0, 4, 0)))
	end
end

local function spawnFloor(run: Run)
	local hall = hallOf(run.Lane)
	local floor = run.Floor
	local level = Temple.Level(floor)
	local hpMult, dmgMult = Temple.Mods(floor)
	tint(run.Lane, floor)
	table.clear(run.Alive)
	run.Cleared = false
	local pool = Temple.Pool(floor)
	local count = Temple.Count(floor)
	local half = Temple.ChamberSize / 2 - 12
	local rng = Random.new()
	local function spawn(defId: string, lvl: number, pos: Vector3, boss: boolean)
		local enemy = services.EnemyService:Spawn(defId, lvl, zone(), pos, {
			GroundY = hall.Center.Y, Temple = run, HealthMult = hpMult, DamageMult = dmgMult, Aggro = Temple.Aggro,
		})
		if enemy then
			run.Alive[enemy] = true
			if boss then
				services.BossService:Manage(enemy)
			end
		end
	end
	if Temple.IsBossFloor(floor) then
		spawn(Temple.BossFor(floor), level, hall.Center + Vector3.new(0, 0, -half + 10), true)
	end
	local guards = if Temple.IsBossFloor(floor) then count - 1 else count
	for _ = 1, guards do
		local pos = hall.Center + Vector3.new(rng:NextNumber(-half, half), 0, rng:NextNumber(-half, half * 0.4))
		spawn(pool[rng:NextInteger(1, #pool)], level + rng:NextInteger(0, 2), pos, false)
	end
	run.Count = 0
	for _ in pairs(run.Alive) do
		run.Count += 1
	end
	event(run.Player, { Type = "Floor", Floor = floor, Count = run.Count, Boss = Temple.IsBossFloor(floor), Level = level, Floors = Temple.Floors })
end

local function finish(run: Run, reason: string)
	if run.Over then
		return
	end
	run.Over = true
	local player = run.Player
	runs[player] = nil
	-- clear the hall of anything left
	for enemy in pairs(run.Alive) do
		if not enemy.Dead then
			enemy.Temple = nil
			services.EnemyService:Kill(enemy, nil)
		end
	end
	table.clear(run.Alive)
	local lane = run.Lane
	task.delay(3, function()
		if laneUsed[lane] == player then
			laneUsed[lane] = nil
		end
	end)
	local data = services.DataService:Get(player)
	if player.Parent then
		event(player, { Type = "End", Reason = reason, Floor = run.Floor, Best = data and data.TempleBest or 0 })
		if reason ~= "died" then
			task.delay(if reason == "victory" then 4 else 0.5, function()
				if player.Parent and not runs[player] then
					services.CharacterService:SpawnAtZone(player, "temple")
				end
			end)
		end
	end
end

function TempleService:StartRun(player: Player, floor: any): (boolean, string?)
	local data = services.DataService:Get(player)
	if not data then
		return false, "Still loading"
	end
	if runs[player] then
		return false, "You're already in the temple"
	end
	if not data.Zones.temple then
		return false, "Unlock The Cursed Temple first"
	end
	if services.DuelService and services.DuelService:InDuel(player) then
		return false, "Finish your duel first"
	end
	local start = if type(floor) == "number" then math.floor(floor) else 1
	if not table.find(Temple.StartFloors(data.TempleBest or 0), start) then
		return false, "You haven't reached that floor yet"
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false, "You need to be alive"
	end
	local lane = nil
	for i = 1, Temple.Lanes * Temple.Lanes do
		if not laneUsed[i] then
			lane = i
			break
		end
	end
	if not lane then
		return false, "The temple is full, try again in a moment"
	end
	laneUsed[lane] = player
	local run: Run = { Player = player, Lane = lane, Floor = start, Alive = {}, Count = 0, Cleared = false, Over = false, Started = os.clock() }
	runs[player] = run
	enter(player, lane)
	humanoid.Health = humanoid.MaxHealth
	task.delay(2, function()
		if not run.Over then
			spawnFloor(run)
		end
	end)
	return true, nil
end

function TempleService:Leave(player: Player): (boolean, string?)
	local run = runs[player]
	if not run then
		return false, "You're not in the temple"
	end
	finish(run, "left")
	return true, nil
end

function TempleService:Descend(player: Player): (boolean, string?)
	local run = runs[player]
	if not run or not run.Cleared then
		return false, "Clear the floor first"
	end
	run.Floor += 1
	run.Cleared = false
	enter(player, run.Lane)
	task.delay(1.5, function()
		if not run.Over then
			spawnFloor(run)
		end
	end)
	return true, nil
end

-- EnemyService:Kill calls this for every temple monster.
function TempleService:OnEnemyKilled(enemy)
	local run = enemy.Temple
	if not run or run.Over or not run.Alive[enemy] then
		return
	end
	run.Alive[enemy] = nil
	local left = 0
	for _ in pairs(run.Alive) do
		left += 1
	end
	event(run.Player, { Type = "Left", Count = left, Total = run.Count })
	if left > 0 then
		return
	end
	-- floor cleared: reward, save the depth, open the seal
	run.Cleared = true
	local player = run.Player
	local data = services.DataService:Get(player)
	local shards, kills = Temple.Reward(run.Floor)
	local coins = math.floor(Balance.EnemyCoins(Temple.Level(run.Floor)) * kills)
	services.ProgressionService:AddShards(player, shards)
	services.ProgressionService:AddCoins(player, coins)
	if data and run.Floor > (data.TempleBest or 0) then
		data.TempleBest = run.Floor
		services.DataService:Changed(player, "TempleBest")
	end
	if run.Floor >= Temple.Floors then
		event(player, { Type = "Cleared", Floor = run.Floor, Shards = shards, Coins = coins, Last = true })
		for _, other in ipairs(Players:GetPlayers()) do
			Net.Event("Notify"):FireClient(other, { Text = player.DisplayName .. " conquered all 100 floors of the Cursed Temple!", Color = rgb(255, 60, 40), Big = true })
		end
		finish(run, "victory")
		return
	end
	local hall = hallOf(run.Lane)
	hall.Glow.Color = rgb(255, 60, 30)
	hall.Glow.Transparency = 0.1
	hall.Prompt.Enabled = true
	event(player, { Type = "Cleared", Floor = run.Floor, Shards = shards, Coins = coins, Checkpoint = (run.Floor + 1) % Temple.CheckpointEvery == 1 })
end

-- In a run? (Other systems check: the duel service, the zone check.)
function TempleService:RunOf(player: Player)
	return runs[player]
end

function TempleService:Init(registry)
	services = registry
end

function TempleService:Start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if prompt:GetAttribute("TempleGate") then
			local data = services.DataService:Get(player)
			if not data then
				return
			end
			if not data.Zones.temple then
				Net.Event("Notify"):FireClient(player, { Text = "Unlock The Cursed Temple in the Areas menu first", Color = rgb(255, 120, 120) })
				return
			end
			event(player, { Type = "Gate", Best = data.TempleBest or 0, Floors = Temple.StartFloors(data.TempleBest or 0) })
		elseif prompt:GetAttribute("TempleDescend") then
			local run = runs[player]
			if run and run.Lane == prompt:GetAttribute("TempleDescend") then
				TempleService:Descend(player)
			end
		elseif prompt:GetAttribute("TempleLeave") then
			local run = runs[player]
			if run and run.Lane == prompt:GetAttribute("TempleLeave") then
				finish(run, "left")
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local run = runs[player]
		if run then
			finish(run, "left")
		end
	end)
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
			if humanoid then
				humanoid.Died:Connect(function()
					local run = runs[player]
					if run then
						finish(run, "died")
					end
				end)
			end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in ipairs(Players:GetPlayers()) do
		hook(player)
	end
end

return TempleService
