--!nocheck
-- Minimal Roblox engine emulation on top of Lune's roblox library.
-- Every Instance handed to game code is a Lua proxy (canonical per instance),
-- so identity, events, computed properties and engine methods all work.
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local task = require("@lune/task")

local RInstance = roblox.Instance
local Vector3, Vector2, CFrame = roblox.Vector3, roblox.Vector2, roblox.CFrame
local Enum = roblox.Enum

local E = {}
E.errors = {}
local seenCount = {}
function E.report(kind, msg)
	msg = tostring(msg)
	local key = kind .. string.sub(msg, 1, 200)
	seenCount[key] = (seenCount[key] or 0) + 1
	table.insert(E.errors, { kind = kind, msg = msg })
	if seenCount[key] <= 1 then
		print("\27[31m[" .. kind .. "]\27[0m " .. msg)
	end
end
local report = E.report
function E.tb(e)
	return tostring(e) .. "\n" .. debug.traceback(nil, 2)
end
local tb = E.tb

-- ===== Signal =====
local Signal = {}
Signal.__index = Signal
function Signal.new(name)
	return setmetatable({ Name = name, Handlers = {}, Waiting = {} }, Signal)
end
function Signal:Connect(fn)
	assert(type(fn) == "function", "Connect expects a function")
	local conn = { Connected = true }
	local entry = { fn = fn }
	table.insert(self.Handlers, entry)
	local sig = self
	function conn:Disconnect()
		self.Connected = false
		local i = table.find(sig.Handlers, entry)
		if i then
			table.remove(sig.Handlers, i)
		end
	end
	return conn
end
function Signal:Once(fn)
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end
function Signal:Wait()
	table.insert(self.Waiting, coroutine.running())
	return coroutine.yield()
end
function Signal:Fire(...)
	local args = table.pack(...)
	for _, entry in ipairs(table.clone(self.Handlers)) do
		task.spawn(function()
			local ok, err = xpcall(entry.fn, tb, table.unpack(args, 1, args.n))
			if not ok then
				report("handler " .. self.Name, err)
			end
		end)
	end
	local waiting = self.Waiting
	self.Waiting = {}
	for _, co in ipairs(waiting) do
		task.spawn(co, table.unpack(args, 1, args.n))
	end
end
E.Signal = Signal

-- ===== proxies =====
local nextId = 0
local proxies = {} -- [id] = proxy
local state = {} -- [id] = { signals, props }
local PROXY = {}
local handlersFor -- forward

local function isProxy(v)
	return type(v) == "table" and getmetatable(v) == PROXY
end
E.isProxy = isProxy

local function idOf(inst)
	local id = inst:GetAttribute("__hid")
	if not id then
		nextId += 1
		id = nextId
		inst:SetAttribute("__hid", id)
	end
	return id
end

local function wrap(v)
	if typeof(v) ~= "Instance" then
		return v
	end
	local id = idOf(v)
	local p = proxies[id]
	if not p then
		p = setmetatable({ __inst = v, __id = id }, PROXY)
		proxies[id] = p
		state[id] = { signals = {}, props = {} }
	end
	return p
end
local function unwrap(v)
	if isProxy(v) then
		return rawget(v, "__inst")
	end
	return v
end
E.wrap, E.unwrap = wrap, unwrap

local function st(p)
	return state[rawget(p, "__id")]
end
local function signalFor(p, name)
	local s = st(p)
	local sig = s.signals[name]
	if not sig then
		sig = Signal.new(rawget(p, "__inst").ClassName .. "." .. name)
		s.signals[name] = sig
	end
	return sig
end
E.signalFor = signalFor

local function wrapAll(...)
	local out = table.pack(...)
	for i = 1, out.n do
		local v = out[i]
		if typeof(v) == "Instance" then
			out[i] = wrap(v)
		elseif type(v) == "table" and not isProxy(v) then
			local t = {}
			for k, x in pairs(v) do
				t[k] = if typeof(x) == "Instance" then wrap(x) else x
			end
			out[i] = t
		end
	end
	return table.unpack(out, 1, out.n)
end
local function unwrapAll(...)
	local out = table.pack(...)
	for i = 1, out.n do
		out[i] = unwrap(out[i])
	end
	return table.unpack(out, 1, out.n)
end

local function stripIds(inst)
	inst:SetAttribute("__hid", nil)
	for _, d in ipairs(inst:GetDescendants()) do
		if d:GetAttribute("__hid") then
			d:SetAttribute("__hid", nil)
		end
	end
end

-- fire ancestry signals for a subtree when it leaves the game
local function fireRemoved(p)
	local sigs = st(p).signals
	if sigs.AncestryChanged then
		sigs.AncestryChanged:Fire(p, nil)
	end
end

PROXY.__index = function(p, key)
	local inst = rawget(p, "__inst")
	local handlers = handlersFor(inst)
	local h = handlers[key]
	if h then
		if h.event then
			return signalFor(p, key)
		elseif h.get then
			return h.get(p)
		elseif h.method then
			return h.method
		end
	end
	local ok, v = pcall(function()
		return inst[key]
	end)
	if not ok then
		local msg = tostring(v)
		if string.find(msg, "missing default value", 1, true) then
			local stored = st(p).props[key]
			if stored ~= nil then
				return stored
			end
			if key == "TextureID" then
				return ""
			end
			report("no-default", inst.ClassName .. "." .. key)
			return nil
		end
		error(inst:GetFullName() .. ": " .. msg, 2)
	end
	if type(v) == "function" then
		return function(self, ...)
			return wrapAll(v(unwrap(self), unwrapAll(...)))
		end
	end
	return wrap(v)
end

PROXY.__newindex = function(p, key, value)
	local inst = rawget(p, "__inst")
	local handlers = handlersFor(inst)
	local h = handlers[key]
	if h and h.set then
		h.set(p, value)
	else
		local oldParent
		if key == "Parent" then
			oldParent = inst.Parent
		end
		local ok, err = pcall(function()
			inst[key] = unwrap(value)
		end)
		if not ok then
			if value == nil and string.find(tostring(err), "'Ref'", 1, true) then
				-- Lune can't clear Ref properties; Roblox allows it
				st(p).props["nil:" .. key] = true
			else
				error(inst:GetFullName() .. "." .. key .. " = " .. tostring(value) .. ": " .. tostring(err), 2)
			end
		end
		if key == "Parent" and value == nil and oldParent ~= nil then
			fireRemoved(p)
		elseif key == "Parent" and value ~= nil then
			local sigs = st(value).signals
			if sigs.ChildAdded then
				sigs.ChildAdded:Fire(p)
			end
		end
	end
	local sigs = st(p).signals
	local sig = sigs["prop:" .. key]
	if sig then
		sig:Fire()
	end
	if sigs.Changed then
		if key == "Value" and inst:IsA("ValueBase") then
			sigs.Changed:Fire(value)
		elseif not inst:IsA("ValueBase") then
			sigs.Changed:Fire(key)
		end
	end
end
PROXY.__tostring = function(p)
	return rawget(p, "__inst").Name
end
PROXY.__eq = function(a, b)
	return rawequal(a, b)
end

-- ===== handlers by class =====
local H = {} -- [className] = { [key] = handler }
local resolved = {}
local function on(class, key, h)
	H[class] = H[class] or {}
	H[class][key] = h
	table.clear(resolved)
end
local function method(class, key, fn)
	on(class, key, { method = fn })
end
local function prop(class, key, get, set)
	on(class, key, { get = get, set = set })
end
local function event(class, ...)
	for _, key in ipairs({ ... }) do
		on(class, key, { event = true })
	end
end
E.method, E.prop, E.event = method, prop, event

function handlersFor(inst)
	local cls = inst.ClassName
	local r = resolved[cls]
	if r then
		return r
	end
	r = {}
	-- apply base classes first so subclasses override
	local order = {}
	for class in pairs(H) do
		if inst:IsA(class) then
			table.insert(order, class)
		end
	end
	-- simple depth heuristic: known base classes first
	local depth = { Instance = 0, PVInstance = 1, GuiBase2d = 1, LayerCollector = 2, GuiObject = 2, BasePart = 2, GuiButton = 3, ValueBase = 1 }
	table.sort(order, function(a, b)
		return (depth[a] or 5) < (depth[b] or 5)
	end)
	for _, class in ipairs(order) do
		for k, h in pairs(H[class]) do
			r[k] = h
		end
	end
	resolved[cls] = r
	return r
end

-- Instance base
event("Instance", "AncestryChanged", "ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "Changed", "Destroying", "AttributeChanged")
method("Instance", "GetPropertyChangedSignal", function(p, name)
	return signalFor(p, "prop:" .. name)
end)
method("Instance", "GetAttributeChangedSignal", function(p, name)
	return signalFor(p, "attr:" .. name)
end)
method("Instance", "SetAttribute", function(p, name, value)
	assert(type(name) == "string", "attribute name must be a string")
	assert(not string.find(name, "^RBX"), "reserved attribute name")
	local t = typeof(value)
	assert(value == nil or t == "string" or t == "number" or t == "boolean" or t == "Vector3" or t == "Vector2" or t == "Color3" or t == "CFrame"
		or t == "UDim2" or t == "UDim" or t == "NumberRange" or t == "NumberSequence" or t == "ColorSequence" or t == "Rect" or t == "BrickColor" or t == "Font",
		"invalid attribute type " .. t .. " for " .. name)
	local inst = rawget(p, "__inst")
	local old = inst:GetAttribute(name)
	inst:SetAttribute(name, value)
	if old ~= value then
		local sig = st(p).signals["attr:" .. name]
		if sig then
			sig:Fire()
		end
		local any = st(p).signals.AttributeChanged
		if any then
			any:Fire(name)
		end
	end
end)
method("Instance", "WaitForChild", function(p, name, timeout)
	local inst = rawget(p, "__inst")
	local t0 = os.clock()
	while true do
		local c = inst:FindFirstChild(name)
		if c then
			return wrap(c)
		end
		if os.clock() - t0 > (timeout or 6) then
			if not timeout then
				report("WaitForChild", inst:GetFullName() .. " never got child '" .. name .. "'")
			end
			return nil
		end
		task.wait(0.05)
	end
end)
method("Instance", "IsDescendantOf", function(p, other)
	local a = rawget(p, "__inst").Parent
	local target = unwrap(other)
	while a do
		if a == target then
			return true
		end
		a = a.Parent
	end
	return false
end)
method("Instance", "Destroy", function(p)
	local inst = rawget(p, "__inst")
	local sigs = st(p).signals
	if sigs.Destroying then
		sigs.Destroying:Fire()
	end
	local hadParent = inst.Parent ~= nil
	inst.Parent = nil
	if hadParent then
		fireRemoved(p)
	end
	for _, d in ipairs(inst:GetDescendants()) do
		local id = d:GetAttribute("__hid")
		if id and proxies[id] then
			fireRemoved(proxies[id])
		end
	end
end)
method("Instance", "Clone", function(p)
	local c = rawget(p, "__inst"):Clone()
	stripIds(c)
	return wrap(c)
end)
method("Instance", "ClearAllChildren", function(p)
	for _, c in ipairs(rawget(p, "__inst"):GetChildren()) do
		wrap(c):Destroy()
	end
end)

-- geometry
local function partsOf(p)
	local list = {}
	local inst = rawget(p, "__inst")
	if inst:IsA("BasePart") then
		table.insert(list, inst)
	end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end
local function pivotOffset(part)
	local ok, offset = pcall(function()
		return part.PivotOffset
	end)
	return if ok and typeof(offset) == "CFrame" then offset else CFrame.identity
end
local function pivotOf(p)
	local inst = rawget(p, "__inst")
	if inst:IsA("BasePart") then
		return inst.CFrame * pivotOffset(inst)
	end
	local pp = inst.PrimaryPart
	if pp then
		return pp.CFrame * pivotOffset(pp)
	end
	if st(p).props.WorldPivot then
		return st(p).props.WorldPivot
	end
	local parts = partsOf(p)
	if parts[1] then
		return CFrame.new(parts[1].CFrame.Position)
	end
	return CFrame.new()
end
method("PVInstance", "GetPivot", pivotOf)
method("PVInstance", "PivotTo", function(p, cf)
	assert(typeof(cf) == "CFrame", "PivotTo expects CFrame")
	local delta = cf * pivotOf(p):Inverse()
	for _, part in ipairs(partsOf(p)) do
		part.CFrame = delta * part.CFrame
	end
	local inst = rawget(p, "__inst")
	if inst:IsA("Model") and not inst.PrimaryPart then
		st(p).props.WorldPivot = cf
	end
end)
prop("Model", "WorldPivot", function(p) return pivotOf(p) end, function(p, cf) st(p).props.WorldPivot = cf end)
method("Model", "SetPrimaryPartCFrame", function(p, cf) p:PivotTo(cf) end)
method("Model", "GetPrimaryPartCFrame", function(p) return pivotOf(p) end)
method("Model", "GetBoundingBox", function(p)
	local minV, maxV
	for _, part in ipairs(partsOf(p)) do
		local half = part.Size / 2
		local pos = part.CFrame.Position
		local lo, hi = pos - half, pos + half
		minV = if minV then Vector3.new(math.min(minV.X, lo.X), math.min(minV.Y, lo.Y), math.min(minV.Z, lo.Z)) else lo
		maxV = if maxV then Vector3.new(math.max(maxV.X, hi.X), math.max(maxV.Y, hi.Y), math.max(maxV.Z, hi.Z)) else hi
	end
	if not minV then
		return CFrame.new(), Vector3.new()
	end
	return CFrame.new((minV + maxV) / 2), maxV - minV
end)
method("Model", "GetExtentsSize", function(p)
	local _, s = p:GetBoundingBox()
	return s
end)
method("Model", "ScaleTo", function(p, s) st(p).props.Scale = s end)
method("Model", "GetScale", function(p) return st(p).props.Scale or 1 end)
method("Model", "TranslateBy", function(p, v) p:PivotTo(pivotOf(p) + v) end)

prop("BasePart", "Position", function(p) return rawget(p, "__inst").CFrame.Position end, function(p, v)
	assert(typeof(v) == "Vector3", "Position expects Vector3")
	local inst = rawget(p, "__inst")
	inst.CFrame = CFrame.new(v) * inst.CFrame.Rotation
end)
prop("BasePart", "Orientation", function(p)
	local rx, ry, rz = rawget(p, "__inst").CFrame:ToOrientation()
	return Vector3.new(math.deg(rx), math.deg(ry), math.deg(rz))
end, function(p, v)
	local inst = rawget(p, "__inst")
	inst.CFrame = CFrame.new(inst.CFrame.Position) * CFrame.fromOrientation(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
end)
prop("BasePart", "Rotation", function(p) return p.Orientation end, function(p, v) p.Orientation = v end)
prop("BasePart", "AssemblyLinearVelocity", function(p) return st(p).props.Vel or Vector3.new() end, function(p, v) st(p).props.Vel = v end)
prop("BasePart", "AssemblyAngularVelocity", function(p) return Vector3.new() end, function() end)
prop("BasePart", "Velocity", function(p) return st(p).props.Vel or Vector3.new() end, function(p, v) st(p).props.Vel = v end)
prop("BasePart", "AssemblyMass", function() return 10 end)
prop("BasePart", "Mass", function() return 10 end)
method("BasePart", "SetNetworkOwner", function() end)
method("BasePart", "GetMass", function() return 10 end)
method("BasePart", "ApplyImpulse", function() end)
event("BasePart", "Touched", "TouchEnded")
prop("Attachment", "WorldPosition", function(p)
	local inst = rawget(p, "__inst")
	local parent = inst.Parent
	return if parent and parent:IsA("BasePart") then (parent.CFrame * inst.CFrame).Position else inst.CFrame.Position
end)
prop("Attachment", "WorldCFrame", function(p)
	local inst = rawget(p, "__inst")
	local parent = inst.Parent
	return if parent and parent:IsA("BasePart") then parent.CFrame * inst.CFrame else inst.CFrame
end)
prop("Attachment", "Position", function(p) return rawget(p, "__inst").CFrame.Position end, function(p, v)
	local inst = rawget(p, "__inst")
	inst.CFrame = CFrame.new(v) * inst.CFrame.Rotation
end)
prop("Attachment", "Orientation", function() return Vector3.new() end, function(p, v)
	local inst = rawget(p, "__inst")
	inst.CFrame = CFrame.new(inst.CFrame.Position) * CFrame.fromOrientation(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
end)
prop("Motor6D", "Transform", function(p) return st(p).props.Transform or CFrame.new() end, function(p, v)
	assert(typeof(v) == "CFrame", "Transform expects CFrame")
	st(p).props.Transform = v
end)

-- GUI
prop("GuiBase2d", "AbsoluteSize", function() return Vector2.new(120, 40) end)
prop("GuiBase2d", "AbsolutePosition", function() return Vector2.new(20, 20) end)
prop("GuiBase2d", "AbsoluteRotation", function() return 0 end)
for _, c in ipairs({ "TextLabel", "TextButton", "TextBox" }) do
	prop(c, "TextBounds", function(p) return Vector2.new(#rawget(p, "__inst").Text * 8, 20) end)
	prop(c, "TextFits", function() return true end)
	prop(c, "ContentText", function(p) return rawget(p, "__inst").Text end)
end
event("GuiObject", "InputBegan", "InputChanged", "InputEnded", "MouseEnter", "MouseLeave", "MouseMoved", "MouseWheelForward", "MouseWheelBackward", "SelectionGained", "SelectionLost")
event("GuiButton", "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "MouseButton2Click")
event("TextBox", "FocusLost", "Focused")
method("TextBox", "CaptureFocus", function() end)
method("TextBox", "ReleaseFocus", function() end)
method("TextBox", "IsFocused", function() return false end)
prop("ScrollingFrame", "AbsoluteCanvasSize", function() return Vector2.new(400, 800) end)
prop("ScrollingFrame", "AbsoluteWindowSize", function() return Vector2.new(400, 400) end)
prop("UIGridStyleLayout", "AbsoluteContentSize", function() return Vector2.new(400, 800) end)
prop("Camera", "ViewportSize", function() return Vector2.new(1280, 720) end)
method("Camera", "WorldToViewportPoint", function() return Vector3.new(640, 360, 10), true end)
method("Camera", "WorldToScreenPoint", function() return Vector3.new(640, 360, 10), true end)
prop("Camera", "Focus", function(p) return st(p).props.Focus or CFrame.new() end, function(p, v) st(p).props.Focus = v end)
prop("BillboardGui", "AbsoluteSize", function() return Vector2.new(150, 40) end)
prop("ScreenGui", "AbsoluteSize", function() return Vector2.new(1280, 720) end) -- UIController fits its roots to this

-- Humanoid
event("Humanoid", "Died", "HealthChanged", "StateChanged", "Running", "MoveToFinished", "Jumping")
method("Humanoid", "TakeDamage", function(p, amount)
	local inst = rawget(p, "__inst")
	p.Health = math.max(0, p.Health - amount)
	signalFor(p, "HealthChanged"):Fire(p.Health)
	if p.Health <= 0 then
		signalFor(p, "Died"):Fire()
	end
end)
method("Humanoid", "MoveTo", function(p, pos)
	assert(typeof(pos) == "Vector3", "MoveTo expects Vector3")
	st(p).props.MoveTo = pos
end)
method("Humanoid", "Move", function() end)
method("Humanoid", "SetStateEnabled", function() end)
method("Humanoid", "ChangeState", function() end)
method("Humanoid", "GetState", function() return Enum.HumanoidStateType.Running end)
method("Humanoid", "UnequipTools", function() end)
method("Humanoid", "ApplyDescription", function() end)
method("Humanoid", "RemoveAccessories", function(p)
	for _, c in ipairs(rawget(p, "__inst").Parent:GetChildren()) do
		if c:IsA("Accessory") then
			c.Parent = nil
		end
	end
end)
method("Humanoid", "GetAppliedDescription", function() return wrap(RInstance.new("HumanoidDescription")) end)
method("Humanoid", "LoadAnimation", function() return { Play = function() end, Stop = function() end, AdjustSpeed = function() end } end)
prop("Humanoid", "RootPart", function(p)
	local parent = rawget(p, "__inst").Parent
	return wrap(parent and parent:FindFirstChild("HumanoidRootPart"))
end)
prop("Humanoid", "Health", function(p) local v = st(p).props.Health if v == nil then return rawget(p, "__inst").MaxHealth end return v end, function(p, v)
	assert(type(v) == "number", "Health expects number")
	st(p).props.Health = math.clamp(v, 0, rawget(p, "__inst").MaxHealth)
end)
prop("Humanoid", "MoveDirection", function() return Vector3.new() end)
prop("Humanoid", "FloorMaterial", function() return Enum.Material.Grass end)
method("Animator", "LoadAnimation", function() return { Play = function() end, Stop = function() end } end)
method("Animator", "GetPlayingAnimationTracks", function() return {} end)

-- misc
method("Sound", "Play", function() end)
method("Sound", "Stop", function() end)
method("Sound", "Pause", function() end)
method("Sound", "Resume", function() end)
prop("Sound", "IsPlaying", function() return false end)
prop("Sound", "IsLoaded", function() return true end)
prop("Sound", "TimeLength", function() return 1 end)
event("Sound", "Ended", "Loaded")
method("ParticleEmitter", "Emit", function(_, n) assert(type(n) == "number" or n == nil, "Emit count") end)
method("ParticleEmitter", "Clear", function() end)
-- Real Roblox throws when terrain is given a non-terrain material (e.g. Glass, Neon, Wood),
-- so check the material argument the same way.
local TERRAIN_MATERIALS = {}
for _, name in ipairs({ "Air", "Water", "Asphalt", "Basalt", "Brick", "Cobblestone", "Concrete", "CrackedLava", "Glacier", "Grass", "Ground", "Ice", "LeafyGrass", "Limestone", "Mud", "Pavement", "Rock", "Salt", "Sand", "Sandstone", "Slate", "Snow", "WoodPlanks" }) do
	TERRAIN_MATERIALS[name] = true
end
local MATERIAL_ARG = { FillBlock = 3, FillBall = 3, FillCylinder = 4, FillWedge = 3, FillRegion = 3, SetMaterialColor = 1 }
for _, m in ipairs({ "FillBlock", "FillBall", "FillCylinder", "FillWedge", "FillRegion", "Clear", "SetMaterialColor", "WriteVoxels", "ReplaceMaterial" }) do
	method("Terrain", m, function(_, ...)
		local args = table.pack(...)
		for i = 1, args.n do
			assert(args[i] ~= nil, "Terrain:" .. m .. " arg " .. i .. " is nil")
		end
		local mi = MATERIAL_ARG[m]
		if mi then
			local material = args[mi]
			assert(typeof(material) == "EnumItem" and TERRAIN_MATERIALS[material.Name], "Terrain:" .. m .. ": " .. tostring(material) .. " is not a terrain material")
		end
	end)
end
method("Terrain", "GetMaterialColor", function() return roblox.Color3.new(1, 1, 1) end)
event("ProximityPrompt", "Triggered", "TriggerEnded", "PromptShown", "PromptHidden")
event("Player", "CharacterAdded", "CharacterRemoving", "CharacterAppearanceLoaded", "Chatted")
event("RemoteEvent", "OnServerEvent", "OnClientEvent")

E.RInstance = RInstance
E.roblox = roblox
E.fs = fs
E.luau = luau
E.task = task
return E
