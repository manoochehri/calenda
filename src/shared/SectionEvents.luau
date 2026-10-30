--!strict
-- Pure event-to-animation planning for section thresholds (issue #14, spec s5, s7, s8).
-- Given the crowd total before and after a change it says what the client should play:
-- ONE combined celebration however many thresholds were crossed, or a quiet dispersal of the
-- newest sections on a drop (no destruction animation),
-- plus which section representatives appear, vanish or change their xN stack count.
local Config = require("./Config")
local CrowdMath = require("./CrowdMath")
local VisualBudget = require("./VisualBudget")

export type RepChange = {
	index: number,
	sectionType: CrowdMath.SectionType,
	fromCount: number,
	toCount: number,
	showBadge: boolean, -- badge visible after the change
}
export type RepDiff = {
	appeared: { VisualBudget.Representative },
	removed: { number }, -- representative indices, newest first
	changed: { RepChange },
}
export type Kind = "none" | "celebrate" | "disperse"
export type Plan = {
	kind: Kind,
	from: number,
	to: number,
	count: number,
	sections: { number },
	types: { CrowdMath.SectionType },
	duration: number,
	reps: RepDiff,
}
export type Phases = { swirl: number, confetti: number, rise: number }

local SectionEvents = {}

SectionEvents.SWIRL_PIVOT_DZ = -9 -- [default] studs behind the lead: where the crowd swirls to
local SWIRL_RADIANS = math.pi * 1.2 -- [default] turn of the loose crowd at peak swirl
local SWIRL_PULL = 0.55 -- [default] fraction of the distance to the pivot closed at peak swirl

-- Window fractions of the celebration [default]; the whole thing lasts Config.durations.assemblySeconds.
local SWIRL_END = 0.4
local CONFETTI_START = 0.15
local CONFETTI_PEAK = 0.4
local CONFETTI_END = 0.8
local RISE_START = 0.2

function SectionEvents.repDiff(from: number, to: number): RepDiff
	local before = VisualBudget.allocate(from).representatives
	local after = VisualBudget.allocate(to).representatives
	local diff: RepDiff = { appeared = {}, removed = {}, changed = {} }
	for i = 1, math.max(#before, #after) do
		local b, a = before[i], after[i]
		if b == nil and a ~= nil then
			table.insert(diff.appeared, a)
		elseif a == nil and b ~= nil then
			table.insert(diff.removed, 1, i) -- newest first
		elseif a ~= nil and b ~= nil and a.count ~= b.count then
			table.insert(diff.changed, {
				index = i,
				sectionType = a.sectionType,
				fromCount = b.count,
				toCount = a.count,
				showBadge = a.showBadge,
			})
		end
	end
	return diff
end

function SectionEvents.plan(from: number, to: number): Plan
	local c = CrowdMath.crossings(from, to)
	local kind: Kind = "none"
	local duration = 0
	if c.direction == "up" then
		kind = "celebrate"
		duration = Config.durations.assemblySeconds
	elseif c.direction == "down" then
		kind = "disperse"
		duration = Config.durations.dispersalSeconds
	end
	return {
		kind = kind,
		from = from,
		to = to,
		count = c.count,
		sections = c.sections,
		types = c.types,
		duration = duration,
		reps = SectionEvents.repDiff(from, to),
	}
end

-- A merged plan re-lists representatives that are already on screen (it re-plans from the running
-- celebration's start). The view builds only the ones it does not have yet; the rest just update
-- their xN count. `built` is a set of representative indices that currently exist.
function SectionEvents.toBuild(
	diff: RepDiff,
	built: { [number]: boolean }
): { VisualBudget.Representative }
	local out: { VisualBudget.Representative } = {}
	for _, r in diff.appeared do
		if not built[r.index] then
			table.insert(out, r)
		end
	end
	return out
end

local function ramp(t: number, a: number, b: number): number
	return math.clamp((t - a) / (b - a), 0, 1)
end

-- Sub-animations at celebration progress 0..1 (clamped): the crowd swirls inward, confetti covers
-- the center briefly then clears so the next decision stays visible, the puppet rises.
function SectionEvents.phases(progress: number): Phases
	local t = math.clamp(progress, 0, 1)
	local swirl = if t >= 1 then 0 else math.sin(math.pi * ramp(t, 0, SWIRL_END))
	local confetti = 0
	if t > CONFETTI_START and t < CONFETTI_END then
		confetti = if t <= CONFETTI_PEAK
			then ramp(t, CONFETTI_START, CONFETTI_PEAK)
			else 1 - ramp(t, CONFETTI_PEAK, CONFETTI_END)
	end
	return { swirl = swirl, confetti = confetti, rise = ramp(t, RISE_START, 1) }
end

-- Where a loose-follower slot (offset from the lead) is drawn at swirl 0..1: turned about the
-- pivot and pulled toward it. swirl 0 returns the slot unchanged.
function SectionEvents.swirlSlot(dx: number, dz: number, swirl: number): (number, number)
	local s = math.clamp(swirl, 0, 1)
	if s == 0 then
		return dx, dz
	end
	local rx, rz = dx, dz - SectionEvents.SWIRL_PIVOT_DZ
	local a = SWIRL_RADIANS * s
	local c, sn = math.cos(a), math.sin(a)
	local k = 1 - SWIRL_PULL * s
	return (rx * c - rz * sn) * k, (rx * sn + rz * c) * k + SectionEvents.SWIRL_PIVOT_DZ
end

return SectionEvents
