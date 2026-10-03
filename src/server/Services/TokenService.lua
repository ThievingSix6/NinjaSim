--[[
	TokenService: combat tokens (Config/Tokens), after Bee Swarm Simulator's.

	Every swing that hits rolls the weapon's chance and every kill rolls each equipped
	pet's; a hit drops a token near the fight, owned by that player (only they see and
	collect it). The server keeps the tokens and picks one up when its owner comes
	within CollectRadius, then applies it: a buff stack (StatService modifier "token_<Kind>",
	every pickup restarting the timer for the whole stack) or an instant payout. Tokens
	left too long fade.

	Events: "Token" { Type = "Spawn" | "Collect" | "Expire" | "Buffs", ... }.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tokens = require(Shared.Config.Tokens)
local Pets = require(Shared.Config.Pets)
local Rarity = require(Shared.Config.Rarity)
local Balance = require(Shared.Config.Balance)
local Net = require(Shared.Net)
local Format = require(Shared.Util.Format)

local TokenService = {}

local services
local rng = Random.new()
type Token = { Id: number, Kind: string, Position: Vector3, Expires: number, Level: number, Source: string? }
local active: { [Player]: { Token } } = {}
local buffs: { [Player]: { [string]: { Stacks: number, Ends: number } } } = {}
local nextId = 0

local function event(player: Player, payload)
	Net.Event("Token"):FireClient(player, payload)
end

local function sendBuffs(player: Player)
	local list = {}
	local now = os.clock()
	for kind, b in pairs(buffs[player] or {}) do
		if b.Ends > now then
			table.insert(list, { Kind = kind, Stacks = b.Stacks, Left = b.Ends - now, Duration = Tokens.Kinds[kind].Duration })
		end
	end
	event(player, { Type = "Buffs", List = list })
end

-- Drops a token of `kind` for `player` near `near` (a fight), paying out at `level`.
function TokenService:Spawn(player: Player, kind: string, near: Vector3, level: number, source: string?)
	if not Tokens.Kinds[kind] then
		return nil
	end
	local list = active[player]
	if not list then
		list = {}
		active[player] = list
	end
	if #list >= Tokens.MaxActive then
		local oldest = table.remove(list, 1)
		event(player, { Type = "Expire", Id = oldest.Id })
	end
	local angle = rng:NextNumber(0, math.pi * 2)
	local dist = rng:NextNumber(Tokens.Spread[1], Tokens.Spread[2])
	local spot = near + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
	local ground = services.ZoneService:GroundHeight(Vector3.new(spot.X, near.Y, spot.Z))
	-- a token never lands up a cliff or down a pit from the fight
	if math.abs(ground - near.Y) > 12 then
		ground = near.Y
		spot = near
	end
	nextId += 1
	local life = rng:NextNumber(Tokens.Life[1], Tokens.Life[2])
	local token: Token = { Id = nextId, Kind = kind, Position = Vector3.new(spot.X, ground + 2.2, spot.Z), Expires = os.clock() + life, Level = level, Source = source }
	table.insert(list, token)
	event(player, { Type = "Spawn", Id = token.Id, Kind = kind, Position = token.Position, Life = life, Source = source })
	return token
end

local function addStacks(player: Player, kind: string, stacks: number)
	local def = Tokens.Kinds[kind]
	local mine = buffs[player] or {}
	buffs[player] = mine
	local now = os.clock()
	local b = mine[kind]
	if not b or b.Ends <= now then
		b = { Stacks = 0, Ends = now }
		mine[kind] = b
	end
	b.Stacks = math.min(def.MaxStacks, b.Stacks + stacks)
	b.Ends = now + def.Duration
	local value = Tokens.BuffValue(kind, b.Stacks)
	local mods = if def.Buff == "CritChance" then { CritChance = value } else { [def.Buff] = 1 + value }
	services.StatService:SetModifier(player, "token_" .. kind, mods, def.Duration)
end

local function apply(player: Player, token: Token): string
	local def = Tokens.Kinds[token.Kind]
	local data = services.DataService:Get(player)
	local stats = services.StatService:Get(player)
	if not data or not stats then
		return def.Name
	end
	if def.Buff then
		addStacks(player, token.Kind, 1)
		local b = buffs[player][token.Kind]
		return string.format("%s x%d", def.Name, b.Stacks)
	elseif def.Instant == "Coins" then
		local coins = math.floor(Balance.EnemyCoins(token.Level) * def.Kills * stats.CoinMult)
		services.ProgressionService:AddCoins(player, coins)
		if def.Shards then
			services.ProgressionService:AddShards(player, def.Shards)
		end
		return string.format("+%s Coins", Format.Abbrev(coins)) .. (if def.Shards then " +" .. def.Shards .. " Shard" else "")
	elseif def.Instant == "XP" then
		local xp = math.floor(Balance.EnemyXP(token.Level) * def.Kills * stats.XPMult * Balance.XPPenalty(data.Level, token.Level))
		services.ProgressionService:AddXP(player, xp)
		return "+" .. Format.Abbrev(xp) .. " XP"
	elseif def.Instant == "Heal" then
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * def.Amount)
		end
		return string.format("+%d%% Health", math.floor(def.Amount * 100))
	elseif def.Instant == "Storm" then
		local zone = services.ZoneService:GetZone(player)
		local hits = 0
		for _, entry in ipairs(services.EnemyService:InRange(zone.Id, token.Position, def.Radius)) do
			local enemy = entry.Enemy
			if not enemy.Dead then
				services.EnemyService:Damage(enemy, player, math.max(1, math.floor(stats.Damage * def.Mult)), token.Position, 1.5, 0.4)
				hits += 1
			end
		end
		return string.format("Blade Storm! %d hit", hits)
	elseif def.Instant == "Frenzy" then
		for _, kind in ipairs({ "Haste", "Fury", "Focus" }) do
			addStacks(player, kind, def.Stacks)
		end
		return "FRENZY!"
	end
	return def.Name
end

local function collect(player: Player, index: number)
	local list = active[player]
	local token = table.remove(list, index)
	local text = apply(player, token)
	event(player, { Type = "Collect", Id = token.Id, Kind = token.Kind, Text = text })
	if Tokens.Kinds[token.Kind].Buff or token.Kind == "Frenzy" then
		sendBuffs(player)
	end
end

-- A weapon token roll for a swing that hit (CombatService).
function TokenService:OnSwingHit(player: Player, enemies: { any }, weapon: string, heavy: boolean?)
	local chance = Tokens.Weapon.Chance * (if heavy then Tokens.Weapon.HeavyMult else 1)
	if #enemies == 0 or rng:NextNumber() >= chance then
		return
	end
	local enemy = enemies[1]
	local kind = if rng:NextNumber() < Tokens.Weapon.RareChance
		then Tokens.Rares[rng:NextInteger(1, #Tokens.Rares)]
		else Tokens.Weighted(Tokens.Weapon.Kinds[weapon] or Tokens.Weapon.Kinds.Katana, rng)
	self:Spawn(player, kind, enemy.Root.Position, enemy.Level or 1, weapon)
end

-- Pet token rolls for a kill (EnemyService:Kill), for each player who earned it.
function TokenService:OnKill(enemy, rewarded: { [Player]: any })
	for player in pairs(rewarded) do
		local data = services.DataService:Get(player)
		if data and player.Parent then
			for _, uid in ipairs(data.EquippedPets) do
				local owned = data.Pets[uid]
				local def = owned and Pets.ById[owned.Id]
				if def then
					local index = Rarity.Index(def.Rarity)
					if rng:NextNumber() < (Tokens.PetChance[index] or Tokens.PetChance[1]) then
						local kind = if index >= Tokens.PetRareFrom and rng:NextNumber() < Tokens.PetRareChance
							then Tokens.Rares[rng:NextInteger(1, #Tokens.Rares)]
							else Tokens.PetKind(def)
						self:Spawn(player, kind, enemy.Root.Position, enemy.Level or 1, def.Name)
					end
				end
			end
		end
	end
end

-- Current buff stacks (tests, admin): { [kind] = stacks }.
function TokenService:Buffs(player: Player): { [string]: number }
	local out = {}
	local now = os.clock()
	for kind, b in pairs(buffs[player] or {}) do
		if b.Ends > now then
			out[kind] = b.Stacks
		end
	end
	return out
end

function TokenService:Active(player: Player): { Token }
	return active[player] or {}
end

function TokenService:Init(registry)
	services = registry
end

function TokenService:Start()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.1 then
			return
		end
		acc = 0
		local now = os.clock()
		for player, list in pairs(active) do
			if not player.Parent then
				active[player] = nil
				continue
			end
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local alive = root ~= nil and humanoid ~= nil and humanoid.Health > 0
			for i = #list, 1, -1 do
				local token = list[i]
				if now >= token.Expires then
					table.remove(list, i)
					event(player, { Type = "Expire", Id = token.Id })
				elseif alive and root then
					local d = token.Position - root.Position
					if Vector3.new(d.X, 0, d.Z).Magnitude <= Tokens.CollectRadius and math.abs(d.Y) < 9 then
						collect(player, i)
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		active[player] = nil
		buffs[player] = nil
	end)
	-- dying clears the buffs (the modifiers end on their own timers)
	local function hook(player: Player)
		player.CharacterAdded:Connect(function()
			if buffs[player] then
				buffs[player] = nil
				for kind in pairs(Tokens.Kinds) do
					if services.StatService.Modifiers[player] then
						services.StatService.Modifiers[player]["token_" .. kind] = nil
					end
				end
				services.StatService:Refresh(player)
				sendBuffs(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in ipairs(Players:GetPlayers()) do
		hook(player)
	end
end

return TokenService
