--!strict
-- Issue #63: the visual distribution of musical shots into parallel streams. One stream per
-- logical parade section, capped at five; shots cycle through the streams. Visual only: the stream
-- count never changes the firing rate, the pool size, or which shots hit (all of that is elsewhere).
local Config = require("../src/shared/Config")
local ShotLook = require("../src/shared/ShotLook")
local ShotStreams = require("../src/shared/ShotStreams")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function near(actual: number, expected: number, name: string)
	assert(math.abs(actual - expected) < 1e-9, `{name}: expected {expected}, got {actual}`)
end

return {
	{
		name = "one stream for 0 or 1 sections, then one per section",
		run = function()
			eq(ShotStreams.count(0), 1, "no sections: one stream")
			eq(ShotStreams.count(1), 1, "one section: one stream")
			eq(ShotStreams.count(2), 2, "two sections: two streams")
			eq(ShotStreams.count(3), 3, "three sections: three streams")
			eq(ShotStreams.count(4), 4, "four sections: four streams")
		end,
	},
	{
		name = "stream count is capped at five however many sections there are",
		run = function()
			eq(ShotStreams.MAX_STREAMS, 5, "the cap is five")
			eq(ShotStreams.count(5), 5, "five sections: five streams")
			eq(ShotStreams.count(6), 5, "six sections: still five")
			eq(ShotStreams.count(500), 5, "many sections: still five")
		end,
	},
	{
		name = "stream count rejects a negative or fractional section count",
		run = function()
			assert(not pcall(ShotStreams.count, -1), "negative must error")
			assert(not pcall(ShotStreams.count, 1.5), "fraction must error")
		end,
	},
	{
		name = "shot numbers cycle through the streams, evenly and in range",
		run = function()
			local streams = 5
			local hits = { 0, 0, 0, 0, 0 }
			for n = 1, 10 do
				local lane = ShotStreams.lane(n, streams)
				assert(lane >= 0 and lane < streams, `lane {lane} out of range`)
				hits[lane + 1] += 1
			end
			for i = 1, 5 do
				eq(hits[i], 2, `lane {i - 1} gets two of ten shots`)
			end
			eq(ShotStreams.lane(1, 1), 0, "a single stream always takes lane 0")
			eq(ShotStreams.lane(7, 1), 0, "a single stream always takes lane 0 later too")
		end,
	},
	{
		name = "one lane counter for hits and misses: shots cycle through the lanes in arrival order",
		run = function()
			-- A hit and a miss draw from the same counter, so the lane follows the shot, not its kind
			-- (issue #63 review: shot.id and miss.n were two different keys).
			local cycle = ShotStreams.cycler()
			local order = {}
			for i = 1, 10 do
				order[i] = cycle.next(5)
			end
			for i = 1, 10 do
				eq(order[i], (i - 1) % 5, `shot {i} takes lane {(i - 1) % 5}`)
			end
			local fresh = ShotStreams.cycler()
			eq(fresh.next(1), 0, "one stream: lane 0")
			eq(fresh.next(1), 0, "one stream: lane 0 again")
		end,
	},
	{
		name = "lateral offsets are distinct, centred on the lead, and within the stream spacing",
		run = function()
			local streams = 5
			local seen = {}
			local sum = 0
			for lane = 0, streams - 1 do
				local off = ShotStreams.offset(lane, streams)
				assert(seen[off] == nil, "offsets are distinct")
				seen[off] = true
				sum += off
			end
			near(sum, 0, "offsets are centred on zero")
			near(ShotStreams.offset(0, 1), 0, "one stream runs straight ahead")
			near(ShotStreams.offset(0, 2), -ShotStreams.SPACING / 2, "two streams sit either side")
			near(ShotStreams.offset(4, 5), 2 * ShotStreams.SPACING, "outermost of five")
		end,
	},
	{
		name = "a stream's miss runs parallel to the lead, at its lane offset, never beyond it",
		run = function()
			local lateral = ShotStreams.offset(4, 5)
			near(ShotLook.miss(0, 3, lateral).dx, 0, "starts at the lead")
			near(ShotLook.miss(1, 3, lateral).dx, lateral, "settles on its lane")
			for i = 0, 20 do
				assert(
					math.abs(ShotLook.miss(i / 20, 3, lateral).dx) <= math.abs(lateral) + 1e-9,
					"never beyond the lane"
				)
			end
		end,
	},
	{
		name = "ShotLook.miss with lateral: eases out to the lane by a third of the flight, ignores n",
		run = function()
			local lateral = -3.2
			near(ShotLook.miss(0.1, 1, lateral).dx, lateral * 0.3, "30% of the way at k=0.1")
			near(ShotLook.miss(1 / 3, 1, lateral).dx, lateral, "on the lane at k=1/3")
			near(ShotLook.miss(0.5, 1, lateral).dx, lateral, "holds the lane after k=1/3")
			for n = 1, 10 do
				near(
					ShotLook.miss(0.2, n, lateral).dx,
					ShotLook.miss(0.2, 1, lateral).dx,
					"n ignored"
				)
			end
			-- The other channels are the same with or without a lateral offset.
			local a, b = ShotLook.miss(0.6, 4, lateral), ShotLook.miss(0.6, 4)
			eq(a.dy, b.dy, "dy unchanged")
			eq(a.dz, b.dz, "dz unchanged")
			eq(a.scale, b.scale, "scale unchanged")
			eq(a.alpha, b.alpha, "alpha unchanged")
		end,
	},
	{
		name = "ShotLook.miss without lateral keeps the old five-lane spread",
		run = function()
			for n = 1, 10 do
				for i = 0, 10 do
					local k = i / 10
					local expected = ((n % 5) - 2) * ShotLook.MISS_SPREAD * k
					near(ShotLook.miss(k, n).dx, expected, `nil lateral, n={n}, k={k}`)
				end
			end
			local seen = {}
			for n = 1, 5 do
				seen[ShotLook.miss(1, n).dx] = true
			end
			local count = 0
			for _ in seen do
				count += 1
			end
			eq(count, 5, "five distinct lanes")
			near(ShotLook.miss(1, 5, 0).dx, 0, "an explicit zero lateral is a stream, not nil")
		end,
	},
	{
		name = "streams never add live shots: the pool stays at rate x flight within the hard cap",
		run = function()
			-- The pool is sized from the firing rate alone; no stream count may enlarge it.
			local rate = Config.firing.cap
			local flight = 0.9
			local cap = ShotStreams.projectileCapacity(rate, flight)
			eq(cap, ShotLook.projectileCapacity(rate, flight), "same pool as the shot look sizing")
			assert(cap <= ShotLook.PROJECTILE_HARD_CAP, "within the hard cap")
			assert(cap >= rate * flight, "covers rate x flight")
			for sections = 0, 12 do
				eq(
					ShotStreams.projectileCapacity(rate, flight),
					cap,
					`pool unchanged at {sections} sections`
				)
			end
		end,
	},
}
