--!strict
-- Issue #220 (architect finding on #54, step 1): one street definition. StreetGeometry derives the
-- road, lanes, lead limit and spawn x from a single HALF_WIDTH. Width-dependent values are
-- checked against HALF_WIDTH by formula; the pinned numbers for the accepted width (ADR 0012) are in
-- issue54_width_flow.test.luau.
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
		name = "issue 220: every derived value follows HALF_WIDTH by formula (the values are pinned in issue54_width_flow)",
		run = function()
			local h = StreetGeometry.HALF_WIDTH
			eq(StreetGeometry.ROAD_INSET, 5, "road inset")
			eq(StreetGeometry.ROAD_HALF_WIDTH, h - 5, "road half width")
			eq(StreetGeometry.LANE_WIDTH, (h - 5) * 2 / 3, "lane width")
			eq(StreetGeometry.LANE_INNER_EDGE, StreetGeometry.LANE_WIDTH / 2, "center lane edge")
			eq(StreetGeometry.LANE_CENTER, StreetGeometry.LANE_WIDTH, "outer lane center")
			eq(StreetGeometry.LEAD_LIMIT, h - 5, "lead limit")
		end,
	},
	{
		name = "issue 220: lane bands and centers follow the road (edges at +-ROAD_HALF_WIDTH, inner +-LANE_INNER_EDGE)",
		run = function()
			eq(LaneGeometry.MIN_X, -StreetGeometry.ROAD_HALF_WIDTH, "MIN_X")
			eq(LaneGeometry.MAX_X, StreetGeometry.ROAD_HALF_WIDTH, "MAX_X")
			eq(LaneGeometry.LEFT_EDGE, -StreetGeometry.LANE_INNER_EDGE, "LEFT_EDGE")
			eq(LaneGeometry.RIGHT_EDGE, StreetGeometry.LANE_INNER_EDGE, "RIGHT_EDGE")
			eq(LaneGeometry.centerOf("left"), -StreetGeometry.LANE_CENTER, "left center")
			eq(LaneGeometry.centerOf("center"), 0, "center center")
			eq(LaneGeometry.centerOf("right"), StreetGeometry.LANE_CENTER, "right center")
			local e = StreetGeometry.LANE_INNER_EDGE
			local r = StreetGeometry.ROAD_HALF_WIDTH
			assert(
				LaneGeometry.laneOf(-r) == "left" and LaneGeometry.laneOf(-e - 0.01) == "left",
				"left"
			)
			assert(
				LaneGeometry.laneOf(-e) == "center" and LaneGeometry.laneOf(e - 0.01) == "center",
				"center"
			)
			assert(LaneGeometry.laneOf(e) == "right" and LaneGeometry.laneOf(r) == "right", "right")
			assert(
				LaneGeometry.laneOf(r + 0.01) == nil and LaneGeometry.laneOf(-r - 0.01) == nil,
				"outside"
			)
		end,
	},
	{
		name = "issue 220: StreetSurface road and sidewalk widths are unchanged (30 stud road, 5 stud sidewalks)",
		run = function()
			eq(StreetSurface.ROAD_INSET, 5, "ROAD_INSET")
			eq(
				StreetSurface.roadHalfWidth(20),
				15,
				"road half width (pure function of its argument)"
			)
			eq(StreetSurface.sidewalkWidth(20), 5, "sidewalk width")
		end,
	},
	{
		name = "issue 220: every layout takes its width, lead limit and spawn x from StreetGeometry",
		run = function()
			eq(DebugLayout.halfWidth, StreetGeometry.HALF_WIDTH, "debug halfWidth")
			eq(DebugLayout.leadLimit, StreetGeometry.LEAD_LIMIT, "debug leadLimit")
			assert(
				DebugLayout.halfWidth == StreetGeometry.HALF_WIDTH,
				"debug layout reads HALF_WIDTH"
			)
			for _, layout in Layouts.all do
				eq(layout.halfWidth, StreetGeometry.HALF_WIDTH, `{layout.name} halfWidth`)
				eq(layout.leadLimit, StreetGeometry.LEAD_LIMIT, `{layout.name} leadLimit`)
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
		name = "issue 220 / ADR 0012: followers and obstacle feedback use the sidewalk WorldBuilder draws (drift resolved)",
		run = function()
			local drawn = StreetGeometry.sidewalkWidth(StreetGeometry.HALF_WIDTH)
			eq(drawn, 5, "sidewalk actually drawn")
			eq(FollowerSlots.SIDEWALK_WIDTH, drawn, "FollowerSlots.SIDEWALK_WIDTH")
			eq(ObstacleFeedback.SIDEWALK_WIDTH, drawn, "ObstacleFeedback.SIDEWALK_WIDTH")
			eq(
				FollowerSlots.roadHalfWidth(),
				StreetGeometry.ROAD_HALF_WIDTH,
				"follower road = drawn road"
			)
		end,
	},
}
