--!strict
local CameraRig = require("../src/shared/CameraRig")
local Formation = require("../src/shared/Formation")
local SectionScale = require("../src/shared/SectionScale")
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
	{
		name = "the next gate row stays visible over the tallest prop at every pullback (spec s3)",
		run = function()
			for pullback = 1, 1.4, 0.05 do
				local pose = CameraRig.pose(0, 0, pullback)
				assert(
					CameraRig.gateClearance(pose, 0, CameraRig.PROP_FRONT, CameraRig.TALLEST_PROP)
						>= CameraRig.CLEARANCE - 1e-9,
					`gate row hidden at pullback {pullback}`
				)
			end
		end,
	},
	{
		name = "a taller prop raises the camera so the gate row is still clear",
		run = function()
			local base = CameraRig.pose(0, 0, 1)
			local tall = CameraRig.pose(0, 0, 1, 40)
			assert(tall.py > base.py, "camera raised")
			assert(
				CameraRig.gateClearance(tall, 0, CameraRig.PROP_FRONT, 40)
					>= CameraRig.CLEARANCE - 1e-9,
				"clear over a 40-stud prop"
			)
			-- without the rule the base pose would be blocked by that prop
			assert(
				CameraRig.gateClearance(base, 0, CameraRig.PROP_FRONT, 40) < CameraRig.CLEARANCE,
				"the base pose is blocked by a 40-stud prop"
			)
			for _, pullback in { 1, 1.2, 1.4 } do
				local pitch = CameraRig.pitchDegrees(CameraRig.pose(0, 0, pullback, 40))
				assert(pitch >= 45 and pitch <= 65, `pitch {pitch} at pullback {pullback}`)
			end
		end,
	},
	{
		name = "a short prop never lowers the camera below the curve",
		run = function()
			eq(CameraRig.pose(0, 0, 1.2, 2).py, CameraRig.pose(0, 0, 1.2).py, "unchanged")
			eq(CameraRig.pose(0, 0, 1.2, 0).py, CameraRig.HEIGHT * 1.2, "curve height")
		end,
	},
	{
		name = "the lead stays in frame and above the section stand-ins' sight line",
		run = function()
			for pullback = 1, 1.4, 0.1 do
				for _, h in { CameraRig.TALLEST_PROP } do
					local pose = CameraRig.pose(0, 0, pullback, h)
					assert(CameraRig.leadInFrame(pose, 0), `lead off screen at {pullback}`)
					for i, slot in Formation.sectionSlots(6) do
						local own = SectionScale.heightOf(
							({ "puppet", "globo", "dancers" })[(i - 1) % 3 + 1],
							i
						)
						assert(
							CameraRig.leadClearance(pose, 0, slot.dz, math.min(h, own)) >= 0,
							`lead hidden behind a prop at dz {slot.dz}, pullback {pullback}`
						)
					end
				end
			end
		end,
	},
	{
		name = "the pullback easing completes: it reaches the curve target and never overshoots",
		run = function()
			local value = 1
			for _ = 1, 60 * 6 do
				local nxt = CameraRig.smooth(value, 1.4, 1 / 60, CameraRig.PULLBACK_RATE)
				assert(nxt >= value and nxt <= 1.4, "monotonic, no overshoot")
				value = nxt
			end
			assert(1.4 - value < 0.001, `settled within 6 s, got {value}`)
		end,
	},
	{
		name = "issue 70: the standing portal is the tallest prop and its row stays visible behind it",
		run = function()
			local PortalGeometry = require("../src/shared/PortalGeometry")
			assert(
				CameraRig.TALLEST_PROP >= PortalGeometry.TOP,
				"portal height feeds the camera rule"
			)
			for _, pullback in { 1, 1.2, 1.4 } do
				local pose = CameraRig.pose(0, 0, pullback)
				local c = CameraRig.gateClearance(pose, 0, CameraRig.PROP_FRONT, PortalGeometry.TOP)
				assert(c >= CameraRig.CLEARANCE - 1e-6, `clearance {c} at pullback {pullback}`)
			end
		end,
	},
	{
		name = "issue 70: screenFraction and studsForScreenFraction are inverses and shrink with distance",
		run = function()
			local pose = CameraRig.pose(0, 0, 1)
			local f = CameraRig.screenFraction(pose, 10, 30, 6)
			assert(f > 0 and f < 1, "fraction")
			local back = CameraRig.studsForScreenFraction(pose, 10, 30, f)
			assert(math.abs(back - 6) < 1e-9, "inverse")
			assert(CameraRig.screenFraction(pose, 10, 90, 6) < f, "farther is smaller")
		end,
	},
	{
		name = "issue 82: a leaning banner (top away from the camera) is seen more face-on than a vertical one",
		run = function()
			local pose = CameraRig.pose(0, 0, 1)
			local flat = CameraRig.screenFraction(pose, 12, 33, 5)
			local lean = CameraRig.screenFraction(pose, 12, 33, 5, math.rad(30))
			assert(lean > flat * 1.3, "about 1.5x taller on screen")
			assert(
				CameraRig.screenFraction(pose, 12, 33, 5, 0) == flat,
				"lean 0 is the vertical case"
			)
			local back = CameraRig.studsForScreenFraction(pose, 12, 33, lean, math.rad(30))
			assert(math.abs(back - 5) < 1e-9, "inverse with lean")
		end,
	},
	{
		name = "issue 82: with a lean the banner cannot hide a lead that has not reached its plane",
		run = function()
			local pose = CameraRig.pose(0, 0, 1)
			local lean = math.rad(30)
			assert(not CameraRig.bannerHidesLead(pose, 0, 5, 7, 17.4, lean), "portal ahead")
			assert(CameraRig.bannerHidesLead(pose, 0, -3, 7, 17.4, lean), "just past")
			assert(
				not CameraRig.bannerHidesLead(pose, 0, -3, 7, 17.4, lean, 0.5),
				"tiny subject is below the underside"
			)
		end,
	},
	{
		name = "issue 70: a banner hides the lead only while the lead is just past it",
		run = function()
			local pose = CameraRig.pose(0, 0, 1)
			local b, t = 7, 19
			assert(
				not CameraRig.bannerHidesLead(pose, 0, 5, b, t),
				"portal still ahead of the lead"
			)
			assert(CameraRig.bannerHidesLead(pose, 0, -3, b, t), "lead just past the portal")
			assert(not CameraRig.bannerHidesLead(pose, 0, -14, b, t), "well past it")
			assert(
				not CameraRig.bannerHidesLead(pose, 0, -3, 30, 40),
				"banner above the line of sight"
			)
		end,
	},
}
