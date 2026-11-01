--!strict
-- The one definition of the street's width (architect finding on #54, step 1; issue #220). Pure: no
-- Roblox APIs. Every width-dependent number derives from HALF_WIDTH here, so the drawn road, the
-- steering bound, the lane bands and centers, the authored spawn x values and the validator cannot
-- drift apart. Widening the street is one edit to HALF_WIDTH (ADR 0012): 20 to 23 for issue #54,
-- +15 percent, giving a 46-stud corridor, a 36-stud road, 12-stud lanes and sidewalks of 5. The
-- generated street (LevelTheme) offsets derive from it too.
local StreetGeometry = {}

StreetGeometry.HALF_WIDTH = 23 -- [default] studs: the walkable corridor, sidewalks included (46 wide; was 20, ADR 0012)
StreetGeometry.ROAD_INSET = 5 -- [default] studs the road edge sits inside the corridor edge
StreetGeometry.LANE_COUNT = 3 -- left, center, right (ADR 0010)

-- Half width of the road surface for a corridor of `halfWidth` (18 at the default 23).
function StreetGeometry.roadHalfWidth(halfWidth: number): number
	return halfWidth - StreetGeometry.ROAD_INSET
end

-- Width of one sidewalk for a corridor of `halfWidth`.
function StreetGeometry.sidewalkWidth(halfWidth: number): number
	return halfWidth - StreetGeometry.roadHalfWidth(halfWidth)
end

StreetGeometry.ROAD_HALF_WIDTH = StreetGeometry.roadHalfWidth(StreetGeometry.HALF_WIDTH) -- 18
-- The three lanes split the road evenly: width 12, outer edges +-18, inner edges +-6, centers 0 / +-12.
StreetGeometry.LANE_WIDTH = StreetGeometry.ROAD_HALF_WIDTH * 2 / StreetGeometry.LANE_COUNT
StreetGeometry.LANE_INNER_EDGE = StreetGeometry.LANE_WIDTH / 2 -- +-6: the center lane's edges
StreetGeometry.LANE_CENTER = StreetGeometry.LANE_WIDTH -- 12: |x| of an outer lane's center
-- The furthest |x| the lead may be asked to stand at by default (ADR 0010 Decision 3): the road edge.
StreetGeometry.LEAD_LIMIT = StreetGeometry.ROAD_HALF_WIDTH

return StreetGeometry
