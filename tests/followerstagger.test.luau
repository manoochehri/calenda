--!strict
local FollowerStagger = require("../src/shared/FollowerStagger")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

return {
	{
		name = "a small gain arrives one at a time at the fountain rate",
		run = function()
			local o = FollowerStagger.offsets(5)
			eq(#o, 5, "five arrivals")
			eq(o[1], 0, "first starts at once")
			for i = 2, 5 do
				assert(
					math.abs(o[i] - o[i - 1] - 1 / FollowerStagger.RATE) < 1e-9,
					"fountain spacing"
				)
			end
		end,
	},
	{
		name = "bounded total time for any N, including +1000 and absurd gains",
		run = function()
			for _, n in { 1, 2, 29, 30, 31, 36, 37, 100, 1000, 100000, 1e9 } do
				local o = FollowerStagger.offsets(n)
				assert(#o >= 1 and #o <= FollowerStagger.MAX_VISIBLE, `visible count for {n}`)
				assert(o[#o] < FollowerStagger.MAX_SPAN, `last arrival of {n} starts at {o[#o]}`)
				eq(#o, math.min(n, FollowerStagger.MAX_VISIBLE), `count for {n}`)
			end
		end,
	},
	{
		name = "order is deterministic and strictly ascending",
		run = function()
			local a, b = FollowerStagger.offsets(77), FollowerStagger.offsets(77)
			eq(#a, #b, "same length")
			for i = 1, #a do
				eq(a[i], b[i], "same offsets")
				if i > 1 then
					assert(a[i] > a[i - 1], "ascending")
				end
			end
		end,
	},
	{
		name = "zero gain draws nothing; a negative or NaN gain is rejected",
		run = function()
			eq(#FollowerStagger.offsets(0), 0, "zero")
			assert(not pcall(FollowerStagger.offsets, -1), "negative")
			assert(not pcall(FollowerStagger.offsets, 0 / 0), "nan")
		end,
	},
	{
		name = "custom rate and span (peeling) are honoured",
		run = function()
			local o = FollowerStagger.offsets(24, 14, 1.0, 24)
			eq(#o, 24, "all drawn")
			assert(o[24] < 1.0, "within span")
		end,
	},
}
