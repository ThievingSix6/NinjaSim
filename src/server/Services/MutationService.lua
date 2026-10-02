--[[
	MutationService: the Mutation Machine by the village spawn (Config/Mutations).

	Roll(player, kind, uid, lucky): reroll the mutation of one of your pets ("Pet") or
	hats ("Hat"). A normal roll costs Coins (more for rarer pets and hats, and as you
	level), a lucky roll costs Spirit Shards and makes the rare results three times as
	likely. Every roll gives a mutation, sometimes a worse one; the rarest, Secret, can
	only come from here. You have to stand at the machine. Rare results are announced.
	Returns ok, { Mutation, Name, Previous } or a message.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Mutations = require(Shared.Config.Mutations)
local Pets = require(Shared.Config.Pets)
local Hats = require(Shared.Config.Hats)
local Rarity = require(Shared.Config.Rarity)
local Zones = require(Shared.Config.Zones)
local Net = require(Shared.Net)

local MutationService = {}

local services
local rng = Random.new()
local lastRoll: { [Player]: number } = {}

-- Where the machine stands (world position).
function MutationService.Position(): Vector3
	local m = Mutations.Machine
	return Zones.WorldPosition(Zones.Get(m.Zone), m.Offset)
end

-- The rarity step (1 = Common) that prices a machine roll of this item.
function MutationService.RarityStep(kind: string, item): number
	if kind == "Pet" then
		local def = Pets.ById[item.Id]
		return if def then Rarity.Index(def.Rarity) else 1
	end
	return Hats.Rarity(item.R).Index
end

function MutationService:Roll(player: Player, kind: any, uid: any, lucky: any): (boolean, any)
	local data = services.DataService:Get(player)
	local stats = services.StatService:Get(player)
	if not data or not stats then
		return false, "Still loading"
	end
	if kind ~= "Pet" and kind ~= "Hat" then
		return false, "Pick a pet or a hat"
	end
	local item = if kind == "Pet" then data.Pets[uid] else data.Hats[uid]
	if type(uid) ~= "string" or type(item) ~= "table" then
		return false, "You don't own that"
	end
	if lastRoll[player] and os.clock() - lastRoll[player] < 1.2 then
		return false, "The machine is still spinning..."
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or (root.Position - MutationService.Position()).Magnitude > Mutations.Machine.Range + 10 then
		return false, "Walk up to the Mutation Machine"
	end
	local isLucky = lucky == true
	local currency = if isLucky then "Shards" else "Coins"
	local price = if isLucky then Mutations.Machine.LuckyShards else Mutations.MachinePrice(data.Level, MutationService.RarityStep(kind, item))
	if not services.DataService:Spend(player, currency, price) then
		return false, "Not enough " .. (if isLucky then "Spirit Shards" else "Coins")
	end
	lastRoll[player] = os.clock()
	local previous = if kind == "Pet" then item.Mutation else item.M
	local result = Mutations.MachineRoll(isLucky, stats.Luck, rng)
	if kind == "Pet" then
		item.Mutation = result
		services.DataService:Changed(player, "Pets") -- stats, and the follow pet rebuilds with its new look
	else
		item.M = result
		services.DataService:Changed(player, "Hats")
		if data.EquippedHat == uid then
			services.LootService:ApplyHat(player)
		end
	end
	local m = Mutations.Get(result) :: any
	local name = if kind == "Pet" then (Pets.ById[item.Id] and Pets.ById[item.Id].Name or "pet") else Hats.BaseName(item)
	if m.Shout then
		for _, other in ipairs(Players:GetPlayers()) do
			Net.Event("Notify"):FireClient(other, {
				Text = player.DisplayName .. " rolled a " .. m.Name .. " " .. name .. " at the Mutation Machine!",
				Color = m.Color, Big = m.Id == "Secret" or other == player,
			})
		end
	end
	return true, { Mutation = result, Name = m.Name, Previous = previous, Kind = kind, Uid = uid }
end

function MutationService:Init(registry)
	services = registry
end

function MutationService:Start()
	Players.PlayerRemoving:Connect(function(player)
		lastRoll[player] = nil
	end)
end

return MutationService
