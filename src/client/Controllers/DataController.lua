--[[
	DataController: the client's read-only mirror of its own save data and stats.
	UI subscribes with :OnChange(key, fn). Actions go through :Request(), which
	shows a friendly error toast when the server says no.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Stats = require(Shared.Stats)

local DataController = {}

local data: any = nil
local stats: any = nil
local listeners: { [string]: { (any) -> () } } = {}
local readyCallbacks = {}

local function fire(key: string, value: any)
	local list = listeners[key]
	if list then
		for _, fn in ipairs(list) do
			task.spawn(fn, value)
		end
	end
	local any = listeners["*"]
	if any then
		for _, fn in ipairs(any) do
			task.spawn(fn, key, value)
		end
	end
end

function DataController:Get()
	return data
end

function DataController:GetStats()
	if not stats and data then
		stats = Stats.Compute(data)
	end
	return stats
end

function DataController:IsReady(): boolean
	return data ~= nil
end

function DataController:OnReady(fn: (any) -> ())
	if data then
		task.spawn(fn, data)
	else
		table.insert(readyCallbacks, fn)
	end
end

-- Subscribe to a data key ("__Stats" for stats, "*" for everything). Calls immediately if loaded.
function DataController:OnChange(key: string, fn: (any) -> ())
	listeners[key] = listeners[key] or {}
	table.insert(listeners[key], fn)
	if data and key ~= "*" then
		local value = if key == "__Stats" then self:GetStats() else data[key]
		if value ~= nil then
			task.spawn(fn, value)
		end
	end
end

local notifier: ((string, Color3?) -> ())? = nil
local errorSound: (() -> ())? = nil
function DataController:SetFeedback(notify: (string, Color3?) -> (), onError: () -> ())
	notifier = notify
	errorSound = onError
end

-- Invoke a server action. Returns ok, message/result.
function DataController:Request(action: string, ...): (boolean, any)
	local ok, response = pcall(function(...)
		return Net.Function("Request"):InvokeServer(action, ...)
	end, ...)
	if not ok or type(response) ~= "table" then
		if notifier then
			notifier("Connection hiccup, try again", Color3.fromRGB(255, 120, 120))
		end
		return false, nil
	end
	if not response.Ok then
		if response.Message and notifier then
			notifier(response.Message, Color3.fromRGB(255, 120, 120))
		end
		if errorSound then
			errorSound()
		end
		return false, response.Message
	end
	return true, response.Result or response.Message
end

function DataController:Start()
	local function applySnapshot(snapshot)
		data = snapshot
		stats = Stats.Compute(data)
		for key, value in pairs(data) do
			fire(key, value)
		end
		fire("__Stats", stats)
		for _, fn in ipairs(readyCallbacks) do
			task.spawn(fn, data)
		end
		readyCallbacks = {}
	end
	Net.Event("DataSync").OnClientEvent:Connect(applySnapshot)
	-- if the initial snapshot arrived before we were listening, ask for it
	task.spawn(function()
		for _ = 1, 20 do
			task.wait(3)
			if data then
				return
			end
			local ok, response = pcall(function()
				return Net.Function("Request"):InvokeServer("Sync")
			end)
			if ok and type(response) == "table" and response.Ok and type(response.Result) == "table" and not data then
				applySnapshot(response.Result)
				return
			end
		end
	end)
	Net.Event("DataChanged").OnClientEvent:Connect(function(payload)
		if not data then
			return
		end
		for key, value in pairs(payload) do
			if key == "__Stats" then
				stats = value
			else
				data[key] = value
			end
		end
		for key, value in pairs(payload) do
			if key ~= "__Stats" then
				fire(key, value)
			end
		end
		if payload.__Stats then
			fire("__Stats", stats)
		end
	end)
end

return DataController
