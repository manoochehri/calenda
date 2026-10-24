--!strict
-- The lead is the player's own Roblox avatar (issue #55, ADR 0003). The Roblox-free decisions are
-- tested here: where the root part goes each frame, when the fallback block may show, rig heights.
local LeadPose = require("../src/shared/LeadPose")
local ViewMap = require("../src/shared/ViewMap")

local function near(actual: number, expected: number, name: string)
	assert(math.abs(actual - expected) < 1e-6, `{name}: expected {expected}, got {actual}`)
end

return {
	{
		name = "the root stands on the mirrored x and the lead's z (ViewMap, issue #58)",
		run = function()
			local p = LeadPose.at(7, 123, 0, 0, 3)
			near(p.x, ViewMap.x(7), "x")
			near(p.z, 123, "z")
		end,
	},
	{
		name = "bob never sinks below the standing height and stays within BOB_HEIGHT",
		run = function()
			for i = 0, 200 do
				local p = LeadPose.at(0, 0, i * 0.037, 0, 3)
				assert(p.y >= 3 - 1e-9, `below standing height at {i}: {p.y}`)
				assert(p.y <= 3 + LeadPose.BOB_HEIGHT + 1e-9, `above bob range at {i}: {p.y}`)
			end
		end,
	},
	{
		name = "the defeat lift is added on top of the bob",
		run = function()
			near(LeadPose.at(0, 0, 0, 2.5, 3).y, 3 + 2.5, "lift at clock 0 (no bob)")
		end,
	},
	{
		name = "the lead faces forward (+z): yaw of half a turn, since a Roblox front is -z",
		run = function()
			near(LeadPose.FACING_YAW, math.pi, "yaw")
		end,
	},
	{
		name = "R15 root height is hip height plus half the root; R6 is leg length plus half the root",
		run = function()
			near(LeadPose.rootHeight("R15", 2, 2), 3, "R15 default")
			near(LeadPose.rootHeight("R15", 2.4, 2), 3.4, "R15 scaled hips")
			near(LeadPose.rootHeight("R6", 0, 2), 3, "R6 default")
			assert(LeadPose.rootHeight("R6", 0, 0) > 0, "never zero or negative")
		end,
	},
	{
		name = "fallback block: not while an avatar exists, only after the grace period without one",
		run = function()
			assert(not LeadPose.showFallback(true, 99), "avatar present")
			assert(not LeadPose.showFallback(false, 0), "just started waiting")
			assert(
				not LeadPose.showFallback(false, LeadPose.FALLBACK_GRACE - 0.01),
				"still in grace"
			)
			assert(LeadPose.showFallback(false, LeadPose.FALLBACK_GRACE), "grace over")
		end,
	},
	{
		name = "absence counts up without an avatar and resets the moment one is present",
		run = function()
			local a = 0
			for _ = 1, 10 do
				a = LeadPose.absence(a, false, 0.5)
			end
			near(a, 5, "five seconds without")
			near(LeadPose.absence(a, true, 0.5), 0, "reset on avatar")
		end,
	},
	{
		name = "the lead's hat height used by the camera covers an avatar with accessories",
		run = function()
			local CameraRig = require("../src/shared/CameraRig")
			assert(
				CameraRig.LEAD_TOP >= LeadPose.AVATAR_TOP,
				"camera framing must include the avatar"
			)
		end,
	},
}
