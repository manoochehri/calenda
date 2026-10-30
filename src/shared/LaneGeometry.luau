--!strict
-- The one lane resolver (ADR 0010 Decision 1, spec Amendment 9). Pure: no Roblox APIs.
-- Three logical lanes across the street: left [-15,-5), center [-5,5), right [5,15]. A value on a
-- boundary belongs to the lane on its right, so -5 is center and 5 is right. Targeting, contact,
-- pickup activation and the client markings all read lanes from here.
local LaneGeometry = {}

export type Lane = "left" | "center" | "right"

LaneGeometry.MIN_X = -15 -- [default] studs; the furthest lane edge on the left
LaneGeometry.MAX_X = 15 -- [default] studs; the furthest lane edge on the right
LaneGeometry.LEFT_EDGE = -5 -- [default] studs; left band is [MIN_X, LEFT_EDGE)
LaneGeometry.RIGHT_EDGE = 5 -- [default] studs; right band is [RIGHT_EDGE, MAX_X]

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
		return -10
	elseif lane == "right" then
		return 10
	end
	return 0
end

return LaneGeometry
