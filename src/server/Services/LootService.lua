--[[
	LootService: Diablo-style hat drops (Config/Hats) and the hat inventory.

	Drops: when an enemy dies (EnemyService:Kill -> OnKill), each player who earned
	the kill rolls Hats.DropChance (1%; bosses Hats.BossDropChance, training dummies
	never). The hat is rolled here (rarity from Luck, base from the area, rolls from
	the enemy's level) and kept as a pending drop for that player only; the client is
	told where it fell (event HatLoot, Kind "Drop") and draws the light pillar. The
	player collects it by walking near it (request PickupHat, distance checked here)
	or it flies to them after Hats.AutoCollect seconds.

	On hit (CombatService -> OnHit): the equipped hat's procs ("5% chance on hit to
	cast Lightning Blade") roll once per landed swing, with Hats.ProcCooldown between
	two procs of the same skill, and fire through SkillService:CastAt (no slot or cooldown, at Hats.ProcLevel).
	On kill: Life Steal heals LifeSteal% of max HP.

	Requests (RequestService): PickupHat, EquipHat, UnequipHat, LockHat, SalvageHats,
	SalvageHatsUpTo. Admin: DropHat (AdminService).

	Charms (Config/Charms) drop through the same pipeline: Charms.DropChance (0.3%) per
	kill per player who earned it, and on boss kills Charms.TorchChance (0.01%) for the
	Hexfire Torch. Charm drops carry `Charm` instead of `Hat` in the HatLoot payloads
	and are stored by CharmService:Add (a full charm stash salvages them for Shards).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Hats = require(Shared.Config.Hats)
local Charms = require(Shared.Config.Charms)
local Temple = require(Shared.Config.Temple)
local Balance = require(Shared.Config.Balance)
local HatBuilder = require(Shared.Visuals.HatBuilder)
local Net = require(Shared.Net)
local TableUtil = require(Shared.Util.TableUtil)

local LootService = {}

local services
local rng = Random.new()
type Drop = { Id: number, Hat: any, Position: Vector3, Kind: string }
local drops: { [Player]: { [number]: Drop } } = {}
local procReady: { [Player]: { [string]: number } } = {}
local nextDrop = 0

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function event(): RemoteEvent
	return Net.Event("HatLoot")
end

local function notify(player: Player, text: string, color: Color3?)
	Net.Event("Notify"):FireClient(player, { Text = text, Color = color, Icon = "Crown" })
end

-- ===== drops =====
-- Drops an item for `player` at `position`: a hat, or a charm with kind "Charm".
function LootService:Drop(player: Player, position: Vector3, item: any, kind: string?): number
	nextDrop += 1
	local id = nextDrop
	local isCharm = kind == "Charm"
	drops[player] = drops[player] or {}
	drops[player][id] = { Id = id, Hat = item, Position = position, Kind = if isCharm then "Charm" else "Hat" }
	event():FireClient(player, { Kind = "Drop", Id = id, Hat = if isCharm then nil else item, Charm = if isCharm then item else nil, Position = position })
	task.delay(Hats.AutoCollect, function()
		if player.Parent then
			self:Collect(player, id)
		end
	end)
	return id
end

-- Salvage value of a list of hats, paid out. Returns coins, shards.
local function payOut(player: Player, list: { any }): (number, number)
	local coins, shards = 0, 0
	for _, hat in ipairs(list) do
		local c, s = Hats.SalvageValue(hat, Balance)
		coins += c
		shards += s
	end
	services.ProgressionService:AddCoins(player, coins)
	if shards > 0 then
		services.ProgressionService:AddShards(player, shards)
	end
	return coins, shards
end

function LootService:Collect(player: Player, id: number): (boolean, string?)
	local list = drops[player]
	local drop = list and list[id]
	if not drop then
		return false, nil
	end
	local data = services.DataService:Get(player)
	if not data then
		return false, "Still loading"
	end
	list[id] = nil
	if drop.Kind == "Charm" then
		return self:CollectCharm(player, id, drop.Hat)
	end
	local hat = drop.Hat
	if TableUtil.Count(data.Hats) >= Hats.Storage then
		local coins = payOut(player, { hat })
		event():FireClient(player, { Kind = "Looted", Id = id, Hat = hat, Salvaged = true, Coins = coins })
		notify(player, string.format("Hat storage full (%d)! Salvaged %s.", Hats.Storage, Hats.Name(hat)), Color3.fromRGB(255, 150, 120))
		return true, nil
	end
	data.HatSerial = (tonumber(data.HatSerial) or 0) + 1
	local uid = tostring(data.HatSerial)
	data.Hats[uid] = hat
	services.DataService:Changed(player, "Hats")
	services.DataService:Changed(player, "HatSerial")
	event():FireClient(player, { Kind = "Looted", Id = id, Uid = uid, Hat = hat })
	local rarity = Hats.Rarity(hat.R)
	if rarity.Index >= 4 then
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player then
				Net.Event("Notify"):FireClient(other, { Text = player.DisplayName .. " found " .. Hats.Name(hat), Color = rarity.Color, Side = true })
			end
		end
	end
	return true, nil
end

function LootService:CollectCharm(player: Player, id: number, charm): (boolean, string?)
	local uid = services.CharmService and services.CharmService:Add(player, charm)
	if not uid then
		local shards = Charms.SalvageValue(charm)
		services.ProgressionService:AddShards(player, shards)
		event():FireClient(player, { Kind = "Looted", Id = id, Charm = charm, Salvaged = true })
		notify(player, string.format("Charm storage full (%d)! Salvaged %s for %d Shards.", Charms.Storage, Charms.Name(charm), shards), Color3.fromRGB(255, 150, 120))
		return true, nil
	end
	event():FireClient(player, { Kind = "Looted", Id = id, Uid = uid, Charm = charm })
	local rarity = Charms.Rarity(charm.R)
	if rarity.Index >= 3 or charm.S then
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player then
				Net.Event("Notify"):FireClient(other, { Text = player.DisplayName .. " found " .. Charms.Name(charm), Color = rarity.Color, Side = true })
			end
		end
	end
	return true, nil
end

function LootService:Pickup(player: Player, id: any): (boolean, string?)
	if type(id) ~= "number" then
		return false, nil
	end
	local drop = drops[player] and drops[player][id]
	local root = rootOf(player)
	if not drop or not root then
		return false, nil
	end
	local flat = Vector3.new(root.Position.X - drop.Position.X, 0, root.Position.Z - drop.Position.Z)
	if flat.Magnitude > Hats.PickupRadius + 6 then
		return false, "Get closer to pick it up"
	end
	return self:Collect(player, id)
end

local function groundPoint(position: Vector3): Vector3
	local offset = Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2))
	local p = position + offset
	return Vector3.new(p.X, services.ZoneService:GroundHeight(p), p.Z)
end

-- Called by EnemyService:Kill with everyone who earned the kill.
function LootService:OnKill(enemy, rewarded: { [Player]: any }, killer: Player?)
	if killer then
		self:LifeSteal(killer)
	end
	if enemy.Def.Static then
		return -- training dummies never drop loot
	end
	local chance = if enemy.IsBoss then Hats.BossDropChance else Hats.DropChance
	local zoneIndex = (enemy.Zone and enemy.Zone.Index) or 1
	for player in pairs(rewarded) do
		if player.Parent and rng:NextNumber() < chance then
			local stats = services.StatService:Get(player)
			local hat = Hats.Roll(zoneIndex, enemy.Level or 1, if stats then stats.Luck else 0, enemy.IsBoss, rng)
			self:Drop(player, groundPoint(enemy.Root.Position), hat)
		end
		-- charms: very rare from anything, and the Hexfire Torch rarer still from bosses
		if player.Parent and rng:NextNumber() < Charms.DropChance * (if enemy.Temple then Temple.CharmBoost else 1) then
			local stats = services.StatService:Get(player)
			self:Drop(player, groundPoint(enemy.Root.Position), Charms.Roll(enemy.Level or 1, if stats then stats.Luck else 0, rng), "Charm")
		end
		if player.Parent and enemy.IsBoss and rng:NextNumber() < Charms.TorchChance then
			self:Drop(player, groundPoint(enemy.Root.Position), Charms.RollUnique("hexfire", enemy.Level or 1, rng), "Charm")
		end
	end
end

function LootService:LifeSteal(player: Player)
	local stats = services.StatService:Get(player)
	local steal = stats and stats.LifeSteal or 0
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if steal <= 0 or not humanoid or humanoid.Health <= 0 or humanoid.Health >= humanoid.MaxHealth then
		return
	end
	local before = humanoid.Health
	humanoid.Health = math.min(humanoid.MaxHealth, before + humanoid.MaxHealth * steal / 100)
	local healed = math.floor(humanoid.Health - before + 0.5)
	if healed > 0 then
		event():FireClient(player, { Kind = "Heal", Amount = healed })
	end
end

-- Called by CombatService after a swing lands (hits = the enemies it struck).
function LootService:OnHit(player: Player, hits: { any })
	local stats = services.StatService:Get(player)
	local procs = stats and stats.HatProcs
	if not procs or #procs == 0 or #hits == 0 or not services.SkillService then
		return
	end
	local ready = procReady[player]
	if not ready then
		ready = {}
		procReady[player] = ready
	end
	local now = os.clock()
	for _, proc in ipairs(procs) do
		if now >= (ready[proc.Skill] or 0) and rng:NextNumber() < proc.Chance then
			ready[proc.Skill] = now + Hats.ProcCooldown
			local target = hits[1]
			local position = target.Root.Position
			Net.FireNear(event(), position, 150, { Kind = "Proc", Skill = proc.Skill, Position = position, Caster = player.UserId })
			task.spawn(function()
				local ok, err = pcall(services.SkillService.CastAt, services.SkillService, player, proc.Skill, position, Hats.ProcLevel)
				if not ok then
					warn("[LootService] proc failed: " .. tostring(err))
				end
			end)
		end
	end
end

-- ===== inventory =====
local function ownedHat(player: Player, uid: any)
	local data = services.DataService:Get(player)
	if not data or type(uid) ~= "string" then
		return data, nil
	end
	local hat = data.Hats[uid]
	return data, if Hats.Valid(hat) then hat else nil
end

function LootService:Equip(player: Player, uid: any): (boolean, string?)
	local data, hat = ownedHat(player, uid)
	if not data or not hat then
		return false, "You don't have that hat"
	end
	data.EquippedHat = uid
	services.DataService:Changed(player, "EquippedHat")
	return true, nil
end

function LootService:Unequip(player: Player): (boolean, string?)
	local data = services.DataService:Get(player)
	if not data then
		return false, "Still loading"
	end
	data.EquippedHat = ""
	services.DataService:Changed(player, "EquippedHat")
	return true, nil
end

function LootService:ToggleLock(player: Player, uid: any): (boolean, string?)
	local data, hat = ownedHat(player, uid)
	if not data or not hat then
		return false, "You don't have that hat"
	end
	hat.Lock = if hat.Lock then nil else true
	services.DataService:Changed(player, "Hats")
	return true, nil
end

-- Salvages the given hats (skipping locked and equipped ones). Returns ok, message.
function LootService:Salvage(player: Player, uids: any): (boolean, string?)
	local data = services.DataService:Get(player)
	if not data or type(uids) ~= "table" then
		return false, "Pick some hats first"
	end
	local list, seen = {}, {}
	for i, uid in ipairs(uids) do
		if i > Hats.Storage + 20 then
			break
		end
		local hat = type(uid) == "string" and data.Hats[uid]
		if hat and not seen[uid] and not hat.Lock and data.EquippedHat ~= uid then
			seen[uid] = true
			table.insert(list, hat)
			data.Hats[uid] = nil
		end
	end
	if #list == 0 then
		return false, "Nothing to salvage (locked and equipped hats are kept)"
	end
	services.DataService:Changed(player, "Hats")
	local coins, shards = payOut(player, list)
	local text = string.format("Salvaged %d hat%s for %s Coins", #list, if #list == 1 then "" else "s", tostring(coins))
	if shards > 0 then
		text ..= string.format(" and %d Shards", shards)
	end
	return true, text
end

-- Salvages every unlocked, unequipped hat of this rarity or lower (Common to Rare only).
function LootService:SalvageUpTo(player: Player, rarityName: any): (boolean, string?)
	local data = services.DataService:Get(player)
	local rarity = type(rarityName) == "string" and Hats.RarityByName[rarityName]
	if not data or not rarity or rarity.Index > 3 then
		return false, "Pick Common, Magic or Rare"
	end
	local uids = {}
	for uid, hat in pairs(data.Hats) do
		if Hats.Valid(hat) and not hat.Lock and data.EquippedHat ~= uid and Hats.Rarity(hat.R).Index <= rarity.Index then
			table.insert(uids, uid)
		end
	end
	return self:Salvage(player, uids)
end

-- Admin / test: drop a hat of a rarity (any if nil) at the player's feet.
function LootService:AdminDrop(player: Player, rarityName: string?, baseId: string?): (boolean, string?)
	local data = services.DataService:Get(player)
	local root = rootOf(player)
	if not data or not root then
		return false, "They have no character"
	end
	local zone = services.ZoneService:GetZone(player)
	local bossLevel = zone.Boss and zone.Boss.Level or zone.Level
	local level = math.clamp(data.Level, zone.Level, math.max(zone.Level, bossLevel))
	local stats = services.StatService:Get(player)
	local hat = Hats.Roll(zone.Index or 1, level, if stats then stats.Luck else 0, false, rng, rarityName, baseId)
	local at = root.Position + root.CFrame.LookVector * 6
	self:Drop(player, Vector3.new(at.X, services.ZoneService:GroundHeight(at), at.Z), hat)
	return true, string.format("Dropped %s (%s, iLvl %d) for %s", Hats.Name(hat), hat.R, hat.L, player.DisplayName)
end

-- ===== wearing =====
function LootService:ApplyHat(player: Player)
	local data = services.DataService:Get(player)
	local character = player.Character
	if not data or not character then
		return
	end
	local ok, err = pcall(HatBuilder.Wear, character, Hats.Equipped(data))
	if not ok then
		warn("[LootService] couldn't put the hat on: " .. tostring(err))
	end
end

-- Old or hand-edited saves: drop malformed hats and a dangling EquippedHat.
local function sanitize(data): boolean
	local changed = false
	if type(data.Hats) ~= "table" then
		data.Hats = {}
		changed = true
	end
	for uid, hat in pairs(data.Hats) do
		if not Hats.Valid(hat) then
			data.Hats[uid] = nil
			changed = true
		end
	end
	if type(data.EquippedHat) ~= "string" or (data.EquippedHat ~= "" and not data.Hats[data.EquippedHat]) then
		data.EquippedHat = ""
		changed = true
	end
	return changed
end

function LootService:Init(registry)
	services = registry
end

function LootService:Start()
	event() -- make sure the remote exists
	services.DataService:OnLoaded(function(player, data)
		if sanitize(data) then
			services.DataService:Changed(player, "Hats")
			services.DataService:Changed(player, "EquippedHat")
		end
	end)
	services.DataService:AddFlushHook(function(player, keys)
		if keys.EquippedHat then
			task.defer(self.ApplyHat, self, player)
		end
	end)
	-- the outfit is (re)built on spawn and on tier-up; the hat goes on top of it
	local function watch(player: Player, character: Model)
		character.ChildAdded:Connect(function(child)
			if child.Name == "NinjaOutfit" then
				task.defer(self.ApplyHat, self, player)
			end
		end)
		if character:FindFirstChild("NinjaOutfit") then
			task.defer(self.ApplyHat, self, player)
		end
	end
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			watch(player, character)
		end)
		if player.Character then
			watch(player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in ipairs(Players:GetPlayers()) do
		hook(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		drops[player] = nil
		procReady[player] = nil
	end)
end

return LootService
