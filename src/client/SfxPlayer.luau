--!strict
-- Client sound effects (issue #62). Silent and error-free by default: Config.sfx ids are empty
-- placeholders, so with no id no Sound is created and every call returns at once. With ids it owns
-- a bounded pool of Config.audio.sfx.maxConcurrent (8) voices (a request with no free voice is
-- dropped, never a new Sound) plus one looping crowd ambience Sound. What plays, how loud, the
-- pitch spread and the per-slot cooldown come from the pure SfxMap; the intensity comes from
-- MusicPlayer, so a bigger parade makes bigger bangs. The crowd loop's volume follows the followers
-- and is slew-limited. Music ducking under big effects is not done (optional in the issue).
-- IN-ENGINE BEHAVIOUR IS UNVERIFIED (see the PR checklist and docs/audio-setup.md).
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AudioIntensity = require(Shared:WaitForChild("AudioIntensity"))
local Config = require(Shared:WaitForChild("Config"))
local SfxMap = require(Shared:WaitForChild("SfxMap"))

local MAX_DT = 0.1

export type SfxPlayer = {
	-- A server Event payload (gate, obstacle, cluster, attack, complete, defeated).
	onEvent: (self: SfxPlayer, payload: any, intensity: number, now: number) -> (),
	-- Play one slot by name, for example "replayClick".
	play: (self: SfxPlayer, slot: string, intensity: number, now: number) -> (),
	-- Once per frame: crowd-total changes (convert, +N, section rise) and the crowd ambience.
	update: (self: SfxPlayer, total: number, intensity: number, dt: number, now: number) -> (),
	-- Replay: stop everything, forget cooldowns and the previous total.
	reset: (self: SfxPlayer) -> (),
	-- Voices in the pool (0 while all ids are empty); never above the hard cap.
	voiceCount: (self: SfxPlayer) -> number,
}

local SfxPlayer = {}

function SfxPlayer.new(): SfxPlayer
	local a = (Config.audio :: any).sfx
	local cap = math.clamp(a.maxConcurrent, 1, 8)
	local anyId = false
	for _, slot in SfxMap.SLOTS do
		if SfxMap.playable(slot) then
			anyId = true
		end
	end
	local loopId = SfxMap.assetUri(Config.sfx.crowdLoop)

	local voices: { Sound } = {}
	local busy: { number } = {}
	local loop: Sound? = nil
	local folder: Folder? = nil

	if anyId or loopId ~= "" then
		local f = Instance.new("Folder")
		f.Name = "CalendaSfx"
		f.Parent = SoundService
		folder = f
	end
	if anyId and folder then
		for i = 1, cap do
			local s = Instance.new("Sound")
			s.Name = `voice{i}`
			s.Volume = 0
			s.Parent = folder
			voices[i] = s
		end
		-- Warm the cache so the first bang is not late (temporary Sounds, destroyed afterwards).
		task.spawn(function()
			local temps = {}
			for _, slot in SfxMap.SLOTS do
				if SfxMap.playable(slot) then
					local s = Instance.new("Sound")
					s.SoundId = SfxMap.assetUri(Config.sfx[slot])
					table.insert(temps, s)
				end
			end
			pcall(function()
				ContentProvider:PreloadAsync(temps)
			end)
			for _, s in temps do
				s:Destroy()
			end
		end)
	end
	if loopId ~= "" and folder then
		local s = Instance.new("Sound")
		s.Name = "crowdLoop"
		s.SoundId = loopId
		s.Looped = true
		s.Volume = 0
		s.Parent = folder
		loop = s
	end

	local limiter = SfxMap.limiter()
	local prevTotal: number? = nil
	local loopVolume = 0
	local loopStarted = false

	local self = {} :: SfxPlayer

	function self.play(_, slot: string, intensity: number, now: number)
		if not SfxMap.playable(slot) then
			return -- silent by default, and unknown slots
		end
		if not SfxMap.admit(limiter, slot, now) then
			return
		end
		local index = SfxMap.pick(busy, now, #voices)
		if index == nil then
			return
		end
		local voice = voices[index]
		voice.SoundId = SfxMap.assetUri(Config.sfx[slot])
		voice.Volume = SfxMap.volume(slot, intensity)
		voice.PlaybackSpeed = SfxMap.speed(intensity, math.random())
		voice.TimePosition = 0
		voice:Play()
		local length = if voice.TimeLength > 0 then voice.TimeLength else a.defaultSeconds
		busy[index] = now + math.min(length, 5)
	end

	function self.onEvent(_, payload: any, intensity: number, now: number)
		for _, slot in SfxMap.forEvent(payload) do
			self:play(slot, intensity, now)
		end
	end

	function self.update(_, total: number, intensity: number, dt: number, now: number)
		if prevTotal ~= nil then
			for _, slot in SfxMap.forTotalChange(prevTotal, total) do
				self:play(slot, intensity, now)
			end
		end
		prevTotal = total
		local s = loop
		if s then
			local d = math.clamp(dt, 0, MAX_DT)
			local goal = AudioIntensity.crowdLoopVolume(total)
			loopVolume = AudioIntensity.slew(
				loopVolume,
				goal,
				d,
				(Config.audio :: any).volumeSlew,
				(Config.audio :: any).volumeSlew
			)
			s.Volume = loopVolume
			if not loopStarted and s.IsLoaded then
				loopStarted = true
				s:Play()
			end
		end
	end

	function self.reset(_)
		limiter = SfxMap.limiter()
		prevTotal = nil
		for i, voice in voices do
			voice:Stop()
			voice.Volume = 0
			busy[i] = 0
		end
		if loop then
			loop:Stop()
			loop.Volume = 0
		end
		loopVolume = 0
		loopStarted = false
	end

	function self.voiceCount(_)
		return #voices
	end

	return self
end

return SfxPlayer
