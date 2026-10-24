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
CameraRig.PULLBACK_RATE = 2 -- [default] easing rate of the pullback as the parade grows (1/s)

-- Gate readability behind tall props (spec s3, issue #22). Gates lie flat on the road ahead of the
-- lead; props stand on or behind the lead's row. The camera line to the next gate row must clear
-- the tallest prop by CLEARANCE studs, else the camera is raised (pitch stays under 65 degrees for
-- props up to 30 studs). Widening the FOV is deliberately not used: pullback already scales the
-- visible street, and a wider FOV only shrinks the gate text.
CameraRig.GATE_NEAR = 30 -- [default] studs ahead of the lead of the nearest gate row that must read
CameraRig.PROP_FRONT = 4 -- [default] how far ahead of the lead's z a prop (entourage) can stand
CameraRig.TALLEST_PROP = 16 -- [default] GUESS, studs: puppet is 11 (PuppetFigure.HEIGHT); update when #19/#20 (globo, dancers) land
CameraRig.CLEARANCE = 3 -- [default] studs the sight line must clear a prop by
CameraRig.LEAD_TOP = 6 -- studs; top of the lead: the player's avatar with accessories (LeadPose.AVATAR_TOP)

export type Pose = {
	px: number,
	py: number,
	pz: number, -- camera position
	lx: number,
	ly: number,
	lz: number, -- point it looks at
}

-- Height above the ground, at depth `propZ`, of the straight line from a camera at (camY, camZ) to
-- the point (targetY, targetZ). Used to ask whether a prop of that height blocks the view.
local function lineHeight(
	camY: number,
	camZ: number,
	targetY: number,
	targetZ: number,
	propZ: number
): number
	local f = (propZ - camZ) / (targetZ - camZ)
	return camY + (targetY - camY) * f
end

-- Lowest camera height at which the line to the gate row clears a prop of `propHeight` standing
-- PROP_FRONT ahead of the lead, with the camera `back` studs behind the lead.
function CameraRig.minHeightForGate(back: number, propHeight: number): number
	local dGate = CameraRig.GATE_NEAR + back
	local dProp = CameraRig.PROP_FRONT + back
	return (propHeight + CameraRig.CLEARANCE) * dGate / (dGate - dProp)
end

-- `pullback` is VisualBudget's cameraPullback multiplier (1 for a small party, up to 1.4).
-- Scaling height and distance together keeps the pitch constant. `propHeight` (default
-- TALLEST_PROP) is the tallest prop the next gate row must stay visible behind: the camera is
-- raised only when the curve height would not clear it.
function CameraRig.pose(leadX: number, leadZ: number, pullback: number, propHeight: number?): Pose
	local x = leadX * CameraRig.FOLLOW_X
	local back = CameraRig.BACK * pullback
	local height = math.max(
		CameraRig.HEIGHT * pullback,
		CameraRig.minHeightForGate(back, propHeight or CameraRig.TALLEST_PROP)
	)
	return {
		px = x,
		py = height,
		pz = leadZ - CameraRig.BACK * pullback,
		lx = x,
		ly = 0,
		lz = leadZ + CameraRig.LOOK_AHEAD * pullback,
	}
end

-- Studs by which the camera line to the nearest gate row (GATE_NEAR ahead of the lead) clears a
-- prop of `propHeight` standing `propDz` ahead of the lead. Negative means the prop hides it.
function CameraRig.gateClearance(
	pose: Pose,
	leadZ: number,
	propDz: number,
	propHeight: number
): number
	return lineHeight(pose.py, pose.pz, 0, leadZ + CameraRig.GATE_NEAR, leadZ + propDz) - propHeight
end

-- Studs by which the camera line to the lead's hat clears a prop `propDz` from the lead. A prop at
-- or behind the camera cannot block it (infinite clearance).
function CameraRig.leadClearance(
	pose: Pose,
	leadZ: number,
	propDz: number,
	propHeight: number
): number
	local propZ = leadZ + propDz
	if propZ <= pose.pz then
		return math.huge
	end
	return lineHeight(pose.py, pose.pz, CameraRig.LEAD_TOP, leadZ, propZ) - propHeight
end

-- True when the lead (ground to hat) is inside the vertical field of view with a 5 degree margin.
function CameraRig.leadInFrame(pose: Pose, leadZ: number): boolean
	local pitch = CameraRig.pitchDegrees(pose)
	local half = CameraRig.FIELD_OF_VIEW / 2 - 5
	local dz = leadZ - pose.pz
	for _, y in { 0, CameraRig.LEAD_TOP } do
		local below = math.deg(math.atan2(pose.py - y, dz))
		if math.abs(below - pitch) > half then
			return false
		end
	end
	return true
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
