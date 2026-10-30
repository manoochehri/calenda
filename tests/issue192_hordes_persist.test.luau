--!strict
-- Issue #192: "the hordes just disappear". The level that is actually played (DebugLayout, wired in
-- RunServer and Main.client) stopped authoring waves at pair 10, 32.5 s into a 90 s run, so no horde
-- was on screen or reached the parade for the last minute. Issue #142 fixed the rhythm in Layouts only.
local ClusterVisual = require("../src/shared/ClusterVisual")
local Config = require("../src/shared/Config")
local DebugLayout = require("../src/shared/DebugLayout")
local Level = require("../src/shared/Level")

local function plazaSeconds(): number
	return DebugLayout.plazaStart / Config.speed
end

return {
	{
		name = "the played level keeps a wave arriving until just before the plaza",
		run = function()
			local closing = Config.speed + Config.spectators.approachSpeed
			local last = 0
			for _, c in DebugLayout.clusters do
				local arrive = (c.spawn.z + Config.spectators.approachSpeed * c.spawnTime) / closing
				last = math.max(last, arrive)
			end
			local plaza = plazaSeconds()
			assert(last >= plaza - 6, `last wave meets the lead at {last} s of a {plaza} s run`)
			assert(
				last <= plaza,
				`last wave meets the lead at {last} s, after the plaza at {plaza} s`
			)
		end,
	},
	{
		name = "hordes are drawn in every 10 s window of the run (headless frames at 30 Hz)",
		run = function()
			local tracker = ClusterVisual.new(DebugLayout)
			local plaza = plazaSeconds()
			local window = 10
			local seenIn: { [number]: number } = {}
			local frames = 0
			local dt = 1 / 30
			local t = 0
			while t < plaza - 4 do
				local views = tracker:views(t, 0, Level.leadZ(t))
				frames += 1
				if #views > 0 then
					local w = math.floor(t / window)
					seenIn[w] = (seenIn[w] or 0) + 1
				end
				t += dt
			end
			assert(frames > 0, "no frames sampled")
			for w = 1, math.floor((plaza - 4) / window) - 1 do
				assert(
					(seenIn[w] or 0) > 0,
					`no horde drawn between {w * window} s and {(w + 1) * window} s`
				)
			end
		end,
	},
}
