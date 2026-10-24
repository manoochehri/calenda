--!strict
local Config = require("../src/shared/Config")
local MusicLayers = require("../src/shared/MusicLayers")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {expected}, got {actual}`)
end

local function near(actual: number, expected: number, name: string)
	assert(math.abs(actual - expected) < 1e-9, `{name}: expected {expected}, got {actual}`)
end

local function listEq(actual: { any }, expected: { any }, name: string)
	eq(#actual, #expected, `{name} length`)
	for i = 1, #expected do
		eq(actual[i], expected[i], `{name}[{i}]`)
	end
end

-- A config copy with placeholder-free stem ids, to exercise the audible path.
local function withIds(): any
	return {
		musicLayerSections = Config.musicLayerSections,
		music = {
			bpm = 120,
			beatsPerBar = 4,
			fadeBars = 1,
			maxSources = 4,
			stemSoundIds = { "id-a", "id-b", "id-c", "id-d" },
		},
	}
end

local function find(plan: MusicLayers.Plan, layer: string, action: string): MusicLayers.Fade?
	for _, f in plan.fades do
		if f.layer == layer and f.action == action then
			return f
		end
	end
	return nil
end

local function expectLayers(sections: number, expected: { string })
	listEq(MusicLayers.activeLayers(sections), expected, `activeLayers({sections})`)
end

return {
	{
		name = "layers at 0 sections: percussion only",
		run = function()
			expectLayers(0, { "percussion" })
		end,
	},
	{
		name = "layers at 1 and 2 sections: brass joins",
		run = function()
			expectLayers(1, { "percussion", "brass" })
			expectLayers(2, { "percussion", "brass" })
		end,
	},
	{
		name = "layers at 3 and 5 sections: ensemble joins",
		run = function()
			expectLayers(3, { "percussion", "brass", "ensemble" })
			expectLayers(5, { "percussion", "brass", "ensemble" })
		end,
	},
	{
		name = "layers at 6 and 100 sections: crowd accents join, no more",
		run = function()
			expectLayers(6, { "percussion", "brass", "ensemble", "crowd" })
			expectLayers(100, { "percussion", "brass", "ensemble", "crowd" })
		end,
	},
	{
		name = "thresholds come from Config.musicLayerSections",
		run = function()
			local cfg = withIds()
			cfg.musicLayerSections = { 0, 2, 4, 8 }
			listEq(MusicLayers.activeLayers(3, cfg), { "percussion", "brass" }, "custom 3")
			listEq(
				MusicLayers.activeLayers(8, cfg),
				{ "percussion", "brass", "ensemble", "crowd" },
				"custom 8"
			)
		end,
	},
	{
		name = "source count never above 4 for any section count",
		run = function()
			for n = 0, 500 do
				assert(#MusicLayers.activeLayers(n) <= 4, `{n} sections > 4 layers`)
			end
			eq(MusicLayers.maxSources(), 4, "maxSources")
		end,
	},
	{
		name = "source cap lowers the active set when maxSources < layers",
		run = function()
			local cfg = withIds()
			cfg.music.maxSources = 2
			listEq(MusicLayers.activeLayers(100, cfg), { "percussion", "brass" }, "capped")
		end,
	},
	{
		name = "invalid sectionCount is rejected",
		run = function()
			assert(not pcall(MusicLayers.activeLayers, -1), "negative accepted")
			assert(not pcall(MusicLayers.activeLayers, 1.5), "fraction accepted")
		end,
	},
	{
		name = "silent when stem ids are empty (default config)",
		run = function()
			listEq(MusicLayers.audibleLayers(100), {}, "audible")
			local plan = MusicLayers.planCrossfade(3.3, {}, MusicLayers.activeLayers(6))
			eq(#plan.fades, 0, "silent plan fades")
		end,
	},
	{
		name = "audible layers keep only layers with a non-empty id",
		run = function()
			local cfg = withIds()
			cfg.music.stemSoundIds = { "id-a", "", "id-c", "" }
			listEq(MusicLayers.audibleLayers(100, cfg), { "percussion", "ensemble" }, "audible")
		end,
	},
	{
		name = "crossfade starts on the next bar boundary (120 bpm, 4/4 = 2s bars)",
		run = function()
			local cfg = withIds()
			local plan = MusicLayers.planCrossfade(
				3.3,
				{ "percussion" },
				{ "percussion", "brass" },
				cfg
			)
			near(plan.boundary, 4, "boundary")
			local brass = find(plan, "brass", "in")
			assert(brass, "brass fade-in missing")
			near(brass.startTime, 4, "brass start")
			near(brass.duration, 2, "brass duration (1 bar)")
			eq(#plan.fades, 1, "only the new layer fades")
		end,
	},
	{
		name = "a change exactly on a boundary starts immediately",
		run = function()
			local cfg = withIds()
			local plan = MusicLayers.planCrossfade(
				6,
				{ "percussion" },
				{ "percussion", "brass" },
				cfg
			)
			near(plan.boundary, 6, "boundary")
		end,
	},
	{
		name = "boundary follows bpm and beatsPerBar",
		run = function()
			local cfg = withIds()
			cfg.music.bpm = 90
			cfg.music.beatsPerBar = 3 -- bar = 2s
			cfg.music.fadeBars = 2
			local plan = MusicLayers.planCrossfade(0.1, {}, { "percussion" }, cfg)
			near(plan.boundary, 2, "boundary")
			local f = find(plan, "percussion", "in")
			assert(f, "fade-in missing")
			near(f.duration, 4, "two-bar fade")
		end,
	},
	{
		name = "dropping layers fades them out on the boundary",
		run = function()
			local cfg = withIds()
			local plan = MusicLayers.planCrossfade(
				0.5,
				{ "percussion", "brass", "ensemble" },
				{ "percussion" },
				cfg
			)
			local out = find(plan, "brass", "out")
			assert(out and find(plan, "ensemble", "out"), "fade-outs missing")
			near(out.startTime, 2, "out start")
			eq(find(plan, "percussion", "out"), nil, "kept layer untouched")
		end,
	},
	{
		name = "no change plans nothing",
		run = function()
			local cfg = withIds()
			local plan = MusicLayers.planCrossfade(
				1,
				{ "percussion", "brass" },
				{ "percussion", "brass" },
				cfg
			)
			eq(#plan.fades, 0, "fades")
		end,
	},
	{
		name = "concurrent sources never exceed the cap, even mid-fade",
		run = function()
			local cfg = withIds()
			cfg.music.maxSources = 2
			-- Swap one layer for another with a cap of 2: the fade-in must wait for the fade-out.
			local plan = MusicLayers.planCrossfade(
				0.5,
				{ "percussion", "brass" },
				{ "percussion", "ensemble" },
				cfg
			)
			local out = find(plan, "brass", "out")
			local inn = find(plan, "ensemble", "in")
			assert(out and inn, "swap fades missing")
			assert(
				inn.startTime >= out.startTime + out.duration - 1e-9,
				"fade-in overlaps fade-out"
			)
			assert(plan.peakSources <= 2, `peak {plan.peakSources} > cap`)
		end,
	},
	{
		name = "with spare capacity a swap overlaps (true crossfade) and stays within the cap",
		run = function()
			local cfg = withIds()
			local plan = MusicLayers.planCrossfade(
				0.5,
				{ "percussion", "brass" },
				{ "percussion", "ensemble" },
				cfg
			)
			local out = find(plan, "brass", "out")
			local inn = find(plan, "ensemble", "in")
			assert(out and inn, "swap fades missing")
			near(inn.startTime, out.startTime, "simultaneous start")
			eq(plan.peakSources, 3, "peak")
		end,
	},
	{
		name = "peak sources never above 4 across all transitions",
		run = function()
			for from = 0, 8 do
				for to = 0, 8 do
					local plan = MusicLayers.planCrossfade(
						1.7,
						MusicLayers.audibleLayers(from, withIds()),
						MusicLayers.audibleLayers(to, withIds()),
						withIds()
					)
					assert(plan.peakSources <= 4, `{from}->{to} peak {plan.peakSources}`)
				end
			end
		end,
	},
	{
		name = "negative or non-finite time is rejected",
		run = function()
			assert(not pcall(MusicLayers.planCrossfade, -1, {}, {}), "negative accepted")
			assert(not pcall(MusicLayers.planCrossfade, 0 / 0, {}, {}), "nan accepted")
		end,
	},
}
