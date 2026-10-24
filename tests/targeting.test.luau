--!strict
local Config = require("../src/shared/Config")
local Level = require("../src/shared/Level")
local RunState = require("../src/shared/RunState")
local Targeting = require("../src/shared/Targeting")

local function near(actual: number, expected: number, name: string)
	assert(math.abs(actual - expected) < 1e-6, `{name}: expected {expected}, got {actual}`)
end

local function cluster(
	id: number,
	x: number,
	z: number,
	kind: string?,
	spawnTime: number?
): Level.Cluster
	return {
		id = id,
		wave = 1,
		type = kind or "small",
		spawnTime = spawnTime or 0,
		spawn = { x = x, z = z },
		path = {},
	}
end

local function layoutOf(clusters: { Level.Cluster }): Level.Layout
	return {
		name = "t",
		seed = 0,
		streetLength = 1600,
		plazaStart = 1440,
		halfWidth = 20,
		maxTotal = 1000,
		intendedRecruitTotal = 0,
		gates = {},
		obstacles = {},
		clusters = clusters,
	}
end

local function runStateFor(layout: Level.Layout): RunState.RunState
	local defs: { RunState.ClusterDef } = {}
	for _, c in layout.clusters do
		table.insert(defs, { id = tostring(c.id), type = c.type :: RunState.ClusterKind })
	end
	return RunState.new({
		seed = 1,
		automated = true,
		layout = { gatePairs = {}, clusters = defs, obstacles = {} },
		now = function()
			return 0
		end,
	})
end

local function newSession(layout: Level.Layout)
	local rs = runStateFor(layout)
	return Targeting.new({ layout = layout, runState = rs }), rs
end

-- Runs the session on a fixed clock and returns every shot fired (hits and misses).
local function driveAll(
	session: any,
	from: number,
	to: number,
	dt: number,
	sections: number,
	steer: string
)
	local shots: { any } = {}
	local t = from
	while t <= to + 1e-9 do
		for _, s in session:advance(t, sections, steer).shots do
			table.insert(shots, s)
		end
		t += dt
	end
	return shots
end

-- Same, but only the shots that hit a cluster (continuous fire also produces display-only misses).
local function drive(
	session: any,
	from: number,
	to: number,
	dt: number,
	sections: number,
	steer: string
)
	local hits: { any } = {}
	for _, s in driveAll(session, from, to, dt, sections, steer) do
		if not s.miss then
			table.insert(hits, s)
		end
	end
	return hits
end

local function cand(id: number, x: number, z: number, full: boolean?): Targeting.Candidate
	return { id = id, x = x, z = z, full = full or false }
end

return {
	{
		name = "fire rate is min(20, 6 + sections) at 0, 1, 9 and 100 sections (ADR 0004)",
		run = function()
			assert(Targeting.fireRate(0) == 6, "0 sections")
			assert(Targeting.fireRate(1) == 7, "1 section")
			assert(Targeting.fireRate(9) == 15, "9 sections")
			assert(Targeting.fireRate(14) == 20, "14 sections reach the cap")
			assert(Targeting.fireRate(15) == 20, "15 sections stay at the cap")
			assert(Targeting.fireRate(100) == 20, "100 sections capped")
			assert(Config.firing.base == 6 and Config.firing.cap == 20, "named defaults")
		end,
	},
	{
		name = "fire rate rejects invalid section counts",
		run = function()
			assert(not pcall(Targeting.fireRate, -1), "negative")
			assert(not pcall(Targeting.fireRate, 1.5), "fraction")
		end,
	},
	{
		name = "no eligible target means no pick, and every scheduled shot is a visual-only miss",
		run = function()
			assert(Targeting.selectTarget({}, 0, "center") == nil, "empty")
			local out = {
				cand(1, 5, Config.firing.range + 1), -- out of range
				cand(2, 5, 30, true), -- meter full
				cand(3, 5, 0), -- at the lead: passed
				cand(4, 5, -10), -- behind the lead: passed
			}
			assert(Targeting.selectTarget(out, 0, "center") == nil, "none eligible")
			local layout = layoutOf({ cluster(1, 5, 400) }) -- far beyond range for a long time
			local session = newSession(layout)
			local all = driveAll(session, 0, 2, 1 / 30, 0, "center")
			assert(#all >= 12, `continuous fire: expected >= 12 shots in 2 s at 6/s, got {#all}`)
			for i, s in all do
				assert(s.miss == true and s.targetId == nil, `shot {i} is a miss`)
				assert(s.hits == 0 and not s.filled and s.credit == nil, `miss {i} touches nothing`)
			end
		end,
	},
	{
		name = "range is inclusive at firing.range and a cluster at the lead is passed",
		run = function()
			assert(
				Targeting.selectTarget({ cand(1, 5, Config.firing.range) }, 0, "center") == 1,
				"edge"
			)
			assert(
				Targeting.selectTarget({ cand(1, 5, 100 + 0.001) }, 100, "center") == 1,
				"just ahead"
			)
			assert(Targeting.selectTarget({ cand(1, 5, 100) }, 100, "center") == nil, "at lead")
		end,
	},
	{
		name = "nearest eligible target to the lead is chosen when steering center",
		run = function()
			local list = { cand(1, -16, 40), cand(2, 16, 20), cand(3, 16, 30) }
			assert(Targeting.selectTarget(list, 0, "center") == 2, "nearest")
			-- a nearer but full cluster is skipped
			list[2] = cand(2, 16, 20, true)
			assert(Targeting.selectTarget(list, 0, "center") == 3, "skips full")
		end,
	},
	{
		name = "steering toward a side prefers eligible targets on that side",
		run = function()
			local list = { cand(1, -16, 50), cand(2, 16, 10), cand(3, 16, 20) }
			assert(Targeting.selectTarget(list, 0, "left") == 1, "left beats nearer right")
			assert(Targeting.selectTarget(list, 0, "right") == 2, "nearest on right")
		end,
	},
	{
		name = "steering toward an empty side falls back to nearest overall",
		run = function()
			local list = { cand(1, 16, 40), cand(2, 16, 25) }
			assert(Targeting.selectTarget(list, 0, "left") == 2, "fallback nearest")
			-- the only left cluster is full: left has no eligible target, so fall back
			local list2 = { cand(1, -16, 10, true), cand(2, 16, 30) }
			assert(Targeting.selectTarget(list2, 0, "left") == 2, "full left falls back")
		end,
	},
	{
		name = "center band uses spectators.centerTolerance for side membership",
		run = function()
			local tol = Config.spectators.centerTolerance
			-- x = -tol is center, so it does not count as "left"
			local list = { cand(1, -tol, 10), cand(2, -tol - 0.5, 50) }
			assert(Targeting.selectTarget(list, 0, "left") == 2, "strictly left only")
			assert(Targeting.selectTarget(list, 0, "center") == 1, "center steering is nearest")
		end,
	},
	{
		name = "ties on distance break by lowest id (deterministic)",
		run = function()
			local list = { cand(7, 16, 20), cand(3, -16, 20) }
			assert(Targeting.selectTarget(list, 0, "center") == 3, "lowest id")
		end,
	},
	{
		name = "shots fire at the curve rate on a fixed clock",
		run = function()
			local layout = layoutOf({ cluster(1, 16, 30, "large") })
			local session = newSession(layout)
			-- sections 0 => 6 per second; stand-still lead is not modelled, so use a short window
			local shots = driveAll(session, 0, 0.9, 1 / 60, 0, "center")
			-- shots at 0, 1/6, ... 5/6 => 6 within [0, 0.9]
			assert(#shots == 6, `expected 6 shots, got {#shots}`)
			near(shots[2].time - shots[1].time, 1 / 6, "interval")
			local fast = newSession(layout)
			local shots14 = driveAll(fast, 0, 0.52, 1 / 60, 14, "center")
			-- 20 per second (the cap): shots at 0, 0.05, ... 0.5 => 11 shots in [0, 0.52]
			assert(#shots14 == 11, `expected 11 shots at cap, got {#shots14}`)
		end,
	},
	{
		name = "meter fills by hits and credits the run exactly once",
		run = function()
			local layout = layoutOf({ cluster(1, 16, 30, "small") })
			local session, rs = newSession(layout)
			local need = Config.clusterTypes.small.hits
			local before = rs:total()
			local shots = drive(session, 0, 5, 1 / 60, 0, "center")
			assert(#shots == need, `expected exactly {need} shots, got {#shots}`)
			assert(shots[need].filled == true, "last shot fills the meter")
			assert(shots[need].credit ~= nil and shots[need].credit.ok, "credited")
			assert(
				shots[1].filled == false and shots[1].credit == nil,
				"first shot does not credit"
			)
			assert(rs:total() == before + Config.clusterTypes.small.reward, "reward applied once")
			assert(rs:clusterConsumption("1") == "credited", "consumed")
			local credits = 0
			for _, e in rs:events() do
				if e.kind == "cluster_credit" then
					credits += 1
				end
			end
			assert(credits == 1, "exactly one credit event")
		end,
	},
	{
		name = "extra hits after the meter is full never credit again",
		run = function()
			local layout = layoutOf({ cluster(1, 16, 30, "small") })
			local session, rs = newSession(layout)
			drive(session, 0, 5, 1 / 60, 0, "center")
			local total = rs:total()
			local events = #rs:events()
			for _ = 1, 5 do
				local r = session:hit(1)
				assert(r.filled == true and r.credit == nil, "late hit is inert")
			end
			assert(rs:total() == total and #rs:events() == events, "no further credit")
			local hits, needed = session:meter(1)
			assert(hits == needed, "meter stays capped at full")
		end,
	},
	{
		name = "a full cluster is no longer targeted",
		run = function()
			local layout = layoutOf({ cluster(1, 16, 30, "small"), cluster(2, -16, 50, "small") })
			local session = newSession(layout)
			local shots = drive(session, 0, 10, 1 / 60, 0, "center")
			local counts: { [number]: number } = {}
			for _, s in shots do
				counts[s.targetId] = (counts[s.targetId] or 0) + 1
			end
			assert(counts[1] == 3 and counts[2] == 3, "each small cluster takes exactly 3 hits")
		end,
	},
	{
		name = "gift cadence: every 4th shot once a dancer section exists",
		run = function()
			-- dancers is section 3 of the puppet/globo/dancers sequence
			for n = 1, 12 do
				assert(Targeting.shotKind(n, 0) == "note", "no sections")
				assert(Targeting.shotKind(n, 2) == "note", "no dancer section yet")
			end
			local kinds = {}
			for n = 1, 8 do
				table.insert(kinds, Targeting.shotKind(n, 3))
			end
			assert(
				table.concat(kinds, ",") == "note,note,note,gift,note,note,note,gift",
				table.concat(kinds, ",")
			)
			assert(Targeting.shotKind(4, 100) == "gift", "stays with many sections")
		end,
	},
	{
		name = "scheduler stamps shots with the gift kind, still one hit each",
		run = function()
			local layout = layoutOf({ cluster(1, 16, 30, "large") })
			local session = newSession(layout)
			local shots = drive(session, 0, 5, 1 / 60, 3, "center")
			assert(#shots == Config.clusterTypes.large.hits, "gifts count as one hit each")
			assert(shots[4].kind == "gift" and shots[8].kind == "gift", "4th and 8th are gifts")
			assert(shots[1].kind == "note" and shots[5].kind == "note", "others are notes")
		end,
	},
	{
		name = "deterministic: identical clock and inputs give identical shots",
		run = function()
			local layout = layoutOf({
				cluster(1, 16, 30, "large"),
				cluster(2, -16, 45, "small"),
				cluster(3, 2, 20, "small", 0.5),
			})
			local function run(): string
				local session = newSession(layout)
				local out = {}
				for _, s in drive(session, 0, 4, 1 / 30, 4, "left") do
					table.insert(out, `{s.number}:{s.time}:{s.targetId}:{s.kind}:{s.filled}`)
				end
				return table.concat(out, "|")
			end
			assert(run() == run(), "runs differ")
			assert(#run() > 0, "something fired")
		end,
	},
	{
		name = "moving targets: eligibility follows position at the shot time",
		run = function()
			-- Cluster starts at z = 500, walks toward the parade at approachSpeed while the lead moves up.
			local layout = layoutOf({ cluster(1, 16, 500, "large") })
			local session = newSession(layout)
			local closing = Config.speed + Config.spectators.approachSpeed
			-- distance(t) = 500 - closing * t; in range when <= firing.range
			local tEnter = (500 - Config.firing.range) / closing
			local shots = drive(session, 0, tEnter + 3, 1 / 30, 0, "center")
			assert(#shots > 0, "fires once in range")
			assert(
				shots[1].time >= tEnter - 1e-6,
				`fired too early at {shots[1].time}, enter {tEnter}`
			)
			assert(shots[1].time < tEnter + 1 / 30 + 1e-6, "fires as soon as it enters range")
			local z = Level.clusterPosition(layout, 1, shots[1].time).z
			assert(z - Level.leadZ(shots[1].time) <= Config.firing.range + 1e-6, "in range at shot")
		end,
	},
	{
		name = "moving targets: a cluster that has not spawned yet is not a target",
		run = function()
			local layout = layoutOf({ cluster(1, 16, 100, "small", 2) })
			local session = newSession(layout)
			local shots = drive(session, 0, 1.5, 1 / 30, 0, "center")
			assert(#shots == 0, "waiting cluster is not targeted")
			local later = drive(session, 1.6, 3, 1 / 30, 0, "center")
			assert(#later > 0 and later[1].time >= 2 - 1e-6, "targetable from spawnTime")
		end,
	},
	{
		name = "clusters leaving range or passing unfilled are reported once, with no credit or penalty",
		run = function()
			-- Right on the lead's path: the lead overtakes it before it can be filled (no fire: steer
			-- sections 0 gives 6/s, cluster needs 8 hits but passes within ~0.9 s).
			local layout = layoutOf({ cluster(1, 16, 20, "large") })
			local session, rs = newSession(layout)
			local total = rs:total()
			local passedIds: { number } = {}
			local t = 0
			local shotCount = 0
			while t <= 3 do
				local step = session:advance(t, 0, "center")
				for _, s in step.shots do
					if not s.miss then
						shotCount += 1
					end
				end
				for _, id in step.passed do
					table.insert(passedIds, id)
				end
				t += 1 / 30
			end
			assert(shotCount < Config.clusterTypes.large.hits, "not filled")
			assert(#passedIds == 1 and passedIds[1] == 1, "reported exactly once")
			assert(rs:total() == total, "no credit and no loss here")
			assert(
				rs:clusterConsumption("1") == nil,
				"left unconsumed (the attack phase consumes it)"
			)
			-- and a passed cluster never receives shots again
			local more = session:advance(t + 1, 0, "center")
			for _, s in more.shots do
				assert(s.miss, "a passed cluster never receives a hit again")
			end
			assert(#more.passed == 0, "reported only once")
		end,
	},
	{
		name = "hit after a cluster passed is inert",
		run = function()
			local layout = layoutOf({ cluster(1, 16, 20, "large") })
			local session, rs = newSession(layout)
			local t = (20 / (Config.speed + Config.spectators.approachSpeed)) + 0.01
			local step = session:advance(t, 0, "center")
			assert(#step.passed == 1 and step.passed[1] == 1, "cluster passed")
			local beforeTotal = rs:total()
			local beforeEvents = #rs:events()
			local beforeHits = session:meter(1)
			local late = session:hit(1)
			assert(late.hits == beforeHits, "late hit does not change meter")
			assert(not late.filled and late.credit == nil, "late hit does not credit")
			assert(rs:total() == beforeTotal, "late hit does not change total")
			assert(#rs:events() == beforeEvents, "late hit does not log")
			assert(rs:clusterConsumption("1") == nil, "passed cluster awaits attack")
		end,
	},
	{
		name = "a cluster that fills just before the lead reaches it converts and is not reported passed",
		run = function()
			local layout = layoutOf({ cluster(1, 16, 14.67, "small") })
			local session = newSession(layout)
			local passed = 0
			local shots = 0
			local t = 0
			while t <= 3 do
				local step = session:advance(t, 0, "center")
				for _, s in step.shots do
					if not s.miss then
						shots += 1
					end
				end
				passed += #step.passed
				t += 1 / 30
			end
			assert(shots == 3, `expected 3 shots, got {shots}`)
			assert(passed == 0, "converted clusters are never reported as passed")
		end,
	},
	{
		name = "advance rejects time going backwards",
		run = function()
			local session = newSession(layoutOf({ cluster(1, 16, 30) }))
			session:advance(1, 0, "center")
			assert(not pcall(function()
				session:advance(0.5, 0, "center")
			end), "backwards time must error")
		end,
	},
}
