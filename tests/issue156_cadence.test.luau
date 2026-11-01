--!strict
-- Issue #156: how often the pickup lane versus horde lane steering choice comes up in a 90 s run
-- (architect report R4 aims for about one every 6 s). Measured by driving the production RunDriver
-- with scripted lane policies on every authored layout. Two numbers are reported and pinned:
--   choices   = pickups presented (each is a take-or-skip decision), per 90 s;
--   switches  = lane changes between the pickup lane and the horde lane by a policy that takes every
--               pickup, per 90 s.
-- Sample sizes are printed; this is a layout-cadence measurement, not a player-feel result.
local BotHarness = require("./helpers/BotHarness")
local Config = require("../src/shared/Config")
local DebugLayout = require("../src/shared/DebugLayout")
local Encounters = require("../src/shared/Encounters")
local LaneGeometry = require("../src/shared/LaneGeometry")
local Layouts = require("../src/shared/Layouts")

local function eq(actual: any, expected: any, label: string)
	assert(actual == expected, `{label}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function laneX(lane: string): number
	return LaneGeometry.centerOf(lane :: any)
end

-- Takes every pickup: stands in the pickup lane while the next pickup is within one span, else in
-- the horde lane. Records each lane the lead is seen in so switches can be counted.
local function collector(layout: any, seen: { string }): BotHarness.Policy
	return {
		name = "collect-all",
		period = 0.25,
		decide = function(view)
			local target = layout.laneRoles.horde
			for _, p in layout.pickups do
				if p.z > view.z then
					if p.z - view.z <= Encounters.SPAN + 1 then
						target = layout.laneRoles.pickup
					end
					break
				end
			end
			table.insert(seen, LaneGeometry.laneOf(view.x) :: any)
			return laneX(target)
		end,
	}
end

local function horde(layout: any): BotHarness.Policy
	return {
		name = "horde-only",
		period = 0.5,
		decide = function()
			return laneX(layout.laneRoles.horde)
		end,
	}
end

local function count(events: { any }, kind: string): number
	local n = 0
	for _, e in events do
		if e.kind == kind then
			n += 1
		end
	end
	return n
end

local all: { any } = { DebugLayout }
for _, l in Layouts.all do
	table.insert(all, l)
end

return {
	{
		name = "cadence: pickups presented per 90 s, lane switches per 90 s, and exactly-once collection",
		run = function()
			local samples = 0
			for _, l in all do
				local seen: { string } = {}
				local r = BotHarness.play(l, collector(l, seen), { maxSeconds = 100 })
				local collected = count(r.events, "pickup")
				local switches = 0
				local prev: string? = nil
				for _, lane in seen do
					-- only the two working lanes count; crossing center on the way is not a lane
					if lane == l.laneRoles.pickup or lane == l.laneRoles.horde then
						if prev ~= nil and lane ~= prev then
							switches += 1
						end
						prev = lane
					end
				end
				local h = BotHarness.play(l, horde(l), { maxSeconds = 100 })
				samples += 2
				local presented = #l.pickups
				local secs = (l.plazaStart / Config.speed)
				print(
					`cadence {l.name}: run {string.format("%.1f", r.time)} s, outcome {tostring(
						r.outcome
					)}; pickups presented {presented} in {string.format("%.1f", secs)} s travel = one per {string.format(
						"%.2f",
						secs / presented
					)} s; collect-all took {collected}, lane switches {switches} ({string.format(
						"%.1f",
						secs / math.max(switches, 1)
					)} s apart); horde-only took {count(h.events, "pickup")}`
				)
				eq(collected, presented, `{l.name} collect-all takes each pickup once`)
				eq(count(h.events, "pickup"), 0, `{l.name} staying in the horde lane takes none`)
				assert(
					secs / presented <= 6,
					`{l.name} presents a pickup choice at least every 6 s`
				)
				eq(switches, 6, `{l.name} three strips = six lane switches`)
			end
			print(`cadence samples: {samples} runs ({#all} layouts x 2 policies)`)
		end,
	},
}
