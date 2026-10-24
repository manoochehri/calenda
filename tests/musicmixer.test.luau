--!strict
local MusicMixer = require("../src/shared/MusicMixer")

local function near(actual: number, expected: number, name: string)
	assert(math.abs(actual - expected) < 1e-9, `{name}: expected {expected}, got {actual}`)
end

local function cfg(ids: { string }?): any
	return {
		musicLayerSections = { 0, 1, 3, 6 },
		music = {
			bpm = 120, -- bar = 2 s
			beatsPerBar = 4,
			fadeBars = 1, -- fade = 2 s
			maxSources = 4,
			stemSoundIds = ids or { "a", "b", "c", "d" },
		},
	}
end

local function sum(g: { [string]: number }): number
	local s = 0
	for _, v in g do
		s += v
	end
	return s
end

return {
	{
		name = "silent by default: empty stem ids give no layers and zero gain",
		run = function()
			local m = MusicMixer.new(cfg({ "", "", "", "" }))
			MusicMixer.setSections(m, 10, 0.5)
			assert(#MusicMixer.soundLayers(m) == 0, "no Sound is needed without ids")
			near(sum(MusicMixer.gains(m, 100)), 0, "gain")
		end,
	},
	{
		name = "Sound layers are the ones with ids, at most 4 (and maxSources)",
		run = function()
			local m = MusicMixer.new(cfg({ "a", "", "c", "d" }))
			local l = MusicMixer.soundLayers(m)
			assert(
				#l == 3 and l[1] == "percussion" and l[2] == "ensemble" and l[3] == "crowd",
				"layers"
			)
			local c = cfg()
			c.music.maxSources = 2
			assert(#MusicMixer.soundLayers(MusicMixer.new(c)) == 2, "maxSources caps the Sounds")
		end,
	},
	{
		name = "a new layer fades in from the next bar boundary, linearly over fadeBars",
		run = function()
			local m = MusicMixer.new(cfg())
			MusicMixer.setSections(m, 0, 0.5) -- boundary at 2 s
			near(MusicMixer.gains(m, 1.9).percussion, 0, "before the boundary")
			near(MusicMixer.gains(m, 2).percussion, 0, "at the boundary")
			near(MusicMixer.gains(m, 3).percussion, 0.5, "halfway")
			near(MusicMixer.gains(m, 4).percussion, 1, "done")
			near(MusicMixer.gains(m, 99).percussion, 1, "stays")
			near(MusicMixer.gains(m, 99).brass, 0, "other layers stay off")
		end,
	},
	{
		name = "more sections add layers on the bar; a layer already on is untouched",
		run = function()
			local m = MusicMixer.new(cfg())
			MusicMixer.setSections(m, 0, 0)
			MusicMixer.setSections(m, 1, 5) -- brass joins at the next bar, 6 s
			near(MusicMixer.gains(m, 5.5).brass, 0, "waits for the bar")
			near(MusicMixer.gains(m, 7).brass, 0.5, "fading in")
			near(MusicMixer.gains(m, 5.5).percussion, 1, "percussion unchanged")
			near(MusicMixer.gains(m, 7).percussion, 1, "percussion unchanged")
		end,
	},
	{
		name = "losing sections fades the top layer out on the bar",
		run = function()
			local m = MusicMixer.new(cfg())
			MusicMixer.setSections(m, 3, 0)
			near(MusicMixer.gains(m, 10).ensemble, 1, "ensemble is on")
			MusicMixer.setSections(m, 1, 10) -- boundary exactly at 10
			near(MusicMixer.gains(m, 10).ensemble, 1, "starts at full")
			near(MusicMixer.gains(m, 11).ensemble, 0.5, "halfway out")
			near(MusicMixer.gains(m, 12).ensemble, 0, "gone")
			near(MusicMixer.gains(m, 12).brass, 1, "brass stays")
		end,
	},
	{
		name = "a change during a fade continues from the current level (no jump)",
		run = function()
			local m = MusicMixer.new(cfg())
			MusicMixer.setSections(m, 1, 0) -- percussion and brass in at 0..2
			near(MusicMixer.gains(m, 1).brass, 0.5, "mid fade-in")
			-- brass leaves again at the bar after t = 1 (2 s): it is at 1.0 by then, then fades out
			MusicMixer.setSections(m, 0, 1)
			near(MusicMixer.gains(m, 2).brass, 1, "continues to the boundary")
			near(MusicMixer.gains(m, 3).brass, 0.5, "fades out after it")
			near(MusicMixer.gains(m, 4).brass, 0, "off")
		end,
	},
	{
		name = "setting the same section count again changes nothing",
		run = function()
			local m = MusicMixer.new(cfg())
			MusicMixer.setSections(m, 3, 0)
			local before = MusicMixer.gains(m, 3).ensemble
			MusicMixer.setSections(m, 3, 3)
			near(MusicMixer.gains(m, 3).ensemble, before, "same")
		end,
	},
	{
		name = "gain is bounded: never below 0 or above 1, and never more than 4 layers sound",
		run = function()
			local m = MusicMixer.new(cfg())
			MusicMixer.setSections(m, 500, 0)
			for t = 0, 20 do
				local g = MusicMixer.gains(m, t * 0.7)
				local audible = 0
				for _, v in g do
					assert(v >= 0 and v <= 1, "range")
					if v > 0 then
						audible += 1
					end
				end
				assert(audible <= 4, "at most 4 sources")
			end
		end,
	},
	{
		name = "reset silences everything and forgets the section count",
		run = function()
			local m = MusicMixer.new(cfg())
			MusicMixer.setSections(m, 6, 0)
			MusicMixer.reset(m)
			near(sum(MusicMixer.gains(m, 50)), 0, "silent after reset")
			MusicMixer.setSections(m, 6, 100) -- the same count schedules again after a reset
			near(MusicMixer.gains(m, 110).crowd, 1, "plays again")
		end,
	},
	{
		name = "volume maps gain to a Sound volume under a controlled ceiling",
		run = function()
			near(MusicMixer.volume(0, 0), 0, "silent")
			near(MusicMixer.volume(1, 0), MusicMixer.LAYER_VOLUME, "full layer")
			near(MusicMixer.volume(0.5, 0), MusicMixer.LAYER_VOLUME / 2, "half")
			local peak = MusicMixer.volume(1, 1)
			assert(peak > MusicMixer.volume(1, 0), "the peak hook raises it")
			assert(peak <= MusicMixer.LAYER_VOLUME * (1 + MusicMixer.PEAK_BOOST) + 1e-9, "bounded")
			near(MusicMixer.volume(1, 5), peak, "intensity clamps to 1")
			near(MusicMixer.volume(1, -3), MusicMixer.volume(1, 0), "intensity clamps to 0")
			near(MusicMixer.volume(2, 0), MusicMixer.LAYER_VOLUME, "gain clamps to 1")
		end,
	},
	{
		name = "the finale intensity ramp is the peak: monotonic and reaches the top",
		run = function()
			local FinalePlan = require("../src/shared/FinalePlan")
			local last = -1
			for i = 0, 90 do
				local v = MusicMixer.volume(
					1,
					MusicMixer.peakAmount(FinalePlan.at(i / 10).musicIntensity)
				)
				assert(v >= last - 1e-9, "never drops during the finale")
				last = v
			end
			near(last, MusicMixer.volume(1, 1), "ends at the peak")
			near(MusicMixer.peakAmount(FinalePlan.at(0).musicIntensity), 0, "starts without a jump")
		end,
	},
}
