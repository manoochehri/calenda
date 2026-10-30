-- Issue #191: Rey is removed from gameplay visuals and its dedicated formation module.
-- This source-level regression guards the visual-only actor, which is built directly with Roblox
-- Parts and cannot be instantiated by Lune. General follower and section behavior has its own suites.
local fs = require("@lune/fs")

return {
	{
		name = "issue 191: CrowdView no longer builds or draws Rey",
		run = function()
			local crowdView = fs.readFile("src/client/CrowdView.luau")
			assert(
				string.find(crowdView, "Rey", 1, true) == nil,
				"CrowdView still contains a Rey rendering path"
			)
		end,
	},
	{
		name = "issue 191: Rey-specific formation module is removed",
		run = function()
			local exists = pcall(function()
				fs.readFile("src/shared/ReyFormation.luau")
			end)
			assert(not exists, "ReyFormation is still present")
		end,
	},
}
