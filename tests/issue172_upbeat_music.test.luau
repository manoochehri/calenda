--!strict
-- Issue #172 (owner: the music is too dour for milestone 7; make it upbeat). The track is one
-- Creator Store full mix (ADR 0005), so its key and mode cannot change in code. The levers are the
-- playback speed (tempo and pitch together) and the mix (drier reverb, brighter highs). These cases
-- pin the upbeat tuning so it cannot silently drift back to the dour values.
local Config = require("../src/shared/Config")

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

-- Validates a deep copy of the defaults after `mutate`; the defaults themselves must pass first.
local function expectInvalid(name: string, mutate: (c: any) -> ())
	return {
		name = `validate rejects {name}`,
		run = function()
			local base, baseErr = Config.validate(clone(Config))
			assert(base, `defaults rejected before mutation: {baseErr}`)
			local c = clone(Config)
			mutate(c)
			local ok = Config.validate(c)
			assert(ok == false, `{name}: validate accepted an invalid value`)
		end,
	}
end

return {
	{
		name = "track plays faster than the recording (upbeat tempo): playbackSpeed in (1, 1.2]",
		run = function()
			local speed = (Config.music :: any).playbackSpeed
			assert(type(speed) == "number", `playbackSpeed missing, got {speed}`)
			assert(speed > 1 and speed <= 1.2, `playbackSpeed {speed} outside (1, 1.2]`)
		end,
	},
	{
		name = "mix is brighter: EqualizerSoundEffect HighGain floor is at least 2 dB",
		run = function()
			local high = Config.audio.effects.eqHigh
			assert(high[1] >= 2, `eqHigh floor {high[1]} below 2 dB`)
		end,
	},
	{
		name = "mix is drier: reverb WetLevel ceiling is at most -16 dB",
		run = function()
			local wet = Config.audio.effects.reverbWet
			assert(wet[2] <= -16, `reverbWet ceiling {wet[2]} above -16 dB`)
		end,
	},
	{
		name = "defaults still validate with the upbeat tuning",
		run = function()
			local ok, err = Config.validate(Config)
			assert(ok, `defaults rejected: {err}`)
		end,
	},
	expectInvalid("playbackSpeed zero", function(c)
		c.music.playbackSpeed = 0
	end),
	expectInvalid("playbackSpeed above 2", function(c)
		c.music.playbackSpeed = 2.5
	end),
}
