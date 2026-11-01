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
	{
		name = "issue 147: crowd follower parts move through one BulkMoveTo batch",
		run = function()
			local text = source("src/client/CrowdView.luau")
			assert(
				string.find(text, "Workspace:BulkMoveTo(parts, cframes", 1, true) ~= nil,
				"CrowdView moves follower parts individually"
			)
			assert(
				string.find(text, "moveBatch:push(instance, cf)", 1, true) ~= nil,
				"CrowdView does not collect follower parts for batching"
			)
		end,
	},
	{
		name = "issue 147: move batch sends all queued parts once and resets after flush",
		run = function()
			local MoveBatch = require("../src/shared/MoveBatch")
			local calls = 0
			local sentParts = {}
			local sentFrames = {}
			local batch = MoveBatch.new(function(parts, frames)
				calls += 1
				sentParts, sentFrames = parts, frames
			end)
			local a, b = {}, {}
			batch:push(a, 10)
			batch:push(b, 20)
			assert(batch:flush() == 2, "flush reports both queued moves")
			assert(calls == 1, "flush sends one batch")
			assert(sentParts[1] == a and sentParts[2] == b, "parts keep queue order")
			assert(sentFrames[1] == 10 and sentFrames[2] == 20, "frames keep queue order")
			assert(batch:flush() == 0 and calls == 1, "empty flush sends nothing")
		end,
	},
}
