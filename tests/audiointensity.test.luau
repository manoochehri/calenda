--!strict
local AudioIntensity = require("../src/shared/AudioIntensity") :: any
local Config = require("../src/shared/Config")

local function near(a: number, b: number, name: string)
	assert(math.abs(a - b) < 1e-9, `{name}: expected {b}, got {a}`)
end

local function at(total: number): number
	return AudioIntensity.target(total, total // Config.sectionSize)
end

local DOC = { -- documented property ranges (docs/audio-setup.md)
	reverbDecay = { 0.1, 20 },
	reverbWet = { -80, 10 },
	reverbDry = { -80, 10 },
	chorusMix = { 0, 1 },
	chorusDepth = { 0, 1 },
	chorusRate = { 0, 20 },
	eqLow = { -80, 10 },
	eqMid = { -80, 10 },
	eqHigh = { -80, 10 },
	compThreshold = { -80, 0 },
	compMakeup = { -30, 30 },
	compAttack = { 0.1, 1 },
	compRelease = { 0, 5 },
}

return {
	{
		name = "intensity is 0 for an empty crowd and 1 at fullTotal, bounded above",
		run = function()
			near(at(0), 0, "0")
			near(at(Config.audio.fullTotal), 1, "full")
			near(at(1000000), 1, "huge stays at 1")
		end,
	},
	{
		name = "10 -> 100 -> 1000 each step up clearly; 10,000 does not blow out",
		run = function()
			local a, b, c, d = at(10), at(100), at(1000), at(10000)
			assert(b - a > 0.1 and c - b > 0.1 and d - c > 0.1, `steps {a} {b} {c} {d}`)
			assert(d <= 1, "ceiling")
			assert(at(20000) == d, "no growth past the top")
		end,
	},
	{
		name = "monotonic and smooth: no jump larger than 0.02 between neighbouring totals",
		run = function()
			local last = at(0)
			for n = 1, 12000 do
				local v = at(n)
				assert(v >= last - 1e-12, `drops at {n}`)
				assert(v - last < 0.02, `jump at {n}: {v - last}`)
				last = v
			end
		end,
	},
	{
		name = "bad input gives 0, never NaN or an error",
		run = function()
			near(AudioIntensity.target(-5, 0), 0, "negative")
			near(AudioIntensity.target(0 / 0, 0 / 0), 0, "nan")
			near(AudioIntensity.target(math.huge, math.huge), 1, "inf clamps")
		end,
	},
	{
		name = "slew limits the rate of change and lands exactly on the target",
		run = function()
			near(AudioIntensity.slew(0, 1, 0.1, 0.2, 0.4), 0.02, "rise 0.2/s over 0.1 s")
			near(AudioIntensity.slew(1, 0, 0.1, 0.2, 0.4), 0.96, "fall 0.4/s over 0.1 s")
			near(AudioIntensity.slew(0.5, 0.51, 1, 0.2, 0.4), 0.51, "reaches it")
			near(AudioIntensity.slew(0.5, 0.9, 0, 0.2, 0.4), 0.5, "dt 0 holds")
			near(AudioIntensity.slew(0.5, 0.9, -1, 0.2, 0.4), 0.5, "negative dt holds")
		end,
	},
	{
		name = "the finale peak only ever overrides upward",
		run = function()
			near(AudioIntensity.withPeak(0.3, 0.5), 0.5, "lifted")
			near(AudioIntensity.withPeak(0.9, 0.5), 0.9, "never lowered")
			near(AudioIntensity.withPeak(0.3, nil), 0.3, "nil = none")
			near(AudioIntensity.withPeak(0.3, 0), 0.3, "0 = none")
			near(AudioIntensity.withPeak(0.3, 7), 1, "clamped")
		end,
	},
	{
		name = "music master gain swells gently between masterMin and masterMax, never above 1",
		run = function()
			near(AudioIntensity.masterGain(0), Config.audio.masterMin, "min")
			near(AudioIntensity.masterGain(1), Config.audio.masterMax, "max")
			assert(
				AudioIntensity.masterGain(5) <= 1 and AudioIntensity.masterGain(-5) > 0,
				"clamped"
			)
			assert(AudioIntensity.masterGain(0.5) > AudioIntensity.masterGain(0.4), "monotonic")
		end,
	},
	{
		name = "stem weights follow intensity continuously: percussion always, others grow later",
		run = function()
			for i = 0, 100 do
				near(AudioIntensity.layerWeight(1, i / 100), 1, "percussion always full")
			end
			for layer = 2, 4 do
				near(
					AudioIntensity.layerWeight(layer, 0),
					Config.audio.layerFloor[layer],
					`floor {layer}`
				)
				near(AudioIntensity.layerWeight(layer, 1), 1, `top {layer}`)
				local last = AudioIntensity.layerWeight(layer, 0)
				for i = 0, 200 do
					local w = AudioIntensity.layerWeight(layer, i / 200)
					assert(w >= last - 1e-12 and w <= 1 and w > 0, `layer {layer} at {i}`)
					assert(w - last < 0.03, `layer {layer} steps at {i}`)
					last = w
				end
			end
			assert(
				AudioIntensity.layerWeight(4, 0.5) < AudioIntensity.layerWeight(2, 0.5),
				"crowd accents grow after brass"
			)
		end,
	},
	{
		name = "effects stay inside the documented SoundEffect ranges at any intensity",
		run = function()
			for i = -2, 30 do
				local e = AudioIntensity.effects(i / 20)
				for key, range in DOC do
					local v = e[key]
					assert(type(v) == "number" and v == v, `{key} missing`)
					assert(
						v >= range[1] and v <= range[2],
						`{key}={v} outside {range[1]}..{range[2]}`
					)
				end
			end
		end,
	},
	{
		name = "effects grow with intensity (bigger reverb, chorus, lift) and are subtle at 0",
		run = function()
			local lo, hi = AudioIntensity.effects(0), AudioIntensity.effects(1)
			assert(hi.reverbDecay > lo.reverbDecay and hi.reverbWet > lo.reverbWet, "reverb")
			assert(hi.chorusMix > lo.chorusMix and hi.chorusDepth > lo.chorusDepth, "chorus")
			assert(hi.eqMid > lo.eqMid and hi.eqHigh > lo.eqHigh, "eq")
			assert(hi.compThreshold < lo.compThreshold and hi.compMakeup > lo.compMakeup, "comp")
			near(lo.chorusMix, 0, "no chorus at 0")
		end,
	},
	{
		name = "loudness compensation never raises the level and shrinks as boosts grow",
		run = function()
			local c0 = AudioIntensity.compensation(AudioIntensity.effects(0))
			local c1 = AudioIntensity.compensation(AudioIntensity.effects(1))
			assert(c0 <= 1 and c1 <= c0 and c1 > 0.4, `{c0} {c1}`)
		end,
	},
	{
		name = "crowd loop volume follows followers on the same log curve, silent at 0, bounded",
		run = function()
			near(AudioIntensity.crowdLoopVolume(0), 0, "empty")
			local a, b = AudioIntensity.crowdLoopVolume(10), AudioIntensity.crowdLoopVolume(1000)
			assert(a > 0 and b > a, "grows")
			near(AudioIntensity.crowdLoopVolume(1e9), Config.audio.sfx.crowdLoopVolume, "ceiling")
		end,
	},
	{
		name = "Config selects one full-mix music loop and keeps music to one source",
		run = function()
			assert((Config.music :: any).trackSoundId == "1838904620", "selected full-mix track")
			local musicSources = 0
			for _, id in Config.music.stemSoundIds do
				assert(id == "", "single-track mode must not also enable stems")
				if id ~= "" then
					musicSources += 1
				end
			end
			if Config.music.trackSoundId ~= "" then
				musicSources += 1
			end
			assert(musicSources == 1, `expected one configured music source, got {musicSources}`)
			local n = 0
			for _, id in Config.sfx do
				n += 1
				assert(id == "", "sfx id must be empty in the repo")
			end
			assert(n >= 13, "all slots plus crowdLoop present")
			local ok, err = Config.validate(Config)
			assert(ok, tostring(err))
		end,
	},
}
