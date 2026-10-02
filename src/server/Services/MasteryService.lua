--[[
	MasteryService: suit choice and suit mastery (Config/Mastery).

	  SetSuit(player, tierId)  wear any suit up to your best rank ("" = your rank's)
	  OnKill(player, enemy)    the worn suit gains mastery (ProgressionService:GrantKill)
	  Grant(player, points)    add mastery points to the worn suit (admin, tests)

	Reaching an ultimate's mastery level announces it; the ultimates themselves are
	cast through SkillService:CastUltimate.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Mastery = require(Shared.Config.Mastery)
local Tiers = require(Shared.Config.Tiers)
local Net = require(Shared.Net)

local MasteryService = {}

local services

local function entry(data, tierId: string)
	if type(data.Mastery) ~= "table" then
		data.Mastery = {}
	end
	local e = data.Mastery[tierId]
	if type(e) ~= "table" then
		e = { L = 1, P = 0 }
		data.Mastery[tierId] = e
	end
	e.L = math.clamp(tonumber(e.L) or 1, 1, Mastery.Max)
	e.P = math.max(0, tonumber(e.P) or 0)
	return e
end

function MasteryService:SetSuit(player: Player, tierId: string): (boolean, string?)
	local data = services.DataService:Get(player)
	if not data then
		return false, "Still loading"
	end
	if tierId == "" then
		data.Suit = ""
	else
		local tier = Tiers.ById[tierId]
		if not tier then
			return false, "Unknown suit"
		end
		if tier.Index > math.max(data.BestTier, data.Tier) then
			return false, "Reach " .. tier.Name .. " first (Lv " .. tier.Level .. ")"
		end
		data.Suit = tierId
	end
	services.DataService:Changed(player, "Suit")
	return true, "Now wearing the " .. Mastery.WornTier(data).Name .. " suit"
end

-- Adds mastery points to the worn suit. Returns the levels gained.
function MasteryService:Grant(player: Player, points: number): number
	local data = services.DataService:Get(player)
	if not data or points <= 0 then
		return 0
	end
	local suit = Mastery.WornTier(data)
	local e = entry(data, suit.Id)
	if e.L >= Mastery.Max then
		return 0
	end
	local before = e.L
	e.P += math.floor(points)
	while e.L < Mastery.Max and e.P >= Mastery.ToNext(e.L) do
		e.P -= Mastery.ToNext(e.L)
		e.L += 1
	end
	if e.L >= Mastery.Max then
		e.P = 0
	end
	services.DataService:Changed(player, "Mastery")
	if e.L > before then
		Net.Event("Notify"):FireClient(player, { Text = suit.Name .. " Mastery " .. e.L, Color = suit.Color, Icon = "Star" })
		for _, def in ipairs(Mastery.ForSuit(suit.Id)) do
			if before < def.Level and e.L >= def.Level then
				Net.Event("Notify"):FireClient(player, {
					Text = "Ultimate unlocked: " .. def.Name .. " [" .. Mastery.Keys[def.Slot] .. "]", Color = def.Color, Big = true,
				})
			end
		end
	end
	return e.L - before
end

function MasteryService:OnKill(player: Player, enemy)
	local data = services.DataService:Get(player)
	if not data then
		return
	end
	self:Grant(player, Mastery.PointsForKill(enemy.Level or 1, data.Level, enemy.IsBoss == true))
end

-- Admin: set the worn suit's mastery level outright.
function MasteryService:SetLevel(player: Player, level: number): boolean
	local data = services.DataService:Get(player)
	if not data then
		return false
	end
	local e = entry(data, Mastery.WornTier(data).Id)
	e.L = math.clamp(math.floor(level), 1, Mastery.Max)
	e.P = 0
	services.DataService:Changed(player, "Mastery")
	return true
end

function MasteryService:Init(registry)
	services = registry
end

function MasteryService:Start() end

return MasteryService
