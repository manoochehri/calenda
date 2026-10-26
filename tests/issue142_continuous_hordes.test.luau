--!strict
-- Issue #142: authored spectator waves must continue through the late route, leaving no-input
-- runs defeated while a competent scripted run can still reach the plaza.
local Config = require("../src/shared/Config")
local Layouts = require("../src/shared/Layouts")
local Level = require("../src/shared/Level")
local BotHarness = require("./helpers/BotHarness")

local MAX_WAVE_GAP = 3

-- Tick rates the outcome checks run at. The defeat and completion claims must hold at all three,
-- not only the 30 Hz server tick. Each (layout, policy, rate) is one deterministic run (n=1).
local TICK_RATES = { 20, 30, 60 }

-- "Competent" means the scripted policy in tests/helpers/BotHarness.luau: it steers to the side
-- of the nearest large cluster (else nearest cluster ahead) and takes the gate preference, so it
-- engages the hordes on the matching side and completes the layout. It is the reference
-- competent player for these checks; it is not a measure of skill or of the best possible run.
local NO_INPUT = "none"
local COMPETENT = "scripted"

local function impactTime(cluster: Level.Cluster): number
	-- Layouts use straight approaches. At impact, the mob's z equals the lead's z.
	return (cluster.spawn.z + Config.spectators.approachSpeed * cluster.spawnTime)
		/ (Config.speed + Config.spectators.approachSpeed)
end

local function uniqueImpactTimes(layout: Level.Layout): { number }
	local times: { number } = {}
	for _, cluster in layout.clusters do
		local t = impactTime(cluster)
		local found = false
		for _, existing in times do
			if math.abs(existing - t) < 1e-6 then
				found = true
				break
			end
		end
		if not found then
			table.insert(times, t)
		end
	end
	table.sort(times)
	return times
end

return {
	{
		name = "each playable layout keeps horde arrivals on a steady cadence through the plaza",
		run = function()
			for _, layout in Layouts.all do
				local arrivals = uniqueImpactTimes(layout)
				local plazaTime = Level.timeAtZ(layout.plazaStart)
				assert(#arrivals > 0, `{layout.name}: no spectator arrivals`)
				for i = 2, #arrivals do
					local gap = arrivals[i] - arrivals[i - 1]
					assert(gap <= MAX_WAVE_GAP, `{layout.name}: horde arrival gap {gap} seconds`)
				end
				local finalGap = plazaTime - arrivals[#arrivals]
				assert(
					finalGap >= 0 and finalGap <= MAX_WAVE_GAP,
					`{layout.name}: final horde arrives {finalGap} seconds before the plaza`
				)
			end
		end,
	},
	{
		name = "a no-input run is defeated before the plaza on every playable layout at 20, 30 and 60 Hz",
		run = function()
			for _, hz in TICK_RATES do
				for _, layout in Layouts.all do
					local result =
						BotHarness.play(layout, BotHarness.policy(NO_INPUT, 1), { hz = hz })
					assert(
						result.outcome == "defeated",
						`{layout.name} @{hz} Hz: outcome={tostring(result.outcome)} time={result.time} total={result.total} attacks={#result.attacks}`
					)
					assert(
						result.time < Level.timeAtZ(layout.plazaStart),
						`{layout.name} @{hz} Hz: defeat was not before the plaza`
					)
				end
			end
		end,
	},
	{
		name = "a competent scripted run completes on every playable layout at 20, 30 and 60 Hz",
		run = function()
			for _, hz in TICK_RATES do
				for _, layout in Layouts.all do
					local result =
						BotHarness.play(layout, BotHarness.policy(COMPETENT, 1), { hz = hz })
					assert(
						result.outcome == "completed",
						`{layout.name} @{hz} Hz: outcome={tostring(result.outcome)} time={result.time} total={result.total} attacks={#result.attacks}`
					)
				end
			end
		end,
	},
}
