--!strict
-- Staggered join schedule (issue #68). Pure. When the crowd grows by N, followers arrive ONE AT
-- A TIME as a fast fountain (RATE per second); for large N the gap shrinks so the whole burst
-- never lasts more than MAX_SPAN seconds, and only MAX_VISIBLE of the N are drawn as individual
-- arrivals (the HUD shows the exact total regardless). Order is deterministic: arrival i is
-- always at offset i * interval.
local FollowerStagger = {}

FollowerStagger.RATE = 30 -- [default] arrivals per second for a small gain
FollowerStagger.MAX_SPAN = 1.0 -- [default] seconds: the last arrival starts before this
FollowerStagger.MAX_VISIBLE = 36 -- [default] individually drawn arrivals per burst

local function checkCount(n: any)
	if type(n) ~= "number" or n ~= n or n < 0 or n == math.huge then
		error(`count must be a non-negative number, got {tostring(n)}`, 3)
	end
end

-- How many arrivals are drawn for a gain of n.
function FollowerStagger.visible(n: number, maxVisible: number?): number
	checkCount(n)
	return math.min(math.floor(n), maxVisible or FollowerStagger.MAX_VISIBLE)
end

-- Start offsets (seconds after the gain), ascending, first 0, last < maxSpan.
function FollowerStagger.offsets(
	n: number,
	rate: number?,
	maxSpan: number?,
	maxVisible: number?
): { number }
	local m = FollowerStagger.visible(n, maxVisible)
	local span = maxSpan or FollowerStagger.MAX_SPAN
	local interval = math.min(1 / (rate or FollowerStagger.RATE), span / math.max(m, 1))
	local out = table.create(m)
	for i = 1, m do
		out[i] = (i - 1) * interval
	end
	return out
end

return FollowerStagger
