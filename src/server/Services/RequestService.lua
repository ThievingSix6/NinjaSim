--[[
	RequestService: the single entry point for client actions (RemoteFunction
	"Request"). Every action is rate-limited, type-checked and routed to the
	service that validates it. Returns { Ok = bool, Message = string? }.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local RequestService = {}

local services
local buckets: { [Player]: { Tokens: number, Last: number } } = {}
local MAX_TOKENS = 12
local REFILL_PER_SECOND = 6

local function allow(player: Player): boolean
	local b = buckets[player]
	local now = os.clock()
	if not b then
		b = { Tokens = MAX_TOKENS, Last = now }
		buckets[player] = b
	end
	b.Tokens = math.min(MAX_TOKENS, b.Tokens + (now - b.Last) * REFILL_PER_SECOND)
	b.Last = now
	if b.Tokens < 1 then
		return false
	end
	b.Tokens -= 1
	return true
end

local function str(v: any): string?
	return if type(v) == "string" and #v <= 64 then v else nil
end

local handlers = {}

function handlers.UnlockZone(player, zoneId)
	return services.ZoneService:Unlock(player, str(zoneId) or "")
end
function handlers.Teleport(player, zoneId)
	return services.ZoneService:Teleport(player, str(zoneId) or "")
end
function handlers.Rebirth(player)
	return services.RebirthService:Rebirth(player)
end
function handlers.BuyUpgrade(player, id)
	return services.RebirthService:BuyUpgrade(player, str(id) or "")
end
function handlers.BuyKatana(player, id)
	return services.ShopService:BuyKatana(player, str(id) or "")
end
function handlers.BuyBoost(player, id)
	return services.ShopService:BuyBoost(player, str(id) or "")
end
function handlers.BuyCosmetic(player, id)
	return services.ShopService:BuyCosmetic(player, str(id) or "")
end
function handlers.BuyUtility(player, id)
	return services.ShopService:BuyUtility(player, str(id) or "")
end
function handlers.Hatch(player, eggId, count)
	return services.PetService:Hatch(player, str(eggId) or "", if count == 3 then 3 else 1)
end
function handlers.EquipPet(player, uid)
	return services.PetService:Equip(player, str(uid) or "")
end
function handlers.UnequipPet(player, uid)
	return services.PetService:Unequip(player, str(uid) or "")
end
function handlers.EquipBestPets(player)
	return services.PetService:EquipBest(player)
end
function handlers.DeletePets(player, uids)
	return services.PetService:Delete(player, uids)
end
function handlers.FavoritePet(player, uid)
	return services.PetService:ToggleFavorite(player, str(uid) or "")
end
function handlers.EquipKatana(player, id)
	return services.InventoryService:EquipKatana(player, str(id) or "")
end
function handlers.EquipCosmetic(player, kind, id)
	return services.InventoryService:EquipCosmetic(player, str(kind) or "", str(id) or "")
end
function handlers.FavoriteItem(player, key)
	return services.InventoryService:ToggleFavorite(player, str(key) or "")
end
function handlers.SetSetting(player, key, value)
	return services.InventoryService:SetSetting(player, str(key) or "", value)
end
function handlers.RedeemCode(player, code)
	return services.InventoryService:RedeemCode(player, str(code) or "")
end
function handlers.RebirthPreview(player)
	return true, services.RebirthService:Preview(player)
end
function handlers.ClaimGift(player, index)
	return services.GiftService:Claim(player, index)
end
function handlers.ClaimAchievement(player, id)
	return services.AchievementService:Claim(player, str(id))
end
function handlers.SetAutoDelete(player, petId, on)
	return services.PetService:SetAutoDelete(player, str(petId) or "", on == true)
end
function handlers.ClaimAllAchievements(player)
	return services.AchievementService:ClaimAll(player)
end
local function slotOf(v: any): number?
	return if type(v) == "number" and v == math.floor(v) and v >= 1 and v <= 4 then v else nil
end
function handlers.BuySkill(player, id)
	return services.SkillService:Buy(player, str(id) or "")
end
function handlers.UpgradeSkill(player, id)
	return services.SkillService:Upgrade(player, str(id) or "")
end
function handlers.EquipSkill(player, id, slot)
	return services.SkillService:Equip(player, str(id) or "", slotOf(slot))
end
function handlers.UnequipSkill(player, slot)
	local s = slotOf(slot)
	if not s then
		return false, "Pick a slot"
	end
	return services.SkillService:Unequip(player, s)
end
function handlers.CastSkill(player, slot, aim)
	local s = slotOf(slot)
	if not s then
		return false, nil
	end
	return services.SkillService:Cast(player, s, aim)
end
-- hats (LootService)
function handlers.PickupHat(player, dropId)
	return services.LootService:Pickup(player, dropId)
end
function handlers.EquipHat(player, uid)
	return services.LootService:Equip(player, str(uid))
end
function handlers.UnequipHat(player)
	return services.LootService:Unequip(player)
end
function handlers.LockHat(player, uid)
	return services.LootService:ToggleLock(player, str(uid))
end
function handlers.SalvageHats(player, uids)
	return services.LootService:Salvage(player, uids)
end
function handlers.SalvageHatsUpTo(player, rarity)
	return services.LootService:SalvageUpTo(player, str(rarity))
end
-- charms (CharmService)
function handlers.PlaceCharm(player, uid, x, y)
	return services.CharmService:Place(player, str(uid), if type(x) == "number" then x else nil, if type(y) == "number" then y else nil)
end
function handlers.StashCharm(player, uid)
	return services.CharmService:Stash(player, str(uid))
end
function handlers.LockCharm(player, uid)
	return services.CharmService:ToggleLock(player, str(uid))
end
function handlers.SalvageCharm(player, uid)
	return services.CharmService:Salvage(player, str(uid))
end
-- duels (DuelService)
function handlers.DuelRequest(player, userId, wager)
	return services.DuelService:Request(player, if type(userId) == "number" then userId else nil, wager == true)
end
function handlers.DuelRespond(player, userId, accept)
	return services.DuelService:Respond(player, if type(userId) == "number" then userId else nil, accept == true)
end
function handlers.DuelForfeit(player)
	return services.DuelService:Forfeit(player)
end
-- the Cursed Temple (TempleService)
function handlers.TempleStart(player, floor)
	return services.TempleService:StartRun(player, if type(floor) == "number" then floor else 1)
end
function handlers.TempleLeave(player)
	return services.TempleService:Leave(player)
end
-- trading (TradeService)
function handlers.TradeRequest(player, userId)
	return services.TradeService:Request(player, if type(userId) == "number" then userId else nil)
end
function handlers.TradeRespond(player, userId, accept)
	return services.TradeService:Respond(player, if type(userId) == "number" then userId else nil, accept == true)
end
function handlers.TradeOffer(player, kind, uid, add)
	return services.TradeService:Offer(player, str(kind), str(uid), add == true)
end
function handlers.TradeReady(player, ready)
	return services.TradeService:SetReady(player, ready == true)
end
function handlers.TradeCancel(player)
	return services.TradeService:Cancel(player)
end
-- the Mutation Machine (MutationService)
function handlers.MutateItem(player, kind, uid, lucky)
	return services.MutationService:Roll(player, str(kind), str(uid), lucky == true)
end
-- suits and mastery (MasteryService, SkillService:CastUltimate)
function handlers.SetSuit(player, tierId)
	return services.MasteryService:SetSuit(player, str(tierId) or "")
end
function handlers.CastUltimate(player, slot, aim)
	local s = slotOf(slot)
	if not s then
		return false, nil
	end
	return services.SkillService:CastUltimate(player, s, aim)
end
function handlers.Admin(player, command, targetId, value)
	return services.AdminService:Run(player, command, targetId, value)
end
-- fallback for a client that missed the initial DataSync event
function handlers.Sync(player)
	local data = services.DataService:Get(player)
	if not data then
		return false, "Still loading"
	end
	return true, data
end
function handlers.BossTimers(_player)
	local Zones = require(ReplicatedStorage.Shared.Config.Zones)
	local out = {}
	for _, zone in ipairs(Zones.List) do
		out[zone.Id] = services.BossService:TimeUntilSpawn(zone.Id)
	end
	return true, out
end

function RequestService:Init(registry)
	services = registry
end

function RequestService:Start()
	Net.Function("Request").OnServerInvoke = function(player: Player, action: any, ...)
		if type(action) ~= "string" or not handlers[action] then
			return { Ok = false, Message = "Unknown action" }
		end
		if not allow(player) then
			return { Ok = false, Message = "Slow down!" }
		end
		local ok, success, result = pcall(handlers[action], player, ...)
		if not ok then
			warn(string.format("[RequestService] %s failed for %s: %s", action, player.Name, tostring(success)))
			return { Ok = false, Message = "Something went wrong" }
		end
		if type(result) == "string" or result == nil then
			return { Ok = success == true, Message = result }
		end
		return { Ok = success == true, Result = result }
	end
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
end

return RequestService
