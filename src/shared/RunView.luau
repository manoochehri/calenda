--!strict
-- Pure view helpers over the replicated State payload (issues #10, #13). The client renders the
-- end of a run from `over`/`outcome` in State, not only from Event: State repeats at 10 Hz, so a
-- listener that connects late still recovers the end (PR #42 review note on issue #10).
local Remotes = require("./Remotes")
local Strings = require("./Strings")

export type Hud = {
	showEnd: boolean,
	endTitle: string,
	score: string,
	best: string,
}

local RunView = {}

RunView.MAX_EXTRAPOLATION = 0.35 -- [default] seconds of dead reckoning past the last State

function RunView.wholeTotal(v: any): number
	if type(v) ~= "number" or v ~= v or v < 0 or v == math.huge then
		return 0
	end
	return math.floor(v)
end

function RunView.hud(state: Remotes.StatePayload): Hud
	local total = RunView.wholeTotal(state.total)
	local title = Strings.ended
	if state.outcome == "completed" then
		title = Strings.completed
	elseif state.outcome == "defeated" then
		title = Strings.defeated
	end
	return {
		showEnd = state.over == true,
		endTitle = title,
		score = string.format("%d", RunView.wholeTotal(state.score or total)),
		best = "",
	}
end

-- Dead-reckons the lead between 10 Hz States: z and t advance at `speed` for at most
-- MAX_EXTRAPOLATION seconds, never past `maxZ`, and not at all once the run is over.
function RunView.leadPosition(
	state: Remotes.StatePayload,
	secondsSinceState: number,
	speed: number,
	maxZ: number
): (number, number, number)
	if state.over then
		return state.x, state.z, state.t
	end
	local dt = math.clamp(secondsSinceState, 0, RunView.MAX_EXTRAPOLATION)
	-- Issue #162: a fight stops forward travel; time and lateral motion go on. The hold plane stops
	-- the extrapolation before a stop the client has not been told about yet.
	if Remotes.isStage(state.stage) and state.stage ~= "traveling" then
		return state.x, state.z, state.t + dt
	end
	local z = math.min(maxZ, state.z + speed * dt)
	if type(state.holdZ) == "number" then
		z = math.min(z, math.max(state.holdZ, state.z))
	end
	return state.x, z, state.t + dt
end

-- Run time only goes forward inside a run; going backwards means the server replayed.
function RunView.isNewRun(previousT: number?, t: number): boolean
	return previousT == nil or t < previousT
end

return RunView
