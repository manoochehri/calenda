--!strict
-- Pure placement for Rey inside the moving parade (issue #100). Keep her in the outer lane,
-- behind the lead, and use a deterministic side that changes only when steering would crowd her.
local ReyFormation = {}

-- At the outermost steering pose the center reaches 9.9 studs. The wings extend 0.79 studs from
-- the body center, so scale 4.15 fills the clearance to the inside edge of the curb stripe (13.2).
ReyFormation.SCALE = 4.15
ReyFormation.HALF_WIDTH = 0.79 * ReyFormation.SCALE
ReyFormation.HALF_DEPTH = 0.9775 * ReyFormation.SCALE
ReyFormation.HEIGHT = 1.9 * ReyFormation.SCALE
ReyFormation.CENTER_Y = 0.99 * ReyFormation.SCALE
ReyFormation.CENTER_Z = -0.1525 * ReyFormation.SCALE
ReyFormation.OFFSET = 8.5
ReyFormation.BEHIND = 6

export type Pose = { x: number, z: number, side: number }

function ReyFormation.pose(leadX: number, leadZ: number, seed: number, roadHalfWidth: number): Pose
	assert(
		type(leadX) == "number" and leadX == leadX and math.abs(leadX) < math.huge,
		"finite leadX required"
	)
	assert(
		type(leadZ) == "number" and leadZ == leadZ and math.abs(leadZ) < math.huge,
		"finite leadZ required"
	)
	assert(
		type(seed) == "number" and seed == seed and math.abs(seed) < math.huge,
		"finite seed required"
	)
	assert(
		type(roadHalfWidth) == "number" and roadHalfWidth > ReyFormation.HALF_WIDTH,
		"valid road width required"
	)
	local side = if math.floor(seed) % 2 == 0 then 1 else -1
	local edge = roadHalfWidth - ReyFormation.HALF_WIDTH - 0.2
	local x = math.clamp(side * ReyFormation.OFFSET + leadX * 0.1, -edge, edge)
	return { x = x, z = leadZ - ReyFormation.BEHIND, side = side }
end

return ReyFormation
