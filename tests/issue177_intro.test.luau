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
		name = "the move starts on the title pose at a nonzero lead position too",
		run = function()
			local x, z = 7.5, 40
			local start = IntroCamera.pose(x, z, 0)
			local title = IntroCamera.titlePose(x, z)
			near(start.px, title.px, "px")
			near(start.py, title.py, "py")
			near(start.pz, title.pz, "pz")
			near(start.lx, title.lx, "lx")
			near(start.ly, title.ly, "ly")
			near(start.lz, title.lz, "lz")
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
	{
		-- Issue #218: the avatar sat under the title text (about 59% across). The title column ends at
		-- 0.6 of the width (TitleLayout), so the avatar must read clear of it, on the right.
		name = "the title camera puts the avatar on the right, clear of the title column",
		run = function()
			local pose = IntroCamera.titlePose(LEAD_X, LEAD_Z)
			local dx, dy, dz = pose.lx - pose.px, pose.ly - pose.py, pose.lz - pose.pz
			local len = math.sqrt(dx * dx + dy * dy + dz * dz)
			dx, dy, dz = dx / len, dy / len, dz / len
			-- camera right = forward x up (up = +y), horizontal only
			local rx, rz = -dz, dx
			local rlen = math.sqrt(rx * rx + rz * rz)
			rx, rz = rx / rlen, rz / rlen
			-- the avatar's chest relative to the camera
			local vx, vy, vz =
				LEAD_X - pose.px, IntroCamera.TITLE_LOOK_HEIGHT - pose.py, LEAD_Z - pose.pz
			local depth = vx * dx + vy * dy + vz * dz
			local across = vx * rx + vz * rz
			local fov, aspect = math.rad(70), 2.1 -- Roblox default vertical FOV; a landscape phone
			local ndc = across / depth / (math.tan(fov / 2) * aspect)
			local screenX = 0.5 + 0.5 * ndc
			assert(screenX >= 0.68 and screenX <= 0.88, `avatar at {screenX} of the width`)
		end,
	},
}
