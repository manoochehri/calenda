--!strict
-- Issue #65 tension (owner, 2026-10-24: "each level needs a little tension ... music/intensity
-- swell with the approach"): the music swells with the nearest unconverted wave's threat.
local AudioIntensity = require("../src/shared/AudioIntensity") :: any
local Emergence = require("../src/shared/Emergence")

local function near(a: number, b: number, name: string)
	assert(math.abs(a - b) < 1e-9, `{name}: expected {b}, got {a}`)
end

return {
	{
		name = "threat swell: silent with no threat, full THREAT_PEAK at full threat",
		run = function()
			assert(
				AudioIntensity.THREAT_PEAK > 0 and AudioIntensity.THREAT_PEAK < 1,
				"THREAT_PEAK in (0, 1)"
			)
			near(AudioIntensity.threatPeak(0), 0, "threatPeak(0)")
			near(AudioIntensity.threatPeak(1), AudioIntensity.THREAT_PEAK, "threatPeak(1)")
		end,
	},
	{
		name = "threat swell: rises monotonically and never leaves 0..THREAT_PEAK",
		run = function()
			local prev = -1
			for i = 0, 100 do
				local v = AudioIntensity.threatPeak(i / 100)
				assert(v >= prev - 1e-12, `not monotone at {i}`)
				assert(
					v >= 0 and v <= AudioIntensity.THREAT_PEAK + 1e-12,
					`out of range at {i}: {v}`
				)
				prev = v
			end
		end,
	},
	{
		name = "threat swell: bad input is clamped or silent, never NaN or above the peak",
		run = function()
			near(AudioIntensity.threatPeak(-3), 0, "negative threat")
			near(AudioIntensity.threatPeak(7), AudioIntensity.THREAT_PEAK, "threat above 1")
			near(AudioIntensity.threatPeak(0 / 0), 0, "NaN threat")
			near(
				AudioIntensity.threatPeak(math.huge),
				AudioIntensity.THREAT_PEAK,
				"infinite threat"
			)
		end,
	},
	{
		name = "threat swell: a wave still far beyond THREAT_FAR does not swell the music",
		run = function()
			near(
				AudioIntensity.threatPeak(Emergence.threat(Emergence.THREAT_FAR + 40)),
				0,
				"far wave"
			)
		end,
	},
	{
		name = "threat swell: a wave at the parade swells the music to THREAT_PEAK",
		run = function()
			near(
				AudioIntensity.threatPeak(Emergence.threat(Emergence.THREAT_NEAR - 5)),
				AudioIntensity.THREAT_PEAK,
				"near wave"
			)
		end,
	},
	{
		name = "threat swell: the crowd's own intensity is never lowered, and the mix stays 0..1",
		run = function()
			local base = 0.9
			local mixed = AudioIntensity.withPeak(base, AudioIntensity.threatPeak(1))
			assert(mixed >= base - 1e-12, "threat never pulls the crowd intensity down")
			assert(mixed <= 1, "mixed intensity <= 1")
			near(
				AudioIntensity.withPeak(0.1, AudioIntensity.threatPeak(1)),
				AudioIntensity.THREAT_PEAK,
				"threat lifts a quiet crowd"
			)
		end,
	},
}
