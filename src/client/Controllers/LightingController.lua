--[[
	LightingController: every zone has its own mood. Entering a zone tweens
	the sky, fog/atmosphere and colour grading to that zone's Lighting table,
	shows the zone banner and switches music. Low Graphics disables ambient
	particles, bloom/sun rays and shadows.
]]

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Zones = require(Shared.Config.Zones)

local LightingController = {}

local controllers
local atmosphere: Atmosphere
local grading: ColorCorrectionEffect
local bloom: BloomEffect
local sunRays: SunRaysEffect
local currentZone: string? = nil
local lowGraphics = false

local function ensure(className: string, name: string): any
	local existing = Lighting:FindFirstChild(name)
	if existing and existing:IsA(className) then
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = Lighting
	return inst
end

local function tween(obj: Instance, props: { [string]: any }, time: number)
	TweenService:Create(obj, TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), props):Play()
end

function LightingController:ApplyZone(zoneId: string, instant: boolean?)
	local zone = Zones.Get(zoneId)
	if not zone or not zone.Lighting then
		return
	end
	local L = zone.Lighting
	local t = if instant then 0 else 2.2
	-- Readability floor: every zone keeps its colour mood (tints, fog colour) but is
	-- lit like a bright afternoon, since the dusk/night zones were too dark to play in
	-- (justin, 2026-10-01). Night and dusk clock times move into the day.
	local clock = L.ClockTime or 14
	if clock < 10 or clock > 16 then
		clock = if clock > 16 and clock < 20 then 15.5 else 13
	end
	tween(Lighting, {
		ClockTime = clock,
		Brightness = math.max(L.Brightness or 2, 3),
		ExposureCompensation = 0.2,
		Ambient = (L.Ambient or Color3.fromRGB(100, 100, 100)):Lerp(Color3.fromRGB(160, 160, 170), 0.65),
		OutdoorAmbient = (L.OutdoorAmbient or Color3.fromRGB(128, 128, 128)):Lerp(Color3.fromRGB(200, 200, 212), 0.6),
	}, t)
	tween(atmosphere, {
		Density = math.min(L.Density or 0.3, 0.3), Haze = math.min(L.Haze or 0, 1.2), Glare = L.Glare or 0,
		Color = (L.AtmosphereColor or Color3.fromRGB(200, 200, 210)):Lerp(Color3.fromRGB(225, 230, 240), 0.35),
		Decay = (L.FogColor or Color3.fromRGB(100, 100, 110)):Lerp(Color3.fromRGB(200, 205, 215), 0.45),
	}, t)
	tween(grading, {
		TintColor = (L.Tint or Color3.new(1, 1, 1)):Lerp(Color3.new(1, 1, 1), 0.5), Saturation = L.Saturation or 0,
		Contrast = math.min(L.Contrast or 0, 0.1), Brightness = 0.03,
	}, t)
end

local function enterZone(zoneId: string)
	if zoneId == currentZone then
		return
	end
	local first = currentZone == nil
	currentZone = zoneId
	LightingController:ApplyZone(zoneId, first)
	controllers.SoundController:PlayZoneMusic(zoneId)
	local zone = Zones.Get(zoneId)
	if zone and not first then
		controllers.NotificationController:Banner(zone.Name, "Recommended Lv " .. zone.Level .. "+", zone.Theme.Accent, 2.4)
	end
end

local function setEmitter(emitter: Instance)
	if emitter:IsA("ParticleEmitter") then
		emitter.Enabled = not lowGraphics
	end
end

local function applyGraphics(low: boolean)
	lowGraphics = low
	for _, emitter in ipairs(CollectionService:GetTagged("AmbientParticles")) do
		setEmitter(emitter)
	end
	Lighting.GlobalShadows = not low
	bloom.Enabled = not low
	sunRays.Enabled = not low
end

function LightingController:Start(c)
	controllers = c
	atmosphere = ensure("Atmosphere", "ZoneAtmosphere")
	grading = ensure("ColorCorrectionEffect", "ZoneGrading")
	bloom = ensure("BloomEffect", "ZoneBloom")
	bloom.Intensity = 0.6
	bloom.Size = 28
	bloom.Threshold = 1.6
	sunRays = ensure("SunRaysEffect", "ZoneSunRays")
	sunRays.Intensity = 0.06
	sunRays.Spread = 0.6

	Net.Event("ZoneChanged").OnClientEvent:Connect(enterZone)
	c.DataController:OnReady(function(data)
		enterZone(data.LastZone or "village")
	end)
	CollectionService:GetInstanceAddedSignal("AmbientParticles"):Connect(setEmitter)
	c.DataController:OnChange("Settings", function(settings)
		if (settings.LowGraphics == true) ~= lowGraphics then
			applyGraphics(settings.LowGraphics == true)
		end
	end)
end

return LightingController
