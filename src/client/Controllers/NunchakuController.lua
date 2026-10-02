--[[
	NunchakuController: swings the free half of every nunchaku nearby.

	The server welds the held stick into the hand (KatanaBuilder) with a still
	"display" copy of the chain and second stick. On each client that copy is hidden
	and replaced by a free one (KatanaBuilder.BuildFreeHalf) driven here:
	  * during a combo move's Whirl window the stick is spun round the hand in the
	    move's plane (Config/Combo, Combo.Nunchaku), trailing a little like a real chain;
	  * the rest of the time it is a small verlet rope (chain points + a rigid stick)
	    under gravity, so it keeps the whirl's momentum and whips, swings and settles.
	Everything is anchored and client-side: nothing is simulated by the server.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Katanas = require(Shared.Config.Katanas)
local KatanaBuilder = require(Shared.Visuals.KatanaBuilder)

local NunchakuController = {}

local GRAVITY = Vector3.new(0, -110, 0)
local DAMPING = 0.985
local ITERATIONS = 6
local MAX_DISTANCE = 160 -- only simulate nunchaku this close to the camera
local LAG = 0.22 -- radians each point trails the one before it during a whirl

type Rig = {
	Weapon: Model,
	Character: Model,
	Anchor: Attachment,
	Stick: Model,
	Links: { BasePart },
	Lengths: { number }, -- rest length of each segment (chain links, then the stick)
	Points: { Vector3 },
	Prev: { Vector3 },
	Phase: number?, -- whirl angle while a whirl is running
	WhirlMove: any?,
}

local controllers
local rigs: { [Model]: Rig } = {}

local function planeAxes(root: CFrame, plane: string): (Vector3, Vector3)
	if plane == "Side" then
		return root.LookVector, root.UpVector
	elseif plane == "Flat" then
		return root.RightVector, -root.LookVector
	end
	return root.RightVector, root.UpVector -- "Front"
end

local function release(weapon: Model)
	local rig = rigs[weapon]
	if not rig then
		return
	end
	rigs[weapon] = nil
	rig.Stick:Destroy()
	for _, link in ipairs(rig.Links) do
		link:Destroy()
	end
end

local function attach(weapon: Model)
	if rigs[weapon] or weapon:GetAttribute("WeaponType") ~= "Nunchaku" then
		return
	end
	local id = weapon:GetAttribute("KatanaId")
	local def = if type(id) == "string" then Katanas.Get(id) else nil
	local grip = weapon.PrimaryPart or weapon:FindFirstChild("Grip")
	local anchor = grip and grip:FindFirstChild("ChainAnchor")
	local character = weapon.Parent
	if not def or not anchor or not anchor:IsA("Attachment") or not character or not character:IsA("Model") then
		return
	end
	-- hide the still copy; this client draws its own swinging one
	for _, d in ipairs(weapon:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("DisplayHalf") then
			d.Transparency = 1
			d.LocalTransparencyModifier = 1
		end
	end
	local stick, links = KatanaBuilder.BuildFreeHalf(def)
	local stickLength = def.Look.Length or 1.5
	local lengths = {}
	for _ = 1, #links do
		table.insert(lengths, KatanaBuilder.ChainLink)
	end
	table.insert(lengths, stickLength)
	local start = anchor.WorldPosition
	local points, prev = {}, {}
	local y = 0
	for i = 1, #lengths + 1 do
		if i > 1 then
			y -= lengths[i - 1]
		end
		points[i] = start + Vector3.new(0, y, 0)
		prev[i] = points[i]
	end
	stick.Parent = weapon
	for _, link in ipairs(links) do
		link.Parent = weapon -- not inside the stick model, which PivotTo moves as a whole
	end
	rigs[weapon] = {
		Weapon = weapon, Character = character, Anchor = anchor, Stick = stick, Links = links,
		Lengths = lengths, Points = points, Prev = prev,
	}
end

local function watch(character: Model)
	local function check(child: Instance)
		if child.Name == "EquippedKatana" and child:IsA("Model") then
			-- the attributes and parts replicate a moment after the model itself
			task.delay(0.1, attach, child)
		end
	end
	character.ChildAdded:Connect(check)
	character.ChildRemoved:Connect(function(child)
		if child:IsA("Model") and rigs[child] then
			release(child)
		end
	end)
	for _, child in ipairs(character:GetChildren()) do
		check(child)
	end
end

local function lookAlong(from: Vector3, to: Vector3): CFrame
	local dir = to - from
	if dir.Magnitude < 1e-4 then
		return CFrame.new(from)
	end
	local up = if math.abs(dir.Unit.Y) > 0.98 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
	return CFrame.lookAt(from, to, up)
end

local function step(rig: Rig, dt: number)
	local points, prev, lengths = rig.Points, rig.Prev, rig.Lengths
	local anchorPos = rig.Anchor.WorldPosition
	local root = rig.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local move, t = controllers.AnimationController:GetSwing(rig.Character)
	local whirl = move and move.Whirl
	local spinning = whirl and root and t and t >= whirl.From and t <= whirl.To

	if spinning and root then
		local u, v = planeAxes(root.CFrame, whirl.Plane)
		if rig.WhirlMove ~= move or not rig.Phase then
			-- start the spin from wherever the stick hangs now, so it doesn't jump
			local d = points[#points] - anchorPos
			rig.Phase = math.atan2(d:Dot(v), d:Dot(u))
			rig.WhirlMove = move
		end
		local span = (whirl.To - whirl.From) * move.Duration
		local speed = whirl.Turns * math.pi * 2 / math.max(span, 0.05)
		rig.Phase = (rig.Phase :: number) + speed * dt
		local reach = 0
		local sign = if whirl.Turns >= 0 then 1 else -1
		for i = 1, #points do
			if i > 1 then
				reach += lengths[i - 1]
			end
			local a = (rig.Phase :: number) - sign * LAG * (i - 1)
			local target = anchorPos + (u * math.cos(a) + v * math.sin(a)) * reach
			-- keep the old position as "previous" so the momentum carries on afterwards
			prev[i] = points[i]
			points[i] = target
		end
		return
	end
	rig.Phase = nil
	rig.WhirlMove = nil

	-- verlet: integrate, then satisfy the segment lengths with the first point pinned
	local dt2 = dt * dt
	for i = 2, #points do
		local p = points[i]
		local velocity = (p - prev[i]) * DAMPING
		prev[i] = p
		points[i] = p + velocity + GRAVITY * dt2
	end
	points[1] = anchorPos
	prev[1] = anchorPos
	for _ = 1, ITERATIONS do
		points[1] = anchorPos
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			local delta = b - a
			local dist = delta.Magnitude
			if dist > 1e-5 then
				local diff = (dist - lengths[i]) / dist
				if i == 1 then
					points[i + 1] = b - delta * diff
				else
					points[i] = a + delta * diff * 0.5
					points[i + 1] = b - delta * diff * 0.5
				end
			end
		end
	end
end

local function draw(rig: Rig)
	local points = rig.Points
	for i, link in ipairs(rig.Links) do
		local a, b = points[i], points[i + 1]
		-- link cylinders run along X: turn the -Z look frame onto X
		link.CFrame = lookAlong(a, b) * CFrame.new(0, 0, -(b - a).Magnitude / 2) * CFrame.Angles(0, math.pi / 2, 0)
	end
	local n = #points
	rig.Stick:PivotTo(lookAlong(points[n - 1], points[n]))
end

function NunchakuController:Start(c)
	controllers = c
	local function hookPlayer(player: Player)
		player.CharacterAdded:Connect(watch)
		if player.Character then
			watch(player.Character)
		end
	end
	Players.PlayerAdded:Connect(hookPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		hookPlayer(player)
	end

	RunService.Heartbeat:Connect(function(dt)
		dt = math.min(dt, 1 / 30)
		local camera = workspace.CurrentCamera
		local eye = if camera then camera.CFrame.Position else Vector3.zero
		for weapon, rig in pairs(rigs) do
			if not weapon.Parent or not rig.Anchor.Parent then
				release(weapon)
				continue
			end
			if (rig.Anchor.WorldPosition - eye).Magnitude > MAX_DISTANCE then
				continue
			end
			step(rig, dt)
			draw(rig)
		end
	end)
end

return NunchakuController
