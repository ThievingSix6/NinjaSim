--[[
	Weapon combos. Combo.Moves is the katana's (Combo.Nunchaku, Combo.Spear, Combo.Claws further down); use
	Combo.Get(index, weapon) / Combo.MovesFor(weapon) to pick by weapon type.

	The katana combo: four attacks that chain while the player keeps attacking.
	  1 horizontal slice to the left
	  2 rising slice upward on the right
	  3 spin, then a horizontal slice to the right (hits all around)
	  4 jumping downward slice (finisher: big damage, knocks enemies back)

	Timings are in seconds at the base attack speed and scale with the player's
	attack speed. Poses are keyframes for Util/Pose (see its sign guide); they were
	tuned with tools/anim (renders the combo in Blender from this file).

	Per move:
	  Duration   animation length
	  Cooldown   time until the next attack of the chain may start, in attack intervals
	  HitAt      when the blade connects (fraction of Duration): hit feedback waits for it
	  Trail      { from, to } fraction of Duration with the swing trail on
	  Damage     damage multiplier
	  Knockback  knockback multiplier on hit enemies
	  Arc        hit arc (cos of the half angle; -1 hits all around)
	  Lunge      studs the player steps forward during the strike
	  Reach      extra studs of range
	  ExtraTargets  enemies it can hit on top of Balance.MaxTargetsPerSwing
	  Width      optional: only enemies within this many studs of the strike line (thrusts)
	  Stun       seconds hit enemies stop moving and attacking
]]

local Balance = require(script.Parent.Balance)

local Combo = {}

Combo.ChainWindow = 0.7 -- seconds after a cooldown ends before the chain resets

-- Every move's Duration below is stretched by this (2026-10-02 Souls-style pacing): the
-- poses are fractions of Duration, so the moves play slower and heavier without retiming.
-- Light attacks 25% faster (2026-10-03): divided by Balance.LightAttackSpeed.
Combo.Pace = 1.25 / Balance.LightAttackSpeed

-- Momentum (justin, 2026-10-03: "slight momentum to all attacks"): every strike steps
-- further in (Lunge x LungeScale + LungeAdd), running into a swing carries some of
-- that speed (Carry studs per stud/s, at most CarryMax), and after the blade lands
-- the body glides on a little (Follow x the lunge) instead of stopping dead.
Combo.Momentum = {
	LungeScale = 1.4,
	LungeAdd = 0.6,
	Carry = 0.1,
	CarryMax = 1.8,
	Follow = 0.4,
	FollowTime = 0.3, -- seconds of glide after the hit
}

-- Heavy attack (justin, 2026-10-03): hold attack to charge, release to strike with the
-- weapon's finisher, harder the longer it charged. A tap is still a light attack.
Combo.Heavy = {
	HoldDelay = 0.22, -- held this long, the press charges a heavy instead of a light attack
	ChargeTime = 0.9, -- seconds to full charge
	MaxHold = 2.4, -- a charge held this long is released on its own
	MinDamage = 1.8, -- damage multiplier at no charge
	MaxDamage = 3.4, -- at full charge
	Knockback = 2.6,
	Stun = 0.8,
	Reach = 1.5,
	Arc = 0,
	ExtraTargets = 2,
	Lunge = 4.5,
	Recovery = 1.7, -- attack intervals before the next swing
	DurationScale = 1.1, -- plays a touch slower than the finisher it borrows
}

-- Reach (2026-10-02): no weapon cuts further round the player than the katana. Only one
-- move per weapon hits all the way round (Arc -1) and it has no extra Reach; spear
-- thrusts keep their longer Reach but in a narrow Width lane.

Combo.Moves = {
	{
		Name = "Horizontal slice left",
		Duration = 0.55,
		Cooldown = 1,
		HitAt = 0.34,
		Trail = { 0.22, 0.5 },
		Damage = 1,
		Knockback = 0.3,
		Arc = -0.1,
		Lunge = 1,
		Reach = 0,
		ExtraTargets = 0,
		Stun = 0,
		Keys = {
			{
				T = 0.22,
				Ease = "Out",
				RootPos = { 0, -0.45, 0 },
				Root = { 0, -20, 0 },
				Waist = { -5, -35, 0 },
				Neck = { 5, 45, 0 },
				RightShoulder = { 80, -45, 0 },
				RightElbow = { 15, 0, 0 },
				RightWrist = { -25, -90, 0 },
				LeftShoulder = { 60, -30, 0 },
				LeftElbow = { 70, 0, 0 },
				RightHip = { 35, 0, 10 },
				RightKnee = { -60, 0, 0 },
				LeftHip = { -20, 0, -12 },
				LeftKnee = { -35, 0, 0 },
			},
			{
				T = 0.4,
				Ease = "Snap",
				RootPos = { 0, -0.5, 0 },
				Root = { 0, 15, 0 },
				Waist = { -15, 30, 0 },
				Neck = { 8, -40, 0 },
				RightShoulder = { 80, 5, 0 },
				RightElbow = { 5, 0, 0 },
				RightWrist = { -50, -90, 0 },
				LeftShoulder = { -30, 0, -35 },
				LeftElbow = { 20, 0, 0 },
				RightHip = { 40, 0, 10 },
				RightKnee = { -65, 0, 0 },
				LeftHip = { -20, 0, -12 },
				LeftKnee = { -35, 0, 0 },
			},
			{
				T = 0.66,
				Ease = "Out",
				RootPos = { 0, -0.5, 0 },
				Root = { 0, 20, 0 },
				Waist = { -12, 40, 0 },
				Neck = { 5, -50, 0 },
				RightShoulder = { 75, 40, 0 },
				RightElbow = { 10, 0, 0 },
				RightWrist = { -40, -90, 0 },
				LeftShoulder = { -35, 0, -45 },
				LeftElbow = { 20, 0, 0 },
				RightHip = { 40, 0, 10 },
				RightKnee = { -65, 0, 0 },
				LeftHip = { -20, 0, -12 },
				LeftKnee = { -35, 0, 0 },
			},
		},
	},
	{
		Name = "Rising slice right",
		Duration = 0.55,
		Cooldown = 1,
		HitAt = 0.3,
		Trail = { 0.2, 0.52 },
		Damage = 1,
		Knockback = 0.3,
		Arc = -0.1,
		Lunge = 1,
		Reach = 0,
		ExtraTargets = 0,
		Stun = 0,
		Keys = {
			{
				T = 0.22,
				Ease = "Out",
				RootPos = { 0, -0.6, 0 },
				Root = { 0, -5, 0 },
				Waist = { -20, -10, 0 },
				Neck = { 15, 15, 0 },
				RightShoulder = { -25, -5, 30 },
				RightElbow = { 10, 0, 0 },
				RightWrist = { -100, 0, 0 },
				LeftShoulder = { 30, -20, -20 },
				LeftElbow = { 60, 0, 0 },
				RightHip = { 40, 0, 12 },
				RightKnee = { -75, 0, 0 },
				LeftHip = { -20, 0, -10 },
				LeftKnee = { -45, 0, 0 },
			},
			{
				T = 0.42,
				Ease = "Snap",
				RootPos = { 0, -0.1, 0 },
				Root = { 0, -5, 0 },
				Waist = { 5, 5, 0 },
				Neck = { -5, 0, 0 },
				RightShoulder = { 115, -10, 15 },
				RightElbow = { 5, 0, 0 },
				RightWrist = { -55, 0, 0 },
				LeftShoulder = { -10, 0, -45 },
				LeftElbow = { 20, 0, 0 },
				RightHip = { 15, 0, 10 },
				RightKnee = { -20, 0, 0 },
				LeftHip = { -15, 0, -10 },
				LeftKnee = { -15, 0, 0 },
			},
			{
				T = 0.66,
				Ease = "Out",
				RootPos = { 0, 0.1, 0 },
				Root = { 0, 0, 0 },
				Waist = { 12, 10, 0 },
				Neck = { -10, -5, 0 },
				RightShoulder = { 165, -10, 15 },
				RightElbow = { 10, 0, 0 },
				RightWrist = { -45, 0, 0 },
				LeftShoulder = { -15, 0, -50 },
				LeftElbow = { 20, 0, 0 },
				RightHip = { 10, 0, 10 },
				RightKnee = { -10, 0, 0 },
				LeftHip = { -10, 0, -10 },
				LeftKnee = { -10, 0, 0 },
			},
		},
	},
	{
		Name = "Spin slice right",
		Duration = 0.7,
		Cooldown = 1.3,
		HitAt = 0.52,
		Trail = { 0.22, 0.62 },
		Damage = 1.2,
		Knockback = 0.5,
		Arc = -1,
		Lunge = 1.5,
		Reach = 0,
		ExtraTargets = 1,
		Stun = 0,
		Keys = {
			{
				T = 0.22,
				Ease = "Out",
				RootPos = { 0, -0.35, 0 },
				Root = { 0, 40, 0 },
				Waist = { 0, 30, 0 },
				Neck = { 0, -50, 0 },
				RightShoulder = { 75, 75, 0 },
				RightElbow = { 30, 0, 0 },
				RightWrist = { -30, 90, 0 },
				LeftShoulder = { 20, 0, -30 },
				LeftElbow = { 30, 0, 0 },
				RightHip = { -15, 0, 12 },
				RightKnee = { -35, 0, 0 },
				LeftHip = { 25, 0, -12 },
				LeftKnee = { -40, 0, 0 },
			},
			{
				T = 0.44,
				Ease = "In",
				RootPos = { 0, -0.25, 0 },
				Root = { 0, -160, 0 },
				Waist = { 0, -10, 0 },
				Neck = { 0, 20, 0 },
				RightShoulder = { 85, -70, 0 },
				RightElbow = { 5, 0, 0 },
				RightWrist = { -40, 90, 0 },
				LeftShoulder = { 20, 0, -60 },
				LeftElbow = { 20, 0, 0 },
				RightHip = { 10, 0, 12 },
				RightKnee = { -30, 0, 0 },
				LeftHip = { 10, 0, -12 },
				LeftKnee = { -30, 0, 0 },
			},
			{
				T = 0.6,
				Ease = "Out",
				RootPos = { 0, -0.4, 0 },
				Root = { 0, -345, 0 },
				Waist = { -10, -25, 0 },
				Neck = { 5, 35, 0 },
				RightShoulder = { 82, -85, 0 },
				RightElbow = { 5, 0, 0 },
				RightWrist = { -45, 90, 0 },
				LeftShoulder = { 20, 0, -60 },
				LeftElbow = { 20, 0, 0 },
				RightHip = { 25, 0, 12 },
				RightKnee = { -45, 0, 0 },
				LeftHip = { -15, 0, -12 },
				LeftKnee = { -35, 0, 0 },
			},
			{
				T = 0.78,
				Ease = "Out",
				RootPos = { 0, -0.4, 0 },
				Root = { 0, -370, 0 },
				Waist = { -10, -30, 0 },
				Neck = { 5, 40, 0 },
				RightShoulder = { 80, -90, 0 },
				RightElbow = { 10, 0, 0 },
				RightWrist = { -40, 90, 0 },
				LeftShoulder = { 20, 0, -55 },
				LeftElbow = { 20, 0, 0 },
				RightHip = { 25, 0, 12 },
				RightKnee = { -45, 0, 0 },
				LeftHip = { -15, 0, -12 },
				LeftKnee = { -35, 0, 0 },
			},
		},
	},
	{
		Name = "Downward slice",
		Duration = 0.85,
		Cooldown = 2,
		HitAt = 0.47,
		Trail = { 0.3, 0.56 },
		Damage = 2,
		Knockback = 2.2,
		Arc = 0.2,
		Lunge = 2.5,
		Reach = 2,
		ExtraTargets = 0,
		Stun = 0.9,
		Finisher = true,
		Keys = {
			{
				T = 0.3,
				Ease = "Out",
				RootPos = { 0, 1.3, 0 },
				Waist = { 15, 0, 0 },
				Neck = { -15, 0, 0 },
				RightShoulder = { 170, 12, 0 },
				RightElbow = { 30, 0, 0 },
				RightWrist = { 0, 0, 0 },
				LeftShoulder = { 170, -20, 0 },
				LeftElbow = { 35, 0, 0 },
				RightHip = { 60, 0, 5 },
				RightKnee = { -90, 0, 0 },
				LeftHip = { 30, 0, -5 },
				LeftKnee = { -80, 0, 0 },
			},
			{
				T = 0.5,
				Ease = "Snap",
				RootPos = { 0, -0.7, 0 },
				Waist = { -35, 0, 0 },
				Neck = { 30, 0, 0 },
				RightShoulder = { 95, 15, 0 },
				RightElbow = { 0, 0, 0 },
				RightWrist = { -75, 0, 0 },
				LeftShoulder = { 95, -40, 0 },
				LeftElbow = { 15, 0, 0 },
				RightHip = { 60, 0, 8 },
				RightKnee = { -90, 0, 0 },
				LeftHip = { -30, 0, -8 },
				LeftKnee = { -20, 0, 0 },
			},
			{
				T = 0.8,
				Ease = "Out",
				RootPos = { 0, -0.75, 0 },
				Waist = { -38, 0, 0 },
				Neck = { 32, 0, 0 },
				RightShoulder = { 88, 15, 0 },
				RightElbow = { 0, 0, 0 },
				RightWrist = { -78, 0, 0 },
				LeftShoulder = { 88, -40, 0 },
				LeftElbow = { 15, 0, 0 },
				RightHip = { 60, 0, 8 },
				RightKnee = { -90, 0, 0 },
				LeftHip = { -30, 0, -8 },
				LeftKnee = { -20, 0, 0 },
			},
		},
	},
}

-- ===== Nunchaku =====
-- Five wild, acrobatic moves in the style of Maxi (Soul Calibur): the free stick is
-- whirled through scripted circles (Whirl) and flies loose in between, so it whips
-- on its own momentum (Controllers/NunchakuController simulates it).
--   Whirl  { From, To, Plane, Turns }: between those fractions of the move the free
--          stick spins Turns times round the hand in Plane, relative to the body:
--          "Front" (facing you, like a figure-eight), "Side" (a wheel at your right),
--          "Flat" (horizontal, like helicopter blades). Negative Turns spin the other way.
Combo.Nunchaku = {
	{
		Name = "Figure-eight flurry",
		Duration = 0.5,
		Cooldown = 0.8,
		HitAt = 0.45,
		Trail = { 0.12, 0.85 },
		Damage = 0.75,
		Knockback = 0.2,
		Arc = 0.1,
		Lunge = 0.8,
		Reach = 0.5,
		ExtraTargets = 0,
		Stun = 0.15,
		Whirl = { From = 0.08, To = 0.85, Plane = "Front", Turns = 2.5 },
		Keys = {
			{
				T = 0.15, Ease = "Out", RootPos = { 0, -0.3, 0 }, Root = { 0, -15, 0 }, Waist = { 5, -10, 0 }, Neck = { 0, 20, 0 },
				RightShoulder = { 70, 10, 20 }, RightElbow = { 45, 0, 0 }, RightWrist = { -30, 0, 0 },
				LeftShoulder = { 40, -20, -10 }, LeftElbow = { 85, 0, 0 },
				RightHip = { 20, 0, 15 }, RightKnee = { -35, 0, 0 }, LeftHip = { -15, 0, -15 }, LeftKnee = { -30, 0, 0 },
			},
			{
				T = 0.5, Ease = "InOut", RootPos = { 0, -0.35, 0 }, Root = { 0, 15, 0 }, Waist = { 0, 20, 0 }, Neck = { 0, -10, 0 },
				RightShoulder = { 95, 30, 10 }, RightElbow = { 20, 0, 0 }, RightWrist = { -45, 0, 0 },
				LeftShoulder = { 30, -10, -25 }, LeftElbow = { 80, 0, 0 },
				RightHip = { 25, 0, 15 }, RightKnee = { -40, 0, 0 }, LeftHip = { -20, 0, -15 }, LeftKnee = { -30, 0, 0 },
			},
			{
				T = 0.8, Ease = "InOut", RootPos = { 0, -0.3, 0 }, Root = { 0, -10, 0 }, Waist = { 0, -15, 0 }, Neck = { 0, 10, 0 },
				RightShoulder = { 80, -25, 25 }, RightElbow = { 30, 0, 0 }, RightWrist = { -40, 0, 0 },
				LeftShoulder = { 45, -25, -15 }, LeftElbow = { 85, 0, 0 },
				RightHip = { 20, 0, 15 }, RightKnee = { -35, 0, 0 }, LeftHip = { -15, 0, -15 }, LeftKnee = { -30, 0, 0 },
			},
		},
	},
	{
		Name = "Behind-the-back spin",
		Duration = 0.55,
		Cooldown = 0.85,
		HitAt = 0.55,
		Trail = { 0.15, 0.9 },
		Damage = 0.85,
		Knockback = 0.6,
		Arc = -0.1,
		Lunge = 0.5,
		Reach = 0.5,
		ExtraTargets = 0,
		Stun = 0.2,
		Whirl = { From = 0.12, To = 0.9, Plane = "Flat", Turns = -1.75 },
		Keys = {
			{
				T = 0.18, Ease = "Out", RootPos = { 0, -0.4, 0 }, Root = { 0, 35, 0 }, Waist = { 0, 15, 0 }, Neck = { 0, -25, 0 },
				RightShoulder = { 60, -70, 30 }, RightElbow = { 70, 0, 0 }, RightWrist = { -20, 0, 0 },
				LeftShoulder = { 20, 0, -50 }, LeftElbow = { 40, 0, 0 },
				RightHip = { 15, 0, 20 }, RightKnee = { -45, 0, 0 }, LeftHip = { -10, 0, -20 }, LeftKnee = { -40, 0, 0 },
			},
			{
				T = 0.72, Ease = "Linear", RootPos = { 0, -0.2, 0 }, Root = { 0, -320, 0 }, Waist = { 0, -20, 0 }, Neck = { 0, 25, 0 },
				RightShoulder = { 90, 20, 70 }, RightElbow = { 10, 0, 0 }, RightWrist = { -55, 0, 0 },
				LeftShoulder = { 30, 0, -70 }, LeftElbow = { 20, 0, 0 },
				RightHip = { 10, 0, 25 }, RightKnee = { -30, 0, 0 }, LeftHip = { -10, 0, -25 }, LeftKnee = { -30, 0, 0 },
			},
			{
				T = 0.88, Ease = "Out", RootPos = { 0, -0.35, 0 }, Root = { 0, -360, 0 }, Waist = { 0, -10, 0 }, Neck = { 0, 10, 0 },
				RightShoulder = { 85, -10, 40 }, RightElbow = { 30, 0, 0 }, RightWrist = { -40, 0, 0 },
				LeftShoulder = { 35, -15, -30 }, LeftElbow = { 70, 0, 0 },
				RightHip = { 20, 0, 15 }, RightKnee = { -40, 0, 0 }, LeftHip = { -15, 0, -15 }, LeftKnee = { -35, 0, 0 },
			},
		},
	},
	{
		Name = "Cartwheel whirl",
		Duration = 0.7,
		Cooldown = 1.1,
		HitAt = 0.62,
		Trail = { 0.1, 0.9 },
		Damage = 1.1,
		Knockback = 1,
		Arc = 0,
		Lunge = 2,
		Reach = 1,
		ExtraTargets = 1,
		Stun = 0.3,
		Airborne = true,
		Whirl = { From = 0.1, To = 0.88, Plane = "Side", Turns = 2 },
		Keys = {
			{
				T = 0.15, Ease = "Out", RootPos = { 0, -0.6, 0 }, Root = { 10, 0, 20 }, Waist = { 10, 0, 10 },
				RightShoulder = { 120, 0, 60 }, RightElbow = { 20, 0, 0 }, RightWrist = { -50, 0, 0 },
				LeftShoulder = { 30, 0, -80 }, LeftElbow = { 10, 0, 0 },
				RightHip = { 30, 0, 10 }, RightKnee = { -70, 0, 0 }, LeftHip = { 10, 0, -10 }, LeftKnee = { -50, 0, 0 },
			},
			{
				T = 0.45, Ease = "Linear", RootPos = { 0, 2, 0 }, Root = { 0, 0, 200 }, Waist = { 0, 0, 10 },
				RightShoulder = { 0, 0, 160 }, RightElbow = { 0, 0, 0 }, RightWrist = { -60, 0, 0 },
				LeftShoulder = { 0, 0, -160 }, LeftElbow = { 0, 0, 0 },
				RightHip = { 0, 0, 55 }, RightKnee = { 0, 0, 0 }, LeftHip = { 0, 0, -55 }, LeftKnee = { 0, 0, 0 },
			},
			{
				T = 0.75, Ease = "Out", RootPos = { 0, -0.5, 0 }, Root = { 0, 0, 360 }, Waist = { 10, 0, 0 },
				RightShoulder = { 100, -20, 30 }, RightElbow = { 30, 0, 0 }, RightWrist = { -40, 0, 0 },
				LeftShoulder = { 40, 0, -60 }, LeftElbow = { 30, 0, 0 },
				RightHip = { 40, 0, 15 }, RightKnee = { -80, 0, 0 }, LeftHip = { -10, 0, -15 }, LeftKnee = { -50, 0, 0 },
			},
		},
	},
	{
		Name = "Helicopter storm",
		Duration = 0.65,
		Cooldown = 1,
		HitAt = 0.5,
		Trail = { 0.1, 0.92 },
		Damage = 0.9,
		Knockback = 0.8,
		Arc = -1,
		Lunge = 0,
		Reach = 0,
		ExtraTargets = 1,
		Stun = 0.25,
		Whirl = { From = 0.08, To = 0.92, Plane = "Flat", Turns = 3 },
		Keys = {
			{
				T = 0.15, Ease = "Out", RootPos = { 0, -0.5, 0 }, Root = { 0, 10, 0 }, Waist = { -10, 0, 0 }, Neck = { -15, 0, 0 },
				RightShoulder = { 165, 0, 15 }, RightElbow = { 15, 0, 0 }, RightWrist = { 10, 0, 0 },
				LeftShoulder = { 20, 0, -60 }, LeftElbow = { 30, 0, 0 },
				RightHip = { 25, 0, 20 }, RightKnee = { -50, 0, 0 }, LeftHip = { -20, 0, -20 }, LeftKnee = { -45, 0, 0 },
			},
			{
				T = 0.85, Ease = "Linear", RootPos = { 0, -0.5, 0 }, Root = { 0, -80, 0 }, Waist = { -10, 0, 0 }, Neck = { -15, 0, 0 },
				RightShoulder = { 170, 0, 10 }, RightElbow = { 10, 0, 0 }, RightWrist = { 15, 0, 0 },
				LeftShoulder = { 20, 0, -65 }, LeftElbow = { 25, 0, 0 },
				RightHip = { 25, 0, 20 }, RightKnee = { -50, 0, 0 }, LeftHip = { -20, 0, -20 }, LeftKnee = { -45, 0, 0 },
			},
		},
	},
	{
		Name = "Dragon smash",
		Duration = 0.9,
		Cooldown = 2,
		HitAt = 0.55,
		Trail = { 0.05, 0.62 },
		Damage = 2.4,
		Knockback = 2.6,
		Arc = 0.3,
		Lunge = 3,
		Reach = 1.5,
		ExtraTargets = 1,
		Stun = 1,
		Finisher = true,
		Whirl = { From = 0.04, To = 0.48, Plane = "Side", Turns = 1.5 },
		Keys = {
			{
				T = 0.32, Ease = "Out", RootPos = { 0, 2.2, 0 }, Root = { -20, 0, 0 }, Waist = { 20, 0, 0 }, Neck = { -15, 0, 0 },
				RightShoulder = { 190, 0, 10 }, RightElbow = { 40, 0, 0 }, RightWrist = { 20, 0, 0 },
				LeftShoulder = { 150, 0, -20 }, LeftElbow = { 40, 0, 0 },
				RightHip = { 70, 0, 5 }, RightKnee = { -110, 0, 0 }, LeftHip = { 50, 0, -5 }, LeftKnee = { -100, 0, 0 },
			},
			{
				T = 0.55, Ease = "Snap", RootPos = { 0, -0.9, 0 }, Root = { 25, 0, 0 }, Waist = { -40, 0, 0 }, Neck = { 30, 0, 0 },
				RightShoulder = { 70, 0, 10 }, RightElbow = { 0, 0, 0 }, RightWrist = { -70, 0, 0 },
				LeftShoulder = { 40, -20, -30 }, LeftElbow = { 40, 0, 0 },
				RightHip = { 70, 0, 8 }, RightKnee = { -100, 0, 0 }, LeftHip = { -30, 0, -8 }, LeftKnee = { -20, 0, 0 },
			},
			{
				T = 0.8, Ease = "InOut", RootPos = { 0, -0.8, 0 }, Root = { 20, 0, 0 }, Waist = { -30, 0, 0 }, Neck = { 25, 0, 0 },
				RightShoulder = { 75, 0, 15 }, RightElbow = { 10, 0, 0 }, RightWrist = { -65, 0, 0 },
				LeftShoulder = { 40, -20, -30 }, LeftElbow = { 40, 0, 0 },
				RightHip = { 65, 0, 8 }, RightKnee = { -95, 0, 0 }, LeftHip = { -30, 0, -8 }, LeftKnee = { -20, 0, 0 },
			},
		},
	},
}

-- ===== Spear =====
-- Six moves mixing fast two-handed thrusts and spear spins, ending in a lunging
-- finisher that launches. The spear reaches further than a katana: thrusts hit a long,
-- narrow lane (Reach plus Width: enemies must be within Width studs of the thrust
-- line), spins hit all around. Keys pose both arms and the Grip (the shaft turned in
-- the hand so it lies along the thrust line); they were solved so the left hand sits
-- on the shaft, then checked with tools/anim (frames.luau Spear + anim_preview.py --spear).
--   Spin  { From, To, Turns, Axis, Slide }: between those fractions of the move the
--         spear twirls Turns whole times about its grip's Axis ("X": a wheel at your
--         side, "Y": helicopter blades when the arm is raised), held Slide studs up the
--         shaft so it turns about its middle (Combo.SpinCFrame).
Combo.Spear = {
	{
		Name = "Quick jab",
		Duration = 0.42,
		Cooldown = 0.75,
		HitAt = 0.45,
		Trail = { 0.25, 0.62 },
		Damage = 0.65,
		Knockback = 0.25,
		Arc = 0.8,
		Width = 2.5,
		Lunge = 1,
		Reach = 5,
		ExtraTargets = 0,
		Stun = 0.1,
		Keys = {
			{ T = 0.25, Ease = "Out", RootPos = { 0, -0.45, 0 }, Root = { 0, -25, 0 }, Waist = { 0, -10, 0 }, Neck = { 0, 35, 0 }, RightShoulder = { -73, 49, -38 }, RightElbow = { 104, 0, 0 }, RightWrist = { 18, 11, 0 }, Grip = { -57, 20, 0 }, LeftShoulder = { 46, -32, 25 }, LeftElbow = { 17, 0, 0 }, RightHip = { -20, 0, 12 }, RightKnee = { -35, 0, 0 }, LeftHip = { 40, 0, -8 }, LeftKnee = { -45, 0, 0 } },
			{ T = 0.45, Ease = "Snap", RootPos = { 0, -0.55, -0.3 }, Root = { 0, -40, 0 }, Waist = { -5, -12, 0 }, Neck = { 5, 47, 0 }, RightShoulder = { -6, 51, 7 }, RightElbow = { 91, 0, 0 }, RightWrist = { -4, 4, 0 }, Grip = { -92, 14, 0 }, LeftShoulder = { 46, -23, 12 }, LeftElbow = { 35, 0, 0 }, LeftWrist = { 1, 0, 0 }, RightHip = { -20, 0, 12 }, RightKnee = { -35, 0, 0 }, LeftHip = { 40, 0, -8 }, LeftKnee = { -45, 0, 0 } },
			{ T = 0.75, Ease = "Out", RootPos = { 0, -0.45, 0 }, Root = { 0, -30, 0 }, Waist = { 0, -10, 0 }, Neck = { 0, 35, 0 }, RightShoulder = { -29, 49, -16 }, RightElbow = { 102, 0, 0 }, RightWrist = { 4, 3, 0 }, Grip = { -89, 9, -1 }, LeftShoulder = { 42, -39, 2 }, LeftElbow = { 25, 0, 0 }, LeftWrist = { 1, 0, 0 }, RightHip = { -20, 0, 12 }, RightKnee = { -35, 0, 0 }, LeftHip = { 40, 0, -8 }, LeftKnee = { -45, 0, 0 } },
		},
	},
	{
		Name = "Double thrust",
		Duration = 0.6,
		Cooldown = 0.95,
		HitAt = 0.62,
		Trail = { 0.18, 0.7 },
		Damage = 0.95,
		Knockback = 0.4,
		Arc = 0.8,
		Width = 2.5,
		Lunge = 1.2,
		Reach = 5.5,
		ExtraTargets = 0,
		Stun = 0.15,
		Keys = {
			{ T = 0.18, Ease = "Out", RootPos = { 0, -0.45, 0 }, Root = { 0, -25, 0 }, Waist = { 0, -10, 0 }, Neck = { 0, 35, 0 }, RightShoulder = { -58, 40, -20 }, RightElbow = { 91, 0, 0 }, RightWrist = { 15, 8, 0 }, Grip = { -58, 11, 0 }, LeftShoulder = { 45, -31, 26 }, LeftElbow = { 9, 0, 0 }, LeftWrist = { -1, 0, 0 }, RightHip = { -20, 0, 12 }, RightKnee = { -35, 0, 0 }, LeftHip = { 40, 0, -8 }, LeftKnee = { -45, 0, 0 } },
			{ T = 0.32, Ease = "Snap", RootPos = { 0, -0.45, 0 }, Root = { 0, -32, 0 }, Waist = { 0, -10, 0 }, Neck = { 0, 35, 0 }, RightShoulder = { -22, 47, -9 }, RightElbow = { 97, 0, 0 }, RightWrist = { -3, 4, 0 }, Grip = { -89, 12, 0 }, LeftShoulder = { 47, -38, 2 }, LeftElbow = { 12, 0, 0 }, RightHip = { -20, 0, 12 }, RightKnee = { -35, 0, 0 }, LeftHip = { 40, 0, -8 }, LeftKnee = { -45, 0, 0 } },
			{ T = 0.46, Ease = "InOut", RootPos = { 0, -0.45, 0 }, Root = { 0, -25, 0 }, Waist = { 0, -10, 0 }, Neck = { 0, 35, 0 }, RightShoulder = { -45, 45, -18 }, RightElbow = { 99, 0, 0 }, RightWrist = { 9, 4, 0 }, Grip = { -71, 11, -1 }, LeftShoulder = { 47, -58, -5 }, LeftElbow = { 11, 0, 0 }, RightHip = { -20, 0, 12 }, RightKnee = { -35, 0, 0 }, LeftHip = { 40, 0, -8 }, LeftKnee = { -45, 0, 0 } },
			{ T = 0.62, Ease = "Snap", RootPos = { 0, -0.35, 0 }, Root = { 0, -42, 0 }, Waist = { 5, -12, 0 }, Neck = { -5, 54, 0 }, RightShoulder = { 1, 52, 2 }, RightElbow = { 89, 0, 0 }, RightWrist = { -6, 2, 0 }, Grip = { -95, 5, -1 }, LeftShoulder = { 48, -48, -25 }, LeftElbow = { 20, 0, 0 }, LeftWrist = { 1, 0, 0 }, RightHip = { -20, 0, 12 }, RightKnee = { -35, 0, 0 }, LeftHip = { 40, 0, -8 }, LeftKnee = { -45, 0, 0 } },
			{ T = 0.85, Ease = "Out", RootPos = { 0, -0.45, 0 }, Root = { 0, -38, 0 }, Waist = { 0, -10, 0 }, Neck = { 0, 48, 0 }, RightShoulder = { 1, 48, -8 }, RightElbow = { 93, 0, 0 }, RightWrist = { -4, 0, 0 }, Grip = { -100, 0, -1 }, LeftShoulder = { 45, -53, -28 }, LeftElbow = { 22, 0, 0 }, LeftWrist = { 1, 0, 0 }, RightHip = { -20, 0, 12 }, RightKnee = { -35, 0, 0 }, LeftHip = { 40, 0, -8 }, LeftKnee = { -45, 0, 0 } },
		},
	},
	{
		Name = "Sweeping spin",
		Duration = 0.7,
		Cooldown = 1.15,
		HitAt = 0.5,
		Trail = { 0.2, 0.7 },
		Damage = 1.05,
		Knockback = 0.7,
		Arc = -1,
		Lunge = 0.5,
		Reach = 1,
		ExtraTargets = 1,
		Stun = 0.2,
		Spin = { From = 0.06, To = 0.9, Turns = 0, Axis = "Y", Slide = -1.6 },
		Keys = {
			{ T = 0.2, Ease = "Out", RootPos = { 0, -0.55, 0 }, Root = { 0, -60, 0 }, Waist = { 0, -15, 0 }, Neck = { 0, 45, 0 }, RightShoulder = { -21, 1, 62 }, RightElbow = { 27, 0, 0 }, RightWrist = { -20, 8, 0 }, Grip = { -138, 18, 0 }, LeftShoulder = { 60, 0, -40 }, LeftElbow = { 40, 0, 0 }, RightHip = { -15, 0, 20 }, RightKnee = { -40, 0, 0 }, LeftHip = { 25, 0, -20 }, LeftKnee = { -45, 0, 0 } },
			{ T = 0.42, Ease = "In", RootPos = { 0, -0.45, 0 }, Root = { 0, 150, 0 }, Waist = { 0, 10, 0 }, Neck = { 0, -10, 0 }, RightShoulder = { -19, -35, 62 }, RightElbow = { 65, 0, 0 }, RightWrist = { 10, 12, 0 }, Grip = { -131, 39, 0 }, LeftShoulder = { 20, 0, -70 }, LeftElbow = { 20, 0, 0 }, RightHip = { -10, 0, 20 }, RightKnee = { -35, 0, 0 }, LeftHip = { 15, 0, -20 }, LeftKnee = { -40, 0, 0 } },
			{ T = 0.62, Ease = "Out", RootPos = { 0, -0.5, 0 }, Root = { 0, 330, 0 }, Waist = { -5, 20, 0 }, Neck = { 0, -20, 0 }, RightShoulder = { -16, -62, 56 }, RightElbow = { 75, 0, 0 }, RightWrist = { 17, 7, 0 }, Grip = { -124, 39, -1 }, LeftShoulder = { 20, 0, -70 }, LeftElbow = { 20, 0, 0 }, RightHip = { -10, 0, 20 }, RightKnee = { -40, 0, 0 }, LeftHip = { 15, 0, -20 }, LeftKnee = { -45, 0, 0 } },
			{ T = 0.82, Ease = "Out", RootPos = { 0, -0.5, 0 }, Root = { 0, 360, 0 }, Waist = { 0, 10, 0 }, Neck = { 0, -5, 0 }, RightShoulder = { -20, -38, 31 }, RightElbow = { 99, 0, 0 }, RightWrist = { 15, 4, 0 }, Grip = { -124, 33, -1 }, LeftShoulder = { 30, 0, -50 }, LeftElbow = { 30, 0, 0 }, RightHip = { -10, 0, 20 }, RightKnee = { -40, 0, 0 }, LeftHip = { 15, 0, -20 }, LeftKnee = { -45, 0, 0 } },
		},
	},
	{
		Name = "Rising spin-lift",
		Duration = 0.72,
		Cooldown = 1.15,
		HitAt = 0.58,
		Trail = { 0.1, 0.65 },
		Damage = 1.1,
		Knockback = 1.5,
		Arc = 0,
		Lunge = 1,
		Reach = 1,
		ExtraTargets = 0,
		Stun = 0.35,
		Airborne = true,
		Spin = { From = 0.1, To = 0.58, Turns = 2, Axis = "X", Slide = 1.35 },
		Keys = {
			{ T = 0.15, Ease = "Out", RootPos = { 0, -0.6, 0 }, Root = { 0, -10, 0 }, Neck = { 0, 10, 0 }, RightShoulder = { 18, -3, 18 }, RightElbow = { 77, 0, 0 }, RightWrist = { 4, -1, 0 }, Grip = { -112, -17, 0 }, LeftShoulder = { 30, 0, -60 }, LeftElbow = { 30, 0, 0 }, RightHip = { 30, 0, 10 }, RightKnee = { -60, 0, 0 }, LeftHip = { 10, 0, -10 }, LeftKnee = { -50, 0, 0 } },
			{ T = 0.4, Ease = "Linear", RootPos = { 0, 0.8, 0 }, Waist = { 5, 0, 0 }, Neck = { -5, 0, 0 }, RightShoulder = { 32, -2, 27 }, RightElbow = { 101, 0, 0 }, RightWrist = { -8, -4, 0 }, Grip = { -143, -19, -7 }, LeftShoulder = { 40, 0, -70 }, LeftElbow = { 20, 0, 0 }, RightHip = { 10, 0, 10 }, RightKnee = { -20, 0, 0 }, LeftHip = { 45, 0, -10 }, LeftKnee = { -75, 0, 0 } },
			{ T = 0.62, Ease = "Out", RootPos = { 0, 1.5, 0 }, Root = { 0, 5, 0 }, Waist = { 10, 0, 0 }, Neck = { -10, 0, 0 }, RightShoulder = { 97, 2, 0 }, RightElbow = { 77, 0, 0 }, RightWrist = { -7, 3, 0 }, Grip = { -148, -2, -5 }, LeftShoulder = { 40, 0, -80 }, LeftElbow = { 20, 0, 0 }, RightHip = { 5, 0, 10 }, RightKnee = { -10, 0, 0 }, LeftHip = { 50, 0, -10 }, LeftKnee = { -80, 0, 0 } },
			{ T = 0.85, Ease = "Out", RootPos = { 0, 0, 0 }, Root = { 0, -25, 0 }, Waist = { 0, -10, 0 }, Neck = { 0, 35, 0 }, RightShoulder = { -45, 45, -17 }, RightElbow = { 100, 0, 0 }, RightWrist = { 9, 5, 0 }, Grip = { -73, 6, 0 }, LeftShoulder = { 48, -43, 10 }, LeftElbow = { 13, 0, 0 }, RightHip = { -20, 0, 12 }, RightKnee = { -35, 0, 0 }, LeftHip = { 40, 0, -8 }, LeftKnee = { -45, 0, 0 } },
		},
	},
	{
		Name = "Overhead twirl",
		Duration = 0.75,
		Cooldown = 1.15,
		HitAt = 0.6,
		Trail = { 0.1, 0.76 },
		Damage = 0.95,
		Knockback = 0.9,
		Arc = 0.3,
		Lunge = 0,
		Reach = 2.5,
		ExtraTargets = 1,
		Stun = 0.25,
		Spin = { From = 0.1, To = 0.74, Turns = 3, Axis = "Y", Slide = 1.35 },
		Keys = {
			{ T = 0.15, Ease = "Out", RootPos = { 0, -0.3, 0 }, Root = { 0, 25, 0 }, Neck = { -10, -20, 0 }, RightShoulder = { 174, -13, -13 }, RightElbow = { -1, 0, 0 }, RightWrist = { -31, -5, 0 }, Grip = { -154, -8, -9 }, LeftShoulder = { 40, 0, -70 }, LeftElbow = { 20, 0, 0 }, RightHip = { 20, 0, 15 }, RightKnee = { -40, 0, 0 }, LeftHip = { -10, 0, -15 }, LeftKnee = { -30, 0, 0 } },
			{ T = 0.7, Ease = "Linear", RootPos = { 0, -0.4, 0 }, Root = { 0, -60, 0 }, Waist = { 0, -10, 0 }, Neck = { -10, 30, 0 }, RightShoulder = { 171, -14, -17 }, RightWrist = { -20, -7, 0 }, Grip = { -161, -14, -10 }, LeftShoulder = { 40, 0, -70 }, LeftElbow = { 20, 0, 0 }, RightHip = { 20, 0, 15 }, RightKnee = { -45, 0, 0 }, LeftHip = { -10, 0, -15 }, LeftKnee = { -35, 0, 0 } },
			{ T = 0.88, Ease = "Out", RootPos = { 0, -0.45, 0 }, Root = { 0, -25, 0 }, Waist = { 0, -10, 0 }, Neck = { 0, 35, 0 }, RightShoulder = { -62, 52, -17 }, RightElbow = { 107, 0, 0 }, RightWrist = { 18, 1, 0 }, Grip = { -73, 0, 0 }, LeftShoulder = { 49, -27, 29 }, LeftElbow = { 12, 0, 0 }, RightHip = { -20, 0, 12 }, RightKnee = { -35, 0, 0 }, LeftHip = { 40, 0, -8 }, LeftKnee = { -45, 0, 0 } },
		},
	},
	{
		Name = "Piercing lunge",
		Duration = 0.9,
		Cooldown = 2,
		HitAt = 0.5,
		Trail = { 0.36, 0.72 },
		Damage = 2.4,
		Knockback = 2.8,
		Arc = 0.7,
		Width = 3,
		Lunge = 4,
		Reach = 7,
		ExtraTargets = 1,
		Stun = 1,
		Finisher = true,
		Spin = { From = 0.36, To = 0.98, Turns = 0, Axis = "Y", Slide = -1.4 },
		Keys = {
			{ T = 0.3, Ease = "Out", RootPos = { 0, -0.85, 0.5 }, Root = { 0, -55, 0 }, Waist = { 10, -10, 0 }, Neck = { -5, 60, 0 }, RightShoulder = { -77, 33, -5 }, RightElbow = { 75, 0, 0 }, RightWrist = { 25, 17, 0 }, Grip = { -34, 10, 0 }, LeftShoulder = { 37, -43, 42 }, LeftElbow = { 13, 0, 0 }, RightHip = { -25, 0, 15 }, RightKnee = { -55, 0, 0 }, LeftHip = { 50, 0, -10 }, LeftKnee = { -70, 0, 0 } },
			{ T = 0.5, Ease = "Snap", RootPos = { 0, -0.7, -0.8 }, Root = { 0, 25, 0 }, Waist = { -15, 10, 0 }, Neck = { 10, -35, 0 }, RightShoulder = { 86, -14, -1 }, RightElbow = { -1, 0, 0 }, RightWrist = { -14, -17, 0 }, Grip = { -64, -30, 0 }, LeftShoulder = { -50, 0, -30 }, LeftElbow = { 20, 0, 0 }, RightHip = { -35, 0, 10 }, RightKnee = { -10, 0, 0 }, LeftHip = { 75, 0, -8 }, LeftKnee = { -85, 0, 0 } },
			{ T = 0.8, Ease = "Out", RootPos = { 0, -0.75, -0.8 }, Root = { 0, 25, 0 }, Waist = { -12, 10, 0 }, Neck = { 8, -35, 0 }, RightShoulder = { 80, -25, -13 }, RightElbow = { -1, 0, 0 }, RightWrist = { -15, -13, 0 }, Grip = { -58, -33, 0 }, LeftShoulder = { -45, 0, -30 }, LeftElbow = { 25, 0, 0 }, RightHip = { -35, 0, 10 }, RightKnee = { -10, 0, 0 }, LeftHip = { 75, 0, -8 }, LeftKnee = { -85, 0, 0 } },
		},
	},
}
-- (end of Combo.Spear)

-- ===== Claws =====
-- Six quick, light moves alternating hands (one claw in each fist, blades along the
-- forearm), ending in a pouncing X-slash. Short cooldowns and low damage per move keep
-- the damage per second in line with the katana: more hits, not more damage.
Combo.Claws = {
	{
		Name = "Left-right double slash", Duration = 0.42, Cooldown = 0.7, HitAt = 0.55, Trail = { 0.12, 0.7 },
		Damage = 0.6, Knockback = 0.25, Arc = -0.1, Lunge = 1, Reach = 0, ExtraTargets = 0, Stun = 0.1,
		Keys = {
			{
				T = 0.15, Ease = "Out", RootPos = { 0, -0.4, 0 }, Root = { 0, 30, 0 }, Waist = { 0, 10, 0 }, Neck = { 0, -35, 0 },
				RightShoulder = { 60, 20, 30 }, RightElbow = { 90, 0, 0 }, LeftShoulder = { 80, 50, -20 }, LeftElbow = { 40, 0, 0 },
				RightHip = { -15, 0, 12 }, RightKnee = { -35, 0, 0 }, LeftHip = { 30, 0, -10 }, LeftKnee = { -45, 0, 0 },
			},
			{
				T = 0.32, Ease = "Snap", RootPos = { 0, -0.45, 0 }, Root = { 0, -20, 0 }, Waist = { 0, -10, 0 }, Neck = { 0, 25, 0 },
				RightShoulder = { 80, -50, 0 }, RightElbow = { 40, 0, 0 }, LeftShoulder = { 85, -45, 0 }, LeftElbow = { 10, 0, 0 },
				RightHip = { -15, 0, 12 }, RightKnee = { -35, 0, 0 }, LeftHip = { 30, 0, -10 }, LeftKnee = { -45, 0, 0 },
			},
			{
				T = 0.55, Ease = "Snap", RootPos = { 0, -0.45, 0 }, Root = { 0, 25, 0 }, Waist = { 0, 10, 0 }, Neck = { 0, -30, 0 },
				RightShoulder = { 85, 45, 0 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 60, -20, -30 }, LeftElbow = { 90, 0, 0 },
				RightHip = { -15, 0, 12 }, RightKnee = { -35, 0, 0 }, LeftHip = { 30, 0, -10 }, LeftKnee = { -45, 0, 0 },
			},
			{
				T = 0.8, Ease = "Out", RootPos = { 0, -0.4, 0 }, Root = { 0, 20, 0 }, Waist = { 0, 8, 0 }, Neck = { 0, -25, 0 },
				RightShoulder = { 80, 40, 0 }, RightElbow = { 20, 0, 0 }, LeftShoulder = { 60, -20, -30 }, LeftElbow = { 90, 0, 0 },
				RightHip = { -15, 0, 12 }, RightKnee = { -35, 0, 0 }, LeftHip = { 30, 0, -10 }, LeftKnee = { -45, 0, 0 },
			},
		},
	},
	{
		Name = "Cross slash", Duration = 0.45, Cooldown = 0.75, HitAt = 0.5, Trail = { 0.2, 0.65 },
		Damage = 0.75, Knockback = 0.4, Arc = 0, Lunge = 1.5, Reach = 0.5, ExtraTargets = 0, Stun = 0.15,
		Keys = {
			{
				T = 0.22, Ease = "Out", RootPos = { 0, -0.2, 0 }, Waist = { 10, 0, 0 }, Neck = { -10, 0, 0 },
				RightShoulder = { 160, -30, 40 }, RightElbow = { 30, 0, 0 }, LeftShoulder = { 160, 30, -40 }, LeftElbow = { 30, 0, 0 },
				RightHip = { -10, 0, 10 }, RightKnee = { -25, 0, 0 }, LeftHip = { 25, 0, -10 }, LeftKnee = { -35, 0, 0 },
			},
			{
				T = 0.5, Ease = "Snap", RootPos = { 0, -0.6, 0 }, Waist = { -25, 0, 0 }, Neck = { 20, 0, 0 },
				RightShoulder = { 70, 55, 0 }, RightElbow = { 5, 0, 0 }, LeftShoulder = { 70, -55, 0 }, LeftElbow = { 5, 0, 0 },
				RightHip = { -20, 0, 12 }, RightKnee = { -40, 0, 0 }, LeftHip = { 40, 0, -10 }, LeftKnee = { -60, 0, 0 },
			},
			{
				T = 0.8, Ease = "Out", RootPos = { 0, -0.55, 0 }, Waist = { -20, 0, 0 }, Neck = { 15, 0, 0 },
				RightShoulder = { 65, 50, 0 }, RightElbow = { 15, 0, 0 }, LeftShoulder = { 65, -50, 0 }, LeftElbow = { 15, 0, 0 },
				RightHip = { -20, 0, 12 }, RightKnee = { -40, 0, 0 }, LeftHip = { 40, 0, -10 }, LeftKnee = { -60, 0, 0 },
			},
		},
	},
	{
		Name = "Triple flurry", Duration = 0.55, Cooldown = 0.85, HitAt = 0.7, Trail = { 0.1, 0.85 },
		Damage = 0.85, Knockback = 0.3, Arc = -0.1, Lunge = 1.5, Reach = 0, ExtraTargets = 0, Stun = 0.25,
		Keys = {
			{
				T = 0.1, Ease = "Out", RootPos = { 0, -0.4, 0 }, Root = { 0, -20, 0 }, Neck = { 0, 20, 0 },
				RightShoulder = { 75, -40, 10 }, RightElbow = { 60, 0, 0 }, LeftShoulder = { 60, -10, -20 }, LeftElbow = { 90, 0, 0 },
				RightHip = { -15, 0, 12 }, RightKnee = { -35, 0, 0 }, LeftHip = { 30, 0, -10 }, LeftKnee = { -45, 0, 0 },
			},
			{
				T = 0.28, Ease = "Snap", RootPos = { 0, -0.45, 0 }, Root = { 0, 20, 0 }, Neck = { 0, -20, 0 },
				RightShoulder = { 90, 40, 0 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 75, 40, -10 }, LeftElbow = { 60, 0, 0 },
				RightHip = { -15, 0, 12 }, RightKnee = { -35, 0, 0 }, LeftHip = { 30, 0, -10 }, LeftKnee = { -45, 0, 0 },
			},
			{
				T = 0.5, Ease = "Snap", RootPos = { 0, -0.45, 0 }, Root = { 0, -25, 0 }, Neck = { 0, 25, 0 },
				RightShoulder = { 75, -40, 10 }, RightElbow = { 60, 0, 0 }, LeftShoulder = { 90, -45, 0 }, LeftElbow = { 10, 0, 0 },
				RightHip = { -15, 0, 12 }, RightKnee = { -35, 0, 0 }, LeftHip = { 30, 0, -10 }, LeftKnee = { -45, 0, 0 },
			},
			{
				T = 0.7, Ease = "Snap", RootPos = { 0, -0.4, 0 }, Root = { 0, 25, 0 }, Neck = { 0, -25, 0 },
				RightShoulder = { 105, 45, -10 }, RightElbow = { 5, 0, 0 }, LeftShoulder = { 60, -10, -20 }, LeftElbow = { 90, 0, 0 },
				RightHip = { -15, 0, 12 }, RightKnee = { -35, 0, 0 }, LeftHip = { 30, 0, -10 }, LeftKnee = { -45, 0, 0 },
			},
			{
				T = 0.88, Ease = "Out", RootPos = { 0, -0.4, 0 }, Root = { 0, 15, 0 }, Neck = { 0, -15, 0 },
				RightShoulder = { 85, 35, 0 }, RightElbow = { 20, 0, 0 }, LeftShoulder = { 60, -10, -20 }, LeftElbow = { 90, 0, 0 },
				RightHip = { -15, 0, 12 }, RightKnee = { -35, 0, 0 }, LeftHip = { 30, 0, -10 }, LeftKnee = { -45, 0, 0 },
			},
		},
	},
	{
		Name = "Whirling claws", Duration = 0.6, Cooldown = 0.95, HitAt = 0.55, Trail = { 0.12, 0.8 },
		Damage = 0.85, Knockback = 0.6, Arc = -1, Lunge = 0.5, Reach = 0, ExtraTargets = 1, Stun = 0.2,
		Keys = {
			{
				T = 0.15, Ease = "Out", RootPos = { 0, -0.4, 0 }, Root = { 0, 40, 0 }, Neck = { 0, -20, 0 },
				RightShoulder = { 10, 0, 85 }, RightElbow = { 5, 0, 0 }, LeftShoulder = { 10, 0, -85 }, LeftElbow = { 5, 0, 0 },
				RightHip = { -10, 0, 20 }, RightKnee = { -35, 0, 0 }, LeftHip = { 15, 0, -20 }, LeftKnee = { -40, 0, 0 },
			},
			{
				T = 0.45, Ease = "Linear", RootPos = { 0, -0.35, 0 }, Root = { 0, -160, 0 }, Neck = { 0, 10, 0 },
				RightShoulder = { 10, 0, 85 }, RightElbow = { 5, 0, 0 }, LeftShoulder = { 10, 0, -85 }, LeftElbow = { 5, 0, 0 },
				RightHip = { -10, 0, 20 }, RightKnee = { -30, 0, 0 }, LeftHip = { 15, 0, -20 }, LeftKnee = { -35, 0, 0 },
			},
			{
				T = 0.7, Ease = "Out", RootPos = { 0, -0.4, 0 }, Root = { 0, -340, 0 }, Neck = { 0, 15, 0 },
				RightShoulder = { 20, 0, 80 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 20, 0, -80 }, LeftElbow = { 10, 0, 0 },
				RightHip = { -10, 0, 20 }, RightKnee = { -35, 0, 0 }, LeftHip = { 15, 0, -20 }, LeftKnee = { -40, 0, 0 },
			},
			{
				T = 0.86, Ease = "Out", RootPos = { 0, -0.4, 0 }, Root = { 0, -360, 0 },
				RightShoulder = { 60, 20, 30 }, RightElbow = { 90, 0, 0 }, LeftShoulder = { 60, -20, -30 }, LeftElbow = { 90, 0, 0 },
				RightHip = { -15, 0, 12 }, RightKnee = { -35, 0, 0 }, LeftHip = { 30, 0, -10 }, LeftKnee = { -45, 0, 0 },
			},
		},
	},
	{
		Name = "Rising double rake", Duration = 0.5, Cooldown = 0.85, HitAt = 0.5, Trail = { 0.25, 0.7 },
		Damage = 0.85, Knockback = 1.3, Arc = 0, Lunge = 1.5, Reach = 0.5, ExtraTargets = 1, Stun = 0.35, Airborne = true,
		Keys = {
			{
				T = 0.25, Ease = "Out", RootPos = { 0, -0.9, 0 }, Waist = { -25, 0, 0 }, Neck = { 20, 0, 0 },
				RightShoulder = { -30, 0, 30 }, RightElbow = { 30, 0, 0 }, LeftShoulder = { -30, 0, -30 }, LeftElbow = { 30, 0, 0 },
				RightHip = { 50, 0, 10 }, RightKnee = { -90, 0, 0 }, LeftHip = { 50, 0, -10 }, LeftKnee = { -90, 0, 0 },
			},
			{
				T = 0.5, Ease = "Snap", RootPos = { 0, 1.2, 0 }, Waist = { 10, 0, 0 }, Neck = { -10, 0, 0 },
				RightShoulder = { 165, 10, 15 }, RightElbow = { 5, 0, 0 }, LeftShoulder = { 165, -10, -15 }, LeftElbow = { 5, 0, 0 },
				RightHip = { 10, 0, 5 }, RightKnee = { -10, 0, 0 }, LeftHip = { 40, 0, -5 }, LeftKnee = { -70, 0, 0 },
			},
			{
				T = 0.75, Ease = "Out", RootPos = { 0, 0.4, 0 }, Waist = { 5, 0, 0 }, Neck = { -5, 0, 0 },
				RightShoulder = { 150, 10, 15 }, RightElbow = { 15, 0, 0 }, LeftShoulder = { 150, -10, -15 }, LeftElbow = { 15, 0, 0 },
				RightHip = { 15, 0, 5 }, RightKnee = { -25, 0, 0 }, LeftHip = { 30, 0, -5 }, LeftKnee = { -50, 0, 0 },
			},
		},
	},
	{
		Name = "Pouncing X-slash", Duration = 0.8, Cooldown = 1.6, HitAt = 0.52, Trail = { 0.3, 0.62 },
		Damage = 1.75, Knockback = 2.5, Arc = 0.1, Lunge = 3.5, Reach = 2, ExtraTargets = 1, Stun = 0.9, Finisher = true, Airborne = true,
		Keys = {
			{
				T = 0.3, Ease = "Out", RootPos = { 0, 2.2, 0 }, Waist = { 20, 0, 0 }, Neck = { -15, 0, 0 },
				RightShoulder = { 175, -25, 45 }, RightElbow = { 35, 0, 0 }, LeftShoulder = { 175, 25, -45 }, LeftElbow = { 35, 0, 0 },
				RightHip = { 80, 0, 5 }, RightKnee = { -110, 0, 0 }, LeftHip = { 70, 0, -5 }, LeftKnee = { -110, 0, 0 },
			},
			{
				T = 0.52, Ease = "Snap", RootPos = { 0, -0.8, 0 }, Waist = { -35, 0, 0 }, Neck = { 30, 0, 0 },
				RightShoulder = { 75, 55, 0 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 75, -55, 0 }, LeftElbow = { 0, 0, 0 },
				RightHip = { 70, 0, 8 }, RightKnee = { -100, 0, 0 }, LeftHip = { -30, 0, -8 }, LeftKnee = { -20, 0, 0 },
			},
			{
				T = 0.82, Ease = "InOut", RootPos = { 0, -0.75, 0 }, Waist = { -30, 0, 0 }, Neck = { 25, 0, 0 },
				RightShoulder = { 70, 50, 0 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 70, -50, 0 }, LeftElbow = { 10, 0, 0 },
				RightHip = { 65, 0, 8 }, RightKnee = { -95, 0, 0 }, LeftHip = { -30, 0, -8 }, LeftKnee = { -20, 0, 0 },
			},
		},
	},
}

-- weapon type -> its combo
Combo.Sets = {
	Katana = Combo.Moves,
	Nunchaku = Combo.Nunchaku,
	Spear = Combo.Spear,
	Claws = Combo.Claws,
}

for _, moves in pairs(Combo.Sets) do
	for _, move in ipairs(moves) do
		move.Duration *= Combo.Pace
		move.Lunge = move.Lunge * Combo.Momentum.LungeScale + Combo.Momentum.LungeAdd
	end
end

-- The heavy attack for a weapon at `charge` (0..1): its combo finisher, reweighted.
function Combo.HeavyMove(weapon: string?, charge: number)
	local moves = Combo.MovesFor(weapon)
	local h = Combo.Heavy
	local k = math.clamp(charge, 0, 1)
	local move = table.clone(moves[#moves])
	move.Name = "Heavy"
	move.Heavy = true
	move.Finisher = true
	move.Charge = k
	move.Duration *= h.DurationScale
	move.Cooldown = h.Recovery
	move.Damage = h.MinDamage + (h.MaxDamage - h.MinDamage) * k
	move.Knockback = h.Knockback * (0.6 + 0.4 * k)
	move.Stun = h.Stun * (0.6 + 0.4 * k)
	move.Reach = h.Reach
	move.Arc = h.Arc
	move.ExtraTargets = h.ExtraTargets
	move.Width = nil
	move.Lunge = h.Lunge
	return move
end

-- The wind-up held while charging: the finisher's first key, held.
local chargePoses = {}
function Combo.ChargePose(weapon: string?)
	local kind = weapon or "Katana"
	if not chargePoses[kind] then
		local moves = Combo.MovesFor(kind)
		local first = moves[#moves].Keys[1]
		local a, b = table.clone(first), table.clone(first)
		-- a low, braced stance whatever the finisher's legs do (some finishers leap)
		for _, key in ipairs({ a, b }) do
			key.RootPos = { 0, -0.6, 0 }
			key.RightHip, key.RightKnee = { 50, 0, 8 }, { -80, 0, 0 }
			key.LeftHip, key.LeftKnee = { -25, 0, -8 }, { -30, 0, 0 }
		end
		a.T, a.Ease = 0.12, "Out"
		b.T, b.Ease = 1, "Linear"
		chargePoses[kind] = { Name = "Charge", Keys = { a, b }, Trail = { 2, 2 } }
	end
	return chargePoses[kind]
end

-- Shop / inventory label for a weapon type, e.g. "Spear, 6-hit combo".
local STYLE_NAMES = { Katana = "Katana", Nunchaku = "Nunchucks", Spear = "Spear", Claws = "Claws (dual)" }
function Combo.StyleText(weapon: string?): string
	local kind = weapon or "Katana"
	return string.format("%s, %d-hit combo", STYLE_NAMES[kind] or kind, #Combo.MovesFor(kind))
end

-- The extra turn (and slide along the shaft) a move's Spin gives the held weapon at
-- t (0..1), in grip space; nil outside the spin window. Whole turns, so it ends
-- where it started.
function Combo.SpinCFrame(move, t: number): CFrame?
	local spin = move.Spin
	if not spin or t <= spin.From or t >= spin.To then
		return nil
	end
	local p = (t - spin.From) / (spin.To - spin.From)
	-- eases in and out, full speed in the middle
	local angle = spin.Turns * 2 * math.pi * (p - math.sin(2 * math.pi * p) / (2 * math.pi))
	local k = math.clamp(math.min(p, 1 - p) / 0.2, 0, 1)
	local slide = (spin.Slide or 0) * k * k * (3 - 2 * k)
	local turn = if spin.Axis == "X" then CFrame.Angles(angle, 0, 0) else CFrame.Angles(0, angle, 0)
	return turn * CFrame.new(0, 0, slide)
end

function Combo.MovesFor(weapon: string?)
	return Combo.Sets[weapon or "Katana"] or Combo.Moves
end

-- Move `index` of a weapon's combo (wraps round), the katana's by default.
function Combo.Get(index: number, weapon: string?)
	local moves = Combo.MovesFor(weapon)
	return moves[((index - 1) % #moves) + 1]
end

-- The weapon type a character holds (its EquippedKatana's WeaponType attribute).
function Combo.WeaponOf(character: Instance?): string
	local weapon = character and character:FindFirstChild("EquippedKatana")
	local kind = weapon and weapon:GetAttribute("WeaponType")
	return if type(kind) == "string" then kind else "Katana"
end

return Combo
