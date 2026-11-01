--!strict
-- Issue #257: the played level's first two gates are retimed (gate 1 about 13 s, gate 2 at the
-- late edge of the spec s9 early window) and a lane arrow row that a gate line lands on is nudged
-- clear of the line instead of dropped, so the lane-arrow count (issue 193) does not depend on
-- where a gate sits. The gate VALUES are a fit to headless witness runs, not a test; this file pins
-- the timing and the arrow behaviour only.
local Config = require("../src/shared/Config")
local DebugLayout = require("../src/shared/DebugLayout")
local LaneMarkings = require("../src/shared/LaneMarkings")
local Level = require("../src/shared/Level")

local function arrowCounts(layout: any): { [string]: number }
	local counts = { left = 0, center = 0, right = 0 }
	for _, s in LaneMarkings.specs(layout) do
		if s.kind == "arrow" then
			counts[s.lane :: string] += 1
		end
	end
	return counts
end

return {
	{
		name = "arrows: a gate on an arrow row nudges the row, so no lane loses an arrow",
		run = function()
			local free = table.clone(DebugLayout) :: any
			free.gates = {}
			free.obstacles = {}
			local blocked = table.clone(free)
			-- z = 96 is an arrow row (a multiple of 48 that is not a centre-line dash row).
			blocked.gates = {
				{
					id = 1,
					z = 96,
					left = { kind = "add", value = 1 },
					right = { kind = "add", value = 1 },
				},
			}
			local a, b = arrowCounts(free), arrowCounts(blocked)
			for _, lane in { "left", "center", "right" } do
				assert(
					a[lane] == b[lane],
					`{lane}: {b[lane]} arrows with a gate on a row, {a[lane]} without`
				)
			end
			for _, s in LaneMarkings.specs(blocked) do
				if s.kind == "arrow" then
					assert(
						math.abs(s.z - 96) >= LaneMarkings.CLEARANCE + LaneMarkings.ARROW_LENGTH / 2,
						`{s.name} sits on the gate line`
					)
				end
			end
		end,
	},
	{
		name = "played level: gate 1 about 13 s, gate 2 inside the early window and after 24 s",
		run = function()
			local t1 = Level.timeAtZ(DebugLayout.gates[1].z, Config)
			local t2 = Level.timeAtZ(DebugLayout.gates[2].z, Config)
			assert(t1 >= 12.5 and t1 <= 13.5, `gate 1 at {t1} s`)
			assert(t2 >= 24 and t2 <= 25, `gate 2 at {t2} s`)
		end,
	},
}
