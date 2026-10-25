--!strict
local FeedbackMath = require("../src/shared/FeedbackMath")

local function near(actual: number, expected: number, name: string)
	assert(math.abs(actual - expected) < 1e-6, `{name}: expected {expected}, got {actual}`)
end
local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

return {
	{
		name = "arc starts at the lead, ends at the target and peaks in between",
		run = function()
			local x0, y0, z0 = FeedbackMath.arc(0, 2, 0, 10, 3, 40, 0, 6)
			near(x0, 0, "x0")
			near(y0, 2, "y0")
			near(z0, 0, "z0")
			local x1, y1, z1 = FeedbackMath.arc(0, 2, 0, 10, 3, 40, 1, 6)
			near(x1, 10, "x1")
			near(y1, 3, "y1")
			near(z1, 40, "z1")
			local _, ym = FeedbackMath.arc(0, 2, 0, 10, 3, 40, 0.5, 6)
			near(ym, 2.5 + 6, "apex above the straight line by the height")
			local _, yOver = FeedbackMath.arc(0, 2, 0, 10, 3, 40, 7, 6)
			near(yOver, 3, "f clamps at 1")
		end,
	},
	{
		name = "flight time is clamped so a close or far target never looks wrong",
		run = function()
			eq(FeedbackMath.flightSeconds(0), FeedbackMath.MIN_FLIGHT, "min")
			eq(FeedbackMath.flightSeconds(1e6), FeedbackMath.MAX_FLIGHT, "max")
			assert(FeedbackMath.flightSeconds(30) > FeedbackMath.MIN_FLIGHT, "grows with distance")
		end,
	},
	{
		name = "shot variants (spec s4, s10): ordinary shots alternate note and heart, gifts alternate heart and snack",
		run = function()
			eq(FeedbackMath.variant("note", 1), "heart", "ordinary odd shot is a heart")
			eq(FeedbackMath.variant("note", 2), "note", "ordinary even shot is a note")
			local hearts, notes = 0, 0
			for hits = 1, 10 do
				local v = FeedbackMath.variant("note", hits)
				assert(v == "heart" or v == "note", `ordinary shot became {v}`)
				if v == "heart" then
					hearts += 1
				else
					notes += 1
				end
			end
			eq(hearts, 5, "half the ordinary shots are hearts")
			eq(notes, 5, "half the ordinary shots are notes")
			eq(FeedbackMath.variant("gift", 1), "heart", "gift odd")
			eq(FeedbackMath.variant("gift", 2), "snack", "gift even")
		end,
	},
	{
		name = "meter fraction is hits over needed, clamped to 0..1",
		run = function()
			near(FeedbackMath.meterFraction(0, 3), 0, "empty")
			near(FeedbackMath.meterFraction(1, 4), 0.25, "quarter")
			near(FeedbackMath.meterFraction(9, 8), 1, "over clamps")
			near(FeedbackMath.meterFraction(-1, 8), 0, "negative clamps")
			near(
				FeedbackMath.meterFraction(1, 0),
				1,
				"zero needed reads as full, no divide by zero"
			)
		end,
	},
	{
		name = "burst particles are deterministic, spread out, rise then fall, and fade",
		run = function()
			local a = FeedbackMath.burst(1, 10, 0.5)
			local b = FeedbackMath.burst(1, 10, 0.5)
			near(a.dx, b.dx, "deterministic dx")
			near(a.dy, b.dy, "deterministic dy")
			local p = FeedbackMath.burst(2, 10, 0)
			near(p.dx, 0, "starts at origin x")
			near(p.dy, 0, "starts at origin y")
			near(p.alpha, 1, "opaque at start")
			local q = FeedbackMath.burst(2, 10, 1)
			near(q.alpha, 0, "gone at end")
			assert(math.abs(q.dx) + math.abs(q.dz) > 1, "moved outward")
			local dirs = {}
			for i = 1, 10 do
				local r = FeedbackMath.burst(i, 10, 0.6)
				dirs[string.format("%.2f,%.2f", r.dx, r.dz)] = true
			end
			local n = 0
			for _ in dirs do
				n += 1
			end
			eq(n, 10, "all ten particles go different ways")
		end,
	},
	{
		name = "floating +N rises and fades",
		run = function()
			local s, e = FeedbackMath.floatText(0), FeedbackMath.floatText(1)
			near(s.dy, 0, "start height")
			near(s.alpha, 1, "start alpha")
			assert(e.dy > 2, "rose")
			near(e.alpha, 0, "end alpha")
		end,
	},
	{
		name = "runner hop: lerps from start to target with a small hop that lands at 0",
		run = function()
			local x, z, y = FeedbackMath.run(0, 0, 10, 20, 0.5)
			near(x, 5, "x mid")
			near(z, 10, "z mid")
			assert(y > 0, "hopping")
			local x1, z1, y1 = FeedbackMath.run(0, 0, 10, 20, 1)
			near(x1, 10, "x end")
			near(z1, 20, "z end")
			near(y1, 0, "lands")
		end,
	},
}
