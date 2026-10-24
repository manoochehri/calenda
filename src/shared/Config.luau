--!strict
-- Every gameplay tunable for the prototype (spec section 11). No magic numbers elsewhere.
-- Values marked [spec] come from docs/Calenda-Prototype-Spec.md; values marked [default] are
-- placeholders chosen by the engineer because the spec gives no number (all are tuning defaults).

export type ClusterType = { hits: number, reward: number, attackDamage: number }
export type GateOp = { kind: string, value: number }
export type Curve = { start: number, max: number, sectionsToMax: number }
export type MusicConfig = {
	bpm: number,
	beatsPerBar: number,
	fadeBars: number,
	maxSources: number,
	stemSoundIds: { string },
	trackSoundId: string?, -- single-track mode (issue #62): one looped asset, empty = off
}
export type ConfigType = {
	sectionSize: number,
	startingTotal: number,
	hp: { max: number },
	clusterTypes: { small: ClusterType, large: ClusterType },
	gateOps: { GateOp },
	obstacleLoss: number,
	speed: number,
	firing: { base: number, cap: number, perSection: number, range: number },
	spectators: { approachSpeed: number, centerTolerance: number },
	visualBudget: {
		sectionRepresentatives: number,
		looseAvatars: number,
		cameraPullback: Curve,
		formationDensity: Curve,
	},
	finaleThresholds: { number },
	giftEveryNthShot: number,
	durations: { assemblySeconds: number, dispersalSeconds: number },
	musicLayerSections: { number },
	music: MusicConfig,
	audio: { [string]: any }, -- AudioIntensity / SfxMap tuning (issue #62)
	sfx: { [string]: string }, -- sound effect asset ids by slot, empty = silent (issue #62)
	validate: (config: any) -> (boolean, string?),
}

local function isPositiveInt(v: any): boolean
	return type(v) == "number" and v > 0 and v == math.floor(v) and v < math.huge
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
	for _, key in { "sectionSize", "obstacleLoss", "giftEveryNthShot" } do
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
	if not isPositive(c.speed) then
		return false, "speed must be a positive number"
	end

	if type(c.clusterTypes) ~= "table" then
		return false, "clusterTypes must be a table"
	end
	for _, name in { "small", "large" } do
		local ct = c.clusterTypes[name]
		if
			type(ct) ~= "table"
			or not isPositiveInt(ct.hits)
			or not isPositiveInt(ct.reward)
			or not isPositiveInt(ct.attackDamage)
		then
			return false, `clusterTypes.{name} needs positive integer hits, reward and attackDamage`
		end
	end
	if type(c.hp) ~= "table" or not isPositiveInt(c.hp.max) then
		return false, "hp.max must be a positive integer"
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
	startingTotal = 10, -- [spec s5]
	hp = { max = 100 }, -- [default] initial parade HP; no regeneration
	clusterTypes = {
		small = { hits = 3, reward = 5, attackDamage = 5 }, -- hits/reward [spec s4], attackDamage [default]
		large = { hits = 8, reward = 15, attackDamage = 12 }, -- hits/reward [spec s4], attackDamage [default]
	},
	-- [default] The spec only gives +N and xN as the allowed forms; +20 and x2 are its examples (s6).
	gateOps = {
		{ kind = "add", value = 20 },
		{ kind = "multiply", value = 2 },
	},
	obstacleLoss = 10, -- [spec s9]
	speed = 16, -- [default] studs/second; spec gives no value
	firing = {
		base = 3, -- [spec s4] min(cap, base + perSection * sectionCount)
		cap = 12, -- [spec s4]
		perSection = 1, -- [spec s4]
		range = 60, -- [default] studs along the street from the lead; spec (Amendment 1) names the key only
	},
	spectators = {
		approachSpeed = 6, -- [default] studs/second a cluster walks toward the parade; spec names the key only
		centerTolerance = 3, -- [default] studs; |x| at or below this counts as "center" (Amendment 1)
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
	giftEveryNthShot = 4, -- [spec s4] every fourth shot once a dancer section exists
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
		-- [default] UNVERIFIED placeholders: empty = silent. Audio must be original or licensed;
		-- the owner supplies real SoundIds. Order matches musicLayerSections.
		stemSoundIds = { "", "", "", "" },
		-- [default] UNVERIFIED single-track mode (issue #62): ONE looped asset id used instead of the
		-- stems; it grows with the parade through SoundEffects. Empty = off. Stems win if both are set.
		trackSoundId = "",
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
		hpHit = "",
		sectionRise = "",
		finalePeak = "",
		defeatBreakup = "",
		replayClick = "",
		crowdLoop = "", -- looping crowd ambience whose volume follows the follower count
	},
	validate = validate,
}

return deepFreeze(config)
