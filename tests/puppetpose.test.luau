--!strict
local Config = require("../src/shared/Config")
local PuppetPose = require("../src/shared/PuppetPose")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function near(actual: number, expected: number, name: string)
	assert(math.abs(actual - expected) < 1e-6, `{name}: expected {expected}, got {actual}`)
end

local BEAT = 60 / Config.music.bpm

return {
	{
		name = "pose: repeats every bar (sways and bobs to the beat), deterministic",
		run = function()
			local bar = BEAT * Config.music.beatsPerBar
			for _, t in { 0, 0.37, 1.9 } do
				local a, b = PuppetPose.pose(t, 0), PuppetPose.pose(t + bar, 0)
				near(a.headBob, b.headBob, "headBob")
				near(a.armLeft, b.armLeft, "armLeft")
				near(a.armRight, b.armRight, "armRight")
				near(a.sway, b.sway, "sway")
				near(a.clap, b.clap, "clap")
			end
		end,
	},
	{
		name = "pose: head bobs, arms swing loosely out of phase, body sways, all bounded",
		run = function()
			local minBob, maxBob, maxArm, maxSway = math.huge, -math.huge, 0, 0
			local differ = false
			for i = 0, 400 do
				local p = PuppetPose.pose(i * 0.01, 0)
				minBob, maxBob = math.min(minBob, p.headBob), math.max(maxBob, p.headBob)
				maxArm = math.max(maxArm, math.abs(p.armLeft), math.abs(p.armRight))
				maxSway = math.max(maxSway, math.abs(p.sway))
				if math.abs(p.armLeft - p.armRight) > 0.05 then
					differ = true
				end
				assert(p.clap >= 0 and p.clap <= 1, "clap in 0..1")
			end
			assert(maxBob - minBob > 0.2, "head visibly bobs")
			assert(maxArm > 0.4 and maxArm <= PuppetPose.MAX_ARM_RADIANS, "arms swing within limit")
			assert(maxSway > 0.02 and maxSway <= PuppetPose.MAX_SWAY_RADIANS, "sways within limit")
			eq(differ, true, "arms are not mirrored")
		end,
	},
	{
		name = "pose: claps land on the beat (clap peaks at beat edges, is open mid-beat)",
		run = function()
			near(PuppetPose.pose(0, 0).clap, 1, "downbeat")
			near(PuppetPose.pose(BEAT, 0).clap, 1, "next beat")
			assert(PuppetPose.pose(BEAT / 2, 0).clap < 0.2, "open between beats")
		end,
	},
	{
		name = "pose: intensity grows with the number of sections but stays bounded (no endless growth)",
		run = function()
			local small = PuppetPose.intensity(1)
			local big = PuppetPose.intensity(40)
			local huge = PuppetPose.intensity(10000)
			assert(big > small, "more sections, more intensity")
			eq(huge <= PuppetPose.MAX_INTENSITY, true, "capped")
			eq(PuppetPose.intensity(0), 1, "baseline")
		end,
	},
	{
		name = "rise: 0 at start, 1 at end, overshoots then settles, clamped outside 0..1",
		run = function()
			eq(PuppetPose.rise(0), 0, "start")
			eq(PuppetPose.rise(1), 1, "end")
			eq(PuppetPose.rise(-3), 0, "below")
			eq(PuppetPose.rise(4), 1, "above")
			local over = false
			for i = 1, 19 do
				if PuppetPose.rise(i / 20) > 1 then
					over = true
				end
			end
			eq(over, true, "overshoots for a pop")
		end,
	},
}
