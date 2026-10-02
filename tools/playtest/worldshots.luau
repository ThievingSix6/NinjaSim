--!nocheck
-- World preview scenario: dumps one zone's scenery (every part the WorldBuilder and
-- ZoneDecor built, plus the land's height field from shared/Landscape) to
-- $WORLDSHOTS_DIR/<zone>.json (default /tmp/claude-0/worldshots) for
-- tools/blender/world_preview.py, which renders views of it.
--   SCENARIO=worldshots WORLDSHOTS_ZONE=village lune run run.luau
local task = require("@lune/task")
local serde = require("@lune/serde")
local fs = require("@lune/fs")
local process = require("@lune/process")

return function(E)
	local out = process.env.WORLDSHOTS_DIR or "/tmp/claude-0/worldshots"
	local zoneId = process.env.WORLDSHOTS_ZONE or "village"
	pcall(fs.writeDir, out)
	task.wait(1)
	local Zones = E.shared("Config.Zones")
	local Landscape = E.shared("Landscape")
	local zone = Zones.Get(zoneId)
	local function enumName(e)
		return (string.gsub(tostring(e), "^Enum%.%w+%.", ""))
	end
	local function col(c)
		return { c.R, c.G, c.B }
	end

	local parts = {}
	local folder = E.Workspace:FindFirstChild("World"):FindFirstChild(zoneId)
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			table.insert(parts, {
				class = d.ClassName, shape = if d.ClassName == "Part" then enumName(d.Shape) else nil,
				size = { d.Size.X, d.Size.Y, d.Size.Z }, cf = { d.CFrame:GetComponents() }, color = col(d.Color),
				material = enumName(d.Material), transparency = d.Transparency,
			})
		end
	end

	local step = 4
	local L = zone.Land
	local rows = {}
	for z = -L.D, L.D, step do
		local row = {}
		for x = -L.H, L.H, step do
			local h, road, s, wl = Landscape.Sample(zone, x, z)
			table.insert(row, { h, road, s, wl or false })
		end
		table.insert(rows, row)
	end
	local theme = zone.Theme
	local payload = {
		zone = zoneId, center = { zone.Center.X, zone.Center.Y, zone.Center.Z }, step = step, h = L.H, d = L.D,
		spawn = { zone.Spawn.X, zone.Spawn.Y, zone.Spawn.Z },
		boss = { zone.BossOffset.X, zone.BossOffset.Y },
		theme = { ground = col(theme.GroundColor), path = col(theme.PathColor), rock = col(theme.RockColor) },
		rows = rows, parts = parts,
	}
	fs.writeFile(out .. "/" .. zoneId .. ".json", serde.encode("json", payload))
	print("[worldshots] wrote " .. #parts .. " parts and a " .. #rows .. "-row height field to " .. out .. "/" .. zoneId .. ".json")
end
