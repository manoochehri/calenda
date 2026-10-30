--!strict
-- Issue #193: the street must show which lane is which and keep display hordes within their
-- authored server lane. These regressions are added before implementation so the unchanged code
-- demonstrates both missing role labels and cross-lane figure placement.
local fs = require("@lune/fs")
local Config = require("../src/shared/Config")
local DebugLayout = require("../src/shared/DebugLayout")
local LaneGeometry = require("../src/shared/LaneGeometry")
local LaneMarkings = require("../src/shared/LaneMarkings")
local Motion = require("../src/shared/SpectatorMotion")
local Scatter = require("../src/shared/SpectatorScatter")

local lanes: { LaneGeometry.Lane } = { "left", "center", "right" }

local function bounds(lane: LaneGeometry.Lane): (number, number)
	return (LaneGeometry :: any).bounds(lane)
end

local function eq(actual: any, expected: any, label: string)
	assert(actual == expected, `{label}: expected {tostring(expected)}, got {tostring(actual)}`)
end

return {
	{
		name = "issue 193: every lane gets a text and glyph role label at the server lane centre",
		run = function()
			local fixture = table.clone(DebugLayout)
			fixture.clusters = {
				{ lane = "left" },
				{ lane = "right" },
			}
			fixture.pickups = { { lane = "center" } }
			local labels = (LaneMarkings :: any).labelSpecs(fixture)
			assert(type(labels) == "table" and #labels >= 3, "three lane role labels are missing")
			local firstZ = math.huge
			for _, spec in labels do
				firstZ = math.min(firstZ, spec.z)
			end
			local seen: { [string]: any } = {}
			for _, spec in labels do
				if spec.z == firstZ then
					seen[spec.lane] = spec
					eq(spec.x, LaneGeometry.centerOf(spec.lane), `{spec.lane} label centre`)
					assert(spec.directionText ~= "", `{spec.lane} direction text is empty`)
					assert(spec.glyph ~= "", `{spec.lane} direction glyph is empty`)
					assert(spec.roleText ~= "", `{spec.lane} role text is empty`)
				end
			end
			assert(
				seen.left ~= nil and seen.center ~= nil and seen.right ~= nil,
				"labels do not cover all lanes"
			)
			assert(
				string.find(seen.left.roleText, "HORDAS", 1, true),
				"left label hides its horde role"
			)
			assert(
				string.find(seen.center.roleText, "+1", 1, true),
				"center label hides its +1 role"
			)
			assert(
				string.find(seen.right.roleText, "HORDAS", 1, true),
				"right label hides its horde role"
			)
		end,
	},
	{
		name = "issue 193: the visible lane labels are rendered as text, not colour-only markers",
		run = function()
			local view = fs.readFile("src/client/LaneView.luau")
			assert(string.find(view, "labelSpecs", 1, true), "LaneView does not render role labels")
			assert(
				string.find(view, "directionText", 1, true),
				"LaneView omits lane direction text"
			)
			assert(string.find(view, "roleText", 1, true), "LaneView omits lane role text")
			assert(string.find(view, "TextLabel", 1, true), "lane labels have no readable text")
			assert(
				string.find(view, "AlwaysOnTop", 1, true),
				"lane text can disappear behind figures"
			)
		end,
	},
	{
		name = "issue 193: each walking horde and full-size figure stays inside its authored lane",
		run = function()
			local p = Config.spectators.scatter
			local figureHalf = math.max(p.bodyWidth, p.armsWidth) * p.maxScale / 2
			for laneIndex, lane in lanes do
				local lo, hi = bounds(lane)
				local maxScatter = (LaneGeometry :: any).maxScatterHalfWidth(lane, figureHalf)
				assert(maxScatter > 0, `{lane}: no usable scatter width`)
				local laneScatter = table.clone(p)
				laneScatter.spreadHalfWidth = math.min(p.spreadHalfWidth, maxScatter)
				local offsets = Scatter.place(24, 431 + laneIndex, laneScatter)
				for person, offset in offsets do
					local path = Motion.plan(
						431,
						laneIndex,
						person,
						LaneGeometry.centerOf(lane),
						500,
						0,
						Config.speed,
						Config.spectators.approachSpeed,
						offset,
						laneScatter,
						lane,
						figureHalf
					)
					for _, age in { 0, 0.5, 1, 3, 6, 10 } do
						local pos = Motion.position(path, age, Config.speed * age)
						assert(
							pos.x - figureHalf >= lo - 1e-6 and pos.x + figureHalf <= hi + 1e-6,
							`{lane} person {person} crosses lane boundary at age {age}: x={pos.x}`
						)
					end
				end
			end
		end,
	},
}
