--!strict
local DebugLayout = require("../src/shared/DebugLayout")

local function eq(actual: any, expected: any, label: string)
	assert(actual == expected, `{label}: expected {tostring(expected)}, got {tostring(actual)}`)
end

return {
	{
		name = "the route begins in a plaza and reaches the separate finale plaza at the existing 90 second timing",
		run = function()
			assert(
				DebugLayout.startPlazaEnd > 0,
				"starting plaza must be part of the authored route"
			)
			assert(
				DebugLayout.startPlazaEnd < DebugLayout.plazaStart,
				"street follows starting plaza"
			)
			assert(
				DebugLayout.plazaStart < DebugLayout.streetLength,
				"ending plaza remains distinct"
			)
			eq(DebugLayout.plazaStart / require("../src/shared/Config").speed, 90, "route timing")
		end,
	},
}
