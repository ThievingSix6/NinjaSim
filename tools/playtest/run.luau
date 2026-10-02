--!nocheck
local E = require("./engine")
local process = require("@lune/process")
local roblox, task, luau, fs = E.roblox, E.task, E.luau, E.fs
local RInstance = E.RInstance
local wrap, unwrap, isProxy, signalFor, report, tb = E.wrap, E.unwrap, E.isProxy, E.signalFor, E.report, E.tb
local method, prop, event, Signal = E.method, E.prop, E.event, E.Signal
local Vector3, Vector2, CFrame = roblox.Vector3, roblox.Vector2, roblox.CFrame
local Enum = roblox.Enum

local PLACE = process.args[1] or "/mnt/project-files/NinjaSim/NinjaSim.rbxl"

-- ===== datatype polyfills =====
local TweenInfo = { new = function(time, style, dir, rc, rev, delayTime)
	return { Time = time or 1, EasingStyle = style, EasingDirection = dir, RepeatCount = rc or 0, Reverses = rev or false, DelayTime = delayTime or 0 }
end }
local function paramsCtor()
	return { new = function()
		return { FilterType = Enum.RaycastFilterType.Exclude, FilterDescendantsInstances = {}, RespectCanCollide = false, IgnoreWater = false, CollisionGroup = "Default", MaxParts = 0 }
	end }
end
local Random = {}
Random.__index = Random
function Random.new(seed)
	return setmetatable({ s = math.floor((seed or os.clock() * 1e6) % 2147483646) + 1 }, Random)
end
function Random:_n()
	self.s = (self.s * 16807) % 2147483647
	return self.s / 2147483647
end
function Random:NextNumber(a, b)
	a = a or 0
	b = b or 1
	return a + (b - a) * self:_n()
end
function Random:NextInteger(a, b)
	assert(a <= b, "NextInteger range")
	return math.min(b, math.floor(a + (b - a + 1) * self:_n()))
end
function Random:NextUnitVector()
	return Vector3.new(self:NextNumber(-1, 1), self:NextNumber(-1, 1), self:NextNumber(-1, 1)).Unit
end

-- ===== place + camera =====
local rgame = roblox.deserializePlace(fs.readFile(PLACE))
-- NINJA_MESHES=1 pretends the Blender asset packs were imported: one MeshPart per
-- manifest entry under ReplicatedStorage.NinjaAssets, so the mesh code paths run too.
-- NINJA_MESHES=workspace leaves them in one model in Workspace, where Import 3D puts it,
-- so the game has to find and move it itself.
if process.env.NINJA_MESHES == "1" or process.env.NINJA_MESHES == "workspace" then
	local inWorkspace = process.env.NINJA_MESHES == "workspace"
	local rs = rgame:GetService("ReplicatedStorage")
	local folder = RInstance.new(if inWorkspace then "Model" else "Folder")
	folder.Name = if inWorkspace then "NinjaSim_AllAssets" else "NinjaAssets"
	local manifests = rs:FindFirstChild("Shared"):FindFirstChild("Visuals"):FindFirstChild("Manifests")
	local count = 0
	for _, module in ipairs(manifests:GetChildren()) do
		local pack = RInstance.new("Model")
		pack.Name = module.Name
		pack.Parent = folder
		for name, size in string.gmatch(module.Source, '%["([%w_]+)"%] = { Center = Vector3%.new%([^)]*%), Size = Vector3%.new%(([^)]*)%)') do
			local x, y, z = string.match(size, "([%-%d%.]+), ([%-%d%.]+), ([%-%d%.]+)")
			local mesh = RInstance.new("MeshPart")
			mesh.Name = name
			-- the importer keeps proportions but not units (metres -> studs here)
			mesh.Size = Vector3.new(tonumber(x) * 3.57, tonumber(y) * 3.57, tonumber(z) * 3.57)
			mesh.Anchored = true
			mesh.Parent = pack
			count += 1
		end
	end
	-- the UI icon atlas rides along as a textured plane; the importer uploads its texture
	local atlas = RInstance.new("MeshPart")
	atlas.Name = "UIIconAtlas"
	atlas.Size = Vector3.new(3.57, 0.01, 3.57)
	atlas.TextureID = "rbxassetid://1000001"
	atlas.Parent = folder
	folder.Parent = if inWorkspace then rgame:GetService("Workspace") else rs
	print("[harness] pretend-imported " .. count .. " meshes into " .. folder.Parent.Name)
end
local Workspace = wrap(rgame:GetService("Workspace"))
local camera = wrap(RInstance.new("Camera"))
camera.Parent = Workspace
Workspace.CurrentCamera = camera

-- ===== services =====
local players = {}
local PlayersService = wrap(rgame:GetService("Players"))
event("Players", "PlayerAdded", "PlayerRemoving")
method("Players", "GetPlayers", function() return table.clone(players) end)
method("Players", "GetPlayerByUserId", function(_, id)
	for _, p in ipairs(players) do
		if p.UserId == id then
			return p
		end
	end
	return nil
end)
method("Players", "GetPlayerFromCharacter", function(_, character)
	for _, p in ipairs(players) do
		if p.Character == character then
			return p
		end
	end
	return nil
end)
prop("Players", "LocalPlayer", function() return players[1] end)
method("Player", "HasAppearanceLoaded", function() return true end)
method("Player", "Kick", function(_, msg) report("Kick", tostring(msg)) end)
method("Player", "GetMouse", function() return { Hit = CFrame.new(), Target = nil } end)
prop("Player", "Character", function(p) return E.characters[p] end, function(p, v) E.characters[p] = v end)
E.characters = {}

local function buildRig(name)
	local rig = RInstance.new("Model")
	rig.Name = name
	local function part(n, size, pos)
		local p = RInstance.new("Part")
		p.Name = n
		p.Size = size
		p.CFrame = CFrame.new(pos)
		p.Parent = rig
		return p
	end
	local root = part("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0))
	local lower = part("LowerTorso", Vector3.new(2, 0.4, 1), Vector3.new(0, 2.8, 0))
	local upper = part("UpperTorso", Vector3.new(2, 1.6, 1), Vector3.new(0, 3.8, 0))
	local head = part("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 5.2, 0))
	local rua = part("RightUpperArm", Vector3.new(1, 1.2, 1), Vector3.new(1.5, 4, 0))
	part("RightLowerArm", Vector3.new(1, 1.2, 1), Vector3.new(1.5, 3, 0))
	part("RightHand", Vector3.new(1, 0.3, 1), Vector3.new(1.5, 2.2, 0))
	local lua = part("LeftUpperArm", Vector3.new(1, 1.2, 1), Vector3.new(-1.5, 4, 0))
	part("LeftLowerArm", Vector3.new(1, 1.2, 1), Vector3.new(-1.5, 3, 0))
	part("LeftHand", Vector3.new(1, 0.3, 1), Vector3.new(-1.5, 2.2, 0))
	for _, n in ipairs({ "RightUpperLeg", "RightLowerLeg", "RightFoot", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot" }) do
		part(n, Vector3.new(1, 1, 1), Vector3.new(0, 1, 0))
	end
	local function motor(n, p0, p1)
		local m = RInstance.new("Motor6D")
		m.Name = n
		m.Part0 = p0
		m.Part1 = p1
		m.C0 = CFrame.new(0, 0.5, 0)
		m.Parent = p1
	end
	motor("Root", root, lower)
	motor("Waist", lower, upper)
	motor("Neck", upper, head)
	motor("RightShoulder", upper, rua)
	motor("LeftShoulder", upper, lua)
	local att = RInstance.new("Attachment")
	att.Name = "HatAttachment"
	att.Parent = head
	local face = RInstance.new("Decal")
	face.Name = "face"
	face.Parent = head
	local hum = RInstance.new("Humanoid")
	hum.Parent = rig
	RInstance.new("Animator").Parent = hum
	RInstance.new("Shirt").Parent = rig
	local acc = RInstance.new("Accessory")
	acc.Parent = rig
	rig.PrimaryPart = root
	return wrap(rig)
end
method("Player", "LoadCharacter", function(p)
	local old = p.Character
	if old then
		signalFor(p, "CharacterRemoving"):Fire(old)
		old:Destroy()
	end
	local rig = buildRig(p.Name)
	p.Character = rig
	rig.Parent = Workspace
	signalFor(p, "CharacterAdded"):Fire(rig)
	signalFor(p, "CharacterAppearanceLoaded"):Fire(rig)
end)

method("TweenService", "Create", function(_, obj, info, props)
	assert(isProxy(obj), "Tween target must be an Instance")
	assert(type(info) == "table", "TweenInfo expected")
	for k, v in pairs(props) do
		local ok, err = pcall(function()
			local cur = obj[k]
			assert(typeof(cur) == typeof(v), "type mismatch " .. typeof(cur) .. " vs " .. typeof(v))
			local TWEENABLE = { number = true, boolean = true, CFrame = true, Rect = true, Color3 = true, UDim = true, UDim2 = true, Vector2 = true, Vector2int16 = true, Vector3 = true }
			assert(TWEENABLE[typeof(v)], typeof(v) .. " cannot be tweened in Roblox")
		end)
		if not ok then
			report("Tween", unwrap(obj):GetFullName() .. "." .. k .. ": " .. tostring(err))
		end
	end
	local tween = { Completed = Signal.new("Tween.Completed"), PlaybackState = Enum.PlaybackState.Begin, Instance = obj }
	function tween.Play(self)
		task.delay(math.min(info.Time or 0, 0.05), function()
			for k, v in pairs(props) do
				local ok, err = pcall(function()
					obj[k] = v
				end)
				if not ok and not string.find(tostring(err), "Parent", 1, true) then
					-- destroyed targets are fine, other failures are not
					if unwrap(obj).Parent ~= nil then
						report("TweenSet", tostring(err))
					end
				end
			end
			self.PlaybackState = Enum.PlaybackState.Completed
			self.Completed:Fire(Enum.PlaybackState.Completed)
		end)
	end
	function tween.Cancel() end
	function tween.Pause() end
	function tween.Destroy() end
	return tween
end)

local tagged = {}
local CS = wrap(rgame:GetService("CollectionService"))
method("CollectionService", "AddTag", function(_, inst, tag)
	assert(isProxy(inst), "AddTag instance")
	assert(type(tag) == "string", "AddTag tag")
	unwrap(inst):AddTag(tag)
	tagged[tag] = tagged[tag] or {}
	if not table.find(tagged[tag], inst) then
		table.insert(tagged[tag], inst)
	end
	signalFor(CS, "added:" .. tag):Fire(inst)
end)
method("CollectionService", "RemoveTag", function(_, inst, tag)
	unwrap(inst):RemoveTag(tag)
	signalFor(CS, "removed:" .. tag):Fire(inst)
end)
method("CollectionService", "HasTag", function(_, inst, tag) return unwrap(inst):HasTag(tag) end)
method("CollectionService", "GetTagged", function(_, tag)
	local out = {}
	for _, inst in ipairs(tagged[tag] or {}) do
		local r = unwrap(inst)
		if r.Parent and r:HasTag(tag) then
			table.insert(out, inst)
		end
	end
	return out
end)
method("CollectionService", "GetInstanceAddedSignal", function(_, tag) return signalFor(CS, "added:" .. tag) end)
method("CollectionService", "GetInstanceRemovedSignal", function(_, tag) return signalFor(CS, "removed:" .. tag) end)
-- fire tag-removed when a tagged instance is destroyed
local origDestroyed = {}
local _ = origDestroyed

local stores = {}
method("DataStoreService", "GetDataStore", function(_, name)
	stores[name] = stores[name] or {}
	local data = stores[name]
	local store = {}
	function store.GetAsync(_, key) return data[key] end
	function store.SetAsync(_, key, value) data[key] = value end
	function store.UpdateAsync(_, key, fn)
		local result = fn(data[key])
		if result ~= nil then
			-- DataStores only accept JSON-able data
			local function check(v, path)
				local t = typeof(v)
				if t == "table" then
					for k, x in pairs(v) do
						assert(type(k) == "string" or type(k) == "number", "non-JSON key at " .. path)
						check(x, path .. "." .. tostring(k))
					end
				else
					assert(t == "string" or t == "number" or t == "boolean", "non-JSON value (" .. t .. ") at " .. path)
				end
			end
			check(result, "root")
			data[key] = result
		end
		return result
	end
	return store
end)
method("PhysicsService", "RegisterCollisionGroup", function() end)
method("PhysicsService", "CollisionGroupSetCollidable", function() end)
method("PhysicsService", "IsCollisionGroupRegistered", function() return false end)
method("Debris", "AddItem", function(_, inst, t)
	task.delay(math.min(t or 10, 2), function()
		pcall(function() inst:Destroy() end)
	end)
end)
method("StarterGui", "SetCoreGuiEnabled", function() end)
method("StarterGui", "SetCore", function() end)
method("TextService", "GetTextSize", function(_, text, size) return Vector2.new(#text * size * 0.55, size) end)
prop("GuiService", "TopbarInset", function() return roblox.Rect.new(0, 0, 1280, 58) end)
event("UserInputService", "InputBegan", "InputChanged", "InputEnded", "TouchStarted", "LastInputTypeChanged", "JumpRequest")
method("UserInputService", "GetFocusedTextBox", function() return nil end)
prop("UserInputService", "TouchEnabled", function() return false end)
prop("UserInputService", "KeyboardEnabled", function() return true end)
prop("UserInputService", "GamepadEnabled", function() return false end)
method("UserInputService", "GetLastInputType", function() return Enum.UserInputType.Keyboard end)
method("UserInputService", "IsKeyDown", function() return false end)
event("ProximityPromptService", "PromptTriggered", "PromptShown", "PromptHidden")
method("ContentProvider", "PreloadAsync", function() end)
method("Workspace", "Raycast", function(_, origin, dir, params)
	assert(typeof(origin) == "Vector3" and typeof(dir) == "Vector3", "Raycast args")
	if dir.Y < 0 and origin.Y > 0 and origin.Y + dir.Y <= 0 then
		local t = origin.Y / -dir.Y
		return { Position = origin + dir * t, Normal = Vector3.new(0, 1, 0), Instance = Workspace.Terrain, Material = Enum.Material.Grass, Distance = dir.Magnitude * t }
	end
	return nil
end)
method("Workspace", "BulkMoveTo", function(_, parts, cfs)
	assert(#parts == #cfs, "BulkMoveTo size mismatch")
	for i, p in ipairs(parts) do
		assert(typeof(cfs[i]) == "CFrame", "BulkMoveTo cframe")
		unwrap(p).CFrame = cfs[i]
	end
end)
method("Workspace", "GetPartBoundsInRadius", function() return {} end)
E.timeOffset = 0 -- scenarios can skip ahead in "server time" (e.g. gift timers)
method("Workspace", "GetServerTimeNow", function() return os.clock() + E.timeOffset end)

-- remotes
-- Copies a remote argument the way Roblox serialises it, and reports data that
-- Roblox would silently drop (mixed tables, sparse arrays) or refuse (functions).
local function copy(v, seen, path)
	path = path or "arg"
	local tv = type(v)
	if tv == "function" or tv == "thread" then
		report("Remote", path .. ": " .. tv .. " values can't be sent over a remote")
		return nil
	end
	if tv ~= "table" or isProxy(v) then
		return v
	end
	seen = seen or {}
	if seen[v] then
		report("Remote", path .. ": cyclic table can't be sent over a remote")
		return seen[v]
	end
	local out = {}
	seen[v] = out
	local n = #v
	local numeric, strings, other = 0, 0, 0
	for k in pairs(v) do
		if type(k) == "number" then
			numeric += 1
		elseif type(k) == "string" then
			strings += 1
		else
			other += 1
		end
	end
	if numeric > 0 and strings > 0 then
		report("Remote", path .. ": mixed table (array + string keys); Roblox drops part of it")
	elseif numeric > 0 and numeric ~= n then
		report("Remote", path .. ": sparse array; Roblox cuts it off at the first gap")
	end
	for k, x in pairs(v) do
		out[copy(k, seen, path)] = copy(x, seen, path .. "." .. tostring(k))
	end
	return out
end
local function copyArgs(...)
	local a = table.pack(...)
	for i = 1, a.n do
		a[i] = copy(a[i])
	end
	return a
end
method("RemoteEvent", "FireClient", function(self, player, ...)
	assert(isProxy(player) and unwrap(player).ClassName == "Player", "FireClient needs a Player")
	local a = copyArgs(...)
	signalFor(self, "OnClientEvent"):Fire(table.unpack(a, 1, a.n))
end)
method("RemoteEvent", "FireAllClients", function(self, ...)
	local a = copyArgs(...)
	signalFor(self, "OnClientEvent"):Fire(table.unpack(a, 1, a.n))
end)
method("RemoteEvent", "FireServer", function(self, ...)
	local a = copyArgs(...)
	signalFor(self, "OnServerEvent"):Fire(players[1], table.unpack(a, 1, a.n))
end)
local invokers = {}
prop("RemoteFunction", "OnServerInvoke", function(self) return invokers[self] end, function(self, fn) invokers[self] = fn end)
method("RemoteFunction", "InvokeServer", function(self, ...)
	local t0 = os.clock()
	while not invokers[self] and os.clock() - t0 < 6 do
		task.wait(0.05)
	end
	assert(invokers[self], "no OnServerInvoke on " .. unwrap(self).Name)
	local a = copyArgs(...)
	local r = copyArgs(invokers[self](players[1], table.unpack(a, 1, a.n)))
	return table.unpack(r, 1, r.n)
end)

-- ===== run services + frame loop =====
local function makeRunService(isServer)
	local rs = {}
	for _, n in ipairs({ "Heartbeat", "Stepped", "RenderStepped", "PreSimulation", "PostSimulation", "PreRender" }) do
		rs[n] = Signal.new(n)
	end
	function rs.IsServer() return isServer end
	function rs.IsClient() return not isServer end
	function rs.IsStudio() return true end
	function rs.IsRunning() return true end
	local binds = {}
	function rs.BindToRenderStep(_, name, _, fn) binds[name] = rs.RenderStepped:Connect(fn) end
	function rs.UnbindFromRenderStep(_, name) if binds[name] then binds[name]:Disconnect() end end
	return rs
end
local serverRun, clientRun = makeRunService(true), makeRunService(false)
local frames = 0
task.spawn(function()
	local last = os.clock()
	while true do
		task.wait(1 / 30)
		frames += 1
		local now = os.clock()
		local dt = now - last
		last = now
		for _, rs in ipairs({ serverRun, clientRun }) do
			rs.Stepped:Fire(now, dt)
			rs.Heartbeat:Fire(dt)
		end
		clientRun.RenderStepped:Fire(dt)
	end
end)

-- ===== script environments =====
local bindToClose = {}
local function makeEnv(isServer)
	local cache = {}
	local gameProxy = setmetatable({}, { __index = function(_, k)
		if k == "GetService" or k == "FindService" then
			return function(_, name)
				if name == "RunService" then
					return if isServer then serverRun else clientRun
				end
				return wrap(rgame:GetService(name))
			end
		elseif k == "BindToClose" then
			return function(_, fn) table.insert(bindToClose, fn) end
		elseif k == "PlaceId" then
			return 0
		elseif k == "JobId" then
			return "harness-job"
		elseif k == "GameId" then
			return 0
		end
		return wrap(rgame)[k]
	end })
	local function guard(fn, where)
		return function(...)
			local ok, err = xpcall(fn, tb, ...)
			if not ok then
				report("task." .. where, err)
			end
		end
	end
	local wtask = {
		spawn = function(fn, ...) if type(fn) == "thread" then return task.spawn(fn, ...) end return task.spawn(guard(fn, "spawn"), ...) end,
		defer = function(fn, ...) if type(fn) == "thread" then return task.defer(fn, ...) end return task.defer(guard(fn, "defer"), ...) end,
		delay = function(t, fn, ...) return task.delay(t, guard(fn, "delay"), ...) end,
		wait = function(t) return task.wait(t or 1 / 60) end,
		cancel = task.cancel,
		synchronize = function() end,
		desynchronize = function() end,
	}
	local base = {
		game = gameProxy, workspace = Workspace, Workspace = Workspace,
		Instance = { new = function(className, parent)
			local i = wrap(RInstance.new(className))
			if parent then
				i.Parent = parent
			end
			return i
		end },
		Vector3 = Vector3, Vector2 = Vector2, CFrame = CFrame, Color3 = roblox.Color3, UDim2 = roblox.UDim2, UDim = roblox.UDim,
		Enum = Enum, NumberSequence = roblox.NumberSequence, NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequence = roblox.ColorSequence, ColorSequenceKeypoint = roblox.ColorSequenceKeypoint, NumberRange = roblox.NumberRange,
		Rect = roblox.Rect, BrickColor = roblox.BrickColor, PhysicalProperties = roblox.PhysicalProperties, Font = roblox.Font,
		Ray = roblox.Ray, Region3 = roblox.Region3, Faces = roblox.Faces, Axes = roblox.Axes,
		TweenInfo = TweenInfo, RaycastParams = paramsCtor(), OverlapParams = paramsCtor(), Random = Random,
		DateTime = { now = function() return { UnixTimestamp = os.time(), UnixTimestampMillis = os.time() * 1000 } end },
		task = wtask,
		typeof = function(v) if isProxy(v) then return "Instance" end return typeof(v) end,
		tick = os.clock, time = os.clock, elapsedTime = os.clock,
		warn = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[i] = tostring((select(i, ...)))
			end
			report("warn", table.concat(parts, " "))
		end,
		print = function(...) print("[game]", ...) end,
		shared = {}, _G = {},
		wait = function(t) return task.wait(t) end,
		delay = function(t, fn) return wtask.delay(t, fn) end,
		spawn = function(fn) return wtask.spawn(fn) end,
	}
	local builtins = { "math", "string", "table", "coroutine", "utf8", "bit32", "buffer", "debug", "os", "pcall", "xpcall", "error", "assert",
		"select", "type", "tostring", "tonumber", "pairs", "ipairs", "next", "setmetatable", "getmetatable", "rawget", "rawset", "rawequal", "rawlen", "newproxy", "gcinfo" }
	local requireModule
	local function envFor(scriptProxy)
		local e = { script = scriptProxy, require = requireModule }
		for k, v in pairs(base) do
			e[k] = v
		end
		for _, k in ipairs(builtins) do
			e[k] = getfenv(0)[k]
		end
		e.unpack = table.unpack
		return e
	end
	function requireModule(module)
		assert(isProxy(module), "require expects a ModuleScript instance, got " .. typeof(module))
		local r = unwrap(module)
		local key = r:GetFullName()
		if cache[key] ~= nil then
			return cache[key]
		end
		local fn = luau.load(r.Source, { debugName = key, environment = envFor(module) })
		local result = fn()
		cache[key] = result
		return result
	end
	local function run(scriptProxy)
		local r = unwrap(scriptProxy)
		local fn = luau.load(r.Source, { debugName = r:GetFullName(), environment = envFor(scriptProxy) })
		task.spawn(function()
			local ok, err = xpcall(fn, tb)
			if not ok then
				report("script " .. r:GetFullName(), err)
			end
		end)
	end
	return run, cache
end

local runServer, S = makeEnv(true)
local runClient, C = makeEnv(false)

-- ===== boot =====
local SSS = wrap(rgame:GetService("ServerScriptService"))
runServer(SSS.Server.Main)
task.wait(1.5)
local tagCounts = {}
for tag, list in pairs(tagged) do
	table.insert(tagCounts, tag .. "=" .. #list)
end
print("world built; tags: " .. table.concat(tagCounts, " "))

local player = wrap(RInstance.new("Player"))
player.Name = "TestNinja"
player.UserId = 12345
player.DisplayName = "TestNinja"
wrap(RInstance.new("PlayerGui")).Parent = player
player.Parent = PlayersService
table.insert(players, player)
signalFor(PlayersService, "PlayerAdded"):Fire(player)

local SP = wrap(rgame:GetService("StarterPlayer"))
local clientFolder = SP.StarterPlayerScripts.Client:Clone()
local ps = wrap(RInstance.new("PlayerScripts"))
ps.Parent = player
clientFolder.Parent = ps
task.wait(0.2)
runClient(clientFolder.Main)
task.wait(0.3)
player:LoadCharacter()
task.wait(3)

E.S, E.C, E.player, E.players, E.stores, E.tagged, E.CS, E.Workspace, E.bindToClose = S, C, player, players, stores, tagged, CS, Workspace, bindToClose
E.sm = function(name) return S["ServerScriptService.Server.Services." .. name] end
E.cm = function(path) return C["Players.TestNinja.PlayerScripts.Client." .. path] end
E.shared = function(path) return S["ReplicatedStorage.Shared." .. path] end
E.frames = function() return frames end
E.PlayersService = PlayersService
E.rgame = rgame
E.RInstance = RInstance

local scenario = if process.env.SCENARIO == "uishots" then require("./uishots")
	elseif process.env.SCENARIO == "petshots" then require("./petshots")
	else require("./scenario")
scenario(E)

print(string.format("\n\27[1m%d problem reports\27[0m", #E.errors))
local kinds = {}
for _, e in ipairs(E.errors) do
	kinds[e.kind] = (kinds[e.kind] or 0) + 1
end
for k, n in pairs(kinds) do
	print("  " .. k .. ": " .. n)
end
process.exit(0)
