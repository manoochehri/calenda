--!strict
-- The one lane resolver (ADR 0010 Decision 1, spec Amendment 9). Pure: no Roblox APIs.
-- Three logical lanes across the street: left [-15,-5), center [-5,5), right [5,15]. A value on a
-- boundary belongs to the lane on its right, so -5 is center and 5 is right. Targeting, contact,
-- pickup activation and the client markings all read lanes from here.
-- The numbers derive from StreetGeometry (issue #220), the one street definition; at its default
-- they are -15 / -5 / 5 / 15 with centers -10 / 0 / 10.
local StreetGeometry = require("./StreetGeometry")

local LaneGeometry = {}

export type Lane = "left" | "center" | "right"

LaneGeometry.MIN_X = -StreetGeometry.ROAD_HALF_WIDTH -- studs; the furthest lane edge on the left
LaneGeometry.MAX_X = StreetGeometry.ROAD_HALF_WIDTH -- studs; the furthest lane edge on the right
LaneGeometry.LEFT_EDGE = -StreetGeometry.LANE_INNER_EDGE -- studs; left band is [MIN_X, LEFT_EDGE)
LaneGeometry.RIGHT_EDGE = StreetGeometry.LANE_INNER_EDGE -- studs; right band is [RIGHT_EDGE, MAX_X]

-- The lane that owns lateral position x, or nil when x lies outside the street's lanes.
function LaneGeometry.laneOf(x: any): Lane?
	if type(x) ~= "number" or x ~= x or x < LaneGeometry.MIN_X or x > LaneGeometry.MAX_X then
		return nil
	end
	if x < LaneGeometry.LEFT_EDGE then
		return "left"
	elseif x < LaneGeometry.RIGHT_EDGE then
		return "center"
	end
	return "right"
end

-- The lateral centre of a lane: -10, 0 or 10.
function LaneGeometry.centerOf(lane: Lane): number
	if lane == "left" then
		return -StreetGeometry.LANE_CENTER
	elseif lane == "right" then
		return StreetGeometry.LANE_CENTER
	end
	return 0
end

-- Bounds follow the same half-open ownership as laneOf; visual footprints stay inside them.
function LaneGeometry.bounds(lane: Lane): (number, number)
	if lane == "left" then
		return LaneGeometry.MIN_X, LaneGeometry.LEFT_EDGE
	elseif lane == "right" then
		return LaneGeometry.RIGHT_EDGE, LaneGeometry.MAX_X
	end
	return LaneGeometry.LEFT_EDGE, LaneGeometry.RIGHT_EDGE
end

function LaneGeometry.fit(lane: Lane, x: number, halfSize: number): number
	local lo, hi = LaneGeometry.bounds(lane)
	return math.clamp(x, lo + halfSize, hi - halfSize)
end

function LaneGeometry.maxScatterHalfWidth(lane: Lane, halfSize: number): number
	local lo, hi = LaneGeometry.bounds(lane)
	return math.max(0, (hi - lo) / 2 - halfSize)
end

return LaneGeometry
