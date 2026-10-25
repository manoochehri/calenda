--!strict
-- Audio tunables (issue #62), exposed as Config.audio. Pure data, no requires, so Config can load
-- it. Every value is a [default] placeholder chosen by the engineer: the spec gives no audio
-- numbers beyond s10 (at most 4 stems, controlled volume). Nothing here is a Roblox asset id.
return {
	-- Intensity curve: crowd size -> 0..1 on a log scale, so 10 -> 100 -> 1000 each step up and
	-- 10,000 (fullTotal) is the top; anything bigger stays at 1.
	refTotal = 10, -- [default] followers where the log curve starts to bend (ln(1 + n / refTotal))
	fullTotal = 10000, -- [default] followers at which intensity from the crowd reaches 1
	fullSections = 200, -- [default] sections at which intensity from the section count reaches 1
	sectionWeight = 0.25, -- [default] share of intensity that comes from the section count
	riseRate = 0.2, -- [default] intensity per second when growing (a 0 -> 1 swell takes 5 s)
	fallRate = 0.4, -- [default] intensity per second when shrinking
	volumeSlew = 1.5, -- [default] max change per second of any volume multiplier (no clicks)
	masterMin = 0.6, -- [default] music master gain at intensity 0
	masterMax = 1.0, -- [default] ... and at intensity 1 (hard ceiling: never above 1)
	defeatDuck = 0.2, -- [default] music multiplier while the party breaks up
	-- Four-stem mode: after a stem is gated on by sections, its level keeps growing with intensity.
	layerFloor = { 1, 0.5, 0.4, 0.3 }, -- [default] level of each stem right when it enters
	layerStart = { 0, 0.1, 0.35, 0.6 }, -- [default] intensity where each stem starts to grow
	layerWidth = 0.3, -- [default] intensity span over which a stem grows to full
	-- Single-track mode: SoundEffects on the track's SoundGroup (property ranges: docs/audio-setup.md)
	effects = {
		reverbDecay = { 1.2, 3.5 }, -- seconds, ReverbSoundEffect.DecayTime (0.1 to 20)
		reverbWet = { -24, -10 }, -- dB, WetLevel (-80 to 10)
		reverbDry = -6, -- dB, DryLevel (-80 to 10), the documented default
		chorusMix = { 0, 0.35 }, -- ChorusSoundEffect.Mix (0 to 1)
		chorusDepth = { 0.05, 0.3 }, -- Depth (0 to 1)
		chorusRate = 0.5, -- Rate (0 to 20), the documented default
		eqLow = { 0, 2 }, -- dB, EqualizerSoundEffect.LowGain (-80 to 10)
		eqMid = { 0, 2 }, -- dB, MidGain
		eqHigh = { 0, 3 }, -- dB, HighGain
		compThreshold = { 0, -16 }, -- dB, CompressorSoundEffect.Threshold (-80 to 0)
		compMakeup = { 0, 3 }, -- dB, GainMakeup (-30 to 30)
		compAttack = 0.1, -- seconds, Attack (0.1 to 1)
		compRelease = 0.1, -- seconds, Release (0 to 5)
	},
	-- Sound effects
	sfx = {
		maxConcurrent = 8, -- [default] hard cap on Sounds in the pool
		volumeMin = 0.55, -- [default] SFX volume multiplier at intensity 0
		volumeMax = 1.0, -- [default] ... at intensity 1
		maxVolume = 0.9, -- [default] hard ceiling for any one effect
		pitchMin = 0.02, -- [default] random PlaybackSpeed spread (+/-) at intensity 0
		pitchMax = 0.12, -- [default] ... at intensity 1
		defaultSeconds = 2, -- [default] how long a slot counts as busy when its length is unknown
		crowdLoopVolume = 0.35, -- [default] crowd ambience volume at fullTotal followers
		volumes = {
			gatePop = 0.6,
			convert = 0.5,
			sparkle = 0.35,
			shotLaunch = 0.3,
			shotImpact = 0.45,
			obstacleThud = 0.7,
			attackBonk = 0.8,
			followerHit = 0.7,
			sectionRise = 0.8,
			finalePeak = 0.9,
			defeatBreakup = 0.9,
			replayClick = 0.5,
		},
		cooldowns = { -- [default] seconds before the same slot may sound again
			gatePop = 0.15,
			convert = 0.12,
			sparkle = 0.2,
			shotLaunch = 0.12,
			shotImpact = 0.08,
			obstacleThud = 0.25,
			attackBonk = 0.15,
			followerHit = 0.3,
			sectionRise = 0.5,
			finalePeak = 2,
			defeatBreakup = 2,
			replayClick = 0.3,
		},
	},
}
