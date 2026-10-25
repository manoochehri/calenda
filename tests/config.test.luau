--!strict
local Config = require("../src/shared/Config")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {expected}, got {actual}`)
end

local function clone(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = clone(v)
	end
	return out
end

-- Returns validate's result for a deep copy of the defaults after `mutate` edits it.
local function validateMutated(mutate: (c: any) -> ()): (boolean, string?)
	local c = clone(Config)
	mutate(c)
	return Config.validate(c)
end

local function expectInvalid(name: string, mutate: (c: any) -> ()): { name: string, run: () -> () }
	return {
		name = `invalid: {name}`,
		run = function()
			local ok = validateMutated(mutate)
			assert(not ok, `expected validation to reject: {name}`)
		end,
	}
end

return {
	{
		name = "defaults validate",
		run = function()
			local ok, err = Config.validate(Config)
			assert(ok, `defaults rejected: {err}`)
		end,
	},
	{
		name = "defaults match spec values",
		run = function()
			local c = Config
			eq(c.sectionSize, 50, "sectionSize")
			eq(c.startingTotal, 10, "startingTotal")
			eq(c.clusterTypes.small.hits, 3, "small.hits")
			eq(c.clusterTypes.small.reward, 5, "small.reward")
			eq(c.clusterTypes.large.hits, 8, "large.hits")
			eq(c.clusterTypes.large.reward, 15, "large.reward")
			eq(c.attackSharePercent, 10, "attackSharePercent (ADR 0006)")
			eq(c.minShareLoss, 1, "minShareLoss (ADR 0006)")
			eq(c.hazards.tomatoSharePercent, 10, "hazards.tomatoSharePercent")
			eq(c.obstacleLoss, 10, "obstacleLoss")
			eq(c.firing.base, 6, "firing.base (ADR 0004; was 3)")
			eq(c.firing.cap, 20, "firing.cap (ADR 0004; was 12)")
			eq(c.firing.perSection, 1, "firing.perSection")
			eq(c.visualBudget.sectionRepresentatives, 6, "sectionRepresentatives")
			eq(c.visualBudget.looseAvatars, 24, "looseAvatars")
			eq(#c.finaleThresholds, 3, "finale count")
			eq(c.finaleThresholds[1], 50, "finale 1")
			eq(c.finaleThresholds[2], 150, "finale 2")
			eq(c.finaleThresholds[3], 300, "finale 3")
			eq(c.giftEveryNthShot, 4, "giftEveryNthShot")
			eq(c.debug.startupTiming, false, "startup timing default")
			eq(c.debug.freezeCamera, false, "freezeCamera default")
			eq(c.debug.noShadows, false, "noShadows default")
			eq(c.debug.rawExtrapolation, false, "rawExtrapolation default")
			eq(c.durations.assemblySeconds, 0.8, "assemblySeconds")
			eq(c.musicLayerSections[1], 0, "music 1")
			eq(c.musicLayerSections[2], 1, "music 2")
			eq(c.musicLayerSections[3], 3, "music 3")
			eq(c.musicLayerSections[4], 6, "music 4")
		end,
	},
	{
		name = "config is deeply frozen",
		run = function()
			assert(table.isfrozen(Config))
			assert(table.isfrozen(Config.clusterTypes))
			assert(table.isfrozen(Config.clusterTypes.small))
			assert(table.isfrozen(Config.debug))
			assert(table.isfrozen(Config.finaleThresholds))
			assert(table.isfrozen(Config.gateOps))
			assert(table.isfrozen(Config.gateOps[1]))
			assert(not pcall(function()
				(Config :: any).sectionSize = 1
			end), "writing to Config must error")
		end,
	},
	expectInvalid("sectionSize zero", function(c)
		c.sectionSize = 0
	end),
	expectInvalid("startup timing flag must be boolean", function(c)
		c.debug.startupTiming = "yes"
	end),
	expectInvalid("freezeCamera flag must be boolean", function(c)
		c.debug.freezeCamera = 1
	end),
	expectInvalid("sectionSize non-integer", function(c)
		c.sectionSize = 50.5
	end),
	expectInvalid("sectionSize wrong type", function(c)
		c.sectionSize = "50"
	end),
	expectInvalid("startingTotal negative", function(c)
		c.startingTotal = -1
	end),
	expectInvalid("attack share non-integer", function(c)
		c.attackSharePercent = 2.5
	end),
	expectInvalid("attack share zero", function(c)
		c.attackSharePercent = 0
	end),
	expectInvalid("attack share above 100", function(c)
		c.attackSharePercent = 101
	end),
	expectInvalid("minimum share loss zero", function(c)
		c.minShareLoss = 0
	end),
	expectInvalid("tomato share zero", function(c)
		c.hazards.tomatoSharePercent = 0
	end),
	expectInvalid("missing field", function(c)
		c.obstacleLoss = nil
	end),
	expectInvalid("cluster hits zero", function(c)
		c.clusterTypes.small.hits = 0
	end),
	expectInvalid("cluster reward non-integer", function(c)
		c.clusterTypes.large.reward = 1.5
	end),
	expectInvalid("firing cap below base", function(c)
		c.firing.cap = 2
	end),
	expectInvalid("firing cap above the 30 Hz tick", function(c)
		c.firing.cap = 31
	end),
	expectInvalid("firing perSection zero", function(c)
		c.firing.perSection = 0
	end),
	expectInvalid("speed not positive", function(c)
		c.speed = 0
	end),
	expectInvalid("visual budget zero", function(c)
		c.visualBudget.looseAvatars = 0
	end),
	expectInvalid("finale thresholds not ascending", function(c)
		c.finaleThresholds = { 150, 50, 300 }
	end),
	expectInvalid("giftEveryNthShot zero", function(c)
		c.giftEveryNthShot = 0
	end),
	expectInvalid("duration not positive", function(c)
		c.durations.assemblySeconds = 0
	end),
	expectInvalid("music layers not ascending", function(c)
		c.musicLayerSections = { 0, 3, 1, 6 }
	end),
	expectInvalid("gate op unknown kind", function(c)
		c.gateOps[1].kind = "divide"
	end),
	expectInvalid("gate op multiply by 1", function(c)
		c.gateOps[2].value = 1
	end),
	expectInvalid("music missing", function(c)
		c.music = nil
	end),
	expectInvalid("music bpm zero", function(c)
		c.music.bpm = 0
	end),
	expectInvalid("music beatsPerBar fractional", function(c)
		c.music.beatsPerBar = 3.5
	end),
	expectInvalid("music fadeBars zero", function(c)
		c.music.fadeBars = 0
	end),
	expectInvalid("music maxSources above hard cap 4", function(c)
		c.music.maxSources = 5
	end),
	expectInvalid("music stem ids wrong length", function(c)
		c.music.stemSoundIds = { "", "" }
	end),
	expectInvalid("music stem id not a string", function(c)
		c.music.stemSoundIds[1] = 123
	end),
	{
		name = "music stem ids default to empty placeholders (game runs silent)",
		run = function()
			eq(#Config.music.stemSoundIds, #Config.musicLayerSections, "stem count")
			for i, id in Config.music.stemSoundIds do
				eq(id, "", `stemSoundIds[{i}]`)
			end
			eq(Config.music.maxSources, 4, "maxSources")
		end,
	},
	{
		name = "wave and range defaults (issue #7)",
		run = function()
			eq(Config.spectators.approachSpeed, 20, "approachSpeed") -- issue #65: the mob charges
			eq(Config.spectators.centerTolerance, 3, "centerTolerance")
			eq(Config.firing.range, 60, "firing.range")
			assert(table.isfrozen(Config.spectators), "spectators frozen")
		end,
	},
	expectInvalid("spectators missing", function(c)
		c.spectators = nil
	end),
	expectInvalid("approachSpeed zero", function(c)
		c.spectators.approachSpeed = 0
	end),
	expectInvalid("approachSpeed non-number", function(c)
		c.spectators.approachSpeed = "fast"
	end),
	expectInvalid("approachSpeed infinite", function(c)
		c.spectators.approachSpeed = math.huge
	end),
	expectInvalid("centerTolerance negative", function(c)
		c.spectators.centerTolerance = -1
	end),
	expectInvalid("firing.range zero", function(c)
		c.firing.range = 0
	end),
	expectInvalid("firing.range missing", function(c)
		c.firing.range = nil
	end),
}
