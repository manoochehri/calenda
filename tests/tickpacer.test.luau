--!strict
local TickPacer = require("../src/shared/TickPacer")

local DT = 1 / 30

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

return {
	{
		name = "a normal frame runs exactly the whole ticks it holds and keeps the remainder",
		run = function()
			local steps, left = TickPacer.plan(0, DT * 2.5, DT)
			eq(steps, 2, "two ticks")
			assert(math.abs(left - DT * 0.5) < 1e-9, "half a tick carried")
			local s2, l2 = TickPacer.plan(left, DT * 0.5, DT)
			eq(s2, 1, "carry completes a tick")
			assert(l2 < 1e-9, "nothing left")
		end,
	},
	{
		name = "a 5 second hitch advances at most the cap in one call and drops the leftover",
		run = function()
			local steps, left = TickPacer.plan(0, 5, DT)
			eq(steps, TickPacer.MAX_STEPS_PER_FRAME, "capped")
			eq(left, 0, "backlog dropped, not carried")
		end,
	},
	{
		name = "a frame at exactly the cap runs the cap and keeps its remainder",
		run = function()
			local steps, left = TickPacer.plan(0, DT * (TickPacer.MAX_STEPS_PER_FRAME + 0.5), DT)
			eq(steps, TickPacer.MAX_STEPS_PER_FRAME, "cap")
			assert(left > 0 and left < DT, "remainder under one tick is kept")
		end,
	},
	{
		name = "bad inputs run no ticks and never grow the accumulator",
		run = function()
			for _, bad in { 0 / 0, math.huge, -1 } do
				local steps, left = TickPacer.plan(0.01, bad, DT)
				eq(steps, 0, "no steps")
				eq(left, 0.01, "accumulator unchanged")
			end
		end,
	},
}
