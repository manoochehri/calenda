--!strict
-- Deterministic one-shot beats on a timeline (issue #16). Pure. A presentation layer asks "how
-- many beats fell in (prev, now]?" each frame, so the total is the same at any frame rate.
local Beats = {}

-- n times spread evenly from `first` to `last` inclusive (n = 1 gives {first}).
function Beats.evenly(n: number, first: number, last: number): { number }
	local out = {}
	if n < 1 then
		return out
	end
	if n == 1 then
		return { first }
	end
	for i = 0, n - 1 do
		table.insert(out, first + (last - first) * i / (n - 1))
	end
	return out
end

-- Count of times t with prev < t <= now.
function Beats.countIn(times: { number }, prev: number, now: number): number
	local n = 0
	for _, t in times do
		if t > prev and t <= now then
			n += 1
		end
	end
	return n
end

return Beats
