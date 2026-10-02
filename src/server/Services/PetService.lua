--[[
	PetService: egg hatching (server-side rolls with luck), equipping, deleting,
	favouriting and "equip best". Pet data is keyed by a per-player serial uid so
	it scales to hundreds of pets and stays DataStore-friendly.

	Every hatch also rolls a mutation (Config/Mutations), saved as
	Pets[uid].Mutation. Mutated pets skip auto-delete, and rare ones are
	announced to the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Pets = require(Shared.Config.Pets)
local Net = require(Shared.Net)
local Format = require(Shared.Util.Format)
local Rarity = require(Shared.Config.Rarity)
local TableUtil = require(Shared.Util.TableUtil)
local Mutations = require(Shared.Config.Mutations)

local PetService = {}

local services
local rng = Random.new()
local HATCH_RANGE = 28
local lastHatch: { [Player]: number } = {}
local forcedMutation: { [Player]: string? } = {} -- admin / playtest: the next hatched pet gets this mutation

local function equippedIndex(data, uid: string): number?
	return table.find(data.EquippedPets, uid)
end

function PetService:Hatch(player: Player, eggId: string, count: number?): (boolean, string?)
	local data = services.DataService:Get(player)
	local stats = services.StatService:Get(player)
	local egg = Pets.EggsById[eggId]
	if not data or not stats or not egg then
		return false, "Unknown egg"
	end
	local amount = if count == 3 then 3 else 1
	if amount == 3 and (data.Utility.triple_hatch or 0) < 1 then
		return false, "Buy Triple Hatch in the shop first"
	end
	if lastHatch[player] and os.clock() - lastHatch[player] < 1.2 then
		return false, "Hatching..."
	end
	if egg.RequiredRebirths and data.Rebirths < egg.RequiredRebirths then
		return false, "Unlocks at Rebirth " .. egg.RequiredRebirths
	end
	if not data.Zones[egg.Zone] then
		return false, "Unlock this area first"
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or (root.Position - Pets.EggPosition(egg)).Magnitude > HATCH_RANGE + 10 then
		return false, "Walk up to the egg to hatch it"
	end
	if TableUtil.Count(data.Pets) + amount > stats.PetStorage then
		return false, "Pet storage full - delete some pets"
	end
	if not services.DataService:Spend(player, egg.Currency, egg.Cost * amount) then
		return false, "Not enough " .. (if egg.Currency == "Shards" then "Spirit Shards" else "Coins")
	end
	lastHatch[player] = os.clock()

	local results = {}
	for _ = 1, amount do
		local pet = Pets.Roll(egg, stats.Luck, rng)
		local mutation = Mutations.Roll(stats.Luck, rng, forcedMutation[player])
		forcedMutation[player] = nil
		-- a mutated pet is always kept, even when its species is set to auto-delete
		if data.AutoDelete[pet.Id] and not mutation then
			table.insert(results, { Id = pet.Id, Deleted = true })
		else
			data.PetSerial += 1
			local uid = tostring(data.PetSerial)
			data.Pets[uid] = { Id = pet.Id, Fav = false, Mutation = mutation }
			table.insert(results, { Uid = uid, Id = pet.Id, Mutation = mutation })
			if #data.EquippedPets < stats.PetSlots then
				table.insert(data.EquippedPets, uid)
			end
		end
	end
	-- server shoutout for Legendary and better, and for the rarest mutations
	for _, r in ipairs(results) do
		local def = Pets.ById[r.Id]
		local mutation = Mutations.Get(r.Mutation)
		local rarePet = def and Rarity.Index(def.Rarity) >= Rarity.Index("Legendary")
		local rareMutation = mutation and mutation.Shout
		if def and (rarePet or rareMutation) then
			local oneIn = Pets.MutatedOneIn(def.Id, r.Mutation)
			local odds = if oneIn then " (1 in " .. Format.Commas(oneIn) .. ")" else ""
			local name = Pets.DisplayName(def, r.Mutation)
			local text = if rarePet
				then "✨ " .. player.DisplayName .. " hatched a " .. def.Rarity .. " " .. name .. odds .. "!"
				else "🌈 " .. player.DisplayName .. " hatched a " .. string.upper(mutation.Name) .. " " .. def.Name .. odds .. "!"
			local color = if rareMutation then mutation.Color else Rarity.Color(def.Rarity)
			if rareMutation and mutation.OneIn >= 2000 then
				-- Giant and Celestial get the big banner on every screen
				Net.Event("Notify"):FireAllClients({ Text = text, Color = color, Big = true })
			elseif services.EventService then
				services.EventService:Shoutout(text, color)
			end
		end
	end
	data.Lifetime.EggsOpened += amount
	services.DataService:Changed(player, "Pets")
	services.DataService:Changed(player, "EquippedPets")
	services.DataService:Changed(player, "PetSerial")
	services.DataService:Changed(player, "Lifetime")
	Net.Event("EggHatched"):FireClient(player, { Egg = egg.Id, Pets = results })
	return true
end

-- Toggle auto-delete for a pet species (only up to Epic, so a misclick can't eat a Legendary).
function PetService:SetAutoDelete(player: Player, petId: string, on: boolean): (boolean, string?)
	local data = services.DataService:Get(player)
	local def = Pets.ById[petId]
	if not data or not def or type(on) ~= "boolean" then
		return false, "Unknown pet"
	end
	if on and Rarity.Index(def.Rarity) > Rarity.Index("Epic") then
		return false, def.Rarity .. " pets can't be auto-deleted"
	end
	data.AutoDelete[petId] = if on then true else nil
	services.DataService:Changed(player, "AutoDelete")
	return true, if on then def.Name .. " will be auto-deleted" else def.Name .. " will be kept"
end

function PetService:Equip(player: Player, uid: string): (boolean, string?)
	local data = services.DataService:Get(player)
	local stats = services.StatService:Get(player)
	if not data or not stats or type(uid) ~= "string" or not data.Pets[uid] then
		return false, "Unknown pet"
	end
	if equippedIndex(data, uid) then
		return true
	end
	if #data.EquippedPets >= stats.PetSlots then
		return false, "All pet slots are full"
	end
	table.insert(data.EquippedPets, uid)
	services.DataService:Changed(player, "EquippedPets")
	return true
end

function PetService:Unequip(player: Player, uid: string): (boolean, string?)
	local data = services.DataService:Get(player)
	if not data or type(uid) ~= "string" then
		return false, "Unknown pet"
	end
	local index = equippedIndex(data, uid)
	if index then
		table.remove(data.EquippedPets, index)
		services.DataService:Changed(player, "EquippedPets")
	end
	return true
end

function PetService:EquipBest(player: Player): (boolean, string?)
	local data = services.DataService:Get(player)
	local stats = services.StatService:Get(player)
	if not data or not stats then
		return false, "Data not loaded"
	end
	local list = {}
	for uid, owned in pairs(data.Pets) do
		local def = Pets.ById[owned.Id]
		if def then
			table.insert(list, { Uid = uid, Score = Pets.Score(def, owned.Mutation) })
		end
	end
	table.sort(list, function(a, b)
		return a.Score > b.Score
	end)
	local equipped = {}
	for i = 1, math.min(stats.PetSlots, #list) do
		table.insert(equipped, list[i].Uid)
	end
	data.EquippedPets = equipped
	services.DataService:Changed(player, "EquippedPets")
	return true
end

function PetService:Delete(player: Player, uids: any): (boolean, string?)
	local data = services.DataService:Get(player)
	if not data or type(uids) ~= "table" then
		return false, "Nothing selected"
	end
	local removed = 0
	for _, uid in ipairs(uids) do
		if type(uid) == "string" then
			local owned = data.Pets[uid]
			if owned and not owned.Fav then
				data.Pets[uid] = nil
				local index = equippedIndex(data, uid)
				if index then
					table.remove(data.EquippedPets, index)
				end
				removed += 1
			end
		end
		if removed >= 200 then
			break
		end
	end
	if removed == 0 then
		return false, "Favourited pets can't be deleted"
	end
	services.DataService:Changed(player, "Pets")
	services.DataService:Changed(player, "EquippedPets")
	return true
end

function PetService:ToggleFavorite(player: Player, uid: string): (boolean, string?)
	local data = services.DataService:Get(player)
	if not data or type(uid) ~= "string" or not data.Pets[uid] then
		return false, "Unknown pet"
	end
	data.Pets[uid].Fav = not data.Pets[uid].Fav
	services.DataService:Changed(player, "Pets")
	return true
end

-- Grant a pet directly (codes, events, the admin panel), optionally mutated.
function PetService:Grant(player: Player, petId: string, mutation: string?): string?
	local data = services.DataService:Get(player)
	if not data or not Pets.ById[petId] then
		return nil
	end
	data.PetSerial += 1
	local uid = tostring(data.PetSerial)
	data.Pets[uid] = { Id = petId, Fav = false, Mutation = if Mutations.Get(mutation) then mutation else nil }
	local stats = services.StatService:Get(player)
	if stats and #data.EquippedPets < stats.PetSlots then
		table.insert(data.EquippedPets, uid)
	end
	services.DataService:Changed(player, "Pets")
	services.DataService:Changed(player, "EquippedPets")
	services.DataService:Changed(player, "PetSerial")
	return uid
end

-- The next pet this player hatches gets `mutation` (admin panel and playtest). nil clears it.
function PetService:ForceNextMutation(player: Player, mutation: string?): boolean
	if mutation ~= nil and not Mutations.Get(mutation) then
		return false
	end
	forcedMutation[player] = mutation
	return true
end

function PetService:Init(registry)
	services = registry
end

function PetService:Start()
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastHatch[player] = nil
		forcedMutation[player] = nil
	end)
	-- Keep player attribute in sync so every client can render everyone's pets:
	-- "fox,panda_cub:Golden" (a mutation rides after a colon).
	services.DataService:AddFlushHook(function(player, keys)
		if keys.EquippedPets or keys.Pets then
			local data = services.DataService:Get(player)
			if data then
				local ids = {}
				for _, uid in ipairs(data.EquippedPets) do
					local owned = data.Pets[uid]
					if owned then
						table.insert(ids, if owned.Mutation then owned.Id .. ":" .. owned.Mutation else owned.Id)
					end
				end
				player:SetAttribute("EquippedPets", table.concat(ids, ","))
			end
		end
	end)
	services.DataService:OnLoaded(function(player)
		services.DataService:Changed(player, "EquippedPets")
	end)
end

return PetService
