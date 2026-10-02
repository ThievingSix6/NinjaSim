--[[
	ParticleEmitter presets shared by katanas, auras, enemies and pets.
	Only built-in rbxasset textures are used so everything works with no uploads.
]]

local Particles = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local rgb = Color3.fromRGB
local NS = NumberSequence.new
local NSK = NumberSequenceKeypoint.new
local CS = ColorSequence.new

Particles.Presets = {
	Sparkle = {
		Texture = SPARKLE, Color = CS(rgb(230, 190, 255)), Rate = 8, Lifetime = NumberRange.new(0.5, 1),
		Speed = NumberRange.new(0.5, 1.5), Size = NS({ NSK(0, 0.25), NSK(1, 0) }), LightEmission = 1,
		SpreadAngle = Vector2.new(180, 180), Transparency = NS(0.1),
	},
	Droplets = {
		Texture = SPARKLE, Color = CS(rgb(120, 220, 255)), Rate = 6, Lifetime = NumberRange.new(0.6, 1),
		Speed = NumberRange.new(1, 2), Size = NS({ NSK(0, 0.2), NSK(1, 0) }), LightEmission = 0.8,
		Acceleration = Vector3.new(0, -6, 0), SpreadAngle = Vector2.new(60, 60), Transparency = NS(0.2),
	},
	Embers = {
		Texture = FIRE, Color = CS(rgb(255, 200, 80), rgb(255, 60, 20)), Rate = 12, Lifetime = NumberRange.new(0.5, 1),
		Speed = NumberRange.new(1, 3), Size = NS({ NSK(0, 0.35), NSK(1, 0) }), LightEmission = 1,
		Acceleration = Vector3.new(0, 4, 0), SpreadAngle = Vector2.new(30, 30), Transparency = NS({ NSK(0, 0.2), NSK(1, 1) }),
	},
	Smoke = {
		Texture = SMOKE, Color = CS(rgb(30, 30, 36)), Rate = 6, Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(0.5, 1.5), Size = NS({ NSK(0, 0.6), NSK(1, 1.4) }), LightEmission = 0,
		Acceleration = Vector3.new(0, 2, 0), SpreadAngle = Vector2.new(180, 180), Transparency = NS({ NSK(0, 0.5), NSK(1, 1) }),
	},
	Frost = {
		Texture = SPARKLE, Color = CS(rgb(220, 245, 255), rgb(120, 210, 255)), Rate = 10, Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(0.3, 1), Size = NS({ NSK(0, 0.3), NSK(1, 0) }), LightEmission = 1,
		Acceleration = Vector3.new(0, -1.5, 0), SpreadAngle = Vector2.new(180, 180), Transparency = NS(0.1),
	},
	Radiance = {
		Texture = SPARKLE, Color = CS(rgb(255, 250, 200), rgb(255, 190, 40)), Rate = 14, Lifetime = NumberRange.new(0.6, 1.2),
		Speed = NumberRange.new(1, 2.5), Size = NS({ NSK(0, 0.4), NSK(1, 0) }), LightEmission = 1,
		SpreadAngle = Vector2.new(180, 180), Transparency = NS(0),
	},
	BloodFlame = {
		Texture = FIRE, Color = CS(rgb(255, 60, 90), rgb(90, 0, 20)), Rate = 16, Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(1, 3), Size = NS({ NSK(0, 0.5), NSK(1, 0) }), LightEmission = 0.7,
		Acceleration = Vector3.new(0, 5, 0), SpreadAngle = Vector2.new(25, 25), Transparency = NS({ NSK(0, 0.1), NSK(1, 1) }),
	},
	Shadow = {
		Texture = SMOKE, Color = CS(rgb(90, 40, 170), rgb(10, 0, 20)), Rate = 10, Lifetime = NumberRange.new(0.8, 1.5),
		Speed = NumberRange.new(0.5, 1.5), Size = NS({ NSK(0, 0.8), NSK(1, 1.6) }), LightEmission = 0.3,
		Acceleration = Vector3.new(0, 1.5, 0), SpreadAngle = Vector2.new(180, 180), Transparency = NS({ NSK(0, 0.4), NSK(1, 1) }),
	},
	Stars = {
		Texture = SPARKLE, Color = CS(rgb(255, 245, 200), rgb(140, 200, 255)), Rate = 12, Lifetime = NumberRange.new(1, 1.8),
		Speed = NumberRange.new(0.3, 1), Size = NS({ NSK(0, 0), NSK(0.3, 0.45), NSK(1, 0) }), LightEmission = 1,
		SpreadAngle = Vector2.new(180, 180), Transparency = NS(0), RotSpeed = NumberRange.new(-90, 90),
	},
	Void = {
		Texture = SPARKLE, Color = CS(rgb(255, 120, 255), rgb(60, 0, 120)), Rate = 18, Lifetime = NumberRange.new(0.6, 1.2),
		Speed = NumberRange.new(-2, -0.5), Size = NS({ NSK(0, 0.5), NSK(1, 0) }), LightEmission = 1,
		SpreadAngle = Vector2.new(180, 180), Transparency = NS(0), RotSpeed = NumberRange.new(-180, 180),
	},
	Petals = {
		Texture = SPARKLE, Color = CS(rgb(255, 190, 210), rgb(255, 140, 180)), Rate = 6, Lifetime = NumberRange.new(2, 3),
		Speed = NumberRange.new(0.5, 1.5), Size = NS({ NSK(0, 0.35), NSK(1, 0.2) }), LightEmission = 0.3,
		Acceleration = Vector3.new(0.5, -1.2, 0), SpreadAngle = Vector2.new(180, 180), Transparency = NS(0.1),
		RotSpeed = NumberRange.new(-120, 120),
	},
	Lightning = {
		Texture = SPARKLE, Color = CS(rgb(200, 240, 255), rgb(80, 160, 255)), Rate = 20, Lifetime = NumberRange.new(0.15, 0.3),
		Speed = NumberRange.new(4, 8), Size = NS({ NSK(0, 0.5), NSK(1, 0) }), LightEmission = 1,
		SpreadAngle = Vector2.new(180, 180), Transparency = NS(0),
	},
	Spirit = {
		Texture = FIRE, Color = CS(rgb(160, 255, 240), rgb(40, 160, 255)), Rate = 18, Lifetime = NumberRange.new(0.6, 1),
		Speed = NumberRange.new(1, 3), Size = NS({ NSK(0, 0.6), NSK(1, 0) }), LightEmission = 1,
		Acceleration = Vector3.new(0, 5, 0), SpreadAngle = Vector2.new(20, 20), Transparency = NS({ NSK(0, 0.2), NSK(1, 1) }),
	},
	Galaxy = {
		Texture = SPARKLE, Color = CS(rgb(255, 200, 255), rgb(120, 140, 255)), Rate = 22, Lifetime = NumberRange.new(1.2, 2),
		Speed = NumberRange.new(0.2, 0.8), Size = NS({ NSK(0, 0), NSK(0.4, 0.4), NSK(1, 0) }), LightEmission = 1,
		SpreadAngle = Vector2.new(180, 180), Transparency = NS(0), RotSpeed = NumberRange.new(-60, 60),
	},
}

-- Create an emitter from a preset. `overrides` may change any property (e.g. Rate, Color).
function Particles.Create(presetName: string, parent: Instance, overrides: { [string]: any }?): ParticleEmitter?
	local preset = Particles.Presets[presetName]
	if not preset then
		return nil
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = presetName
	for key, value in pairs(preset) do
		(emitter :: any)[key] = value
	end
	if overrides then
		for key, value in pairs(overrides) do
			(emitter :: any)[key] = value
		end
	end
	emitter.Parent = parent
	return emitter
end

return Particles
