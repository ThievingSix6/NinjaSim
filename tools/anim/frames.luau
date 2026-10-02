--!nocheck
--[[
	Samples a weapon's combo (src/shared/Config/Combo.lua) with the game's own pose
	code (src/shared/Util/Pose.lua) and writes every joint's Transform per frame as
	JSON, for tools/blender/anim_preview.py to render. "Grip" is the weapon's turn in
	the hand; "spin" (when a move has a Spin) is its extra twirl on top.

	Run: lune run tools/anim/frames.luau <out.json> [fps] [Katana|Nunchaku|Spear]
]]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local ROOT = process.cwd
local OUT = process.args[1] or "/tmp/combo_frames.json"
local FPS = tonumber(process.args[2]) or 30
local WEAPON = process.args[3] or "Katana"

local env = setmetatable({ CFrame = roblox.CFrame, Vector3 = roblox.Vector3 }, { __index = _G })
local function load(path)
	return luau.load(fs.readFile(ROOT .. path), { debugName = path, environment = env })()
end
local Pose = load("src/shared/Util/Pose.lua")
local Combo = load("src/shared/Config/Combo.lua")

local out = { fps = FPS, joints = Pose.Joints, weapon = WEAPON, moves = {} }
local from = nil
local moves = Combo.MovesFor(WEAPON)
for i, move in ipairs(moves) do
	-- holding attack starts the next move as soon as this one's cooldown ends (at the
	-- base attack speed); the last move plays out
	local length = if i < #moves then move.Cooldown * 0.62 else move.Duration -- 0.62 = Balance.BaseAttackInterval
	local frames = {}
	local n = math.floor(length * FPS + 0.5)
	local last, lastWeight
	for f = 0, n do
		local t = f / FPS / move.Duration
		local pose, weight = Pose.Sample(move, math.min(t, 1), from)
		local joints = {}
		for _, joint in ipairs(Pose.Joints) do
			local cf = roblox.CFrame.new():Lerp(Pose.CFrame(pose, joint), weight)
			joints[joint] = { cf:GetComponents() }
		end
		local spin = Combo.SpinCFrame and Combo.SpinCFrame(move, math.min(t, 1))
		table.insert(frames, { t = t, weight = weight, joints = joints, spin = if spin then { spin:GetComponents() } else nil })
		last, lastWeight = pose, weight
	end
	from = Pose.Scale(last, lastWeight)
	table.insert(out.moves, {
		name = move.Name,
		duration = move.Duration,
		hitAt = move.HitAt,
		trail = move.Trail,
		frames = frames,
	})
end
fs.writeFile(OUT, serde.encode("json", out))
print("wrote", OUT, #out.moves, "moves")
