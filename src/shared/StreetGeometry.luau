--!strict
-- The one definition of the street's width (architect finding on #54, step 1; issue #220). Pure: no
-- Roblox APIs. Every width-dependent number derives from HALF_WIDTH here, so the drawn road, the
-- steering bound, the lane bands and centers, the authored spawn x values and the validator cannot
-- drift apart. At HALF_WIDTH = 20 every value equals what the code used before this module existed
-- (tests/issue220_street_geometry.test.luau pins that); changing the street's width is a separate,
-- ADR-gated change (step 2) that edits HALF_WIDTH and nothing else.
local StreetGeometry = {}

StreetGeometry.HALF_WIDTH = 20 -- [default] studs: the walkable corridor, sidewalks included (40 wide)
StreetGeometry.ROAD_INSET = 5 -- [default] studs the road edge sits inside the corridor edge
StreetGeometry.LANE_COUNT = 3 -- left, center, right (ADR 0010)

-- Half width of the road surface for a corridor of `halfWidth` (15 at the default 20).
function StreetGeometry.roadHalfWidth(halfWidth: number): number
	return halfWidth - StreetGeometry.ROAD_INSET
end

-- Width of one sidewalk for a corridor of `halfWidth`.
function StreetGeometry.sidewalkWidth(halfWidth: number): number
	return halfWidth - StreetGeometry.roadHalfWidth(halfWidth)
end

StreetGeometry.ROAD_HALF_WIDTH = StreetGeometry.roadHalfWidth(StreetGeometry.HALF_WIDTH) -- 15
-- The three lanes split the road evenly: width 10, outer edges +-15, inner edges +-5, centers 0 / +-10.
StreetGeometry.LANE_WIDTH = StreetGeometry.ROAD_HALF_WIDTH * 2 / StreetGeometry.LANE_COUNT
StreetGeometry.LANE_INNER_EDGE = StreetGeometry.LANE_WIDTH / 2 -- +-5: the center lane's edges
StreetGeometry.LANE_CENTER = StreetGeometry.LANE_WIDTH -- 10: |x| of an outer lane's center
-- The furthest |x| the lead may be asked to stand at by default (ADR 0010 Decision 3): the road edge.
StreetGeometry.LEAD_LIMIT = StreetGeometry.ROAD_HALF_WIDTH

-- KNOWN DRIFT, deliberately NOT fixed in step 1 (it would change follower slots and obstacle
-- feedback positions). WorldBuilder draws the sidewalk from ROAD_INSET (5), but FollowerSlots and
-- ObstacleFeedback assume 6 ("mirrors WorldBuilder"), so they treat the road as 1 stud narrower than
-- the one drawn. Both read this constant so step 2 resolves it in one place, on purpose.
StreetGeometry.FOLLOWER_SIDEWALK_WIDTH = 6

return StreetGeometry
