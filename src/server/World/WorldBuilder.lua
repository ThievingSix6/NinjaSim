--[[
	WorldBuilder: generates the whole map at server start from Config/Zones and
	Config/ZoneLayouts: a smooth-terrain valley per zone (rolling ground, plateaus,
	hills, ponds, a winding road with branches to every camp, cliffs and terraced
	ridges between zones), invisible bounds that follow the cliffs, gates with lock
	barriers, egg stands, boss arenas, spawn pads, zone signs, ambient particles,
	and per-zone decoration and vegetation (ZoneDecor).

	The land's shape is pure math in shared/Landscape (so clients agree with it);
	this file turns it into terrain voxels and props.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Pets = require(Shared.Config.Pets)
local Enemies = require(Shared.Config.Enemies)
local Format = require(Shared.Util.Format)
local Landscape = require(Shared.Landscape)
local Particles = require(Shared.Visuals.Particles)
local Props = require(script.Parent.Props)
local ZoneDecor = require(script.Parent.ZoneDecor)

local WorldBuilder = {}

local rgb = Color3.fromRGB
local UP = CFrame.Angles(0, 0, math.pi / 2)
local ROAD_HALF_WIDTH = Landscape.MainRoadHalfWidth
local CHUNK = 64 -- studs per WriteVoxels call
local VOXEL = 4
local BOTTOM = -12 -- terrain floor below the lowest ground

local terrain = workspace.Terrain

-- Surface material of one terrain column.
local function columnMaterial(theme, alt: Enum.Material?, road: number, s: number, slope: number, wx: number, wz: number): Enum.Material
	if road > 0.5 then
		return theme.Path
	end
	local n = Landscape.Noise(wx / 23, wz / 23, 71)
	if slope > 1.05 + 0.15 * n or (s > 0 and slope > 0.6 + 0.2 * n) then
		return theme.Rock
	end
	if alt and Landscape.Fbm(wx / 70, wz / 70, 77, 2) > 0.18 then
		return alt
	end
	return theme.Ground
end

-- Writes one zone's land as terrain voxels, CHUNK x CHUNK studs at a time, and
-- records each column's height and edge distance in grid (for decor placement).
local function buildTerrain(zone, grid)
	local theme = zone.Theme
	local layout = zone.Layout or {}
	local alt = layout.Alt
	local L = zone.Land
	local c = zone.Center
	terrain:SetMaterialColor(theme.Ground, theme.GroundColor)
	terrain:SetMaterialColor(theme.Path, theme.PathColor)
	terrain:SetMaterialColor(theme.Rock, theme.RockColor)

	local air, water = Enum.Material.Air, Enum.Material.Water
	for x0 = -L.H, L.H - 1, CHUNK do
		for z0 = -L.D, L.D - 1, CHUNK do
			local x1, z1 = math.min(x0 + CHUNK, L.H), math.min(z0 + CHUNK, L.D)
			local nx, nz = (x1 - x0) / VOXEL, (z1 - z0) / VOXEL
			-- heights for the chunk plus a one-column rim (for slopes)
			local region = Landscape.Region(zone, x0 - VOXEL, z0 - VOXEL, x1 + VOXEL, z1 + VOXEL)
			local hs, info = {}, {}
			local lo, hi = math.huge, -math.huge
			for i = 0, nx + 1 do
				local row = {}
				for k = 0, nz + 1 do
					local x, z = x0 + (i - 0.5) * VOXEL, z0 + (k - 0.5) * VOXEL
					local h, road, s, wl = Landscape.Sample(zone, x, z, region)
					row[k] = h
					if i >= 1 and i <= nx and k >= 1 and k <= nz then
						info[i * 1000 + k] = { road, s, wl }
						local gi, gk = (x0 + L.H) / VOXEL + i - 1, (z0 + L.D) / VOXEL + k - 1
						grid.h[gi] = grid.h[gi] or {}
						grid.s[gi] = grid.s[gi] or {}
						grid.h[gi][gk], grid.s[gi][gk] = h, s
						lo = math.min(lo, h)
						hi = math.max(hi, h, wl or -math.huge)
					end
				end
				hs[i] = row
			end
			local y0 = math.min(BOTTOM, math.floor((lo - 8) / VOXEL) * VOXEL)
			local y1 = math.ceil((hi + 1) / VOXEL) * VOXEL
			local ny = (y1 - y0) / VOXEL
			local mats, occs = table.create(nx), table.create(nx)
			for i = 1, nx do
				local mx, ox = table.create(ny), table.create(ny)
				for j = 1, ny do
					mx[j] = table.create(nz, air)
					ox[j] = table.create(nz, 0)
				end
				mats[i], occs[i] = mx, ox
				for k = 1, nz do
					local h = hs[i][k]
					local d = info[i * 1000 + k]
					local slope = math.sqrt((hs[i + 1][k] - hs[i - 1][k]) ^ 2 + (hs[i][k + 1] - hs[i][k - 1]) ^ 2) / (2 * VOXEL)
					local wx, wz = c.X + x0 + (i - 0.5) * VOXEL, c.Z + z0 + (k - 0.5) * VOXEL
					local top = columnMaterial(theme, alt, d[1], d[2], slope, wx, wz)
					local wl = d[3]
					for j = 1, ny do
						local vb = y0 + (j - 1) * VOXEL
						local o = math.clamp((h - vb) / VOXEL, 0, 1)
						-- a voxel only holds one material: a thin bit of pond floor gives way to water
						if o > 0 and not (wl and o < 0.6 and wl > vb + 1) then
							mx[j][k] = if vb + VOXEL > h - 8 then top else theme.Rock
							ox[j][k] = o
						elseif wl and vb < wl then
							mx[j][k] = water
							ox[j][k] = math.clamp((wl - vb) / VOXEL, 0, 1)
						end
					end
				end
			end
			local minCorner = Vector3.new(c.X + x0, y0, c.Z + z0)
			terrain:WriteVoxels(Region3.new(minCorner, minCorner + Vector3.new(nx * VOXEL, ny * VOXEL, nz * VOXEL)), VOXEL, mats, occs)
		end
	end

	-- scenery beyond the ridges
	if zone.Decor == "Volcanic" then
		local volcano = c + Vector3.new(60, -40, L.D + 90)
		terrain:FillBall(volcano, 130, Enum.Material.Basalt)
		terrain:FillBall(volcano + Vector3.new(0, 122, 0), 20, Enum.Material.CrackedLava)
	elseif zone.Decor == "Sky" then
		local rng = Random.new(zone.Index * 31)
		for _ = 1, 8 do
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			local p = c + Vector3.new(rng:NextNumber(-L.H, L.H), rng:NextNumber(80, 130), side * rng:NextNumber(L.D - 30, L.D + 60))
			terrain:FillBall(p, rng:NextNumber(12, 22), Enum.Material.Snow)
			terrain:FillBall(p + Vector3.new(0, -10, 0), rng:NextNumber(8, 14), Enum.Material.Glacier)
		end
	end
end

-- Marching squares over Landscape.BoundField: the zero contour runs part way up
-- the cliffs all around the valley. Contours are chained and simplified into
-- long wall segments; small closed loops (rock outcrops inside the valley) are
-- left climbable.
local function contourPolylines(zone)
	local L = zone.Land
	local cols, rows = math.round(2 * L.H / 12), math.round(2 * L.D / 12)
	local sx, sz = 2 * L.H / cols, 2 * L.D / rows
	local f = {}
	for i = 0, cols do
		local col = {}
		local x = -L.H + i * sx
		local region = Landscape.Region(zone, x - 1, -L.D, x + 1, L.D)
		for k = 0, rows do
			col[k] = Landscape.BoundField(zone, x, -L.D + k * sz, region)
		end
		f[i] = col
	end
	local points: { [string]: Vector2 } = {}
	local links: { [string]: { string } } = {}
	local function edgePoint(id: string, ax: number, az: number, va: number, bx: number, bz: number, vb: number)
		if not points[id] then
			local t = va / (va - vb)
			points[id] = Vector2.new(ax + (bx - ax) * t, az + (bz - az) * t)
		end
		return id
	end
	local function link(a: string, b: string)
		links[a] = links[a] or {}
		links[b] = links[b] or {}
		table.insert(links[a], b)
		table.insert(links[b], a)
	end
	for i = 0, cols - 1 do
		for k = 0, rows - 1 do
			local v = { f[i][k], f[i + 1][k], f[i + 1][k + 1], f[i][k + 1] }
			local inside = {}
			local any, all = false, true
			for j = 1, 4 do
				inside[j] = v[j] < 0
				any = any or inside[j]
				all = all and inside[j]
			end
			if any and not all then
				local x0, z0 = -L.H + i * sx, -L.D + k * sz
				local x1, z1 = x0 + sx, z0 + sz
				-- edges: 1 bottom (c1-c2), 2 right (c2-c3), 3 top (c4-c3), 4 left (c1-c4)
				local e = {}
				if inside[1] ~= inside[2] then
					e[1] = edgePoint("h" .. i .. "," .. k, x0, z0, v[1], x1, z0, v[2])
				end
				if inside[2] ~= inside[3] then
					e[2] = edgePoint("v" .. (i + 1) .. "," .. k, x1, z0, v[2], x1, z1, v[3])
				end
				if inside[4] ~= inside[3] then
					e[3] = edgePoint("h" .. i .. "," .. (k + 1), x0, z1, v[4], x1, z1, v[3])
				end
				if inside[1] ~= inside[4] then
					e[4] = edgePoint("v" .. i .. "," .. k, x0, z0, v[1], x0, z1, v[4])
				end
				if e[1] and e[2] and e[3] and e[4] then
					-- saddle: cut off the two corners that differ from the centre
					local centre = (v[1] + v[2] + v[3] + v[4]) / 4 < 0
					local corners = { { 4, 1 }, { 1, 2 }, { 2, 3 }, { 3, 4 } }
					for j = 1, 4 do
						if inside[j] ~= centre then
							link(e[corners[j][1]], e[corners[j][2]])
						end
					end
				else
					local found = {}
					for j = 1, 4 do
						if e[j] then
							table.insert(found, e[j])
						end
					end
					if #found == 2 then
						link(found[1], found[2])
					end
				end
			end
		end
	end

	-- chain the segments: open chains first (they end on the strip border), then loops
	local used: { [string]: boolean } = {}
	local function key(a: string, b: string): string
		return if a < b then a .. "|" .. b else b .. "|" .. a
	end
	local lines = {}
	local function walk(startId: string)
		local line = { points[startId] }
		local current = startId
		while true do
			local nextId
			for _, other in ipairs(links[current]) do
				if not used[key(current, other)] then
					nextId = other
					break
				end
			end
			if not nextId then
				break
			end
			used[key(current, nextId)] = true
			table.insert(line, points[nextId])
			current = nextId
		end
		return line, current == startId
	end
	for id, list in pairs(links) do
		if #list == 1 and not used[key(id, list[1])] then
			table.insert(lines, (walk(id)))
		end
	end
	for id, list in pairs(links) do
		for _, other in ipairs(list) do
			if not used[key(id, other)] then
				local line, closed = walk(id)
				local length = 0
				for j = 2, #line do
					length += (line[j] - line[j - 1]).Magnitude
				end
				if not closed or length > 420 then
					table.insert(lines, line)
				end
			end
		end
	end
	return lines
end

-- Douglas-Peucker simplification.
local function simplify(line: { Vector2 }, tolerance: number): { Vector2 }
	if #line < 3 then
		return line
	end
	local a, b = line[1], line[#line]
	local ab = b - a
	local len = math.max(ab.Magnitude, 1e-6)
	local worst, at = 0, 0
	for i = 2, #line - 1 do
		local p = line[i]
		local d = if len < 1e-3 then (p - a).Magnitude else math.abs((p - a).X * ab.Y - (p - a).Y * ab.X) / len
		if d > worst then
			worst, at = d, i
		end
	end
	if worst <= tolerance then
		return { a, b }
	end
	local left = simplify(table.move(line, 1, at, 1, {}), tolerance)
	local right = simplify(table.move(line, at, #line, 1, {}), tolerance)
	table.remove(left)
	return table.move(right, 1, #right, #left + 1, left)
end

local function invisibleWall(parent: Instance, cf: CFrame, size: Vector3)
	local wall = Props.Part(parent, size, cf, Color3.new(), Enum.Material.SmoothPlastic)
	wall.Transparency = 1
	wall.CanQuery = false
	wall.CanTouch = false
	wall.CastShadow = false
	wall.Name = "Bound"
	return wall
end

local function buildBounds(zone, parent: Instance)
	local c = zone.Center
	local L = zone.Land
	for _, line in ipairs(contourPolylines(zone)) do
		line = simplify(line, 2.5)
		for j = 2, #line do
			local a, b = line[j - 1], line[j]
			local length = (b - a).Magnitude
			if length > 0.5 then
				local mid = (a + b) / 2
				local from = c + Vector3.new(mid.X, 120, mid.Y)
				invisibleWall(parent, CFrame.lookAt(from, from + Vector3.new(b.X - a.X, 0, b.Y - a.Y)), Vector3.new(3, 440, length + 3))
			end
		end
	end
	-- the strip border beside each gate (the gap is the barrier)
	for _, gate in ipairs(L.Gates) do
		local span = L.D - 14
		for _, side in ipairs({ -1, 1 }) do
			invisibleWall(parent, CFrame.new(c.X + gate.x, 120, side * (14 + span / 2)), Vector3.new(24, 440, span))
		end
	end
end

local function buildGate(zone, parent: Instance)
	if zone.Index == 1 then
		return
	end
	local x = zone.Center.X - Zones.Spacing / 2
	local gateCf = CFrame.new(x, 0, 0) * CFrame.Angles(0, math.pi / 2, 0)
	Props.Torii(parent, gateCf, 24, 22, zone.Theme.Accent:Lerp(rgb(200, 40, 30), 0.5))
	local barrier = Props.Part(parent, Vector3.new(3, 30, 28), CFrame.new(x, 15, 0), zone.Theme.Accent, Enum.Material.ForceField)
	barrier.Name = "Gate_" .. zone.Id
	barrier.Transparency = 0.2
	barrier.CastShadow = false
	barrier:SetAttribute("ZoneId", zone.Id)
	CollectionService:AddTag(barrier, "ZoneGate")
	for _, face in ipairs({ Enum.NormalId.Left, Enum.NormalId.Right }) do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "GateLabel"
		gui.Face = face
		gui.CanvasSize = Vector2.new(300, 320)
		gui.LightInfluence = 0
		gui.AlwaysOnTop = false
		gui.Parent = barrier
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.Size = UDim2.fromScale(0.8, 0.6)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 1
		local outline = Instance.new("UIStroke")
		outline.Color = rgb(26, 22, 40)
		outline.Thickness = 3
		outline.Parent = label
		local cap = Instance.new("UITextSizeConstraint")
		cap.MaxTextSize = 44
		cap.Parent = label
		label.Text = string.format("🔒\n%s\nLv %d\n🪙 %s", zone.Name, zone.Level, Format.Abbrev(zone.Cost))
		label.Parent = gui
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "UnlockPrompt"
	prompt.ActionText = "Unlock (" .. Format.Abbrev(zone.Cost) .. ")"
	prompt.ObjectText = zone.Name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Parent = barrier
end

local function buildEgg(egg, parent: Instance)
	local pos = Pets.EggPosition(egg)
	local cf = CFrame.new(pos)
	local m = Instance.new("Model")
	m.Name = "EggStand_" .. egg.Id
	m.Parent = parent
	Props.Part(m, Vector3.new(1.4, 18, 18), cf * CFrame.new(0, 0.7, 0) * UP, rgb(235, 232, 225), Enum.Material.Marble, Enum.PartType.Cylinder)
	local ring = Props.Part(m, Vector3.new(0.4, 18.6, 18.6), cf * CFrame.new(0, 1.2, 0) * UP, egg.Accent, Enum.Material.Neon, Enum.PartType.Cylinder)
	ring.CanCollide = false
	Props.Part(m, Vector3.new(3, 7, 7), cf * CFrame.new(0, 2.5, 0) * UP, rgb(80, 70, 65), Enum.Material.Slate, Enum.PartType.Cylinder)
	local shell = Props.Part(m, Vector3.new(6, 7.8, 6), cf * CFrame.new(0, 8, 0), egg.Color, Enum.Material.SmoothPlastic)
	shell.Name = "Egg"
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = shell
	for i, y in ipairs({ -0.8, 1.2 }) do
		local band = Props.Part(m, Vector3.new(0.6, 6.1 - i * 0.4, 6.1 - i * 0.4), cf * CFrame.new(0, 8 + y, 0) * UP, egg.Accent, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		band.CanCollide = false
	end
	Particles.Create("Sparkle", shell, { Rate = 6, Color = ColorSequence.new(egg.Accent) })
	Props.Light(shell, egg.Accent, 16, 1.2)

	local billboard = Instance.new("BillboardGui")
	-- sized in studs, so it shrinks with distance like the egg instead of covering the screen
	billboard.Size = UDim2.fromScale(7, 2.2)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	billboard.MaxDistance = 90
	billboard.LightInfluence = 0
	billboard.Parent = shell
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0.55, 0)
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextStrokeTransparency = 1
	local outline = Instance.new("UIStroke")
	outline.Color = rgb(26, 22, 40)
	outline.Thickness = 2
	outline.Parent = name
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 40
	cap.Parent = name
	name.Text = egg.Name
	name.Parent = billboard
	local price = name:Clone()
	price.Position = UDim2.new(0, 0, 0.55, 0)
	price.Size = UDim2.new(1, 0, 0.45, 0)
	price.TextColor3 = if egg.Currency == "Shards" then rgb(140, 255, 240) else rgb(255, 215, 80)
	price.Text = (if egg.Currency == "Shards" then "💎 " else "🪙 ") .. Format.Abbrev(egg.Cost)
	price.Parent = billboard

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HatchPrompt"
	prompt.ActionText = "Open Egg"
	prompt.ObjectText = egg.Name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Parent = shell
	shell:SetAttribute("EggId", egg.Id)
	CollectionService:AddTag(shell, "EggStand")
end

local function buildArena(zone, parent: Instance)
	local pos = Zones.WorldPosition(zone, zone.BossOffset)
	local cf = CFrame.new(pos)
	local boss = Enemies.Get(zone.Boss.Enemy)
	local accent = if boss then boss.Colors.Accent else zone.Theme.Accent
	Props.Part(parent, Vector3.new(1.4, 76, 76), cf * CFrame.new(0, 0.3, 0) * UP, zone.Theme.RockColor:Lerp(rgb(90, 90, 90), 0.4), Enum.Material.Slate, Enum.PartType.Cylinder)
	local ring = Props.Part(parent, Vector3.new(1.2, 78, 78), cf * CFrame.new(0, 0.2, 0) * UP, accent, Enum.Material.Neon, Enum.PartType.Cylinder)
	ring.CanCollide = false
	Props.Part(parent, Vector3.new(1.5, 20, 20), cf * CFrame.new(0, 0.5, 0) * UP, accent:Lerp(Color3.new(0, 0, 0), 0.5), Enum.Material.Slate, Enum.PartType.Cylinder)
	for i = 0, 7 do
		local a = i * math.pi / 4
		local pcf = cf * CFrame.new(math.cos(a) * 36, 0, math.sin(a) * 36)
		if i % 2 == 0 then
			Props.Brazier(parent, pcf, accent)
		else
			Props.Part(parent, Vector3.new(3, 12, 3), pcf * CFrame.new(0, 6, 0), zone.Theme.RockColor, Enum.Material.Slate)
			local cap = Props.Part(parent, Vector3.new(1.4, 1.4, 1.4), pcf * CFrame.new(0, 12.8, 0), accent, Enum.Material.Neon, Enum.PartType.Ball)
			Props.Light(cap, accent, 12, 1)
		end
	end
	local marker = Props.Part(parent, Vector3.new(1, 1, 1), cf * CFrame.new(0, 1, 0), accent)
	marker.Transparency = 1
	marker.CanCollide = false
	marker.Name = "ArenaMarker"
	marker:SetAttribute("ZoneId", zone.Id)
	CollectionService:AddTag(marker, "BossArena")
	Props.Sign(parent, cf * CFrame.new(0, 0, 44) * CFrame.Angles(0, math.pi, 0), "BOSS ARENA", if boss then boss.Name else nil, accent)
end

local function buildSpawn(zone, parent: Instance)
	local pos = Vector3.new(zone.Spawn.X, zone.Spawn.Y - 4, zone.Spawn.Z)
	local cf = CFrame.new(pos)
	Props.Part(parent, Vector3.new(1, 26, 26), cf * CFrame.new(0, 0.5, 0) * UP, rgb(200, 195, 185), Enum.Material.Cobblestone, Enum.PartType.Cylinder)
	local ring = Props.Part(parent, Vector3.new(0.8, 27, 27), cf * CFrame.new(0, 0.4, 0) * UP, zone.Theme.Accent, Enum.Material.Neon, Enum.PartType.Cylinder)
	ring.CanCollide = false
	if zone.Index == 1 then
		local spawn = Instance.new("SpawnLocation")
		spawn.Size = Vector3.new(12, 1, 12)
		spawn.CFrame = cf * CFrame.new(0, 1.1, 0)
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Duration = 3
		spawn.Transparency = 1
		spawn.CanCollide = false
		spawn.Parent = parent
		local decal = spawn:FindFirstChildOfClass("Decal")
		if decal then
			decal:Destroy()
		end
	end
	Props.Sign(parent, CFrame.new(pos + Vector3.new(14, 0, -18)) * CFrame.Angles(0, -math.pi / 2, 0), zone.Name:upper(), if zone.Level > 1 then "Recommended Lv " .. zone.Level .. "+" else "Welcome, young ninja!", zone.Theme.Accent:Lerp(Color3.new(1, 1, 1), 0.4))
end

local AMBIENT = {
	Village = { "Petals", { Rate = 25 } },
	Bamboo = { "Petals", { Rate = 18, Color = ColorSequence.new(rgb(170, 220, 120), rgb(110, 170, 70)) } },
	Samurai = { "Petals", { Rate = 20 } },
	Demon = { "Embers", { Rate = 30, Lifetime = NumberRange.new(4, 7), Speed = NumberRange.new(1, 3) } },
	Shadow = { "Sparkle", { Rate = 30, Color = ColorSequence.new(rgb(180, 120, 255)), Lifetime = NumberRange.new(3, 6) } },
	Volcanic = { "Embers", { Rate = 45, Lifetime = NumberRange.new(4, 7), Speed = NumberRange.new(1, 3) } },
	Sky = { "Frost", { Rate = 30, Lifetime = NumberRange.new(5, 8) } },
	Void = { "Void", { Rate = 35, Lifetime = NumberRange.new(3, 6), Speed = NumberRange.new(0.5, 2) } },
}

local function buildAmbient(zone, parent: Instance)
	local preset = AMBIENT[zone.Decor]
	if not preset then
		return
	end
	-- one emitter over the valley; the rate scales with its area so the density matches the village
	local size = if zone.Index == 1 then Vector2.new(Zones.Size - 40, Zones.Size - 40) else Vector2.new(Zones.Spacing - 80, Zones.Depth - 140)
	local emitterPart = Props.Part(parent, Vector3.new(size.X, 1, size.Y), CFrame.new(zone.Center + Vector3.new(0, if zone.Index == 1 then 18 else 34, 0)), Color3.new())
	emitterPart.Name = "AmbientEmitter"
	emitterPart.Transparency = 1
	emitterPart.CanCollide = false
	emitterPart.CanQuery = false
	emitterPart.CanTouch = false
	local overrides = table.clone(preset[2])
	overrides.Rate = (overrides.Rate or 20) * math.min(size.X * size.Y / (Zones.Size - 40) ^ 2, 3)
	overrides.Lifetime = overrides.Lifetime or NumberRange.new(6, 10)
	overrides.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.1, 0.4), NumberSequenceKeypoint.new(1, 0.3) })
	local emitter = Particles.Create(preset[1], emitterPart, overrides)
	if emitter then
		emitter.Name = "Ambient"
		CollectionService:AddTag(emitter, "AmbientParticles")
	end
end

-- One broken piece of scenery must not stop the rest of the world (or the game) from loading.
local function guard(label: string, fn, ...): boolean
	local ok, err = pcall(fn, ...)
	if not ok then
		warn("[WorldBuilder] " .. label .. " failed: " .. tostring(err))
	end
	return ok
end

-- Safety net once every zone is built: clear any terrain bulging into the pass at
-- each gate (scenery fills can reach it) and repaint the road under the gate.
local function carveGatePass(zone)
	if zone.Index == 1 then
		return
	end
	local x = zone.Center.X - Zones.Spacing / 2
	terrain:FillBlock(CFrame.new(x, 31, 0), Vector3.new(48, 60, 24), Enum.Material.Air)
	for _, side in ipairs({ { Zones.List[zone.Index - 1], -12 }, { zone, 12 } }) do
		terrain:FillBlock(CFrame.new(x + side[2], -1.2, 0), Vector3.new(24, 2.4, ROAD_HALF_WIDTH * 2), side[1].Theme.Path)
	end
end

-- Decor context: placement helpers that know the zone's land (see ZoneDecor).
local function makeContext(zone, folder: Instance, rng: Random, grid)
	local L = zone.Land
	local c = zone.Center
	local H, D = L.H, L.D

	-- reserved ground decor stays off: pads (camps keep their whole fighting area)
	local circles = {}
	for _, p in ipairs(L.Pads) do
		table.insert(circles, { p.x, p.z, if p.Kind == "Boss" then 46 elseif p.Kind == "Camp" then p.r else p.r + 2 })
	end
	for _, egg in ipairs(Pets.Eggs) do
		if egg.Zone == zone.Id and egg.Offset then
			table.insert(circles, { egg.Offset.X, egg.Offset.Y, 16 })
		end
	end

	-- what's already placed, on a coarse grid
	local CELL = 16
	local taken = {}
	local function cellKey(ix: number, iz: number): number
		return ix * 100000 + iz
	end
	local function occupied(x: number, z: number, r: number): boolean
		local ix, iz = x // CELL, z // CELL
		for dx = -1, 1 do
			for dz = -1, 1 do
				local list = taken[cellKey(ix + dx, iz + dz)]
				if list then
					for _, t in ipairs(list) do
						local rr = t[3] + r
						if (t[1] - x) ^ 2 + (t[2] - z) ^ 2 < rr * rr then
							return true
						end
					end
				end
			end
		end
		return false
	end
	local function claim(x: number, z: number, r: number)
		local k = cellKey(x // CELL, z // CELL)
		taken[k] = taken[k] or {}
		table.insert(taken[k], { x, z, r })
	end

	-- terrain grid lookups (bilinear between voxel columns), analytic if the terrain failed
	local function gridValue(field: string, x: number, z: number): number?
		if not grid then
			return nil
		end
		local u, v = (x + H) / VOXEL - 0.5, (z + D) / VOXEL - 0.5
		local i, k = math.floor(u), math.floor(v)
		local fu, fv = u - i, v - k
		local g = grid[field]
		local a, b = g[i] and g[i][k], g[i + 1] and g[i + 1][k]
		local cc, d = g[i] and g[i][k + 1], g[i + 1] and g[i + 1][k + 1]
		if not (a and b and cc and d) then
			return nil
		end
		return (a * (1 - fu) + b * fu) * (1 - fv) + (cc * (1 - fu) + d * fu) * fv
	end

	local ctx = { Zone = zone, Folder = folder, Rng = rng, Land = L }

	function ctx.Height(x: number, z: number): number
		return gridValue("h", x, z) or Landscape.Height(zone, x, z)
	end
	function ctx.Edge(x: number, z: number): number
		return gridValue("s", x, z) or Landscape.Edge(zone, x, z)
	end
	function ctx.Slope(x: number, z: number): number
		local dx = ctx.Height(x + 3, z) - ctx.Height(x - 3, z)
		local dz = ctx.Height(x, z + 3) - ctx.Height(x, z - 3)
		return math.sqrt(dx * dx + dz * dz) / 6
	end
	-- Ground CFrame at a zone-local position (sink pushes it a little into the ground).
	function ctx.At(x: number, z: number, yaw: number?, sink: number?): CFrame
		return CFrame.new(c.X + x, c.Y + ctx.Height(x, z) - (sink or 0), c.Z + z) * CFrame.Angles(0, yaw or 0, 0)
	end
	function ctx.Claim(x: number, z: number, r: number)
		claim(x, z, r)
	end

	--[[
		Can something of radius `margin` go at (x, z)? opts:
		  Edge      how far past the valley edge it may go (studs, default -3 = inside)
		  MinEdge   it must be at least this far past the edge (for ridge tops)
		  MaxSlope  steepest ground allowed (rise / run)
		  Road      extra clearance from roads (default 3)
	]]
	function ctx.IsClear(x: number, z: number, margin: number, opts: any?): boolean
		opts = opts or {}
		if math.abs(x) > H - 10 or math.abs(z) > D - 10 then
			return false
		end
		for _, circle in ipairs(circles) do
			local rr = circle[3] + margin
			if (x - circle[1]) ^ 2 + (z - circle[2]) ^ 2 < rr * rr then
				return false
			end
		end
		if occupied(x, z, margin) then
			return false
		end
		local s = ctx.Edge(x, z)
		if s > (opts.Edge or -3) or (opts.MinEdge and s < opts.MinEdge) then
			return false
		end
		local d, hw = Landscape.RoadDistance(zone, x, z)
		if d < hw + (opts.Road or 3) + margin then
			return false
		end
		if opts.MaxSlope and ctx.Slope(x, z) > opts.MaxSlope then
			return false
		end
		return true
	end

	local function randomPoint(area): (number, number)
		if area then
			local a, r = rng:NextNumber(0, math.pi * 2), area[3] * math.sqrt(rng:NextNumber())
			return area[1] + math.cos(a) * r, area[2] + math.sin(a) * r
		end
		return rng:NextNumber(-H, H), rng:NextNumber(-D, D)
	end

	-- Calls fn(cf, x, z) at up to `count` random clear spots. opts as IsClear, plus
	-- Area = {x, z, radius} to stay inside, Sink to push props into the ground.
	function ctx.Scatter(count: number, margin: number, fn: (CFrame, number, number) -> (), opts: any?)
		opts = opts or {}
		local placed, tries = 0, 0
		while placed < count and tries < count * 30 do
			tries += 1
			local x, z = randomPoint(opts.Area)
			if ctx.IsClear(x, z, margin, opts) then
				claim(x, z, margin)
				placed += 1
				fn(ctx.At(x, z, rng:NextNumber(0, math.pi * 2), opts.Sink or 0.3), x, z)
			end
		end
		return placed
	end

	-- Clusters: `groves` centres, each with up to `per` items within `spread` studs.
	function ctx.Groves(groves: number, per: number, spread: number, margin: number, fn: (CFrame, number, number) -> (), opts: any?)
		local o: { [string]: any } = opts or {}
		for _ = 1, groves do
			for _ = 1, 40 do
				local gx, gz = randomPoint(o.Area)
				if ctx.IsClear(gx, gz, margin, o) then
					local inner = table.clone(o)
					inner.Area = { gx, gz, spread }
					ctx.Scatter(per, margin, fn, inner)
					break
				end
			end
		end
	end

	-- Calls fn(cf, side, index) beside the main road every `step` studs, `offset`
	-- studs from its centre line, facing the road, for props up to `radius` studs
	-- across. Skips junctions, pads and the valley edge.
	function ctx.RoadSide(step: number, offset: number, fn: (CFrame, number, number) -> (), both: boolean?, radius: number?)
		local r = radius or 2
		for i, p in ipairs(Landscape.RoadPoints(zone, step)) do
			for _, side in ipairs(if both then { -1, 1 } elseif i % 2 == 0 then { 1 } else { -1 }) do
				local x, z = p.X - p.DirZ * offset * side, p.Z + p.DirX * offset * side
				local ok = math.abs(x) < H - 30 and not occupied(x, z, r)
				if ok then
					for _, circle in ipairs(circles) do
						if (x - circle[1]) ^ 2 + (z - circle[2]) ^ 2 < (circle[3] + r + 1) ^ 2 then
							ok = false
							break
						end
					end
				end
				if ok then
					local d, hw = Landscape.RoadDistance(zone, x, z)
					ok = d > hw + 1.5 + math.max(r - 2, 0) and ctx.Edge(x, z) < -2 - r
				end
				if ok then
					claim(x, z, r)
					local cf = ctx.At(x, z)
					local face = Vector3.new(p.X - x, 0, p.Z - z)
					fn(CFrame.lookAt(cf.Position, cf.Position + face), side, i)
				end
			end
		end
	end

	-- Calls fn(cf, x, z) on the ridges beyond the valley (out of bounds), for skylines.
	function ctx.Ridge(count: number, margin: number, fn: (CFrame, number, number) -> ())
		local placed, tries = 0, 0
		while placed < count and tries < count * 30 do
			tries += 1
			local x, z = randomPoint(nil)
			if math.abs(x) < H - 8 and math.abs(z) < D - 8 and not occupied(x, z, margin) then
				local s = ctx.Edge(x, z)
				local _, _, _, _, _, cliffW = Landscape.Sample(zone, x, z)
				if s > cliffW * 0.9 and s < cliffW * 3 and ctx.Slope(x, z) < 0.6 then
					claim(x, z, margin)
					placed += 1
					fn(ctx.At(x, z, rng:NextNumber(0, math.pi * 2), 0.5), x, z)
				end
			end
		end
	end

	return ctx
end

function WorldBuilder.Build()
	local world = Instance.new("Folder")
	world.Name = "World"
	world.Parent = workspace
	local bounds = Instance.new("Folder")
	bounds.Name = "Bounds"
	bounds.Parent = world
	-- grass blades on Grass terrain (not settable from scripts on every engine version)
	pcall(function()
		(terrain :: any).Decoration = true
	end)

	for _, zone in ipairs(Zones.List) do
		local rng = Random.new(zone.Index * 7919)
		local folder = Instance.new("Model")
		folder.Name = zone.Id
		folder.Parent = world

		local grid: any = { h = {}, s = {} }
		if not guard(zone.Id .. " terrain", buildTerrain, zone, grid) then
			grid = nil -- decor falls back to the analytic land
		end
		guard(zone.Id .. " bounds", buildBounds, zone, bounds)
		guard(zone.Id .. " gate", buildGate, zone, folder)
		guard(zone.Id .. " arena", buildArena, zone, folder)
		guard(zone.Id .. " spawn", buildSpawn, zone, folder)
		guard(zone.Id .. " ambient", buildAmbient, zone, folder)

		local ctx = makeContext(zone, folder, rng, grid)
		local decor = ZoneDecor[zone.Decor]
		if decor then
			guard("decor for " .. zone.Id, decor, ctx)
		end
		task.wait() -- let the server breathe between zones
	end
	for _, zone in ipairs(Zones.List) do
		guard(zone.Id .. " gate pass", carveGatePass, zone)
	end

	for _, egg in ipairs(Pets.Eggs) do
		local zoneFolder = world:FindFirstChild(egg.Zone)
		if zoneFolder then
			guard(egg.Id .. " egg", buildEgg, egg, zoneFolder)
		end
	end
	return world
end

return WorldBuilder
