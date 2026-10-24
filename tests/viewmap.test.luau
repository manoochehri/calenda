--!strict
-- Regression for the mirrored lateral axis (issue #58): "left" (negative world x) must be on the
-- screen's left. A Roblox camera looking along +Z with up +Y has screen-right = world -X, so the
-- client mirrors x when it draws (ViewMap). These tests project points with the real camera pose.
local CameraRig = require("../src/shared/CameraRig")
local DebugLayout = require("../src/shared/DebugLayout")
local InputIntent = require("../src/shared/InputIntent")
local ViewMap = require("../src/shared/ViewMap")

-- +1 when the (Roblox position) point is on the camera's screen-right, -1 on the screen-left.
-- Roblox: RightVector = LookVector x UpVector, with up = +Y, so right = (-look.z, 0, look.x).
local function screenSide(pose: CameraRig.Pose, px: number, pz: number): number
	local lookX, lookZ = pose.lx - pose.px, pose.lz - pose.pz
	local rightX, rightZ = -lookZ, lookX
	local d = (px - pose.px) * rightX + (pz - pose.pz) * rightZ
	return if d > 0 then 1 elseif d < 0 then -1 else 0
end

return {
	{
		name = "with the mirror, world x=-5 is on the screen's left and x=+5 on the right",
		run = function()
			local pose = CameraRig.pose(0, 100, 1)
			assert(screenSide(pose, ViewMap.x(-5), 120) == -1, "x=-5 must be screen-left")
			assert(screenSide(pose, ViewMap.x(5), 120) == 1, "x=+5 must be screen-right")
		end,
	},
	{
		name = "without the mirror it is the opposite (the bug this fixes)",
		run = function()
			local pose = CameraRig.pose(0, 100, 1)
			assert(screenSide(pose, -5, 120) == 1, "unmirrored x=-5 lands on the screen's right")
			assert(screenSide(pose, 5, 120) == -1, "unmirrored x=+5 lands on the screen's left")
		end,
	},
	{
		name = "mirror is its own inverse and keeps zero at zero",
		run = function()
			assert(ViewMap.fromView(ViewMap.x(7.5)) == 7.5, "round trip")
			assert(ViewMap.x(0) == 0, "centre stays centre")
		end,
	},
	{
		name = "the camera follows the lead on the mirrored side",
		run = function()
			-- lead at world x=-8 (left): camera x is mirrored with it, lead stays right of centre-left
			local pose = CameraRig.pose(ViewMap.x(-8), 100, 1)
			assert(screenSide(pose, ViewMap.x(-8), 100) == -1, "lead on screen-left of the camera")
			assert(pose.px == ViewMap.x(-8) * CameraRig.FOLLOW_X, "camera copies the mirrored x")
		end,
	},
	{
		name = "keyboard left lowers the world x and moves the parade to screen-left",
		run = function()
			local pose = CameraRig.pose(0, 100, 1)
			local axis = InputIntent.keyAxis(true, false)
			local x = InputIntent.stepKeys(0, axis, 0.5, 18)
			assert(x < 0, "left key decreases world x")
			assert(screenSide(pose, ViewMap.x(x), 100) == -1, "and is drawn on screen-left")
			local r = InputIntent.stepKeys(0, InputIntent.keyAxis(false, true), 0.5, 18)
			assert(screenSide(pose, ViewMap.x(r), 100) == 1, "right key is drawn on screen-right")
		end,
	},
	{
		name = "dragging left lowers the world x and moves the parade to screen-left",
		run = function()
			local pose = CameraRig.pose(0, 100, 1)
			local x = InputIntent.dragToX(0, -200, 1000, 18)
			assert(x < 0, "drag left decreases world x")
			assert(screenSide(pose, ViewMap.x(x), 100) == -1, "and is drawn on screen-left")
			local r = InputIntent.dragToX(0, 200, 1000, 18)
			assert(screenSide(pose, ViewMap.x(r), 100) == 1, "drag right is drawn on screen-right")
		end,
	},
	{
		name = "the 'left' gate panel of every gate is on screen-left, 'right' on screen-right",
		run = function()
			for _, gate in DebugLayout.gates do
				local pose = CameraRig.pose(0, gate.z - 40, 1)
				local l = ViewMap.x(ViewMap.gateWorldX("left", DebugLayout.halfWidth))
				local r = ViewMap.x(ViewMap.gateWorldX("right", DebugLayout.halfWidth))
				assert(screenSide(pose, l, gate.z) == -1, `gate {gate.id} left op on screen-left`)
				assert(screenSide(pose, r, gate.z) == 1, `gate {gate.id} right op on screen-right`)
			end
		end,
	},
	{
		name = "clusters keep their DebugLayout side on screen",
		run = function()
			local pose = CameraRig.pose(0, 0, 1)
			for _, c in DebugLayout.clusters do
				local want = if c.spawn.x < 0 then -1 else 1
				assert(screenSide(pose, ViewMap.x(c.spawn.x), c.spawn.z) == want, `cluster {c.id}`)
			end
		end,
	},
}
