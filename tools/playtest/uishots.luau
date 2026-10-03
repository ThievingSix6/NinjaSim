--!nocheck
-- UI snapshot scenario: builds a mid-game save, then dumps the HUD and every menu
-- to /tmp/claude-0/uishots/<name>.json for tools/uipreview.
local task = require("@lune/task")
local serde = require("@lune/serde")
local fs = require("@lune/fs")
local process = require("@lune/process")
local dump = require("./uidump")

return function(E)
	local player = E.player
	local out = process.env.UISHOTS_DIR or "/tmp/claude-0/uishots"
	pcall(fs.writeDir, out)
	local DS = E.sm("DataService")
	local data = DS:Get(player)
	local DC = E.cm("Controllers.DataController")
	local MM = E.cm("UI.MenuManager")
	local function shot(name)
		task.wait(0.5)
		local guis = dump(E, player.PlayerGui)
		fs.writeFile(out .. "/" .. name .. ".json", serde.encode("json", { name = name, w = 1280, h = 720, guis = guis }))
		print("[uishots] " .. name)
	end

	-- a believable mid-game save
	local PS = E.sm("ProgressionService")
	PS:AddXP(player, 2500)
	PS:AddCoins(player, 572831)
	task.wait(3)
	local Pets = E.shared("Config.Pets")
	local eggPos = Pets.EggPosition(Pets.EggsById.village_egg)
	E.sm("ZoneService"):MarkTeleported(player)
	player.Character.HumanoidRootPart.CFrame = E.roblox.CFrame.new(eggPos + E.roblox.Vector3.new(0, 3, 6))
	task.wait(0.5)
	for _ = 1, 4 do
		DC:Request("Hatch", "village_egg", 1)
		task.wait(0.3)
	end
	DC:Request("EquipBestPets")
	DC:Request("BuyBoost", "XP2")
	DS:Set(player, "Shards", 45)
	DS:Set(player, "Rebirths", 2)
	data.Upgrades.XP = 4
	data.Upgrades.Damage = 7
	DS:Changed(player, "Upgrades")
	-- a few charms in the grid and the stash (Config/Charms)
	local Charms = E.shared("Config.Charms")
	local CS = E.sm("CharmService")
	for _, spec in ipairs({ { "Grand", "Legendary", "shuriken_storm" }, { "Large", "Rare" }, { "Small", "Magic" }, { "Small", "Mythic" }, { "Grand", "Magic" }, { "Large", "Magic" }, { "Small", "Rare" } }) do
		CS:Add(player, Charms.Roll(20, 0, nil, spec[1], spec[2], spec[3]))
	end
	CS:Add(player, Charms.RollUnique("hexfire", 40))
	local spare = CS:Add(player, Charms.Roll(20, 0, nil, "Grand", "Rare", "any"))
	if spare then
		data.Charms[spare].X, data.Charms[spare].Y = nil, nil
	end
	local spare2 = CS:Add(player, Charms.Roll(20, 0, nil, "Small", "Legendary"))
	if spare2 then
		data.Charms[spare2].X, data.Charms[spare2].Y = nil, nil
	end
	DS:Changed(player, "Charms")
	task.wait(1)
	print("state: level", data.Level, "coins", data.Coins, "pets", #data.EquippedPets)
	task.wait(15) -- let the daily reward popup, hatch overlays and toasts clear

	-- toasts and banners come and go; keep them out of the menu shots
	local toasts = player.PlayerGui:FindFirstChild("NinjaToasts")
	if toasts then
		toasts.Enabled = false
	end
	shot("hud")
	local only = process.env.UISHOTS_ONLY
	for _, name in ipairs({ "Shop", "Pets", "Inventory", "Armory", "Rebirth", "Upgrades", "Areas", "Gifts", "Trophies", "Codes", "Settings", "Skills", "Suits", "Mutate", "Trade", "Temple" }) do
		if not only or string.find(only, name, 1, true) then
			MM:Open(name)
			shot(string.lower(name))
		end
	end
	if not only or string.find(only, "Egg", 1, true) then
		MM:Open("Egg", "village_egg")
		shot("egg")
	end
	MM:Close()
	task.wait(0.3)
	if not only or string.find(only, "Skills", 1, true) then
		-- the skill bar mid-cooldown
		local SC = E.cm("Controllers.SkillController")
		SC:Cast(1)
		task.wait(0.35)
		SC:Cast(2)
		task.wait(1.2)
		shot("hud_cooldown")
	end
	if only and string.find(only, "Tokens", 1, true) then
		local TS = E.sm("TokenService")
		local root = player.Character.HumanoidRootPart
		for _, kind in ipairs({ "Haste", "Haste", "Haste", "Fury", "Focus", "Focus" }) do
			local t = TS:Spawn(player, kind, root.Position + E.roblox.Vector3.new(60, 0, 0), 10, "test")
			E.sm("ZoneService"):MarkTeleported(player)
			root.CFrame = E.roblox.CFrame.new(t.Position)
			task.wait(0.3)
		end
		task.wait(1.5)
		shot("hud_tokens")
	end
	if only and string.find(only, "Party", 1, true) then
		-- the party panel, with two fake members (the panel only reads the list)
		local Net = E.shared("Net")
		local list = { { UserId = player.UserId, Name = player.DisplayName, Leader = true }, { UserId = 901, Name = "ShadowFox" }, { UserId = 902, Name = "KunaiQueen_77" } }
		local ok = pcall(function()
			for _, conn in ipairs(E.connectionsOf and E.connectionsOf(Net.Event("Party").OnClientEvent) or {}) do
				conn({ Type = "Update", Members = list, Max = 4 })
			end
		end)
		if not ok or #E.cm("Controllers.PartyController"):Members() == 0 then
			E.sm("PartyService") -- fall back to the server path
			Net.Event("Party"):FireClient(player, { Type = "Update", Members = list, Max = 4 })
		end
		task.wait(0.5)
		shot("hud_party")
	end
	if not only or string.find(only, "Toast", 1, true) then
		for _, c in ipairs(toasts.Root:GetDescendants()) do
			if c.Name == "Toasts" then
				for _, t in ipairs(c:GetChildren()) do
					if t.ClassName == "Frame" then
						t:Destroy()
					end
				end
			end
		end
		toasts.Enabled = true
		local NC = E.cm("Controllers.NotificationController")
		NC:Banner("Bamboo Forest", "Recommended Lv 10+", E.roblox.Color3.fromRGB(120, 220, 110), 8)
		NC:Toast("Trophy complete: Getting Started! Claim it in Trophies.", E.roblox.Color3.fromRGB(255, 214, 64), "Trophy")
		NC:Toast("🔒 Samurai Village is locked. Unlock it from the Areas menu!", E.roblox.Color3.fromRGB(255, 120, 120))
		task.wait(0.4)
		shot("toast")
	end
end
