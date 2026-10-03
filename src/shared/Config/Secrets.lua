--[[
	Cursed Seals and the Seal Shop (2026-10-03). Seals come only from clearing Cursed
	Temple floors (Temple.Seals); they buy secret suits (Tiers.Secret, with their own
	ultimates), secret weapons and secret pets (Temple menu > Seal Shop, ShopService:BuySecret).
]]

local Secrets = {}

Secrets.Currency = "Cursed Seals"
Secrets.Items = {
	{ Kind = "Suit", Id = "secret_crimson", Price = 60 },
	{ Kind = "Weapon", Id = "secret_soulreaver", Price = 80 },
	{ Kind = "Pet", Id = "secret_oni_pup", Price = 100 },
	{ Kind = "Suit", Id = "secret_jade", Price = 160 },
	{ Kind = "Weapon", Id = "secret_jade_dragon", Price = 200 },
	{ Kind = "Pet", Id = "secret_temple_koi", Price = 220 },
	{ Kind = "Suit", Id = "secret_abyss", Price = 350 },
	{ Kind = "Weapon", Id = "secret_abyss_edge", Price = 400 },
	{ Kind = "Pet", Id = "secret_abyss_wyrm", Price = 500 },
}
Secrets.ById = {}
for i, item in ipairs(Secrets.Items) do
	item.Order = i
	Secrets.ById[item.Id] = item
end

return Secrets
