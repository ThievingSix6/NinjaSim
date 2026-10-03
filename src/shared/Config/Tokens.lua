--[[
	Combat tokens (justin, 2026-10-03, after Bee Swarm Simulator's tokens): while you
	fight, your weapon and your pets now and then drop a glowing token on the ground
	near the fight. Run through it to pick it up. There is no timer to watch: every
	hit and every kill rolls a chance, so they turn up when they turn up, and each
	fades away if it is left too long (Life). TokenService runs them, TokenController
	draws them and the buff bar.

	Kinds:
	  Buff tokens stack (up to MaxStacks). Every pickup adds a stack and restarts the
	  timer for all of them, so chaining pickups keeps a big stack alive.
	    Per = the bonus per stack: WalkSpeed / Damage multipliers (+x per stack) or
	    CritChance (added).
	  Instant tokens pay out at once: Coins (kills' worth at your zone's level), XP,
	  Heal (fraction of max health), Storm (damage all enemies nearby, x your damage),
	  Shards, or Frenzy (stacks of several buffs at once).
	  Rare tokens only come from Legendary-and-up pets (and the rare roll of a weapon).

	Sources (TokenService):
	  Weapon: a chance on every swing that hits (Weapon.Chance, x HeavyMult for heavy
	  attacks). The kind leans on the weapon type (Weapon.Kinds).
	  Pets: on every kill, each equipped pet rolls PetChance by rarity; its kind comes
	  from the pet's best bonus (PetKinds), so changing pets changes your tokens.
]]

local Tokens = {}

local rgb = Color3.fromRGB

Tokens.Life = { 8, 11 } -- seconds on the ground before it fades
Tokens.BlinkFor = 2.2 -- blinks for the last seconds of its life
Tokens.CollectRadius = 6 -- studs (flat) to pick one up
Tokens.MaxActive = 12 -- per player; past this the oldest fades
Tokens.Spread = { 4, 11 } -- studs from the fight it lands

Tokens.Kinds = {
	Haste = { Name = "Haste", Icon = "💨", Color = rgb(90, 230, 255), Buff = "WalkSpeed", Per = 0.07, MaxStacks = 10, Duration = 15 },
	Fury = { Name = "Fury", Icon = "🔥", Color = rgb(255, 80, 60), Buff = "Damage", Per = 0.05, MaxStacks = 10, Duration = 15 },
	Focus = { Name = "Focus", Icon = "🎯", Color = rgb(255, 225, 70), Buff = "CritChance", Per = 0.03, MaxStacks = 10, Duration = 15 },
	Coins = { Name = "Coin Pouch", Icon = "🪙", Color = rgb(255, 200, 40), Instant = "Coins", Kills = 3 },
	Spirit = { Name = "Spirit Orb", Icon = "✨", Color = rgb(170, 140, 255), Instant = "XP", Kills = 1 },
	Heal = { Name = "Healing Herb", Icon = "💚", Color = rgb(110, 240, 120), Instant = "Heal", Amount = 0.12 },
	-- rare
	Storm = { Name = "Blade Storm", Icon = "🌀", Color = rgb(200, 90, 255), Instant = "Storm", Radius = 24, Mult = 4, Rare = true },
	Jackpot = { Name = "Jackpot", Icon = "💰", Color = rgb(255, 170, 30), Instant = "Coins", Kills = 15, Shards = 1, Rare = true },
	Frenzy = { Name = "Frenzy", Icon = "⚡", Color = rgb(255, 110, 200), Instant = "Frenzy", Stacks = 3, Rare = true },
}
Tokens.Order = { "Haste", "Fury", "Focus", "Coins", "Spirit", "Heal", "Storm", "Jackpot", "Frenzy" }
Tokens.Rares = { "Storm", "Jackpot", "Frenzy" }

-- Weapon drops: a chance per swing that hits, the kind weighted by weapon type.
Tokens.Weapon = {
	Chance = 0.07,
	HeavyMult = 2.5,
	RareChance = 0.03, -- of a weapon token being a rare one
	Kinds = {
		Katana = { Fury = 5, Focus = 2, Haste = 2, Coins = 1, Heal = 1 },
		Nunchaku = { Haste = 5, Fury = 2, Focus = 1, Coins = 1, Heal = 1 },
		Spear = { Focus = 5, Fury = 2, Haste = 1, Coins = 1, Heal = 1 },
		Claws = { Fury = 3, Haste = 3, Focus = 1, Coins = 1, Heal = 1 },
	},
}

-- Pet drops: a chance per kill per equipped pet, by rarity index (Config/Rarity).
Tokens.PetChance = { 0.02, 0.025, 0.03, 0.04, 0.05, 0.06, 0.07, 0.09 }
Tokens.PetRareFrom = 5 -- Legendary and up can drop rare tokens
Tokens.PetRareChance = 0.15 -- of such a pet's tokens
-- a pet's token kind comes from its biggest bonus
Tokens.PetKinds = { Damage = "Fury", Coins = "Coins", XP = "Spirit", Luck = "Focus", Speed = "Haste", Health = "Heal" }

function Tokens.Get(kind: string)
	return Tokens.Kinds[kind]
end

-- The kind of token a pet drops (from its Bonus table).
function Tokens.PetKind(def): string
	local best, bestValue = "Fury", -1
	for stat, value in pairs(def and def.Bonus or {}) do
		local kind = Tokens.PetKinds[stat]
		if kind and value > bestValue then
			best, bestValue = kind, value
		end
	end
	return best
end

-- Picks a key from a { key = weight } table.
function Tokens.Weighted(weights: { [string]: number }, rng: Random): string
	local total = 0
	for _, w in pairs(weights) do
		total += w
	end
	local roll = rng:NextNumber() * total
	local last
	for _, kind in ipairs(Tokens.Order) do
		local w = weights[kind]
		if w then
			last = kind
			roll -= w
			if roll <= 0 then
				return kind
			end
		end
	end
	return last or "Fury"
end

-- A buff's multiplier / bonus at `stacks`.
function Tokens.BuffValue(kind: string, stacks: number): number
	local def = Tokens.Kinds[kind]
	return if def and def.Per then def.Per * stacks else 0
end

return Tokens
