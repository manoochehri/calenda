--!strict
-- Results screen content (spec s9, Amendment 1, issue #16). Pure. Score is the crowd total at the
-- end of the run; the session best counts completed runs only; a defeat shows no tier.
local RunFlow = require("./RunFlow")
local RunView = require("./RunView")
local Strings = require("./Strings")

export type Results = {
	outcome: string, -- "completed" | "defeated" | other
	title: string,
	scoreValue: number,
	bestValue: number,
	newBest: boolean,
	tier: number,
	score: string,
	best: string,
}

local Results = {}

-- The best after a run ends, and whether that run set it. Only a completed run can.
function Results.sessionBest(prevBest: number, outcome: string?, score: number): (number, boolean)
	if outcome == "completed" and score > prevBest then
		return score, true
	end
	return prevBest, false
end

function Results.build(state: any, flow: RunFlow.Flow): Results
	local outcome = if type(state.outcome) == "string" then state.outcome else "unknown"
	local scoreValue = RunView.wholeTotal(if state.score ~= nil then state.score else state.total)
	local serverBest = RunView.wholeTotal(state.best)
	local best, isNew = Results.sessionBest(flow.bestBefore, outcome, scoreValue)
	local bestValue = math.max(serverBest, if outcome == "completed" then best else 0)
	local newBest = isNew and flow.bestKnown
	local bestText = if newBest then Strings.newBest else ""
	return {
		outcome = outcome,
		title = RunView.hud(state).endTitle,
		scoreValue = scoreValue,
		bestValue = bestValue,
		newBest = newBest,
		tier = if outcome == "completed" then flow.tier else 0,
		score = string.format("%d", scoreValue),
		best = bestText,
	}
end

-- The HUD view with the end panel gated on the flow and its texts from `build`.
function Results.apply(view: RunView.Hud, state: any, flow: RunFlow.Flow): RunView.Hud
	local out = table.clone(view)
	out.showEnd = state.over == true and RunFlow.resultsVisible(flow)
	if out.showEnd then
		local r = Results.build(state, flow)
		out.endTitle = r.title
		out.score = r.score
		out.best = r.best
	end
	return out
end

return Results
