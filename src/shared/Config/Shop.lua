--[[
	Shop catalogue (Weapons come from Katanas.lua where Source == "Shop").

	Nothing here is Robux-only: everything is bought with Coins or Spirit Shards
	earned by playing. Premium variants can be layered on later by adding a
	ProductId field and a MarketplaceService handler in ShopService.

	Price fields:
	  CostKills  -> price = Balance.CoinsForKills(player level, CostKills)  (scales with you)
	  Cost       -> fixed price in `Currency`
]]

local Shop = {}

local rgb = Color3.fromRGB

Shop.Boosts = {
	{ Id = "XP2", Name = "2x XP", Icon = "📘", Desc = "Double XP from every enemy.", Duration = 600, CostKills = 45, Color = rgb(90, 200, 255) },
	{ Id = "Coins2", Name = "2x Coins", Icon = "🪙", Desc = "Double Coins from every enemy.", Duration = 600, CostKills = 40, Color = rgb(255, 200, 60) },
	{ Id = "Damage", Name = "Rage Tonic", Icon = "🔥", Desc = "+50% damage.", Duration = 600, CostKills = 40, Color = rgb(255, 90, 60) },
	{ Id = "Luck", Name = "Lucky Charm", Icon = "🍀", Desc = "+50% egg luck.", Duration = 900, CostKills = 30, Color = rgb(110, 230, 110) },
	{ Id = "Haste", Name = "Haste Scroll", Icon = "🌀", Desc = "+25% attack speed.", Duration = 600, CostKills = 35, Color = rgb(190, 120, 255) },
}
Shop.MaxBoostSeconds = 3 * 3600

-- Boost effects, read by Stats.Compute
Shop.BoostEffects = {
	XP2 = { XP = 2 },
	Coins2 = { Coins = 2 },
	Damage = { Damage = 1.5 },
	Luck = { Luck = 0.5 },
	Haste = { AttackSpeed = 0.25 },
}

-- Cosmetics: Kind = Aura | Trail | KillEffect | Title
Shop.Cosmetics = {
	-- Auras (particles around your ninja)
	{ Id = "aura_sakura", Kind = "Aura", Name = "Sakura Drift", Rarity = "Rare", Currency = "Coins", Cost = 25000, Color = rgb(255, 170, 200) },
	{ Id = "aura_lightning", Kind = "Aura", Name = "Storm Coil", Rarity = "Epic", Currency = "Shards", Cost = 15, Color = rgb(120, 200, 255) },
	{ Id = "aura_spirit", Kind = "Aura", Name = "Spirit Flame", Rarity = "Legendary", Currency = "Rebirth", Cost = 3, Color = rgb(120, 255, 230) },
	{ Id = "aura_galaxy", Kind = "Aura", Name = "Galaxy Veil", Rarity = "Mythic", Currency = "Shards", Cost = 60, Color = rgb(170, 120, 255) },
	-- Trails (behind your ninja while moving)
	{ Id = "trail_wind", Kind = "Trail", Name = "Wind Trail", Rarity = "Common", Currency = "Coins", Cost = 3000, Color = rgb(230, 240, 255) },
	{ Id = "trail_sakura", Kind = "Trail", Name = "Petal Trail", Rarity = "Rare", Currency = "Coins", Cost = 40000, Color = rgb(255, 160, 200) },
	{ Id = "trail_flame", Kind = "Trail", Name = "Flame Trail", Rarity = "Epic", Currency = "Shards", Cost = 12, Color = rgb(255, 120, 30) },
	{ Id = "trail_soul", Kind = "Trail", Name = "Soul Trail", Rarity = "Legendary", Currency = "Rebirth", Cost = 10, Color = rgb(120, 255, 230) },
	{ Id = "trail_rainbow", Kind = "Trail", Name = "Prism Trail", Rarity = "Mythic", Currency = "Shards", Cost = 45, Color = rgb(255, 120, 255) },
	-- Kill effects (what enemies burst into)
	{ Id = "kill_sakura", Kind = "KillEffect", Name = "Sakura Burst", Rarity = "Rare", Currency = "Coins", Cost = 15000, Color = rgb(255, 170, 200) },
	{ Id = "kill_lightning", Kind = "KillEffect", Name = "Thunderclap", Rarity = "Epic", Currency = "Shards", Cost = 10, Color = rgb(140, 220, 255) },
	{ Id = "kill_gold", Kind = "KillEffect", Name = "Gold Rush", Rarity = "Legendary", Currency = "Shards", Cost = 25, Color = rgb(255, 210, 60) },
	{ Id = "kill_void", Kind = "KillEffect", Name = "Void Collapse", Rarity = "Mythic", Currency = "Shards", Cost = 50, Color = rgb(220, 80, 255) },
	-- Titles (shown above your head)
	{ Id = "title_shinobi", Kind = "Title", Name = "Shinobi", Rarity = "Common", Currency = "Coins", Cost = 2000, Color = rgb(220, 220, 230) },
	{ Id = "title_blade", Kind = "Title", Name = "Blade Dancer", Rarity = "Rare", Currency = "Coins", Cost = 60000, Color = rgb(120, 190, 255) },
	{ Id = "title_slayer", Kind = "Title", Name = "Demon Slayer", Rarity = "Epic", Currency = "Shards", Cost = 8, Color = rgb(255, 90, 60) },
	{ Id = "title_reborn", Kind = "Title", Name = "Reborn", Rarity = "Epic", Currency = "Rebirth", Cost = 5, Color = rgb(120, 255, 230) },
	{ Id = "title_shadow", Kind = "Title", Name = "Shadow Walker", Rarity = "Legendary", Currency = "Shards", Cost = 30, Color = rgb(170, 100, 255) },
	{ Id = "title_legend", Kind = "Title", Name = "Reborn Legend", Rarity = "Mythic", Currency = "Rebirth", Cost = 15, Color = rgb(255, 210, 80) },
	{ Id = "title_void", Kind = "Title", Name = "Void Touched", Rarity = "Divine", Currency = "Shards", Cost = 120, Color = rgb(230, 80, 255) },
}

-- Utility / quality of life. MaxOwned = how many times it can be bought.
Shop.Utility = {
	{ Id = "swift_sandals", Name = "Swift Sandals", Icon = "👟", Desc = "+3 walk speed, forever.", Currency = "Coins", Cost = 1500, MaxOwned = 1 },
	{ Id = "pet_slot", Name = "Extra Pet Slot", Icon = "🐾", Desc = "Equip one more companion.", Currency = "Shards", Costs = { 6, 20, 50 }, MaxOwned = 3 },
	{ Id = "pet_storage", Name = "Pet Storage +40", Icon = "📦", Desc = "Hold 40 more companions.", Currency = "Coins", Cost = 8000, CostGrowth = 3, MaxOwned = 5 },
	{ Id = "triple_hatch", Name = "Triple Hatch", Icon = "🥚", Desc = "Open 3 eggs at once.", Currency = "Shards", Cost = 8, MaxOwned = 1 },
	{ Id = "auto_swing", Name = "Auto Swing", Icon = "🤖", Desc = "Toggle: swing automatically while an enemy is in reach.", Currency = "Shards", Cost = 15, MaxOwned = 1, RequiredRebirths = 1 },
}

Shop.CosmeticsById = {}
for index, item in ipairs(Shop.Cosmetics) do
	item.Order = index
	Shop.CosmeticsById[item.Id] = item
end
Shop.BoostsById = {}
for _, item in ipairs(Shop.Boosts) do
	Shop.BoostsById[item.Id] = item
end
Shop.UtilityById = {}
for _, item in ipairs(Shop.Utility) do
	Shop.UtilityById[item.Id] = item
end

function Shop.UtilityCost(item, owned: number): number
	if item.Costs then
		return item.Costs[math.min(owned + 1, #item.Costs)]
	end
	if item.CostGrowth then
		return math.floor(item.Cost * item.CostGrowth ^ owned)
	end
	return item.Cost
end

return Shop
