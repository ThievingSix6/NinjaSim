--[[
	TokenController: draws this player's combat tokens (TokenService, Config/Tokens).
	A token is a glowing spinning coin with its icon floating over it; it drops in,
	bobs, blinks before it fades, and bursts with a chime and a little text when you
	run through it. The buff bar (bottom right, over the multipliers) shows each
	buff's stacks and a bar for the time left.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Tokens = require(Shared.Config.Tokens)

local TokenController = {}

local controllers
local folder: Folder? = nil
type Visual = { Model: Model, Disc: BasePart, Rim: BasePart, Base: Vector3, Born: number, Expires: number, Spin: number, Rare: boolean }
local visuals: { [number]: Visual } = {}
local buffBar: Frame? = nil
local buffs: { { Kind: string, Stacks: number, Ends: number, Duration: number } } = {}
local buffCells: { [string]: { Frame: Frame, Count: TextLabel, Fill: Frame } } = {}

function TokenController:Count(): number
	local n = 0
	for _ in pairs(visuals) do
		n += 1
	end
	return n
end

local function getFolder(): Folder
	if not folder or not folder.Parent then
		local f = Instance.new("Folder")
		f.Name = "ClientTokens"
		f.Parent = workspace
		folder = f
	end
	return folder :: Folder
end

local function part(parent: Instance, size: Vector3, color: Color3, material: Enum.Material): BasePart
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = size
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function spawnToken(payload)
	local def = Tokens.Get(payload.Kind)
	if not def or typeof(payload.Position) ~= "Vector3" then
		return
	end
	local model = Instance.new("Model")
	model.Name = "Token" .. payload.Id
	local size = if def.Rare then 4.2 else 3.4
	local rim = part(model, Vector3.new(0.45, size + 0.5, size + 0.5), def.Color:Lerp(Color3.new(0, 0, 0), 0.45), Enum.Material.SmoothPlastic)
	local disc = part(model, Vector3.new(0.55, size, size), def.Color, Enum.Material.Neon)
	disc.Transparency = 0.1
	local light = Instance.new("PointLight")
	light.Color = def.Color
	light.Range = if def.Rare then 14 else 9
	light.Brightness = if def.Rare then 2.5 else 1.6
	light.Parent = disc
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(2.6, 2.6)
	gui.StudsOffset = Vector3.new(0, 0, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 140
	gui.Adornee = disc
	local icon = Instance.new("TextLabel")
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromScale(1, 1)
	icon.Text = def.Icon
	icon.TextScaled = true
	icon.Font = Enum.Font.GothamBold
	icon.Parent = gui
	gui.Parent = disc
	if def.Rare then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkle.Color = ColorSequence.new(def.Color)
		sparkle.LightEmission = 1
		sparkle.Size = NumberSequence.new(0.6, 0)
		sparkle.Lifetime = NumberRange.new(0.6, 1)
		sparkle.Speed = NumberRange.new(1, 3)
		sparkle.Rate = 14
		sparkle.Parent = disc
	end
	model.Parent = getFolder()
	local now = os.clock()
	visuals[payload.Id] = {
		Model = model, Disc = disc, Rim = rim, Base = payload.Position, Born = now,
		Expires = now + (payload.Life or 9), Spin = math.random() * math.pi * 2, Rare = def.Rare == true,
	}
	controllers.SoundController:Play("Coin", 0.5, if def.Rare then 0.9 else 1.6)
end

local function removeVisual(id: number, collected: boolean, payload)
	local v = visuals[id]
	if not v then
		return
	end
	visuals[id] = nil
	local def = Tokens.Get(payload and payload.Kind or "")
	if collected and def then
		local pos = v.Disc.Position
		controllers.EffectsController:Burst(pos, "Sparkle", if def.Rare then 30 else 14, { Color = ColorSequence.new(def.Color) })
		controllers.SoundController:Play("Coin", 0.9, if def.Rare then 1.1 else 2.2)
		if def.Rare then
			controllers.SoundController:Play("TierUp", 0.5, 1.4)
		end
		local camera = workspace.CurrentCamera
		local screen, onScreen = camera:WorldToViewportPoint(pos + Vector3.new(0, 2.5, 0))
		local scale = controllers.UIController.Scale
		local at = if onScreen then Vector2.new(screen.X, screen.Y) / scale else Vector2.new(640, 340)
		controllers.EffectsController:FloatText(def.Icon .. " " .. tostring(payload.Text or def.Name), def.Color, at, if def.Rare then 30 else 22)
		-- fly up and shrink away
		for _, p in ipairs({ v.Disc, v.Rim }) do
			TweenService:Create(p, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Size = p.Size * 0.2, Transparency = 1, CFrame = p.CFrame + Vector3.new(0, 3, 0),
			}):Play()
		end
		task.delay(0.3, function()
			v.Model:Destroy()
		end)
	else
		for _, p in ipairs({ v.Disc, v.Rim }) do
			TweenService:Create(p, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		end
		task.delay(0.45, function()
			v.Model:Destroy()
		end)
	end
end

-- ===== the buff bar =====
local function rebuildBuffBar()
	local Kit, Theme = controllers.Kit, controllers.Theme
	if not buffBar then
		local root = controllers.UIController:Root("HUD")
		local bar = Kit.New("Frame", {
			Name = "TokenBuffs", BackgroundTransparency = 1, Size = UDim2.fromOffset(420, 62),
			Position = UDim2.new(1, -24, 1, -150), AnchorPoint = Vector2.new(1, 1), Parent = root,
		})
		Kit.List(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Bottom).Parent = bar
		buffBar = bar
	end
	local keep = {}
	for i, b in ipairs(buffs) do
		keep[b.Kind] = true
		local cell = buffCells[b.Kind]
		local def = Tokens.Get(b.Kind)
		if not cell then
			local frame = Kit.Panel({ Size = UDim2.fromOffset(56, 56), Color = Theme.Bg, Transparency = 0.25, StrokeColor = def.Color, StrokeThickness = 2.5, Radius = 10, Parent = buffBar })
			Kit.Label({ Text = def.Icon, TextSize = 28, XAlign = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 1, -10), Stroke = false, Parent = frame })
			local count = Kit.Label({ Text = "", Font = Theme.FontNumber, TextSize = 16, XAlign = Enum.TextXAlignment.Right, Size = UDim2.new(1, -4, 0, 18), Position = UDim2.new(0, 0, 1, -28), StrokeThickness = 2, Parent = frame })
			local back = Kit.New("Frame", { BackgroundColor3 = Theme.Ink, Size = UDim2.new(1, -10, 0, 5), Position = UDim2.new(0, 5, 1, -9), Parent = frame })
			local fill = Kit.New("Frame", { BackgroundColor3 = def.Color, Size = UDim2.fromScale(1, 1), Parent = back })
			cell = { Frame = frame, Count = count, Fill = fill }
			buffCells[b.Kind] = cell
		end
		cell.Frame.LayoutOrder = i
		cell.Count.Text = "x" .. b.Stacks
	end
	for kind, cell in pairs(buffCells) do
		if not keep[kind] then
			cell.Frame:Destroy()
			buffCells[kind] = nil
		end
	end
end

local function onEvent(payload)
	if payload.Type == "Spawn" then
		spawnToken(payload)
	elseif payload.Type == "Collect" then
		removeVisual(payload.Id, true, payload)
	elseif payload.Type == "Expire" then
		removeVisual(payload.Id, false, nil)
	elseif payload.Type == "Buffs" then
		local now = os.clock()
		buffs = {}
		for _, b in ipairs(payload.List or {}) do
			table.insert(buffs, { Kind = b.Kind, Stacks = b.Stacks, Ends = now + (b.Left or 0), Duration = b.Duration or 15 })
		end
		table.sort(buffs, function(a, b)
			return (table.find(Tokens.Order, a.Kind) or 0) < (table.find(Tokens.Order, b.Kind) or 0)
		end)
		rebuildBuffBar()
	end
end

function TokenController:Start(c)
	controllers = c
	Net.Event("Token").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		local ok, err = pcall(onEvent, payload)
		if not ok then
			warn("[TokenController] " .. tostring(err))
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		for _, v in pairs(visuals) do
			v.Spin += dt * (if v.Rare then 3.2 else 2.2)
			local age = now - v.Born
			local drop = math.max(0, 1 - age / 0.35)
			local y = 0.35 * math.sin(age * 3) + drop * drop * 5
			local cf = CFrame.new(v.Base + Vector3.new(0, y, 0)) * CFrame.Angles(0, v.Spin, 0)
			v.Disc.CFrame = cf
			v.Rim.CFrame = cf
			-- blink before fading
			local left = v.Expires - now
			if left < Tokens.BlinkFor then
				local on = math.floor(now * (if left < 0.8 then 12 else 6)) % 2 == 0
				v.Disc.Transparency = if on then 0.1 else 0.7
			end
		end
		if #buffs > 0 then
			local changed = false
			for i = #buffs, 1, -1 do
				local b = buffs[i]
				local left = b.Ends - now
				if left <= 0 then
					table.remove(buffs, i)
					changed = true
				else
					local cell = buffCells[b.Kind]
					if cell then
						cell.Fill.Size = UDim2.fromScale(math.clamp(left / b.Duration, 0, 1), 1)
					end
				end
			end
			if changed then
				rebuildBuffBar()
			end
		end
	end)
end

return TokenController
