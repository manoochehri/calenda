--!strict
-- Issue #193 (owner report: no visible lanes on the street, like mob control). The lane markings
-- are data (LaneMarkings) read from LaneGeometry, the module the server resolves lanes with, and
-- drawn by LaneView. Fail-first: before the change neither module exists.
local fs = require("@lune/fs")
local DebugLayout = require("../src/shared/DebugLayout")
local LaneGeometry = require("../src/shared/LaneGeometry")
local LaneMarkings = require("../src/shared/LaneMarkings")
local LayerHeights = require("../src/shared/LayerHeights")
local StreetSurface = require("../src/shared/StreetSurface")

local LANES = { "left", "center", "right" }
local road = StreetSurface.roadHalfWidth(DebugLayout.halfWidth)
local specs = LaneMarkings.specs(DebugLayout)

local function eq(actual: any, expected: any, label: string)
	assert(actual == expected, `{label}: expected {tostring(expected)}, got {tostring(actual)}`)
end

return {
	{
		name = "issue 193: every lane has centre arrows at its LaneGeometry centre, along the street",
		run = function()
			for _, lane in LANES do
				local count = 0
				for _, s in specs do
					if s.kind == "arrow" and s.lane == lane then
						count += 1
						eq(s.x, LaneGeometry.centerOf(lane :: LaneGeometry.Lane), `{s.name} x`)
						eq(LaneGeometry.laneOf(s.x), lane, `{s.name} lane`)
						assert(
							s.z >= (DebugLayout.startPlazaEnd or 0)
								and s.z <= DebugLayout.plazaStart,
							`{s.name} is off the street`
						)
					end
				end
				assert(count >= 5, `lane {lane} has only {count} centre arrows`)
			end
		end,
	},
	{
		name = "issue 193: dividers sit on the two LaneGeometry boundaries for the whole street",
		run = function()
			local seen: { [number]: boolean } = {}
			for _, s in specs do
				if s.kind == "divider" then
					seen[s.x] = true
					eq(s.z - s.sz / 2, DebugLayout.startPlazaEnd or 0, `{s.name} start`)
					eq(s.z + s.sz / 2, DebugLayout.plazaStart, `{s.name} end`)
				end
			end
			assert(seen[LaneGeometry.LEFT_EDGE], "no divider at LEFT_EDGE")
			assert(seen[LaneGeometry.RIGHT_EDGE], "no divider at RIGHT_EDGE")
		end,
	},
	{
		name = "issue 193: markings stay on the road, never on the sidewalk",
		run = function()
			for _, s in specs do
				assert(
					s.x - s.sx / 2 >= -road and s.x + s.sx / 2 <= road,
					`{s.name} reaches the sidewalk`
				)
				assert(
					s.x - s.sx / 2 >= LaneGeometry.MIN_X and s.x + s.sx / 2 <= LaneGeometry.MAX_X,
					`{s.name} outside the lanes`
				)
			end
			for _, s in specs do
				if s.kind == "arrow" then
					for _, part in LaneMarkings.arrowParts(s) do
						assert(
							part.x0 >= s.x - s.sx / 2 and part.x1 <= s.x + s.sx / 2,
							`{part.name} reaches outside its arrow`
						)
						assert(part.z1 <= s.z + s.sz / 2 + 1e-9, `{part.name} passes the arrow tip`)
						assert(
							part.x0 >= -road and part.x1 <= road,
							`{part.name} reaches the sidewalk`
						)
					end
				end
			end
			for _, lane in LANES do
				local centre = LaneGeometry.centerOf(lane :: LaneGeometry.Lane)
				for _, bar in LaneMarkings.leadBracket(centre, 100) do
					assert(
						bar.x - bar.sx / 2 >= -road and bar.x + bar.sx / 2 <= road,
						"lead bracket reaches the sidewalk"
					)
				end
			end
		end,
	},
	{
		name = "issue 193: no marking is coplanar with another flat surface (no z-fighting)",
		run = function()
			local info = {
				streetLength = DebugLayout.streetLength,
				plazaStart = DebugLayout.plazaStart,
				halfWidth = DebugLayout.halfWidth,
				leadLimit = 15,
				gates = DebugLayout.gates,
				obstacles = DebugLayout.obstacles,
				startPlazaEnd = DebugLayout.startPlazaEnd,
			}
			local list = LayerHeights.surfaces(info)
			-- Every arrow as its separate Parts (shaft and both barbs), as LaneView draws them.
			for _, s in specs do
				if s.kind == "divider" then
					table.insert(list, {
						name = s.name,
						top = s.top,
						x0 = s.x - s.sx / 2,
						x1 = s.x + s.sx / 2,
						z0 = s.z - s.sz / 2,
						z1 = s.z + s.sz / 2,
					})
				else
					for _, part in LaneMarkings.arrowParts(s) do
						table.insert(list, {
							name = part.name,
							top = part.top,
							x0 = part.x0,
							x1 = part.x1,
							z0 = part.z0,
							z1 = part.z1,
						})
					end
				end
			end
			for _, bar in { LaneMarkings.leadBracket(0, 0)[1] } do
				table.insert(list, {
					name = "LeadBracket",
					top = bar.top,
					x0 = bar.x - bar.sx / 2,
					x1 = bar.x + bar.sx / 2,
					z0 = -LaneMarkings.BRACKET_HALF_LENGTH - 1,
					z1 = DebugLayout.streetLength,
				})
			end
			local conflicts = LayerHeights.conflicts(list)
			assert(#conflicts == 0, `z-fight risks: {table.concat(conflicts, "; ")}`)
		end,
	},
	{
		name = "issue 193: the lead bracket marks the lead's lane, boundaries as the server resolves them",
		run = function()
			local function centreOf(x: number): number
				return LaneMarkings.leadBracket(x, 50)[1].x
			end
			eq(centreOf(-12), LaneGeometry.centerOf("left"), "x=-12")
			eq(centreOf(LaneGeometry.LEFT_EDGE), LaneGeometry.centerOf("center"), "x=-5 is centre")
			eq(centreOf(0), LaneGeometry.centerOf("center"), "x=0")
			eq(centreOf(LaneGeometry.RIGHT_EDGE), LaneGeometry.centerOf("right"), "x=5 is right")
			eq(centreOf(40), LaneGeometry.centerOf("right"), "off the street clamps to right")
			eq(centreOf(-40), LaneGeometry.centerOf("left"), "off the street clamps to left")
			local bars = LaneMarkings.leadBracket(0, 50)
			eq(#bars, 2, "two bars")
			assert(bars[1].z > 50 and bars[2].z < 50, "bracket frames the lead")
		end,
	},
	{
		name = "issue 193: the per-frame lead update is allocation-free and guarded (no redundant writes)",
		run = function()
			for _, x in { -40, -12, -5, 0, 4.9, 5, 40 } do
				eq(
					LaneMarkings.leadCentre(x),
					LaneMarkings.leadBracket(x, 7)[1].x,
					`leadCentre x={x}`
				)
			end
			eq(LaneMarkings.leadBracket(0, 0)[1].sx, LaneMarkings.bracketWidth(), "bracket width")
			local view = fs.readFile("src/client/LaneView.luau")
			local body = string.match(view, "function LaneView%.update.-\nend\n") or ""
			assert(string.find(body, "return", 1, true), "update has no early return")
			assert(
				string.find(body, "leadBracket", 1, true) == nil,
				"update allocates via leadBracket"
			)
			assert(string.find(body, "Size", 1, true) == nil, "update writes Size every frame")
		end,
	},
	{
		name = "issue 193: LaneView draws shadowless, static marks from LaneMarkings and Main moves the bracket",
		run = function()
			local view = fs.readFile("src/client/LaneView.luau")
			assert(string.find(view, "CastShadow = false", 1, true), "LaneView parts cast shadows")
			assert(string.find(view, "LaneMarkings", 1, true), "LaneView ignores LaneMarkings")
			for _, banned in
				{
					"TweenService",
					"RenderStepped",
					"Heartbeat",
					"Transparency",
					"Brightness",
					"os.clock",
				}
			do
				assert(string.find(view, banned, 1, true) == nil, `LaneView animates ({banned})`)
			end
			local markings = fs.readFile("src/shared/LaneMarkings.luau")
			for _, literal in { "-10", "x = 10", "= -5", "x = 5" } do
				assert(
					string.find(markings, literal, 1, true) == nil,
					`LaneMarkings repeats a lane number ({literal})`
				)
			end
			local main = fs.readFile("src/client/Main.client.luau")
			assert(
				string.find(main, "laneView:update(drawnX, z)", 1, true),
				"Main never updates the lane marker"
			)
		end,
	},
}
