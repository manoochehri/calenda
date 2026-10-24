--!strict
-- Issue #19: pure globo / marmota animation (spec s7): rotation and tilt with the carriers, and the
-- decorative rings on the beat. Rings are timing and look only; nothing here touches the total.
local Config = require("../src/shared/Config")
local GloboPose = require("../src/shared/GloboPose")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function near(actual: number, expected: number, name: string)
	assert(math.abs(actual - expected) < 1e-6, `{name}: expected {expected}, got {actual}`)
end

local BEAT = 60 / Config.music.bpm

return {
	{
		name = "pose: the sphere keeps rotating (monotonic spin, whole turn every SPIN_BEATS beats)",
		run = function()
			local prev = GloboPose.pose(0, 0).spin
			for i = 1, 200 do
				local s = GloboPose.pose(i * 0.05, 0).spin
				assert(s > prev, `spin must keep increasing at step {i}`)
				prev = s
			end
			local period = BEAT * GloboPose.SPIN_BEATS
			near(
				GloboPose.pose(1.3 + period, 0).spin - GloboPose.pose(1.3, 0).spin,
				2 * math.pi,
				"one revolution per period"
			)
		end,
	},
	{
		name = "pose: always visibly tilted, never past MAX_TILT, and the lean direction wobbles",
		run = function()
			local leansLeft, leansRight = false, false
			for i = 0, 600 do
				local p = GloboPose.pose(i * 0.01, 0)
				local mag = math.sqrt(p.tiltX ^ 2 + p.tiltZ ^ 2)
				assert(mag <= GloboPose.MAX_TILT + 1e-9, `tilt {mag} over max at {i}`)
				assert(mag >= GloboPose.MAX_TILT * 0.5, `tilt {mag} too small to read at {i}`)
				if p.tiltZ > 0.05 then
					leansLeft = true
				elseif p.tiltZ < -0.05 then
					leansRight = true
				end
			end
			assert(leansLeft and leansRight, "tilt must wobble both ways")
		end,
	},
	{
		name = "pose: tilt, lift and carrier step repeat every bar and lift pops on the beat",
		run = function()
			local bar = BEAT * Config.music.beatsPerBar
			for _, t in { 0, 0.41, 2.2 } do
				local a, b = GloboPose.pose(t, 0), GloboPose.pose(t + bar, 0)
				near(a.tiltX, b.tiltX, "tiltX")
				near(a.tiltZ, b.tiltZ, "tiltZ")
				near(a.lift, b.lift, "lift")
				near(a.carrierStep, b.carrierStep, "carrierStep")
			end
			near(GloboPose.pose(BEAT * 3, 0).lift, GloboPose.LIFT_STUDS, "full lift on a beat")
			assert(
				GloboPose.pose(BEAT * 3.5, 0).lift < 0.1 * GloboPose.LIFT_STUDS,
				"rests off-beat"
			)
			for i = 0, 100 do
				local p = GloboPose.pose(i * 0.03, 0)
				assert(p.lift >= 0 and p.lift <= GloboPose.LIFT_STUDS + 1e-9, "lift bounded")
				assert(p.carrierStep >= 0 and p.carrierStep <= 1 + 1e-9, "step bounded")
			end
		end,
	},
	{
		name = "pose: phase offsets decorrelate two globos",
		run = function()
			local a, b = GloboPose.pose(1, 0), GloboPose.pose(1, 0.37)
			assert(math.abs(a.spin - b.spin) > 0.1, "spin differs by phase")
		end,
	},
	{
		name = "rings: one per beat, the total is the same at any frame rate, none when time stands still",
		run = function()
			local function total(step: number): number
				local n, prev = 0, 0.0
				for i = 1, math.floor(10 / step + 0.5) do
					local t = i * step
					n += GloboPose.beatsIn(prev, t)
					prev = t
				end
				return n
			end
			local expected = 10 / BEAT
			for _, step in { 1 / 240, 1 / 60, 1 / 30, 0.1, 0.25, 0.5 } do
				eq(total(step), expected, `beats at step {step}`)
			end
			eq(GloboPose.beatsIn(2, 2), 0, "no time, no ring")
			eq(GloboPose.beatsIn(3, 2), 0, "time going backwards never rings")
			eq(GloboPose.beatsIn(0, BEAT * 1.0001), 1, "first beat")
		end,
	},
	{
		name = "rings: expand and fade over RING_SECONDS, then are gone; colors cycle without error",
		run = function()
			local r0 = GloboPose.ring(0)
			local r1 = GloboPose.ring(GloboPose.RING_SECONDS / 2)
			local r2 = GloboPose.ring(GloboPose.RING_SECONDS)
			assert(r0.radius < r1.radius and r1.radius < r2.radius, "radius grows")
			assert(r0.alpha > r1.alpha and r1.alpha > r2.alpha, "alpha falls")
			near(r0.alpha, 1, "starts opaque")
			near(r2.alpha, 0, "ends invisible")
			near(GloboPose.ring(99).alpha, 0, "stays gone")
			near(GloboPose.ring(-1).radius, r0.radius, "negative age clamps to the start")
			eq(GloboPose.ringColorIndex(0, 4), 1, "first color")
			eq(GloboPose.ringColorIndex(5, 4), 2, "wraps")
			assert(GloboPose.MAX_RINGS >= 2 and GloboPose.MAX_RINGS <= 24, "ring count is bounded")
		end,
	},
	{
		name = "carriers: evenly around the pole base at one radius, at least the requested count",
		run = function()
			eq(#GloboPose.carrierOffsets(0), 0, "none")
			for n = 1, 6 do
				local offs = GloboPose.carrierOffsets(n)
				eq(#offs, n, `count {n}`)
				for _, o in offs do
					near(math.sqrt(o.dx ^ 2 + o.dz ^ 2), GloboPose.CARRIER_RADIUS, "radius")
				end
			end
			local four = GloboPose.carrierOffsets(4)
			near(four[1].dx, -four[3].dx, "opposite carriers mirror (x)")
			near(four[1].dz, -four[3].dz, "opposite carriers mirror (z)")
		end,
	},
}
