--!strict
-- Issue #222: the solid dark lane-label rectangles painted on the road (LaneView.buildLabel)
-- were an unexplained placeholder look. The role text stays; the opaque plate and label
-- backing go. Config.debug.legacyLaneLabelPlates is the one-flip switch to bring them back.
local Config = require("../src/shared/Config")
local LaneMarkings = require("../src/shared/LaneMarkings")
local fs = require("@lune/fs")

local function eq(a: any, b: any, msg: string)
	assert(a == b, `{msg}: expected {tostring(b)}, got {tostring(a)}`)
end

return {
	{
		name = "issue 222: legacyLaneLabelPlates defaults false and validates as a boolean",
		run = function()
			eq((Config.debug :: any).legacyLaneLabelPlates, false, "default")
			local copy: any = table.clone(Config)
			copy.debug = table.clone(Config.debug)
			copy.debug.legacyLaneLabelPlates = 1
			eq((Config.validate(copy)), false, "must be validated as boolean")
		end,
	},
	{
		name = "issue 222: lane label backing is fully transparent unless the legacy switch is on",
		run = function()
			eq((LaneMarkings :: any).labelBackingTransparency(false), 1, "normal game")
			eq((LaneMarkings :: any).labelBackingTransparency(true), 0, "legacy plates")
		end,
	},
	{
		name = "issue 222: LaneView draws no opaque dark plate behind lane labels",
		run = function()
			local view = fs.readFile("src/client/LaneView.luau")
			assert(
				not string.find(view, "Color3.fromRGB(30, 32, 36)", 1, true),
				"LaneView still hard-codes the dark label plate colour"
			)
			assert(
				string.find(view, "labelBackingTransparency", 1, true),
				"LaneView does not route the plate through the debug switch"
			)
			assert(
				string.find(view, "legacyLaneLabelPlates", 1, true),
				"LaneView ignores Config.debug.legacyLaneLabelPlates"
			)
		end,
	},
}
