--!strict
local Config = require("../src/shared/Config")
local CrowdMath = require("../src/shared/CrowdMath")
local RunState = require("../src/shared/RunState")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {expected}, got {actual}`)
end

local layout: RunState.Layout = {
	gatePairs = {
		{
			id = "g1",
			left = { x = -4, op = { kind = "add", value = 20 } },
			right = { x = 4, op = { kind = "multiply", value = 2 } },
		},
		{
			id = "g2",
			left = { x = -4, op = { kind = "multiply", value = 2 } },
			right = { x = 4, op = { kind = "add", value = 20 } },
		},
	},
	clusters = {
		{ id = "c1", type = "small" },
		{ id = "c2", type = "large" },
	},
	obstacles = { { id = "o1" }, { id = "o2" } },
}

local function make(automated: boolean?): (RunState.RunState, { clock: number })
	local t = { clock = 100 }
	local run = RunState.new({
		seed = 42,
		automated = automated or false,
		layout = layout,
		now = function()
			t.clock += 1
			return t.clock
		end,
	})
	return run, t
end

-- Whole observable state, for "no state change" comparisons.
local function snapshot(run: RunState.RunState): string
	local parts = { run:total(), tostring(run:isComplete()), tostring(run:score()), run:best() }
	parts[#parts + 1] = #run:events()
	return table.concat(parts, "|")
end

local function reject(
	ok: boolean,
	reason: string?,
	run: RunState.RunState,
	before: string,
	name: string
)
	assert(not ok, `{name}: expected rejection`)
	assert(reason ~= nil and reason ~= "", `{name}: rejection needs a reason`)
	eq(snapshot(run), before, `{name} state unchanged`)
end

return {
	{
		name = "new run starts at Config.startingTotal, not complete, one run_start event",
		run = function()
			local run = make()
			eq(run:total(), Config.startingTotal, "total")
			eq(run:isComplete(), false, "complete")
			eq(run:outcome(), nil, "outcome")
			eq(run:score(), nil, "score before completion")
			eq(run:best(), 0, "best")
			local ev = run:events()
			eq(#ev, 1, "events")
			eq(ev[1].kind, "run_start", "kind")
		end,
	},
	{
		name = "gate: lead nearest the left gate takes the left op on the whole total",
		run = function()
			local run = make()
			local r = run:resolveGate("g1", -3)
			assert(r.ok, "should resolve")
			eq(r.side, "left", "side")
			eq(r.before, 10, "before")
			eq(r.after, 30, "after")
			eq(run:total(), 30, "total")
		end,
	},
	{
		name = "gate: lead nearest the right gate takes the right op (x2)",
		run = function()
			local run = make()
			local r = run:resolveGate("g1", 3.5)
			assert(r.ok, "should resolve")
			eq(r.side, "right", "side")
			eq(run:total(), 20, "total")
		end,
	},
	{
		name = "gate: exact tie at the center picks the left gate (spec s6)",
		run = function()
			local run = make()
			local r = run:resolveGate("g1", 0)
			assert(r.ok, "should resolve")
			eq(r.side, "left", "side")
			eq(run:total(), 30, "total")
		end,
	},
	{
		name = "gate: tie break also holds for an off-center pair",
		run = function()
			local run = RunState.new({
				seed = 1,
				automated = true,
				layout = {
					gatePairs = {
						{
							id = "p",
							left = { x = 2, op = { kind = "add", value = 20 } },
							right = { x = 6, op = { kind = "multiply", value = 2 } },
						},
					},
					clusters = {},
					obstacles = {},
				},
			})
			local r = run:resolveGate("p", 4)
			assert(r.ok, "should resolve")
			eq(r.side, "left", "side")
		end,
	},
	{
		name = "gate: a pair resolves once; repeated calls (even other leadX) change nothing",
		run = function()
			local run = make()
			assert(run:resolveGate("g1", -3).ok, "first")
			local before = snapshot(run)
			for _, x in { -3, 3, 0, 100 } do
				local r = run:resolveGate("g1", x)
				reject(r.ok, r.reason, run, before, `repeat x={x}`)
			end
			eq(run:total(), 30, "total")
		end,
	},
	{
		name = "gate: unknown pair id rejected, no state change",
		run = function()
			local run = make()
			local before = snapshot(run)
			local r = run:resolveGate("forged", -3)
			reject(r.ok, r.reason, run, before, "unknown pair")
		end,
	},
	{
		name = "gate: non-string ids and bad leadX rejected, no state change",
		run = function()
			local run = make()
			local before = snapshot(run)
			local bads: { any } = { 1, true, {}, "" }
			for _, id in bads do
				local r = run:resolveGate(id :: any, 0)
				reject(r.ok, r.reason, run, before, "bad id")
			end
			local xs: { any } = { 0 / 0, math.huge, -math.huge, "3", {} }
			for _, x in xs do
				local r = run:resolveGate("g1", x :: any)
				reject(r.ok, r.reason, run, before, "bad leadX")
			end
			assert(run:resolveGate("g1", 0).ok, "pair still unconsumed")
		end,
	},
	{
		name = "cluster: credited once with the Config reward",
		run = function()
			local run = make()
			local r = run:creditCluster("c1")
			assert(r.ok, "credit")
			eq(r.before, 10, "before")
			eq(r.after, 10 + Config.clusterTypes.small.reward, "after")
			local r2 = run:creditCluster("c2")
			assert(r2.ok, "credit large")
			eq(
				run:total(),
				10 + Config.clusterTypes.small.reward + Config.clusterTypes.large.reward,
				"total"
			)
		end,
	},
	{
		name = "cluster: repeated credit (animation arrival, retriggers) is rejected, no change",
		run = function()
			local run = make()
			assert(run:creditCluster("c1").ok, "first")
			local before = snapshot(run)
			for _ = 1, 5 do
				local r = run:creditCluster("c1")
				reject(r.ok, r.reason, run, before, "repeat credit")
			end
		end,
	},
	{
		name = "cluster: forged id rejected, no change",
		run = function()
			local run = make()
			local before = snapshot(run)
			local r = run:creditCluster("c999")
			reject(r.ok, r.reason, run, before, "forged cluster")
			local r2 = run:creditCluster(5 :: any)
			reject(r2.ok, r2.reason, run, before, "numeric cluster id")
		end,
	},
	{
		name = "cluster: consumption records its kind (credited) so a later attack cannot also apply",
		run = function()
			local run = make()
			eq(run:clusterConsumption("c1"), nil, "unconsumed")
			assert(run:creditCluster("c1").ok, "credit")
			eq(run:clusterConsumption("c1"), "credited", "kind")
			eq(run:clusterConsumption("c2"), nil, "other cluster untouched")
		end,
	},
	{
		name = "cluster attacks apply configured HP damage once and never change crowd total",
		run = function()
			local run = make()
			local total, hp = run:total(), run:hp()
			local first = run:attackCluster("c1")
			assert(first.ok, "first attack")
			eq(first.before, hp, "HP before")
			eq(first.after, hp - Config.clusterTypes.small.attackDamage, "HP after")
			eq(run:hp(), first.after, "current HP")
			eq(run:total(), total, "attack leaves crowd unchanged")
			eq(run:clusterConsumption("c1"), "attacked", "consumption")
			local before = snapshot(run)
			local again = run:attackCluster("c1")
			reject(again.ok, again.reason, run, before, "repeated attack")
		end,
	},
	{
		name = "credited cluster cannot attack and forged attack events have no effect",
		run = function()
			local run = make()
			assert(run:creditCluster("c1").ok, "credit")
			local before = snapshot(run)
			local credited = run:attackCluster("c1")
			reject(credited.ok, credited.reason, run, before, "attack after credit")
			local forged = run:attackCluster("forged")
			reject(forged.ok, forged.reason, run, before, "forged attack")
		end,
	},
	{
		name = "HP zero defeats the run, clamps damage, ignores later events, and reset restores HP",
		run = function()
			local attackDamage = Config.clusterTypes.large.attackDamage
			local attackCount = math.ceil(Config.hp.max / attackDamage)
			local clusters: { RunState.ClusterDef } = {}
			for i = 1, attackCount do
				table.insert(clusters, { id = `c{i}`, type = "large" })
			end
			local run = RunState.new({
				seed = 1,
				automated = true,
				layout = { gatePairs = {}, clusters = clusters, obstacles = {} },
				startingTotal = 73,
			})
			for i = 1, attackCount do
				assert(run:attackCluster(`c{i}`).ok, `attack {i}`)
			end
			eq(run:hp(), 0, "HP clamps at zero")
			eq(run:outcome(), "defeated", "defeated outcome")
			eq(run:score(), 73, "defeat score is current crowd total")
			local before = snapshot(run)
			local later = run:attackCluster(`c{attackCount}`)
			reject(later.ok, later.reason, run, before, "attack after defeat")
			run:reset()
			eq(run:hp(), Config.hp.max, "HP reset")
			eq(run:outcome(), nil, "outcome reset")
		end,
	},
	{
		name = "obstacle: applies -Config.obstacleLoss once",
		run = function()
			local run = make()
			local r = run:hitObstacle("o1")
			assert(r.ok, "hit")
			eq(r.before, 10, "before")
			eq(r.after, 10 - Config.obstacleLoss, "after")
			local before = snapshot(run)
			for _ = 1, 3 do
				local again = run:hitObstacle("o1")
				reject(again.ok, again.reason, run, before, "repeat obstacle")
			end
		end,
	},
	{
		name = "obstacle: clamps at zero, never negative; spec 105 -> 95",
		run = function()
			local run = RunState.new({ seed = 1, automated = true, layout = layout })
			assert(run:creditCluster("c1").ok and run:creditCluster("c2").ok, "grow") -- 10+5+15=30
			assert(run:hitObstacle("o1").ok, "o1") -- 20
			assert(run:hitObstacle("o2").ok, "o2") -- 10
			eq(run:total(), 10, "total")
			local small = RunState.new({
				seed = 1,
				automated = true,
				layout = { gatePairs = {}, clusters = {}, obstacles = { { id = "x" } } },
				startingTotal = 4,
			})
			local r = small:hitObstacle("x")
			assert(r.ok, "hit")
			eq(r.before, 4, "before")
			eq(r.after, 0, "clamped")
			eq(small:total(), 0, "total")
		end,
	},
	{
		name = "obstacle: forged id rejected, no change",
		run = function()
			local run = make()
			local before = snapshot(run)
			local r = run:hitObstacle("nope")
			reject(r.ok, r.reason, run, before, "forged obstacle")
		end,
	},
	{
		name = "interleaved repeated calls apply each item exactly once",
		run = function()
			local run = make()
			for _ = 1, 3 do
				run:resolveGate("g1", -3)
				run:creditCluster("c1")
				run:hitObstacle("o1")
				run:resolveGate("g2", 3)
				run:creditCluster("c2")
				run:hitObstacle("o2")
				run:resolveGate("g1", 3)
				run:creditCluster("c1")
			end
			-- 10 +20 (g1 left)=30, +5=35, -10=25, g2 right +20=45, +15=60, -10=50
			eq(run:total(), 50, "total")
			eq(#run:events(), 1 + 6, "one event per consumed item plus run_start")
		end,
	},
	{
		name = "same id in different kinds are independent namespaces",
		run = function()
			local run = RunState.new({
				seed = 1,
				automated = true,
				layout = {
					gatePairs = {
						{
							id = "a",
							left = { x = -1, op = { kind = "add", value = 20 } },
							right = { x = 1, op = { kind = "add", value = 20 } },
						},
					},
					clusters = { { id = "a", type = "small" } },
					obstacles = { { id = "a" } },
				},
			})
			assert(run:resolveGate("a", 0).ok, "gate")
			assert(run:creditCluster("a").ok, "cluster")
			assert(run:hitObstacle("a").ok, "obstacle")
			eq(run:total(), 10 + 20 + 5 - 10, "total")
		end,
	},
	{
		name = "complete: sets outcome and score == final total; second complete rejected",
		run = function()
			local run = make()
			run:resolveGate("g1", 3)
			run:creditCluster("c2")
			local r = run:complete()
			assert(r.ok, "complete")
			eq(run:isComplete(), true, "complete")
			eq(run:outcome(), "completed", "outcome")
			eq(run:total(), 35, "total")
			eq(run:score(), run:total(), "score == total")
			eq(r.score, 35, "result score")
			local before = snapshot(run)
			local again = run:complete()
			reject(again.ok, again.reason, run, before, "double complete")
		end,
	},
	{
		name = "after completion every mutation is rejected and score stays the final total",
		run = function()
			local run = make()
			assert(run:complete().ok, "complete")
			local before = snapshot(run)
			local a = run:resolveGate("g1", 0)
			reject(a.ok, a.reason, run, before, "gate after complete")
			local b = run:creditCluster("c1")
			reject(b.ok, b.reason, run, before, "cluster after complete")
			local c = run:hitObstacle("o1")
			reject(c.ok, c.reason, run, before, "obstacle after complete")
			eq(run:score(), 10, "score")
		end,
	},
	{
		name = "session best tracks the highest completed score and survives reset",
		run = function()
			local run = make()
			run:creditCluster("c2")
			assert(run:complete().ok, "complete")
			eq(run:best(), 25, "best")
			run:reset()
			eq(run:best(), 25, "best kept across reset")
			assert(run:complete().ok, "complete low run")
			eq(run:score(), 10, "score")
			eq(run:best(), 25, "best not lowered")
			run:reset()
			run:resolveGate("g1", 3)
			run:resolveGate("g2", 3) -- 20 -> +20 = 40
			assert(run:complete().ok, "complete")
			eq(run:best(), 40, "best raised")
		end,
	},
	{
		name = "reset leaves no stale state: consumed ids usable again, total/log/outcome fresh",
		run = function()
			local run = make()
			run:resolveGate("g1", -3)
			run:creditCluster("c1")
			run:hitObstacle("o1")
			run:complete()
			run:reset()
			eq(run:total(), Config.startingTotal, "total")
			eq(run:isComplete(), false, "complete")
			eq(run:outcome(), nil, "outcome")
			eq(run:score(), nil, "score")
			eq(run:clusterConsumption("c1"), nil, "consumption")
			local ev = run:events()
			eq(#ev, 1, "log restarted")
			eq(ev[1].kind, "run_start", "first event")
			assert(run:resolveGate("g1", -3).ok, "gate usable again")
			assert(run:creditCluster("c1").ok, "cluster usable again")
			assert(run:hitObstacle("o1").ok, "obstacle usable again")
			eq(run:total(), 10 + 20 + 5 - 10, "total")
		end,
	},
	{
		name = "reset mid-run (not completed) also clears everything and can take a new seed",
		run = function()
			local run = make()
			run:resolveGate("g1", -3)
			run:reset(7)
			eq(run:total(), 10, "total")
			eq(run:seed(), 7, "seed")
			eq(run:events()[1].seed, 7, "run_start seed")
			eq(run:best(), 0, "no completed run, best stays 0")
			assert(run:resolveGate("g1", 3).ok, "gate usable again")
		end,
	},
	{
		name = "event log: ordered, seeded, timestamped, before/after totals, human flag",
		run = function()
			local run, t = make(false)
			run:resolveGate("g1", -3)
			run:creditCluster("c1")
			run:hitObstacle("o1")
			run:complete()
			local ev = run:events()
			local kinds = {}
			for _, e in ev do
				kinds[#kinds + 1] = e.kind
			end
			eq(table.concat(kinds, ","), "run_start,gate,cluster_credit,obstacle,complete", "kinds")
			local prevT = -1
			for i, e in ev do
				eq(e.index, i, "index")
				eq(e.seed, 42, "seed")
				eq(e.automated, false, "automated flag")
				assert(e.time > prevT, "timestamps increase")
				prevT = e.time
			end
			eq(ev[1].time, 101, "run_start time from injected clock")
			eq(ev[2].id, "g1", "gate id")
			eq(ev[2].side, "left", "gate side")
			eq(ev[2].before, 10, "gate before")
			eq(ev[2].after, 30, "gate after")
			eq(ev[3].before, 30, "cluster before")
			eq(ev[3].after, 35, "cluster after")
			eq(ev[4].before, 35, "obstacle before")
			eq(ev[4].after, 25, "obstacle after")
			eq(ev[5].before, 25, "complete before")
			eq(ev[5].after, 25, "complete after")
			eq(ev[5].score, 25, "complete score")
			assert(t.clock > 101, "clock used")
		end,
	},
	{
		name = "event log: automated QA session is flagged on every event",
		run = function()
			local run = make(true)
			run:creditCluster("c1")
			run:complete()
			for _, e in run:events() do
				eq(e.automated, true, "automated")
			end
		end,
	},
	{
		name = "event log: rejected calls add no event; returned log is a copy",
		run = function()
			local run = make()
			run:resolveGate("nope", 0)
			run:creditCluster("nope")
			run:hitObstacle("nope")
			eq(#run:events(), 1, "only run_start")
			local ev = run:events()
			ev[1].kind = "tampered"
			table.insert(ev, ev[1])
			eq(run:events()[1].kind, "run_start", "internal log untouched")
			eq(#run:events(), 1, "internal length untouched")
		end,
	},
	{
		name = "first_recruit and first_assembly are recorded (spec s12 Record)",
		run = function()
			local run = make()
			run:creditCluster("c1") -- 15, no section
			run:resolveGate("g1", 3) -- 30
			run:resolveGate("g2", 3) -- 50: first section
			local ev = run:events()
			local flags = {}
			for _, e in ev do
				if e.firstRecruit then
					flags[#flags + 1] = `recruit@{e.kind}`
				end
				if e.firstAssembly then
					flags[#flags + 1] = `assembly@{e.kind}`
				end
			end
			eq(table.concat(flags, ","), "recruit@cluster_credit,assembly@gate", "flags")
			eq(CrowdMath.sectionCount(run:total()), 1, "one section")
		end,
	},
	{
		name = "bad construction is rejected: negative seed type, malformed layout, duplicate ids",
		run = function()
			local function bad(opts: any, name: string)
				local ok = pcall(RunState.new, opts)
				assert(not ok, `{name}: should error`)
			end
			bad({ seed = "x", automated = true, layout = layout }, "seed type")
			bad({ seed = 1, automated = true }, "no layout")
			bad({
				seed = 1,
				automated = true,
				layout = {
					gatePairs = {},
					clusters = { { id = "a", type = "small" }, { id = "a", type = "small" } },
					obstacles = {},
				},
			}, "duplicate cluster")
			bad({
				seed = 1,
				automated = true,
				layout = {
					gatePairs = {},
					clusters = { { id = "a", type = "huge" } },
					obstacles = {},
				},
			}, "unknown cluster type")
		end,
	},
	{
		name = "total matches CrowdMath arithmetic across a long mixed sequence (no drift)",
		run = function()
			local run = make()
			local expected = Config.startingTotal
			expected = CrowdMath.applyOp(expected, layout.gatePairs[1].right.op)
			run:resolveGate("g1", 4)
			expected += Config.clusterTypes.large.reward
			run:creditCluster("c2")
			expected = CrowdMath.applyOp(expected, CrowdMath.obstacleOp())
			run:hitObstacle("o1")
			eq(run:total(), expected, "total")
			run:complete()
			eq(run:score(), expected, "score")
		end,
	},
	{
		name = "new: startingTotal must be a non-negative integer when given (never client data)",
		run = function()
			local empty = { gatePairs = {}, clusters = {}, obstacles = {} }
			for _, bad in { -1, 1.5, 0 / 0, math.huge, -math.huge, "10", true } do
				local ok = pcall(function()
					RunState.new({
						seed = 1,
						automated = true,
						layout = empty,
						startingTotal = bad :: any,
					})
				end)
				assert(not ok, `startingTotal {tostring(bad)} must be rejected`)
			end
			local zero =
				RunState.new({ seed = 1, automated = true, layout = empty, startingTotal = 0 })
			eq(zero:total(), 0, "zero allowed")
		end,
	},
}
