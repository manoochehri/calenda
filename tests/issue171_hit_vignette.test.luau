--!strict
-- Issue #171: the hit cue must not strobe. The old cue drew a full-screen white wash that turned
-- red, restarted on every hit. These pin the replacement: no white, opacity capped by
-- Config.hitVignette, eased (no frame-to-frame jump), and rate-limited so rapid hits cannot stack.
local Config = require("../src/shared/Config")
local HitFeedback = require("../src/shared/HitFeedback")

local DT = 1 / 60

return {
	{
		name = "the hit cue is never white: its color mix is red at every age of a hit",
		run = function()
			local fx = HitFeedback.new()
			fx:hit(1)
			for _ = 1, 90 do
				local mix = (fx:sample() :: any).redMix
				assert(mix == nil or mix == 1, `white phase present (redMix {tostring(mix)})`)
				fx:step(DT)
			end
		end,
	},
	{
		name = "over a rapid hit sequence the cue stays under the Config peak and never jumps",
		run = function()
			local hv = (Config :: any).hitVignette
			assert(hv ~= nil, "Config.hitVignette missing")
			local fx = HitFeedback.new()
			local peak, prev, worstJump = 0, 0, 0
			for frame = 1, 600 do -- 10 s at 60 fps, a hit every 0.1 s
				if frame % 6 == 1 then
					fx:hit(1)
				end
				local f = fx:sample().flash
				peak = math.max(peak, f)
				worstJump = math.max(worstJump, math.abs(f - prev))
				prev = f
				fx:step(DT)
			end
			assert(peak <= hv.peakAlpha + 1e-9, `peak {peak} above Config cap {hv.peakAlpha}`)
			assert(peak > 0.05, "cue should still be visible")
			-- Eased: one frame moves at most a small share of the peak (a snap would be ~the peak).
			assert(worstJump <= hv.peakAlpha * 0.25, `frame jump {worstJump} is a pop, not an ease`)
		end,
	},
	{
		name = "the cue restarts at most once per Config minimum gap, however fast hits arrive",
		run = function()
			local hv = (Config :: any).hitVignette
			assert(hv ~= nil, "Config.hitVignette missing")
			local fx = HitFeedback.new()
			local starts, wasOff = 0, true
			local seconds = 10
			for _ = 1, seconds * 60 do
				fx:hit(1) -- a hit on every frame
				local on = fx:sample().flash > 0.001
				if on and wasOff then
					starts += 1
				end
				wasOff = not on
				fx:step(DT)
			end
			local allowed = math.ceil(seconds / hv.minGapSeconds)
			assert(starts <= allowed, `{starts} cue starts in {seconds}s, allowed {allowed}`)
			assert(starts >= 1, "at least one cue")
		end,
	},
	{
		name = "Config rejects a vignette that could overlap itself or hide the game",
		run = function()
			local function bad(mutate: (hv: any) -> ()): boolean
				local copy = table.clone(Config :: any)
				local hv = table.clone(copy.hitVignette)
				mutate(hv)
				copy.hitVignette = hv
				local ok = Config.validate(copy)
				return not ok
			end
			assert(Config.validate(Config :: any), "defaults valid")
			assert(
				bad(function(hv)
					hv.minGapSeconds = 0.1
				end),
				"gap shorter than the cue"
			)
			assert(
				bad(function(hv)
					hv.peakAlpha = 0.9
				end),
				"peak too opaque"
			)
			assert(
				bad(function(hv)
					hv.riseSeconds = 0
				end),
				"zero rise"
			)
		end,
	},
}
