-- Rarity tiers used by katanas, pets and cosmetics.
local Rarity = {}

Rarity.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Divine", "Secret" }

Rarity.Info = {
	Common = { Index = 1, Color = Color3.fromRGB(190, 190, 200), Glow = false },
	Uncommon = { Index = 2, Color = Color3.fromRGB(96, 214, 110), Glow = false },
	Rare = { Index = 3, Color = Color3.fromRGB(70, 160, 255), Glow = false },
	Epic = { Index = 4, Color = Color3.fromRGB(176, 92, 255), Glow = true },
	Legendary = { Index = 5, Color = Color3.fromRGB(255, 190, 40), Glow = true },
	Mythic = { Index = 6, Color = Color3.fromRGB(255, 70, 110), Glow = true },
	Divine = { Index = 7, Color = Color3.fromRGB(120, 255, 240), Glow = true },
	-- one per egg, 1 in 100,000 up to 1 in 1,000,000,000
	Secret = { Index = 8, Color = Color3.fromRGB(255, 70, 200), Glow = true },
}

function Rarity.Index(name: string): number
	local info = Rarity.Info[name]
	return if info then info.Index else 1
end

function Rarity.Color(name: string): Color3
	local info = Rarity.Info[name]
	return if info then info.Color else Color3.new(1, 1, 1)
end

return Rarity
