--!strict
-- Headless bot over the REAL RunDriver + RunHooks (issue #17). Plays the fixed DebugLayout and
-- the spec s12 numeric scenarios end to end. Failing assertions print the event log.
-- These tests state facts and invariants (timing, totals, log contents); they do NOT assert that
-- the layout is balanced or that the player has to react (an owner decision; see tests/ladder.luau).
local Config = require("../src/shared/Config")
local CrowdMath = require("../src/shared/CrowdMath")
local DebugLayout = require("../src/shared/DebugLayout")
local Level = require("../src/shared/Level")
local VisualBudget = require("../src/shared/VisualBudget")
local BotHarness = require("./helpers/BotHarness")
local Ladder = require("./helpers/Ladder")

local check = BotHarness.check

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function scripted(): BotHarness.Policy
	return BotHarness.policy("scripted", 1)
end

local function layoutOf(
	gates: { Level.Gate },
	obstacles: { Level.Obstacle },
	clusters: { Level.Cluster }?
): Level.Layout
	return {
		name = "issue17-synthetic",
		seed = 17,
		streetLength = 500,
		plazaStart = 400,
		halfWidth = 20,
		maxTotal = 100000,
		intendedRecruitTotal = 0,
		gates = gates,
		obstacles = obstacles,
		clusters = clusters or {},
	}
end

local noop = { kind = "add", value = 0 }
local function gate(id: number, z: number, rightValue: number, kind: string?): Level.Gate
	return {
		id = id,
		z = z,
		left = noop :: Level.Op,
		right = { kind = kind or "add", value = rightValue } :: Level.Op,
	}
end

local function goRight(): BotHarness.Policy
	return BotHarness.policy("always-right", 1)
end

-- Walks the run log: each event's `before` must equal the previous event's `after`, and each
-- change must equal the independently recomputed operation. Returns the number of changes seen.
local function checkTotalsChain(result: BotHarness.Result, layout: Level.Layout)
	local running = Config.startingTotal
	local changes = 0
	for _, e in result.events do
		if e.kind == "gate" then
			local gateDef
			for _, g in layout.gates do
				if `g{g.id}` == e.id then
					gateDef = g
				end
			end
			check(gateDef ~= nil, `unknown gate {tostring(e.id)}`, result)
			local op = if e.side == "left" then gateDef.left else gateDef.right
			check(e.before == running, `gate {e.id} before {e.before} ~= running {running}`, result)
			check(
				e.after == CrowdMath.applyOp(running, op),
				`gate {e.id} after {e.after} ~= applyOp`,
				result
			)
			running = e.after
			changes += 1
		elseif e.kind == "cluster_credit" then
			local def = Config.clusterTypes[(Level.findCluster(
				layout,
				tonumber(string.sub(e.id :: string, 2)) :: number
			)).type]
			check(
				e.before == running,
				`credit {e.id} before {e.before} ~= running {running}`,
				result
			)
			check(e.after == running + def.reward, `credit {e.id} after {e.after}`, result)
			running = e.after
			changes += 1
		elseif e.kind == "obstacle" then
			check(e.before == running, `obstacle {e.id} before ~= running`, result)
			check(
				e.after == CrowdMath.applyOp(running, CrowdMath.obstacleOp()),
				"obstacle after",
				result
			)
			running = e.after
			changes += 1
		elseif e.kind == "hazard_hit" then
			-- A tomato (ADR 0006): removes a share of the parade before the hit, clamped at zero.
			check(e.before == running, "tomato starts from the running total", result)
			local tomato =
				CrowdMath.shareLoss(running, Config.hazards.tomatoSharePercent, Config.minShareLoss)
			check(
				e.after == math.max(0, running - tomato),
				"a tomato removes its share of the parade, clamped at zero",
				result
			)
			running = e.after
			changes += 1
		elseif e.kind == "cluster_attack" then
			-- ADR 0006: an unconverted horde removes attackSharePercent of the parade before the hit.
			local known = false
			for _, c in layout.clusters do
				if `c{c.id}` == e.id then
					known = true
				end
			end
			check(known, `attack on unknown cluster {tostring(e.id)}`, result)
			check(e.before == running, "attack starts from the running total", result)
			local loss =
				CrowdMath.shareLoss(running, Config.attackSharePercent, Config.minShareLoss)
			check(
				e.after == math.max(0, running - loss),
				"an attack removes its share of the parade, clamped at zero",
				result
			)
			running = e.after
			changes += 1
		end
	end
	check(running == result.total, `chain ends at {running}, total {result.total}`, result)
	return changes
end

local function attackedIds(result: BotHarness.Result): { [number]: number }
	local counts: { [number]: number } = {}
	for _, a in result.attacks do
		counts[a.id] = (counts[a.id] or 0) + 1
	end
	return counts
end

return {
	{
		name = "scripted bot completes the fixed layout in ~90 s with followers left",
		run = function()
			for _, hz in { 30, 60 } do
				local r = BotHarness.play(DebugLayout, scripted(), { hz = hz })
				check(r.outcome == "completed", `{hz} Hz: outcome {tostring(r.outcome)}`, r)
				check(math.abs(r.time - 90) <= 1, `{hz} Hz: simulated time {r.time}`, r)
				check(r.total > 0, `{hz} Hz: followers left {r.total}`, r)
			end
		end,
	},
	{
		name = "first section forms by ~25 s and the first recruit comes early",
		run = function()
			local r = BotHarness.play(DebugLayout, scripted())
			local log = r.runLog
			check(log.firstAssemblyTime ~= nil, "no first assembly in the log", r)
			check(
				(log.firstAssemblyTime :: number) <= 25,
				`first section at {log.firstAssemblyTime}`,
				r
			)
			check(log.firstRecruitment ~= nil, "no first recruit", r)
			check((log.firstRecruitment :: any).time <= 25, "first recruit after 25 s", r)
		end,
	},
	{
		name = "expected totals at every event (chained and recomputed from the layout ops)",
		run = function()
			for _, hz in { 30, 60 } do
				for _, name in { "scripted", "always-right", "always-left", "none" } do
					local r = BotHarness.play(DebugLayout, BotHarness.policy(name, 1), { hz = hz })
					checkTotalsChain(r, DebugLayout)
				end
			end
			local r = BotHarness.play(DebugLayout, scripted())
			eq(
				checkTotalsChain(r, DebugLayout) >= #DebugLayout.gates,
				true,
				"gates and credits seen"
			)
			eq(#r.runLog.gates, #DebugLayout.gates, "all 7 gate pairs logged exactly once")
		end,
	},
	{
		name = "score equals the final crowd total, in the snapshot and in the log",
		run = function()
			local r = BotHarness.play(DebugLayout, scripted())
			eq(r.score, r.total, "snapshot score")
			local c = r.runLog.completion :: any
			check(c ~= nil, "no completion in the log", r)
			eq(c.outcome, "completed", "log outcome")
			eq(c.finalTotal, r.total, "log finalTotal")
			eq(c.score, r.total, "log score")
		end,
	},
	{
		name = "replay restarts clean and the same bot repeats the same run",
		run = function()
			local run = BotHarness.newRun(DebugLayout)
			local first = BotHarness.play(DebugLayout, scripted(), { run = run })
			eq(first.outcome, "completed", "first run outcome")
			eq(run.driver:replay(run.clock.session + 2), true, "replay accepted after the end")
			local s = run.driver:snapshot()
			eq(s.time, 0, "time")
			eq(s.z, 0, "z")
			eq(s.x, 0, "x")
			eq(s.total, Config.startingTotal, "total")
			eq((s :: any).hp, nil, "no HP in the snapshot (ADR 0006)")
			eq(s.outcome, nil, "outcome cleared")
			eq(s.score, nil, "score cleared")
			eq(s.best, first.total, "session best survives the replay")
			eq(#run.driver:events(), 1, "log holds only the new run_start")
			local second = BotHarness.play(DebugLayout, scripted(), { run = run })
			eq(second.outcome, first.outcome, "second outcome")
			eq(second.total, first.total, "second total")
			eq(#second.events, #first.events, "second event count")
			eq(#run.driver:replays(), 1, "one replay recorded")
		end,
	},
	{
		name = "replay is refused mid-run",
		run = function()
			local run = BotHarness.newRun(DebugLayout)
			run.driver:tick(1 / 30)
			eq(run.driver:replay(50), false, "refused while the run is live")
		end,
	},
	{
		name = "no-input run: every horde that reached the parade removed its share; the total chain holds",
		-- OPEN (issue #121, spec Amendment 4 Balance): with fixed per-hit losses the no-input run is
		-- NOT defeated on the debug layout (its total grows to ~800 from recruits and gates). That
		-- balance check is therefore not asserted here; the defeat mechanism is tested in
		-- issue121_life.test.luau. The owner decides the loss rule before this check can be restored.
		run = function()
			for _, hz in { 30, 60 } do
				local r = BotHarness.play(DebugLayout, BotHarness.policy("none", 1), { hz = hz })
				check(#r.attacks > 0, "the no-input run is attacked", r)
				check(checkTotalsChain(r, DebugLayout) >= 0, "chain", r)
				if r.outcome == "defeated" then
					local c = r.runLog.completion :: any
					check(c ~= nil and c.outcome == "defeated", "log must record defeated", r)
					eq(r.driver:snapshot().best, 0, "defeat does not set the session best")
				end
			end
		end,
	},
	{
		name = "a completed run records the plaza and sets the session best",
		run = function()
			local r = BotHarness.play(DebugLayout, scripted())
			local c = r.runLog.completion :: any
			eq(c.outcome, "completed", "outcome")
			check(c.time >= 89 and c.time <= 91, `completion time {c.time}`, r)
			eq(r.driver:snapshot().best, r.total, "best == score for a completed run")
		end,
	},
	{
		name = "run log has seed, gate choices with before/after, first recruit, first assembly, obstacle loss, completion",
		run = function()
			-- always-right is chosen because it drives into the right-hand obstacle (o2 at 64 s).
			local r = BotHarness.play(DebugLayout, goRight())
			local log = r.runLog
			eq(log.seed, DebugLayout.seed, "seed")
			eq(log.automated, true, "automated flag")
			eq(#log.gates, #DebugLayout.gates, "gate choices")
			for _, g in log.gates do
				check(g.side == "right", `gate {g.id} side {g.side}`, r)
				check(type(g.before) == "number" and type(g.after) == "number", "before/after", r)
			end
			check(log.firstRecruitment ~= nil, "first recruit", r)
			check(log.firstAssemblyTime ~= nil, "first assembly", r)
			eq(#log.obstacleLosses >= 1, true, "an obstacle loss is logged")
			eq(log.obstacleLosses[1].loss, Config.obstacleLoss, "obstacle loss amount")
			check(log.completion ~= nil, "completion", r)
			local kinds: { [string]: boolean } = {}
			for _, e in log.entries do
				kinds[e.kind] = true
			end
			for _, k in
				{ "start", "gate", "first_recruitment", "first_assembly", "obstacle", "complete" }
			do
				check(kinds[k] == true, `entries lack {k}`, r)
			end
		end,
	},
	{
		name = "moving clusters: the first unconverted attack happens when the cluster's time-based position reaches the lead",
		run = function()
			local r = BotHarness.play(DebugLayout, BotHarness.policy("none", 1))
			check(#r.attacks >= 1, "no attack in the no-input run", r)
			local a = r.attacks[1]
			-- Level says cluster `a.id` is at or behind the lead from tReach on; the driver must attack on
			-- the tick that contains tReach (within one tick).
			local tReach
			for k = 0, 12000 do -- 20 s: the first no-input attack is later at the 6/s rate (ADR 0004)
				local t = k / 600
				if Level.clusterPosition(DebugLayout, a.id, t).z <= Level.leadZ(t) then
					tReach = t
					break
				end
			end
			check(tReach ~= nil, "cluster never reaches the lead", r)
			check(
				math.abs(a.time - tReach) <= 1 / 30 + 1e-6,
				`attack at {a.time}, level says {tReach}`,
				r
			)
		end,
	},
	{
		name = "missed wave: an unconverted cluster attacks once, never credits, never lowers the total",
		run = function()
			-- Three clusters arrive together; base fire (6/s, one target at a time, ADR 0004) cannot convert
			-- all of them: 3 + 3 + 8 hits need 2.3 s, they reach the lead in under 2 s.
			local clusters: { Level.Cluster } = {}
			for i = 1, 3 do
				table.insert(clusters, {
					id = i,
					wave = 1,
					type = if i == 1 then "large" else "small",
					spawnTime = 0,
					spawn = { x = if i == 2 then 16 else -16, z = 40 + i },
					path = {},
				})
			end
			local layout = layoutOf({}, {}, clusters)
			local r = BotHarness.play(layout, BotHarness.policy("none", 1))
			local credited: { [string]: boolean } = {}
			for _, e in r.events do
				if e.kind == "cluster_credit" then
					credited[e.id :: string] = true
				end
			end
			check(#r.attacks >= 1, "expected at least one missed wave", r)
			local counts = attackedIds(r)
			for _, a in r.attacks do
				check(counts[a.id] == 1, `cluster {a.id} attacked {counts[a.id]} times`, r)
				check(credited[`c{a.id}`] == nil, `cluster {a.id} attacked AND was credited`, r)
			end
			-- Replay in event order: each credit adds its reward, each attack takes its share of the
			-- total before that attack (ADR 0006). No gates or obstacles in this layout.
			local rewardOf = {}
			for _, cl in clusters do
				rewardOf[`c{cl.id}`] = Config.clusterTypes[cl.type].reward
			end
			local expected = Config.startingTotal
			for _, e in r.events do
				if e.kind == "cluster_credit" then
					expected += rewardOf[e.id :: string]
				elseif e.kind == "cluster_attack" then
					expected = math.max(
						0,
						expected
							- CrowdMath.shareLoss(
								expected,
								Config.attackSharePercent,
								Config.minShareLoss
							)
					)
				end
			end
			eq(
				r.total,
				expected,
				"total = start + credits - each missed cluster's share at its attack (ADR 0006)"
			)
		end,
	},
	{
		name = "spec s12 end to end: 49 + 1 = 50 forms one section with no loss",
		run = function()
			local layout = layoutOf({ gate(1, 100, 39), gate(2, 200, 1) }, {})
			local r = BotHarness.play(layout, goRight())
			eq(r.runLog.gates[1].after, 49, "after +39")
			eq(CrowdMath.sectionCount(49), 0, "49 has no section")
			eq(r.runLog.gates[2].before, 49, "before +1")
			eq(r.runLog.gates[2].after, 50, "49 + 1")
			eq(CrowdMath.sectionCount(50), 1, "one section")
			eq(CrowdMath.looseFollowers(50), 0, "no loose follower, no value lost")
			eq(r.total, 50, "final total")
			eq(r.score, 50, "score")
			check(r.runLog.firstAssemblyTime ~= nil, "first assembly recorded at the +1 gate", r)
			eq(
				r.runLog.firstAssemblyTime,
				r.runLog.gates[2].time,
				"assembly time is the +1 gate's time"
			)
		end,
	},
	{
		name = "spec s12 end to end: 120 x2 = 240",
		run = function()
			local layout = layoutOf({ gate(1, 100, 110), gate(2, 200, 2, "multiply") }, {})
			local r = BotHarness.play(layout, goRight())
			eq(r.runLog.gates[1].after, 120, "10 + 110")
			eq(r.runLog.gates[2].before, 120, "before x2")
			eq(r.runLog.gates[2].after, 240, "120 x 2")
			eq(r.total, 240, "total")
			eq(r.score, 240, "score")
		end,
	},
	{
		name = "spec s12 end to end: 105 - 10 = 95 and the section visuals update",
		run = function()
			-- 10 + 95 = 105 (2 sections, 5 loose), then the right-hand obstacle at z 300 removes 10.
			local layout = layoutOf({ gate(1, 100, 95) }, { { id = 1, z = 300, side = "right" } })
			local r = BotHarness.play(layout, goRight())
			eq(r.runLog.gates[1].after, 105, "105")
			eq(r.runLog.obstacleLosses[1].before, 105, "before the obstacle")
			eq(r.runLog.obstacleLosses[1].after, 95, "105 - 10")
			eq(r.total, 95, "total")
			local before, after = VisualBudget.allocate(105), VisualBudget.allocate(95)
			eq(before.logicalSections, 2, "105 = 2 sections")
			eq(after.logicalSections, 1, "95 = 1 section")
			eq(after.looseCount, 45, "95 = 1 section + 45 loose")
			eq(CrowdMath.crossings(105, 95).direction, "down", "a section disperses")
		end,
	},
	{
		name = "spec s12 end to end: a synthetic 10,000 keeps the counter exact and respects visual budgets",
		run = function()
			local layout = layoutOf({ gate(1, 100, 9990) }, {})
			local r = BotHarness.play(layout, goRight())
			eq(r.total, 10000, "total")
			eq(r.score, 10000, "score")
			local plan = VisualBudget.allocate(r.total)
			eq(plan.logicalSections, 200, "sections")
			eq(plan.looseCount, 0, "loose")
			eq(
				#plan.representatives <= Config.visualBudget.sectionRepresentatives,
				true,
				"representatives"
			)
			eq(plan.looseAvatars <= Config.visualBudget.looseAvatars, true, "loose avatars")
			local stacked = 0
			for _, rep in plan.representatives do
				stacked += rep.count
			end
			eq(stacked, 200, "stacks account for every section")
		end,
	},
	{
		name = "perturbation: same seed gives the same layout; gates, obstacles and sides are unchanged",
		run = function()
			local a, b = BotHarness.perturb(DebugLayout, 5), BotHarness.perturb(DebugLayout, 5)
			local c = BotHarness.perturb(DebugLayout, 6)
			local differs = false
			for i, cl in a.clusters do
				eq(cl.spawnTime, b.clusters[i].spawnTime, "same seed spawnTime")
				eq(cl.spawn.z, b.clusters[i].spawn.z, "same seed spawn z")
				eq(cl.spawn.x, DebugLayout.clusters[i].spawn.x, "side unchanged")
				if cl.spawnTime ~= c.clusters[i].spawnTime then
					differs = true
				end
			end
			eq(differs, true, "a different seed moves clusters")
			eq(#a.gates, #DebugLayout.gates, "gates")
			eq(a.gates[3].z, DebugLayout.gates[3].z, "gate z")
			eq(a.obstacles[2].z, DebugLayout.obstacles[2].z, "obstacle z")
		end,
	},
	{
		name = "ladder smoke (fixed layout, 30 Hz, 5 seeds per random policy): runs, every row is well formed",
		run = function()
			local text = Ladder.report(Ladder.SMOKE)
			assert(string.find(text, "scripted", 1, true), "ladder lists the scripted policy")
			assert(
				string.find(text, "no balance claim", 1, true),
				"ladder states it makes no claim"
			)
			print(text)
		end,
	},
}
