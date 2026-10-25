--!strict
-- Pure pose for Rey inside the moving parade (issue #100, ADR 0006). Keep her in the outer lane, on a
-- deterministic side, with a march bob derived only from the lead's run position. Since #93 she
-- stands AHEAD of the lead by Config.rey.aheadStuds, so a shot (which only flies forward) can reach
-- her; the server computes the same pose for targeting, so client and server agree.
local Config = require("./Config")
local ReyFormation = {}

-- At the outermost steering pose the center reaches 9.9 studs. The wings extend 0.79 studs from
-- the body center, so scale 4.15 fills the clearance to the inside edge of the curb stripe (13.2).
ReyFormation.SCALE = 4.15
ReyFormation.HALF_WIDTH = 0.79 * ReyFormation.SCALE
ReyFormation.HALF_DEPTH = 0.9775 * ReyFormation.SCALE
ReyFormation.HEIGHT = 1.9 * ReyFormation.SCALE
ReyFormation.CENTER_Y = 0.99 * ReyFormation.SCALE
ReyFormation.CENTER_Z = -0.1525 * ReyFormation.SCALE
ReyFormation.BODY_CENTER_Y = 0.68
ReyFormation.BODY_HALF_HEIGHT = 0.55
ReyFormation.OFFSET = 8.5
ReyFormation.BEHIND = 6 -- superseded by #93: Rey is ahead of the lead (Config.rey.aheadStuds)

export type Pose = { x: number, z: number, side: number, bob: number }

-- Rey's lane side from the seed alone: +1 right (positive x), -1 left. Fixed for the whole run.
function ReyFormation.side(seed: number): number
	assert(
		type(seed) == "number" and seed == seed and math.abs(seed) < math.huge,
		"finite seed required"
	)
	return if math.floor(seed) % 2 == 0 then 1 else -1
end

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
	local side = ReyFormation.side(seed)
	local edge = roadHalfWidth - ReyFormation.HALF_WIDTH - 0.2
	local x = math.clamp(side * ReyFormation.OFFSET + leadX * 0.1, -edge, edge)
	local bob = 0.25 * math.abs(math.sin(leadZ * 0.35))
	return { x = x, z = leadZ + Config.rey.aheadStuds, side = side, bob = bob }
end

return ReyFormation
