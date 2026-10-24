--!strict
-- Client layered music (spec s10, issue #21). Silent by default: Config.music.stemSoundIds are
-- empty placeholders, and with no id no Sound is created, nothing plays and nothing errors. With
-- ids it creates at most Config.music.maxSources (4) looping Sounds, starts them together, and
-- copies MusicMixer's per-layer gains onto Sound.Volume each frame. Which layers sound and the
-- bar-boundary crossfades are decided by the pure MusicLayers / MusicMixer; the clock is the
-- local os.clock() since the stems were started (no server time involved).
-- Loops must be a whole number of bars so bar boundaries match the audio.
-- IN-ENGINE BEHAVIOUR IS UNVERIFIED (see the PR checklist).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CrowdMath = require(Shared:WaitForChild("CrowdMath"))
local MusicMixer = require(Shared:WaitForChild("MusicMixer"))

local LAYER_NAMES = { "percussion", "brass", "ensemble", "crowd" }

export type MusicPlayer = {
	-- Call once per frame with the replicated crowd total and os.clock().
	update: (self: MusicPlayer, total: number, now: number) -> (),
	-- Finale music peak hook: FinalePlan.at(t).musicIntensity (0..1). nil/0 = normal level.
	setPeak: (self: MusicPlayer, musicIntensity: number?) -> (),
	-- Replay: stop, rewind and forget the schedule. The next update starts the stems afresh.
	reset: (self: MusicPlayer) -> (),
	-- Number of Sound instances this player owns (0 while the stem ids are empty).
	soundCount: (self: MusicPlayer) -> number,
}

local MusicPlayer = {}

function MusicPlayer.new(): MusicPlayer
	local mixer = MusicMixer.new(Config :: any)
	local layers = MusicMixer.soundLayers(mixer)
	local sounds: { [string]: Sound } = {}

	if #layers > 0 then
		local f = Instance.new("Folder")
		f.Name = "CalendaMusic"
		f.Parent = SoundService
		for _, name in layers do
			local sound = Instance.new("Sound")
			sound.Name = name
			sound.SoundId = Config.music.stemSoundIds[table.find(LAYER_NAMES, name) :: number]
			sound.Looped = true
			sound.Volume = 0
			sound.Parent = f
			sounds[name] = sound
		end
	end

	local started = false
	local epoch = 0
	local peak = 0

	local function allLoaded(): boolean
		for _, sound in sounds do
			if not sound.IsLoaded then
				return false
			end
		end
		return true
	end

	local self = {} :: MusicPlayer

	function self.update(_, total: number, now: number)
		if #layers == 0 then
			return -- silent by default
		end
		if not started then
			-- Start every stem in the same frame so they stay in sync; wait for the assets first.
			if not allLoaded() then
				return
			end
			started = true
			epoch = now
			for _, sound in sounds do
				sound.TimePosition = 0
				sound.Volume = 0
				sound:Play()
			end
		end
		local t = now - epoch
		MusicMixer.setSections(mixer, CrowdMath.sectionCount(total), t)
		local gains = MusicMixer.gains(mixer, t)
		for name, sound in sounds do
			sound.Volume = MusicMixer.volume(gains[name] or 0, peak)
		end
	end

	function self.setPeak(_, musicIntensity: number?)
		peak = MusicMixer.peakAmount(musicIntensity or 0)
	end

	function self.reset(_)
		MusicMixer.reset(mixer)
		started = false
		peak = 0
		for _, sound in sounds do
			sound:Stop()
			sound.TimePosition = 0
			sound.Volume = 0
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
