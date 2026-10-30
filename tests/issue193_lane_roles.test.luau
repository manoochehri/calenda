--!strict
-- Issue #193 (owner: "no lanes like mob control", lanes with distinct jobs). Fail-first: before the
-- change LaneGeometry.fit, LaneMarkings.roles/labelSpecs do not exist and a horde's figures wander
-- across lane lines. Roles come from the layout's authored data (cluster.lane, pickup.lane) read
-- through LaneGeometry; none is hard-coded per lane, because the spec (ADR 0010, Amendment 9)
-- assigns no fixed role to a lane.
local fs = require("@lune/fs")
local Config = require("../src/shared/Config")
local DebugLayout = require("../src/shared/DebugLayout")
local LaneGeometry = require("../src/shared/LaneGeometry")
local LaneMarkings = require("../src/shared/LaneMarkings")
local LayerHeights = require("../src/shared/LayerHeights")
local Layouts = require("../src/shared/Layouts")
local Scatter = require("../src/shared/SpectatorScatter")
local SpectatorMotion = require("../src/shared/SpectatorMotion")
local StreetSurface = require("../src/shared/StreetSurface")

local function eq(actual: any, expected: any, label: string)
	assert(actual == expected, `{label}: expected {tostring(expected)}, got {tostring(actual)}`)
end

return {
	{
		name = "issue 193: LaneGeometry.fit keeps a figure inside its authored lane band",
		run = function()
			-- right lane band is [5,15]; a 0.85 margin keeps the arms inside
			eq(LaneGeometry.fit(10, 2, 0.85), 5.85, "pushed in from the left edge")
			eq(LaneGeometry.fit(10, 18, 0.85), 14.15, "pushed in from the right edge")
			eq(LaneGeometry.fit(10, 11, 0.85), 11, "inside is untouched")
			eq(LaneGeometry.fit(-10, -2, 0.85), -5.85, "left lane inner edge")
			eq(LaneGeometry.fit(0, 9, 0.85), 4.15, "centre lane")
			eq(LaneGeometry.fit(30, 30, 0.85), 30, "off the street: unchanged")
		end,
	},
	{
		name = "issue 193: every horde figure stays in its own lane over its whole approach",
		run = function()
			local p = Config.spectators.scatter
			local half = p.armsWidth / 2
			for _, origin in { -10, 10 } do
				local lane = LaneGeometry.laneOf(origin) :: LaneGeometry.Lane
				local lo, hi = origin - 5, origin + 5
				for _, count in { 10, 30, 40 } do
					for cluster = 1, 6 do
						local offsets = Scatter.place(count, 7 + cluster * 1009, p)
						for i = 1, count do
							local path = SpectatorMotion.plan(
								7,
								cluster,
								i,
								origin,
								1500,
								0,
								Config.speed,
								Config.spectators.approachSpeed,
								offsets[i],
								p
							)
							for age = 0, 12, 0.25 do
								local pos = SpectatorMotion.position(path, age, 0)
								assert(
									pos.x - half >= lo - 1e-6 and pos.x + half <= hi + 1e-6,
									`{lane} cluster {cluster} person {i} age {age}: x={pos.x} leaves [{lo},{hi}]`
								)
							end
						end
					end
				end
			end
		end,
	},
	{
		name = "issue 193: roles are read from the layout's authored lanes, not fixed per lane",
		run = function()
			local roles = LaneMarkings.roles(DebugLayout)
			assert(
				roles.left.horde and roles.right.horde,
				"the played level's outer lanes hold hordes"
			)
			assert(not roles.center.horde and not roles.center.pickup, "centre holds neither today")
			local custom = {
				clusters = { { lane = "center" } },
				pickups = { { id = 1, z = 100, lane = "left" } },
			}
			local r = LaneMarkings.roles(custom :: any)
			assert(r.center.horde and not r.left.horde and not r.right.horde, "horde follows data")
			assert(r.left.pickup and not r.center.pickup, "pickup follows data")
			eq(LaneMarkings.roleText(r.left), "+1 PEOPLE", "pickup text")
			eq(LaneMarkings.roleText(r.center), "SHOOT HORDE", "horde text")
			eq(LaneMarkings.roleText(r.right), "", "empty lane has no role text")
		end,
	},
	{
		name = "issue 193: every lane has a painted text label at its LaneGeometry centre, on the road, tied to its role",
		run = function()
			local labels = LaneMarkings.labelSpecs(DebugLayout)
			local roles = LaneMarkings.roles(DebugLayout)
			local road = StreetSurface.roadHalfWidth(DebugLayout.halfWidth)
			for _, lane in LaneMarkings.lanes do
				local count = 0
				for _, l in labels do
					if l.lane == lane then
						count += 1
						eq(l.x, LaneGeometry.centerOf(lane :: LaneGeometry.Lane), `{l.name} x`)
						assert(
							l.x - l.sx / 2 >= -road and l.x + l.sx / 2 <= road,
							`{l.name} off road`
						)
						assert(
							string.find(l.text, string.upper(lane), 1, true) == 1,
							`{l.name} text {l.text} does not name the lane`
						)
						local role = LaneMarkings.roleText((roles :: any)[lane])
						assert(
							role == "" or string.find(l.text, role, 1, true),
							`{l.name} text {l.text} omits role {role}`
						)
						assert(
							l.z - l.sz / 2 >= (DebugLayout.startPlazaEnd or 0)
								and l.z + l.sz / 2 <= DebugLayout.plazaStart,
							`{l.name} off the street`
						)
					end
				end
				assert(count >= 3, `lane {lane} has only {count} labels`)
			end
		end,
	},
	{
		name = "issue 193: lane labels do not overlap arrows, dividers, dashes, gates or obstacles",
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
			for _, s in LaneMarkings.specs(DebugLayout) do
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
			for _, l in LaneMarkings.labelSpecs(DebugLayout) do
				table.insert(list, {
					name = l.name,
					top = l.top,
					x0 = l.x - l.sx / 2,
					x1 = l.x + l.sx / 2,
					z0 = l.z - l.sz / 2,
					z1 = l.z + l.sz / 2,
				})
			end
			local conflicts = LayerHeights.conflicts(list)
			assert(#conflicts == 0, `z-fight risks: {table.concat(conflicts, "; ")}`)
			for _, l in LaneMarkings.labelSpecs(DebugLayout) do
				for _, g in DebugLayout.gates do
					assert(math.abs(l.z - g.z) > l.sz / 2 + 4, `{l.name} sits on a gate line`)
				end
				for _, o in DebugLayout.obstacles do
					assert(math.abs(l.z - o.z) > l.sz / 2 + 4, `{l.name} sits on an obstacle line`)
				end
			end
		end,
	},
	{
		name = "issue 193: every authored cluster's lane has a horde role, in the played and the seeded layouts",
		run = function()
			for _, layout in { DebugLayout, Layouts.select(1) } do
				local roles = LaneMarkings.roles(layout)
				for _, c in layout.clusters do
					assert(
						(roles :: any)[c.lane].horde,
						`cluster {c.id} lane {c.lane} has no horde role`
					)
				end
			end
		end,
	},
	{
		name = "issue 193: LaneView draws the labels as text on a SurfaceGui from labelSpecs",
		run = function()
			local view = fs.readFile("src/client/LaneView.luau")
			assert(string.find(view, "labelSpecs", 1, true), "LaneView ignores labelSpecs")
			assert(string.find(view, "SurfaceGui", 1, true), "LaneView draws no text")
		end,
	},
}
