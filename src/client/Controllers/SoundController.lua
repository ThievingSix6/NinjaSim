--[[
	SoundController: plays UI/combat sounds from Config/Sounds with pitch variety,
	respecting the player's SFX / Music volume settings. Sounds are pooled.
]]

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)

local SoundController = {}

local sfxVolume = 0.8
local musicVolume = 0.5
local pools: { [string]: { Sound } } = {}
local music: Sound? = nil
local group: SoundGroup

local function getSound(name: string): Sound?
	local def = Sounds[name]
	if not def or type(def) ~= "table" or not def.Id then
		return nil
	end
	local pool = pools[name]
	if not pool then
		pool = {}
		pools[name] = pool
	end
	for _, s in ipairs(pool) do
		if not s.IsPlaying then
			return s
		end
	end
	if #pool >= 6 then
		return pool[1]
	end
	local s = Instance.new("Sound")
	s.SoundId = def.Id
	s.SoundGroup = group
	s.Parent = SoundService
	table.insert(pool, s)
	return s
end

function SoundController:Play(name: string, volumeScale: number?, pitchOverride: number?)
	local def = Sounds[name]
	local s = getSound(name)
	if not s or not def then
		return
	end
	local pitch = pitchOverride or (def.Pitch[1] + math.random() * (def.Pitch[2] - def.Pitch[1]))
	s.PlaybackSpeed = pitch
	s.Volume = def.Volume * (volumeScale or 1)
	s.TimePosition = 0
	s:Play()
end

function SoundController:SetVolumes(sfx: number, musicVol: number)
	sfxVolume = sfx
	musicVolume = musicVol
	group.Volume = sfxVolume
	if music then
		music.Volume = musicVolume * (Sounds.MusicVolume or 0.5)
	end
end

-- Plays the area's own music, or else the shared Playlist, one track after another.
local playlist: { string } = {}
local track = 0
local function playTrack()
	local m = music :: Sound
	m.SoundId = playlist[track]
	m.Looped = #playlist == 1
	m.TimePosition = 0
	m:Play()
end

function SoundController:PlayZoneMusic(zoneId: string)
	local entry = Sounds.Music[zoneId] or Sounds.Playlist
	local list: { string } = {}
	if type(entry) == "string" then
		entry = { entry }
	end
	for _, id in ipairs(entry or {}) do
		if type(id) == "string" and id ~= "" then
			table.insert(list, id)
		end
	end
	if #list == 0 then
		playlist = {}
		if music then
			music:Stop()
		end
		return
	end
	if table.concat(list, "|") == table.concat(playlist, "|") and music and music.IsPlaying then
		return -- same music as the last area: keep playing
	end
	if not music then
		local m = Instance.new("Sound")
		m.Name = "Music"
		m.Parent = SoundService
		m.Ended:Connect(function()
			if #playlist > 1 then
				track = track % #playlist + 1
				playTrack()
			end
		end)
		music = m
	end
	;(music :: Sound).Volume = musicVolume * (Sounds.MusicVolume or 0.5)
	playlist = list
	track = 1
	playTrack()
end

function SoundController:Start(controllers)
	group = Instance.new("SoundGroup")
	group.Name = "SFX"
	group.Volume = sfxVolume
	group.Parent = SoundService
	controllers.Kit.Sound = function(name: string)
		self:Play(name)
	end
	controllers.DataController:OnChange("Settings", function(settings)
		self:SetVolumes(settings.SFX, settings.Music)
	end)
end

return SoundController
