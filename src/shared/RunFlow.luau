--!strict
-- The client's view of how a run ends (spec s9, Amendment 1, issue #16). Pure. It is driven only
-- by the replicated State (`over`, `outcome`, `score`), so a client that connects late still plays
-- the right ending:
--   running -> finale  -> results   (completed; the tier comes from the final total)
--   running -> breakup -> results   (defeated; never a finale, never a tier)
--   running -> results              (any outcome this client does not know)
local Celebration = require("./Celebration")
local DefeatPlan = require("./DefeatPlan")
local FinalePlan = require("./FinalePlan")
local RunView = require("./RunView")
local Strings = require("./Strings")

export type Flow = {
	phase: string, -- "running" | "finale" | "breakup" | "results"
	elapsed: number, -- seconds inside the finale / breakup
	outcome: string?,
	tier: number, -- celebration tier; 0 unless the run completed
	score: number?,
	bestBefore: number, -- session best seen while the run was still going
	bestKnown: boolean, -- false when this client first saw the run already over
}

local RunFlow = {}

local function fresh(flow: Flow)
	flow.phase = "running"
	flow.elapsed = 0
	flow.outcome = nil
	flow.tier = 0
	flow.score = nil
	flow.bestBefore = 0
	flow.bestKnown = false
end

function RunFlow.new(): Flow
	local flow = {} :: Flow
	fresh(flow)
	return flow
end

-- Back to a fresh run (the replay checklist's "flow" item).
function RunFlow.reset(flow: Flow)
	fresh(flow)
end

-- Advances by `dt` seconds with the latest State. Returns the new phase when it changed.
function RunFlow.step(flow: Flow, state: any, dt: number): string?
	if state.over ~= true then
		local changed = flow.phase ~= "running"
		if changed then
			fresh(flow) -- the server started a new run under us
		end
		flow.bestBefore = RunView.wholeTotal(state.best)
		flow.bestKnown = true
		return if changed then "running" else nil
	end

	if flow.phase == "running" then
		flow.outcome = if type(state.outcome) == "string" then state.outcome else "unknown"
		flow.score = RunView.wholeTotal(if state.score ~= nil then state.score else state.total)
		flow.elapsed = 0
		if flow.outcome == "completed" then
			flow.phase = "finale"
			flow.tier = Celebration.tierFor(flow.score)
		elseif flow.outcome == "defeated" then
			flow.phase = "breakup"
			flow.tier = 0
		else
			flow.phase = "results"
			flow.tier = 0
		end
		return flow.phase
	end

	if flow.phase == "finale" or flow.phase == "breakup" then
		flow.elapsed += math.max(0, dt)
		local length = if flow.phase == "finale" then FinalePlan.DURATION else DefeatPlan.DURATION
		if flow.elapsed >= length then
			flow.phase = "results"
			return "results"
		end
	end
	return nil
end

function RunFlow.resultsVisible(flow: Flow): boolean
	return flow.phase == "results"
end

-- The big banner text during the end beat, or nil.
function RunFlow.banner(flow: Flow): string?
	if flow.phase == "finale" then
		return Celebration.banner(flow.tier)
	elseif flow.phase == "breakup" then
		return Strings.defeated
	end
	return nil
end

return RunFlow
