--!strict
-- Pure camera pose (issue #10, spec s3; Mob Control framing note on the issue). A high camera
-- behind and above the lead, looking down about 50 degrees at the lane, so the lead sits low in
-- the frame with plenty of empty road ahead. The pose is plain numbers; the client turns it into a
-- CFrame. Values marked [default] are tuning defaults.
local CameraRig = {}

CameraRig.HEIGHT = 46 -- [default] studs above the road at pullback 1
CameraRig.BACK = 24 -- [default] studs behind the lead at pullback 1
CameraRig.LOOK_AHEAD = 12 -- [default] studs ahead of the lead that the camera aims at
CameraRig.FOLLOW_X = 0.5 -- [default] share of the lead's sideways offset the camera copies
CameraRig.FIELD_OF_VIEW = 70 -- [default] degrees

export type Pose = {
	px: number,
	py: number,
	pz: number, -- camera position
	lx: number,
	ly: number,
	lz: number, -- point it looks at
}

-- `pullback` is VisualBudget's cameraPullback multiplier (1 for a small party, up to 1.4).
-- Scaling height and distance together keeps the pitch constant.
function CameraRig.pose(leadX: number, leadZ: number, pullback: number): Pose
	local x = leadX * CameraRig.FOLLOW_X
	return {
		px = x,
		py = CameraRig.HEIGHT * pullback,
		pz = leadZ - CameraRig.BACK * pullback,
		lx = x,
		ly = 0,
		lz = leadZ + CameraRig.LOOK_AHEAD * pullback,
	}
end

-- Angle of the view direction below the horizon, in degrees.
function CameraRig.pitchDegrees(pose: Pose): number
	local horizontal = math.sqrt((pose.lx - pose.px) ^ 2 + (pose.lz - pose.pz) ^ 2)
	return math.deg(math.atan2(pose.py - pose.ly, horizontal))
end

-- Frame-rate independent ease toward a target (used for the camera and the lead's x).
function CameraRig.smooth(current: number, target: number, dt: number, rate: number): number
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

return CameraRig
