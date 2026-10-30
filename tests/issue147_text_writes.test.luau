--!strict
-- Issue #147 (choppy frame rate): per-frame TextLabel writes. A TextLabel relayouts its text on
-- every write, and ClusterView.update and SectionsView.update run every render frame. These three
-- labels were assigned on every frame even though their text almost never changes. Hud already
-- follows the rule "assign text only when it changes"; these cases pin the same rule. Source-text
-- checks, like issue171_road_flash: they fail on the unchanged code (no guard before the write).
local fs = require("@lune/fs")

local function source(path: string): string
	return fs.readFile(path)
end

return {
	{
		name = "issue 147: the cluster numeral and reward text are written only when they change",
		run = function()
			local text = source("src/client/ClusterView.luau")
			assert(
				string.find(text, "if g.numeral.Text ~= numeralText then", 1, true) ~= nil,
				"ClusterView writes g.numeral.Text every frame"
			)
			assert(
				string.find(text, "if g.reward.Text ~= rewardText then", 1, true) ~= nil,
				"ClusterView writes g.reward.Text every frame"
			)
		end,
	},
	{
		name = "issue 147: the cluster float text is written only when it changes",
		run = function()
			local text = source("src/client/ClusterView.luau")
			assert(
				string.find(text, "if item.text.Text ~= f.data.text then", 1, true) ~= nil,
				"ClusterView writes item.text.Text every frame"
			)
		end,
	},
	{
		name = "issue 147: the sections xN badge is written only when it changes",
		run = function()
			local text = source("src/client/SectionsView.luau")
			assert(
				string.find(text, "if rep.badge.Text ~= badgeText then", 1, true) ~= nil,
				"SectionsView writes rep.badge.Text every frame"
			)
		end,
	},
}
