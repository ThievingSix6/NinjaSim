--!nocheck
local task = require("@lune/task")
local process = require("@lune/process")

return function(E)
	local roblox = E.roblox
	local Vector3, CFrame = roblox.Vector3, roblox.CFrame
	local player = E.player
	local report = E.report
	local data

	local steps = {}
	local function step(name, fn)
		table.insert(steps, { name, fn })
	end

	-- Every step starts rested: the last swing has played out and both the server's
	-- and the client's stamina pools are full, so one step's combo can't starve the next.
	local function freshStamina()
		local CC = E.cm("Controllers.CombatController")
		local CS = E.sm("CombatService")
		if not CC or not CS then
			return
		end
		for _ = 1, 40 do
			if not CC:IsAttacking() then
				break
			end
			task.wait(0.05)
		end
		CS:RefillStamina(player)
		E.shared("Util.Stamina").Refill(CC.Stamina, os.clock())
	end

	step("boot", function()
		local DS = E.sm("DataService")
		assert(DS, "DataService missing")
		data = DS:Get(player)
		assert(data, "server data not loaded")
		local DC = E.cm("Controllers.DataController")
		assert(DC and DC:IsReady(), "client not ready")
		local katana = player.Character and player.Character:FindFirstChild("EquippedKatana")
		local meshes, parts = 0, 0
		if katana then
			for _, d in ipairs(katana:GetDescendants()) do
				if d:IsA("MeshPart") then meshes += 1 elseif d:IsA("BasePart") then parts += 1 end
			end
		end
		print("katana", katana ~= nil, "meshparts", meshes, "parts", parts)
		local worldMeshes, colliders = 0, 0
		for _, d in ipairs(E.Workspace:GetDescendants()) do
			if d:IsA("MeshPart") then worldMeshes += 1 elseif d.Name == "Collider" then colliders += 1 end
		end
		print("world meshparts", worldMeshes, "colliders", colliders)
		local outfit = player.Character and player.Character:FindFirstChild("NinjaOutfit")
		local outfitMeshes, outfitParts = 0, 0
		if outfit then
			for _, d in ipairs(outfit:GetDescendants()) do
				if d:IsA("MeshPart") then outfitMeshes += 1 elseif d:IsA("BasePart") then outfitParts += 1 end
			end
		end
		print("outfit meshparts", outfitMeshes, "parts", outfitParts)
		local kinds = {}
		for _, enemy in ipairs(E.CS:GetTagged("Enemy")) do
			local m = 0
			for _, d in ipairs(enemy:GetDescendants()) do
				if d:IsA("MeshPart") then m += 1 end
			end
			kinds[enemy.Name] = m
		end
		local list = {}
		for name, m in pairs(kinds) do table.insert(list, name .. "=" .. m) end
		table.sort(list)
		print("enemy meshparts", table.concat(list, " "))
		print("daily", data.Daily.Day, data.Daily.Streak, "coins", data.Coins)
		assert(data.Daily.Streak == 1, "daily reward not granted on first join")
		print("level", data.Level, "damage", DC:GetStats().Damage, "enemies", #E.CS:GetTagged("Enemy"), "frames", E.frames())
	end)

	step("menus", function()
		local MM = E.cm("UI.MenuManager")
		for _, name in ipairs({ "Shop", "Inventory", "Pets", "Rebirth", "Upgrades", "Areas", "Codes", "Gifts", "Trophies", "Settings" }) do
			MM:Open(name)
			task.wait(0.3)
		end
		MM:Open("Egg", "village_egg")
		task.wait(0.3)
		MM:Close()
		task.wait(0.2)
	end)

	step("pet pivot + katana effects", function()
		local function shared(path)
			return E.C["ReplicatedStorage.Shared." .. path] or E.shared(path)
		end
		local PetBuilder = shared("Visuals.PetBuilder")
		local Pets = shared("Config.Pets")
		local dummy = PetBuilder.Build(Pets.ById.straw_dummy, 1)
		local up = dummy:GetPivot().UpVector
		print("straw dummy pivot up", up)
		if up.Y < 0.99 then
			report("scenario", "straw dummy pet pivot is tilted: " .. tostring(up))
		end
		local KB = shared("Visuals.KatanaBuilder")
		local Katanas = shared("Config.Katanas")
		for _, id in ipairs({ "brown_katana", "ember_katana", "frostmoon_katana", "bloodmoon_katana", "starfall_katana" }) do
			local m = KB.Build(Katanas.Get(id))
			local core = m:FindFirstChild("BladeCore")
			local names = {}
			for _, d in ipairs(core:GetDescendants()) do
				table.insert(names, d.Name)
			end
			table.sort(names)
			print("katana fx", id, table.concat(names, ","))
			local want = ({ ember_katana = "Glint", frostmoon_katana = "Sheath", bloodmoon_katana = "Aura", starfall_katana = "SheathFast" })[id]
			if want and not core:FindFirstChild(want, true) then
				report("scenario", id .. " is missing its " .. want .. " effect")
			end
			m:Destroy()
		end
	end)

	step("admin panel", function()
		local AS = E.sm("AdminService")
		task.wait(0.2)
		print("admin rank", AS:Rank(player), "attribute", player:GetAttribute("NinjaAdmin"))
		local data = E.sm("DataService"):Get(player)
		local coins0, level0 = data.Coins, data.Level
		local function run(cmd, value)
			local ok, result = AS:Run(player, cmd, player.UserId, value)
			print("admin", cmd, ok, if type(result) == "table" then result.Message else result)
			return ok
		end
		run("Coins", "1000")
		run("Levels", "2")
		run("Heal")
		run("God")
		run("God")
		run("UnlockZones")
		run("Event", "XPStorm")
		run("Coins", "abc")
		run("MakeAdmin") -- already owner: refused
		run("ListAdmins")
		if data.Coins ~= coins0 + 1000 or data.Level ~= level0 + 2 then
			E.report("scenario", "admin grants did not apply")
		end
		-- reset progress: refused without the typed confirmation, then wipes to a new save
		local saved = {}
		for k, v in pairs(data) do
			saved[k] = v
		end
		local music = data.Settings.Music
		data.Settings.Music = 0.123
		run("ResetProgress")
		if data.Level ~= saved.Level then
			E.report("scenario", "ResetProgress ran without typing RESET")
		end
		run("ResetProgress", "reset")
		task.wait(1)
		print("after reset: level", data.Level, "coins", data.Coins, "zones", data.Zones.bamboo, "music", data.Settings.Music)
		if data.Level ~= 1 or data.Coins ~= 0 or data.Zones.bamboo or data.Settings.Music ~= 0.123 then
			E.report("scenario", "ResetProgress did not reset to a new save (keeping settings)")
		end
		if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
			E.report("scenario", "no character after ResetProgress")
		end
		-- put the earlier progress back so the rest of the scenario runs as before
		for k in pairs(data) do
			data[k] = nil
		end
		for k, v in pairs(saved) do
			data[k] = v
		end
		data.Settings.Music = music
		E.shared("Net").Event("DataSync"):FireClient(player, data)
		E.sm("StatService"):Refresh(player)
		task.wait(0.5)
		-- the panel itself
		local MM = E.cm("UI.MenuManager")
		MM:Open("Admin")
		task.wait(0.5)
		MM:Close()
		task.wait(0.3)
		-- a non-admin is refused
		local ok = AS:Run({ UserId = 1, Name = "x" } :: any, "Coins", player.UserId, "5")
		print("non-admin allowed (true in Studio, where every tester is an owner):", ok)
	end)

	step("keyboard + mouse input", function()
		local UIS = E.wrap(E.rgame:GetService("UserInputService"))
		local function key(code)
			local input = { UserInputType = E.roblox.Enum.UserInputType.Keyboard, KeyCode = code, Position = Vector3.new(), UserInputState = E.roblox.Enum.UserInputState.Begin }
			E.signalFor(UIS, "InputBegan"):Fire(input, false)
			task.wait(0.25)
			E.signalFor(UIS, "InputEnded"):Fire(input, false)
		end
		local K = E.roblox.Enum.KeyCode
		for _, code in ipairs({ K.G, K.P, K.I, K.R, K.U, K.M, K.T, K.Escape, K.F }) do
			key(code)
		end
		local click = { UserInputType = E.roblox.Enum.UserInputType.MouseButton1, KeyCode = K.Unknown, Position = Vector3.new(600, 300, 0) }
		E.signalFor(UIS, "InputBegan"):Fire(click, false)
		task.wait(1)
		E.signalFor(UIS, "InputEnded"):Fire(click, false)
	end)

	step("sprint + double jump", function()
		local UIS = E.wrap(E.rgame:GetService("UserInputService"))
		local K = E.roblox.Enum.KeyCode
		local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
		local root = player.Character.HumanoidRootPart
		local base = E.cm("Controllers.DataController"):GetStats().WalkSpeed
		task.wait(0.1)
		print("walk speed", humanoid.WalkSpeed, "stat", base)
		local shift = { UserInputType = E.roblox.Enum.UserInputType.Keyboard, KeyCode = K.LeftShift, Position = Vector3.new() }
		E.signalFor(UIS, "InputBegan"):Fire(shift, false)
		task.wait(0.1)
		local sprint = humanoid.WalkSpeed
		E.signalFor(UIS, "InputEnded"):Fire(shift, false)
		task.wait(0.1)
		print("sprint speed", sprint, "after release", humanoid.WalkSpeed)
		if math.abs(sprint - base * 1.4) > 0.05 or math.abs(humanoid.WalkSpeed - base) > 0.05 then
			E.report("scenario", "sprint speed wrong")
		end
		-- jump: take off, then press jump again in the air
		local HS = E.roblox.Enum.HumanoidStateType
		E.signalFor(humanoid, "StateChanged"):Fire(HS.Running, HS.Landed)
		E.signalFor(humanoid, "StateChanged"):Fire(HS.Landed, HS.Jumping)
		E.signalFor(UIS, "JumpRequest"):Fire() -- the ground jump itself: must not count
		local early = root.AssemblyLinearVelocity.Y
		task.wait(0.25)
		E.signalFor(UIS, "JumpRequest"):Fire()
		local vy = root.AssemblyLinearVelocity.Y
		task.wait(0.3)
		E.signalFor(UIS, "JumpRequest"):Fire() -- no third jump
		local MC = E.cm("Controllers.MovementController")
		print("double jump: early vy", early, "after 2nd press vy", vy, "third allowed", MC:TryExtraJump())
		if not (vy > 30) or early > 30 then
			E.report("scenario", "double jump did not launch")
		end
		E.signalFor(humanoid, "StateChanged"):Fire(HS.Freefall, HS.Landed)
		root.AssemblyLinearVelocity = Vector3.zero
		task.wait(0.5)
	end)

	step("nunchucks", function()
		local DC = E.cm("Controllers.DataController")
		local data = E.sm("DataService"):Get(player)
		data.Coins += 1e7
		print("buy chucks", DC:Request("BuyKatana", "training_chucks"))
		print("equip chucks", DC:Request("EquipKatana", "training_chucks"))
		task.wait(0.6)
		local weapon = player.Character:FindFirstChild("EquippedKatana")
		print("weapon", weapon and weapon:GetAttribute("KatanaId"), weapon and weapon:GetAttribute("WeaponType"))
		if not weapon or weapon:GetAttribute("WeaponType") ~= "Nunchaku" then
			report("scenario", "nunchucks not equipped")
			return
		end
		local free = weapon:FindFirstChild("FreeStick")
		if not free then
			report("scenario", "no swinging stick on the nunchucks")
		end
		-- the sticks only simulate near the camera; welds don't carry the weapon to the player here
		E.CameraFocus = function()
			return weapon.PrimaryPart and weapon.PrimaryPart.Position
		end
		local root = player.Character.HumanoidRootPart
		local target
		for _, m in ipairs(E.CS:GetTagged("Enemy")) do
			if not m:GetAttribute("Dead") and m.PrimaryPart and m:GetAttribute("EnemyId") ~= "TrainingDummy" then
				target = m
				break
			end
		end
		if target then
			local p = target.PrimaryPart.Position
			E.sm("ZoneService"):MarkTeleported(player)
			root.CFrame = CFrame.lookAt(p + Vector3.new(0, 0, 5), p)
		end
		local CC = E.cm("Controllers.CombatController")
		local Combo = E.C["ReplicatedStorage.Shared.Config.Combo"] or E.shared("Config.Combo")
		local AC = E.cm("Controllers.AnimationController")
		local names, positions = {}, {}
		-- hold attack: swing whenever the cooldown allows, as a player holding the button does
		local lastT = 2
		for _ = 1, 200 do
			CC:Swing()
			local move, t = AC:GetSwing(player.Character)
			if move and t and t < lastT and #names < 7 then
				table.insert(names, move.Name)
			end
			lastT = t or 2
			if free and free.PrimaryPart then
				table.insert(positions, free.PrimaryPart.Position)
			end
			if #names >= 7 then
				break
			end
			task.wait(0.05)
		end
		print("nunchuck moves:", table.concat(names, " / "))
		for i = 1, math.min(#names, #Combo.Nunchaku) do
			if names[i] ~= Combo.Nunchaku[i].Name then
				report("scenario", "nunchuck move " .. i .. " was " .. tostring(names[i]) .. ", not " .. Combo.Nunchaku[i].Name)
			end
		end
		if #names < #Combo.Nunchaku then
			report("scenario", "only " .. #names .. " nunchuck moves played")
		end
		local moved = 0
		for i = 2, #positions do
			moved = math.max(moved, (positions[i] - positions[i - 1]).Magnitude)
		end
		E.CameraFocus = nil
		print("free stick max step", moved)
		if free and moved < 0.2 then
			report("scenario", "the free nunchuck stick never moved")
		end
		print("back to katana", DC:Request("EquipKatana", "brown_katana"))
		task.wait(0.5)
	end)

	step("spear", function()
		local DC = E.cm("Controllers.DataController")
		local data = E.sm("DataService"):Get(player)
		data.Coins += 1e7
		print("buy spear", DC:Request("BuyKatana", "bamboo_yari"))
		print("equip spear", DC:Request("EquipKatana", "bamboo_yari"))
		task.wait(0.6)
		local weapon = player.Character:FindFirstChild("EquippedKatana")
		print("weapon", weapon and weapon:GetAttribute("KatanaId"), weapon and weapon:GetAttribute("WeaponType"))
		if not weapon or weapon:GetAttribute("WeaponType") ~= "Spear" then
			report("scenario", "spear not equipped")
			return
		end
		local weld = weapon.PrimaryPart and weapon.PrimaryPart:FindFirstChild("KatanaGrip")
		local baseC0 = weld and weld.C0
		local root = player.Character.HumanoidRootPart
		local Balance = E.shared("Config.Balance")
		-- stand a little past katana reach from an enemy, facing it
		local target
		for _, m in ipairs(E.CS:GetTagged("Enemy")) do
			if not m:GetAttribute("Dead") and m.PrimaryPart and m:GetAttribute("EnemyId") ~= "TrainingDummy" then
				target = m
				break
			end
		end
		if target then
			local p = target.PrimaryPart.Position
			E.sm("ZoneService"):MarkTeleported(player)
			root.CFrame = CFrame.lookAt(p + Vector3.new(0, 0, Balance.AttackRange + 3), p)
			-- hold the target still (stunned) so the thrusts are measured at range, not after it charges in
			for _, e in pairs(E.sm("EnemyService").All) do
				if e.Model == target then
					e.StunUntil = os.clock() + 30
				end
			end
		end
		-- log every hit the server lands, with its distance from the player
		local ES = E.sm("EnemyService")
		local damage = ES.Damage
		local hits, farthest = 0, 0
		ES.Damage = function(self, enemy, who, amount, ...)
			if who == player and enemy.Root then
				local d = enemy.Root.Position - root.Position
				local flat = Vector3.new(d.X, 0, d.Z).Magnitude - (enemy.Radius or 0)
				hits += 1
				farthest = math.max(farthest, flat)
			end
			return damage(self, enemy, who, amount, ...)
		end
		local CC = E.cm("Controllers.CombatController")
		local Combo = E.C["ReplicatedStorage.Shared.Config.Combo"] or E.shared("Config.Combo")
		local AC = E.cm("Controllers.AnimationController")
		local names = {}
		local spun = 0
		-- hold attack: swing whenever the cooldown allows, as a player holding the button does
		local lastT = 2
		for _ = 1, 260 do
			CC:Swing()
			local move, t = AC:GetSwing(player.Character)
			if move and t and t < lastT and #names < 7 then
				table.insert(names, move.Name)
			end
			lastT = t or 2
			if weld and baseC0 then
				local dot = math.clamp(baseC0.LookVector:Dot(weld.C0.LookVector), -1, 1)
				spun = math.max(spun, math.acos(dot))
			end
			if #names >= 7 then
				break
			end
			task.wait(0.05)
		end
		ES.Damage = damage
		print("spear moves:", table.concat(names, " / "))
		for i = 1, math.min(#names, #Combo.Spear) do
			if names[i] ~= Combo.Spear[i].Name then
				report("scenario", "spear move " .. i .. " was " .. tostring(names[i]) .. ", not " .. Combo.Spear[i].Name)
			end
		end
		if #names < #Combo.Spear then
			report("scenario", "only " .. #names .. " spear moves played")
		end
		print(string.format("spear hits %d, farthest %.1f studs past the enemy's edge (katana reach %d), grip turned up to %.0f deg", hits, farthest, Balance.AttackRange, math.deg(spun)))
		if hits == 0 then
			report("scenario", "the spear never hit anything")
		elseif farthest <= Balance.AttackRange then
			report("scenario", "the spear never hit beyond katana reach")
		end
		if weld and spun < math.rad(60) then
			report("scenario", "the spear never turned in the hand")
		end
		print("back to katana", DC:Request("EquipKatana", "brown_katana"))
		task.wait(0.5)
	end)

	step("claws", function()
		local DC = E.cm("Controllers.DataController")
		local data = E.sm("DataService"):Get(player)
		data.Coins += 1e7
		print("buy claws", DC:Request("BuyKatana", "iron_claws"))
		print("equip claws", DC:Request("EquipKatana", "iron_claws"))
		task.wait(0.6)
		local weapon = player.Character:FindFirstChild("EquippedKatana")
		local offhand = player.Character:FindFirstChild("EquippedOffhand")
		print("weapon", weapon and weapon:GetAttribute("WeaponType"), "offhand", offhand and offhand:GetAttribute("KatanaId"))
		if not weapon or weapon:GetAttribute("WeaponType") ~= "Claws" then
			report("scenario", "claws not equipped")
			return
		end
		local offTrail = offhand and offhand:FindFirstChild("SwingTrail", true)
		if not offTrail then
			report("scenario", "no left-hand claw with a swing trail")
		end
		-- the Divine claws build from parts too, with a left-hand copy
		local KB = E.shared("Visuals.KatanaBuilder")
		local bartuc = E.shared("Config.Katanas").ById.bartucs_claws
		local right, left = KB.Build(bartuc), KB.BuildOffhand(bartuc)
		print("Bartuc's Claws parts", #right:GetDescendants(), left and #left:GetDescendants())
		if not left or not right:FindFirstChild("SwingTrail", true) then
			report("scenario", "Bartuc's Claws did not build both claws")
		end
		local root = player.Character.HumanoidRootPart
		local target
		for _, m in ipairs(E.CS:GetTagged("Enemy")) do
			if not m:GetAttribute("Dead") and m.PrimaryPart and m:GetAttribute("EnemyId") ~= "TrainingDummy" then
				target = m
				break
			end
		end
		if target then
			local p = target.PrimaryPart.Position
			E.sm("ZoneService"):MarkTeleported(player)
			root.CFrame = CFrame.lookAt(p + Vector3.new(0, 0, 5), p)
		end
		local ES = E.sm("EnemyService")
		local damage = ES.Damage
		local hits = 0
		ES.Damage = function(self, enemy, who, ...)
			if who == player then
				hits += 1
			end
			return damage(self, enemy, who, ...)
		end
		local CC = E.cm("Controllers.CombatController")
		local Combo = E.C["ReplicatedStorage.Shared.Config.Combo"] or E.shared("Config.Combo")
		local AC = E.cm("Controllers.AnimationController")
		local names = {}
		local bothLit = false
		local lastT = 2
		for _ = 1, 220 do
			CC:Swing()
			local move, t = AC:GetSwing(player.Character)
			if move and t and t < lastT and #names < 7 then
				table.insert(names, move.Name)
			end
			lastT = t or 2
			if offTrail and offTrail.Enabled then
				bothLit = true
			end
			if #names >= 7 then
				break
			end
			task.wait(0.05)
		end
		ES.Damage = damage
		print("claw moves:", table.concat(names, " / "), "hits", hits, "left trail lit", bothLit)
		for i = 1, math.min(#names, #Combo.Claws) do
			if names[i] ~= Combo.Claws[i].Name then
				report("scenario", "claw move " .. i .. " was " .. tostring(names[i]) .. ", not " .. Combo.Claws[i].Name)
			end
		end
		if #names < #Combo.Claws then
			report("scenario", "only " .. #names .. " claw moves played")
		end
		if hits == 0 then
			report("scenario", "the claws never hit anything")
		end
		if offTrail and not bothLit then
			report("scenario", "the left claw's trail never lit")
		end
		print("back to katana", DC:Request("EquipKatana", "brown_katana"))
		task.wait(0.5)
		if player.Character:FindFirstChild("EquippedOffhand") then
			report("scenario", "the left claw stayed after switching to a katana")
		end
	end)

	step("combat", function()
		local root = player.Character.HumanoidRootPart
		local enemy
		for _, m in ipairs(E.CS:GetTagged("Enemy")) do
			if m:GetAttribute("EnemyId") == "TrainingDummy" then
				enemy = m
				break
			end
		end
		assert(enemy, "no training dummy")
		local pos = enemy.PrimaryPart.Position
		E.sm("ZoneService"):MarkTeleported(player) -- a scripted move, not an exploit: skip the anti-teleport revert
		print("distance to dummy", math.floor((root.Position - pos).Magnitude))
		root.CFrame = CFrame.lookAt(pos + Vector3.new(0, 0, 4), pos)
		local CC = E.cm("Controllers.CombatController")
		local AC = E.cm("Controllers.AnimationController")
		local ES = E.sm("EnemyService")
		local moves, knocks = {}, {}
		local playSwing, damage = AC.PlaySwing, ES.Damage
		AC.PlaySwing = function(self, character, index, ...)
			table.insert(moves, index)
			return playSwing(self, character, index, ...)
		end
		ES.Damage = function(self, enemy, p, amount, from, knockback, stun)
			table.insert(knocks, knockback or 0)
			return damage(self, enemy, p, amount, from, knockback, stun)
		end
		local hp0 = enemy:GetAttribute("Health")
		local shoulder
		for _, d in ipairs(player.Character:GetDescendants()) do
			if d:IsA("Motor6D") and (d.Name == "RightShoulder" or d.Name == "Right Shoulder") then
				shoulder = d
			end
		end
		for i = 1, 30 do
			if enemy:GetAttribute("Dead") then
				-- this dummy is down: walk up to a standing one so every move has a target
				for _, m in ipairs(E.CS:GetTagged("Enemy")) do
					if m:GetAttribute("EnemyId") == "TrainingDummy" and not m:GetAttribute("Dead") and m.PrimaryPart then
						enemy = m
						local p = m.PrimaryPart.Position
						E.sm("ZoneService"):MarkTeleported(player)
						root.CFrame = CFrame.lookAt(p + Vector3.new(0, 0, 4), p)
						break
					end
				end
			end
			CC:Swing()
			if i == 1 and shoulder then
				task.wait(0.12)
				local base = shoulder:GetAttribute("NinjaC0")
				local moved = base and (shoulder.C0.Position - base.Position).Magnitude + (shoulder.C0.LookVector - base.LookVector).Magnitude
				print("swing poses the shoulder through C0:", moved ~= nil and moved > 0.05, moved)
				if not (moved and moved > 0.05) then
					E.report("scenario", "swing did not pose the right shoulder")
				end
				task.wait(0.33)
				continue
			end
			task.wait(0.45)
			if i <= 6 then
				print("swing", i, "dummy hp", enemy:GetAttribute("Health"), "/", hp0, "dead", enemy:GetAttribute("Dead"))
			end
		end
		AC.PlaySwing, ES.Damage = playSwing, damage
		print("combo moves played", table.concat(moves, ","))
		if shoulder then
			task.wait(2.5)
			local base = shoulder:GetAttribute("NinjaC0")
			local rest = (shoulder.C0.Position - base.Position).Magnitude + (shoulder.C0.LookVector - base.LookVector).Magnitude
			print("shoulder back at rest after the combo:", rest < 1e-4, rest)
			local HUD = E.cm("UI.HUD")
			HUD:ShowStreak("DOUBLE KILL!", 2)
			task.wait(2)
			for _, d in ipairs(player.PlayerGui:GetDescendants()) do
				if d:IsA("TextLabel") and d.Text == "DOUBLE KILL!" then
					print("streak text hidden after 2s:", not d.Visible)
					if d.Visible then
						E.report("scenario", "streak text still on screen")
					end
				end
			end
			if rest >= 1e-4 then
				E.report("scenario", "shoulder C0 not restored after the combo")
			end
		else
			E.report("scenario", "no right shoulder motor on the test character")
		end
		print("knockback per hit", table.concat(knocks, ","))
		assert(table.find(moves, 4) and table.find(knocks, 2.2), "the combo never reached its finisher")
		print("after combat: level", data.Level, "xp", data.XP, "coins", data.Coins, "kills", data.Lifetime.Kills)
		assert(data.Lifetime.Kills > 0, "no kills registered")
	end)

	step("stamina + dodge", function()
		local UIS = E.wrap(E.rgame:GetService("UserInputService"))
		local K = E.roblox.Enum.KeyCode
		local CC = E.cm("Controllers.CombatController")
		local DodgeC = E.cm("Controllers.DodgeController")
		local MM = E.cm("UI.MenuManager")
		local CS = E.sm("CombatService")
		local ES = E.sm("EnemyService")
		local Balance = E.shared("Config.Balance")
		local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
		local root = player.Character.HumanoidRootPart
		-- a swing spends stamina on both sides
		CC:Swing()
		task.wait(0.1)
		local client, server = CC:GetStamina(), CS:GetStamina(player)
		print(string.format("stamina after one swing: client %.0f server %.0f (cost %d)", client, server, Balance.Stamina.Attack))
		if client > Balance.Stamina.Max - Balance.Stamina.Attack + 1 or server > Balance.Stamina.Max - Balance.Stamina.Attack + 1 then
			report("scenario", "a swing did not spend stamina")
		end
		print("walking slowly while the swing plays:", CC:IsAttacking(), humanoid.WalkSpeed)
		task.wait(1.2)
		E.shared("Util.Stamina").Refill(CC.Stamina, os.clock())
		CS:RefillStamina(player)
		-- Circle (ButtonB) rolls when no menu is open
		local circle = { UserInputType = E.roblox.Enum.UserInputType.Gamepad1, KeyCode = K.ButtonB, Position = Vector3.new() }
		E.signalFor(humanoid, "StateChanged"):Fire(E.roblox.Enum.HumanoidStateType.Jumping, E.roblox.Enum.HumanoidStateType.Landed)
		E.signalFor(UIS, "InputBegan"):Fire(circle, false)
		task.wait(0.1)
		local rolling = DodgeC:IsDodging()
		local velocity = root:FindFirstChild("DodgeVelocity")
		local invulnerable = CS:IsInvulnerable(player)
		print("circle press: dodging", rolling, "velocity", velocity ~= nil, "server i-frames", invulnerable, "stamina", math.floor(CC:GetStamina()))
		if not rolling or not velocity then
			report("scenario", "Circle did not start a dodge roll")
		end
		if not invulnerable then
			report("scenario", "the server opened no i-frames for the dodge")
		end
		task.wait(Balance.Dodge.Duration + 0.2)
		print("after the roll: dodging", DodgeC:IsDodging(), "velocity left", root:FindFirstChild("DodgeVelocity") ~= nil, "i-frames", CS:IsInvulnerable(player))
		if DodgeC:IsDodging() or root:FindFirstChild("DodgeVelocity") or CS:IsInvulnerable(player) then
			report("scenario", "the dodge did not end")
		end
		-- Circle with a menu open only closes the menu
		task.wait(Balance.Dodge.Cooldown)
		MM:Open("Shop")
		task.wait(0.4)
		E.signalFor(UIS, "InputBegan"):Fire(circle, false)
		task.wait(0.1)
		print("circle with the shop open: menu open", MM:IsOpen(), "dodging", DodgeC:IsDodging())
		if MM:IsOpen() or DodgeC:IsDodging() then
			report("scenario", "Circle should close the menu without rolling")
		end
		task.wait(0.5)
		-- no stamina, no roll
		E.shared("Util.Stamina").Spend(CC.Stamina, os.clock(), 1000)
		print("roll with an empty bar:", DodgeC:Dodge())
		if DodgeC:IsDodging() then
			report("scenario", "rolled with no stamina")
		end
		task.wait(1.5)
		E.shared("Util.Stamina").Refill(CC.Stamina, os.clock())
		CS:RefillStamina(player)
		-- an enemy swing lands after its windup unless a roll's i-frames cover it
		local enemy
		for _, e in pairs(ES.All) do
			if not e.Dead and not e.IsBoss and not e.Def.Static and e.Humanoid then
				enemy = e
				break
			end
		end
		if not enemy then
			report("scenario", "no enemy to test the dodge against")
			return
		end
		local function standByEnemy()
			E.sm("ZoneService"):MarkTeleported(player)
			local p = enemy.Root.Position
			root.CFrame = CFrame.lookAt(p + Vector3.new(0, 0, 3), p)
		end
		humanoid.Health = humanoid.MaxHealth
		standByEnemy()
		enemy.StunUntil = 0
		ES:EnemyAttack(enemy, player)
		task.wait(Balance.EnemyWindup * 0.5)
		local early = humanoid.Health
		task.wait(Balance.EnemyWindup * 0.5 + 0.25)
		print(string.format("enemy swing: hp %.0f during windup, %.0f after it lands (max %.0f)", early, humanoid.Health, humanoid.MaxHealth))
		if early < humanoid.MaxHealth then
			report("scenario", "the enemy hit landed before its windup")
		elseif humanoid.Health >= humanoid.MaxHealth then
			report("scenario", "the enemy swing never landed")
		end
		task.wait(Balance.Dodge.Cooldown)
		humanoid.Health = humanoid.MaxHealth
		standByEnemy()
		enemy.StunUntil = 0
		local evaded = 0
		local conn = E.C["ReplicatedStorage.Shared.Net"].Event("Evaded").OnClientEvent:Connect(function()
			evaded += 1
		end)
		ES:EnemyAttack(enemy, player)
		task.wait(Balance.EnemyWindup - 0.2)
		print("rolling into the swing:", DodgeC:Dodge())
		task.wait(0.5)
		conn:Disconnect()
		print("hp after rolling through it", humanoid.Health, "/", humanoid.MaxHealth, "evaded", evaded)
		if humanoid.Health < humanoid.MaxHealth then
			report("scenario", "the dodge's i-frames did not stop the enemy hit")
		end
	end)

	step("heavy attack + momentum", function()
		local CC = E.cm("Controllers.CombatController")
		local ES = E.sm("EnemyService")
		local Net = E.shared("Net")
		local Combo = E.shared("Config.Combo")
		local root = player.Character.HumanoidRootPart
		local hits = {}
		local conn = Net.Event("CombatResult").OnClientEvent:Connect(function(result)
			for _, hit in ipairs(result.Hits) do
				table.insert(hits, { Damage = hit.Damage, Heavy = result.Heavy, Crit = hit.Crit })
			end
		end)
		local enemy
		for _, e in pairs(ES.All) do
			if not e.Dead and not e.IsBoss then
				enemy = e
				break
			end
		end
		if not enemy then
			report("scenario", "no enemy for the heavy attack test")
			conn:Disconnect()
			return
		end
		enemy.MaxHealth, enemy.Health = 1e12, 1e12
		local function place(dist: number)
			E.sm("ZoneService"):MarkTeleported(player)
			root.CFrame = CFrame.new(enemy.Root.Position + Vector3.new(dist, 0, 0)) * CFrame.Angles(0, math.pi / 2, 0)
		end
		-- a tap: a light attack, and it steps in a little
		task.wait(1.2)
		freshStamina()
		place(9)
		local x0 = root.Position.X
		CC:PressAttack()
		task.wait(0.05)
		CC:ReleaseAttack()
		task.wait(1.0)
		print("tap: hits", #hits, "heavy", hits[1] and hits[1].Heavy, "| stepped", string.format("%.2f", x0 - root.Position.X), "studs")
		if #hits == 0 or hits[1].Heavy then
			report("scenario", "a tap of attack didn't make a light attack")
		end
		if x0 - root.Position.X < 1 then
			report("scenario", "a light attack carried no momentum")
		end
		local light = hits[1] and hits[1].Damage or 0
		-- a hold: charges, then a heavy attack on release
		table.clear(hits)
		task.wait(1.2)
		freshStamina()
		place(5)
		CC:PressAttack()
		task.wait(Combo.Heavy.HoldDelay + Combo.Heavy.ChargeTime + 0.2)
		local charging, charge = CC:IsCharging()
		print("holding: charging", charging, "charge", string.format("%.2f", charge), "| attacking (slow walk)", CC:IsAttacking())
		if not charging or charge < 0.99 then
			report("scenario", "holding attack didn't charge a heavy attack")
		end
		CC:ReleaseAttack()
		task.wait(1.2)
		print("heavy: hits", #hits, "heavy", hits[1] and hits[1].Heavy, "damage", hits[1] and hits[1].Damage, "vs light", light)
		if #hits == 0 or not hits[1].Heavy then
			report("scenario", "releasing a charge didn't land a heavy attack")
		elseif not hits[1].Crit and hits[1].Damage < light * 2.2 then
			report("scenario", "the heavy attack isn't much stronger than a light one")
		end
		-- a dodge while charging cancels it
		table.clear(hits)
		task.wait(1.5)
		freshStamina()
		place(5)
		CC:PressAttack()
		task.wait(Combo.Heavy.HoldDelay + 0.3)
		CC:CancelSwing(true)
		CC:ReleaseAttack()
		task.wait(1)
		print("charge cancelled: charging", (CC:IsCharging()), "hits", #hits)
		if #hits > 0 or CC:IsCharging() then
			report("scenario", "cancelling a charge still struck")
		end
		conn:Disconnect()
	end)

	step("fluid combat", function()
		local CC = E.cm("Controllers.CombatController")
		local DodgeC = E.cm("Controllers.DodgeController")
		local CS = E.sm("CombatService")
		local ES = E.sm("EnemyService")
		local Net = E.shared("Net")
		local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
		local root = player.Character.HumanoidRootPart
		local results = 0
		local conn = Net.Event("CombatResult").OnClientEvent:Connect(function()
			results += 1
		end)
		local function target()
			for _, e in pairs(ES.All) do
				if not e.Dead and not e.IsBoss then
					e.MaxHealth, e.Health = 1e12, 1e12
					E.sm("ZoneService"):MarkTeleported(player)
					-- stand on +X looking -X (Lune's lookAt mirrors Roblox's in Z)
					root.CFrame = CFrame.new(e.Root.Position + Vector3.new(4, 0, 0)) * CFrame.Angles(0, math.pi / 2, 0)
					return e
				end
			end
			return nil
		end
		local function rested()
			task.wait(1.2)
			freshStamina()
		end
		-- 1) an uncancelled swing lands
		local enemy = target()
		if not enemy then
			report("scenario", "no enemy for the fluid combat test")
			conn:Disconnect()
			return
		end
		rested()
		target()
		local hp = enemy.Health
		CC:Swing()
		task.wait(0.9)
		print("plain swing: hits", results, "damage", hp - enemy.Health)
		if results == 0 then
			report("scenario", "a plain swing hit nothing")
		end
		-- 2) dodging in the wind-up cancels it: no damage, the roll still happens
		rested()
		target()
		E.signalFor(humanoid, "StateChanged"):Fire(E.roblox.Enum.HumanoidStateType.Running, E.roblox.Enum.HumanoidStateType.Landed)
		hp = enemy.Health
		results = 0
		CC:Swing()
		task.wait(0.03)
		local rolled = DodgeC:Dodge()
		task.wait(0.9)
		print("swing then dodge in the wind-up: rolled", rolled, "hits", results, "damage", hp - enemy.Health)
		if not rolled then
			report("scenario", "could not dodge out of a swing's wind-up")
		elseif results > 0 or enemy.Health < hp then
			report("scenario", "a swing cancelled by a dodge still dealt damage")
		end
		-- 3) jumping in the wind-up cancels it too
		rested()
		target()
		hp = enemy.Health
		results = 0
		CC:Swing()
		task.wait(0.03)
		E.signalFor(humanoid, "StateChanged"):Fire(E.roblox.Enum.HumanoidStateType.Running, E.roblox.Enum.HumanoidStateType.Jumping)
		task.wait(0.9)
		print("swing then jump in the wind-up: hits", results, "damage", hp - enemy.Health, "| attacking", CC:IsAttacking())
		if results > 0 or enemy.Health < hp then
			report("scenario", "a swing cancelled by a jump still dealt damage")
		end
		-- 4) right after a cancel a new swing starts straight away
		rested()
		target()
		results = 0
		CC:Swing()
		task.wait(0.03)
		CC:CancelSwing(true)
		task.wait(0.05)
		CC:Swing()
		task.wait(0.9)
		print("cancel then swing again at once: hits", results)
		if results == 0 then
			report("scenario", "could not swing again right after a cancel")
		end
		conn:Disconnect()
		-- 5) clicking a menu's backdrop (or empty space) leaves it open
		local MM = E.cm("UI.MenuManager")
		MM:Open("Shop")
		task.wait(0.4)
		local dim = player.PlayerGui:FindFirstChild("Dim", true)
		if dim then
			E.signalFor(dim, "Activated"):Fire()
		end
		task.wait(0.3)
		print("backdrop clicked: shop still open", MM:IsOpen("Shop"))
		if not MM:IsOpen("Shop") then
			report("scenario", "clicking the backdrop closed the menu")
		end
		MM:Close()
	end)

	step("suits + mastery", function()
		local DC = E.cm("Controllers.DataController")
		local UC = E.cm("Controllers.UltimateController")
		local MS = E.sm("MasteryService")
		local Mastery = E.shared("Config.Mastery")
		local data = E.sm("DataService"):Get(player)
		local character = player.Character
		print("wear a suit not reached yet:", DC:Request("SetSuit", "void"))
		if data.Suit == "void" then
			report("scenario", "wore a suit above the best rank")
		end
		data.BestTier = math.max(data.BestTier, 3)
		E.sm("DataService"):Changed(player, "BestTier")
		print("wear the blue suit:", DC:Request("SetSuit", "blue"))
		task.wait(0.5)
		print("suit", data.Suit, "outfit tier attribute", player.Character:GetAttribute("NinjaTier"))
		if player.Character:GetAttribute("NinjaTier") ~= 3 then
			report("scenario", "the blue suit was not put on")
		end
		-- kills give the worn suit mastery
		local before = select(2, Mastery.Of(data, "blue"))
		MS:OnKill(player, { Level = data.Level, IsBoss = false })
		local afterLevel, after = Mastery.Of(data, "blue")
		print("mastery points from a kill:", before, "->", after, "level", afterLevel)
		if after <= before and afterLevel == 1 then
			report("scenario", "a kill gave no mastery")
		end
		-- the Brown Ninja keeps the first ultimates (Rush, Lance, Cataclysm, Avatar); the
		-- other suits' own sets are checked in "every suit's ultimates"
		print("wear the brown suit:", DC:Request("SetSuit", "brown"))
		task.wait(0.3)
		-- locked ultimate, then every ultimate at Mastery 100
		local locked = UC:Cast(1)
		print("ultimate at mastery 1 refused:", not locked)
		if locked then
			report("scenario", "cast an ultimate below its mastery")
		end
		MS:SetLevel(player, 100)
		task.wait(0.3)
		local damage0 = E.sm("StatService"):Get(player).Damage
		print("damage with Mastery 100:", damage0, "(+50%)")
		local hitsBy = {}
		local Net = E.C["ReplicatedStorage.Shared.Net"]
		local conn = Net.Event("SkillHits").OnClientEvent:Connect(function(payload)
			if type(payload) == "table" and payload.Caster == player.UserId and type(payload.Skill) == "string" then
				hitsBy[payload.Skill] = (hitsBy[payload.Skill] or 0) + #payload.Hits
			end
		end)
		local root = character.HumanoidRootPart
		local function nearEnemies()
			for _, e in pairs(E.sm("EnemyService").All) do
				if not e.Dead and not e.IsBoss and not e.Def.Static then
					E.sm("ZoneService"):MarkTeleported(player)
					local p = e.Root.Position
					root.CFrame = CFrame.lookAt(p + Vector3.new(0, 0, 10), p)
					return true
				end
			end
			return false
		end
		for slot = 1, 4 do
			local def = UC:Get(slot)
			if not nearEnemies() then
				report("scenario", "no enemies left for the ultimates")
				break
			end
			print("cast", def.Name, "(" .. def.Kind .. ")", UC:Cast(slot))
			task.wait(if def.Kind == "Lance" then 1.6 elseif def.Kind == "Cataclysm" then 1.6 else 0.9)
		end
		-- awakened: a sword swing throws a wave
		local avatar = UC:Get(4)
		nearEnemies()
		local waves = 0
		local waveConn = Net.Event("SkillCast").OnClientEvent:Connect(function(payload)
			if type(payload) == "table" and payload.Player == player and type(payload.Info) == "table" and payload.Info.Wave then
				waves += 1
			end
		end)
		E.cm("Controllers.CombatController"):Swing()
		task.wait(0.6)
		waveConn:Disconnect()
		conn:Disconnect()
		for slot = 1, 4 do
			local def = UC:Get(slot)
			print(string.format("  %-18s hits %d", def.Name, hitsBy[def.Id] or 0))
			if def.Kind ~= "Avatar" and (hitsBy[def.Id] or 0) == 0 then
				report("scenario", def.Name .. " hit nothing")
			end
		end
		local stats = E.sm("StatService"):Get(player)
		print("awake:", stats.Avatar ~= nil, "damage", damage0, "->", stats.Damage, "waves thrown", waves, "wave hits", hitsBy[avatar.Id] or 0)
		if not stats.Avatar then
			report("scenario", "the Avatar did not awaken")
		elseif waves == 0 then
			report("scenario", "an awakened swing threw no wave")
		end
		print("back to the rank's suit:", DC:Request("SetSuit", ""))
	end)

	step("every suit's ultimates", function()
		local DC = E.cm("Controllers.DataController")
		local UC = E.cm("Controllers.UltimateController")
		local MS = E.sm("MasteryService")
		local Mastery = E.shared("Config.Mastery")
		local Tiers = E.shared("Config.Tiers")
		local Net = E.shared("Net")
		local DS = E.sm("DataService")
		local data = DS:Get(player)
		data.BestTier = #Tiers.List
		DS:Changed(player, "BestTier")
		local hitsBy, castsBy = {}, {}
		local hitConn = Net.Event("SkillHits").OnClientEvent:Connect(function(payload)
			if type(payload) == "table" and type(payload.Hits) == "table" then
				hitsBy[payload.Skill] = (hitsBy[payload.Skill] or 0) + #payload.Hits
			end
		end)
		local root = player.Character.HumanoidRootPart
		local function nearEnemies()
			for _, e in pairs(E.sm("EnemyService").All) do
				if not e.Dead and not e.IsBoss and not e.Def.Static then
					E.sm("ZoneService"):MarkTeleported(player)
					local p = e.Root.Position
					-- stand on +X looking -X (Lune's CFrame.lookAt mirrors Roblox's in Z, so
					-- along X the aim assist and lock-on still face the right way)
					root.CFrame = CFrame.new(p + Vector3.new(9, 0, 0)) * CFrame.Angles(0, math.pi / 2, 0)
					return true
				end
			end
			return false
		end
		local hum = player.Character:FindFirstChildOfClass("Humanoid")
		local missed = {}
		-- keep the crowd alive: hundreds of kills in a few seconds stall the emulator's
		-- scheduler (it happens without ultimates too), and hits are what's checked here
		local function sturdy()
			for _, e in pairs(E.sm("EnemyService").All) do
				if not e.Dead and not e.IsBoss then
					e.MaxHealth = 1e12
					e.Health = 1e12
				end
			end
		end
		-- SUITS=green,blue tests just those (one emulator run per suit keeps the
		-- emulator's timer queue small; a long run of all 44 can stall it)
		local only = {}
		for id in string.gmatch(process.env.SUITS or "", "[^,]+") do
			only[id] = true
		end
		local function wanted(tierId: string): boolean
			return Mastery.Sets[tierId] ~= nil and (next(only) == nil or only[tierId] == true)
		end
		for _, tier in ipairs(Tiers.List) do
			if wanted(tier.Id) then
				print("wear", tier.Id, DC:Request("SetSuit", tier.Id))
				task.wait(0.3)
				MS:SetLevel(player, 100)
				task.wait(0.3)
				for slot = 1, 4 do
					local def = UC:Get(slot)
					hum.Health = hum.MaxHealth
					sturdy()
					if not nearEnemies() then
						report("scenario", "no enemies left for " .. def.Name)
						break
					end
					task.wait(0.1)
					print("  casting " .. def.Name)
					local ok = UC:Cast(slot)
					castsBy[def.Id] = ok
					task.wait(1.4)
					-- Phoenix Rebirth: the death guard takes the first lethal blow
					if def.Kind == "PhoenixRebirth" then
						local CS = E.sm("CombatService")
						hum.Health = 10
						local saved = CS:Guarded(player, hum, 1e6)
						print("  lethal blow guarded:", saved, "health", math.floor(hum.Health), "/", hum.MaxHealth, "| a second one not:", not CS:Guarded(player, hum, 1e6))
						if not saved or hum.Health < hum.MaxHealth * 0.9 then
							report("scenario", "Phoenix Rebirth did not save the player")
						end
					end
					-- swing buffs: a swing while it lasts
					if def.Kind == "StormOverload" or def.Kind == "BloodPact" then
						nearEnemies()
						freshStamina()
						E.cm("Controllers.CombatController"):Swing()
						task.wait(0.8)
					end
				end
			end
		end
		task.wait(5) -- the long ones (sentinel, clones, sanctuary, shadow realm) finish
		hitConn:Disconnect()
		for _, tier in ipairs(Tiers.List) do
			if wanted(tier.Id) then
				local line = {}
				for _, def in ipairs(Mastery.ForSuit(tier.Id)) do
					table.insert(line, string.format("%s %s/%d", def.Name, if castsBy[def.Id] then "ok" else "NO", hitsBy[def.Id] or 0))
					if not castsBy[def.Id] then
						report("scenario", def.Name .. " did not cast")
					elseif (hitsBy[def.Id] or 0) == 0 and def.Kind ~= "PhoenixRebirth" then
						table.insert(missed, def.Name)
					end
				end
				print(string.format("  %-9s %s", tier.Id, table.concat(line, " | ")))
			end
		end
		print("hit nothing:", #missed, table.concat(missed, ", "))
		if #missed > 0 then
			report("scenario", #missed .. " ultimates hit nothing: " .. table.concat(missed, ", "))
		end
		print("back to the rank's suit:", DC:Request("SetSuit", ""))
		hum.Health = hum.MaxHealth
	end)

	step("mutation machine", function()
		local DC = E.cm("Controllers.DataController")
		local Mutations = E.shared("Config.Mutations")
		local Hats = E.shared("Config.Hats")
		local MS = E.sm("MutationService")
		local data = E.sm("DataService"):Get(player)
		data.Coins += 1e9
		data.Shards += 1000
		local uid = E.sm("PetService"):Grant(player, "fox")
		local hat = Hats.Roll(1, 10, 0, false, nil, "Rare")
		data.HatSerial += 1
		local hatUid = tostring(data.HatSerial)
		data.Hats[hatUid] = hat
		E.sm("DataService"):Changed(player, "Hats")
		local root = player.Character.HumanoidRootPart
		print("roll far from the machine:", DC:Request("MutateItem", "Pet", uid, false))
		E.sm("ZoneService"):MarkTeleported(player)
		root.CFrame = CFrame.new(MS.Position() + Vector3.new(6, 3, 0))
		task.wait(0.3)
		local coins0 = data.Coins
		local ok, result = DC:Request("MutateItem", "Pet", uid, false)
		print("pet roll:", ok, result and result.Mutation, "coins spent", coins0 - data.Coins, "saved", data.Pets[uid].Mutation)
		if not ok or not data.Pets[uid].Mutation then
			report("scenario", "the machine did not mutate the pet")
		end
		task.wait(1.3)
		local shards0 = data.Shards
		ok, result = DC:Request("MutateItem", "Hat", hatUid, true)
		print("lucky hat roll:", ok, result and result.Mutation, "shards spent", shards0 - data.Shards, "name", Hats.Name(data.Hats[hatUid]))
		if not ok or not data.Hats[hatUid].M then
			report("scenario", "the machine did not mutate the hat")
		end
		-- hat stats scale with the mutation
		local plain = table.clone(hat)
		plain.M = nil
		local before, after = Hats.Bonus(plain), Hats.Bonus(data.Hats[hatUid])
		for key, value in pairs(before) do
			if type(value) == "number" then
				print(string.format("  hat %s %.3f -> %.3f", key, value, after[key]))
				break
			end
		end
		-- odds: Secret is rare, lucky rolls tilt toward the rare ones; eggs never give it
		local counts, luckyCounts = {}, {}
		local rng = nil
		for _ = 1, 20000 do
			local a = Mutations.MachineRoll(false, 0, rng)
			counts[a] = (counts[a] or 0) + 1
			local b = Mutations.MachineRoll(true, 0, rng)
			luckyCounts[b] = (luckyCounts[b] or 0) + 1
		end
		print(string.format("machine odds over 20000: Big %d, Rainbow %d, Celestial %d, Secret %d; lucky Secret %d", counts.Big or 0, counts.Rainbow or 0, counts.Celestial or 0, counts.Secret or 0, luckyCounts.Secret or 0))
		if (luckyCounts.Secret or 0) <= (counts.Secret or 0) then
			report("scenario", "lucky rolls did not raise the Secret odds")
		end
		local hatched = 0
		for _ = 1, 50000 do
			if Mutations.Roll(5, rng) == "Secret" then
				hatched += 1
			end
		end
		if hatched > 0 then
			report("scenario", "an egg hatch rolled Secret")
		end
		local secret = E.C["ReplicatedStorage.Shared.Visuals.PetBuilder"].Build(E.shared("Config.Pets").ById.fox, 1, "Secret")
		print("Secret fox parts", #secret:GetDescendants(), "outline", secret:FindFirstChild("SecretOutline") ~= nil)
	end)

	step("trading", function()
		local DC = E.cm("Controllers.DataController")
		local TS = E.sm("TradeService")
		local DS = E.sm("DataService")
		local rival = E.addServerPlayer("Rival", 777)
		for _ = 1, 60 do
			if DS:Get(rival) then
				break
			end
			task.wait(0.1)
		end
		local mine, theirs = DS:Get(player), DS:Get(rival)
		if not theirs then
			report("scenario", "the second player's save never loaded")
			return
		end
		local myPet = E.sm("PetService"):Grant(player, "kitsune", "Golden")
		local theirPet = E.sm("PetService"):Grant(rival, "panda_cub")
		local Hats = E.shared("Config.Hats")
		theirs.HatSerial += 1
		local theirHat = tostring(theirs.HatSerial)
		theirs.Hats[theirHat] = Hats.Roll(1, 12, 0, false, nil, "Magic")
		print("request:", DC:Request("TradeRequest", 777))
		print("accept:", TS:Respond(rival, player.UserId, true))
		print("offer my kitsune:", DC:Request("TradeOffer", "Pet", myPet, true))
		print("rival offers panda + hat:", TS:Offer(rival, "Pet", theirPet, true), TS:Offer(rival, "Hat", theirHat, true))
		local refused = DC:Request("TradeOffer", "Pet", "no-such-pet", true)
		print("offer something I don't own refused:", not refused)
		if refused then
			report("scenario", "offered a pet I don't own")
		end
		DC:Request("TradeReady", true)
		TS:SetReady(rival, true)
		-- the rival changes their offer during the countdown: both are un-readied, nothing swaps
		task.wait(1)
		TS:Offer(rival, "Hat", theirHat, false)
		task.wait(3)
		print("after a change mid-countdown: I still have the kitsune", mine.Pets[myPet] ~= nil, "rival still has the panda", theirs.Pets[theirPet] ~= nil)
		if not mine.Pets[myPet] or not theirs.Pets[theirPet] then
			report("scenario", "the trade went through after an offer changed")
		end
		TS:Offer(rival, "Hat", theirHat, true)
		DC:Request("TradeReady", true)
		TS:SetReady(rival, true)
		task.wait(3.6)
		local gotPanda, gotHat, gaveKitsune = false, false, true
		for _, pet in pairs(mine.Pets) do
			gotPanda = gotPanda or pet.Id == "panda_cub"
		end
		for _, hat in pairs(mine.Hats) do
			gotHat = gotHat or (Hats.Valid(hat) and hat.R == "Magic")
		end
		for _, pet in pairs(theirs.Pets) do
			if pet.Id == "kitsune" and pet.Mutation == "Golden" then
				gaveKitsune = false
			end
		end
		print("after the trade: I got the panda", gotPanda, "and the hat", gotHat, "| rival has my Golden kitsune", not gaveKitsune, "| my kitsune uid gone", mine.Pets[myPet] == nil)
		if not gotPanda or not gotHat or gaveKitsune or mine.Pets[myPet] ~= nil then
			report("scenario", "the trade did not swap the items")
		end
		print("cancel with nothing open:", DC:Request("TradeCancel"))
		E.removeServerPlayer(rival)
		task.wait(0.5)
	end)

	step("charms", function()
		local DC = E.cm("Controllers.DataController")
		local DS = E.sm("DataService")
		local CS = E.sm("CharmService")
		local SS = E.sm("StatService")
		local Charms = E.shared("Config.Charms")
		local Skills = E.shared("Config.Skills")
		local mine = DS:Get(player)
		-- 1) rolls: rarity and size shares, skill charms only on Grand ones
		local rarity, size, skill, grand = {}, {}, 0, 0
		for _ = 1, 20000 do
			local c = Charms.Roll(60, 0)
			rarity[c.R] = (rarity[c.R] or 0) + 1
			size[c.Z] = (size[c.Z] or 0) + 1
			if c.Z == "Grand" then
				grand += 1
				if c.S then
					skill += 1
				end
			elseif c.S then
				report("scenario", "a " .. c.Z .. " charm rolled a skill")
			end
			if not Charms.Valid(c) then
				report("scenario", "rolled an invalid charm")
			end
		end
		print(string.format("20000 rolls: Magic %d Rare %d Legendary %d Mythic %d | Small %d Large %d Grand %d | skill grands %.0f%%",
			rarity.Magic or 0, rarity.Rare or 0, rarity.Legendary or 0, rarity.Mythic or 0, size.Small or 0, size.Large or 0, size.Grand or 0, skill / grand * 100))
		local sample = Charms.Roll(120, 0, nil, "Grand", "Mythic", "shuriken_storm")
		print("sample:", Charms.Name(sample), "|", table.concat((function()
			local t = {}
			for _, l in ipairs(Charms.Lines(sample)) do
				table.insert(t, l[1])
			end
			return t
		end)(), "; "))

		-- 2) a skill charm pushes a skill past the buyable max
		mine.Skills.shuriken_storm = Skills.MaxLevel
		DS:Changed(player, "Skills")
		local before = SS:Get(player)
		local damage0 = before.Damage
		local uid = CS:Add(player, Charms.Roll(60, 0, nil, "Grand", "Legendary", "shuriken_storm"))
		task.wait(0.3)
		local charm = mine.Charms[uid]
		local stats = SS:Get(player)
		local effective = Skills.Effective(mine.Skills.shuriken_storm, stats, "shuriken_storm")
		print("grand skill charm placed at", charm.X, charm.Y, "| shuriken storm level", mine.Skills.shuriken_storm, "->", effective, "| damage", damage0, "->", stats.Damage)
		if not charm.X then
			report("scenario", "a new charm was not put in the grid")
		end
		if effective <= Skills.MaxLevel then
			report("scenario", "the skill charm did not raise the skill past the cap")
		end
		local def = Skills.Get("shuriken_storm")
		print(string.format("cooldown at %d: %.2fs (max buyable %d: %.2fs), power x%.2f", effective, Skills.Cooldown(def, effective), Skills.MaxLevel, Skills.Cooldown(def, Skills.MaxLevel), Skills.Power(effective)))
		-- the server casts at the boosted level
		local slot = table.find(mine.SkillSlots, "shuriken_storm")
		if slot then
			local ok, result = E.sm("SkillService"):Cast(player, slot, nil)
			print("server cast:", ok, "cooldown", result and result.Cooldown)
			if ok and math.abs(result.Cooldown - Skills.Cooldown(def, effective)) > 0.01 then
				report("scenario", "the server cast at the bought level, not the charm level")
			end
		end
		-- the client sees it too
		local clientStats = DC:GetStats()
		print("client SkillBonus", clientStats.SkillBonus and clientStats.SkillBonus.shuriken_storm)

		-- 3) placing: off the grid and overlapping are refused, stash turns it off
		print("place at row 3 (runs off):", DC:Request("PlaceCharm", uid, 1, 3))
		local small = CS:Add(player, Charms.Roll(60, 0, nil, "Small", "Magic"))
		task.wait(0.2)
		local sx, sy = mine.Charms[small].X, mine.Charms[small].Y
		local overlap = DC:Request("PlaceCharm", uid, sx, sy)
		print("small charm at", sx, sy, "| move the grand onto it:", overlap)
		if overlap or DC:Request("PlaceCharm", uid, 1, 3) then
			report("scenario", "a charm was placed where it doesn't fit")
		end
		print("move the grand to column 10 row 2:", DC:Request("PlaceCharm", uid, 10, 2), mine.Charms[uid].X, mine.Charms[uid].Y)
		print("stash it:", DC:Request("StashCharm", uid))
		task.wait(0.2)
		local off = Skills.Effective(mine.Skills.shuriken_storm, SS:Get(player), "shuriken_storm")
		print("stashed: shuriken storm level", off)
		if off ~= Skills.MaxLevel then
			report("scenario", "a stashed charm still counted")
		end
		DC:Request("PlaceCharm", uid, 10, 2)

		-- 4) the Hexfire Torch: one counts, 25% on attack, the tendril burns
		local torch = Charms.RollUnique("hexfire", 80)
		print("torch:", Charms.Name(torch), torch.S.K, torch.S.N, "| lines", #Charms.Lines(torch))
		local t1 = CS:Add(player, torch)
		local t2 = CS:Add(player, Charms.RollUnique("hexfire", 80))
		task.wait(0.3)
		stats = SS:Get(player)
		print("two torches in the grid: Hexfire chance", stats.Hexfire, "AllSkills", stats.AllSkills, "(first", torch.S.N, ")")
		if stats.Hexfire ~= Charms.Hexfire.Chance then
			report("scenario", "the torch's Hexfire chance is " .. tostring(stats.Hexfire))
		end
		local hits, casts = 0, 0
		local Net = E.shared("Net")
		local hitConn = Net.Event("SkillHits").OnClientEvent:Connect(function(payload)
			if type(payload) == "table" and payload.Skill == "hexfire" then
				hits += #payload.Hits
			end
		end)
		local castConn = Net.Event("SkillCast").OnClientEvent:Connect(function(payload)
			if type(payload) == "table" and payload.Skill == "hexfire" then
				casts += 1
			end
		end)
		local root = player.Character.HumanoidRootPart
		for _, e in pairs(E.sm("EnemyService").All) do
			if not e.Dead and not e.IsBoss and not e.Def.Static then
				E.sm("ZoneService"):MarkTeleported(player)
				local p = e.Root.Position
				-- stand on +X looking -X: Lune's CFrame.lookAt mirrors Roblox's in Z, so the
				-- aim assist only turns the right way along X
				root.CFrame = CFrame.new(p + Vector3.new(12, 0, 0)) * CFrame.Angles(0, math.pi / 2, 0)
				break
			end
		end
		task.wait(0.2)
		print("facing", root.CFrame.LookVector)
		-- force the 25% roll so one swing must cast it
		local live = SS:Get(player)
		live.Hexfire = 1
		freshStamina()
		E.cm("Controllers.CombatController"):Swing()
		task.wait(1.4)
		hitConn:Disconnect()
		castConn:Disconnect()
		print("swing with Hexfire forced: casts", casts, "tendril hits", hits)
		if casts == 0 then
			report("scenario", "an attack did not cast Hexfire")
		elseif hits == 0 then
			report("scenario", "the Hexfire tendril hit nothing")
		end
		DC:Request("SalvageCharm", t2)

		-- 5) a drop on the ground is picked up into the charm stash
		local count0 = 0
		for _ in pairs(mine.Charms) do
			count0 += 1
		end
		local dropId = E.sm("LootService"):Drop(player, root.Position + Vector3.new(3, -2.5, 0), Charms.Roll(40, 0, nil, "Large", "Rare"), "Charm")
		task.wait(0.4)
		local seen = E.cm("Controllers.LootController"):Drops()[dropId] ~= nil
		print("charm drop drawn on the client:", seen, "| pickup:", DC:Request("PickupHat", dropId))
		task.wait(0.3)
		local count1 = 0
		for _ in pairs(mine.Charms) do
			count1 += 1
		end
		print("charms", count0, "->", count1)
		if count1 ~= count0 + 1 then
			report("scenario", "the picked-up charm was not stored")
		end
		print(string.format("drop chances: %.2f%% per kill, torch %.2f%% per boss kill", Charms.DropChance * 100, Charms.TorchChance * 100))

		-- 6) trading a charm
		local rival = E.addServerPlayer("CharmRival", 778)
		for _ = 1, 60 do
			if DS:Get(rival) then
				break
			end
			task.wait(0.1)
		end
		local theirs = DS:Get(rival)
		if theirs then
			local TS = E.sm("TradeService")
			local gift = CS:Add(rival, Charms.Roll(50, 0, nil, "Grand", "Mythic", "any"))
			print("request:", DC:Request("TradeRequest", 778), "accept:", TS:Respond(rival, player.UserId, true))
			print("rival offers a Mythic grand:", TS:Offer(rival, "Charm", gift, true), "I offer my small:", DC:Request("TradeOffer", "Charm", small, true))
			print("salvage while offered refused:", not DC:Request("SalvageCharm", small))
			DC:Request("TradeReady", true)
			TS:SetReady(rival, true)
			task.wait(3.6)
			local got = nil
			for _, c in pairs(mine.Charms) do
				if c.R == "Mythic" and c.Z == "Grand" then
					got = c
				end
			end
			print("after the trade: got the Mythic grand", got ~= nil, "in stash", got and got.X == nil, "| small gone", mine.Charms[small] == nil, "| rival has it", (function()
				for _, c in pairs(theirs.Charms) do
					if c.Z == "Small" then
						return true
					end
				end
				return false
			end)())
			if not got or mine.Charms[small] ~= nil then
				report("scenario", "the charm trade did not swap")
			end
			E.removeServerPlayer(rival)
		else
			report("scenario", "the charm rival's save never loaded")
		end

		-- 7) the inventory menu draws the grid
		local MM = E.cm("UI.MenuManager")
		if MM then
			-- the rival's data events also landed on this one client: resync ours first
			DS:Changed(player, "Charms")
			task.wait(0.3)
			MM:Open("Inventory")
			task.wait(0.5)
			local gui = player.PlayerGui
			local window = nil
			for _, d in ipairs(gui:GetDescendants()) do
				if d.Name == "Inventory" and d:IsA("Frame") and d:FindFirstChild("Header") then
					window = d
				end
			end
			local tiles = 0
			if window then
				for _, d in ipairs(window:GetDescendants()) do
					if d:IsA("TextButton") and string.sub(d.Name, 1, 5) == "Charm" then
						tiles += 1
					end
				end
			end
			print("inventory window", window ~= nil, "charm tiles", tiles, "owned", (function()
				local n = 0
				for _ in pairs(mine.Charms) do
					n += 1
				end
				return n
			end)())
			if not window or tiles == 0 then
				report("scenario", "the inventory shows no charms")
			end
			MM:Close()
		end
		mine.Skills.shuriken_storm = 1
		DS:Changed(player, "Skills")
	end)

	step("lockon", function()
		local LC = E.cm("Controllers.LockOnController")
		local root = player.Character.HumanoidRootPart
		local target = nil
		for _, e in pairs(E.sm("EnemyService").All) do
			if not e.Dead and not e.IsBoss and not e.Def.Static then
				target = e
				break
			end
		end
		if not target then
			report("scenario", "no enemy to lock on to")
			return
		end
		E.sm("ZoneService"):MarkTeleported(player)
		local p = target.Root.Position
		-- stand next to it, facing away: the lock still finds it and turns us round
		root.CFrame = CFrame.lookAt(p + Vector3.new(0, 0, 18), p + Vector3.new(0, 0, 40))
		task.wait(0.3)
		LC:Toggle()
		local locked = LC:Target()
		print("locked on:", locked ~= nil, locked and locked:GetAttribute("DisplayName"))
		if not locked then
			report("scenario", "lock-on found nothing")
			return
		end
		-- right after each camera update, how well do the character and camera face it?
		-- (measured against the engine's own CFrame.lookAt: Lune 0.8.9's mirrors Roblox's)
		local original = LC.Apply
		local samples, faceSum, camSum = 0, 0, 0
		LC.Apply = function(self, cam, dt)
			original(self, cam, dt)
			local t = self:Target()
			if t then
				local tp = t.PrimaryPart.Position
				local d = Vector3.new(tp.X - root.Position.X, 0, tp.Z - root.Position.Z)
				if d.Magnitude > 2 then
					local want = CFrame.lookAt(root.Position, Vector3.new(tp.X, root.Position.Y, tp.Z)).LookVector
					local camWant = CFrame.lookAt(cam.CFrame.Position, Vector3.new(tp.X, cam.CFrame.Position.Y, tp.Z)).LookVector
					samples += 1
					faceSum += root.CFrame.LookVector:Dot(want)
					camSum += Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z).Unit:Dot(camWant)
				end
			end
		end
		task.wait(0.5) -- let it turn round first
		samples, faceSum, camSum = 0, 0, 0
		task.wait(1)
		LC.Apply = original
		print(string.format("over %d frames: facing the target %.2f, camera looking at it %.2f (1 = dead on)", samples, faceSum / math.max(1, samples), camSum / math.max(1, samples)))
		if samples > 0 and faceSum / samples < 0.9 then
			report("scenario", "the locked character doesn't face the target")
		end
		if samples > 0 and camSum / samples < 0.8 then
			report("scenario", "the lock-on camera doesn't look at the target")
		end
		LC:Toggle()
		print("unlocked:", LC:Target() == nil)
	end)

	step("duel", function()
		local DC = E.cm("Controllers.DataController")
		local CC = E.cm("Controllers.CombatController")
		local DS = E.sm("DataService")
		local Duel = E.sm("DuelService")
		local Net = E.shared("Net")
		local rival = E.addServerPlayer("Duelist", 779)
		for _ = 1, 60 do
			if DS:Get(rival) and rival.Character then
				break
			end
			task.wait(0.1)
		end
		local mine, theirs = DS:Get(player), DS:Get(rival)
		if not theirs then
			report("scenario", "the duel rival never loaded")
			return
		end
		mine.Level = math.max(mine.Level, 30)
		theirs.Level = 40
		DS:Changed(player, "Level")
		local events = {}
		local conn = Net.Event("Duel").OnClientEvent:Connect(function(payload)
			table.insert(events, payload.Type)
		end)
		print("wager challenge:", DC:Request("DuelRequest", 779, true))
		print("rival accepts:", Duel:Respond(rival, player.UserId, true))
		task.wait(0.5)
		local root = player.Character.HumanoidRootPart
		local foeRoot = rival.Character.HumanoidRootPart
		print("in the dojo: y", math.floor(root.Position.Y), "rival y", math.floor(foeRoot.Position.Y), "| in duel", Duel:InDuel(player))
		if not Duel:InDuel(player) or root.Position.Y < 200 then
			report("scenario", "the duel did not start in the dojo")
		end
		task.wait(Duel.Countdown + 0.3)
		local myLevel0, theirLevel0 = mine.Level, theirs.Level
		local t0 = os.clock()
		while Duel:InDuel(player) and os.clock() - t0 < 40 do
			-- stand next to them on -X, looking +X (Lune's lookAt mirrors Roblox's in Z)
			E.sm("ZoneService"):MarkTeleported(player)
			root.CFrame = CFrame.new(foeRoot.Position - Vector3.new(4, 0, 0)) * CFrame.Angles(0, -math.pi / 2, 0)
			freshStamina()
			CC:Swing()
			task.wait(0.7)
		end
		task.wait(0.5)
		conn:Disconnect()
		local hum = rival.Character:FindFirstChildOfClass("Humanoid")
		print("duel over:", not Duel:InDuel(player), "events", table.concat(events, ","), "| rival hp", hum and math.floor(hum.Health))
		print(string.format("wager: me %d -> %d, rival %d -> %d", myLevel0, mine.Level, theirLevel0, theirs.Level))
		if Duel:InDuel(player) then
			report("scenario", "the duel never ended")
		elseif mine.Level ~= myLevel0 + math.floor(theirLevel0 / 2) or theirs.Level ~= theirLevel0 - math.floor(theirLevel0 / 2) then
			report("scenario", "the wager did not move the levels")
		end
		task.wait(3)
		print("sent back: y", math.floor(root.Position.Y))
		E.removeServerPlayer(rival)
	end)

	step("cursed temple", function()
		local DC = E.cm("Controllers.DataController")
		local DS = E.sm("DataService")
		local TS = E.sm("TempleService")
		local ES = E.sm("EnemyService")
		local Net = E.shared("Net")
		local data = DS:Get(player)
		-- the gate prompt exists in the ruined temple
		local gate = nil
		for _, d in ipairs(E.Workspace:GetDescendants()) do
			if d:IsA("ProximityPrompt") and d:GetAttribute("TempleGate") then
				gate = d
			end
		end
		print("temple gate prompt:", gate ~= nil)
		if not gate then
			report("scenario", "no Cursed Temple gate prompt in the world")
		end
		print("start locked:", DC:Request("TempleStart", 1))
		data.Zones.temple = true
		DS:Changed(player, "Zones")
		print("checkpoint not reached:", DC:Request("TempleStart", 11))
		local events = {}
		local conn = Net.Event("Temple").OnClientEvent:Connect(function(payload)
			table.insert(events, payload.Type .. (if payload.Floor then tostring(payload.Floor) else ""))
		end)
		print("start floor 1:", DC:Request("TempleStart", 1))
		task.wait(2.6)
		local run = TS:RunOf(player)
		local root = player.Character.HumanoidRootPart
		print("in the hall: y", math.floor(root.Position.Y), "| floor", run and run.Floor, "monsters", run and run.Count)
		if not run or root.Position.Y > -150 or run.Count == 0 then
			report("scenario", "the temple run did not start in a hall below the valley")
			conn:Disconnect()
			return
		end
		local levels = {}
		for enemy in pairs(run.Alive) do
			table.insert(levels, enemy.Level)
			if math.abs(enemy.Root.Position.Y - root.Position.Y) > 12 then
				report("scenario", "a temple monster spawned off the hall floor (y " .. math.floor(enemy.Root.Position.Y) .. ")")
				break
			end
		end
		table.sort(levels)
		print("floor 1 monster levels", levels[1], "to", levels[#levels])
		if levels[1] < 70 then
			report("scenario", "temple floor 1 monsters are below Level 70")
		end
		local shards0 = data.Shards
		for enemy in pairs(table.clone(run.Alive)) do
			ES:Kill(enemy, player)
		end
		task.wait(0.3)
		print("cleared:", run.Cleared, "| best", data.TempleBest, "| shards +", data.Shards - shards0)
		if not run.Cleared or data.TempleBest ~= 1 then
			report("scenario", "clearing temple floor 1 didn't open the seal / save the depth")
		end
		print("descend:", TS:Descend(player))
		task.wait(2)
		print("floor now", run.Floor, "monsters", run.Count)
		if run.Floor ~= 2 or run.Count == 0 then
			report("scenario", "descending didn't fill floor 2")
		end
		-- a boss floor
		run.Floor = 9
		for enemy in pairs(table.clone(run.Alive)) do
			ES:Kill(enemy, player)
		end
		task.wait(0.2)
		TS:Descend(player)
		task.wait(2)
		local boss = nil
		for enemy in pairs(run.Alive) do
			if enemy.IsBoss then
				boss = enemy
			end
		end
		print("floor 10 boss:", boss and boss.Def.Id, boss and boss.Level)
		if not boss then
			report("scenario", "temple floor 10 has no boss")
		end
		print("leave:", DC:Request("TempleLeave"))
		task.wait(1.2)
		conn:Disconnect()
		print("events", table.concat(events, ","))
		print("back up: y", math.floor(root.Position.Y), "| run over", TS:RunOf(player) == nil)
		if TS:RunOf(player) or root.Position.Y < -50 then
			report("scenario", "leaving the temple didn't bring the player back up")
		end
		local alive = 0
		for _, enemy in pairs(ES.All) do
			if enemy.Temple then
				alive += 1
			end
		end
		if alive > 0 then
			report("scenario", alive .. " temple monsters were left behind after the run")
		end
	end)

	step("ragdolls", function()
		local AC = E.cm("Controllers.AnimationController")
		print("ragdolls made so far", AC.RagdollCount)
		if AC.RagdollCount == 0 then
			report("scenario", "no defeated enemy turned into a ragdoll")
		end
		task.wait(3)
		local left = AC:ActiveRagdolls()
		print("ragdolls still lying around after 3s", left)
		if left > 0 then
			report("scenario", left .. " ragdolls were not cleaned up")
		end
	end)

	step("health regen + enemy sizes", function()
		local sizes = {}
		local small, big = 0, 0
		for _, enemy in pairs(E.sm("EnemyService").All) do
			local size = enemy.Model:GetAttribute("Size") or 1
			table.insert(sizes, size)
			if size < 0.9 then
				small += 1
			elseif size > 1.12 then
				big += 1
			end
		end
		print("enemy sizes", #sizes, "small", small, "big", big)
		if #sizes > 20 and (small == 0 or big == 0) then
			report("scenario", "enemy sizes don't vary")
		end
		local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
		local HS = E.sm("HealthService")
		humanoid.Health = humanoid.MaxHealth * 0.4
		HS:MarkHurt(player)
		task.wait(1.5)
		local early = humanoid.Health / humanoid.MaxHealth
		task.wait(5)
		local later = humanoid.Health / humanoid.MaxHealth
		print(string.format("regen: 40%% -> %.0f%% after 1.5s (in combat) -> %.0f%% after 6.5s", early * 100, later * 100))
		if early > 0.41 then
			report("scenario", "health regenerated while in combat")
		end
		if later <= 0.42 then
			report("scenario", "health didn't regenerate out of combat")
		end
		humanoid.Health = humanoid.MaxHealth
	end)

	step("progression + shop", function()
		local PS = E.sm("ProgressionService")
		PS:AddXP(player, 3e6)
		PS:AddCoins(player, 5e7)
		task.wait(8)
		print("level", data.Level, "tier", data.Tier, "katana", data.EquippedKatana)
		local DC = E.cm("Controllers.DataController")
		for _, req in ipairs({
			{ "BuyKatana", "oak_fang" }, { "BuyBoost", "XP2" }, { "BuyCosmetic", "trail_wind" }, { "BuyCosmetic", "aura_sakura" },
			{ "BuyCosmetic", "kill_sakura" }, { "BuyCosmetic", "title_shinobi" },
			{ "BuyUtility", "swift_sandals" }, { "BuyUtility", "pet_storage" }, { "UnlockZone", "bamboo" }, { "UnlockZone", "samurai" },
			{ "Teleport", "bamboo" }, { "EquipKatana", "brown_katana" }, { "FavoriteItem", "katana:brown_katana" },
		}) do
			print(req[1], req[2], DC:Request(req[1], req[2]))
		end
		task.wait(1)
		local MM = E.cm("UI.MenuManager")
		for _, name in ipairs({ "Shop", "Inventory", "Areas", "Settings" }) do
			MM:Open(name)
			task.wait(0.4)
		end
		MM:Close()
		print("teleport back", DC:Request("Teleport", "village"))
		task.wait(1)
	end)

	step("skills", function()
		local SS = E.sm("SkillService")
		assert(SS, "SkillService missing")
		local DC = E.cm("Controllers.DataController")
		local SC = E.cm("Controllers.SkillController")
		local FX = E.cm("Controllers.EffectsController")
		local ES = E.sm("EnemyService")
		local BS = E.sm("BossService")
		local Skills = E.shared("Config.Skills")
		local Zones = E.shared("Config.Zones")
		local root = player.Character.HumanoidRootPart
		print("starter skill", data.Skills.shuriken_storm, "slots", table.concat(data.SkillSlots, ","))
		if not (data.Skills.shuriken_storm and data.SkillSlots[1] == "shuriken_storm") then
			report("scenario", "new players should start with Shuriken Storm on key 1")
		end
		-- free unlocks by level / tier arrive on their own
		local free = {}
		for _, def in ipairs(Skills.List) do
			if Skills.IsFree(def) and Skills.MeetsRequirement(def, data) then
				table.insert(free, def.Id .. "=" .. tostring(data.Skills[def.Id]))
				if not data.Skills[def.Id] then
					report("scenario", "free skill " .. def.Id .. " was not granted")
				end
			end
		end
		print("free skills", table.concat(free, " "))
		-- buying: the ultimate needs a rebirth first, the rest cost Coins
		local ok, msg = DC:Request("BuySkill", "thousand_cuts")
		print("buy thousand_cuts before rebirth:", ok, msg)
		if ok then
			report("scenario", "Thousand Cuts was sold before Rebirth 1")
		end
		for _, def in ipairs(Skills.List) do
			if def.Unlock.Kind == "Coins" then
				local coins = data.Coins
				local bought = DC:Request("BuySkill", def.Id)
				local _, price = Skills.Price(def)
				print("buy", def.Id, bought, "paid", coins - data.Coins, "price", price)
				if not bought or coins - data.Coins ~= price then
					report("scenario", "buying " .. def.Id .. " failed or charged the wrong price")
				end
				task.wait(0.2)
			end
		end
		print("buy again refused:", not DC:Request("BuySkill", "smoke_bomb"))
		print("unlock all (admin)", SS:UnlockAll(player))
		-- upgrades and equipping
		local lv0 = data.Skills.shuriken_storm
		print("upgrade", DC:Request("UpgradeSkill", "shuriken_storm"), lv0, "->", data.Skills.shuriken_storm)
		if data.Skills.shuriken_storm ~= lv0 + 1 then
			report("scenario", "skill upgrade did not raise the level")
		end
		print("equip whirlwind to 2", DC:Request("EquipSkill", "whirlwind_slash", 2), table.concat(data.SkillSlots, ","))
		print("equip shuriken to 2 (swap)", DC:Request("EquipSkill", "shuriken_storm", 2), table.concat(data.SkillSlots, ","))
		if data.SkillSlots[2] ~= "shuriken_storm" or table.find(data.SkillSlots, "shuriken_storm") ~= 2 then
			report("scenario", "equip swap left the slots wrong: " .. table.concat(data.SkillSlots, ","))
		end
		print("unequip 4", DC:Request("UnequipSkill", 4), "slot 4 =", data.SkillSlots[4])
		print("bad slot refused", not DC:Request("EquipSkill", "shuriken_storm", 9))
		task.wait(1)

		-- helpers: stand next to the thickest crowd in the village and count damage dealt
		local function crowd()
			local best, bestN = nil, -1
			for _, enemy in ipairs(ES.ByZone.village or {}) do
				-- a real crowd: training dummies are static and can't be rooted, frozen or slowed
				if not enemy.Dead and not enemy.IsBoss and not enemy.Def.Static then
					local n = #ES:InRange("village", enemy.Root.Position, 16)
					if n > bestN then
						best, bestN = enemy, n
					end
				end
			end
			return best, bestN
		end
		local damage = ES.Damage
		local log = {}
		ES.Damage = function(self, enemy, p, amount, ...)
			if p == player then
				table.insert(log, { Boss = enemy.IsBoss, Amount = amount })
			end
			return damage(self, enemy, p, amount, ...)
		end
		local numbers = 0
		local dn = FX.DamageNumber
		FX.DamageNumber = function(...)
			numbers += 1
			return dn(...)
		end
		local function equip(id)
			DC:Request("EquipSkill", id, 1)
			task.wait(0.15)
			return data.SkillSlots[1] == id
		end

		-- bosses take skill damage
		local zone = Zones.Get("village")
		if not BS.Active.village then
			BS:SpawnBoss(zone)
		end
		task.wait(0.5)
		local boss = BS.Active.village
		if boss then
			local hp = boss.Health
			E.sm("ZoneService"):MarkTeleported(player)
			root.CFrame = CFrame.lookAt(boss.Root.Position + Vector3.new(0, 0, 8), boss.Root.Position)
			task.wait(0.6)
			equip("oni_quake")
			print("cast oni_quake at boss", SC:Cast(1))
			task.wait(1.2)
			print("boss hp", hp, "->", boss.Health)
			if not (boss.Health < hp or boss.Dead) then
				report("scenario", "the boss took no skill damage")
			end
		else
			report("scenario", "no village boss to test skills on")
		end

		local stats0 = E.sm("StatService"):Get(player).Damage
		for _, def in ipairs(Skills.List) do
			if def.Id ~= "oni_quake" then
				local target, n = crowd()
				assert(target, "no enemies left in the village")
				E.sm("ZoneService"):MarkTeleported(player)
				local p = target.Root.Position
				root.CFrame = CFrame.lookAt(p + Vector3.new(0, 0, 6), p)
				-- the harness camera drifts with every shake (no Roblox camera script resets it), and
				-- dashes go where the camera looks when standing still: point it at the crowd
				E.Workspace.CurrentCamera.CFrame = CFrame.lookAt(p + Vector3.new(0, 6, 20), p)
				task.wait(0.7)
				if not equip(def.Id) then
					report("scenario", "could not equip " .. def.Id)
				end
				table.clear(log)
				local kills0 = data.Lifetime.Kills
				local cast = SC:Cast(1)
				task.wait(0.05)
				local again = SC:Cast(1) -- still cooling down: refused on the client
				local serverAgain = SS:Cast(player, 1, Vector3.new(0, 0, -1)) -- and on the server
				task.wait(if def.Id == "thousand_cuts" then 3.2 elseif def.Id == "shadow_clone" then 3 elseif def.Id == "dragon_flame" then 2.6 else 1.6)
				local total = 0
				for _, h in ipairs(log) do
					total += h.Amount
				end
				print(string.format("cast %-16s ok=%s crowd=%d hits=%d damage=%d kills=%d | recast client=%s server=%s",
					def.Id, tostring(cast), n, #log, total, data.Lifetime.Kills - kills0, tostring(again), tostring(serverAgain)))
				if not cast then
					report("scenario", def.Id .. " could not be cast")
				elseif #log == 0 then
					report("scenario", def.Id .. " hit nothing next to a crowd of " .. n)
				end
				if again or serverAgain then
					report("scenario", def.Id .. " ignored its cooldown")
				end
				if def.Id == "bushido_spirit" then
					local buffed = E.sm("StatService"):Get(player).Damage
					print("bushido damage", stats0, "->", buffed, "client stat", DC:GetStats().Damage)
					if buffed <= stats0 then
						report("scenario", "Bushido Spirit did not raise damage")
					end
				end
			end
		end
		ES.Damage = damage
		FX.DamageNumber = dn
		print("damage numbers shown for skill hits:", numbers)
		if numbers == 0 then
			report("scenario", "no damage numbers for skill hits")
		end
		-- the menu and the HUD bar
		local MM = E.cm("UI.MenuManager")
		MM:Open("Skills")
		task.wait(0.4)
		local menuRoot = E.cm("Controllers.UIController"):Root("Menus")
		local window = menuRoot:FindFirstChild("Skills")
		local pressed = 0
		for _, d in ipairs(window:GetDescendants()) do
			if d:IsA("TextButton") and d.Name ~= "Close" and d.Parent then
				E.signalFor(d, "Activated"):Fire()
				pressed += 1
				task.wait(0.05)
			end
		end
		print("skills menu buttons pressed", pressed)
		MM:Close()
		task.wait(8) -- let the buffs and clones run out
		print("damage after buffs end", E.sm("StatService"):Get(player).Damage, "base", stats0)
		local hud = E.cm("Controllers.UIController"):Root("HUD")
		print("skill bar", hud:FindFirstChild("SkillBar") ~= nil)
	end)

	step("elemental tier skills", function()
		local SS = E.sm("SkillService")
		local DS = E.sm("DataService")
		local ES = E.sm("EnemyService")
		local DC = E.cm("Controllers.DataController")
		local SC = E.cm("Controllers.SkillController")
		local NC = E.cm("Controllers.NotificationController")
		local Skills = E.shared("Config.Skills")
		local Tiers = E.shared("Config.Tiers")
		local root = player.Character.HumanoidRootPart
		-- 2 per tier, 36 in all, the base 12 untouched
		local perTier, elemental = {}, 0
		for _, def in ipairs(Skills.List) do
			if def.Element then
				elemental += 1
				perTier[def.Unlock.Tier] = (perTier[def.Unlock.Tier] or 0) + 1
				if not SS.CastAt then
					report("scenario", "SkillService:CastAt missing")
				end
			end
		end
		print("skills", #Skills.List, "elemental", elemental, "base", Skills.BaseCount)
		if #Skills.List ~= 36 or elemental ~= 24 or Skills.BaseCount ~= 12 then
			report("scenario", "expected 12 base + 24 elemental skills")
		end
		for t = 1, #Tiers.List do
			if perTier[t] ~= 2 then
				report("scenario", "tier " .. t .. " has " .. tostring(perTier[t]) .. " elemental skills")
			end
		end
		-- rebirth keeps them: the unlock reads BestTier, not the current tier
		local fake = { Level = 1, Tier = 1, BestTier = #Tiers.List, Rebirths = 1, Lifetime = { HighestLevel = 1 } }
		for _, def in ipairs(Skills.List) do
			if def.Element and not Skills.MeetsRequirement(def, fake) then
				report("scenario", def.Id .. " would be lost on rebirth")
			end
		end
		-- forget the top five tiers' skills, then level up into them: they come back with a toast
		local data = DS:Get(player)
		for _, def in ipairs(Skills.List) do
			if def.Element and def.Unlock.Tier >= 8 then
				data.Skills[def.Id] = nil
				local slot = table.find(data.SkillSlots, def.Id)
				if slot then
					data.SkillSlots[slot] = ""
				end
			end
		end
		data.BestTier = math.min(data.BestTier, 7)
		DS:Changed(player, "Skills")
		DS:Changed(player, "SkillSlots")
		local toasts = {}
		local toast = NC.Toast
		NC.Toast = function(self, text, ...)
			table.insert(toasts, text)
			return toast(self, text, ...)
		end
		local AS = E.sm("AdminService")
		print("admin levels", AS:Run(player, "Levels", player.UserId, tostring(Tiers.List[#Tiers.List].Level + 5 - data.Level)))
		task.wait(2)
		NC.Toast = toast
		print("level", data.Level, "tier", data.Tier, "best", data.BestTier)
		local missing = {}
		for _, def in ipairs(Skills.List) do
			if def.Element and not (data.Skills[def.Id] and DC:Get().Skills[def.Id]) then
				table.insert(missing, def.Id)
			end
		end
		if #missing > 0 then
			report("scenario", "tier skills not granted at max tier: " .. table.concat(missing, ","))
		end
		local unlockToast = nil
		for _, t in ipairs(toasts) do
			if string.find(t, "skills", 1, true) then
				unlockToast = t
			end
		end
		print("unlock toast:", unlockToast)
		if not unlockToast then
			report("scenario", "no toast for the new elemental skills")
		end
		local overlay = E.cm("Controllers.UIController"):Root("Overlay")
		local cinematicLine = nil
		for _, d in ipairs(overlay:GetDescendants()) do
			if d:IsA("TextLabel") and string.find(d.Text, " skills: ", 1, true) then
				cinematicLine = d.Text
			end
		end
		print("tier cinematic line:", cinematicLine)
		task.wait(3)

		-- cast every elemental skill next to a crowd: hits and damage per skill (from SkillHits)
		local Net = E.C["ReplicatedStorage.Shared.Net"]
		local bySkill = {}
		local conn = Net.Event("SkillHits").OnClientEvent:Connect(function(payload)
			if type(payload) == "table" and payload.Caster == player.UserId then
				local entry = bySkill[payload.Skill] or { Hits = 0, Damage = 0 }
				bySkill[payload.Skill] = entry
				for _, h in ipairs(payload.Hits) do
					entry.Hits += 1
					entry.Damage += h.Damage
				end
			end
		end)
		local function crowd()
			local best, bestN = nil, -1
			for _, enemy in ipairs(ES.ByZone.village or {}) do
				-- a real crowd: training dummies are static and can't be rooted, frozen or slowed
				if not enemy.Dead and not enemy.IsBoss and not enemy.Def.Static then
					local n = #ES:InRange("village", enemy.Root.Position, 16)
					if n > bestN then
						best, bestN = enemy, n
					end
				end
			end
			return best, bestN
		end
		local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
		local hitDamage = E.sm("StatService"):Get(player).Damage
		local AS2 = E.sm("AdminService")
		AS2:Run(player, "God", player.UserId) -- tanked crowds hit back; keep the caster alive
		local results = {}
		for _, def in ipairs(Skills.List) do
			if def.Element then
				local target, n = crowd()
				assert(target, "no enemies left in the village")
				E.sm("ZoneService"):MarkTeleported(player)
				local p = target.Root.Position
				root.CFrame = CFrame.lookAt(p + Vector3.new(0, 0, 6), p)
				E.Workspace.CurrentCamera.CFrame = CFrame.lookAt(p + Vector3.new(0, 6, 20), p)
				task.wait(0.6)
				DC:Request("EquipSkill", def.Id, 1)
				task.wait(0.15)
				if data.SkillSlots[1] ~= def.Id then
					report("scenario", "could not equip " .. def.Id)
				end
				if def.Id == "sanctuary" or def.Id == "life_drain" then
					humanoid.Health = humanoid.MaxHealth * 0.5
				end
				local hp0 = humanoid.Health
				-- control skills: make the crowd tanky so the slow / freeze / float can be seen
				local control = def.Slow or def.Freeze or def.Root or def.KnockUp or def.Pull
				local tanked, speeds = {}, {}
				if control then
					for _, entry in ipairs(ES:InRange("village", p, 45)) do
						tanked[entry.Enemy] = entry.Enemy.Health
						speeds[entry.Enemy] = entry.Enemy.Humanoid and entry.Enemy.Humanoid.WalkSpeed
						entry.Enemy.Health = 1e15
					end
				end
				local t0 = os.clock()
				local cast = SC:Cast(1)
				task.wait(0.05)
				local again = SC:Cast(1)
				local serverAgain = SS:Cast(player, 1, Vector3.new(0, 0, -1))
				local extra = ""
				local function count(fn)
					local c = 0
					for enemy in pairs(tanked) do
						if not enemy.Dead and fn(enemy) then
							c += 1
						end
					end
					return c
				end
				if def.Freeze or def.Root then
					task.wait(0.8)
					extra ..= " held=" .. count(function(enemy)
						return (enemy.StunUntil or 0) > os.clock()
					end)
				end
				if def.Id == "zero_gravity" then
					task.wait(1.1)
					extra ..= " floating=" .. count(function(enemy)
						return enemy.Root:FindFirstChild("ZeroGravity") ~= nil
					end)
				end
				if def.Slow then
					task.wait(1.2)
					extra ..= " slowed=" .. count(function(enemy)
						return enemy.SkillSlowBase ~= nil and enemy.Humanoid.WalkSpeed < enemy.SkillSlowBase
					end)
				end
				local wait = math.max(1.8, (def.Field or 0) + 0.9)
				task.wait(math.max(0, wait - (os.clock() - t0)))
				local r = bySkill[def.Id] or { Hits = 0, Damage = 0 }
				if def.Id == "ring_of_fire" then
					task.wait(0.8)
					extra ..= " still slowed after=" .. count(function(enemy)
						return enemy.SkillSlowBase ~= nil or enemy.Humanoid.WalkSpeed ~= speeds[enemy]
					end)
				end
				if control and next(tanked) and not string.find(extra, "=[1-9]") and extra ~= "" then
					report("scenario", def.Id .. " control effect not seen:" .. extra)
				end
				if string.find(extra, "after=[1-9]") then
					report("scenario", "ring_of_fire slow was not restored")
				end
				for enemy, health in pairs(tanked) do
					if not enemy.Dead then
						enemy.Health = math.min(health, enemy.MaxHealth)
					end
				end
				if def.Heal then
					extra ..= string.format(" hp %.0f%%->%.0f%%", hp0 / humanoid.MaxHealth * 100, humanoid.Health / humanoid.MaxHealth * 100)
					if humanoid.Health <= hp0 then
						report("scenario", def.Id .. " did not heal")
					end
				end
				print(string.format("cast %-17s ok=%s crowd=%d hits=%d damage=%d (x%.1f hit dmg) | recast client=%s server=%s%s",
					def.Id, tostring(cast), n, r.Hits, r.Damage, r.Damage / math.max(1, hitDamage), tostring(again), tostring(serverAgain), extra))
				if not cast then
					report("scenario", def.Id .. " could not be cast")
				elseif r.Hits == 0 then
					report("scenario", def.Id .. " hit nothing next to a crowd of " .. n)
				end
				if again or serverAgain then
					report("scenario", def.Id .. " ignored its cooldown")
				end
				results[def.Id] = r
			end
		end
		-- procs: fire a skill at a point with no slot or cooldown
		task.wait(2.5) -- let Zero Gravity's floating crowd land first
		for _, id in ipairs({ "frost_nova", "black_hole", "starfall", "shuriken_storm" }) do
			local target, n = crowd()
			E.sm("ZoneService"):MarkTeleported(player)
			local p = target.Root.Position
			root.CFrame = CFrame.lookAt(p + Vector3.new(0, 0, 12), p)
			task.wait(0.4)
			bySkill[id] = nil
			local ok, info = SS:CastAt(player, id, p)
			local ok2 = SS:CastAt(player, id, p) -- no cooldown for procs
			task.wait(if id == "black_hole" then 3.2 else 1.6)
			local r = bySkill[id] or { Hits = 0, Damage = 0 }
			print(string.format("CastAt %-15s ok=%s again=%s crowd=%d hits=%d damage=%d", id, tostring(ok), tostring(ok2), n, r.Hits, r.Damage), type(info))
			if not ok or not ok2 or r.Hits == 0 then
				report("scenario", "CastAt " .. id .. " failed or hit nothing")
			end
		end
		print("CastAt unknown skill refused:", not SS:CastAt(player, "nope", root.Position))
		AS2:Run(player, "God", player.UserId)
		conn:Disconnect()
		-- the Skills menu: tabs, element blocks, every button
		local MM = E.cm("UI.MenuManager")
		MM:Open("Skills")
		task.wait(0.4)
		local window = E.cm("Controllers.UIController"):Root("Menus"):FindFirstChild("Skills")
		local blocks = window and window:FindFirstChild("Elements", true)
		local count = 0
		if blocks then
			for _, c in ipairs(blocks:GetChildren()) do
				if c:IsA("Frame") then
					count += 1
				end
			end
		end
		print("element blocks", count)
		if count ~= 12 then
			report("scenario", "the Skills menu should show 12 element blocks")
		end
		MM:Close()
		task.wait(6) -- let fields and floats run out
		local floating = 0
		for _, enemy in pairs(ES.All) do
			if enemy.Root and enemy.Root:FindFirstChild("ZeroGravity") then
				floating += 1
			end
		end
		print("enemies still floating", floating)
		if floating > 0 then
			report("scenario", "Zero Gravity left enemies floating")
		end
	end)

	step("eggs", function()
		local stand
		for _, e in ipairs(E.CS:GetTagged("EggStand")) do
			if e:GetAttribute("EggId") == "village_egg" then
				stand = e
			end
		end
		assert(stand, "no village egg")
		E.sm("ZoneService"):MarkTeleported(player)
		player.Character.HumanoidRootPart.CFrame = CFrame.new(stand.Position + Vector3.new(0, 0, 8))
		local DC = E.cm("Controllers.DataController")
		data.Shards += 100
		print("triple", DC:Request("BuyUtility", "triple_hatch"))
		print("hatch1", DC:Request("Hatch", "village_egg", 1))
		task.wait(4)
		print("hatch3", DC:Request("Hatch", "village_egg", 3))
		task.wait(5)
		local n = 0
		for _ in pairs(data.Pets) do
			n += 1
		end
		print("pets", n, "equipped", #data.EquippedPets, "attr", player:GetAttribute("EquippedPets"))
		-- auto-delete: mark every pet in the egg, hatch, nothing new should be kept
		local Pets = E.shared("Config.Pets")
		local marked = {}
		for _, entry in ipairs(Pets.Chances(Pets.EggsById.village_egg, 0)) do
			local ok, msg = DC:Request("SetAutoDelete", entry.Pet.Id, true)
			if ok then table.insert(marked, entry.Pet.Id) else print("auto-delete refused", entry.Pet.Id, msg) end
			task.wait(0.1)
		end
		E.cm("UI.MenuManager"):Open("Egg", "village_egg")
		task.wait(0.5)
		local before = n
		local serialBefore = data.PetSerial
		print("hatch w/ auto-delete", DC:Request("Hatch", "village_egg", 1))
		task.wait(4)
		local after = 0
		for uid, p in pairs(data.Pets) do
			-- a freshly hatched mutated pet is kept even when its species is auto-deleted
			if not (p.Mutation and tonumber(uid) > serialBefore) then after += 1 end
		end
		print("auto-delete marked", #marked, "pets before", before, "after", after)
		assert(#marked == 0 or after == before or not data.AutoDelete, "auto-delete kept a marked pet")
		for _, id in ipairs(marked) do
			DC:Request("SetAutoDelete", id, false)
			task.wait(0.1)
		end
		E.cm("UI.MenuManager"):Close()
		print("bad auto-delete", DC:Request("SetAutoDelete", "nope", true))
		local uid = next(data.Pets)
		print("fav", DC:Request("FavoritePet", uid))
		print("unequip", DC:Request("UnequipPet", data.EquippedPets[1]))
		print("best", DC:Request("EquipBestPets"))
		E.cm("UI.MenuManager"):Open("Pets")
		task.wait(1)
		E.cm("UI.MenuManager"):Close()
		local folder = E.Workspace:FindFirstChild("ClientPets")
		print("client pet models", folder and #folder:GetChildren())
	end)

	step("pet mutations", function()
		local function sharedMod(path)
			return E.C["ReplicatedStorage.Shared." .. path] or E.shared(path)
		end
		local Pets = E.shared("Config.Pets")
		local Mutations = E.shared("Config.Mutations")
		local Stats = E.shared("Stats")
		local PS = E.sm("PetService")
		local DC = E.cm("Controllers.DataController")
		-- 1) the roll itself: forced rolls, and the natural rate with and without luck
		local rng = { s = 42 } -- seeded stand-in for Random (NextNumber only)
		function rng:NextNumber()
			self.s = (self.s * 16807) % 2147483647
			return self.s / 2147483647
		end
		local counts, n = {}, 200000
		for _ = 1, n do
			local id = Mutations.Roll(0, rng)
			if id then counts[id] = (counts[id] or 0) + 1 end
		end
		local mutated = 0
		for _, m in ipairs(Mutations.List) do
			assert(Mutations.Roll(0, nil, m.Id) == m.Id, "forced roll " .. m.Id)
			local c = counts[m.Id] or 0
			mutated += c
			-- common ones must land near their odds (rare ones are too noisy at 200k)
			if m.OneIn <= 500 and math.abs(c / n - m.Chance) > m.Chance * 0.25 then
				report("scenario", string.format("mutation %s rolled %.5f, expected %.5f", m.Id, c / n, m.Chance))
			end
		end
		local lucky = 0
		for _ = 1, n do
			if Mutations.Roll(2, rng) then lucky += 1 end
		end
		print(string.format("mutation rate %.2f%% (expected %.2f%%), with Luck 2: %.2f%% (expected %.2f%%)",
			mutated / n * 100, Mutations.TotalChance(0) * 100, lucky / n * 100, Mutations.TotalChance(2) * 100))
		if math.abs(lucky / mutated - Mutations.LuckMult(2)) > 0.1 then
			report("scenario", "luck does not raise mutation chances as configured")
		end

		-- 2) hatch one of each, forced, through the real hatch path
		local stand
		for _, e in ipairs(E.CS:GetTagged("EggStand")) do
			if e:GetAttribute("EggId") == "village_egg" then stand = e end
		end
		E.sm("ZoneService"):MarkTeleported(player)
		player.Character.HumanoidRootPart.CFrame = CFrame.new(stand.Position + Vector3.new(0, 0, 8))
		local storageBefore = data.Utility.pet_storage
		data.Utility.pet_storage = (storageBefore or 0) + 3 -- room for the test pets
		E.sm("StatService"):Refresh(player)
		local hatched = {}
		for _, m in ipairs(Mutations.List) do
			data.Coins += Pets.EggsById.village_egg.Cost
			local serial = data.PetSerial
			PS:ForceNextMutation(player, m.Id)
			local ok, msg = DC:Request("Hatch", "village_egg", 1)
			local uid = tostring(serial + 1)
			local owned = data.Pets[uid]
			if not ok or not owned then
				report("scenario", "forced " .. m.Id .. " hatch failed: " .. tostring(msg))
			elseif owned.Mutation ~= m.Id then
				report("scenario", "forced " .. m.Id .. " hatch stored mutation " .. tostring(owned.Mutation))
			else
				hatched[m.Id] = uid
			end
			task.wait(1.3)
		end
		print("hatched mutated", (function()
			local t = {}
			for id, uid in pairs(hatched) do table.insert(t, id .. "=" .. data.Pets[uid].Id) end
			table.sort(t)
			return table.concat(t, " ")
		end)())

		-- 3) stats: the bonus is multiplied by the mutation
		for _, m in ipairs(Mutations.List) do
			local plain = Stats.PetBonus({ EquippedPets = { "1" }, Pets = { ["1"] = { Id = "jade_dragon" } } })
			local mut = Stats.PetBonus({ EquippedPets = { "1" }, Pets = { ["1"] = { Id = "jade_dragon", Mutation = m.Id } } })
			if math.abs(mut.Damage - plain.Damage * m.Mult) > 1e-6 or math.abs(mut.XP - plain.XP * m.Mult) > 1e-6 then
				report("scenario", "Stats.PetBonus ignores the " .. m.Id .. " multiplier")
			end
			local base = Pets.Score(Pets.ById.jade_dragon)
			if math.abs(Pets.Score(Pets.ById.jade_dragon, m.Id) - base * m.Mult) > 1e-6 then
				report("scenario", "Pets.Score ignores " .. m.Id)
			end
		end
		print("names", Pets.DisplayName(Pets.ById.panda_cub, "Golden"), "|", Pets.DisplayName(Pets.ById.fox), "| giant jade odds 1 in", Pets.MutatedOneIn("jade_dragon", "Giant"))
		-- equip best puts the highest mutated score first; the live stats follow
		DC:Request("EquipBestPets")
		task.wait(0.5)
		local first = data.Pets[data.EquippedPets[1]]
		local bestScore = 0
		for _, p in pairs(data.Pets) do
			bestScore = math.max(bestScore, Pets.Score(Pets.ById[p.Id], p.Mutation))
		end
		print("equip best first", first and first.Id, first and first.Mutation, "attr", player:GetAttribute("EquippedPets"))
		if not first or math.abs(Pets.Score(Pets.ById[first.Id], first.Mutation) - bestScore) > 1e-9 or not first.Mutation then
			report("scenario", "Equip Best did not count the mutation multiplier")
		end
		local live = DC:GetStats().PetBonus
		local expect = Stats.PetBonus(data)
		if math.abs(live.Damage - expect.Damage) > 1e-6 then
			report("scenario", "client pet bonus differs from Stats.PetBonus")
		end
		print("team bonus with mutations", live.Damage, live.XP, live.Coins, live.Luck)

		-- 4) visuals on the built pet
		local PetBuilder = sharedMod("Visuals.PetBuilder")
		local MutationLook = sharedMod("Visuals.MutationLook")
		local CPets = sharedMod("Config.Pets")
		local expectations = {
			Golden = function(m) return m.Body.Material == roblox.Enum.Material.Foil end,
			Frozen = function(m) return m:FindFirstChild("IceCrystal") ~= nil and m.Body.Transparency >= 0.28 and m.Body:FindFirstChild("Frost") ~= nil end,
			Shocked = function(m)
				local arcs = 0
				for _, d in ipairs(m.Body:GetChildren()) do if d.Name == "Arc" then arcs += 1 end end
				return arcs == 3 and m:FindFirstChild("Bolt") ~= nil and MutationLook.Animator(m) ~= nil
			end,
			Shadow = function(m) return m:FindFirstChild("Aura") ~= nil and m.Aura.Material == roblox.Enum.Material.ForceField end,
			Rainbow = function(m)
				local animate = MutationLook.Animator(m)
				if not animate then return false end
				local before = m.Body.Color
				animate(1.3)
				return m.Body.Color ~= before
			end,
			Celestial = function(m) return m:FindFirstChild("Halo") ~= nil and m:FindFirstChild("Star") ~= nil and m.Body:FindFirstChild("Galaxy") ~= nil end,
		}
		for _, m in ipairs(Mutations.List) do
			for _, petId in ipairs({ "fox", "jade_dragon", "straw_dummy", "koi" }) do
				local model = PetBuilder.Build(CPets.ById[petId], 1, m.Id)
				local okScale = math.abs(model:GetScale() - m.Scale) < 1e-6
				local okLook = expectations[m.Id] == nil or expectations[m.Id](model)
				if model:GetAttribute("Mutation") ~= m.Id or not okScale or not okLook then
					report("scenario", string.format("%s %s look wrong (scale %s, look %s)", m.Id, petId, tostring(model:GetScale()), tostring(okLook)))
				end
				model:Destroy()
			end
		end

		-- 5) follow pets in the world carry their mutation
		task.wait(0.5)
		local folder = E.Workspace:FindFirstChild("ClientPets")
		local worldMut = {}
		for _, model in ipairs(folder and folder:GetChildren() or {}) do
			if model:GetAttribute("Mutation") then
				table.insert(worldMut, model.Name .. ":" .. model:GetAttribute("Mutation") .. "@" .. model:GetScale())
			end
		end
		print("world mutated pets", table.concat(worldMut, " "))
		if #worldMut == 0 then
			report("scenario", "no mutated follow pet in the world")
		end

		-- 6) admin: give a mutated pet, and force the next hatch
		local AS = E.sm("AdminService")
		local serial = data.PetSerial
		print("admin give", AS:Run(player, "GivePet", player.UserId, "golden Jade Dragon"))
		local given = data.Pets[tostring(serial + 1)]
		if not given or given.Id ~= "jade_dragon" or given.Mutation ~= "Golden" then
			report("scenario", "admin GivePet did not give a Golden Jade Dragon")
		end
		print("admin next", AS:Run(player, "GivePet", player.UserId, "Rainbow"))
		print("admin bad", AS:Run(player, "GivePet", player.UserId, "golden nothing"))
		data.Coins += Pets.EggsById.village_egg.Cost
		task.wait(1.3)
		serial = data.PetSerial
		DC:Request("Hatch", "village_egg", 1)
		local nextPet = data.Pets[tostring(serial + 1)]
		print("admin forced hatch", nextPet and nextPet.Id, nextPet and nextPet.Mutation)
		if not nextPet or nextPet.Mutation ~= "Rainbow" then
			report("scenario", "admin forced mutation did not apply to the next hatch")
		end

		-- 7) menus: cards and detail show the mutation, Select All skips mutated pets
		task.wait(12) -- let the hatch reveals play
		local MM = E.cm("UI.MenuManager")
		local root = E.cm("Controllers.UIController"):Root("Menus")
		MM:Open("Pets")
		task.wait(0.5)
		local window = root:FindFirstChild("Pets")
		local tags = {}
		for _, d in ipairs(window:GetDescendants()) do
			if d.Name == "MutationTag" then table.insert(tags, d.Text) end
		end
		print("pets menu mutation tags", #tags, table.concat(tags, ","))
		if #tags < #Mutations.List then
			report("scenario", "Pets menu shows " .. #tags .. " mutation tags")
		end
		local function press(text)
			for _, d in ipairs(window:GetDescendants()) do
				if d:IsA("TextButton") then
					for _, l in ipairs(d:GetDescendants()) do
						if l:IsA("TextLabel") and l.Text == text then
							E.signalFor(d, "Activated"):Fire()
							task.wait(0.2)
							return true
						end
					end
				end
			end
			return false
		end
		print("multi delete", press("Multi Delete"), "select all", press("Select All"))
		local markedMutated = 0
		for _, d in ipairs(window:GetDescendants()) do
			if d.Name == "MutationTag" then
				for _, l in ipairs(d.Parent:GetDescendants()) do
					if l:IsA("TextLabel") and l.Text == "DELETE" then markedMutated += 1 end
				end
			end
		end
		print("mutated pets marked by Select All", markedMutated)
		if markedMutated > 0 then
			report("scenario", "Select All marked mutated pets")
		end
		press("Clear")
		press("Cancel")
		MM:Close()
		MM:Open("Egg", "village_egg")
		task.wait(0.4)
		local strip = root:FindFirstChild("Egg") and root.Egg:FindFirstChild("Mutations", true)
		print("egg mutation strip", strip ~= nil)
		if not strip then
			report("scenario", "Egg menu has no mutation strip")
		end
		MM:Close()
		data.Utility.pet_storage = storageBefore
		E.sm("StatService"):Refresh(player)
	end)

	step("codes + settings", function()
		local DC = E.cm("Controllers.DataController")
		print("code", DC:Request("RedeemCode", "RELEASE"))
		print("code again", DC:Request("RedeemCode", "RELEASE"))
		print("low gfx", DC:Request("SetSetting", "LowGraphics", true))
		print("music", DC:Request("SetSetting", "Music", 0.3))
		print("bad setting", DC:Request("SetSetting", "Music", "loud"))
		task.wait(4)
	end)

	step("gifts + guide", function()
		local DC = E.cm("Controllers.DataController")
		print("gift early", DC:Request("ClaimGift", 1))
		print("gift bogus", DC:Request("ClaimGift", 99), DC:Request("ClaimGift", "1"), DC:Request("ClaimGift", 1.5))
		local coins0 = data.Coins
		E.timeOffset += 6 * 60
		task.wait(1.5)
		local HUD = E.cm("UI.HUD")
		local badge = HUD:GetMenuButton("Gifts"):FindFirstChild("Badge")
		print("gift badge visible", badge.Visible, "timer", HUD:GetMenuButton("Gifts"):FindFirstChild("GiftTimer").Text)
		assert(badge.Visible, "gift badge should show when a gift is ready")
		print("gift 1", DC:Request("ClaimGift", 1))
		print("gift 1 again", DC:Request("ClaimGift", 1))
		print("gift 2", DC:Request("ClaimGift", 2))
		print("gift 3 (8 min)", DC:Request("ClaimGift", 3))
		assert(data.Coins > coins0, "gift coins not granted")
		print("claimed attr", player:GetAttribute("GiftsClaimed"), "boosts XP2", data.Boosts.XP2)
		local MM = E.cm("UI.MenuManager")
		MM:Open("Gifts")
		task.wait(0.6)
		MM:Close()
		-- trophies
		local shards0 = data.Shards
		print("trophy level1", DC:Request("ClaimAchievement", "level1"))
		print("trophy again", DC:Request("ClaimAchievement", "level1"))
		print("trophy unfinished", DC:Request("ClaimAchievement", "kills5"))
		print("trophy bogus", DC:Request("ClaimAchievement", "nope"), DC:Request("ClaimAchievement", 5))
		assert(data.Shards > shards0 and data.Achievements.level1, "trophy not granted")
		local trophyBadge = HUD:GetMenuButton("Trophies"):FindFirstChild("Badge")
		task.wait(1.2)
		print("trophy badge", trophyBadge.Visible)
		print("trophy claim all", DC:Request("ClaimAllAchievements"))
		print("trophy claim all again", DC:Request("ClaimAllAchievements"))
		task.wait(1.2)
		print("trophy badge after claim all", trophyBadge.Visible)
		MM:Open("Trophies")
		task.wait(0.8)
		local list = E.cm("Controllers.UIController"):Root("Menus"):FindFirstChild("Trophies")
		local summaryText = nil
		for _, d in ipairs(list and list:GetDescendants() or {}) do
			if d.ClassName == "TextLabel" and (string.find(d.Text, "ready to claim", 1, true) or string.find(d.Text, "Finish goals", 1, true)) then
				summaryText = d.Text
			end
		end
		print("trophies summary", summaryText)
		assert(summaryText, "trophies summary missing")
		MM:Close()
		-- server events + friends bonus
		local ES = E.sm("EventService")
		local c0, x0 = ES:Multipliers(player)
		ES:Begin("CoinFrenzy")
		task.wait(1.2)
		local c1, x1 = ES:Multipliers(player)
		print("event mults before", c0, x0, "during", c1, x1, "attr", E.Workspace:GetAttribute("EventId"))
		print("event pill", HUD:GetMenuButton("Shop") and E.cm("Controllers.UIController"):Root("HUD"):FindFirstChild("EventPill").Visible)
		assert(c1 == 2 and x1 == 1, "coin frenzy multiplier wrong")
		ES:Shoutout("test shoutout")
		local board = E.Workspace:FindFirstChild("Leaderboard")
		local rowsText = {}
		if board then
			for _, d in ipairs(board:GetDescendants()) do
				if d:IsA("TextLabel") and d.LayoutOrder > 0 then
					table.insert(rowsText, d.Text)
				end
			end
		end
		print("leaderboard", board ~= nil, #rowsText, rowsText[1])
		assert(board and #rowsText > 0, "leaderboard did not render")
		-- next-goal card opens the matching menu
		local hudRoot = E.cm("Controllers.UIController"):Root("HUD")
		local openGoal = hudRoot:FindFirstChild("Open", true)
		assert(openGoal, "goal card button missing")
		E.signalFor(openGoal, "Activated"):Fire()
		task.wait(0.4)
		print("goal card opened", MM:Current())
		MM:Close()
		-- guide beam: should exist and point somewhere (or be hidden) without errors
		local beam = E.Workspace:FindFirstChild("GuideTarget")
		print("guide target", beam ~= nil, beam and beam:FindFirstChild("GuideBeam") and beam.GuideBeam.Enabled)
		print("guide off", DC:Request("SetSetting", "Guide", false))
		task.wait(0.8)
		print("guide on", DC:Request("SetSetting", "Guide", true))
	end)

	step("hat loot", function()
		local LS = E.sm("LootService")
		assert(LS, "LootService missing")
		local DS = E.sm("DataService")
		local SS = E.sm("StatService")
		local ES = E.sm("EnemyService")
		local DC = E.cm("Controllers.DataController")
		local LC = E.cm("Controllers.LootController")
		local MM = E.cm("UI.MenuManager")
		local Hats = E.shared("Config.Hats")
		local root = player.Character.HumanoidRootPart
		local function count()
			local n = 0
			for _ in pairs(data.Hats) do n += 1 end
			return n
		end
		local function newest()
			return tostring(data.HatSerial)
		end
		local before = count()
		-- a real kill drop: force the 1% roll, kill a camp enemy, walk onto the pillar
		local oldChance = Hats.DropChance
		Hats.DropChance = 1
		local zone = E.sm("ZoneService"):GetZone(player)
		local target
		for _, enemy in ipairs(ES.ByZone[zone.Id] or {}) do
			if not enemy.Dead and not enemy.Def.Static then
				target = enemy
				break
			end
		end
		assert(target, "no enemy to kill for a hat drop")
		ES:Damage(target, player, target.Health + 1, root.Position)
		Hats.DropChance = oldChance
		task.wait(0.3)
		local seen = 0
		local dropPos
		for _, drop in pairs(LC:Drops()) do
			seen += 1
			dropPos = drop.Position
		end
		assert(seen >= 1 and dropPos, "client never saw the kill drop")
		local pillar = E.Workspace:FindFirstChild("HatDrops")
		print("hat drop on the ground:", seen, "pillar parts", pillar and #pillar:GetDescendants() or 0)
		E.sm("ZoneService"):MarkTeleported(player)
		root.CFrame = CFrame.new(dropPos + Vector3.new(1, 3, 0))
		task.wait(0.8)
		assert(count() == before + 1, "walking onto the drop didn't pick it up (hats " .. count() .. ")")
		-- forced drops of every rarity (the admin command's path), picked up by walking over each
		local admin = E.sm("AdminService")
		for _, rarity in ipairs({ "Common", "Magic", "Rare", "Legendary", "Mythic" }) do
			local ok, msg = LS:AdminDrop(player, rarity)
			assert(ok, "AdminDrop " .. rarity .. ": " .. tostring(msg))
			task.wait(0.2)
			for _, drop in pairs(LC:Drops()) do
				E.sm("ZoneService"):MarkTeleported(player)
				root.CFrame = CFrame.new(drop.Position + Vector3.new(0, 3, 1))
			end
			task.wait(0.6)
			print(msg)
		end
		assert(count() == before + 6, "not every forced drop was collected: " .. count())
		local ok, msg = admin:Run(player, "DropHat", player.UserId, "leg")
		print("admin DropHat:", ok, msg)
		-- auto-collect after Hats.AutoCollect seconds, even standing still far away
		E.sm("ZoneService"):MarkTeleported(player)
		root.CFrame = root.CFrame + Vector3.new(0, 0, 40)
		task.wait(Hats.AutoCollect + 0.8)
		assert(count() == before + 7, "the admin drop was not auto-collected")
		for uid, hat in pairs(data.Hats) do
			assert(Hats.Valid(hat), "bad hat record " .. uid)
			print("  hat", uid, hat.R, hat.Id, "iLvl", hat.L, "affixes", #hat.A, "proc", hat.P and hat.P.S or "-", "|", Hats.Name(hat))
			local want = Hats.Rarity(hat.R).Affixes
			if #hat.A < want[1] or #hat.A > want[2] then
				report("scenario", hat.R .. " hat rolled " .. #hat.A .. " affixes")
			end
			if (hat.R == "Legendary" or hat.R == "Mythic") ~= (hat.P ~= nil) then
				report("scenario", hat.R .. " hat proc mismatch")
			end
		end

		-- equip: damage and regen change on the server and on the client
		local s0 = SS:Get(player)
		local dmg0, regen0, delay0, hp0 = s0.Damage, s0.HealthRegen, s0.RegenDelay, s0.MaxHealth
		LS:AdminDrop(player, "Legendary", "komuso_basket")
		task.wait(Hats.AutoCollect + 0.8)
		local basket = newest()
		assert(data.Hats[basket] and data.Hats[basket].Id == "komuso_basket", "forced basket missing")
		assert(DC:Request("EquipHat", basket), "EquipHat failed")
		task.wait(0.6)
		local s1 = SS:Get(player)
		print(string.format("basket: damage %d -> %d, regen %.3f -> %.3f, delay %.1f -> %.1f, hp %d -> %d", dmg0, s1.Damage, regen0, s1.HealthRegen, delay0, s1.RegenDelay, hp0, s1.MaxHealth))
		assert(s1.HealthRegen >= regen0 + 0.0099, "HealthRegen did not go up with the basket")
		assert(s1.RegenDelay <= delay0 - 0.99, "RegenDelay did not go down with the basket")
		local cs = DC:GetStats()
		assert(math.abs(cs.HealthRegen - s1.HealthRegen) < 1e-6 and cs.Damage == s1.Damage, "client stats differ from the server's")
		local worn = player.Character:FindFirstChild("NinjaHat")
		assert(worn and #worn:GetChildren() > 3 and worn:GetAttribute("HatId") == "komuso_basket", "the hat is not on the character")
		local fit, k = E.shared("Visuals.HatBuilder").Fit(player.Character, player.Character.Head)
		print(string.format("hat fit on the head: crown at (%.2f, %.2f, %.2f) from the head centre, scale %.2f", fit.X, fit.Y, fit.Z, k))
		LS:AdminDrop(player, "Rare", "oni_mask")
		task.wait(Hats.AutoCollect + 0.8)
		local oni = newest()
		DC:Request("EquipHat", oni)
		task.wait(0.6)
		local s2 = SS:Get(player)
		local expect = Hats.Bonus(data.Hats[oni]).Damage or 0
		print(string.format("oni mask: damage %d -> %d (hat +%.1f%%), HUD damage %s", dmg0, s2.Damage, expect * 100, tostring(DC:GetStats().Damage)))
		assert(s2.Damage >= math.floor(dmg0 * (1 + expect)) - 1 and expect >= 0.08, "the Oni Mask didn't raise damage")

		-- proc: a Legendary hat with its chance pushed to 100%, one swing lands
		local legendary
		for uid, hat in pairs(data.Hats) do
			if hat.P then legendary = uid end
		end
		assert(legendary, "no hat with a proc")
		data.Hats[legendary].P.C = 1
		DC:Request("EquipHat", legendary)
		task.wait(0.6)
		local casts = {}
		local SkS = E.sm("SkillService")
		local castAt = SkS.CastAt
		SkS.CastAt = function(self, p, skill, pos, lv)
			local ok2, info = castAt(self, p, skill, pos, lv)
			table.insert(casts, skill .. "=" .. tostring(ok2))
			return ok2, info
		end
		local victim
		for _, enemy in ipairs(ES.ByZone[zone.Id] or {}) do
			if not enemy.Dead then victim = enemy break end
		end
		assert(victim, "no enemy for the proc")
		LS:OnHit(player, { victim })
		LS:OnHit(player, { victim }) -- inside the internal cooldown: must not fire again
		task.wait(0.5)
		SkS.CastAt = castAt
		print("procs fired:", table.concat(casts, " "))
		if #casts ~= 1 or not string.find(casts[1], "=true", 1, true) then
			report("scenario", "expected exactly one successful proc, got " .. #casts)
		end
		data.Hats[legendary].P.C = 0.05

		-- life steal: a Demon Horns hat, hurt, then a kill heals 1%+ of max HP
		LS:AdminDrop(player, "Magic", "demon_horns")
		task.wait(Hats.AutoCollect + 0.8)
		local horns = newest()
		DC:Request("EquipHat", horns)
		task.wait(0.6)
		local hum = player.Character.Humanoid
		hum.Health = hum.MaxHealth * 0.5
		local hp1 = hum.Health
		local steal = SS:Get(player).LifeSteal
		local prey
		for _, enemy in ipairs(ES.ByZone[zone.Id] or {}) do
			if not enemy.Dead then prey = enemy break end
		end
		assert(prey, "no enemy for life steal")
		ES:Damage(prey, player, prey.Health + 1, root.Position)
		print(string.format("life steal %d: health %.0f -> %.0f of %d", steal, hp1, hum.Health, hum.MaxHealth))
		assert(steal >= 1 and hum.Health >= hp1 + hum.MaxHealth * steal / 100 - 1, "life steal did not heal")

		-- the menu: open it, select, lock, press its buttons
		MM:Open("Hats")
		task.wait(0.5)
		local window = E.cm("Controllers.UIController"):Root("Menus"):FindFirstChild("Hats")
		assert(window and window.Visible, "Hats menu didn't open")
		local cards = 0
		for _, d in ipairs(window:GetDescendants()) do
			if d.Name == "Card" then cards += 1 end
		end
		print("hats menu cards", cards)
		assert(cards == count(), "Hats menu shows " .. cards .. " cards for " .. count() .. " hats")
		assert(DC:Request("LockHat", oni), "LockHat failed")
		-- salvage one, then bulk-salvage Commons; locked and equipped hats stay
		local coins0 = data.Coins
		local common
		for uid, hat in pairs(data.Hats) do
			if hat.R == "Common" and uid ~= data.EquippedHat then common = uid end
		end
		assert(common, "no Common hat to salvage")
		local okS, sMsg = DC:Request("SalvageHats", { common })
		print("salvage:", okS, sMsg, "coins", coins0, "->", data.Coins)
		assert(okS and data.Hats[common] == nil and data.Coins > coins0, "salvage failed")
		local okL = DC:Request("SalvageHats", { oni, data.EquippedHat })
		assert(not okL and data.Hats[oni] and data.Hats[data.EquippedHat], "salvaged a locked or equipped hat")
		local root2 = E.cm("Controllers.UIController"):Root("Menus")
		for _, d in ipairs(window:GetDescendants()) do
			if d:IsA("TextButton") and d.Name ~= "Close" and d.Parent and d.Name ~= "Card" then
				E.signalFor(d, "Activated"):Fire()
				task.wait(0.05)
			end
		end
		for _, d in ipairs(root2:GetDescendants()) do
			if d:IsA("TextButton") and d.ZIndex >= 52 then
				E.signalFor(d, "Activated"):Fire() -- confirm dialogs
			end
		end
		task.wait(0.8)
		MM:Close()
		local equipped = data.EquippedHat
		print("hats kept", count(), "equipped", equipped, data.Hats[equipped] and Hats.Name(data.Hats[equipped]))
		assert(data.Hats[oni] and data.Hats[oni].Lock, "the locked hat was lost")
		-- the save must bring them back (checked in the rejoin step)
		local kept = {}
		for uid, hat in pairs(data.Hats) do
			kept[uid] = Hats.Name(hat)
		end
		E.hatsCheck = function(d2) -- later steps (the boss) may add more
			local m = 0
			for _ in pairs(d2.Hats) do m += 1 end
			print("rejoined hats", m, "equipped", d2.EquippedHat, "serial", d2.HatSerial)
			for uid, name in pairs(kept) do
				assert(d2.Hats[uid] and Hats.Name(d2.Hats[uid]) == name, "hat " .. name .. " did not survive the rejoin")
			end
			assert(d2.EquippedHat == equipped and d2.Hats[oni].Lock, "equipped / locked hat lost on rejoin")
		end
	end)

	step("press every button in every menu", function()
		local MM = E.cm("UI.MenuManager")
		local root = E.cm("Controllers.UIController"):Root("Menus")
		local skip = { Close = true }
		for _, name in ipairs({ "Shop", "Inventory", "Pets", "Upgrades", "Areas", "Codes", "Gifts", "Trophies", "Settings", "Egg" }) do
			MM:Open(name, if name == "Egg" then "village_egg" else nil)
			task.wait(0.3)
			local window = root:FindFirstChild(name)
			assert(window, "window " .. name .. " missing")
			local counts = {}
			for _, d in ipairs(window:GetDescendants()) do
				counts[d.ClassName] = (counts[d.ClassName] or 0) + 1
			end
			local parts = {}
			for k, v in pairs(counts) do
				table.insert(parts, k .. "=" .. v)
			end
			print(name, table.concat(parts, " "))
			local pressed = 0
			for pass = 1, 2 do
				for _, d in ipairs(window:GetDescendants()) do
					if d:IsA("TextButton") and not skip[d.Name] and d.Parent then
						E.signalFor(d, "MouseEnter"):Fire()
						E.signalFor(d, "Activated"):Fire()
						pressed += 1
						task.wait(0.03)
					end
				end
				task.wait(0.3)
			end
			-- also press confirm dialogs that popped up
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("TextButton") and d.ZIndex >= 52 then
					E.signalFor(d, "Activated"):Fire()
				end
			end
			local n = 0
			for _ in pairs(data.Pets) do n += 1 end
			print(name, "pressed", pressed, "| pets owned", n, "equipped", #data.EquippedPets)
			task.wait(0.8) -- let the rate limiter refill
		end
		MM:Close()
	end)

	step("rebirth + upgrades", function()
		local DC = E.cm("Controllers.DataController")
		print("preview", DC:Request("RebirthPreview"))
		print("rebirth", DC:Request("Rebirth"))
		task.wait(5)
		print("rebirths", data.Rebirths, "shards", data.Shards, "level", data.Level, "tier", data.Tier)
		print("upgrade", DC:Request("BuyUpgrade", "Damage"))
		print("autoswing", DC:Request("BuyUtility", "auto_swing"))
		print("autoswing on", DC:Request("SetSetting", "AutoSwing", true))
		E.cm("UI.MenuManager"):Open("Upgrades")
		task.wait(0.5)
		E.cm("UI.MenuManager"):Open("Rebirth")
		task.wait(0.5)
		E.cm("UI.MenuManager"):Close()
	end)

	step("notifications", function()
		local NC = E.cm("Controllers.NotificationController")
		local BS = E.sm("BossService")
		local Zones = E.shared("Config.Zones")
		local seen = { Chat = {}, Side = {}, Banner = {} }
		local originals = {}
		for _, name in ipairs({ "Chat", "Side", "Banner" }) do
			originals[name] = NC[name]
			NC[name] = function(self, text, ...)
				table.insert(seen[name], text)
				return originals[name](self, text, ...)
			end
		end
		-- a boss in another area: no banner here
		local far = Zones.Get("bamboo")
		local active = BS.Active[far.Id]
		if not active then
			BS:SpawnBoss(far)
		end
		task.wait(0.5)
		print("boss spawned elsewhere: banners", #seen.Banner)
		if #seen.Banner > 0 and not active then
			report("scenario", "a boss in another area showed a banner here")
		end
		-- defeating it: a red line in the chat
		local boss = BS.Active[far.Id]
		if boss then
			E.sm("EnemyService"):Kill(boss, player)
		end
		task.wait(0.5)
		print("boss defeated: chat lines", #seen.Chat, seen.Chat[1])
		if #seen.Chat == 0 then
			report("scenario", "a boss kill wrote nothing in the chat")
		end
		-- a drop: a side note, not a callout
		local Hats = E.shared("Config.Hats")
		local root = player.Character.HumanoidRootPart
		local id = E.sm("LootService"):Drop(player, root.Position + Vector3.new(2, -2.5, 0), Hats.Roll(1, 10, 0, false, nil, "Legendary"))
		task.wait(0.3)
		E.cm("Controllers.DataController"):Request("PickupHat", id)
		task.wait(0.5)
		local notes = player.PlayerGui:FindFirstChild("SideNotes", true)
		print("hat picked up: side notes", #seen.Side, seen.Side[1], "| on screen", notes and #notes:GetChildren())
		if #seen.Side == 0 then
			report("scenario", "a hat pickup showed no side note")
		end
		for name, fn in pairs(originals) do
			NC[name] = fn
		end
	end)

	step("boss", function()
		local BS = E.sm("BossService")
		local Zones = E.shared("Config.Zones")
		local zone = Zones.Get("village")
		local pos = Zones.WorldPosition(zone, zone.BossOffset)
		E.sm("ZoneService"):MarkTeleported(player)
		player.Character.HumanoidRootPart.CFrame = CFrame.new(pos + Vector3.new(0, 3, 10))
		if not BS.Active.village then
			BS:SpawnBoss(zone)
		end
		task.wait(0.5)
		local boss = BS.Active.village
		assert(boss, "boss did not spawn")
		-- let the AI run its attacks for a while with the player in the arena
		local CC = E.cm("Controllers.CombatController")
		local PS = E.sm("ProgressionService")
		PS:AddXP(player, 50000)
		local t0 = os.clock()
		while os.clock() - t0 < 16 and BS.Active.village do
			local b = BS.Active.village
			if b and b.Root then
				player.Character.HumanoidRootPart.CFrame = CFrame.lookAt(b.Root.Position + Vector3.new(0, 0, 5), b.Root.Position)
			end
			CC:Swing()
			task.wait(0.3)
		end
		print("boss alive:", BS.Active.village ~= nil, "boss kills", data.Lifetime.BossKills, "player hp", player.Character.Humanoid.Health)
	end)

	step("death + respawn", function()
		player.Character.Humanoid:TakeDamage(1e9)
		task.wait(0.5)
		player:LoadCharacter()
		task.wait(2)
		print("respawned; katana?", player.Character:FindFirstChild("EquippedKatana") ~= nil, "outfit?", player.Character:FindFirstChild("NinjaOutfit") ~= nil)
	end)

	step("leave + save", function()
		data.Daily.Day -= 1 -- pretend the last login was yesterday: rejoin should continue the streak
		E.signalFor(E.PlayersService, "PlayerRemoving"):Fire(player)
		task.wait(2)
		for name, store in pairs(E.stores) do
			for key, v in pairs(store) do
				print("store", name, key, "Level", v.Level, "Rebirths", v.Rebirths)
			end
		end
	end)

	step("rejoin loads the save", function()
		local p2 = E.wrap(E.RInstance.new("Player"))
		p2.Name = "TestNinja"
		p2.UserId = 12345
		E.wrap(E.RInstance.new("PlayerGui")).Parent = p2
		p2.Parent = E.PlayersService
		E.players[1] = p2
		E.signalFor(E.PlayersService, "PlayerAdded"):Fire(p2)
		task.wait(2)
		local d2 = E.sm("DataService"):Get(p2)
		assert(d2, "rejoin: data not loaded (session lock not released?)")
		local n = 0 for _ in pairs(d2.Pets) do n += 1 end print("rejoined: level", d2.Level, "rebirths", d2.Rebirths, "owned pets", n, "equipped", #d2.EquippedPets)
		assert(d2.Rebirths == 1, "rejoin lost rebirths")
		print("rejoined daily streak", d2.Daily.Streak, "trophies claimed", d2.Achievements.level1)
		assert(d2.Daily.Streak == 2, "daily streak did not continue")
		if E.hatsCheck then
			E.hatsCheck(d2)
		end
		-- server shutdown path
		for _, fn in ipairs(E.bindToClose) do
			fn()
		end
		print("BindToClose ran", #E.bindToClose)
	end)

	-- ONLY=spear,combat runs just those steps (boot always runs)
	local only = {}
	for name in string.gmatch(process.env.ONLY or "", "[^,]+") do
		only[name] = true
	end
	for _, s in ipairs(steps) do
		if next(only) and s[1] ~= "boot" and not only[s[1]] then
			continue
		end
		print("\27[36m== " .. s[1] .. " ==\27[0m")
		freshStamina()
		local ok, err = xpcall(s[2], E.tb)
		if not ok then
			report("STEP " .. s[1], err)
		end
	end
end
