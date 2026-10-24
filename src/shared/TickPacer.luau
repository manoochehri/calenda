--!strict
-- Fixed-step pacing for the server run loop (issue #36 review). Pure: given the carried time and
-- this frame's dt, says how many fixed ticks to run and what to carry. A server hitch of N seconds
-- must not run 30*N ticks in one frame (that stalls every player), so a frame runs at most
-- MAX_STEPS_PER_FRAME ticks and the backlog beyond that is dropped, not carried.
local TickPacer = {}

TickPacer.MAX_STEPS_PER_FRAME = 5 -- [default] about 0.17 s of simulation per frame at 30 Hz

function TickPacer.plan(accumulator: number, dt: number, tickDt: number): (number, number)
	if type(dt) ~= "number" or dt ~= dt or dt <= 0 or dt == math.huge then
		return 0, accumulator
	end
	local total = accumulator + dt
	local steps = math.floor(total / tickDt + 1e-9) -- tolerance for float error
	if steps > TickPacer.MAX_STEPS_PER_FRAME then
		return TickPacer.MAX_STEPS_PER_FRAME, 0
	end
	return steps, math.max(0, total - steps * tickDt)
end

return TickPacer
