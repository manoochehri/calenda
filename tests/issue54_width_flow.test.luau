--!strict
-- Issue #54 / ADR 0012 step 2: the street is widened by changing the one number
-- StreetGeometry.HALF_WIDTH. These tests pin the accepted value (23, +15 percent) and prove it
-- flows to the lanes, the lead limit, the road, the curb stripe, the generated street (facades,
-- flag lanes, lamps, curb) and the ground that backs the camera view. Pure: runs under Lune.
local CameraRig = require("../src/shared/CameraRig")
local DebugLayout = require("../src/shared/DebugLayout")
local LaneGeometry = require("../src/shared/LaneGeometry")
local Layouts = require("../src/shared/Layouts")
local LevelTheme = require("../src/shared/LevelTheme")
local StreetGeometry = require("../src/shared/StreetGeometry")
local StreetSurface = require("../src/shared/StreetSurface")

local function eq(actual: number, expected: number, name: string)
	assert(math.abs(actual - expected) < 1e-9, `{name}: expected {expected}, got {actual}`)
end

-- True half-width (studs) of the view at the ground point `z` ahead: pinhole math along the view
-- axis, vertical FOV, the correct form of what CameraRig.visibleHalfWidth approximates (#229).
local function trueVisibleHalfWidth(pose: CameraRig.Pose, groundZ: number, aspect: number): number
	local pitch = math.rad(CameraRig.pitchDegrees(pose))
	local dz = groundZ - pose.pz
	local depth = dz * math.cos(pitch) + pose.py * math.sin(pitch)
	return depth * math.tan(math.rad(CameraRig.FIELD_OF_VIEW / 2)) * aspect
end

return {
	{
		name = "issue 54: the accepted street is 46 studs wide (HALF_WIDTH 23, +15 percent on 20)",
		run = function()
			eq(StreetGeometry.HALF_WIDTH, 23, "corridor half width")
			assert(StreetGeometry.HALF_WIDTH / 20 <= 1.15 + 1e-9, "at most about 15 percent wider")
		end,
	},
	{
		name = "issue 54: road, lanes and lead limit derive from the one number",
		run = function()
			local h = StreetGeometry.HALF_WIDTH
			eq(StreetGeometry.ROAD_HALF_WIDTH, h - StreetGeometry.ROAD_INSET, "road half")
			eq(StreetGeometry.ROAD_HALF_WIDTH, 18, "road half (36 stud road)")
			eq(StreetGeometry.LANE_WIDTH, 12, "lane width")
			eq(StreetGeometry.LANE_INNER_EDGE, 6, "inner edge")
			eq(StreetGeometry.LANE_CENTER, 12, "outer lane center")
			eq(StreetGeometry.LEAD_LIMIT, 18, "lead limit")
			eq(LaneGeometry.MIN_X, -18, "MIN_X")
			eq(LaneGeometry.MAX_X, 18, "MAX_X")
			eq(LaneGeometry.LEFT_EDGE, -6, "LEFT_EDGE")
			eq(LaneGeometry.RIGHT_EDGE, 6, "RIGHT_EDGE")
			eq(LaneGeometry.centerOf("left"), -12, "left center")
			eq(LaneGeometry.centerOf("right"), 12, "right center")
			assert(LaneGeometry.laneOf(5.99) == "center", "center band edge")
			assert(
				LaneGeometry.laneOf(6) == "right" and LaneGeometry.laneOf(18) == "right",
				"right band"
			)
			assert(LaneGeometry.laneOf(18.01) == nil, "outside the road")
		end,
	},
	{
		name = "issue 54: every layout takes the new width, lead limit and lane-center spawns",
		run = function()
			eq(DebugLayout.halfWidth, StreetGeometry.HALF_WIDTH, "debug halfWidth")
			eq(DebugLayout.leadLimit, StreetGeometry.LEAD_LIMIT, "debug leadLimit")
			for _, layout in Layouts.all do
				eq(layout.halfWidth, StreetGeometry.HALF_WIDTH, `{layout.name} halfWidth`)
				eq(layout.leadLimit, StreetGeometry.LEAD_LIMIT, `{layout.name} leadLimit`)
				assert(layout.leadLimit <= layout.halfWidth, `{layout.name}: lead stays inside`)
			end
		end,
	},
	{
		name = "issue 54: road surface and sidewalks follow the corridor (one sidewalk width, no drift)",
		run = function()
			local h = StreetGeometry.HALF_WIDTH
			eq(StreetSurface.roadHalfWidth(h), 18, "road half")
			eq(StreetSurface.sidewalkWidth(h), 5, "sidewalk")
			eq(
				StreetGeometry.sidewalkWidth(h),
				StreetSurface.sidewalkWidth(h),
				"one sidewalk definition"
			)
		end,
	},
	{
		name = "issue 54: the generated street's theme offsets follow the width (curb, facades, flags, lamps)",
		run = function()
			local h = StreetGeometry.HALF_WIDTH
			local l = LevelTheme.level1.layout
			eq(
				l.curbX,
				StreetGeometry.ROAD_HALF_WIDTH - 0.4,
				"curbX one stud-ish inside the road edge"
			)
			eq(l.facadeInset, h + 8, "facade inset keeps the 8 stud margin")
			eq(l.lampX, h + 1.5, "lamp x")
			assert(
				#LevelTheme.validate(LevelTheme.level1, h) == 0,
				"theme still valid for the corridor"
			)
			for _, lane in l.flagLanes do
				assert(
					lane.x > h and lane.x < l.facadeInset,
					"flag lanes stay between corridor and facades"
				)
			end
		end,
	},
	{
		name = "issue 54: the ground plate still reaches past the facades at every camera extent (no void)",
		run = function()
			local l = LevelTheme.level1.layout
			local facadeOuter = l.facadeInset + l.facadeDepth
			local plate = StreetSurface.groundPlate(DebugLayout.streetLength)
			assert(
				plate.x1 > facadeOuter and plate.x0 < -facadeOuter,
				"plate wider than the facades"
			)
			for _, pullback in { 1, 1.2, 1.4 } do
				for _, leadX in { -StreetGeometry.LEAD_LIMIT, 0, StreetGeometry.LEAD_LIMIT } do
					local pose = CameraRig.pose(leadX, 400, pullback)
					local far = StreetSurface.farVisibleGroundZ(pose)
					for _, aspect in { 0.46, 1.0, 2.2, 3.0 } do
						local reach = math.abs(pose.px) + trueVisibleHalfWidth(pose, far, aspect)
						assert(reach <= plate.x1, `side reach {reach} past plate (aspect {aspect})`)
					end
				end
			end
		end,
	},
}
