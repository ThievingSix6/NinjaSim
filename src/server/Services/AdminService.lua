--[[
	AdminService: the admin panel's server side.

	Ranks: "Owner" (the game's creator, group owner, Config/Admins.Owners, or
	anyone testing in Studio) and "Admin" (Config/Admins.Admins, or appointed in
	game by an owner and saved in the "NinjaSim_Admins" DataStore so it holds in
	every server). The rank is mirrored to the player attribute "NinjaAdmin" so the
	client knows to show the panel; every command is checked again here.

	Commands come through RequestService ("Admin", command, targetUserId, value).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local AdminConfig = require(ReplicatedStorage.Shared.Config.Admins)
local Zones = require(ReplicatedStorage.Shared.Config.Zones)
local Events = require(ReplicatedStorage.Shared.Config.Events)
local Pets = require(ReplicatedStorage.Shared.Config.Pets)
local Mutations = require(ReplicatedStorage.Shared.Config.Mutations)

local AdminService = {}

local services
local STORE_KEY = "Admins"
local store: DataStore? = nil
local appointed: { [string]: string } = {} -- userId -> name, from the DataStore
local god: { [Player]: boolean? } = {}

local function log(admin: Player, text: string)
	print(string.format("[NinjaSim][Admin] %s: %s", admin.Name, text))
end

local function isOwner(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if table.find(AdminConfig.Owners, player.UserId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	local ok, rank = pcall(function()
		return player:GetRankInGroupAsync(game.CreatorId)
	end)
	return ok and rank == 255
end

function AdminService:Rank(player: Player): string?
	if isOwner(player) then
		return "Owner"
	end
	if table.find(AdminConfig.Admins, player.UserId) or appointed[tostring(player.UserId)] then
		return "Admin"
	end
	return nil
end

local function refreshAttribute(player: Player)
	local rank = AdminService:Rank(player)
	if player:GetAttribute("NinjaAdmin") ~= rank then
		player:SetAttribute("NinjaAdmin", rank)
	end
end

local function loadAppointed()
	if not store then
		return
	end
	local ok, value = pcall(function()
		return (store :: DataStore):GetAsync(STORE_KEY)
	end)
	if ok and type(value) == "table" then
		appointed = value
	end
end

-- Changes the saved admin list in one atomic update; the local copy follows.
local function saveAppointed(change: ({ [string]: string }) -> ())
	change(appointed)
	if not store then
		return
	end
	pcall(function()
		(store :: DataStore):UpdateAsync(STORE_KEY, function(old)
			local list = if type(old) == "table" then old else {}
			change(list)
			appointed = list
			return list
		end)
	end)
end

local function findPlayer(userId: any): Player?
	if type(userId) ~= "number" then
		return nil
	end
	return Players:GetPlayerByUserId(userId)
end

local function amountOf(value: any): number?
	local n = tonumber(value)
	if not n or n ~= n or math.abs(n) == math.huge then
		return nil
	end
	return math.clamp(math.floor(n), -AdminConfig.MaxGrant, AdminConfig.MaxGrant)
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function setGod(player: Player, on: boolean)
	god[player] = if on then true else nil
	local character = player.Character
	if not character then
		return
	end
	local existing = character:FindFirstChild("AdminGod")
	if on and not existing then
		local field = Instance.new("ForceField")
		field.Name = "AdminGod"
		field.Visible = false
		field.Parent = character
	elseif not on and existing then
		existing:Destroy()
	end
end

local function addLevels(player: Player, n: number)
	local data = services.DataService:Get(player)
	if not data then
		return
	end
	local before = data.Level
	data.Level = math.clamp(data.Level + n, 1, 100000)
	data.XP = 0
	if data.Level > data.Lifetime.HighestLevel then
		data.Lifetime.HighestLevel = data.Level
		services.DataService:Changed(player, "Lifetime")
	end
	services.DataService:Changed(player, "Level")
	services.DataService:Changed(player, "XP")
	services.StatService:Refresh(player)
	if data.Level > before then
		Net.Event("LevelUp"):FireClient(player, data.Level, data.Level - before)
	end
	services.ProgressionService:CheckTier(player)
end

local function addCurrency(player: Player, key: string, n: number)
	local data = services.DataService:Get(player)
	if not data then
		return
	end
	if n > 0 then
		if key == "Coins" then
			services.ProgressionService:AddCoins(player, n)
		else
			services.ProgressionService:AddShards(player, n)
		end
	else
		data[key] = math.max(0, data[key] + n)
		services.DataService:Changed(player, key)
	end
end

-- command -> handler(admin, target?, value) -> (ok, message). `Target` says whether a player is needed.
local COMMANDS: { [string]: { Owner: boolean?, Target: boolean?, Run: (Player, Player?, any) -> (boolean, string?) } } = {
	Coins = {
		Target = true,
		Run = function(_admin, target, value)
			local n = amountOf(value)
			if not n or n == 0 then
				return false, "Type an amount first"
			end
			addCurrency(target :: Player, "Coins", n)
			return true, string.format("%s %d coins to %s", if n > 0 then "Gave" else "Took", math.abs(n), (target :: Player).DisplayName)
		end,
	},
	Shards = {
		Target = true,
		Run = function(_admin, target, value)
			local n = amountOf(value)
			if not n or n == 0 then
				return false, "Type an amount first"
			end
			addCurrency(target :: Player, "Shards", n)
			return true, string.format("%s %d shards to %s", if n > 0 then "Gave" else "Took", math.abs(n), (target :: Player).DisplayName)
		end,
	},
	Levels = {
		Target = true,
		Run = function(_admin, target, value)
			local n = amountOf(value)
			if not n or n == 0 then
				return false, "Type how many levels"
			end
			addLevels(target :: Player, n)
			return true, string.format("%s is now level %d", (target :: Player).DisplayName, services.DataService:Get(target).Level)
		end,
	},
	Mastery = {
		Target = true,
		Run = function(_admin, target, value)
			local n = amountOf(value)
			if not n or n < 1 then
				return false, "Type a mastery level (1-100)"
			end
			if not services.MasteryService:SetLevel(target :: Player, n) then
				return false, "Still loading"
			end
			return true, string.format("%s's worn suit is now Mastery %d", (target :: Player).DisplayName, math.clamp(math.floor(n), 1, 100))
		end,
	},
	UnlockZones = {
		Target = true,
		Run = function(_admin, target)
			local data = services.DataService:Get(target :: Player)
			if not data then
				return false, "Still loading"
			end
			for _, zone in ipairs(Zones.List) do
				data.Zones[zone.Id] = true
			end
			services.DataService:Changed(target :: Player, "Zones")
			return true, "Unlocked every area for " .. (target :: Player).DisplayName
		end,
	},
	UnlockSkills = {
		Target = true,
		Run = function(_admin, target)
			if not services.SkillService then
				return false, "Skills are not running"
			end
			local n = services.SkillService:UnlockAll(target :: Player)
			return true, string.format("Unlocked %d skills for %s", n, (target :: Player).DisplayName)
		end,
	},
	-- "golden fox" / "Rainbow Jade Dragon" gives that pet; a mutation alone ("Giant")
	-- makes the target's next hatch that mutation (to see the hatch reveal).
	GivePet = {
		Target = true,
		Run = function(_admin, target, value)
			if type(value) ~= "string" or #value == 0 then
				return false, "Type a mutation and/or pet, e.g. \"golden fox\" or \"Rainbow\""
			end
			local text = string.lower(string.sub(value, 1, 80))
			local mutation = nil
			local rest = {}
			for word in string.gmatch(text, "%S+") do
				local found = Mutations.Find(word)
				if found and not mutation then
					mutation = found
				else
					table.insert(rest, word)
				end
			end
			local query = table.concat(rest, " ")
			local t = target :: Player
			if query == "" then
				if not mutation then
					return false, "Unknown mutation or pet"
				end
				services.PetService:ForceNextMutation(t, mutation)
				return true, t.DisplayName .. "'s next hatch will be " .. mutation
			end
			local pet = nil
			for _, def in ipairs(Pets.List) do
				if def.Id == query or string.lower(def.Name) == query or def.Id == (string.gsub(query, " ", "_")) then
					pet = def
					break
				end
			end
			if not pet then
				return false, "No pet called \"" .. query .. "\""
			end
			if not services.PetService:Grant(t, pet.Id, mutation) then
				return false, "Still loading"
			end
			return true, "Gave " .. Pets.DisplayName(pet, mutation) .. " to " .. t.DisplayName
		end,
	},
	ResetProgress = {
		Target = true,
		Run = function(_admin, target, value)
			if type(value) ~= "string" or string.lower(value) ~= "reset" then
				return false, "Type RESET in the box, then press Reset Progress again"
			end
			setGod(target :: Player, false)
			if not services.DataService:Reset(target :: Player) then
				return false, "Still loading"
			end
			services.StatService:Refresh(target :: Player)
			task.defer(function()
				if (target :: Player).Parent then
					(target :: Player):LoadCharacter()
				end
			end)
			return true, "Reset all progress for " .. (target :: Player).DisplayName
		end,
	},
	Heal = {
		Target = true,
		Run = function(_admin, target)
			local humanoid = (target :: Player).Character and ((target :: Player).Character :: Model):FindFirstChildOfClass("Humanoid")
			if not humanoid or humanoid.Health <= 0 then
				return false, "They have no living character"
			end
			humanoid.Health = humanoid.MaxHealth
			return true, "Healed " .. (target :: Player).DisplayName
		end,
	},
	God = {
		Target = true,
		Run = function(_admin, target)
			local on = not god[target :: Player]
			setGod(target :: Player, on)
			return true, string.format("God mode %s for %s", if on then "ON" else "OFF", (target :: Player).DisplayName)
		end,
	},
	Kill = {
		Target = true,
		Run = function(_admin, target)
			local humanoid = (target :: Player).Character and ((target :: Player).Character :: Model):FindFirstChildOfClass("Humanoid")
			if not humanoid then
				return false, "They have no character"
			end
			setGod(target :: Player, false)
			humanoid.Health = 0
			return true, "Knocked out " .. (target :: Player).DisplayName
		end,
	},
	GoTo = {
		Target = true,
		Run = function(admin, target)
			local from, to = rootOf(admin), rootOf(target :: Player)
			if not from or not to then
				return false, "No character to move"
			end
			services.ZoneService:MarkTeleported(admin)
			from.CFrame = to.CFrame * CFrame.new(0, 0, 5)
			return true, "Teleported to " .. (target :: Player).DisplayName
		end,
	},
	Bring = {
		Target = true,
		Run = function(admin, target)
			local here, them = rootOf(admin), rootOf(target :: Player)
			if not here or not them then
				return false, "No character to move"
			end
			services.ZoneService:MarkTeleported(target :: Player)
			them.CFrame = here.CFrame * CFrame.new(0, 0, -5)
			return true, "Brought " .. (target :: Player).DisplayName
		end,
	},
	Kick = {
		Target = true,
		Run = function(admin, target, value)
			if target == admin then
				return false, "You can't kick yourself"
			end
			if AdminService:Rank(target :: Player) == "Owner" then
				return false, "Owners can't be kicked"
			end
			local reason = if type(value) == "string" and #value > 0 then string.sub(value, 1, 100) else "Kicked by an admin"
			local ok, filtered = pcall(function()
				return TextService:FilterStringAsync(reason, admin.UserId):GetNonChatStringForUserAsync((target :: Player).UserId)
			end)
			;(target :: Player):Kick(if ok then filtered else "Kicked by an admin")
			return true, "Kicked " .. (target :: Player).DisplayName
		end,
	},
	Event = {
		Run = function(_admin, _target, value)
			local id = if type(value) == "string" then value else nil
			local known = false
			for _, def in ipairs(Events.List) do
				known = known or def.Id == id
			end
			services.EventService:Begin(if known then id else nil)
			return true, "Started " .. tostring(workspace:GetAttribute("EventId"))
		end,
	},
	Boss = {
		Target = true,
		Run = function(_admin, target)
			local zone = services.ZoneService:GetZone(target :: Player)
			if services.BossService.Active[zone.Id] then
				return false, "The " .. zone.Name .. " boss is already out"
			end
			services.BossService:SpawnBoss(zone)
			return true, "Spawned the boss in " .. zone.Name
		end,
	},
	Announce = {
		Run = function(admin, _target, value)
			if type(value) ~= "string" or #value == 0 then
				return false, "Type a message first"
			end
			local ok, filtered = pcall(function()
				return TextService:FilterStringAsync(string.sub(value, 1, 150), admin.UserId):GetNonChatStringForBroadcastAsync()
			end)
			if not ok then
				return false, "The message couldn't be filtered; try again"
			end
			Net.Event("Notify"):FireAllClients({ Text = "📢 " .. admin.DisplayName .. ": " .. filtered, Color = Color3.fromRGB(255, 214, 90), Big = true })
			return true, "Announced"
		end,
	},
	MakeAdmin = {
		Owner = true,
		Target = true,
		Run = function(_admin, target)
			local t = target :: Player
			if AdminService:Rank(t) then
				return false, t.DisplayName .. " is already " .. tostring(AdminService:Rank(t))
			end
			saveAppointed(function(list)
				list[tostring(t.UserId)] = t.Name
			end)
			refreshAttribute(t)
			Net.Event("Notify"):FireClient(t, { Text = "👑 You're now an admin! Press F2 or the Admin button.", Color = Color3.fromRGB(255, 214, 90), Big = true })
			return true, t.DisplayName .. " is now an admin"
		end,
	},
	RemoveAdmin = {
		Owner = true,
		Run = function(_admin, _target, value)
			local id = tostring(value)
			local name = appointed[id]
			if not name then
				return false, "That player isn't an appointed admin"
			end
			saveAppointed(function(list)
				list[id] = nil
			end)
			local p = findPlayer(tonumber(id))
			if p then
				refreshAttribute(p)
			end
			return true, "Removed admin " .. name
		end,
	},
	DropHat = {
		Target = true,
		-- the box picks the rarity (Common, Magic, Rare, Legendary, Mythic; empty = a normal roll)
		Run = function(_admin, target, value)
			if not services.LootService then
				return false, "Loot is not running"
			end
			local rarity = nil
			if type(value) == "string" and value ~= "" then
				local Hats = require(ReplicatedStorage.Shared.Config.Hats)
				for _, r in ipairs(Hats.Rarities) do
					if string.sub(string.lower(r.Name), 1, #value) == string.lower(value) then
						rarity = r.Name
						break
					end
				end
				if not rarity then
					return false, "Type a rarity: Common, Magic, Rare, Legendary or Mythic"
				end
			end
			return services.LootService:AdminDrop(target :: Player, rarity)
		end,
	},
	DropCharm = {
		Target = true,
		-- the box: a rarity (Magic..Mythic), a size (Small, Large, Grand), Skill or Torch; empty = a normal roll
		Run = function(_admin, target, value)
			if not services.CharmService then
				return false, "Charms are not running"
			end
			local kind = nil
			if type(value) == "string" and value ~= "" then
				local Charms = require(ReplicatedStorage.Shared.Config.Charms)
				local names = { "Skill", "Torch" }
				for _, r in ipairs(Charms.Rarities) do
					if r.Name ~= "Unique" then
						table.insert(names, r.Name)
					end
				end
				for _, size in ipairs(Charms.Sizes) do
					table.insert(names, size.Id)
				end
				for _, name in ipairs(names) do
					if string.sub(string.lower(name), 1, #value) == string.lower(value) then
						kind = name
						break
					end
				end
				if not kind then
					return false, "Type a rarity, a size (Small, Large, Grand), Skill or Torch"
				end
			end
			return services.CharmService:AdminDrop(target :: Player, kind)
		end,
	},
	ListAdmins = {
		Run = function()
			return true, nil
		end,
	},
}

-- Returns ok, message and, for the panel, the current admin list.
function AdminService:Run(admin: Player, command: any, targetId: any, value: any): (boolean, any)
	local rank = self:Rank(admin)
	if not rank then
		return false, "You're not an admin"
	end
	local def = type(command) == "string" and COMMANDS[command]
	if not def then
		return false, "Unknown command"
	end
	if def.Owner and rank ~= "Owner" then
		return false, "Only owners can do that"
	end
	local target = findPlayer(targetId)
	if def.Target and not target then
		return false, "Pick a player first"
	end
	if type(value) == "string" then
		value = string.sub(value, 1, 200)
	end
	local ok, message = def.Run(admin, target, value)
	if not ok then
		return false, message
	end
	if command ~= "ListAdmins" then
		log(admin, string.format("%s %s %s -> %s", command, if target then target.Name else "-", tostring(value), tostring(message)))
	end
	local list = {}
	for id, name in pairs(appointed) do
		table.insert(list, { UserId = tonumber(id), Name = name })
	end
	return true, { Message = message, Admins = list, Rank = rank }
end

function AdminService:Init(registry)
	services = registry
end

function AdminService:Start()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("NinjaSim_Admins")
	end)
	store = if ok then result else nil
	task.spawn(function()
		loadAppointed()
		for _, player in ipairs(Players:GetPlayers()) do
			refreshAttribute(player)
		end
		-- pick up admins appointed in other servers
		while true do
			task.wait(120)
			loadAppointed()
			for _, player in ipairs(Players:GetPlayers()) do
				refreshAttribute(player)
			end
		end
	end)
	Players.PlayerAdded:Connect(refreshAttribute)
	for _, player in ipairs(Players:GetPlayers()) do
		refreshAttribute(player)
		player.CharacterAdded:Connect(function()
			if god[player] then
				task.wait(0.5)
				setGod(player, true)
			end
		end)
	end
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			if god[player] then
				task.wait(0.5)
				setGod(player, true)
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		god[player] = nil
	end)
end

return AdminService
