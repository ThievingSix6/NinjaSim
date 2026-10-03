--[[
	UltimatePoses: the full-body animations of the suit ultimates (Config/Mastery.Sets),
	one of their own for each of the 44. Same format as SkillEffects' poses (Util/Pose
	sign guide: Root/Waist/Neck y+ turn left, x+ lean back; Shoulder x+ raise forward,
	z+ raise out (left side mirrored); Elbow x+ bend; Hip x+ leg forward; Knee x- bend).
	SuitUltimateEffects adds them to SkillEffects.Poses and plays them by name.
]]

local function key(t: number, ease: string, joints)
	joints.T = t
	joints.Ease = ease
	return joints
end

-- legs shorthands
local function stance(j)
	j.RightHip = j.RightHip or { 30, 0, 10 }
	j.RightKnee = j.RightKnee or { -45, 0, 0 }
	j.LeftHip = j.LeftHip or { -15, 0, -10 }
	j.LeftKnee = j.LeftKnee or { -30, 0, 0 }
	return j
end
local function wide(j)
	j.RightHip = j.RightHip or { 25, 0, 28 }
	j.RightKnee = j.RightKnee or { -55, 0, 0 }
	j.LeftHip = j.LeftHip or { 25, 0, -28 }
	j.LeftKnee = j.LeftKnee or { -55, 0, 0 }
	j.RootPos = j.RootPos or { 0, -0.8, 0 }
	return j
end
local function tuck(j)
	j.RightHip = j.RightHip or { 95, 0, 8 }
	j.RightKnee = j.RightKnee or { -120, 0, 0 }
	j.LeftHip = j.LeftHip or { 95, 0, -8 }
	j.LeftKnee = j.LeftKnee or { -120, 0, 0 }
	return j
end

local P = {}

-- ===================== Green: Wind =====================
-- A flat-out ninja run, arms streaming behind; the stride flips at each zig.
P.GaleRun = { Keys = {
	key(0.12, "Out", { RootPos = { 0, -0.7, 0 }, Root = { -42, 0, 0 }, Waist = { -10, 0, 0 }, Neck = { 30, 0, 0 },
		RightShoulder = { -70, 0, 18 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { -70, 0, -18 }, LeftElbow = { 10, 0, 0 },
		RightHip = { 70, 0, 5 }, RightKnee = { -80, 0, 0 }, LeftHip = { -40, 0, -5 }, LeftKnee = { -50, 0, 0 } }),
	key(0.42, "Linear", { RootPos = { 0, -0.7, 0 }, Root = { -42, 18, 0 }, Waist = { -10, -10, 0 }, Neck = { 30, 0, 0 },
		RightShoulder = { -70, 0, 18 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { -70, 0, -18 }, LeftElbow = { 10, 0, 0 },
		RightHip = { -40, 0, 5 }, RightKnee = { -50, 0, 0 }, LeftHip = { 70, 0, -5 }, LeftKnee = { -80, 0, 0 } }),
	key(0.72, "Linear", { RootPos = { 0, -0.7, 0 }, Root = { -42, -18, 0 }, Waist = { -10, 10, 0 }, Neck = { 30, 0, 0 },
		RightShoulder = { -70, 0, 18 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { -70, 0, -18 }, LeftElbow = { 10, 0, 0 },
		RightHip = { 70, 0, 5 }, RightKnee = { -80, 0, 0 }, LeftHip = { -40, 0, -5 }, LeftKnee = { -50, 0, 0 } }),
	key(0.95, "Out", stance({ RootPos = { 0, -0.4, 0 }, Root = { -10, 0, 0 },
		RightShoulder = { 20, 0, 30 }, RightElbow = { 30, 0, 0 }, LeftShoulder = { 20, 0, -30 }, LeftElbow = { 30, 0, 0 } })),
} }

-- Wind up across the body, then whip the crescent out to the right.
P.BoomerangThrow = { Keys = {
	key(0.3, "Out", stance({ RootPos = { 0, -0.5, 0 }, Root = { 0, 45, 0 }, Waist = { 0, 25, 0 }, Neck = { 0, -40, 0 },
		RightShoulder = { 70, 80, 0 }, RightElbow = { 60, 0, 0 }, RightWrist = { 30, 0, 0 }, LeftShoulder = { 30, 0, -50 }, LeftElbow = { 50, 0, 0 } })),
	key(0.5, "Snap", stance({ RootPos = { 0, -0.6, 0 }, Root = { 0, -50, 0 }, Waist = { 0, -25, 0 }, Neck = { 0, 45, 0 },
		RightShoulder = { 80, -40, 60 }, RightElbow = { 0, 0, 0 }, RightWrist = { -30, 0, 0 }, LeftShoulder = { 10, 0, -70 }, LeftElbow = { 20, 0, 0 } })),
	key(0.85, "Out", stance({ RootPos = { 0, -0.6, 0 }, Root = { 0, -60, 0 }, Waist = { 0, -25, 0 }, Neck = { 0, 50, 0 },
		RightShoulder = { 60, -50, 70 }, RightElbow = { 5, 0, 0 }, LeftShoulder = { 0, 0, -60 }, LeftElbow = { 20, 0, 0 } })),
} }

-- Arms overhead, then the whole body becomes the spinning eye of the storm.
P.TyphoonSpin = { Keys = {
	key(0.15, "Out", wide({ Root = { 5, 0, 0 }, Neck = { -20, 0, 0 },
		RightShoulder = { 165, 0, 20 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 165, 0, -20 }, LeftElbow = { 10, 0, 0 } })),
	key(0.5, "Linear", wide({ Root = { 0, -540, 0 }, Neck = { -10, 0, 0 },
		RightShoulder = { 30, 0, 120 }, RightElbow = { 5, 0, 0 }, LeftShoulder = { 30, 0, -120 }, LeftElbow = { 5, 0, 0 } })),
	key(0.85, "Out", wide({ Root = { 0, -1080, 0 }, Neck = { -10, 0, 0 },
		RightShoulder = { 30, 0, 130 }, RightElbow = { 5, 0, 0 }, LeftShoulder = { 30, 0, -130 }, LeftElbow = { 5, 0, 0 } })),
} }

-- A leap into a spread-eagle hang, then a flurry of downward throws.
P.SkyDance = { Keys = {
	key(0.12, "Out", tuck({ Root = { -20, 0, 0 },
		RightShoulder = { 60, 0, 30 }, RightElbow = { 90, 0, 0 }, LeftShoulder = { 60, 0, -30 }, LeftElbow = { 90, 0, 0 } })),
	key(0.3, "Out", { Root = { 10, 0, 0 }, Neck = { -15, 0, 0 },
		RightShoulder = { 30, 0, 140 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 30, 0, -140 }, LeftElbow = { 0, 0, 0 },
		RightHip = { 10, 0, 30 }, RightKnee = { -10, 0, 0 }, LeftHip = { 10, 0, -30 }, LeftKnee = { -10, 0, 0 } }),
	key(0.45, "Snap", { Root = { -25, 20, 0 }, Neck = { 20, 0, 0 },
		RightShoulder = { 60, -20, 20 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 140, 0, -30 }, LeftElbow = { 60, 0, 0 },
		RightHip = { 40, 0, 10 }, RightKnee = { -70, 0, 0 }, LeftHip = { 10, 0, -10 }, LeftKnee = { -30, 0, 0 } }),
	key(0.6, "Snap", { Root = { -25, -20, 0 }, Neck = { 20, 0, 0 },
		RightShoulder = { 140, 0, 30 }, RightElbow = { 60, 0, 0 }, LeftShoulder = { 60, 20, -20 }, LeftElbow = { 0, 0, 0 },
		RightHip = { 10, 0, 10 }, RightKnee = { -30, 0, 0 }, LeftHip = { 40, 0, -10 }, LeftKnee = { -70, 0, 0 } }),
	key(0.75, "Snap", { Root = { -30, 0, 0 }, Neck = { 25, 0, 0 },
		RightShoulder = { 70, -20, 20 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 70, 20, -20 }, LeftElbow = { 0, 0, 0 },
		RightHip = { 30, 0, 10 }, RightKnee = { -60, 0, 0 }, LeftHip = { 30, 0, -10 }, LeftKnee = { -60, 0, 0 } }),
	key(0.95, "Out", { Root = { -5, 0, 0 },
		RightShoulder = { 20, 0, 70 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 20, 0, -70 }, LeftElbow = { 10, 0, 0 },
		RightHip = { 20, 0, 10 }, RightKnee = { -30, 0, 0 }, LeftHip = { 20, 0, -10 }, LeftKnee = { -30, 0, 0 } }),
} }

-- ===================== Blue: Ice =====================
-- A speed skater's glide: one leg pushing out behind, arms swinging, body swaying.
P.Skate = { Keys = {
	key(0.2, "Out", { RootPos = { 0, -0.9, 0 }, Root = { -35, 12, 0 }, Waist = { -10, 0, 0 }, Neck = { 25, -10, 0 },
		RightShoulder = { 60, 0, 10 }, RightElbow = { 30, 0, 0 }, LeftShoulder = { -60, 0, -20 }, LeftElbow = { 10, 0, 0 },
		RightHip = { 70, 0, 5 }, RightKnee = { -90, 0, 0 }, LeftHip = { -45, 0, -25 }, LeftKnee = { -5, 0, 0 } }),
	key(0.55, "InOut", { RootPos = { 0, -0.9, 0 }, Root = { -35, -12, 0 }, Waist = { -10, 0, 0 }, Neck = { 25, 10, 0 },
		RightShoulder = { -60, 0, 20 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 60, 0, -10 }, LeftElbow = { 30, 0, 0 },
		RightHip = { -45, 0, 25 }, RightKnee = { -5, 0, 0 }, LeftHip = { 70, 0, -5 }, LeftKnee = { -90, 0, 0 } }),
	key(0.9, "Out", { RootPos = { 0, -0.7, 0 }, Root = { -25, 0, 0 }, Neck = { 15, 0, 0 },
		RightShoulder = { 30, 0, 50 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 30, 0, -50 }, LeftElbow = { 10, 0, 0 },
		RightHip = { 50, 0, 10 }, RightKnee = { -80, 0, 0 }, LeftHip = { 20, 0, -10 }, LeftKnee = { -50, 0, 0 } }),
} }

-- Lance after lance: right, left, right, left, right.
P.Volley = { Keys = {
	key(0.12, "Out", stance({ RootPos = { 0, -0.4, 0 }, Root = { 0, 20, 0 }, RightShoulder = { 120, 30, 0 }, RightElbow = { 90, 0, 0 }, LeftShoulder = { 40, 0, -30 }, LeftElbow = { 40, 0, 0 } })),
	key(0.24, "Snap", stance({ RootPos = { 0, -0.5, 0 }, Root = { -10, -15, 0 }, RightShoulder = { 95, -10, 0 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 120, -30, 0 }, LeftElbow = { 90, 0, 0 } })),
	key(0.38, "Snap", stance({ RootPos = { 0, -0.5, 0 }, Root = { -10, 15, 0 }, RightShoulder = { 120, 30, 0 }, RightElbow = { 90, 0, 0 }, LeftShoulder = { 95, 10, 0 }, LeftElbow = { 0, 0, 0 } })),
	key(0.52, "Snap", stance({ RootPos = { 0, -0.5, 0 }, Root = { -10, -15, 0 }, RightShoulder = { 95, -10, 0 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 120, -30, 0 }, LeftElbow = { 90, 0, 0 } })),
	key(0.66, "Snap", stance({ RootPos = { 0, -0.5, 0 }, Root = { -10, 15, 0 }, RightShoulder = { 120, 30, 0 }, RightElbow = { 90, 0, 0 }, LeftShoulder = { 95, 10, 0 }, LeftElbow = { 0, 0, 0 } })),
	key(0.8, "Snap", stance({ RootPos = { 0, -0.6, 0 }, Root = { -15, -20, 0 }, RightShoulder = { 92, -15, 0 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { -10, 0, -40 }, LeftElbow = { 20, 0, 0 } })),
} }

-- Drop to one knee, palm to the ice, then rise opening both arms as the dome grows.
P.DomeKneel = { Keys = {
	key(0.3, "Out", { RootPos = { 0, -1.6, 0 }, Root = { -25, 0, 0 }, Waist = { -15, 0, 0 }, Neck = { 10, 0, 0 },
		RightShoulder = { 40, 0, 10 }, RightElbow = { 10, 0, 0 }, RightWrist = { 60, 0, 0 }, LeftShoulder = { 20, 0, -20 }, LeftElbow = { 60, 0, 0 },
		RightHip = { 90, 0, 5 }, RightKnee = { -90, 0, 0 }, LeftHip = { -10, 0, -5 }, LeftKnee = { -110, 0, 0 } }),
	key(0.55, "InOut", { RootPos = { 0, -1.5, 0 }, Root = { -25, 0, 0 }, Waist = { -15, 0, 0 },
		RightShoulder = { 30, 0, 15 }, RightElbow = { 5, 0, 0 }, RightWrist = { 60, 0, 0 }, LeftShoulder = { 20, 0, -20 }, LeftElbow = { 60, 0, 0 },
		RightHip = { 90, 0, 5 }, RightKnee = { -90, 0, 0 }, LeftHip = { -10, 0, -5 }, LeftKnee = { -110, 0, 0 } }),
	key(0.85, "Out", wide({ Root = { 10, 0, 0 }, Neck = { -20, 0, 0 },
		RightShoulder = { 60, 0, 110 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 60, 0, -110 }, LeftElbow = { 10, 0, 0 } })),
} }

-- Both hands lift the sentinel out of the ground, palms up.
P.SentinelSummon = { Keys = {
	key(0.3, "Out", wide({ Root = { -20, 0, 0 }, Waist = { -10, 0, 0 },
		RightShoulder = { 40, 20, 0 }, RightElbow = { 20, 0, 0 }, RightWrist = { -60, 0, 0 }, LeftShoulder = { 40, -20, 0 }, LeftElbow = { 20, 0, 0 }, LeftWrist = { -60, 0, 0 } })),
	key(0.65, "InOut", wide({ RootPos = { 0, -0.3, 0 }, Root = { 12, 0, 0 }, Neck = { -25, 0, 0 },
		RightShoulder = { 150, 15, 0 }, RightElbow = { 30, 0, 0 }, RightWrist = { 40, 0, 0 }, LeftShoulder = { 150, -15, 0 }, LeftElbow = { 30, 0, 0 }, LeftWrist = { 40, 0, 0 } })),
	key(0.9, "Out", stance({ Root = { 5, 0, 0 },
		RightShoulder = { 100, 0, 30 }, RightElbow = { 20, 0, 0 }, LeftShoulder = { 100, 0, -30 }, LeftElbow = { 20, 0, 0 } })),
} }

-- ===================== Purple: Arcane Lightning =====================
-- Crouched like a sprinter's start, a lunge with the hand reaching out, three times.
P.Blink = { Keys = {
	key(0.1, "Out", { RootPos = { 0, -1.3, 0 }, Root = { -50, 0, 0 }, Neck = { 40, 0, 0 },
		RightShoulder = { -40, 0, 20 }, RightElbow = { 20, 0, 0 }, LeftShoulder = { -40, 0, -20 }, LeftElbow = { 20, 0, 0 },
		RightHip = { 90, 0, 5 }, RightKnee = { -120, 0, 0 }, LeftHip = { 30, 0, -5 }, LeftKnee = { -100, 0, 0 } }),
	key(0.3, "Snap", { RootPos = { 0, -0.8, 0 }, Root = { -30, 0, 0 }, Neck = { 25, 0, 0 },
		RightShoulder = { 100, 0, 0 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { -60, 0, -20 }, LeftElbow = { 10, 0, 0 },
		RightHip = { -30, 0, 5 }, RightKnee = { -20, 0, 0 }, LeftHip = { 70, 0, -5 }, LeftKnee = { -60, 0, 0 } }),
	key(0.5, "Snap", { RootPos = { 0, -0.8, 0 }, Root = { -30, 0, 0 }, Neck = { 25, 0, 0 },
		RightShoulder = { -60, 0, 20 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 100, 0, 0 }, LeftElbow = { 0, 0, 0 },
		RightHip = { 70, 0, 5 }, RightKnee = { -60, 0, 0 }, LeftHip = { -30, 0, -5 }, LeftKnee = { -20, 0, 0 } }),
	key(0.7, "Snap", { RootPos = { 0, -0.8, 0 }, Root = { -30, 0, 0 }, Neck = { 25, 0, 0 },
		RightShoulder = { 100, 0, 0 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { -60, 0, -20 }, LeftElbow = { 10, 0, 0 },
		RightHip = { -30, 0, 5 }, RightKnee = { -20, 0, 0 }, LeftHip = { 70, 0, -5 }, LeftKnee = { -60, 0, 0 } }),
	key(0.92, "Out", stance({ RootPos = { 0, -0.5, 0 }, Root = { -10, 0, 0 },
		RightShoulder = { 40, 0, 40 }, RightElbow = { 30, 0, 0 }, LeftShoulder = { 40, 0, -40 }, LeftElbow = { 30, 0, 0 } })),
} }

-- Two-handed aim down the right arm, then the recoil throws the body back.
P.Railgun = { Keys = {
	key(0.3, "Out", stance({ RootPos = { 0, -0.5, 0 }, Root = { 0, 35, 0 }, Waist = { 0, 10, 0 }, Neck = { 0, -40, 0 },
		RightShoulder = { 90, -35, 0 }, RightElbow = { 0, 0, 0 }, RightWrist = { 30, 0, 0 }, LeftShoulder = { 85, -60, 0 }, LeftElbow = { 40, 0, 0 } })),
	key(0.5, "Snap", stance({ RootPos = { 0, -0.4, 0 }, Root = { 18, 40, 0 }, Waist = { 10, 10, 0 }, Neck = { -15, -40, 0 },
		RightShoulder = { 120, -35, 0 }, RightElbow = { 20, 0, 0 }, LeftShoulder = { 100, -60, 0 }, LeftElbow = { 50, 0, 0 },
		RightHip = { 10, 0, 10 }, RightKnee = { -20, 0, 0 }, LeftHip = { -35, 0, -10 }, LeftKnee = { -20, 0, 0 } })),
	key(0.9, "Out", stance({ RootPos = { 0, -0.4, 0 }, Root = { 5, 20, 0 }, Neck = { 0, -20, 0 },
		RightShoulder = { 70, -20, 0 }, RightElbow = { 30, 0, 0 }, LeftShoulder = { 30, 0, -30 }, LeftElbow = { 40, 0, 0 } })),
} }

-- Hop with both fists overhead, then drive them into the ground.
P.CageDrive = { Keys = {
	key(0.3, "Out", { Root = { 15, 0, 0 }, Neck = { -20, 0, 0 },
		RightShoulder = { 175, 0, 10 }, RightElbow = { 30, 0, 0 }, LeftShoulder = { 175, 0, -10 }, LeftElbow = { 30, 0, 0 },
		RightHip = { 50, 0, 10 }, RightKnee = { -90, 0, 0 }, LeftHip = { 50, 0, -10 }, LeftKnee = { -90, 0, 0 } }),
	key(0.5, "Snap", wide({ RootPos = { 0, -1.6, 0 }, Root = { -40, 0, 0 }, Waist = { -20, 0, 0 }, Neck = { 30, 0, 0 },
		RightShoulder = { 60, 0, 10 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 60, 0, -10 }, LeftElbow = { 0, 0, 0 },
		RightHip = { 70, 0, 30 }, RightKnee = { -110, 0, 0 }, LeftHip = { 70, 0, -30 }, LeftKnee = { -110, 0, 0 } })),
	key(0.88, "Out", wide({ RootPos = { 0, -1.4, 0 }, Root = { -35, 0, 0 }, Waist = { -20, 0, 0 }, Neck = { 30, 0, 0 },
		RightShoulder = { 55, 0, 15 }, RightElbow = { 5, 0, 0 }, LeftShoulder = { 55, 0, -15 }, LeftElbow = { 5, 0, 0 },
		RightHip = { 70, 0, 30 }, RightKnee = { -110, 0, 0 }, LeftHip = { 70, 0, -30 }, LeftKnee = { -110, 0, 0 } })),
} }

-- Power up: fists at the hips, then a roar to the sky with the arms flexed out.
P.Overload = { Keys = {
	key(0.3, "Out", wide({ Root = { -15, 0, 0 }, Neck = { 15, 0, 0 },
		RightShoulder = { -20, 0, 25 }, RightElbow = { 100, 0, 0 }, LeftShoulder = { -20, 0, -25 }, LeftElbow = { 100, 0, 0 } })),
	key(0.55, "Snap", wide({ RootPos = { 0, -0.4, 0 }, Root = { 18, 0, 0 }, Waist = { 10, 0, 0 }, Neck = { -35, 0, 0 },
		RightShoulder = { 20, 0, 95 }, RightElbow = { 90, 0, 0 }, LeftShoulder = { 20, 0, -95 }, LeftElbow = { 90, 0, 0 } })),
	key(0.9, "Out", wide({ RootPos = { 0, -0.4, 0 }, Root = { 12, 0, 0 }, Neck = { -25, 0, 0 },
		RightShoulder = { 20, 0, 90 }, RightElbow = { 95, 0, 0 }, LeftShoulder = { 20, 0, -90 }, LeftElbow = { 95, 0, 0 } })),
} }

-- ===================== Red: Fire =====================
-- A tucked leap, a head-first dive with the arms ahead, a crouched landing.
P.CometLeap = { Keys = {
	key(0.25, "Out", tuck({ Root = { -30, 0, 0 }, Neck = { 20, 0, 0 },
		RightShoulder = { 140, 0, 30 }, RightElbow = { 40, 0, 0 }, LeftShoulder = { 140, 0, -30 }, LeftElbow = { 40, 0, 0 } })),
	key(0.6, "InOut", { Root = { -75, 0, 0 }, Neck = { 50, 0, 0 },
		RightShoulder = { 170, 0, 8 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 170, 0, -8 }, LeftElbow = { 0, 0, 0 },
		RightHip = { -10, 0, 5 }, RightKnee = { -15, 0, 0 }, LeftHip = { -10, 0, -5 }, LeftKnee = { -15, 0, 0 } }),
	key(0.75, "Snap", wide({ RootPos = { 0, -1.6, 0 }, Root = { -30, 0, 0 }, Neck = { 20, 0, 0 },
		RightShoulder = { 40, 0, 60 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 40, 0, -60 }, LeftElbow = { 10, 0, 0 },
		RightHip = { 80, 0, 25 }, RightKnee = { -120, 0, 0 }, LeftHip = { 80, 0, -25 }, LeftKnee = { -120, 0, 0 } })),
	key(0.95, "Out", stance({ RootPos = { 0, -0.6, 0 }, Root = { -10, 0, 0 },
		RightShoulder = { 30, 0, 40 }, RightElbow = { 20, 0, 0 }, LeftShoulder = { 30, 0, -40 }, LeftElbow = { 20, 0, 0 } })),
} }

-- Palms together at the mouth, sweeping the torrent left to right.
P.DragonBreath = { Keys = {
	key(0.2, "Out", wide({ Root = { -10, 55, 0 }, Waist = { 0, 15, 0 }, Neck = { 10, 0, 0 },
		RightShoulder = { 95, 25, 0 }, RightElbow = { 30, 0, 0 }, RightWrist = { 40, 0, 0 }, LeftShoulder = { 95, -25, 0 }, LeftElbow = { 30, 0, 0 }, LeftWrist = { 40, 0, 0 } })),
	key(0.85, "InOut", wide({ Root = { -10, -55, 0 }, Waist = { 0, -15, 0 }, Neck = { 10, 0, 0 },
		RightShoulder = { 95, 25, 0 }, RightElbow = { 30, 0, 0 }, RightWrist = { 40, 0, 0 }, LeftShoulder = { 95, -25, 0 }, LeftElbow = { 30, 0, 0 }, LeftWrist = { 40, 0, 0 } })),
	key(0.97, "Out", stance({ Root = { 0, -20, 0 },
		RightShoulder = { 40, 0, 30 }, RightElbow = { 30, 0, 0 }, LeftShoulder = { 40, 0, -30 }, LeftElbow = { 30, 0, 0 } })),
} }

-- Knee high, then a stomp that splits the earth, arms flung wide.
P.EruptionStomp = { Keys = {
	key(0.3, "Out", { RootPos = { 0, 0.2, 0 }, Root = { 10, 0, 0 }, Neck = { -10, 0, 0 },
		RightShoulder = { 60, 0, 60 }, RightElbow = { 80, 0, 0 }, LeftShoulder = { 60, 0, -60 }, LeftElbow = { 80, 0, 0 },
		RightHip = { 110, 0, 10 }, RightKnee = { -110, 0, 0 }, LeftHip = { 0, 0, -5 }, LeftKnee = { -10, 0, 0 } }),
	key(0.45, "Snap", wide({ RootPos = { 0, -1.3, 0 }, Root = { -20, 0, 0 }, Neck = { 15, 0, 0 },
		RightShoulder = { 0, 0, 100 }, RightElbow = { 20, 0, 0 }, LeftShoulder = { 0, 0, -100 }, LeftElbow = { 20, 0, 0 },
		RightHip = { 50, 0, 35 }, RightKnee = { -80, 0, 0 }, LeftHip = { 50, 0, -35 }, LeftKnee = { -80, 0, 0 } })),
	key(0.9, "Out", wide({ RootPos = { 0, -1.1, 0 }, Root = { -10, 0, 0 },
		RightShoulder = { 20, 0, 90 }, RightElbow = { 30, 0, 0 }, LeftShoulder = { 20, 0, -90 }, LeftElbow = { 30, 0, 0 } })),
} }

-- Arms swept back and up like wings, chest high, rising onto the toes.
P.PhoenixRise = { Keys = {
	key(0.3, "Out", { RootPos = { 0, -0.8, 0 }, Root = { -25, 0, 0 }, Waist = { -15, 0, 0 }, Neck = { 15, 0, 0 },
		RightShoulder = { -40, 0, 40 }, RightElbow = { 20, 0, 0 }, LeftShoulder = { -40, 0, -40 }, LeftElbow = { 20, 0, 0 },
		RightHip = { 40, 0, 10 }, RightKnee = { -70, 0, 0 }, LeftHip = { 40, 0, -10 }, LeftKnee = { -70, 0, 0 } }),
	key(0.6, "InOut", { RootPos = { 0, 0.4, 0 }, Root = { 15, 0, 0 }, Waist = { 10, 0, 0 }, Neck = { -30, 0, 0 },
		RightShoulder = { -30, 0, 130 }, RightElbow = { 20, 0, 0 }, LeftShoulder = { -30, 0, -130 }, LeftElbow = { 20, 0, 0 },
		RightHip = { -5, 0, 5 }, RightKnee = { 0, 0, 0 }, LeftHip = { -5, 0, -5 }, LeftKnee = { 0, 0, 0 } }),
	key(0.92, "Out", stance({ Root = { 8, 0, 0 }, Neck = { -15, 0, 0 },
		RightShoulder = { -10, 0, 110 }, RightElbow = { 20, 0, 0 }, LeftShoulder = { -10, 0, -110 }, LeftElbow = { 20, 0, 0 } })),
} }

-- ===================== Black: Smoke Storm =====================
-- A surfer's stance, side-on, knees soft, arms out for balance.
P.CloudSurf = { Keys = {
	key(0.15, "Out", { RootPos = { 0, -0.9, 0 }, Root = { -5, 70, 0 }, Waist = { 0, -15, 0 }, Neck = { 0, -55, 0 },
		RightShoulder = { 10, 0, 70 }, RightElbow = { 20, 0, 0 }, LeftShoulder = { 30, 0, -80 }, LeftElbow = { 20, 0, 0 },
		RightHip = { 35, 0, 25 }, RightKnee = { -70, 0, 0 }, LeftHip = { 35, 0, -25 }, LeftKnee = { -70, 0, 0 } }),
	key(0.55, "InOut", { RootPos = { 0, -1.1, 0 }, Root = { -12, 70, 8 }, Waist = { 0, -15, 0 }, Neck = { 0, -55, 0 },
		RightShoulder = { 0, 0, 55 }, RightElbow = { 30, 0, 0 }, LeftShoulder = { 40, 0, -95 }, LeftElbow = { 10, 0, 0 },
		RightHip = { 45, 0, 25 }, RightKnee = { -85, 0, 0 }, LeftHip = { 30, 0, -25 }, LeftKnee = { -60, 0, 0 } }),
	key(0.95, "Out", stance({ RootPos = { 0, -0.5, 0 }, Root = { 0, 20, 0 },
		RightShoulder = { 20, 0, 50 }, RightElbow = { 20, 0, 0 }, LeftShoulder = { 20, 0, -50 }, LeftElbow = { 20, 0, 0 } })),
} }

-- The right arm calls to the sky, then sweeps down to point along the line.
P.SpearCall = { Keys = {
	key(0.25, "Out", stance({ Root = { 12, 0, 0 }, Neck = { -35, 0, 0 },
		RightShoulder = { 175, 0, 5 }, RightElbow = { 0, 0, 0 }, RightWrist = { -60, 0, 0 }, LeftShoulder = { 20, 0, -40 }, LeftElbow = { 60, 0, 0 } })),
	key(0.5, "Snap", stance({ RootPos = { 0, -0.5, 0 }, Root = { -10, 0, 0 }, Neck = { 5, 0, 0 },
		RightShoulder = { 85, 0, 5 }, RightElbow = { 0, 0, 0 }, RightWrist = { -60, 0, 0 }, LeftShoulder = { -20, 0, -40 }, LeftElbow = { 20, 0, 0 } })),
	key(0.9, "Out", stance({ RootPos = { 0, -0.5, 0 }, Root = { -10, 0, 0 },
		RightShoulder = { 85, 0, 5 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { -20, 0, -40 }, LeftElbow = { 20, 0, 0 } })),
} }

-- A low spin with the arms flung wide, then pulled in tight as the storm collapses.
P.TempestSpin = { Keys = {
	key(0.35, "Out", wide({ RootPos = { 0, -1, 0 }, Root = { -10, -360, 0 },
		RightShoulder = { 10, 0, 95 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 10, 0, -95 }, LeftElbow = { 0, 0, 0 } })),
	key(0.65, "InOut", wide({ RootPos = { 0, -1.2, 0 }, Root = { -20, -540, 0 }, Waist = { -10, 0, 0 },
		RightShoulder = { 70, 40, 0 }, RightElbow = { 110, 0, 0 }, LeftShoulder = { 70, -40, 0 }, LeftElbow = { 110, 0, 0 } })),
	key(0.92, "Out", wide({ RootPos = { 0, -0.9, 0 }, Root = { 10, -720, 0 }, Neck = { -20, 0, 0 },
		RightShoulder = { 30, 0, 110 }, RightElbow = { 20, 0, 0 }, LeftShoulder = { 30, 0, -110 }, LeftElbow = { 20, 0, 0 } })),
} }

-- A hand seal at the chest, then arms thrown out as the clones split away.
P.CloneSplit = { Keys = {
	key(0.35, "Out", stance({ RootPos = { 0, -0.6, 0 }, Neck = { 10, 0, 0 },
		RightShoulder = { 55, 50, 0 }, RightElbow = { 110, 0, 0 }, RightWrist = { 50, 0, 0 }, LeftShoulder = { 55, -50, 0 }, LeftElbow = { 110, 0, 0 }, LeftWrist = { 50, 0, 0 } })),
	key(0.55, "Snap", wide({ Root = { 5, 0, 0 },
		RightShoulder = { 20, 0, 115 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 20, 0, -115 }, LeftElbow = { 0, 0, 0 } })),
	key(0.9, "Out", stance({ RootPos = { 0, -0.5, 0 },
		RightShoulder = { 20, 0, 60 }, RightElbow = { 30, 0, 0 }, LeftShoulder = { 20, 0, -60 }, LeftElbow = { 30, 0, 0 } })),
} }

-- ===================== White: Holy Light =====================
-- Arms straight up, rising onto the toes; then a downward strike from the sky.
P.Ascend = { Keys = {
	key(0.35, "Out", { RootPos = { 0, 0.4, 0 }, Root = { 8, 0, 0 }, Neck = { -35, 0, 0 },
		RightShoulder = { 178, 0, 5 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 178, 0, -5 }, LeftElbow = { 0, 0, 0 },
		RightHip = { -5, 0, 3 }, RightKnee = { -5, 0, 0 }, LeftHip = { -5, 0, -3 }, LeftKnee = { -5, 0, 0 } }),
	key(0.7, "Snap", wide({ RootPos = { 0, -1.5, 0 }, Root = { -45, 0, 0 }, Neck = { 30, 0, 0 },
		RightShoulder = { 20, 0, 10 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 20, 0, -10 }, LeftElbow = { 0, 0, 0 },
		RightHip = { 80, 0, 20 }, RightKnee = { -110, 0, 0 }, LeftHip = { 80, 0, -20 }, LeftKnee = { -110, 0, 0 } })),
	key(0.95, "Out", stance({ RootPos = { 0, -0.6, 0 }, Root = { -10, 0, 0 },
		RightShoulder = { 30, 0, 30 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 30, 0, -30 }, LeftElbow = { 10, 0, 0 } })),
} }

-- Hands form a triangle before the face, then push the beam through it.
P.PrismCast = { Keys = {
	key(0.35, "Out", stance({ Neck = { 5, 0, 0 },
		RightShoulder = { 110, 40, 0 }, RightElbow = { 80, 0, 0 }, RightWrist = { 40, 0, 0 }, LeftShoulder = { 110, -40, 0 }, LeftElbow = { 80, 0, 0 }, LeftWrist = { 40, 0, 0 } })),
	key(0.55, "Snap", stance({ RootPos = { 0, -0.5, 0 }, Root = { -12, 0, 0 },
		RightShoulder = { 95, 15, 0 }, RightElbow = { 5, 0, 0 }, RightWrist = { 50, 0, 0 }, LeftShoulder = { 95, -15, 0 }, LeftElbow = { 5, 0, 0 }, LeftWrist = { 50, 0, 0 } })),
	key(0.9, "Out", stance({ RootPos = { 0, -0.5, 0 }, Root = { -10, 0, 0 },
		RightShoulder = { 92, 15, 0 }, RightElbow = { 8, 0, 0 }, LeftShoulder = { 92, -15, 0 }, LeftElbow = { 8, 0, 0 } })),
} }

-- An open palm raised to heaven, a hand on the heart; then the verdict falls.
P.JudgmentRaise = { Keys = {
	key(0.35, "Out", stance({ Root = { 10, 0, 0 }, Neck = { -30, 0, 0 },
		RightShoulder = { 170, 0, 20 }, RightElbow = { 10, 0, 0 }, RightWrist = { 40, 0, 0 }, LeftShoulder = { 30, 45, 0 }, LeftElbow = { 120, 0, 0 } })),
	key(0.75, "InOut", stance({ RootPos = { 0, -0.4, 0 }, Root = { 10, 0, 0 }, Neck = { -25, 0, 0 },
		RightShoulder = { 175, 0, 15 }, RightElbow = { 0, 0, 0 }, RightWrist = { 40, 0, 0 }, LeftShoulder = { 30, 45, 0 }, LeftElbow = { 120, 0, 0 } })),
	key(0.9, "Snap", wide({ Root = { -25, 0, 0 }, Neck = { 15, 0, 0 },
		RightShoulder = { 60, 0, 20 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 30, 45, 0 }, LeftElbow = { 120, 0, 0 } })),
} }

-- Kneel with the hands together in prayer, head bowed.
P.Pray = { Keys = {
	key(0.4, "Out", { RootPos = { 0, -1.6, 0 }, Root = { -5, 0, 0 }, Neck = { 30, 0, 0 },
		RightShoulder = { 50, 40, 0 }, RightElbow = { 110, 0, 0 }, RightWrist = { 20, 0, 0 }, LeftShoulder = { 50, -40, 0 }, LeftElbow = { 110, 0, 0 }, LeftWrist = { 20, 0, 0 },
		RightHip = { 90, 0, 5 }, RightKnee = { -90, 0, 0 }, LeftHip = { -5, 0, -5 }, LeftKnee = { -110, 0, 0 } }),
	key(0.9, "InOut", { RootPos = { 0, -1.6, 0 }, Root = { -5, 0, 0 }, Neck = { 20, 0, 0 },
		RightShoulder = { 55, 40, 0 }, RightElbow = { 105, 0, 0 }, RightWrist = { 20, 0, 0 }, LeftShoulder = { 55, -40, 0 }, LeftElbow = { 105, 0, 0 }, LeftWrist = { 20, 0, 0 },
		RightHip = { 90, 0, 5 }, RightKnee = { -90, 0, 0 }, LeftHip = { -5, 0, -5 }, LeftKnee = { -110, 0, 0 } }),
} }

-- ===================== Gold: Sun =====================
-- A lowered-shoulder charge.
P.ShoulderCharge = { Keys = {
	key(0.15, "Out", { RootPos = { 0, -0.9, 0 }, Root = { -35, 35, 0 }, Waist = { -10, 10, 0 }, Neck = { 20, -35, 0 },
		RightShoulder = { 30, 60, 0 }, RightElbow = { 100, 0, 0 }, LeftShoulder = { -30, 0, -20 }, LeftElbow = { 60, 0, 0 },
		RightHip = { 60, 0, 5 }, RightKnee = { -80, 0, 0 }, LeftHip = { -30, 0, -5 }, LeftKnee = { -40, 0, 0 } }),
	key(0.55, "Linear", { RootPos = { 0, -0.9, 0 }, Root = { -35, 35, 0 }, Waist = { -10, 10, 0 }, Neck = { 20, -35, 0 },
		RightShoulder = { 30, 60, 0 }, RightElbow = { 100, 0, 0 }, LeftShoulder = { -30, 0, -20 }, LeftElbow = { 60, 0, 0 },
		RightHip = { -30, 0, 5 }, RightKnee = { -40, 0, 0 }, LeftHip = { 60, 0, -5 }, LeftKnee = { -80, 0, 0 } }),
	key(0.9, "Out", wide({ Root = { 10, 0, 0 }, Neck = { -20, 0, 0 },
		RightShoulder = { 40, 0, 110 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 40, 0, -110 }, LeftElbow = { 10, 0, 0 } })),
} }

-- A javelin throw: arm cocked back high, the other pointing the way; then the throw.
P.Javelin = { Keys = {
	key(0.35, "Out", stance({ RootPos = { 0, -0.4, 0 }, Root = { 12, 40, 0 }, Waist = { 5, 15, 0 }, Neck = { 0, -50, 0 },
		RightShoulder = { 150, 0, 40 }, RightElbow = { 40, 0, 0 }, RightWrist = { -30, 0, 0 }, LeftShoulder = { 90, -60, 0 }, LeftElbow = { 0, 0, 0 } })),
	key(0.5, "Snap", stance({ RootPos = { 0, -0.6, 0 }, Root = { -20, -20, 0 }, Waist = { -10, -10, 0 }, Neck = { 10, 20, 0 },
		RightShoulder = { 100, -20, 0 }, RightElbow = { 0, 0, 0 }, RightWrist = { -50, 0, 0 }, LeftShoulder = { -20, 0, -45 }, LeftElbow = { 20, 0, 0 },
		RightHip = { -30, 0, 10 }, RightKnee = { -20, 0, 0 }, LeftHip = { 50, 0, -10 }, LeftKnee = { -50, 0, 0 } })),
	key(0.9, "Out", stance({ RootPos = { 0, -0.5, 0 }, Root = { -15, -25, 0 }, Neck = { 10, 25, 0 },
		RightShoulder = { 80, -30, 0 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { -20, 0, -45 }, LeftElbow = { 20, 0, 0 } })),
} }

-- Curl up tight around the gathering light, then burst open into a star.
P.NovaCharge = { Keys = {
	key(0.55, "Out", { RootPos = { 0, -1.5, 0 }, Root = { -30, 0, 0 }, Waist = { -20, 0, 0 }, Neck = { 30, 0, 0 },
		RightShoulder = { 70, 55, 0 }, RightElbow = { 120, 0, 0 }, LeftShoulder = { 70, -55, 0 }, LeftElbow = { 120, 0, 0 },
		RightHip = { 90, 0, 10 }, RightKnee = { -120, 0, 0 }, LeftHip = { 90, 0, -10 }, LeftKnee = { -120, 0, 0 } }),
	key(0.68, "Snap", { RootPos = { 0, 0.3, 0 }, Root = { 15, 0, 0 }, Neck = { -30, 0, 0 },
		RightShoulder = { 30, 0, 140 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 30, 0, -140 }, LeftElbow = { 0, 0, 0 },
		RightHip = { 0, 0, 35 }, RightKnee = { 0, 0, 0 }, LeftHip = { 0, 0, -35 }, LeftKnee = { 0, 0, 0 } }),
	key(0.95, "Out", wide({ Root = { 5, 0, 0 },
		RightShoulder = { 20, 0, 100 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 20, 0, -100 }, LeftElbow = { 10, 0, 0 } })),
} }

-- Both hands lift a crown above the head and set it down; then arms out, triumphant.
P.CrownRaise = { Keys = {
	key(0.35, "Out", stance({ Neck = { -20, 0, 0 },
		RightShoulder = { 160, 25, 0 }, RightElbow = { 40, 0, 0 }, LeftShoulder = { 160, -25, 0 }, LeftElbow = { 40, 0, 0 } })),
	key(0.6, "InOut", stance({ Neck = { 5, 0, 0 },
		RightShoulder = { 150, 30, 0 }, RightElbow = { 90, 0, 0 }, LeftShoulder = { 150, -30, 0 }, LeftElbow = { 90, 0, 0 } })),
	key(0.9, "Out", wide({ Root = { 10, 0, 0 }, Neck = { -15, 0, 0 },
		RightShoulder = { 30, 0, 120 }, RightElbow = { 15, 0, 0 }, LeftShoulder = { 30, 0, -120 }, LeftElbow = { 15, 0, 0 } })),
} }

-- ===================== Crimson: Blood =====================
-- Low and fast, blade arm trailing; the body twists through each cut.
P.RendDash = { Keys = {
	key(0.15, "Out", { RootPos = { 0, -1.1, 0 }, Root = { -40, -25, 0 }, Waist = { -10, -15, 0 }, Neck = { 30, 30, 0 },
		RightShoulder = { -50, 0, 40 }, RightElbow = { 10, 0, 0 }, RightWrist = { -40, 0, 0 }, LeftShoulder = { 30, 0, -40 }, LeftElbow = { 60, 0, 0 },
		RightHip = { 70, 0, 5 }, RightKnee = { -90, 0, 0 }, LeftHip = { -30, 0, -5 }, LeftKnee = { -50, 0, 0 } }),
	key(0.4, "Snap", { RootPos = { 0, -1.1, 0 }, Root = { -40, 30, 0 }, Waist = { -10, 15, 0 }, Neck = { 30, -30, 0 },
		RightShoulder = { 90, -70, 20 }, RightElbow = { 0, 0, 0 }, RightWrist = { -50, 0, 0 }, LeftShoulder = { -20, 0, -40 }, LeftElbow = { 20, 0, 0 },
		RightHip = { -30, 0, 5 }, RightKnee = { -50, 0, 0 }, LeftHip = { 70, 0, -5 }, LeftKnee = { -90, 0, 0 } }),
	key(0.65, "Snap", { RootPos = { 0, -1.1, 0 }, Root = { -40, -25, 0 }, Waist = { -10, -15, 0 }, Neck = { 30, 30, 0 },
		RightShoulder = { -50, 0, 40 }, RightElbow = { 10, 0, 0 }, RightWrist = { -40, 0, 0 }, LeftShoulder = { 30, 0, -40 }, LeftElbow = { 60, 0, 0 },
		RightHip = { 70, 0, 5 }, RightKnee = { -90, 0, 0 }, LeftHip = { -30, 0, -5 }, LeftKnee = { -50, 0, 0 } }),
	key(0.9, "Snap", { RootPos = { 0, -1.2, 0 }, Root = { -30, 40, 0 }, Waist = { -10, 15, 0 }, Neck = { 30, -30, 0 },
		RightShoulder = { 85, -80, 20 }, RightElbow = { 0, 0, 0 }, RightWrist = { -50, 0, 0 }, LeftShoulder = { -20, 0, -40 }, LeftElbow = { 20, 0, 0 },
		RightHip = { 80, 0, 10 }, RightKnee = { -100, 0, 0 }, LeftHip = { -30, 0, -10 }, LeftKnee = { -40, 0, 0 } }),
} }

-- Whirl the scythe overhead with both hands, then hurl it low from left to right.
P.ScytheFling = { Keys = {
	key(0.3, "Out", stance({ Root = { 5, 50, 0 }, Neck = { -10, -40, 0 },
		RightShoulder = { 160, 40, 0 }, RightElbow = { 30, 0, 0 }, LeftShoulder = { 160, -10, 0 }, LeftElbow = { 40, 0, 0 } })),
	key(0.5, "Snap", wide({ Root = { -20, -60, 0 }, Waist = { -10, -20, 0 }, Neck = { 10, 50, 0 },
		RightShoulder = { 60, -60, 70 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 30, 0, -80 }, LeftElbow = { 10, 0, 0 } })),
	key(0.9, "Out", wide({ Root = { -15, -55, 0 }, Neck = { 10, 50, 0 },
		RightShoulder = { 40, -60, 80 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 20, 0, -70 }, LeftElbow = { 20, 0, 0 } })),
} }

-- One arm raised to call the moon, the other down; the head thrown back.
P.MoonCall = { Keys = {
	key(0.4, "Out", stance({ Root = { 12, 0, 0 }, Waist = { 8, 0, 0 }, Neck = { -40, 0, 0 },
		RightShoulder = { 20, 0, 30 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 165, 0, -25 }, LeftElbow = { 10, 0, 0 }, LeftWrist = { 40, 0, 0 } })),
	key(0.9, "InOut", stance({ RootPos = { 0, -0.3, 0 }, Root = { 15, 0, 0 }, Waist = { 10, 0, 0 }, Neck = { -45, 0, 0 },
		RightShoulder = { 10, 0, 45 }, RightElbow = { 15, 0, 0 }, LeftShoulder = { 172, 0, -20 }, LeftElbow = { 0, 0, 0 }, LeftWrist = { 40, 0, 0 } })),
} }

-- Draw the blade across the open palm, then clench the bleeding fist to the chest.
P.PactCut = { Keys = {
	key(0.35, "Out", stance({ Neck = { 25, 0, 0 },
		RightShoulder = { 60, 50, 0 }, RightElbow = { 70, 0, 0 }, RightWrist = { -20, 0, 0 }, LeftShoulder = { 60, -20, 0 }, LeftElbow = { 60, 0, 0 }, LeftWrist = { 60, 0, 0 } })),
	key(0.5, "Snap", stance({ Neck = { 20, 0, 0 },
		RightShoulder = { 60, -30, 30 }, RightElbow = { 30, 0, 0 }, RightWrist = { -20, 0, 0 }, LeftShoulder = { 60, -20, 0 }, LeftElbow = { 60, 0, 0 }, LeftWrist = { 60, 0, 0 } })),
	key(0.9, "Out", wide({ Root = { -20, 0, 0 }, Waist = { -10, 0, 0 }, Neck = { 15, 0, 0 },
		RightShoulder = { 20, 0, 50 }, RightElbow = { 60, 0, 0 }, LeftShoulder = { 50, 50, 0 }, LeftElbow = { 130, 0, 0 } })),
} }

-- ===================== Shadow: Darkness =====================
-- Melt down into the shadow, then rise behind them with a backhand strike.
P.ShadowSink = { Keys = {
	key(0.3, "In", { RootPos = { 0, -2.4, 0 }, Root = { -10, 0, 0 }, Neck = { 30, 0, 0 },
		RightShoulder = { 20, 40, 0 }, RightElbow = { 120, 0, 0 }, LeftShoulder = { 20, -40, 0 }, LeftElbow = { 120, 0, 0 },
		RightHip = { 110, 0, 10 }, RightKnee = { -140, 0, 0 }, LeftHip = { 110, 0, -10 }, LeftKnee = { -140, 0, 0 } }),
	key(0.55, "Snap", stance({ RootPos = { 0, -0.6, 0 }, Root = { -15, -70, 0 }, Waist = { 0, -20, 0 }, Neck = { 0, 60, 0 },
		RightShoulder = { 90, -80, 30 }, RightElbow = { 0, 0, 0 }, RightWrist = { -50, 0, 0 }, LeftShoulder = { -20, 0, -40 }, LeftElbow = { 20, 0, 0 } })),
	key(0.9, "Out", stance({ RootPos = { 0, -0.6, 0 }, Root = { -10, -60, 0 }, Neck = { 0, 55, 0 },
		RightShoulder = { 80, -80, 30 }, RightElbow = { 5, 0, 0 }, LeftShoulder = { -20, 0, -40 }, LeftElbow = { 20, 0, 0 } })),
} }

-- One arm undulates forward like a striking snake.
P.SerpentCast = { Keys = {
	key(0.2, "Out", stance({ Root = { 0, 20, 0 },
		RightShoulder = { 60, 30, 0 }, RightElbow = { 100, 0, 0 }, RightWrist = { 40, 0, 0 }, LeftShoulder = { 20, 0, -30 }, LeftElbow = { 40, 0, 0 } })),
	key(0.4, "InOut", stance({ Root = { -5, 0, 0 },
		RightShoulder = { 100, 0, 15 }, RightElbow = { 50, 0, 0 }, RightWrist = { -40, 0, 0 }, LeftShoulder = { 20, 0, -30 }, LeftElbow = { 40, 0, 0 } })),
	key(0.6, "InOut", stance({ Root = { -10, -10, 0 },
		RightShoulder = { 80, -10, 0 }, RightElbow = { 20, 0, 0 }, RightWrist = { 40, 0, 0 }, LeftShoulder = { 20, 0, -30 }, LeftElbow = { 40, 0, 0 } })),
	key(0.85, "Snap", stance({ RootPos = { 0, -0.5, 0 }, Root = { -15, -15, 0 },
		RightShoulder = { 95, -10, 0 }, RightElbow = { 0, 0, 0 }, RightWrist = { -50, 0, 0 }, LeftShoulder = { -20, 0, -40 }, LeftElbow = { 20, 0, 0 } })),
} }

-- Clawed hands rise from low and clench, dragging the darkness down.
P.NightGrasp = { Keys = {
	key(0.3, "Out", wide({ RootPos = { 0, -1.3, 0 }, Root = { -30, 0, 0 }, Neck = { 25, 0, 0 },
		RightShoulder = { 20, 0, 30 }, RightElbow = { 20, 0, 0 }, RightWrist = { 60, 0, 0 }, LeftShoulder = { 20, 0, -30 }, LeftElbow = { 20, 0, 0 }, LeftWrist = { 60, 0, 0 } })),
	key(0.6, "InOut", wide({ Root = { 10, 0, 0 }, Neck = { -20, 0, 0 },
		RightShoulder = { 140, 0, 40 }, RightElbow = { 30, 0, 0 }, RightWrist = { 60, 0, 0 }, LeftShoulder = { 140, 0, -40 }, LeftElbow = { 30, 0, 0 }, LeftWrist = { 60, 0, 0 } })),
	key(0.8, "Snap", wide({ RootPos = { 0, -1.2, 0 }, Root = { -25, 0, 0 }, Neck = { 20, 0, 0 },
		RightShoulder = { 50, 0, 30 }, RightElbow = { 100, 0, 0 }, LeftShoulder = { 50, 0, -30 }, LeftElbow = { 100, 0, 0 } })),
} }

-- Arms crossed over the face, then a hunched, prowling stance.
P.RealmStep = { Keys = {
	key(0.35, "Out", stance({ Neck = { 20, 0, 0 },
		RightShoulder = { 110, 55, 0 }, RightElbow = { 110, 0, 0 }, LeftShoulder = { 110, -55, 0 }, LeftElbow = { 110, 0, 0 } })),
	key(0.75, "InOut", { RootPos = { 0, -1, 0 }, Root = { -30, 0, 0 }, Waist = { -15, 0, 0 }, Neck = { 35, 0, 0 },
		RightShoulder = { -30, 0, 30 }, RightElbow = { 30, 0, 0 }, LeftShoulder = { -30, 0, -30 }, LeftElbow = { 30, 0, 0 },
		RightHip = { 60, 0, 10 }, RightKnee = { -100, 0, 0 }, LeftHip = { 20, 0, -10 }, LeftKnee = { -70, 0, 0 } }),
} }

-- ===================== Celestial: Cosmic =====================
-- Trace a circle in the air with the right hand, then step through it.
P.GateOpen = { Keys = {
	key(0.15, "Out", stance({ RightShoulder = { 160, 0, 30 }, RightElbow = { 5, 0, 0 }, LeftShoulder = { 20, 0, -30 }, LeftElbow = { 40, 0, 0 } })),
	key(0.3, "Linear", stance({ RightShoulder = { 90, 0, 90 }, RightElbow = { 5, 0, 0 }, LeftShoulder = { 20, 0, -30 }, LeftElbow = { 40, 0, 0 } })),
	key(0.45, "Linear", stance({ RightShoulder = { 30, 0, 20 }, RightElbow = { 5, 0, 0 }, LeftShoulder = { 20, 0, -30 }, LeftElbow = { 40, 0, 0 } })),
	key(0.6, "Linear", stance({ RightShoulder = { 90, -50, 0 }, RightElbow = { 5, 0, 0 }, LeftShoulder = { 20, 0, -30 }, LeftElbow = { 40, 0, 0 } })),
	key(0.85, "Out", { RootPos = { 0, -0.6, 0 }, Root = { -25, 0, 0 }, Neck = { 20, 0, 0 },
		RightShoulder = { 80, 0, 10 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { -30, 0, -20 }, LeftElbow = { 10, 0, 0 },
		RightHip = { 60, 0, 5 }, RightKnee = { -50, 0, 0 }, LeftHip = { -30, 0, -5 }, LeftKnee = { -30, 0, 0 } }),
} }

-- An archer aiming at the sky: draw to the cheek, hold, release.
P.BowDraw = { Keys = {
	key(0.3, "Out", stance({ Root = { 15, 70, 0 }, Waist = { 5, 10, 0 }, Neck = { -30, -70, 0 },
		LeftShoulder = { 130, -70, 0 }, LeftElbow = { 0, 0, 0 }, RightShoulder = { 130, 60, 0 }, RightElbow = { 130, 0, 0 } })),
	key(0.55, "InOut", stance({ Root = { 18, 70, 0 }, Waist = { 5, 10, 0 }, Neck = { -32, -70, 0 },
		LeftShoulder = { 135, -70, 0 }, LeftElbow = { 0, 0, 0 }, RightShoulder = { 120, 80, 0 }, RightElbow = { 150, 0, 0 } })),
	key(0.65, "Snap", stance({ Root = { 18, 70, 0 }, Waist = { 5, 10, 0 }, Neck = { -32, -70, 0 },
		LeftShoulder = { 135, -70, 0 }, LeftElbow = { 0, 0, 0 }, RightShoulder = { 90, 20, 60 }, RightElbow = { 20, 0, 0 } })),
	key(0.95, "Out", stance({ Root = { 5, 40, 0 }, Neck = { -15, -40, 0 },
		LeftShoulder = { 100, -60, 0 }, LeftElbow = { 10, 0, 0 }, RightShoulder = { 40, 0, 50 }, RightElbow = { 20, 0, 0 } })),
} }

-- Point out star after star, then close the fist and pull them down.
P.StarMark = { Keys = {
	key(0.15, "Out", stance({ Root = { 5, 40, 0 }, Neck = { -20, 0, 0 }, RightShoulder = { 140, 20, 0 }, RightElbow = { 0, 0, 0 }, RightWrist = { -60, 0, 0 }, LeftShoulder = { 20, 0, -30 }, LeftElbow = { 40, 0, 0 } })),
	key(0.3, "Snap", stance({ Root = { 5, 10, 0 }, Neck = { -20, 0, 0 }, RightShoulder = { 130, 0, 40 }, RightElbow = { 0, 0, 0 }, RightWrist = { -60, 0, 0 }, LeftShoulder = { 20, 0, -30 }, LeftElbow = { 40, 0, 0 } })),
	key(0.45, "Snap", stance({ Root = { 5, -25, 0 }, Neck = { -20, 0, 0 }, RightShoulder = { 140, -10, 50 }, RightElbow = { 0, 0, 0 }, RightWrist = { -60, 0, 0 }, LeftShoulder = { 20, 0, -30 }, LeftElbow = { 40, 0, 0 } })),
	key(0.6, "Snap", stance({ Root = { 5, -50, 0 }, Neck = { -20, 0, 0 }, RightShoulder = { 120, -20, 30 }, RightElbow = { 0, 0, 0 }, RightWrist = { -60, 0, 0 }, LeftShoulder = { 20, 0, -30 }, LeftElbow = { 40, 0, 0 } })),
	key(0.85, "Snap", wide({ Root = { -25, 0, 0 }, Neck = { 20, 0, 0 }, RightShoulder = { 40, 0, 20 }, RightElbow = { 90, 0, 0 }, LeftShoulder = { 20, 0, -40 }, LeftElbow = { 40, 0, 0 } })),
} }

-- A palm thrust out: stop. The rest of the body freezes mid-motion.
P.ClockStop = { Keys = {
	key(0.25, "Out", stance({ Root = { 5, 30, 0 }, RightShoulder = { 60, 40, 0 }, RightElbow = { 110, 0, 0 }, LeftShoulder = { 20, 0, -30 }, LeftElbow = { 40, 0, 0 } })),
	key(0.4, "Snap", stance({ RootPos = { 0, -0.5, 0 }, Root = { -10, -10, 0 }, Neck = { 5, 0, 0 },
		RightShoulder = { 92, -10, 0 }, RightElbow = { 0, 0, 0 }, RightWrist = { 70, 0, 0 }, LeftShoulder = { -40, 0, -30 }, LeftElbow = { 30, 0, 0 } })),
	key(0.95, "Linear", stance({ RootPos = { 0, -0.5, 0 }, Root = { -10, -10, 0 }, Neck = { 5, 0, 0 },
		RightShoulder = { 92, -10, 0 }, RightElbow = { 0, 0, 0 }, RightWrist = { 70, 0, 0 }, LeftShoulder = { -40, 0, -30 }, LeftElbow = { 30, 0, 0 } })),
} }

-- ===================== Void: Gravity =====================
-- Drawn back as if a sling were stretched, then flung forward like a bolt.
P.Slingshot = { Keys = {
	key(0.3, "Out", { RootPos = { 0, -1.2, 0 }, Root = { 20, 0, 0 }, Waist = { 10, 0, 0 }, Neck = { -10, 0, 0 },
		RightShoulder = { 100, 0, 10 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 100, 0, -10 }, LeftElbow = { 10, 0, 0 },
		RightHip = { 60, 0, 10 }, RightKnee = { -100, 0, 0 }, LeftHip = { 20, 0, -10 }, LeftKnee = { -110, 0, 0 } }),
	key(0.5, "Snap", { Root = { -80, 0, 0 }, Neck = { 55, 0, 0 },
		RightShoulder = { 170, 0, 10 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 170, 0, -10 }, LeftElbow = { 0, 0, 0 },
		RightHip = { -10, 0, 5 }, RightKnee = { -10, 0, 0 }, LeftHip = { -10, 0, -5 }, LeftKnee = { -10, 0, 0 } }),
	key(0.9, "Out", wide({ RootPos = { 0, -1.2, 0 }, Root = { -25, 0, 0 }, Neck = { 20, 0, 0 },
		RightShoulder = { 60, 0, 40 }, RightElbow = { 20, 0, 0 }, LeftShoulder = { 60, 0, -40 }, LeftElbow = { 20, 0, 0 } })),
} }

-- Both palms pushed out, fingers spread, leaning into the beam.
P.HorizonPush = { Keys = {
	key(0.25, "Out", stance({ Root = { 10, 0, 0 }, RightShoulder = { 70, 30, 0 }, RightElbow = { 120, 0, 0 }, LeftShoulder = { 70, -30, 0 }, LeftElbow = { 120, 0, 0 } })),
	key(0.4, "Snap", stance({ RootPos = { 0, -0.6, 0 }, Root = { -18, 0, 0 }, Waist = { -8, 0, 0 },
		RightShoulder = { 92, 10, 0 }, RightElbow = { 0, 0, 0 }, RightWrist = { 70, 0, 0 }, LeftShoulder = { 92, -10, 0 }, LeftElbow = { 0, 0, 0 }, LeftWrist = { 70, 0, 0 },
		RightHip = { 50, 0, 10 }, RightKnee = { -60, 0, 0 }, LeftHip = { -30, 0, -10 }, LeftKnee = { -20, 0, 0 } })),
	key(0.95, "Linear", stance({ RootPos = { 0, -0.6, 0 }, Root = { -20, 0, 0 }, Waist = { -8, 0, 0 },
		RightShoulder = { 90, 10, 0 }, RightElbow = { 5, 0, 0 }, RightWrist = { 70, 0, 0 }, LeftShoulder = { 90, -10, 0 }, LeftElbow = { 5, 0, 0 }, LeftWrist = { 70, 0, 0 },
		RightHip = { 50, 0, 10 }, RightKnee = { -60, 0, 0 }, LeftHip = { -30, 0, -10 }, LeftKnee = { -20, 0, 0 } })),
} }

-- Palms up, lifting the world; fists clench in the air; then both slam down.
P.GravityLift = { Keys = {
	key(0.3, "Out", wide({ Root = { 10, 0, 0 }, Neck = { -20, 0, 0 },
		RightShoulder = { 130, 0, 40 }, RightElbow = { 30, 0, 0 }, RightWrist = { 50, 0, 0 }, LeftShoulder = { 130, 0, -40 }, LeftElbow = { 30, 0, 0 }, LeftWrist = { 50, 0, 0 } })),
	key(0.6, "InOut", wide({ Root = { 12, 0, 0 }, Neck = { -25, 0, 0 },
		RightShoulder = { 150, 30, 0 }, RightElbow = { 90, 0, 0 }, LeftShoulder = { 150, -30, 0 }, LeftElbow = { 90, 0, 0 } })),
	key(0.75, "Snap", wide({ RootPos = { 0, -1.5, 0 }, Root = { -40, 0, 0 }, Neck = { 30, 0, 0 },
		RightShoulder = { 50, 0, 15 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 50, 0, -15 }, LeftElbow = { 0, 0, 0 } })),
	key(0.95, "Out", wide({ RootPos = { 0, -1.2, 0 }, Root = { -30, 0, 0 }, Neck = { 25, 0, 0 },
		RightShoulder = { 45, 0, 20 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 45, 0, -20 }, LeftElbow = { 10, 0, 0 } })),
} }

-- Hold a sphere up and out in front, then crush it smaller and smaller.
P.BlackSunHold = { Keys = {
	key(0.3, "Out", wide({ Root = { 8, 0, 0 }, Neck = { -15, 0, 0 },
		RightShoulder = { 120, 0, 45 }, RightElbow = { 40, 0, 0 }, LeftShoulder = { 120, 0, -45 }, LeftElbow = { 40, 0, 0 } })),
	key(0.7, "InOut", wide({ Root = { 10, 0, 0 }, Neck = { -15, 0, 0 },
		RightShoulder = { 120, 25, 0 }, RightElbow = { 70, 0, 0 }, LeftShoulder = { 120, -25, 0 }, LeftElbow = { 70, 0, 0 } })),
	key(0.95, "Snap", wide({ RootPos = { 0, -1, 0 }, Root = { -20, 0, 0 }, Neck = { 15, 0, 0 },
		RightShoulder = { 90, 45, 0 }, RightElbow = { 110, 0, 0 }, LeftShoulder = { 90, -45, 0 }, LeftElbow = { 110, 0, 0 } })),
} }

return P
