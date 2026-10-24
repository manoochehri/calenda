--!strict
-- Issue #20: pure dancer animation (spec s7): swirling skirts, coordinated steps, the gift toss.
local Config = require("../src/shared/Config")
local DancerPose = require("../src/shared/DancerPose")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function near(actual: number, expected: number, name: string)
	assert(math.abs(actual - expected) < 1e-6, `{name}: expected {expected}, got {actual}`)
end

local BEAT = 60 / Config.music.bpm

return {
	{
		name = "steps: feet alternate (never both up), and the hop lands on every step",
		run = function()
			local leftUp, rightUp = false, false
			for i = 0, 400 do
				local p = DancerPose.pose(i * 0.01, 0)
				assert(p.footL * p.footR == 0, `both feet up at {i}`)
				assert(p.footL >= 0 and p.footR >= 0, "lifts are non-negative")
				assert(p.footL <= DancerPose.FOOT_LIFT + 1e-9, "left bounded")
				assert(p.footR <= DancerPose.FOOT_LIFT + 1e-9, "right bounded")
				assert(p.hop >= 0 and p.hop <= DancerPose.HOP_STUDS + 1e-9, "hop bounded")
				leftUp = leftUp or p.footL > 0.1
				rightUp = rightUp or p.footR > 0.1
			end
			assert(leftUp and rightUp, "both feet step")
			near(DancerPose.pose(0, 0).hop, 0, "grounded on the downbeat")
			near(DancerPose.pose(BEAT / 2, 0).hop, DancerPose.HOP_STUDS, "peak between steps")
		end,
	},
	{
		name = "coordinated: steps and hops ignore the swirl phase, so a group moves as one",
		run = function()
			for _, t in { 0, 0.23, 1.1, 3.7 } do
				local a, b = DancerPose.pose(t, 0), DancerPose.pose(t, 0.4)
				near(a.footL, b.footL, "footL")
				near(a.footR, b.footR, "footR")
				near(a.hop, b.hop, "hop")
				near(a.flare, b.flare, "flare")
			end
		end,
	},
	{
		name = "skirt: swirls both ways within bounds, flares open on the beat, repeats every bar",
		run = function()
			local minS, maxS = math.huge, -math.huge
			for i = 0, 800 do
				local p = DancerPose.pose(i * 0.01, 0)
				minS, maxS = math.min(minS, p.swirl), math.max(maxS, p.swirl)
				assert(
					p.flare >= DancerPose.FLARE_MIN - 1e-9 and p.flare <= 1 + 1e-9,
					"flare bounded"
				)
			end
			assert(
				minS < -0.8 * DancerPose.MAX_SWIRL and maxS > 0.8 * DancerPose.MAX_SWIRL,
				"swirls"
			)
			assert(
				minS >= -DancerPose.MAX_SWIRL - 1e-9 and maxS <= DancerPose.MAX_SWIRL + 1e-9,
				"max"
			)
			near(DancerPose.pose(BEAT * 2, 0).flare, 1, "fully open on a beat")
			near(DancerPose.pose(BEAT * 2.5, 0).flare, DancerPose.FLARE_MIN, "closed between beats")
			local bar = BEAT * Config.music.beatsPerBar
			for _, t in { 0, 0.6 } do
				near(
					DancerPose.pose(t, 0).swirl,
					DancerPose.pose(t + bar, 0).swirl,
					"swirl per bar"
				)
			end
			assert(
				math.abs(DancerPose.pose(0.5, 0).swirl - DancerPose.pose(0.5, 0.25).swirl) > 0.1,
				"swirl phase offsets decorrelate dancers"
			)
		end,
	},
	{
		name = "toss: raises the basket arm and peaks mid-throw; nothing before or after",
		run = function()
			local zero = DancerPose.toss(0)
			eq(zero.raise, 0, "starts down")
			local mid = DancerPose.toss(DancerPose.TOSS_SECONDS / 2)
			near(mid.raise, 1, "peak")
			eq(DancerPose.toss(DancerPose.TOSS_SECONDS).raise, 0, "ends down")
			eq(DancerPose.toss(-0.1).raise, 0, "before is idle")
			eq(DancerPose.toss(5).raise, 0, "after is idle")
			assert(DancerPose.toss(DancerPose.TOSS_SECONDS * 0.25).raise > 0.3, "quick wind-up")
			for i = 0, 50 do
				local t = DancerPose.toss(i * DancerPose.TOSS_SECONDS / 50)
				assert(
					t.raise >= 0 and t.raise <= 1 + 1e-9 and t.lift >= 0 and t.lift <= 1 + 1e-9,
					"range"
				)
			end
		end,
	},
	{
		name = "formation: the lead dancer first, the rest in a V behind and a little smaller",
		run = function()
			local solo = DancerPose.formation(3)
			eq(#solo, 3, "count")
			eq(solo[1].dx, 0, "lead at the center x")
			eq(solo[1].dz, 0, "lead z")
			eq(solo[1].scale, 1, "lead full size")
			assert(solo[2].dx < 0 and solo[3].dx > 0, "alternate sides")
			assert(solo[2].dz < 0 and solo[3].dz < 0, "behind the lead")
			assert(solo[2].scale < 1 and solo[2].scale > 0.5, "slightly smaller")
			eq(#DancerPose.formation(1), 1, "one")
			eq(#DancerPose.formation(0), 0, "none")
			local five = DancerPose.formation(5)
			assert(math.abs(five[4].dx) > math.abs(five[2].dx), "second rank is wider")
		end,
	},
}
