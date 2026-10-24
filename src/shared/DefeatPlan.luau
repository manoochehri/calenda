--!strict
-- The playful party breakup after a defeat (Amendment 1, issue #16). Pure. A short beat: the
-- parade stops, the musicians tumble and land upright, hats and instruments fly, confetti pops,
-- then the followers wander off laughing. Never a death or destruction animation, and never a
-- finale or celebration tier (the results screen follows; RunFlow keeps the tier at 0).
local Beats = require("./Beats")

export type Frame = {
	phase: string, -- "stop" | "breakup" | "wander" | "done"
	paradeStopped: boolean,
	tumble: number, -- radians of roll for the lead; a whole number of turns at the end
	lift: number, -- studs the lead hops during the tumble, never below 0
	wander: number, -- 0..1 how far the followers have strolled away
	bannerVisible: boolean,
	done: boolean,
}

local DefeatPlan = {}

DefeatPlan.DURATION = 3 -- [default] seconds; the spec asks for a short beat
DefeatPlan.STOP_END = 0.5 -- [default]
DefeatPlan.BREAKUP_END = 2 -- [default]
DefeatPlan.TURNS = 2 -- [default] whole somersaults, so the lead lands standing
DefeatPlan.HATS = 6 -- [default]
DefeatPlan.INSTRUMENTS = 5 -- [default]

local BURST_TIMES = { 0.5, 1.0, 1.5 } -- [default]
local LAUGH_TIMES = { 2.0, 2.3, 2.6 } -- [default]

function DefeatPlan.at(elapsed: number): Frame
	local t = math.max(0, elapsed)
	local phase = "stop"
	if t >= DefeatPlan.DURATION then
		phase = "done"
	elseif t >= DefeatPlan.BREAKUP_END then
		phase = "wander"
	elseif t >= DefeatPlan.STOP_END then
		phase = "breakup"
	end
	local tumble, lift = 0, 0
	if t >= DefeatPlan.STOP_END then
		local p = math.clamp(
			(t - DefeatPlan.STOP_END) / (DefeatPlan.BREAKUP_END - DefeatPlan.STOP_END),
			0,
			1
		)
		local eased = 1 - (1 - p) * (1 - p)
		tumble = DefeatPlan.TURNS * 2 * math.pi * eased
		lift = math.sin(math.pi * p) * 3
	end
	return {
		phase = phase,
		paradeStopped = true,
		tumble = tumble,
		lift = math.max(0, lift),
		wander = math.clamp(
			(t - DefeatPlan.BREAKUP_END) / (DefeatPlan.DURATION - DefeatPlan.BREAKUP_END),
			0,
			1
		),
		bannerVisible = true,
		done = phase == "done",
	}
end

export type Due = { hats: number, instruments: number, bursts: number, laughs: number }

-- What to start in the window (prev, now]: the flying hats and instruments all launch together
-- as the tumble begins.
function DefeatPlan.due(prev: number, now: number): Due
	local launched = Beats.countIn({ DefeatPlan.STOP_END }, prev, now)
	return {
		hats = launched * DefeatPlan.HATS,
		instruments = launched * DefeatPlan.INSTRUMENTS,
		bursts = Beats.countIn(BURST_TIMES, prev, now),
		laughs = Beats.countIn(LAUGH_TIMES, prev, now),
	}
end

return DefeatPlan
