--!strict
local CameraRig = require("../src/shared/CameraRig")
local VisualBudget = require("../src/shared/VisualBudget")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

return {
	{
		name = "camera is high, behind the lead and looks past it (lead low in frame, road ahead)",
		run = function()
			local p = CameraRig.pose(0, 100, 1)
			assert(p.py > 20, "high above the road")
			assert(p.pz < 100, "behind the lead")
			assert(p.lz > 100, "looks at a point ahead of the lead")
			eq(p.ly, 0, "looks at the ground")
		end,
	},
	{
		name = "looks down 45 to 60 degrees (Mob Control framing note)",
		run = function()
			for _, pullback in { 1, 1.2, 1.4 } do
				local pitch = CameraRig.pitchDegrees(CameraRig.pose(0, 0, pullback))
				assert(pitch >= 45 and pitch <= 60, `pitch {pitch} at pullback {pullback}`)
			end
		end,
	},
	{
		name = "follows the lead sideways only partly, so both sidewalks stay in view",
		run = function()
			local p = CameraRig.pose(10, 0, 1)
			assert(p.px > 0 and p.px < 10, "camera x between the center and the lead")
			eq(p.lx, p.px, "looks straight ahead, not skewed")
		end,
	},
	{
		name = "pullback moves the camera back and up without changing the pitch",
		run = function()
			local near, far = CameraRig.pose(0, 0, 1), CameraRig.pose(0, 0, 1.4)
			assert(far.py > near.py and far.pz < near.pz, "farther")
			assert(
				math.abs(CameraRig.pitchDegrees(near) - CameraRig.pitchDegrees(far)) < 1e-6,
				"same pitch"
			)
		end,
	},
	{
		name = "pullback comes from the visual budget: bigger parade, modestly farther",
		run = function()
			local small = CameraRig.pose(0, 0, VisualBudget.allocate(10).cameraPullback)
			local huge = CameraRig.pose(0, 0, VisualBudget.allocate(10000).cameraPullback)
			assert(huge.py > small.py, "huge parade pulls back")
			assert(huge.py < small.py * 1.5, "but only modestly")
		end,
	},
	{
		name = "smooth moves toward the target without overshoot and is dt-independent",
		run = function()
			local one = CameraRig.smooth(0, 10, 0.2, 8)
			assert(one > 0 and one < 10, "partway")
			local two = CameraRig.smooth(CameraRig.smooth(0, 10, 0.1, 8), 10, 0.1, 8)
			assert(math.abs(one - two) < 1e-9, "two half steps equal one whole step")
			eq(CameraRig.smooth(4, 4, 0.1, 8), 4, "at target")
			eq(CameraRig.smooth(0, 10, 0, 8), 0, "zero dt")
		end,
	},
}
