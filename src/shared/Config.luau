--!strict
-- Every gameplay tunable for the prototype (spec section 11). No magic numbers elsewhere.
-- Values marked [spec] come from docs/Calenda-Prototype-Spec.md; values marked [default] are
-- placeholders chosen by the engineer because the spec gives no number (all are tuning defaults).

export type ClusterType = { hits: number, reward: number }
export type GateOp = { kind: string, value: number }
export type Curve = { start: number, max: number, sectionsToMax: number }
-- Spectators as individuals across the lane (issue #65; see SpectatorScatter). Studs unless noted.
export type ScatterConfig = {
	perReward: number, -- individuals per cluster reward point, capped per mob by QualityConfig
	spreadHalfWidth: number, -- half the lane the individuals spread across
	colSpacing: number, -- smallest spacing between columns across the lane
	rowSpacing: number, -- spacing between rows, front to back
	jitter: number, -- random offset of each individual, as a fraction of its spacing (0..0.5)
	minSeparation: number, -- no two individuals closer than this
	bunchRadius: number, -- a bunch is individuals this close to one another
	maxBunch: number, -- most individuals allowed in one bunch
	minScreenFraction: number, -- a figure reads at this share of screen height (phone, high camera)
	maxScale: number, -- at most this much a far figure is enlarged to keep reading (>= 1)
	bodyWidth: number, -- torso width in studs
	bodyHeight: number, -- torso height in studs
	bodyDepth: number, -- torso depth in studs
	headDiameter: number, -- spherical head diameter in studs
	armsWidth: number, -- raised arms width in studs
	armsHeight: number, -- raised arms height in studs
	armsDepth: number, -- raised arms depth in studs
	startDelayMax: number, -- maximum independently seeded delay before a figure starts moving
	approachSpeedSpread: number, -- per-person speed variation as a share of approachSpeed
	longitudinalJitter: number, -- independently seeded front/back spawn offset in studs
	lateralWander: number, -- independently seeded lateral turn distance in studs
	turnDelayMax: number, -- maximum independently seeded delay before a lateral turn
	turnSeconds: number, -- duration of each figure's lateral turn
	arrivalSpread: number, -- per-person variation around the mob's contact distance
}
export type MusicConfig = {
	bpm: number,
	beatsPerBar: number,
	fadeBars: number,
	maxSources: number,
	stemSoundIds: { string },
	trackSoundId: string?, -- single-track mode (issue #62): one looped asset, empty = off
	playbackSpeed: number?, -- issue #172: Sound.PlaybackSpeed for the music (tempo and pitch); nil = 1
}
export type ConfigType = {
	sectionSize: number,
	startingTotal: number,
	clusterTypes: { small: ClusterType, large: ClusterType },
	gateOps: { GateOp },
	obstacleLoss: number,
	attackSharePercent: number,
	minShareLoss: number,
	hazards: { tomatoSharePercent: number },
	layout: { maxTotal: number },
	speed: number,
	firing: { base: number, cap: number, perSection: number, range: number },
	spectators: { approachSpeed: number, centerTolerance: number, scatter: ScatterConfig },
	visualBudget: {
		sectionRepresentatives: number,
		looseAvatars: number,
		cameraPullback: Curve,
		formationDensity: Curve,
	},
	finaleThresholds: { number },
	levelPlayOrder: { string }, -- level ids in play order (issue #128); reaching a level's finale moves on
	giftEveryNthShot: number,
	durations: { assemblySeconds: number, dispersalSeconds: number },
	musicLayerSections: { number },
	music: MusicConfig,
	debug: {
		startupTiming: boolean,
		freezeCamera: boolean,
		noShadows: boolean,
		rawExtrapolation: boolean,
		noTrails: boolean, -- issue #171 A/B: no shot Trails
		noHitShake: boolean, -- issue #171 A/B: no hit camera shake
		noTransparentStrips: boolean, -- issue #171 A/B: gate crossing strip and lead ring opaque
		noDust: boolean, -- issue #171 A/B: no dust ParticleEmitter output
		quality: string?, -- nil = automatic; "low" | "medium" | "high" forces the mob quality (issue #65)
	},
	audio: { [string]: any }, -- AudioIntensity / SfxMap tuning (issue #62)
	sfx: { [string]: string }, -- sound effect asset ids by slot, empty = silent (issue #62)
	validate: (config: any) -> (boolean, string?),
}

local function isPositiveInt(v: any): boolean
	return type(v) == "number" and v > 0 and v == math.floor(v) and v < math.huge
end

local function isPercent(v: any): boolean
	return type(v) == "number" and v >= 1 and v <= 100 and v == math.floor(v)
end

local function isPositive(v: any): boolean
	return type(v) == "number" and v > 0 and v < math.huge
end

-- A saturating linear curve over logical sections: start at 0 sections, max at sectionsToMax.
local function validCurve(c: any): boolean
	return type(c) == "table"
		and type(c.start) == "number"
		and c.start >= 0
		and c.start < math.huge
		and type(c.max) == "number"
		and c.max >= c.start
		and c.max < math.huge
		and isPositiveInt(c.sectionsToMax)
end

local function ascending(list: any, firstMin: number): boolean
	if type(list) ~= "table" or #list == 0 then
		return false
	end
	local prev = firstMin - 1
	for i = 1, #list do
		local v = list[i]
		if type(v) ~= "number" or v ~= math.floor(v) or v <= prev then
			return false
		end
		prev = v
	end
	return true
end

-- Returns true, or false plus the first problem found. Pure: usable on any candidate table.
local function validate(c: any): (boolean, string?)
	if type(c) ~= "table" then
		return false, "config must be a table"
	end
	for _, key in { "sectionSize", "obstacleLoss", "giftEveryNthShot", "minShareLoss" } do
		if not isPositiveInt(c[key]) then
			return false, `{key} must be a positive integer`
		end
	end
	if
		type(c.startingTotal) ~= "number"
		or c.startingTotal < 0
		or c.startingTotal ~= math.floor(c.startingTotal)
	then
		return false, "startingTotal must be a non-negative integer"
	end
	if type(c.debug) ~= "table" or type(c.debug.startupTiming) ~= "boolean" then
		return false, "debug.startupTiming must be a boolean"
	end
	for _, flag in
		{
			"freezeCamera",
			"noShadows",
			"rawExtrapolation",
			"noTrails",
			"noHitShake",
			"noTransparentStrips",
			"noDust",
		}
	do
		if type(c.debug[flag]) ~= "boolean" then
			return false, `debug.{flag} must be a boolean`
		end
	end
	local q = c.debug.quality
	if q ~= nil and q ~= "low" and q ~= "medium" and q ~= "high" then
		return false, 'debug.quality must be nil, "low", "medium" or "high"'
	end
	if not isPositive(c.speed) then
		return false, "speed must be a positive number"
	end

	if type(c.clusterTypes) ~= "table" then
		return false, "clusterTypes must be a table"
	end
	for _, name in { "small", "large" } do
		local ct = c.clusterTypes[name]
		if type(ct) ~= "table" or not isPositiveInt(ct.hits) or not isPositiveInt(ct.reward) then
			return false, `clusterTypes.{name} needs positive integer hits and reward`
		end
	end
	if not isPercent(c.attackSharePercent) then
		return false, "attackSharePercent must be a whole number from 1 to 100"
	end
	if type(c.hazards) ~= "table" or not isPercent(c.hazards.tomatoSharePercent) then
		return false, "hazards.tomatoSharePercent must be a whole number from 1 to 100"
	end
	if type(c.layout) ~= "table" or not isPositiveInt(c.layout.maxTotal) then
		return false, "layout.maxTotal must be a positive integer"
	end

	if type(c.gateOps) ~= "table" or #c.gateOps == 0 then
		return false, "gateOps must be a non-empty list"
	end
	for i, op in c.gateOps do
		if type(op) ~= "table" or not isPositiveInt(op.value) then
			return false, `gateOps[{i}] needs a positive integer value`
		end
		if op.kind ~= "add" and op.kind ~= "multiply" then
			return false, `gateOps[{i}].kind must be "add" or "multiply"`
		end
		if op.kind == "multiply" and op.value < 2 then
			return false, `gateOps[{i}] multiply value must be >= 2`
		end
	end

	local f = c.firing
	if
		type(f) ~= "table"
		or not isPositiveInt(f.base)
		or not isPositiveInt(f.cap)
		or not isPositiveInt(f.perSection)
	then
		return false, "firing needs positive integer base, cap and perSection"
	end
	if f.cap < f.base then
		return false, "firing.cap must be >= firing.base"
	end
	-- Every shot is one replicated event (ADR 0004), so the rate is bounded by the 30 Hz server tick.
	if f.cap > 30 then
		return false, "firing.cap must be <= 30 (one shot event per 30 Hz server tick)"
	end
	if not isPositive(f.range) then
		return false, "firing.range must be a positive number"
	end

	local sp = c.spectators
	if type(sp) ~= "table" or not isPositive(sp.approachSpeed) then
		return false, "spectators.approachSpeed must be a positive number"
	end
	if
		type(sp.centerTolerance) ~= "number"
		or sp.centerTolerance < 0
		or sp.centerTolerance == math.huge
	then
		return false, "spectators.centerTolerance must be a non-negative number"
	end

	local sc = sp.scatter
	if type(sc) ~= "table" then
		return false, "spectators.scatter must be a table"
	end
	for _, key in
		{
			"perReward",
			"spreadHalfWidth",
			"colSpacing",
			"rowSpacing",
			"minSeparation",
			"bunchRadius",
			"minScreenFraction",
			"bodyWidth",
			"bodyHeight",
			"bodyDepth",
			"headDiameter",
			"armsWidth",
			"armsHeight",
			"armsDepth",
			"startDelayMax",
			"longitudinalJitter",
			"lateralWander",
			"turnDelayMax",
			"turnSeconds",
			"arrivalSpread",
		}
	do
		if not isPositive((sc :: any)[key]) then
			return false, `spectators.scatter.{key} must be a positive number`
		end
	end
	if type(sc.jitter) ~= "number" or sc.jitter < 0 or sc.jitter >= 0.5 then
		return false, "spectators.scatter.jitter must be in [0, 0.5)"
	end
	if not isPositiveInt(sc.maxBunch) then
		return false, "spectators.scatter.maxBunch must be a positive integer"
	end
	if type(sc.maxScale) ~= "number" or sc.maxScale < 1 or sc.maxScale == math.huge then
		return false, "spectators.scatter.maxScale must be a number >= 1"
	end
	if
		type(sc.approachSpeedSpread) ~= "number"
		or sc.approachSpeedSpread < 0
		or sc.approachSpeedSpread >= 0.5
	then
		return false, "spectators.scatter.approachSpeedSpread must be in [0, 0.5)"
	end
	if sc.minScreenFraction < 0.02 then
		return false, "spectators.scatter.minScreenFraction must be >= 0.02 for readable figures"
	end
	if sc.headDiameter < sc.bodyHeight * 0.5 then
		return false, "spectators.scatter.headDiameter must be at least half the body height"
	end

	local v = c.visualBudget
	if
		type(v) ~= "table"
		or not isPositiveInt(v.sectionRepresentatives)
		or not isPositiveInt(v.looseAvatars)
	then
		return false, "visualBudget needs positive integer sectionRepresentatives and looseAvatars"
	end
	for _, name in { "cameraPullback", "formationDensity" } do
		if not validCurve(v[name]) then
			return false,
				`visualBudget.{name} needs numeric start >= 0, max >= start and positive integer sectionsToMax`
		end
	end

	-- Issue #128: a non-empty list of distinct, non-empty level ids. LevelChain maps them to layouts.
	if type(c.levelPlayOrder) ~= "table" or #c.levelPlayOrder == 0 then
		return false, "levelPlayOrder must be a non-empty list of level ids"
	end
	local seenLevel: { [string]: boolean } = {}
	for _, id in c.levelPlayOrder do
		if type(id) ~= "string" or id == "" or seenLevel[id] then
			return false, "levelPlayOrder must hold distinct, non-empty level ids"
		end
		seenLevel[id] = true
	end

	if not ascending(c.finaleThresholds, 1) then
		return false, "finaleThresholds must be a strictly ascending list of positive integers"
	end
	if not ascending(c.musicLayerSections, 0) then
		return false,
			"musicLayerSections must be a strictly ascending list of non-negative integers"
	end

	local m = c.music
	if type(m) ~= "table" then
		return false, "music must be a table"
	end
	if not isPositive(m.bpm) then
		return false, "music.bpm must be a positive number"
	end
	if not isPositiveInt(m.beatsPerBar) or not isPositiveInt(m.fadeBars) then
		return false, "music.beatsPerBar and music.fadeBars must be positive integers"
	end
	-- Spec s10: adding sections must not add unlimited audio sources; 4 is the hard maximum.
	if not isPositiveInt(m.maxSources) or m.maxSources > 4 then
		return false, "music.maxSources must be an integer from 1 to 4"
	end
	if type(m.stemSoundIds) ~= "table" or #m.stemSoundIds ~= #c.musicLayerSections then
		return false, "music.stemSoundIds needs one entry per musicLayerSections entry"
	end
	for i = 1, #c.musicLayerSections do
		if type(m.stemSoundIds[i]) ~= "string" then
			return false, `music.stemSoundIds[{i}] must be a string`
		end
	end
	if m.trackSoundId ~= nil and type(m.trackSoundId) ~= "string" then
		return false, "music.trackSoundId must be a string"
	end
	-- Issue #172: a speed outside this range is a mistake, not a mix choice (0 would stop playback).
	if
		m.playbackSpeed ~= nil
		and not (
			type(m.playbackSpeed) == "number"
			and m.playbackSpeed >= 0.5
			and m.playbackSpeed <= 2
		)
	then
		return false, "music.playbackSpeed must be a number from 0.5 to 2"
	end
	if c.sfx ~= nil then
		for slot, id in c.sfx do
			if type(id) ~= "string" then
				return false, `sfx.{slot} must be a string`
			end
		end
	end

	local d = c.durations
	if
		type(d) ~= "table"
		or not isPositive(d.assemblySeconds)
		or not isPositive(d.dispersalSeconds)
	then
		return false, "durations needs positive assemblySeconds and dispersalSeconds"
	end
	return true, nil
end

local function deepFreeze<T>(t: T): T
	if type(t) == "table" then
		for _, child in t :: any do
			deepFreeze(child)
		end
		table.freeze(t :: any)
	end
	return t
end

local config: ConfigType = {
	sectionSize = 50, -- [spec s5]
	startingTotal = 0, -- owner direction #226, spec Amendment 13: recruit everyone during play
	clusterTypes = {
		-- hits/reward [spec s4]. An unconverted horde costs attackSharePercent of the parade (any type).
		small = { hits = 3, reward = 5 },
		large = { hits = 8, reward = 15 },
	},
	-- [default] The spec only gives +N and xN as the allowed forms; +20 and x2 are its examples (s6).
	gateOps = {
		{ kind = "add", value = 20 },
		{ kind = "multiply", value = 2 },
	},
	obstacleLoss = 10, -- [spec s9] fixed
	-- ADR 0007 (provisional, Amendment 4; supersedes ADR 0006's loss rule): an unconverted horde and an unblocked tomato each remove
	-- floor(percent * parade / 100) followers, the parade as it stood before the hit, and never fewer
	-- than minShareLoss. Tune with the #17 ladder.
	-- Owner approval (2026-10-26, issue #148): 10 -> 7. Measured under the share rule on 3 layouts,
	-- seeds 1-10, 30 Hz, n=3 effective per policy. At 6, no-input and always-center completed 10 of 30
	-- (one layout, all seeds). At 5, 4 and 3, no-input was also not defeated on every layout. The
	-- defeat holds on every layout from 7 upward. The scripted margin was 123 to 172. UNVERIFIED for
	-- the skeptic; the #17 ladder re-run is still open.
	attackSharePercent = 7, -- [owner-approved 2026-10-26, provisional]
	minShareLoss = 1, -- [default, provisional]
	-- Issue #96: followers lost once when an unblocked tomato hits the lead. Blocking is by a landed
	-- gift. [default, provisional]
	hazards = { tomatoSharePercent = 10 },
	-- Owner decision (2026-10-26, issue #142): the validator's bound on every layout's best-route
	-- final total. Raised from 2500 so the continuous-hordes layouts pass.
	-- POST-HOC FIT: 4000 was chosen AFTER the best routes were known (calle-del-mercado 3390,
	-- portal-del-sur 3850, esquina-de-la-banda 3490); it is the smallest round value above the
	-- highest of them. It is a fit to the output, not a pre-set bound, so the validator passing
	-- is not independent evidence. The 3850 best route is a steering-optimistic ceiling from the
	-- validator's optimiser (perfect steering and foresight), not a total any bot or player reaches.
	-- Not a balance claim: the balance evidence is UNVERIFIED until the skeptic holds it.
	layout = { maxTotal = 4000 },
	speed = 7.2, -- [default] studs/second; half the first playable pace (owner feedback, issue #174)
	firing = {
		-- Firing is continuous (ADR 0004, Amendment 2): a shot every 1 / rate seconds, hit or miss.
		-- rate = min(cap, base + perSection * sectionCount) shots/s. One line each to retune.
		base = 6, -- [default] was 3 in spec s4
		cap = 20, -- [default] was 12 in spec s4; validate() bounds it by the 30 Hz server tick
		perSection = 1, -- [spec s4] kept by Amendment 2
		range = 60, -- [default] studs along the street from the lead; spec (Amendment 1) names the key only
	},
	spectators = {
		approachSpeed = 27.2, -- [default] studs/second; keeps the former 34.4 relative closing speed when the parade pace halves (issue #174)
		centerTolerance = 3, -- [default] studs; |x| at or below this counts as "center" (Amendment 1)
		scatter = {
			perReward = 2, -- [default] individuals per reward point (a +5 cluster stands 10 spectators)
			spreadHalfWidth = 8, -- [default] studs; a cluster's individuals spread over this half-band around its lane
			colSpacing = 3.0, -- [default] studs between columns (figures are ~1.9 studs wide with arms)
			rowSpacing = 3.0, -- [default] studs between rows
			jitter = 0.15, -- [default] random offset as a share of spacing: keeps it a loose scatter
			minSeparation = 2.1, -- [default] studs; (1 - 2 x jitter) x spacing, so no two touch
			bunchRadius = 2.0, -- [default] studs; closer than this counts as one bunch
			maxBunch = 2, -- [default] most spectators in one bunch
			minScreenFraction = 0.022, -- [default] 2.2% of screen height (about 18 px on an 800 px phone)
			maxScale = 3.0, -- [default] far figures grow up to 3x so the head and body remain distinct
			bodyWidth = 1.4,
			bodyHeight = 2.0,
			bodyDepth = 0.9,
			headDiameter = 1.2,
			armsWidth = 1.7,
			armsHeight = 0.4,
			armsDepth = 0.3,
			startDelayMax = 0.8,
			approachSpeedSpread = 0.18,
			longitudinalJitter = 5,
			lateralWander = 4,
			turnDelayMax = 0.7,
			turnSeconds = 0.8,
			arrivalSpread = 1.5,
		},
	},
	visualBudget = {
		sectionRepresentatives = 6, -- [spec s8]
		looseAvatars = 24, -- [spec s8]
		-- Spec s8 asks for a "modest" pullback and a denser formation as the party grows, no numbers.
		-- Both curves rise linearly with logical sections and saturate at sectionsToMax.
		cameraPullback = { start = 1.0, max = 1.4, sectionsToMax = 40 }, -- [default] camera distance multiplier
		formationDensity = { start = 0.5, max = 1.0, sectionsToMax = 40 }, -- [default] 0..1 compactness
	},
	finaleThresholds = { 50, 150, 300 }, -- [spec s9, provisional]
	-- [default] issue #128: the play order. One entry today; a level's finale advances to the next.
	levelPlayOrder = { "oaxacan-street" },
	-- The gift share: every Nth shot is a gift once a dancer section exists, so 1 / N of shots.
	-- Owner report (#93 tuning): gifts were far too frequent at 4 (one in four); 100 gives one in
	-- a hundred. Was 4 [spec s4, every fourth shot]. One number to retune.
	giftEveryNthShot = 100, -- [owner-tuned, one gift per 100 shots once a dancer section exists]
	durations = {
		assemblySeconds = 0.8, -- [spec s7]
		dispersalSeconds = 0.5, -- [default] spec says only "brief animation" (s5)
	},
	musicLayerSections = { 0, 1, 3, 6 }, -- [spec s10] percussion, brass, bass/ensemble, crowd accents
	music = {
		bpm = 120, -- [default] tempo of the (not yet supplied) loop; spec gives no number
		beatsPerBar = 4, -- [default] 4/4
		fadeBars = 1, -- [default] crossfade length in bars
		maxSources = 4, -- [spec s10] hard cap on simultaneous stems; validate rejects > 4
		-- One selected Creator Store full-mix loop (ADR 0005 / issue #21). Stems stay off so
		-- this prototype creates exactly one music Sound. Playback permission and fit are Studio checks.
		stemSoundIds = { "", "", "", "" },
		-- [default] Mexican Nostalgia by APMOfficial; fit is UNVERIFIED until heard in Studio.
		trackSoundId = "1838904620",
		-- [default] issue #172 (owner: too dour; make it upbeat). The recording's key and mode cannot
		-- change in code, so the track plays 10% faster (tempo and pitch up together). UNVERIFIED by ear.
		playbackSpeed = 1.1,
	},
	audio = require("./AudioTuning"),
	-- [default] UNVERIFIED sound effect asset ids by slot (issue #62). Empty = silent; never invent
	-- ids. Owner supplies licensed or original audio (issue #30). See docs/audio-setup.md.
	sfx = {
		gatePop = "",
		convert = "",
		sparkle = "",
		shotLaunch = "",
		shotImpact = "",
		obstacleThud = "",
		attackBonk = "",
		followerHit = "",
		sectionRise = "",
		finalePeak = "",
		defeatBreakup = "",
		replayClick = "",
		crowdLoop = "", -- looping crowd ambience whose volume follows the follower count
	},
	debug = {
		startupTiming = false, -- [default] opt-in local startup trace; no Output logging unless enabled
		-- Issue #85 A/B switches for Studio (all default false = normal game):
		freezeCamera = false, -- hold the camera at its first pose: does the flicker survive a still camera?
		noShadows = false, -- Lighting.GlobalShadows = false: is it shadow flicker?
		quality = nil, -- [default] nil = automatic (medium on touch, high otherwise); or "low" | "medium" | "high"
		rawExtrapolation = false, -- the pre-#85 snap-to-State lead path instead of ServerClock
		-- Issue #171 A/B switches (flip one, replay the same route; all false = normal game):
		noTrails = false, -- shot Trails (Neon streaks) off
		noHitShake = false, -- hit camera shake off
		noTransparentStrips = false, -- GateView crossing strip and LeadRing drawn opaque
		noDust = false, -- chevron and mob dust ParticleEmitters off
	},
	validate = validate,
}

return deepFreeze(config)
