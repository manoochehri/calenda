--!strict
-- Issue #20: pure look of the gift shot (spec s4): a wrapped treat that is plainly not a note and
-- not a spectator, and the spectators' catch celebration. Visual only: nothing here is a reward.
local GiftVisual = require("../src/shared/GiftVisual")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function near(actual: number, expected: number, name: string)
	assert(math.abs(actual - expected) < 1e-6, `{name}: expected {expected}, got {actual}`)
end

local function dist(a: { number }, b: { number }): number
	return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
end

return {
	{
		name = "wrapped treat is bigger than a note and every wrapper color contrasts with note and spectator",
		run = function()
			assert(
				GiftVisual.TREAT_LENGTH > GiftVisual.NOTE_SIZE * 1.3,
				"clearly bigger than a note"
			)
			assert(#GiftVisual.WRAPPERS >= 2, "more than one colorway")
			for i, w in GiftVisual.WRAPPERS do
				assert(
					dist(w, GiftVisual.NOTE_RGB) > 150,
					`wrapper {i} too close to the note color`
				)
				assert(
					dist(w, GiftVisual.SPECTATOR_RGB) > 150,
					`wrapper {i} too close to the spectator color`
				)
			end
		end,
	},
	{
		name = "look: deterministic per hit count, cycles the colorways, always valid",
		run = function()
			for hits = 0, 40 do
				local a, b = GiftVisual.look(hits), GiftVisual.look(hits)
				eq(a.wrapper, b.wrapper, "deterministic")
				assert(a.wrapper >= 1 and a.wrapper <= #GiftVisual.WRAPPERS, "valid index")
				assert(a.spin ~= 0, "always tumbles")
			end
			assert(GiftVisual.look(1).wrapper ~= GiftVisual.look(2).wrapper, "consecutive differ")
			eq(
				GiftVisual.look(1).wrapper,
				GiftVisual.look(1 + #GiftVisual.WRAPPERS).wrapper,
				"cycle"
			)
		end,
	},
	{
		name = "tumble: turns more than once in flight, starts at zero",
		run = function()
			eq(GiftVisual.tumble(0), 0, "start")
			assert(GiftVisual.tumble(1) >= 2 * math.pi, "at least one full turn")
			assert(GiftVisual.tumble(0.5) < GiftVisual.tumble(1), "monotonic")
			eq(GiftVisual.tumble(2), GiftVisual.tumble(1), "clamped past the end")
		end,
	},
	{
		name = "catch: members hop up when the gift lands, staggered, and settle; nothing before or after",
		run = function()
			eq(GiftVisual.catch(-0.1, 1).hop, 0, "before landing")
			eq(GiftVisual.catch(GiftVisual.CATCH_SECONDS + 1, 1).hop, 0, "after")
			local peak = 0
			for i = 0, 40 do
				peak = math.max(peak, GiftVisual.catch(i * GiftVisual.CATCH_SECONDS / 40, 1).hop)
			end
			assert(peak > 0.5 and peak <= GiftVisual.CATCH_HOP + 1e-9, `peak {peak}`)
			-- the second member starts later than the first
			local t = GiftVisual.STAGGER_SECONDS / 2
			assert(GiftVisual.catch(t, 1).hop > 0, "first already up")
			eq(GiftVisual.catch(t, 2).hop, 0, "second still waiting")
			near(GiftVisual.catch(0, 1).hop, 0, "grounded at the start")
			assert(
				GiftVisual.catch(GiftVisual.CATCH_SECONDS / 2, 1).glow > 0,
				"glow while catching"
			)
		end,
	},
}
