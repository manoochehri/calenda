--!strict
-- Issue #220 (architect finding on #54, step 1): one street definition. StreetGeometry derives the
-- road, lanes, lead limit and spawn x from a single HALF_WIDTH. This is a pure refactor, so the
-- values below are the LITERALS the code used before the module existed; any difference is a
-- behavior change and fails here. Changing the street's width is step 2 (an ADR), not this test.
local DebugLayout = require("../src/shared/DebugLayout")
local FollowerSlots = require("../src/shared/FollowerSlots")
local LaneGeometry = require("../src/shared/LaneGeometry")
local Layouts = require("../src/shared/Layouts")
local ObstacleFeedback = require("../src/shared/ObstacleFeedback")
local StreetGeometry = require("../src/shared/StreetGeometry")
local StreetSurface = require("../src/shared/StreetSurface")

local function eq(actual: number, expected: number, name: string)
	assert(actual == expected, `{name}: expected {expected}, got {actual}`)
end

return {
	{
		name = "issue 220: StreetGeometry at its default equals the old literals",
		run = function()
			eq(StreetGeometry.HALF_WIDTH, 20, "corridor half width")
			eq(StreetGeometry.ROAD_INSET, 5, "road inset")
			eq(StreetGeometry.ROAD_HALF_WIDTH, 15, "road half width")
			eq(StreetGeometry.LANE_WIDTH, 10, "lane width")
			eq(StreetGeometry.LANE_INNER_EDGE, 5, "center lane edge")
			eq(StreetGeometry.LANE_CENTER, 10, "outer lane center")
			eq(StreetGeometry.LEAD_LIMIT, 15, "lead limit")
		end,
	},
	{
		name = "issue 220: lane bands and centers are unchanged (-15 / -5 / 5 / 15, centers -10 / 0 / 10)",
		run = function()
			eq(LaneGeometry.MIN_X, -15, "MIN_X")
			eq(LaneGeometry.MAX_X, 15, "MAX_X")
			eq(LaneGeometry.LEFT_EDGE, -5, "LEFT_EDGE")
			eq(LaneGeometry.RIGHT_EDGE, 5, "RIGHT_EDGE")
			eq(LaneGeometry.centerOf("left"), -10, "left center")
			eq(LaneGeometry.centerOf("center"), 0, "center center")
			eq(LaneGeometry.centerOf("right"), 10, "right center")
			assert(
				LaneGeometry.laneOf(-15) == "left" and LaneGeometry.laneOf(-5.01) == "left",
				"left band"
			)
			assert(
				LaneGeometry.laneOf(-5) == "center" and LaneGeometry.laneOf(4.99) == "center",
				"center band"
			)
			assert(
				LaneGeometry.laneOf(5) == "right" and LaneGeometry.laneOf(15) == "right",
				"right band"
			)
			assert(
				LaneGeometry.laneOf(15.01) == nil and LaneGeometry.laneOf(-15.01) == nil,
				"outside"
			)
		end,
	},
	{
		name = "issue 220: StreetSurface road and sidewalk widths are unchanged (30 stud road, 5 stud sidewalks)",
		run = function()
			eq(StreetSurface.ROAD_INSET, 5, "ROAD_INSET")
			eq(StreetSurface.roadHalfWidth(20), 15, "road half width")
			eq(StreetSurface.sidewalkWidth(20), 5, "sidewalk width")
		end,
	},
	{
		name = "issue 220: every layout takes its width, lead limit and spawn x from StreetGeometry",
		run = function()
			eq(DebugLayout.halfWidth, 20, "debug halfWidth")
			eq(DebugLayout.leadLimit, 15, "debug leadLimit")
			assert(
				DebugLayout.halfWidth == StreetGeometry.HALF_WIDTH,
				"debug layout reads HALF_WIDTH"
			)
			for _, layout in Layouts.all do
				eq(layout.halfWidth, 20, `{layout.name} halfWidth`)
				eq(layout.leadLimit, 15, `{layout.name} leadLimit`)
			end
			for _, cluster in DebugLayout.clusters do
				eq(
					math.abs(cluster.spawn.x),
					StreetGeometry.LANE_CENTER,
					`debug cluster {cluster.id} spawn x`
				)
			end
		end,
	},
	{
		-- Known drift, pinned on purpose so step 2 changes it deliberately rather than by accident.
		name = "issue 220: the 6-stud follower/obstacle sidewalk drift is pinned (WorldBuilder draws 5)",
		run = function()
			eq(StreetGeometry.FOLLOWER_SIDEWALK_WIDTH, 6, "pinned follower sidewalk")
			eq(FollowerSlots.SIDEWALK_WIDTH, 6, "FollowerSlots.SIDEWALK_WIDTH")
			eq(ObstacleFeedback.SIDEWALK_WIDTH, 6, "ObstacleFeedback.SIDEWALK_WIDTH")
			eq(FollowerSlots.roadHalfWidth(), 14, "road half width followers assume")
			eq(
				StreetGeometry.sidewalkWidth(StreetGeometry.HALF_WIDTH),
				5,
				"sidewalk actually drawn"
			)
		end,
	},
}
