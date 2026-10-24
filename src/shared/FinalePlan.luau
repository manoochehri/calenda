--!strict
-- The plaza finale timeline (spec s2, s9, issue #16). Pure: time in, parameters out; the client
-- draws them. 9 s total: the party spreads across the plaza, then gifts and confetti, then a
-- music peak. The music value is an intensity 0..1 for a placeholder hook; no asset IDs exist.
local Beats = require("./Beats")
local Celebration = require("./Celebration")

export type Frame = {
	phase: string, -- "spread" | "party" | "peak" | "done"
	spread: number, -- 0 together at the lead .. 1 spread across the plaza
	musicIntensity: number, -- 0..1
	cameraPullback: number, -- multiplier on the camera distance, 1 or more
	done: boolean,
}

local FinalePlan = {}

FinalePlan.DURATION = 9 -- [default] seconds; spec s2 asks for 8-10
FinalePlan.SPREAD_END = 3 -- [default]
FinalePlan.PARTY_END = 7 -- [default]
FinalePlan.EXTRA_PULLBACK = 0.5 -- [default] camera pulls back by up to +50% to show the plaza

local function smooth(t: number): number
	local c = math.clamp(t, 0, 1)
	return c * c * (3 - 2 * c)
end

function FinalePlan.at(elapsed: number): Frame
	local t = math.max(0, elapsed)
	local phase = "spread"
	if t >= FinalePlan.DURATION then
		phase = "done"
	elseif t >= FinalePlan.PARTY_END then
		phase = "peak"
	elseif t >= FinalePlan.SPREAD_END then
		phase = "party"
	end
	local spread = smooth(t / FinalePlan.SPREAD_END)
	return {
		phase = phase,
		spread = spread,
		musicIntensity = if phase == "peak" or phase == "done"
			then 1
			else 0.5 + 0.5 * math.clamp(t / FinalePlan.PARTY_END, 0, 1),
		cameraPullback = 1 + FinalePlan.EXTRA_PULLBACK * spread,
		done = phase == "done",
	}
end

-- Where party member i of n ends up, relative to the lead, on a plaza `halfWidth` wide and `depth`
-- deep ahead of it: a sunflower spread that stays inside the plaza and never overlaps two slots.
function FinalePlan.slot(i: number, n: number, halfWidth: number, depth: number): (number, number)
	local r = math.sqrt((i - 0.5) / math.max(1, n))
	local a = i * 2.399963 -- golden angle
	local dx = math.cos(a) * r * (halfWidth - 2)
	local dz = 6 + (math.sin(a) * r * 0.5 + 0.5) * (depth - 6)
	return dx, dz
end

function FinalePlan.burstTimes(tier: number): { number }
	return Beats.evenly(Celebration.profile(tier).bursts, 0.5, FinalePlan.DURATION - 1)
end

function FinalePlan.giftTimes(tier: number): { number }
	return Beats.evenly(Celebration.profile(tier).gifts, 1.5, FinalePlan.PARTY_END + 0.5)
end

-- How many confetti bursts and gift tosses to start in the window (prev, now].
function FinalePlan.due(prev: number, now: number, tier: number): { bursts: number, gifts: number }
	return {
		bursts = Beats.countIn(FinalePlan.burstTimes(tier), prev, now),
		gifts = Beats.countIn(FinalePlan.giftTimes(tier), prev, now),
	}
end

return FinalePlan
