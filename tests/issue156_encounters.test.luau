--!strict
-- Issue #156 (ADR 0010 item 5): bounded, deterministic, server-owned lane encounter state and its
-- validated client representation. Covers boundary crossing, repeated ticks, overlapping
-- encounters, missed pickups and replay/reset. Modules are required inside each case so a missing
-- module fails only its own case.
local RunDriver = require("../src/shared/RunDriver")

local function eq(actual: any, expected: any, label: string)
	assert(actual == expected, `{label}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function near(actual: number, expected: number, label: string)
	assert(math.abs(actual - expected) < 1e-9, `{label}: expected {expected}, got {actual}`)
end

local function deepCopy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, child in v do
		out[k] = deepCopy(child)
	end
	return out
end

-- A minimal authored segment: no gates, obstacles or mobs, only the pickups given.
local function segment(pickups: { { id: number, z: number, lane: string } }): any
	return {
		name = "issue156-encounter",
		seed = 3,
		streetLength = 400,
		plazaStart = 320,
		halfWidth = 20,
		leadLimit = 15,
		maxTotal = 1000,
		intendedRecruitTotal = 0,
		gates = {},
		obstacles = {},
		clusters = {},
		pickups = pickups,
	}
end

-- Ticks the driver until the lead has reached z (or the run ends); fails if it never gets there.
local function tickUntil(d: any, zTarget: number)
	for _ = 1, 20000 do
		if d:snapshot().z >= zTarget or d:outcome() ~= nil then
			return
		end
		d:tick(RunDriver.TICK_DT)
	end
	error(`lead never reached z {zTarget}`)
end

local function runToEnd(d: any)
	for _ = 1, 20000 do
		if d:outcome() ~= nil then
			return
		end
		d:tick(RunDriver.TICK_DT)
	end
	error("run never ended")
end

return {
	{
		name = "Encounters.spanOf: a pickup is live on the SPAN studs before its plane",
		run = function()
			local Encounters = require("../src/shared/Encounters")
			local lo, hi = Encounters.spanOf({ id = 1, z = 64, lane = "right" } :: any)
			near(hi, 64, "span ends at the plane")
			near(lo, 64 - Encounters.SPAN, "span starts SPAN studs before the plane")
			assert(Encounters.SPAN > 0, "SPAN is positive")
		end,
	},
	{
		name = "Encounters.validateSpans: overlapping spans fail, touching spans pass, any lane",
		run = function()
			local Encounters = require("../src/shared/Encounters")
			local span = Encounters.SPAN
			local ok1 = Encounters.validateSpans(segment({
				{ id = 1, z = 64, lane = "right" },
				{ id = 2, z = 64 + span / 2, lane = "left" },
			}))
			eq(ok1, false, "overlapping spans in different lanes fail (one active encounter)")
			local ok2 = Encounters.validateSpans(segment({
				{ id = 1, z = 64, lane = "right" },
				{ id = 2, z = 64 + span, lane = "right" },
			}))
			eq(ok2, true, "a span that only touches the next one is allowed")
			local ok3 = Encounters.validateSpans(segment({
				{ id = 1, z = 64, lane = "right" },
				{ id = 2, z = 200, lane = "center" },
			}))
			eq(ok3, true, "distant pickups are allowed")
			eq(Encounters.validateSpans(segment({})), true, "no pickups is valid")
		end,
	},
	{
		name = "Crossing.pickupsCrossed: every plane passed this tick, in any lane, once per tick",
		run = function()
			local Crossing = require("../src/shared/Crossing")
			local layout = segment({
				{ id = 1, z = 5, lane = "right" },
				{ id = 2, z = 5, lane = "left" },
				{ id = 3, z = 12, lane = "center" },
			})
			local function ids(list: { { id: number } }): string
				local out = {}
				for _, p in list do
					table.insert(out, tostring(p.id))
				end
				return table.concat(out, ",")
			end
			eq(ids(Crossing.pickupsCrossed(layout, 0, 10)), "1,2", "both planes at 5 passed")
			eq(ids(Crossing.pickupsCrossed(layout, 0, 5)), "1,2", "plane exactly at z1 is passed")
			eq(ids(Crossing.pickupsCrossed(layout, 5, 10)), "", "a plane at z0 is not passed again")
			eq(ids(Crossing.pickupsCrossed(layout, 10, 20)), "3", "later plane")
			eq(ids(Crossing.pickupsCrossed(layout, 5, 5)), "", "no forward progress, no plane")
		end,
	},
	{
		name = "Encounters.current: none without pickups; active inside the span, upcoming before",
		run = function()
			local Encounters = require("../src/shared/Encounters")
			eq(Encounters.current(segment({}), 10, {}), nil, "no pickups, no encounter")
			local layout = segment({ { id = 1, z = 64, lane = "right" } })
			local before = Encounters.current(layout, 10, {})
			assert(before ~= nil, "upcoming pickup is reported")
			eq(before.id, "p1", "id is the RunState pickup id")
			eq(before.kind, "pickup", "kind")
			eq(before.lane, "right", "lane")
			eq(before.active, false, "not yet in its span")
			eq(before.progress, 0, "no progress before the span")
			near(before.remaining, 54, "studs to the plane")
			local inside = Encounters.current(layout, 50, {})
			assert(inside ~= nil, "in-span pickup is reported")
			eq(inside.active, true, "active inside the span")
			near(inside.progress, (50 - (64 - Encounters.SPAN)) / Encounters.SPAN, "progress")
			near(inside.remaining, 14, "remaining to the plane")
			local atStart = Encounters.current(layout, 64 - Encounters.SPAN, {})
			assert(atStart ~= nil, "span start is reported")
			eq(atStart.active, true, "span start is active (lo <= z)")
			eq(atStart.progress, 0, "span start progress is 0")
		end,
	},
	{
		name = "Encounters.current: resolved pickups are skipped; missed ones advance the encounter",
		run = function()
			local Encounters = require("../src/shared/Encounters")
			local layout = segment({
				{ id = 1, z = 64, lane = "right" },
				{ id = 2, z = 150, lane = "left" },
			})
			eq(Encounters.current(layout, 50, { [1] = "collected" }).id, "p2", "collected skipped")
			eq(Encounters.current(layout, 50, { [1] = "missed" }).id, "p2", "missed skipped")
			eq(Encounters.current(layout, 50, { [1] = "missed", [2] = "missed" }), nil, "none left")
		end,
	},
	{
		name = "Encounters.current is deterministic and bounded even for overlapping input",
		run = function()
			local Encounters = require("../src/shared/Encounters")
			local layout = segment({
				{ id = 2, z = 70, lane = "left" },
				{ id = 1, z = 64, lane = "right" },
			})
			local a = Encounters.current(layout, 60, {})
			local b = Encounters.current(layout, 60, {})
			eq(a.id, "p1", "smallest pending z wins, whatever the authored order")
			eq(b.id, a.id, "same input gives the same encounter")
			local far = Encounters.current(segment({ { id = 9, z = 300, lane = "left" } }), 0, {})
			assert(far.remaining <= 1000, "remaining is bounded by the client limit")
			assert(far.progress >= 0 and far.progress <= 1, "progress stays in [0, 1]")
		end,
	},
	{
		name = "Remotes.decodeEncounter: accepts only the validated shape, drops everything else",
		run = function()
			local Remotes = require("../src/shared/Remotes")
			local good = {
				id = "p1",
				kind = "pickup",
				lane = "right",
				progress = 0.5,
				remaining = 12,
				active = true,
			}
			local clean = Remotes.decodeEncounter(good)
			assert(clean ~= nil, "a valid encounter is kept")
			eq(clean.id, "p1", "id kept")
			eq(clean.lane, "right", "lane kept")
			local function rejects(label: string, mutate: (any) -> ())
				local bad = deepCopy(good)
				mutate(bad)
				eq(Remotes.decodeEncounter(bad), nil, label)
			end
			rejects("unknown kind", function(e)
				e.kind = "boss"
			end)
			rejects("bad lane", function(e)
				e.lane = "up"
			end)
			rejects("progress above 1", function(e)
				e.progress = 1.5
			end)
			rejects("progress NaN", function(e)
				e.progress = 0 / 0
			end)
			rejects("negative remaining", function(e)
				e.remaining = -1
			end)
			rejects("remaining beyond the bound", function(e)
				e.remaining = 1e9
			end)
			rejects("active not a boolean", function(e)
				e.active = "yes"
			end)
			rejects("id not a pickup id", function(e)
				e.id = "p1; drop"
			end)
			rejects("id too long", function(e)
				e.id = "p" .. string.rep("1", 40)
			end)
			eq(Remotes.decodeEncounter(nil), nil, "nil is no encounter")
			eq(Remotes.decodeEncounter("p1"), nil, "a string is no encounter")
		end,
	},
	{
		name = "Remotes.encodeState: carries the encounter, drops invalid ones, copies no extra fields",
		run = function()
			local Remotes = require("../src/shared/Remotes")
			local base = { time = 1, z = 50, x = 0, total = 10, best = 0 }
			local withEnc = Remotes.encodeState({
				time = base.time,
				z = base.z,
				x = base.x,
				total = base.total,
				best = base.best,
				encounter = {
					id = "p1",
					kind = "pickup",
					lane = "right",
					progress = 0.4,
					remaining = 14,
					active = true,
					award = 99,
				} :: any,
			} :: any)
			assert(withEnc.encounter ~= nil, "valid encounter encoded")
			eq(withEnc.encounter.id, "p1", "id")
			eq((withEnc.encounter :: any).award, nil, "no extra (award) field is copied")
			local none = Remotes.encodeState(base :: any)
			eq(none.encounter, nil, "no encounter when the snapshot has none")
			local bad = Remotes.encodeState({
				time = base.time,
				z = base.z,
				x = base.x,
				total = base.total,
				best = base.best,
				encounter = { id = 7, kind = "pickup" } :: any,
			} :: any)
			eq(bad.encounter, nil, "malformed encounter is dropped, not passed through")
		end,
	},
	{
		name = "RunDriver: snapshot reports the next pickup, then nothing once it is resolved",
		run = function()
			local d = RunDriver.new({
				layout = segment({ { id = 1, z = 64, lane = "right" } }) :: any,
				automated = true,
			})
			local e0 = (d:snapshot() :: any).encounter
			assert(e0 ~= nil, "pickup is shown before the run")
			eq(e0.id, "p1", "the authored pickup")
			eq(e0.active, false, "not yet in its span at the start")
			assert(d:steer(0, { x = 10 }), "steer accepted")
			tickUntil(d, 64)
			eq((d:snapshot() :: any).encounter, nil, "resolved pickup is no longer an encounter")
		end,
	},
	{
		name = "RunDriver: boundary crossing: the lead's lane at the plane decides, and only once",
		run = function()
			-- x 0 -> 10 while crossing the plane puts the lead at the boundary zone; a centre pickup
			-- is awarded to a lead at x=0 and not to a lead already in the right lane (x=10).
			local d = RunDriver.new({
				layout = segment({ { id = 1, z = 64, lane = "center" } }) :: any,
				automated = true,
			})
			local before = d:total()
			assert(d:steer(0, { x = 0 }), "steer accepted")
			tickUntil(d, 64)
			runToEnd(d)
			eq(d:total(), before + 1, "centre lead collects the centre pickup once")
		end,
	},
	{
		name = "RunDriver: repeated ticks after the plane never award the pickup again",
		run = function()
			local d = RunDriver.new({
				layout = segment({ { id = 1, z = 64, lane = "right" } }) :: any,
				automated = true,
			})
			local before = d:total()
			assert(d:steer(0, { x = 10 }), "steer accepted")
			tickUntil(d, 64)
			local afterCross = d:total()
			eq(afterCross, before + 1, "collected at the plane")
			for _ = 1, 300 do
				d:tick(RunDriver.TICK_DT)
			end
			eq(d:total(), afterCross, "300 further ticks add nothing")
		end,
	},
	{
		name = "RunDriver: a missed pickup is passed for nothing and the next encounter takes over",
		run = function()
			local d = RunDriver.new({
				layout = segment({
					{ id = 1, z = 64, lane = "right" },
					{ id = 2, z = 150, lane = "right" },
				}) :: any,
				automated = true,
			})
			local before = d:total()
			assert(d:steer(0, { x = -10 }), "steer accepted: left lead misses the right pickup")
			tickUntil(d, 64)
			eq(d:total(), before, "missed pickup awards nothing")
			local next = (d:snapshot() :: any).encounter
			assert(next ~= nil, "the next pickup is now the encounter")
			eq(next.id, "p2", "missed p1 is skipped, p2 is next")
			assert(d:steer(1, { x = 10 }), "steer accepted: move to the right lane")
			tickUntil(d, 150)
			eq(d:total(), before + 1, "p2 collected once; p1 never counted")
			runToEnd(d)
			eq(d:total(), before + 1, "end of run: still exactly +1")
		end,
	},
	{
		name = "RunDriver: replay starts the encounter over and awards it exactly once again",
		run = function()
			local d = RunDriver.new({
				layout = segment({ { id = 1, z = 64, lane = "right" } }) :: any,
				automated = true,
			})
			local before = d:total()
			assert(d:steer(0, { x = 10 }), "steer accepted")
			runToEnd(d)
			eq(d:total(), before + 1, "first run: +1")
			eq((d:snapshot() :: any).encounter, nil, "resolved encounter gone at the end")
			eq(d:replay(1000), true, "replay accepted")
			local fresh = (d:snapshot() :: any).encounter
			assert(fresh ~= nil, "replay re-arms the pickup")
			eq(fresh.id, "p1", "the same authored pickup")
			eq(fresh.active, false, "back at the start")
			assert(d:steer(1000, { x = 10 }), "steer accepted after replay")
			runToEnd(d)
			eq(d:total(), before + 1, "replayed run: +1 again, not +2")
		end,
	},
	{
		name = "LayoutValidator: overlapping pickup spans fail; spaced pickups validate",
		run = function()
			local Layouts = require("../src/shared/Layouts")
			local LayoutValidator = require("../src/shared/LayoutValidator")
			local Encounters = require("../src/shared/Encounters")
			local base = Layouts.all[1]
			local overlap = deepCopy(base)
			overlap.pickups = {
				{ id = 1, z = 500, lane = "left" },
				{ id = 2, z = 500 + Encounters.SPAN / 2, lane = "right" },
			}
			local ok, msg = LayoutValidator.validate(overlap)
			eq(ok, false, "overlapping encounters fail validation")
			assert(string.find(msg :: string, "overlap") ~= nil, "message names the overlap")
			local spaced = deepCopy(base)
			spaced.pickups = {
				{ id = 1, z = 500, lane = "left" },
				{ id = 2, z = 530, lane = "right" },
			}
			eq(LayoutValidator.validate(spaced), true, "spaced pickups validate")
		end,
	},
}
