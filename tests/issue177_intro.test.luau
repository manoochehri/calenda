--!strict
-- Issue #177: the opening camera move replaces the count-in. On Play the camera opens on a close
-- view of the player's avatar face, then pans and zooms out to the normal game camera. The run's
-- Start request is due only once that move has settled.
local CameraRig = require("../src/shared/CameraRig")
local IntroCamera = require("../src/shared/IntroCamera")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function near(actual: number, expected: number, name: string)
	assert(math.abs(actual - expected) < 1e-9, `{name}: expected {expected}, got {actual}`)
end

local LEAD_X, LEAD_Z = 0, 0

return {
	{
		name = "intro opens on a close view in front of the avatar face, looking back at it",
		run = function()
			local p = IntroCamera.pose(LEAD_X, LEAD_Z, 0)
			assert(p.pz > LEAD_Z, "camera is in front of the avatar (it faces +z)")
			assert(p.pz - LEAD_Z <= 10, "close: within 10 studs of the face")
			near(p.ly, IntroCamera.FACE_HEIGHT, "looks at the face height")
			near(p.lz, LEAD_Z, "looks at the avatar")
			assert(p.py <= CameraRig.LEAD_TOP, "camera at about face height")
		end,
	},
	{
		name = "intro ends exactly on the normal game camera (seamless hand-off)",
		run = function()
			local end_ = IntroCamera.pose(LEAD_X, LEAD_Z, 1)
			local game = CameraRig.pose(LEAD_X, LEAD_Z, 1)
			near(end_.px, game.px, "px")
			near(end_.py, game.py, "py")
			near(end_.pz, game.pz, "pz")
			near(end_.lx, game.lx, "lx")
			near(end_.ly, game.ly, "ly")
			near(end_.lz, game.lz, "lz")
		end,
	},
	{
		name = "intro pans and zooms out: camera moves back and up, monotonically",
		run = function()
			local last = IntroCamera.pose(LEAD_X, LEAD_Z, 0)
			for i = 1, 20 do
				local p = IntroCamera.pose(LEAD_X, LEAD_Z, i / 20)
				assert(p.pz <= last.pz + 1e-9, `camera z moves back at step {i}`)
				assert(p.py >= last.py - 1e-9, `camera height rises at step {i}`)
				last = p
			end
			local mid = IntroCamera.pose(LEAD_X, LEAD_Z, 0.5)
			assert(mid.pz < IntroCamera.pose(LEAD_X, LEAD_Z, 0).pz, "midway is already moving")
			assert(mid.py > IntroCamera.pose(LEAD_X, LEAD_Z, 0).py, "midway is already rising")
		end,
	},
	{
		name = "intro camera never passes through the avatar on its way out",
		run = function()
			for i = 0, 40 do
				local p = IntroCamera.pose(LEAD_X, LEAD_Z, i / 40)
				if math.abs(p.pz - LEAD_Z) < 1.5 then
					assert(p.py > CameraRig.LEAD_TOP, `camera passes over the avatar at step {i}`)
				end
			end
		end,
	},
	{
		name = "progress is elapsed time over DURATION, clamped to 0..1",
		run = function()
			assert(IntroCamera.DURATION > 0, "positive duration")
			near(IntroCamera.progress(0), 0, "start")
			near(IntroCamera.progress(IntroCamera.DURATION / 2), 0.5, "halfway")
			near(IntroCamera.progress(IntroCamera.DURATION * 3), 1, "after the end is clamped")
			near(IntroCamera.progress(-1), 0, "before the start is clamped")
		end,
	},
	{
		name = "run start waits for intro to finish, and is due exactly once",
		run = function()
			local intro = IntroCamera.begin(100)
			local d = IntroCamera.DURATION
			local _, due = IntroCamera.step(intro, 100, LEAD_X, LEAD_Z)
			eq(due, false, "not due at Play")
			_, due = IntroCamera.step(intro, 100 + d / 2, LEAD_X, LEAD_Z)
			eq(due, false, "not due halfway through the move")
			_, due = IntroCamera.step(intro, 100 + d - 0.001, LEAD_X, LEAD_Z)
			eq(due, false, "not due just before the move settles")
			_, due = IntroCamera.step(intro, 100 + d, LEAD_X, LEAD_Z)
			eq(due, true, "due once the move has settled")
			_, due = IntroCamera.step(intro, 100 + d + 5, LEAD_X, LEAD_Z)
			eq(due, false, "never due a second time")
		end,
	},
	{
		name = "the intro's camera pose is the one the step returns, settling on the game camera",
		run = function()
			local intro = IntroCamera.begin(0)
			local pose = IntroCamera.step(intro, IntroCamera.DURATION, LEAD_X, LEAD_Z)
			local game = CameraRig.pose(LEAD_X, LEAD_Z, 1)
			near(pose.pz, game.pz, "settled pz")
			near(pose.py, game.py, "settled py")
		end,
	},
}
