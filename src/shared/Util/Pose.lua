--[[
	Pose: keyframed full-body poses for procedural animation (no animation assets).

	A pose is a table of joint name -> { x, y, z } rotation in degrees, applied as
	CFrame.fromEulerAnglesYXZ in the joint's parent space (R15 convention: the
	character faces -Z, +X is its right). "RootPos" is a { x, y, z } offset in studs.
	Joints a pose leaves out are 0 (the underlying walk/idle shows through there only
	as the move fades out).

	Sign guide (right side; the left side mirrors y and z):
	  Root / Waist / Neck   y + = turn left      x + = lean back
	  Shoulder              x + = raise forward  y + = swing across to the left
	                        z + = raise out to the right
	  Elbow                 x + = bend
	  Wrist                 x + = cock the blade up (+30 is square to the forearm,
	                              -60 is in line with it)   y = twist
	  Hip                   x + = leg forward     Knee  x - = bend
	  Grip                  the weapon in the hand (grip space: x + = tip up, y = swing
	                        the tip sideways); see Combo.Spear

	A move is { Keys = { { T = 0..1, Ease = "Out", <joint> = {...}, ... }, ... } }.
	Pose.Sample(move, t, from) blends from the `from` pose (the previous move's last
	pose, so combos flow) through the keys, then fades out after the last key.
]]

local Pose = {}

Pose.Joints = {
	"Root",
	"Waist",
	"Neck",
	"RightShoulder",
	"RightElbow",
	"RightWrist",
	"LeftShoulder",
	"LeftElbow",
	"LeftWrist",
	"RightHip",
	"RightKnee",
	"LeftHip",
	"LeftKnee",
	-- not a body joint: the held weapon's extra turn in the hand (spears turn the
	-- shaft along the forearm to thrust); AnimationController applies it to the grip weld
	"Grip",
}

local ZERO = { 0, 0, 0 }

local EASE = {
	Linear = function(t: number): number
		return t
	end,
	In = function(t: number): number
		return t * t
	end,
	Out = function(t: number): number
		return 1 - (1 - t) ^ 2
	end,
	-- fast strike that decelerates hard: the blade whips through, then settles
	Snap = function(t: number): number
		return 1 - (1 - t) ^ 4
	end,
	InOut = function(t: number): number
		return if t < 0.5 then 2 * t * t else 1 - (-2 * t + 2) ^ 2 / 2
	end,
}

local function lerp3(a, b, k: number)
	return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k }
end

-- Blends two poses (missing joints count as 0).
function Pose.Lerp(a, b, k: number)
	local out = {}
	for _, joint in ipairs(Pose.Joints) do
		out[joint] = lerp3(a[joint] or ZERO, b[joint] or ZERO, k)
	end
	out.RootPos = lerp3(a.RootPos or ZERO, b.RootPos or ZERO, k)
	return out
end

local function wrap(a: number): number
	return (a + 180) % 360 - 180
end

-- The same pose with every angle in -180..180 (a spin that ended at -370 fades back
-- from -10 instead of unwinding a whole turn).
function Pose.Wrap(pose)
	local out = {}
	for _, joint in ipairs(Pose.Joints) do
		local a = pose[joint] or ZERO
		out[joint] = { wrap(a[1]), wrap(a[2]), wrap(a[3]) }
	end
	out.RootPos = pose.RootPos or ZERO
	return out
end

-- Pose of `move` at t (0..1) plus its weight (1 while the keys play, falling to 0
-- after the last key so the default animation takes back over).
function Pose.Sample(move, t: number, from)
	local keys = move.Keys
	local prev, prevT = from or {}, 0
	for _, key in ipairs(keys) do
		if t <= key.T then
			local span = key.T - prevT
			local k = if span > 0 then (t - prevT) / span else 1
			return Pose.Lerp(prev, key, EASE[key.Ease or "InOut"](math.clamp(k, 0, 1))), 1
		end
		prev, prevT = key, key.T
	end
	local last = Pose.Wrap(keys[#keys])
	local k = if keys[#keys].T < 1 then (t - keys[#keys].T) / (1 - keys[#keys].T) else 1
	return last, 1 - EASE.InOut(math.clamp(k, 0, 1))
end

-- Scales a pose toward rest (used to start the next move from a half-faded one).
function Pose.Scale(pose, k: number)
	return Pose.Lerp({}, Pose.Wrap(pose), k)
end

-- The joint's Transform for an R15 rig (joint frames line up with the character).
function Pose.CFrame(pose, joint: string): CFrame
	local a = pose[joint] or ZERO
	local cf = CFrame.fromEulerAnglesYXZ(math.rad(a[1]), math.rad(a[2]), math.rad(a[3]))
	if joint == "Root" and pose.RootPos then
		local p = pose.RootPos
		cf = CFrame.new(p[1], p[2], p[3]) * cf
	end
	return cf
end

return Pose
