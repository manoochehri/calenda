--!strict
local Effects = require("../src/shared/Effects")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

return {
	{
		name = "an effect is active for its duration with progress 0..1, then gone",
		run = function()
			local e = Effects.new(4)
			assert(e:start(10, 2, "a"), "started")
			local act = e:active(11)
			eq(#act, 1, "one active")
			eq(act[1].data, "a", "data")
			assert(math.abs(act[1].f - 0.5) < 1e-9, "halfway")
			eq(#e:active(12), 0, "expired at its end")
		end,
	},
	{
		name = "the pool is bounded: when full a new effect is dropped, never queued or grown",
		run = function()
			local e = Effects.new(3)
			for i = 1, 3 do
				assert(e:start(0, 1, i), `start {i}`)
			end
			eq(e:start(0.5, 1, 4), false, "fourth dropped")
			eq(e:count(0.5), 3, "still three")
			eq(e:capacity(), 3, "capacity fixed")
			assert(e:start(1.1, 1, 5), "room again once the first three ended")
			eq(e:count(1.1), 1, "only the new one")
		end,
	},
	{
		name = "a flood of starts never exceeds capacity",
		run = function()
			local e = Effects.new(16)
			local peak = 0
			for i = 0, 600 do
				e:start(i * 0.01, 0.5, i)
				peak = math.max(peak, e:count(i * 0.01))
			end
			assert(peak <= 16, `peak {peak}`)
		end,
	},
	{
		name = "bad construction and bad durations are errors; clear empties",
		run = function()
			assert(not pcall(Effects.new, 0), "zero capacity")
			assert(not pcall(Effects.new, 1.5), "fractional capacity")
			local e = Effects.new(2)
			assert(not pcall(function()
				e:start(0, 0, "x")
			end), "zero duration")
			e:start(0, 5, "x")
			e:clear()
			eq(e:count(0), 0, "cleared")
		end,
	},
}
