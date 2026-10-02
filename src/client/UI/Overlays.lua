--[[
	Overlays: the big celebratory moments.
	  Level up        quick pop + burst (never blocks)
	  Tier unlocked   letterbox cinematic, new title, katana reveal
	  Rebirth         white-out, spiral, shards + bonus summary
	  Egg hatch       egg wobbles, cracks, pet reveal with rarity rays (x1 or x3)
	  Reward          code rewards and rare boss drops
	Big overlays queue so they never stack on top of each other.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Tiers = require(Shared.Config.Tiers)
local Katanas = require(Shared.Config.Katanas)
local Pets = require(Shared.Config.Pets)
local Rarity = require(Shared.Config.Rarity)
local Mutations = require(Shared.Config.Mutations)
local Format = require(Shared.Util.Format)

local Overlays = {}

local controllers, Kit, Theme, Common
local root: Frame
local queue = {}
local running = false

local function enqueue(fn)
	table.insert(queue, fn)
	if running then
		return
	end
	running = true
	task.spawn(function()
		while #queue > 0 do
			local nextFn = table.remove(queue, 1)
			local ok, err = pcall(nextFn)
			if not ok then
				warn("[Overlays] " .. tostring(err))
			end
		end
		running = false
	end)
end

-- Full-screen click catcher; returns frame and a function that waits for click or timeout.
local function backdrop(transparency: number)
	local frame = Kit.New("TextButton", {
		Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1), ZIndex = 20, Parent = root,
	})
	Kit.Tween(frame, { BackgroundTransparency = transparency }, 0.25)
	local clicked = false
	frame.Activated:Connect(function()
		clicked = true
	end)
	local function waitFor(seconds: number)
		local t = 0
		while t < seconds and not clicked do
			t += task.wait()
		end
	end
	return frame, waitFor
end

local function fadeOut(frame: GuiObject, duration: number)
	for _, d in ipairs(frame:GetDescendants()) do
		if d:IsA("TextLabel") then
			Kit.Tween(d, { TextTransparency = 1 }, duration)
		elseif d:IsA("UIStroke") then
			Kit.Tween(d, { Transparency = 1 }, duration)
		elseif d:IsA("ViewportFrame") then
			Kit.Tween(d, { ImageTransparency = 1 }, duration)
		elseif d:IsA("Frame") and d.BackgroundTransparency < 1 then
			Kit.Tween(d, { BackgroundTransparency = 1 }, duration)
		end
	end
	Kit.Tween(frame, { BackgroundTransparency = 1 }, duration)
	task.wait(duration)
	frame:Destroy()
end

-- Rotating light rays behind a reveal.
local function rays(parent: Instance, color: Color3, size: number, zIndex: number): Frame
	local holder = Kit.New("Frame", {
		BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), ZIndex = zIndex, Parent = parent,
	})
	for i = 0, 11 do
		local ray = Kit.New("Frame", {
			BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.new(0, 16, 1, 0), AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5), Rotation = i * 15, ZIndex = zIndex, Parent = holder,
		})
		Kit.New("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 0.55),
				NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(0.65, 0.55), NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = ray,
		})
	end
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		if not holder.Parent then
			conn:Disconnect()
			return
		end
		holder.Rotation += dt * 25
	end)
	return holder
end

local function bigText(parent: Instance, text: string, color: Color3, y: number, size: number, zIndex: number): TextLabel
	local label = Kit.Label({
		Text = text, Font = Theme.FontBig, TextSize = size, Color = color, XAlign = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, size + 10), Position = UDim2.new(0, 0, 0.5, y), AnchorPoint = Vector2.new(0, 0.5),
		StrokeThickness = math.clamp(size / 11, 2.5, 6), ZIndex = zIndex, Parent = parent,
	})
	local scale = Kit.New("UIScale", { Scale = 0.2, Parent = label })
	Kit.Tween(scale, { Scale = 1 }, 0.4, Enum.EasingStyle.Back)
	return label
end

-- ===== Level up =====
local function onLevelUp(level: number, gained: number)
	controllers.SoundController:Play("LevelUp")
	controllers.EffectsController:CharacterBurst(Theme.XP, false)
	local label = Kit.Label({
		Text = if gained > 1 then "LEVEL UP x" .. gained .. "!" else "LEVEL UP!", Font = Theme.FontBig, TextSize = 56, Color = Theme.Gold,
		XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 62), Position = UDim2.fromScale(0, 0.26), StrokeThickness = 5, ZIndex = 10, Parent = root,
	})
	local sub = Kit.Label({
		Text = "Level " .. level, Font = Theme.FontTitle, TextSize = 30, XAlign = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 34), Position = UDim2.new(0, 0, 0.26, 62), StrokeThickness = 3.5, ZIndex = 10, Parent = root,
	})
	local scale = Kit.New("UIScale", { Scale = 0.3, Parent = label })
	Kit.Tween(scale, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)
	task.delay(1.4, function()
		Kit.Tween(label, { TextTransparency = 1, Position = UDim2.fromScale(0, 0.2) }, 0.5)
		Kit.Tween(sub, { TextTransparency = 1 }, 0.5)
		for _, s in ipairs({ label:FindFirstChildOfClass("UIStroke"), sub:FindFirstChildOfClass("UIStroke") }) do
			Kit.Tween(s, { Transparency = 1 }, 0.5)
		end
		task.wait(0.55)
		label:Destroy()
		sub:Destroy()
	end)
end

-- ===== Tier unlocked =====
local function tierCinematic(tierIndex: number)
	local tier = Tiers.Get(tierIndex)
	local katana = Katanas.Get(tier.Katana)
	controllers.SoundController:Play("TierUp")
	controllers.CameraController:Cinematic(3.6)
	controllers.CameraController:Shake(0.35)
	controllers.EffectsController:Flash(tier.Color, 0.6)
	controllers.EffectsController:CharacterBurst(tier.Color, true)

	local frame, waitFor = backdrop(1)
	-- letterbox bars
	local bars = {}
	for i, y in ipairs({ 0, 1 }) do
		local bar = Kit.New("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 0),
			Position = UDim2.fromScale(0, y), AnchorPoint = Vector2.new(0, y), ZIndex = 21, Parent = frame,
		})
		Kit.Tween(bar, { Size = UDim2.new(1, 0, 0.13, 0) }, 0.4)
		bars[i] = bar
	end
	task.wait(0.5)
	Kit.Label({
		Text = "NEW NINJA RANK", Font = Theme.FontHeavy, TextSize = 20, Color = Theme.SubText, XAlign = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 0.2, 0), ZIndex = 22, Parent = frame,
	})
	bigText(frame, string.upper(tier.Name), tier.Color:Lerp(Color3.new(1, 1, 1), 0.2), -190, 64, 22)
	-- the rank's two elemental skills (Config/ElementSkills, granted by SkillService)
	local tierSkills, element = require(Shared.Config.Skills).ForTier(tierIndex)
	if element and #tierSkills > 0 then
		local names = {}
		for _, def in ipairs(tierSkills) do
			table.insert(names, def.Name)
		end
		bigText(frame, element.Name .. " skills: " .. table.concat(names, " & "), element.Color:Lerp(Color3.new(1, 1, 1), 0.35), -128, 28, 22)
	end
	-- katana reveal card at the bottom
	task.wait(0.6)
	if katana then
		local card = Kit.Panel({
			Size = UDim2.fromOffset(460, 150), Position = UDim2.new(0.5, 0, 0.87, -12), AnchorPoint = Vector2.new(0.5, 1),
			Paint = Kit.RarityPaint(katana.Rarity), StrokeThickness = 4, Radius = 16, ZIndex = 22, Parent = frame,
		})
		local cardScale = Kit.New("UIScale", { Scale = 0.5, Parent = card })
		Kit.Tween(cardScale, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)
		local model = Common.KatanaModel(katana.Id)
		if model then
			local vp = Kit.Viewport(card, model, { Spin = true, Size = UDim2.fromOffset(150, 150), ZIndex = 23 })
			vp.ZIndex = 23
		end
		Kit.Label({ Text = "Katana unlocked", Font = Theme.FontBold, TextSize = 17, Color = Theme.Text, Size = UDim2.new(1, -170, 0, 20), Position = UDim2.fromOffset(160, 22), ZIndex = 23, Parent = card })
		Kit.Label({ Text = katana.Name, Font = Theme.FontBig, TextSize = 32, Color = Theme.Text, Size = UDim2.new(1, -170, 0, 36), Position = UDim2.fromOffset(160, 44), StrokeThickness = 4, ZIndex = 23, Parent = card })
		Kit.Label({
			Text = Format.Mult(katana.Mult) .. " damage  •  +" .. math.floor((tier.HealthMult - 1) * 100 + 0.5) .. "% health  •  +" .. tier.SpeedBonus .. " speed",
			Font = Theme.FontNumber, TextSize = 15, Color = Theme.Text, Scaled = true, MaxTextSize = 15, Size = UDim2.new(1, -176, 0, 22), Position = UDim2.fromOffset(160, 92), ZIndex = 23, StrokeThickness = 2, Parent = card,
		})
	end
	waitFor(3.4)
	for _, bar in ipairs(bars) do
		Kit.Tween(bar, { Size = UDim2.new(1, 0, 0, 0) }, 0.35)
	end
	fadeOut(frame, 0.4)
end

-- ===== Rebirth =====
local function rebirthCinematic(info)
	controllers.SoundController:Play("Rebirth")
	controllers.EffectsController:Flash(Color3.new(1, 1, 1), 1.2)
	controllers.CameraController:Shake(0.4)
	local accent = Color3.fromRGB(150, 110, 255)
	local frame, waitFor = backdrop(0.35)
	rays(frame, accent, 900, 21)
	bigText(frame, "REBIRTH " .. info.Rebirths, accent:Lerp(Color3.new(1, 1, 1), 0.3), -70, 72, 22)
	task.wait(0.4)
	bigText(frame, "+" .. Format.Commas(info.Shards) .. " Spirit Shards", Theme.Shard, 10, 34, 22)
	task.wait(0.3)
	bigText(frame, "Permanent bonus " .. Format.Percent(1 + info.Bonus) .. " XP, Coins & Damage", Theme.Green, 56, 24, 22)
	task.delay(0.8, function()
		controllers.EffectsController:CharacterBurst(accent, true)
	end)
	waitFor(3.6)
	fadeOut(frame, 0.4)
end

-- ===== Egg hatch =====
local function eggModel(egg): Model
	local model = Instance.new("Model")
	local shell = Instance.new("Part")
	shell.Name = "Shell"
	shell.Shape = Enum.PartType.Ball
	shell.Size = Vector3.new(3, 3, 3)
	shell.Color = egg.Color
	shell.Material = Enum.Material.SmoothPlastic
	shell.Anchored = true
	shell.Parent = model
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.28, 1)
	mesh.Parent = shell
	model.PrimaryPart = shell
	local rng = Random.new(#egg.Id)
	for _ = 1, 7 do
		local spot = Instance.new("Part")
		spot.Shape = Enum.PartType.Ball
		local s = rng:NextNumber(0.5, 0.9)
		spot.Size = Vector3.new(s, s, s)
		spot.Color = egg.Accent
		spot.Material = if egg.Currency == "Shards" then Enum.Material.Neon else Enum.Material.SmoothPlastic
		spot.Anchored = true
		local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.9, 0.9), rng:NextNumber(-1, 1)).Unit
		spot.Position = Vector3.new(dir.X * 1.42, dir.Y * 1.82, dir.Z * 1.42)
		spot.Parent = model
	end
	return model
end

local function hatchSequence(info)
	local egg = Pets.EggsById[info.Egg]
	if not egg then
		return
	end
	local results = info.Pets
	local count = #results
	local data = controllers.DataController:Get()
	local frame, waitFor = backdrop(0.35)
	local slotWidth = 300
	local startX = -((count - 1) * slotWidth) / 2
	local slots = {}
	for i = 1, count do
		local slot = Kit.New("Frame", {
			BackgroundTransparency = 1, Size = UDim2.fromOffset(280, 380), AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, startX + (i - 1) * slotWidth, 0.5, -20), ZIndex = 21, Parent = frame,
		})
		local model = eggModel(egg)
		local vp = Kit.Viewport(slot, model, { Size = UDim2.fromOffset(240, 240), Position = UDim2.fromScale(0.5, 0.42), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 22, Zoom = 1.25 })
		local vpScale = Kit.New("UIScale", { Scale = 0.2, Parent = vp })
		Kit.Tween(vpScale, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)
		slots[i] = { Slot = slot, Viewport = vp, Model = model, Scale = vpScale }
	end
	task.wait(0.4)
	-- three wobbles of increasing strength, then a frantic shake
	for round = 1, 3 do
		controllers.SoundController:Play("EggShake", 0.6 + round * 0.15, 0.9 + round * 0.1)
		local t0 = os.clock()
		while os.clock() - t0 < 0.32 do
			local k = (os.clock() - t0) / 0.32
			local angle = math.sin(k * math.pi * 4) * (0.15 + round * 0.1) * (1 - k)
			for _, s in ipairs(slots) do
				s.Model:PivotTo(CFrame.Angles(0, 0, angle))
			end
			RunService.RenderStepped:Wait()
		end
		task.wait(0.22 - round * 0.04)
	end
	local t0 = os.clock()
	while os.clock() - t0 < 0.45 do
		local k = (os.clock() - t0) / 0.45
		for _, s in ipairs(slots) do
			s.Model:PivotTo(CFrame.Angles(math.sin(os.clock() * 60) * 0.12 * k, 0, math.sin(os.clock() * 70) * 0.25 * k))
			s.Scale.Scale = 1 + k * 0.15
		end
		RunService.RenderStepped:Wait()
	end

	-- crack!
	local best = 1
	local rareMutation = nil -- the rarest mutation that rolled, if any
	for _, r in ipairs(results) do
		local def = Pets.ById[r.Id]
		if def then
			best = math.max(best, Rarity.Index(def.Rarity))
		end
		local m = Mutations.Get(r.Mutation)
		if m and (not rareMutation or m.OneIn > rareMutation.OneIn) then
			rareMutation = m
		end
	end
	local bigMutation = rareMutation and rareMutation.OneIn >= Mutations.RareOneIn
	if bigMutation then
		best = math.max(best, 5)
	end
	controllers.EffectsController:Flash(if rareMutation then rareMutation.Color else Color3.new(1, 1, 1), if best >= 5 then 0.9 else 0.5)
	controllers.SoundController:Play("EggHatch", 1, if best >= 5 then 0.8 else 1)
	controllers.CameraController:Shake(if best >= 5 then 0.5 else 0.2)
	for i, s in ipairs(slots) do
		s.Viewport:Destroy()
		local result = results[i]
		local def = Pets.ById[result.Id]
		if def then
			local color = Rarity.Color(def.Rarity)
			local mutation = Mutations.Get(result.Mutation)
			local glow = Rarity.Info[def.Rarity] and Rarity.Info[def.Rarity].Glow
			if glow or mutation then
				rays(s.Slot, if mutation then mutation.Color else color, 360, 21).Position = UDim2.fromScale(0.5, 0.42)
			end
			local model = Common.PetModel(def.Id, result.Mutation)
			if model then
				local vp = Kit.Viewport(s.Slot, model, { Spin = true, SpinSpeed = 1.2, Size = UDim2.fromOffset(240, 240), Position = UDim2.fromScale(0.5, 0.42), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 22, Zoom = Common.PetZoom(1.1, result.Mutation) })
				local sc = Kit.New("UIScale", { Scale = 0.1, Parent = vp })
				Kit.Tween(sc, { Scale = 1 }, 0.45, Enum.EasingStyle.Back)
			end
			Kit.Label({ Text = Pets.DisplayName(def, result.Mutation), Font = Theme.FontTitle, TextSize = 32, Scaled = true, MaxTextSize = 32, Color = if mutation then mutation.Color else Theme.Text, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 38), Position = UDim2.new(0, 0, 1, -110), StrokeThickness = 2.5, ZIndex = 23, Parent = s.Slot })
			Kit.Label({ Text = string.upper(def.Rarity) .. (if mutation then "  •  " .. Format.Mult(mutation.Mult) .. " STATS" else ""), Font = Theme.FontHeavy, TextSize = 20, Color = color, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 1, -72), StrokeThickness = 2, ZIndex = 23, Parent = s.Slot })
			if mutation then
				-- tilted mutation stamp that slams in over the pet
				local rare = mutation.OneIn >= Mutations.RareOneIn
				local stamp = Kit.Label({
					Text = string.upper(mutation.Name) .. "!", Font = Theme.FontBig, TextSize = if rare then 40 else 30, Color = mutation.Color,
					XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 40, 0, 44), Position = UDim2.new(0, -20, 1, -158),
					StrokeThickness = if rare then 4.5 else 3.5, ZIndex = 24, Parent = s.Slot,
				})
				stamp.Rotation = -7
				local stampScale = Kit.New("UIScale", { Scale = 2.6, Parent = stamp })
				task.delay(0.25, function()
					Kit.Tween(stampScale, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)
				end)
				if mutation.Id == "Rainbow" then
					local hueConn
					hueConn = RunService.RenderStepped:Connect(function()
						if not stamp.Parent then
							hueConn:Disconnect()
							return
						end
						stamp.TextColor3 = Color3.fromHSV((os.clock() * 0.5) % 1, 0.6, 1)
					end)
				end
			end
			local oneIn = Pets.MutatedOneIn(def.Id, result.Mutation)
			if oneIn then
				local odds = Kit.Label({ Text = Common.OddsText(oneIn), Font = Theme.FontBig, TextSize = if oneIn >= 1000 then 30 else 22, Color = color, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 40, 0, 32), Position = UDim2.new(0, -20, 0, -8), StrokeThickness = 3, ZIndex = 24, Parent = s.Slot })
				if oneIn >= 1000 then
					odds.Rotation = -3
					local sc = Kit.New("UIScale", { Scale = 2.2, Parent = odds })
					Kit.Tween(sc, { Scale = 1 }, 0.5, Enum.EasingStyle.Back)
				end
			end
			local lines = Common.BonusLines(Pets.BonusOf(def, result.Mutation))
			local parts = {}
			for _, l in ipairs(lines) do
				table.insert(parts, l[1] .. " " .. l[2])
			end
			Kit.Label({ Text = table.concat(parts, "   "), Font = Theme.FontNumber, TextSize = 15, Color = Theme.Gold, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 1, -44), ZIndex = 23, Parent = s.Slot })
			-- "NEW!" if this is the first of its kind
			local copies = 0
			if data then
				for _, p in pairs(data.Pets) do
					if p.Id == def.Id then
						copies += 1
					end
				end
			end
			if result.Deleted then
				local tag = Kit.Label({ Text = "AUTO-DELETED", Font = Theme.FontHeavy, TextSize = 18, Color = Theme.Red, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 24), StrokeThickness = 2, ZIndex = 24, Parent = s.Slot })
				tag.Rotation = -4
			elseif copies <= 1 then
				local newTag = Kit.Label({ Text = "NEW!", Font = Theme.FontTitle, TextSize = 26, Color = Theme.Gold, XAlign = Enum.TextXAlignment.Center, Size = UDim2.fromOffset(90, 30), Position = UDim2.new(0.5, 70, 0, 30), StrokeThickness = 2, ZIndex = 24, Parent = s.Slot })
				newTag.Rotation = 12
			end
		end
	end
	if best >= 8 then
		controllers.NotificationController:Banner("SECRET PET!", "You beat the odds", Rarity.Color("Secret"), 3)
	elseif bigMutation and rareMutation then
		controllers.NotificationController:Banner(string.upper(rareMutation.Name) .. " MUTATION!", Format.Mult(rareMutation.Mult) .. " stats  •  1 in " .. Format.Commas(rareMutation.OneIn), rareMutation.Color, 3)
		controllers.CameraController:Shake(0.45)
	elseif rareMutation then
		controllers.NotificationController:Toast("✨ " .. rareMutation.Name .. " mutation! " .. Format.Mult(rareMutation.Mult) .. " stats", rareMutation.Color, "Sparkle")
	elseif best >= 5 then
		controllers.NotificationController:Toast("✨ Incredible luck!", Rarity.Color(Rarity.Order[best]))
	end
	waitFor(if best >= 5 then 3.4 else 2.4)
	fadeOut(frame, 0.3)
end

-- ===== Reward popup =====
local function rewardPopup(title: string, text: string, color: Color3?, model: Model?)
	controllers.SoundController:Play("Purchase")
	local accent = color or Theme.Gold
	local frame, waitFor = backdrop(0.5)
	local card = Kit.Panel({
		Size = UDim2.fromOffset(440, if model then 340 else 200), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		Paint = { Theme.Body, Theme.BodyDark }, Stripes = false, StrokeThickness = 4, Radius = 18, ZIndex = 22, Parent = frame,
	})
	Kit.Rays(card, { Size = UDim2.fromOffset(420, 420), Position = UDim2.new(0.5, 0, 0, if model then 140 else 60), ZIndex = 22, Color = accent, Spin = 20, Transparency = 0.5 })
	local scale = Kit.New("UIScale", { Scale = 0.4, Parent = card })
	Kit.Tween(scale, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)
	Kit.Label({ Text = title, Font = Theme.FontBig, TextSize = 40, Color = accent, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 46), Position = UDim2.fromOffset(0, 14), StrokeThickness = 4.5, ZIndex = 23, Parent = card })
	if model then
		Kit.Viewport(card, model, { Spin = true, Size = UDim2.fromOffset(180, 160), Position = UDim2.new(0.5, 0, 0, 64), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 23 })
	end
	Kit.Label({
		Text = text, Font = Theme.FontBold, TextSize = 21, Wrapped = true, XAlign = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, -40, 0, 70), Position = UDim2.new(0, 20, 1, -86), ZIndex = 23, StrokeThickness = 2.5, Parent = card,
	})
	-- confetti
	for _ = 1, 40 do
		local bit = Kit.New("Frame", {
			BackgroundColor3 = Color3.fromHSV(math.random(), 0.7, 1), BorderSizePixel = 0, Size = UDim2.fromOffset(8, 14),
			Position = UDim2.new(0.5, 0, 0.5, 0), Rotation = math.random(0, 360), ZIndex = 24, Parent = frame,
		})
		Kit.Tween(bit, {
			Position = UDim2.new(0.5 + (math.random() - 0.5) * 0.9, 0, 0.5 + (math.random() - 0.3) * 0.9, 0),
			Rotation = math.random(-720, 720), BackgroundTransparency = 1,
		}, 1.4 + math.random() * 0.6, Enum.EasingStyle.Quad)
	end
	waitFor(3)
	fadeOut(frame, 0.3)
end

function Overlays:Start(c)
	controllers = c
	Kit, Theme, Common = c.Kit, c.Theme, c.MenuCommon
	root = c.UIController:Root("Overlay")

	Net.Event("LevelUp").OnClientEvent:Connect(onLevelUp)
	Net.Event("TierUnlocked").OnClientEvent:Connect(function(target: number)
		enqueue(function()
			tierCinematic(target)
		end)
	end)
	Net.Event("Rebirthed").OnClientEvent:Connect(function(info)
		enqueue(function()
			rebirthCinematic(info)
		end)
	end)
	Net.Event("EggHatched").OnClientEvent:Connect(function(info)
		enqueue(function()
			hatchSequence(info)
		end)
	end)
	Net.Event("Reward").OnClientEvent:Connect(function(info)
		enqueue(function()
			rewardPopup(info.Title or "Reward!", info.Text or "", info.Color)
		end)
	end)
	-- rare boss katana drops
	Net.Event("EnemyDied").OnClientEvent:Connect(function(info)
		local drop = info.Rewards and info.Rewards.Drop
		local def = drop and Katanas.Get(drop)
		if def then
			enqueue(function()
				rewardPopup("RARE DROP!", def.Name .. " (" .. Format.Mult(def.Mult) .. ")  is in your Inventory", Rarity.Color(def.Rarity), Common.KatanaModel(def.Id))
			end)
		end
	end)
end

return Overlays
