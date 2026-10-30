--!strict
-- The opening camera move (issue #177), replacing the Spanish count-in. On Play the camera opens
-- on a close view of the player's avatar face (the avatar faces +z, so the camera stands in front
-- of it, looking back), then pans and zooms out to the normal game camera (CameraRig.pose at
-- pullback 1). It is client presentation only: the run still starts only when the server says so,
-- and the client's one payload-free Start request is due once this move has settled.
-- Values marked [default] are tuning defaults; FACE_HEIGHT is UNVERIFIED on device.
local CameraRig = require("./CameraRig")

local IntroCamera = {}

IntroCamera.DURATION = 3.2 -- [default] seconds for the whole move, Play to settled
IntroCamera.FACE_HEIGHT = 4.9 -- [default] studs above the ground: the avatar's face (UNVERIFIED)
IntroCamera.FACE_DISTANCE = 7 -- [default] studs in front of the face where the close view starts
IntroCamera.FACE_CAMERA_HEIGHT = 5.4 -- [default] studs: the close view's camera sits at face level
IntroCamera.AVATAR_WAIT = 1.5 -- [default] seconds Play waits for the avatar before the move starts without it

export type Pose = CameraRig.Pose

-- `playedAt` is when Play was pressed; `moveAt` is when the move starts (nil while it waits for
-- the avatar). The run's Start request is due DURATION seconds after `moveAt`.
export type Intro = { playedAt: number, moveAt: number?, startDue: boolean }

-- Share of the move done, 0..1, for `elapsed` seconds since Play.
function IntroCamera.progress(elapsed: number): number
	return math.clamp(elapsed / IntroCamera.DURATION, 0, 1)
end

-- The two keyframes: the close view on the face, and the normal game camera it settles on.
local function closeView(leadX: number, leadZ: number): Pose
	return {
		px = leadX,
		py = IntroCamera.FACE_CAMERA_HEIGHT,
		pz = leadZ + IntroCamera.FACE_DISTANCE,
		lx = leadX,
		ly = IntroCamera.FACE_HEIGHT,
		lz = leadZ,
	}
end

local function smoothstep(u: number): number
	return u * u * (3 - 2 * u)
end

local function lerp(a: number, b: number, u: number): number
	return a + (b - a) * u
end

-- The camera pose at share `t` (0..1) of the move, for the lead at (leadX, leadZ). `leadX` is the
-- same mirrored x CameraRig.pose receives. t = 1 is exactly CameraRig.pose(leadX, leadZ, 1).
function IntroCamera.pose(leadX: number, leadZ: number, t: number): Pose
	local from = closeView(leadX, leadZ)
	local to = CameraRig.pose(leadX, leadZ, 1)
	local u = smoothstep(math.clamp(t, 0, 1))
	return {
		px = lerp(from.px, to.px, u),
		py = lerp(from.py, to.py, u),
		pz = lerp(from.pz, to.pz, u),
		lx = lerp(from.lx, to.lx, u),
		ly = lerp(from.ly, to.ly, u),
		lz = lerp(from.lz, to.lz, u),
	}
end

-- Starts the intro at `now` (the moment Play is pressed). The move itself waits for the avatar.
function IntroCamera.begin(now: number): Intro
	return { playedAt = now, moveAt = nil, startDue = false }
end

-- One frame of the intro. `avatarReady` says the lead's avatar part exists. Until it does, the
-- camera holds the close view and the move does not start; after AVATAR_WAIT seconds it starts
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
