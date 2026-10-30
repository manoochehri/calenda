--!strict
-- Issues #177 and #211: the opening camera move. Play starts it from the title framing, orbits the
-- player, zooms out to show the street, and settles behind the player on the normal game camera.
-- The run's Start request is due only once that move has settled.
local CameraRig = require("../src/shared/CameraRig")
local IntroCamera = require("../src/shared/IntroCamera")

local function near(actual: number, expected: number, name: string)
	assert(math.abs(actual - expected) < 1e-9, `{name}: expected {expected}, got {actual}`)
end

local LEAD_X, LEAD_Z = 0, 0

return {
	{
		name = "the intro ends exactly on the normal game camera (seamless hand-off)",
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
		name = "the hand-off holds away from the origin too (lead at a nonzero x and z)",
		run = function()
			local x, z = 7.5, 40
			local end_ = IntroCamera.pose(x, z, 1)
			local game = CameraRig.pose(x, z, 1)
			near(end_.px, game.px, "px")
			near(end_.py, game.py, "py")
			near(end_.pz, game.pz, "pz")
			near(end_.lx, game.lx, "lx")
			near(end_.ly, game.ly, "ly")
			near(end_.lz, game.lz, "lz")
		end,
	},
	{
		name = "the intro ends behind the player (the avatar faces +z, the camera is at -z)",
		run = function()
			local end_ = IntroCamera.pose(LEAD_X, LEAD_Z, 1)
			assert(end_.pz < LEAD_Z, "camera is behind the lead")
		end,
	},
	{
		name = "progress is elapsed time over DURATION, clamped to 0..1",
		run = function()
			near(IntroCamera.progress(0), 0, "start")
			near(IntroCamera.progress(IntroCamera.DURATION / 2), 0.5, "middle")
			near(IntroCamera.progress(IntroCamera.DURATION * 3), 1, "past the end")
			near(IntroCamera.progress(-1), 0, "before Play")
		end,
	},
	{
		name = "run start waits for the intro to finish, and is due exactly once",
		run = function()
			local intro = IntroCamera.begin(0)
			local due = 0
			local t = 0
			while t <= IntroCamera.DURATION + 2 do
				local _, startDue = IntroCamera.step(intro, t, LEAD_X, LEAD_Z, true)
				if startDue then
					due += 1
					assert(t >= IntroCamera.DURATION, "Start not due before DURATION")
				end
				t += 0.05
			end
			assert(due == 1, `Start due {due} times, expected once`)
		end,
	},
	{
		name = "with no avatar yet, the move does not start: the camera holds the title view",
		run = function()
			local intro = IntroCamera.begin(0)
			local pose = IntroCamera.step(intro, 0.5, LEAD_X, LEAD_Z, false)
			local title = IntroCamera.titlePose(LEAD_X, LEAD_Z)
			near(pose.px, title.px, "px")
			near(pose.pz, title.pz, "pz")
			assert(intro.moveAt == nil, "move waits for the avatar")
		end,
	},
	{
		name = "a missing avatar falls back to the move after AVATAR_WAIT (stand-in grace path)",
		run = function()
			local intro = IntroCamera.begin(0)
			IntroCamera.step(intro, IntroCamera.AVATAR_WAIT, LEAD_X, LEAD_Z, false)
			assert(intro.moveAt ~= nil, "move starts after AVATAR_WAIT even without the avatar")
		end,
	},
}
