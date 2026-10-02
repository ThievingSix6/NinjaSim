--[[
	DataService: loading, saving, session locking and replication of player data.

	Reliability rules:
	  * Data is only ever saved if it was loaded successfully. A failed load never
	    produces a blank profile that could overwrite real progress.
	  * Loads retry with backoff; if the store stays down the player is kicked with
	    a friendly message instead of playing on data that cannot be saved.
	  * A session lock (JobId + timestamp inside the saved record) stops two servers
	    from writing the same profile. Stale locks (> LOCK_EXPIRE) are taken over.
	  * Autosave every AUTOSAVE_INTERVAL, save + release on leave, save all on shutdown.
	  * In Studio without API access an in-memory mock store is used automatically.

	Replication: changes are batched per player and flushed once per frame as a
	single DataChanged event carrying only the keys that changed.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TableUtil = require(Shared.Util.TableUtil)
local DataTemplate = require(Shared.DataTemplate)
local Net = require(Shared.Net)

local STORE_NAME = "NinjaSim_PlayerData_v1"
local AUTOSAVE_INTERVAL = 120
local LOCK_EXPIRE = 60 * 10
local LOAD_ATTEMPTS = 6
local SAVE_ATTEMPTS = 4

local DataService = {}
DataService.Profiles = {} :: { [Player]: any }

local loadedCallbacks = {}
local releasingCallbacks = {}
local pending: { [Player]: { [string]: boolean } } = {}
local flushHooks = {}
local store: any
local usingMock = false

-- ===== Store backends =====
local MockStore = {}
MockStore.__index = MockStore
local mockData = {}
function MockStore.UpdateAsync(_self, key: string, transform)
	local result = transform(TableUtil.DeepCopy(mockData[key]))
	if result ~= nil then
		mockData[key] = TableUtil.DeepCopy(result)
	end
	return result
end

local function selectStore()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		-- Probe once: in Studio without API access this errors immediately.
		local probeOk, probeErr = pcall(function()
			return result:GetAsync("__probe")
		end)
		if probeOk or not RunService:IsStudio() then
			return result
		end
		warn("[DataService] DataStore unavailable in Studio (" .. tostring(probeErr) .. "). Using in-memory mock store; progress will not persist between test sessions.")
	elseif not RunService:IsStudio() then
		warn("[DataService] Could not get DataStore: " .. tostring(result))
		return nil
	end
	usingMock = true
	return setmetatable({}, MockStore)
end

local function profileKey(player: Player): string
	return "Player_" .. player.UserId
end

-- ===== Loading =====
local function loadProfile(player: Player)
	local key = profileKey(player)
	for attempt = 1, LOAD_ATTEMPTS do
		if not player.Parent then
			return nil
		end
		local lockedElsewhere = false
		local forceTakeover = attempt >= LOAD_ATTEMPTS - 1
		local ok, result = pcall(function()
			return store:UpdateAsync(key, function(old)
				if old and old.SessionLock and old.SessionLock.JobId ~= game.JobId then
					local age = os.time() - (old.SessionLock.Time or 0)
					if age < LOCK_EXPIRE and not forceTakeover then
						lockedElsewhere = true
						return nil -- cancel write, retry shortly
					end
				end
				local data = old or TableUtil.DeepCopy(DataTemplate)
				data.SessionLock = { JobId = game.JobId, Time = os.time() }
				return data
			end)
		end)
		if ok and result then
			return result
		end
		if not ok then
			warn(string.format("[DataService] Load attempt %d for %s failed: %s", attempt, player.Name, tostring(result)))
		end
		-- locked by another server (usually the one they just left, still saving) or store error
		task.wait(if lockedElsewhere then 3 else math.min(2 ^ attempt, 16))
	end
	return nil
end

-- ===== Saving =====
local function saveProfile(player: Player, release: boolean): boolean
	local profile = DataService.Profiles[player]
	if not profile or not profile.Loaded then
		return false
	end
	local key = profileKey(player)
	local snapshot = TableUtil.DeepCopy(profile.Data)
	for attempt = 1, SAVE_ATTEMPTS do
		local stolen = false
		local ok, err = pcall(function()
			store:UpdateAsync(key, function(old)
				if old and old.SessionLock and old.SessionLock.JobId ~= game.JobId then
					-- another server took over this profile; never overwrite its newer data
					stolen = true
					return nil
				end
				snapshot.SessionLock = if release then nil else { JobId = game.JobId, Time = os.time() }
				return snapshot
			end)
		end)
		if ok then
			if stolen then
				warn("[DataService] Session for " .. player.Name .. " was taken over by another server; skipping save.")
				return false
			end
			profile.LastSave = os.clock()
			return true
		end
		warn(string.format("[DataService] Save attempt %d for %s failed: %s", attempt, player.Name, tostring(err)))
		task.wait(math.min(2 ^ attempt, 8))
	end
	return false
end

-- ===== Public API =====
function DataService:Get(player: Player)
	local profile = self.Profiles[player]
	return if profile and profile.Loaded then profile.Data else nil
end

function DataService:IsUsingMock(): boolean
	return usingMock
end

-- Mark a top-level key as changed (after mutating nested tables).
function DataService:Changed(player: Player, key: string)
	if not self.Profiles[player] then
		return
	end
	local keys = pending[player]
	if not keys then
		keys = {}
		pending[player] = keys
	end
	keys[key] = true
end

function DataService:Set(player: Player, key: string, value: any)
	local data = self:Get(player)
	if not data then
		return
	end
	data[key] = value
	self:Changed(player, key)
end

function DataService:Increment(player: Player, key: string, delta: number)
	local data = self:Get(player)
	if not data then
		return
	end
	data[key] = (data[key] or 0) + delta
	self:Changed(player, key)
end

-- Spend a currency atomically. Returns true if the player could afford it.
function DataService:Spend(player: Player, currency: string, amount: number): boolean
	local data = self:Get(player)
	if not data or type(amount) ~= "number" or amount < 0 or amount ~= amount then
		return false
	end
	if (data[currency] or 0) < amount then
		return false
	end
	data[currency] -= amount
	self:Changed(player, currency)
	return true
end

function DataService:OnLoaded(callback: (Player, any) -> ())
	table.insert(loadedCallbacks, callback)
	for player, profile in pairs(self.Profiles) do
		if profile.Loaded then
			task.spawn(callback, player, profile.Data)
		end
	end
end

-- Wipes a player's progress back to a new save (admin "Reset Progress", for testing).
-- Settings and the daily streak are kept (so the day's reward isn't paid again). The
-- table is refilled in place, so services holding it stay valid.
function DataService:Reset(player: Player): boolean
	local profile = self.Profiles[player]
	if not profile or not profile.Loaded then
		return false
	end
	local data = profile.Data
	local settings, daily = data.Settings, data.Daily
	for key in pairs(data) do
		data[key] = nil
	end
	for key, value in pairs(TableUtil.DeepCopy(DataTemplate)) do
		data[key] = value
	end
	data.Settings = settings or data.Settings
	data.Daily = daily or data.Daily
	pending[player] = nil
	Net.Event("DataSync"):FireClient(player, data)
	for _, callback in ipairs(loadedCallbacks) do
		task.spawn(callback, player, data)
	end
	return true
end

function DataService:OnReleasing(callback: (Player, any) -> ())
	table.insert(releasingCallbacks, callback)
end

-- hook(player, changedKeys, payload) may add derived values to the payload (e.g. stats).
function DataService:AddFlushHook(hook)
	table.insert(flushHooks, hook)
end

function DataService:SaveNow(player: Player)
	return saveProfile(player, false)
end

-- ===== Lifecycle =====
local function onPlayerAdded(player: Player)
	local data = loadProfile(player)
	if not player.Parent then
		-- left while loading: release the lock we may have taken
		if data then
			DataService.Profiles[player] = { Data = data, Loaded = true, LastSave = os.clock() }
			saveProfile(player, true)
			DataService.Profiles[player] = nil
		end
		return
	end
	if not data then
		player:Kick("NinjaSim couldn't load your save right now (Roblox data servers are busy). Your progress is safe - please rejoin in a minute.")
		return
	end
	TableUtil.Reconcile(data, DataTemplate)
	data.SessionLock = nil
	DataService.Profiles[player] = { Data = data, Loaded = true, LastSave = os.clock() }

	Net.Event("DataSync"):FireClient(player, data)
	for _, callback in ipairs(loadedCallbacks) do
		task.spawn(callback, player, data)
	end
end

local function onPlayerRemoving(player: Player)
	local profile = DataService.Profiles[player]
	if not profile then
		return
	end
	for _, callback in ipairs(releasingCallbacks) do
		pcall(callback, player, profile.Data)
	end
	saveProfile(player, true)
	DataService.Profiles[player] = nil
	pending[player] = nil
end

local function flush()
	if next(pending) == nil then
		return
	end
	local batch = pending
	pending = {}
	for player, keys in pairs(batch) do
		local data = DataService:Get(player)
		if data and player.Parent then
			local payload = {}
			for key in pairs(keys) do
				payload[key] = data[key]
			end
			for _, hook in ipairs(flushHooks) do
				hook(player, keys, payload)
			end
			Net.Event("DataChanged"):FireClient(player, payload)
		end
	end
end

function DataService:Init()
	store = selectStore()
	if not store then
		store = setmetatable({}, MockStore)
		usingMock = true
	end
end

function DataService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
	RunService.Heartbeat:Connect(flush)

	-- Staggered autosave
	task.spawn(function()
		while true do
			task.wait(10)
			for player, profile in pairs(DataService.Profiles) do
				if profile.Loaded and os.clock() - profile.LastSave >= AUTOSAVE_INTERVAL then
					task.spawn(saveProfile, player, false)
				end
			end
		end
	end)

	game:BindToClose(function()
		if RunService:IsStudio() and usingMock then
			return
		end
		local remaining = 0
		for player in pairs(DataService.Profiles) do
			remaining += 1
			task.spawn(function()
				saveProfile(player, true)
				remaining -= 1
			end)
		end
		local deadline = os.clock() + 25
		while remaining > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
