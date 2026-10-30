--!strict
-- Client music (spec s10, issues #21 and #62). Silent by default: with no ids no Sound is created,
-- nothing plays and nothing errors. Two modes:
--   * four stems (Config.music.stemSoundIds): at most 4 looping Sounds; which stems sound and the
--     bar-boundary crossfades come from MusicLayers / MusicMixer, and each stem's level also
--     follows the continuous AudioIntensity (percussion always, the others grow with the parade).
--   * single track (Config.music.trackSoundId, used only when no stem id is set): one looping Sound
--     on a SoundGroup whose Reverb, Chorus, Equalizer and Compressor children grow with intensity.
-- Both go through one SoundGroup whose Volume is the master gain (gentle swell, defeat duck).
-- Intensity, the duck and the track's fade-in are all slew-limited, so nothing clicks.
-- Loops must be a whole number of bars (120 bpm, 4/4 = 2 s per bar) so bar boundaries match.
-- IN-ENGINE BEHAVIOUR IS UNVERIFIED (see the PR checklist and docs/audio-setup.md).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AudioIntensity = require(Shared:WaitForChild("AudioIntensity"))
local Config = require(Shared:WaitForChild("Config"))
local CrowdMath = require(Shared:WaitForChild("CrowdMath"))
local MusicMixer = require(Shared:WaitForChild("MusicMixer"))
local SfxMap = require(Shared:WaitForChild("SfxMap"))

local LAYER_NAMES = { "percussion", "brass", "ensemble", "crowd" }
local MAX_DT = 0.1 -- a long frame must not make a slewed value jump

export type MusicPlayer = {
	-- Start immediately from the user's Jugar action; playback can begin while the asset streams.
	start: (self: MusicPlayer, now: number) -> (),
	-- Call once per frame with the replicated crowd total and os.clock().
	update: (self: MusicPlayer, total: number, now: number) -> (),
	-- Finale music peak hook: FinalePlan.at(t).musicIntensity (0..1). nil/0 = normal level.
	setPeak: (self: MusicPlayer, musicIntensity: number?) -> (),
	-- Defeat: duck the music (true) or bring it back (false).
	setDucked: (self: MusicPlayer, ducked: boolean) -> (),
	-- The smoothed audio intensity 0..1 (shared with SfxPlayer so bangs grow with the parade).
	intensity: (self: MusicPlayer) -> number,
	-- Replay: intensity, peak and duck back to the start (the "audio" reset item).
	resetAudio: (self: MusicPlayer) -> (),
	-- Replay: stop, rewind and forget the schedule. The next update starts the music afresh.
	reset: (self: MusicPlayer) -> (),
	-- Number of music Sound instances this player owns (0 while the ids are empty).
	soundCount: (self: MusicPlayer) -> number,
}

local MusicPlayer = {}

local function makeEffects(group: SoundGroup): { [string]: Instance }
	local reverb = Instance.new("ReverbSoundEffect")
	local chorus = Instance.new("ChorusSoundEffect")
	local eq = Instance.new("EqualizerSoundEffect")
	local comp = Instance.new("CompressorSoundEffect")
	for _, fx in { reverb, chorus, eq, comp } do
		fx.Parent = group
	end
	return { reverb = reverb, chorus = chorus, eq = eq, comp = comp }
end

function MusicPlayer.new(): MusicPlayer
	local mixer = MusicMixer.new(Config :: any)
	local layers = MusicMixer.soundLayers(mixer)
	local trackId = SfxMap.assetUri((Config.music :: any).trackSoundId)
	local mode = if #layers > 0 then "stems" elseif trackId ~= "" then "track" else "silent"
	local sounds: { [string]: Sound } = {}
	local group: SoundGroup? = nil
	-- Issue #172: one tempo/pitch setting for every music Sound (nil = the recording's own speed).
	local speed = (Config.music :: any).playbackSpeed or 1
	local effects: { [string]: any } = {}

	if mode ~= "silent" then
		local g = Instance.new("SoundGroup")
		g.Name = "CalendaMusicGroup"
		g.Volume = 0
		g.Parent = SoundService
		group = g
		if mode == "stems" then
			for _, name in layers do
				local sound = Instance.new("Sound")
				sound.Name = name
				sound.SoundId = SfxMap.assetUri(
					Config.music.stemSoundIds[table.find(LAYER_NAMES, name) :: number]
				)
				sound.Looped = true
				sound.PlaybackSpeed = speed
				sound.Volume = 0
				sound.SoundGroup = g
				sound.Parent = g
				sounds[name] = sound
			end
		else
			local sound = Instance.new("Sound")
			sound.Name = "track"
			sound.SoundId = trackId
			sound.Looped = true
			sound.PlaybackSpeed = speed
			sound.Volume = 0
			sound.SoundGroup = g
			sound.Parent = g
			sounds.track = sound
			effects = makeEffects(g)
		end
	end

	local a = Config.audio :: any
	local started = false
	local startRequested = false
	local epoch = 0
	local lastNow: number? = nil
	local peakRaw = 0 -- FinalePlan musicIntensity, 0 = none
	local peak = 0 -- MusicMixer.peakAmount of it
	local intensity = 0
	local duckTarget = 1
	local duck = 1
	local fadeIn = 0 -- single track: start-of-run fade 0..1
	local self = {} :: MusicPlayer

	local function allLoaded(): boolean
		for _, sound in sounds do
			if not sound.IsLoaded then
				return false
			end
		end
		return true
	end

	local function tryStart(now: number)
		if mode == "silent" or started or not startRequested or not allLoaded() then
			return
		end
		started = true
		epoch = now
		lastNow = nil
		for _, sound in sounds do
			sound:Play()
		end
	end

	local function applyEffects()
		local e = AudioIntensity.effects(intensity)
		local r, c, q, k = effects.reverb, effects.chorus, effects.eq, effects.comp
		r.DecayTime, r.WetLevel, r.DryLevel = e.reverbDecay, e.reverbWet, e.reverbDry
		c.Mix, c.Depth, c.Rate = e.chorusMix, e.chorusDepth, e.chorusRate
		q.LowGain, q.MidGain, q.HighGain = e.eqLow, e.eqMid, e.eqHigh
		k.Threshold, k.GainMakeup, k.Attack, k.Release =
			e.compThreshold, e.compMakeup, e.compAttack, e.compRelease
		return AudioIntensity.compensation(e)
	end

	for _, sound in sounds do
		sound.Loaded:Connect(function()
			tryStart(os.clock())
		end)
	end

	function self.start(_, now: number)
		if mode == "silent" or startRequested then
			return
		end
		startRequested = true
		tryStart(now)
	end

	function self.update(_, total: number, now: number)
		if mode == "silent" then
			return -- silent by default
		end
		local dt = if lastNow then math.clamp(now - lastNow, 0, MAX_DT) else 0
		lastNow = now
		if not started then
			-- Also supports replay, whose server State arrives after the button press.
			if not startRequested then
				self:start(now)
			end
			tryStart(now)
			if not started then
				return -- wait for Loaded; the Jugar request remains queued
			end
		end
		local t = now - epoch
		local sections = CrowdMath.sectionCount(total)
		local goal = AudioIntensity.withPeak(AudioIntensity.target(total, sections), peakRaw)
		intensity = AudioIntensity.slew(intensity, goal, dt, a.riseRate, a.fallRate)
		duck = AudioIntensity.slew(duck, duckTarget, dt, a.volumeSlew, a.volumeSlew)
		local comp = 1
		if mode == "stems" then
			MusicMixer.setSections(mixer, sections, t)
			local gains = MusicMixer.gains(mixer, t)
			for name, sound in sounds do
				local index = table.find(LAYER_NAMES, name) :: number
				local weight = AudioIntensity.layerWeight(index, intensity)
				sound.Volume = MusicMixer.volume((gains[name] or 0) * weight, peak)
			end
		else
			fadeIn = AudioIntensity.slew(fadeIn, 1, dt, a.volumeSlew, a.volumeSlew)
			comp = applyEffects()
			sounds.track.Volume = MusicMixer.volume(fadeIn, peak)
		end
		if group then
			group.Volume = AudioIntensity.masterGain(intensity) * duck * comp
		end
	end

	function self.setPeak(_, musicIntensity: number?)
		peakRaw = musicIntensity or 0
		peak = MusicMixer.peakAmount(peakRaw)
	end

	function self.setDucked(_, ducked: boolean)
		duckTarget = if ducked then a.defeatDuck else 1
	end

	function self.intensity(_)
		return intensity
	end

	function self.resetAudio(_)
		intensity = 0
		peakRaw = 0
		peak = 0
		duckTarget = 1
		duck = 1
		fadeIn = 0
		lastNow = nil
	end

	function self.reset(_)
		MusicMixer.reset(mixer)
		started = false
		startRequested = false
		self:resetAudio()
		for _, sound in sounds do
			sound:Stop()
			if sound.IsLoaded then
				sound.TimePosition = 0
			end
			sound.Volume = 0
		end
		if group then
			group.Volume = 0
		end
	end

	function self.soundCount(_)
		local n = 0
		for _ in sounds do
			n += 1
		end
		return n
	end

	return self
end

return MusicPlayer
