--!strict
-- The opening camera move (issues #177, #211). The title shows the street with the player's avatar
-- standing in it, framed on the right in a three-quarter view. On Play the camera orbits the lead,
-- zooms out to show the scene, then comes round behind the player and settles on the normal game
-- camera (CameraRig.pose at pullback 1). It is client presentation only: the run still starts only
-- when the server says so, and the client's one payload-free Start request is due once this move
-- has settled. Values marked [default] are tuning defaults; the look is UNVERIFIED on device.
local CameraRig = require("./CameraRig")

local IntroCamera = {}

IntroCamera.DURATION = 4.5 -- [default] seconds for the whole move, Play to settled
IntroCamera.AVATAR_WAIT = 1.5 -- [default] seconds Play waits for the avatar before the move starts without it
IntroCamera.TITLE_RADIUS = 9 -- [default] studs from the lead while the title shows
IntroCamera.TITLE_AZIMUTH = 0.6 -- [default] radians round from the avatar's front (0 = straight in front)
IntroCamera.TITLE_HEIGHT = 4.5 -- [default] studs above the ground while the title shows
IntroCamera.TITLE_LOOK_SHIFT = -7 -- [default] studs along the camera's right: the title looks left of the avatar, so it sits right (#218: -2.5 left it under the title text)
IntroCamera.TITLE_LOOK_HEIGHT = 3.5 -- [default] studs: the title looks at the avatar's chest
IntroCamera.ZOOM_OUT = 20 -- [default] extra studs of radius at the middle of the move, to show the street

export type Pose = CameraRig.Pose

-- `playedAt` is when Play was pressed; `moveAt` is when the move starts (nil while it waits for
-- the avatar). The run's Start request is due DURATION seconds after `moveAt`.
export type Intro = { playedAt: number, moveAt: number?, startDue: boolean }

-- Share of the move done, 0..1, for `elapsed` seconds since Play.
function IntroCamera.progress(elapsed: number): number
	return math.clamp(elapsed / IntroCamera.DURATION, 0, 1)
end

local function smoothstep(u: number): number
	return u * u * (3 - 2 * u)
end

local function lerp(a: number, b: number, u: number): number
	return a + (b - a) * u
end

-- The camera framing the title screen shows while the lead stands at its start.
function IntroCamera.titlePose(leadX: number, leadZ: number): Pose
	local az = IntroCamera.TITLE_AZIMUTH
	return {
		px = leadX + IntroCamera.TITLE_RADIUS * math.sin(az),
		py = IntroCamera.TITLE_HEIGHT,
		pz = leadZ + IntroCamera.TITLE_RADIUS * math.cos(az),
		-- Issue #218: the shift runs along the camera's own right vector, so it moves the avatar
		-- across the screen (a plain world-x shift barely moved it from this angle).
		lx = leadX + IntroCamera.TITLE_LOOK_SHIFT * math.cos(az),
		ly = IntroCamera.TITLE_LOOK_HEIGHT,
		lz = leadZ - IntroCamera.TITLE_LOOK_SHIFT * math.sin(az),
	}
end

-- The camera pose at share `t` (0..1) of the move, for the lead at (leadX, leadZ). `leadX` is the
-- same mirrored x CameraRig.pose receives. The camera sweeps round the lead from the title angle to
-- directly behind it (azimuth pi), easing the radius out to show the street and back in. t = 0 is
-- titlePose and t = 1 is exactly CameraRig.pose(leadX, leadZ, 1).
function IntroCamera.pose(leadX: number, leadZ: number, t: number): Pose
	local title = IntroCamera.titlePose(leadX, leadZ)
	local game = CameraRig.pose(leadX, leadZ, 1)
	local s = smoothstep(math.clamp(t, 0, 1))
	local angle = lerp(IntroCamera.TITLE_AZIMUTH, math.pi, s)
	local radius = lerp(IntroCamera.TITLE_RADIUS, CameraRig.BACK, s)
		+ IntroCamera.ZOOM_OUT * math.sin(math.pi * math.clamp(t, 0, 1))
	local pivotX = lerp(leadX, game.px, s)
	return {
		px = pivotX + radius * math.sin(angle),
		py = lerp(title.py, game.py, s),
		pz = leadZ + radius * math.cos(angle),
		lx = lerp(title.lx, game.lx, s),
		ly = lerp(title.ly, game.ly, s),
		lz = lerp(title.lz, game.lz, s),
	}
end

-- Starts the intro at `now` (the moment Play is pressed). The move itself waits for the avatar.
function IntroCamera.begin(now: number): Intro
	return { playedAt = now, moveAt = nil, startDue = false }
end

-- One frame of the intro. `avatarReady` says the lead's avatar part exists. Until it does, the
-- camera holds the title view and the move does not start; after AVATAR_WAIT seconds it starts
-- anyway, and the existing stand-in grace path covers the lead. Returns this frame's pose and
-- `startDue`: true exactly once, on the first frame at or after DURATION past the move's start.
-- The caller sends the run's Start request on that frame.
function IntroCamera.step(
	intro: Intro,
	now: number,
	leadX: number,
	leadZ: number,
	avatarReady: boolean
): (Pose, boolean)
	if intro.moveAt == nil and (avatarReady or now - intro.playedAt >= IntroCamera.AVATAR_WAIT) then
		intro.moveAt = now
	end
	if intro.moveAt == nil then
		return IntroCamera.pose(leadX, leadZ, 0), false
	end
	local elapsed = now - intro.moveAt
	local pose = IntroCamera.pose(leadX, leadZ, IntroCamera.progress(elapsed))
	local startDue = false
	if elapsed >= IntroCamera.DURATION and not intro.startDue then
		intro.startDue = true
		startDue = true
	end
	return pose, startDue
end

return IntroCamera
