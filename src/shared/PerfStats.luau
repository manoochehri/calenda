--!strict
-- Issue #256 / #147: rolling frame-time window for the on-device perf overlay. Pure and Lune-tested;
-- the Instance counting and the TextLabel live in the client PerfOverlay.
local PerfStats = {}
PerfStats.__index = PerfStats

export type Stats = typeof(setmetatable(
	{} :: { cap: number, dts: { number }, next: number, n: number },
	PerfStats
))

function PerfStats.new(capacity: number): Stats
	return setmetatable({ cap = capacity, dts = {}, next = 1, n = 0 }, PerfStats)
end

function PerfStats.push(self: Stats, dt: number)
	self.dts[self.next] = dt
	self.next = self.next % self.cap + 1
	self.n = math.min(self.n + 1, self.cap)
end

-- Nearest-rank percentile (0..1) of the window, in the same unit as pushed (seconds); 0 when empty.
function PerfStats.percentile(self: Stats, p: number): number
	if self.n == 0 then
		return 0
	end
	local copy = table.create(self.n)
	for i = 1, self.n do
		copy[i] = self.dts[i]
	end
	table.sort(copy)
	return copy[math.clamp(math.ceil(p * self.n), 1, self.n)]
end

-- The overlay text: three lines, large enough to read off a phone screenshot.
function PerfStats.format(
	parts: number,
	emitters: number,
	trails: number,
	p50: number,
	p95: number,
	n: number
): string
	return string.format(
		"Parts %d\nEmitters %d  Trails %d\ndt p50 %.1f ms  p95 %.1f ms  (n=%d)",
		parts,
		emitters,
		trails,
		p50 * 1000,
		p95 * 1000,
		n
	)
end

return PerfStats
