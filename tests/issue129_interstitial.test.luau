-- Issue #129: the between-level card lasts about three seconds, can be skipped, and advances once.
local ok, LevelInterstitial = pcall(require, "../src/shared/LevelInterstitial")
assert(ok, `LevelInterstitial module missing: {tostring(LevelInterstitial)}`)

local function eq(actual: any, expected: any, message: string)
	assert(actual == expected, `{message}: expected {tostring(expected)}, got {tostring(actual)}`)
end

return {
	{
		name = "does not advance before the three-second duration",
		run = function()
			local flow = LevelInterstitial.new(10, 2)
			local before = LevelInterstitial.step(flow, 12.99, false)
			eq(before.advance, false, "early advance")
			eq(before.active, true, "early active")
			eq(before.elapsed, 2.99, "elapsed")
		end,
	},
	{
		name = "automatically advances at the duration exactly once",
		run = function()
			local flow = LevelInterstitial.new(10, 2)
			local done = LevelInterstitial.step(flow, 13, false)
			eq(done.advance, true, "automatic advance")
			eq(done.active, false, "inactive after advance")
			local again = LevelInterstitial.step(flow, 14, false)
			eq(again.advance, false, "advance only once")
		end,
	},
	{
		name = "a skip advances immediately and never leaks a second advance",
		run = function()
			local flow = LevelInterstitial.new(10, 2)
			local skipped = LevelInterstitial.step(flow, 10.25, true)
			eq(skipped.advance, true, "skip advance")
			eq(skipped.active, false, "inactive after skip")
			local later = LevelInterstitial.step(flow, 20, true)
			eq(later.advance, false, "skip only once")
		end,
	},
	{
		name = "a late frame still completes without extending the card",
		run = function()
			local flow = LevelInterstitial.new(10, 2)
			local done = LevelInterstitial.step(flow, 100, false)
			eq(done.advance, true, "late advance")
			eq(done.elapsed, 3, "elapsed is capped")
		end,
	},
}
