--!strict
-- Issue #256 / #147: perf overlay stats and per-figure LOD. Frame-time benefit is UNVERIFIED
-- (no Studio); these tests pin the pure decisions and the wiring.
local Config = require("../src/shared/Config")
local MobFigureLod = require("../src/shared/MobFigureLod")
local PerfStats = require("../src/shared/PerfStats")
local fs = require("@lune/fs")

local function eq(a: any, b: any, msg: string)
	assert(a == b, `{msg}: expected {tostring(b)}, got {tostring(a)}`)
end
local function has(path: string, needle: string): boolean
	return string.find(fs.readFile(path), needle, 1, true) ~= nil
end

return {
	{
		name = "issue 256: perfOverlay defaults false and validates as boolean",
		run = function()
			eq((Config.debug :: any).perfOverlay, false, "default")
			local copy: any = table.clone(Config)
			copy.debug = table.clone(Config.debug)
			copy.debug.perfOverlay = 1
			eq((Config.validate(copy)), false, "must be boolean")
		end,
	},
	{
		name = "issue 256: PerfStats rolling window p50/p95",
		run = function()
			local s = PerfStats.new(100)
			eq(s:percentile(0.5), 0, "empty")
			for i = 1, 100 do
				s:push(i / 1000)
			end
			eq(s:percentile(0.5), 0.05, "p50")
			eq(s:percentile(0.95), 0.095, "p95")
			for _ = 1, 100 do
				s:push(0.016) -- the window rolls: old samples are gone
			end
			eq(s:percentile(0.95), 0.016, "rolled")
			eq(s.n, 100, "capped")
			local text = PerfStats.format(612, 11, 27, 0.0167, 0.033, 100)
			assert(
				string.find(text, "Parts 612", 1, true)
					and string.find(text, "p95 33.0 ms", 1, true),
				text
			)
		end,
	},
	{
		name = "issue 256: LOD tiers by screen share, Parts per figure fall with distance",
		run = function()
			eq(MobFigureLod.tier(0.05, nil), 3, "near")
			eq(MobFigureLod.tier(0.015, nil), 2, "mid")
			eq(MobFigureLod.tier(0.005, nil), 1, "far")
			eq(MobFigureLod.partsFor({ 0.05, 0.015, 0.005 }), 6, "3+2+1")
			-- hysteresis: just under a threshold keeps the richer tier, just over a lower one keeps the poorer
			eq(MobFigureLod.tier(0.021, 3), 3, "near stays near")
			eq(MobFigureLod.tier(0.021, 2), 2, "mid stays mid")
			eq(MobFigureLod.tier(0.0105, 2), 2, "mid holds")
			eq(MobFigureLod.tier(0.0105, 1), 1, "far holds")
			eq(MobFigureLod.bodyStretch(3, 2, 1.2), 1, "near unstretched")
			assert(MobFigureLod.bodyStretch(1, 2, 1.2) > 1, "far body absorbs the head")
		end,
	},
	{
		name = "issue 256: MobView applies the LOD without changing the figure count, overlay is wired",
		run = function()
			local mv = "src/client/MobView.luau"
			assert(has(mv, "MobFigureLod.tier(frac, f.tier)"), "tier chosen per figure")
			assert(has(mv, "if tier >= 3 then"), "arms pushed only near")
			assert(has(mv, "figureSlots[figureCursor]"), "one slot per figure kept")
			assert(has("src/client/Main.client.luau", "Config.debug.perfOverlay"), "overlay gated")
		end,
	},
}
