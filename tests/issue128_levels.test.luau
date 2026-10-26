--!strict
-- Issue #128: the level chain. Reaching a level's plaza finale moves the run to the next level in
-- Config.levelPlayOrder; the crowd total carries over; the last finale and defeat end the run.
-- LevelChain and the `levels` option are required inside each case, so before the change each case
-- fails with its own message instead of the whole runner aborting when this file loads.
local Config = require("../src/shared/Config")
local CrowdMath = require("../src/shared/CrowdMath")
local DebugLayout = require("../src/shared/DebugLayout")
local Level = require("../src/shared/Level")
local RunDriver = require("../src/shared/RunDriver")

local DT = RunDriver.TICK_DT

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

-- Level A: a gate at z 64 (left add 15, right multiply 2), one small cluster "c1", plaza at z 320.
local function levelA(): Level.Layout
	return {
		name = "level-a",
		seed = 1,
		streetLength = 400,
		plazaStart = 320,
		halfWidth = 20,
		maxTotal = 1000,
		intendedRecruitTotal = 0,
		gates = {
			{
				id = 1,
				z = 64,
				left = { kind = "add", value = 15 },
				right = { kind = "multiply", value = 2 },
			},
		},
		obstacles = {},
		clusters = {
			{
				id = 1,
				wave = 1,
				type = "small",
				spawnTime = 0,
				spawn = { x = -16, z = 200 },
				path = {},
			},
		},
	}
end

-- Level B: its own gate at z 64 (left multiply 2, right add 1000), its own cluster "c2", plaza at z 320.
local function levelB(): Level.Layout
	return {
		name = "level-b",
		seed = 2,
		streetLength = 400,
		plazaStart = 320,
		halfWidth = 20,
		maxTotal = 1000,
		intendedRecruitTotal = 0,
		gates = {
			{
				id = 1,
				z = 64,
				left = { kind = "multiply", value = 2 },
				right = { kind = "add", value = 1000 },
			},
		},
		obstacles = {},
		clusters = {
			{
				id = 2,
				wave = 1,
				type = "small",
				spawnTime = 0,
				spawn = { x = -16, z = 200 },
				path = {},
			},
		},
	}
end

-- Ticks until `done` is true (or a safety cap), collecting every event.
local function runUntil(d: any, done: () -> boolean, maxSeconds: number?): { any }
	local all = {}
	for _ = 1, math.ceil((maxSeconds or 300) / DT) do
		if done() then
			break
		end
		for _, e in d:tick(DT) do
			table.insert(all, e)
		end
	end
	return all
end

local function chain(hooks: any?): any
	local RD = require("../src/shared/RunDriver")
	local first = levelA()
	return RD.new({ layout = first, levels = { first, levelB() }, automated = true, hooks = hooks })
end

local function countKind(events: { any }, kind: string): number
	local n = 0
	for _, e in events do
		if e.kind == kind then
			n += 1
		end
	end
	return n
end

local function firstOfKind(events: { any }, kind: string): any?
	for _, e in events do
		if e.kind == kind then
			return e
		end
	end
	return nil
end

local cases = {}

table.insert(cases, {
	name = "config: the play order is one level, the Oaxacan street",
	run = function()
		eq(#Config.levelPlayOrder, 1, "levelPlayOrder length")
		eq(Config.levelPlayOrder[1], "oaxacan-street", "levelPlayOrder[1]")
	end,
})

table.insert(cases, {
	name = "LevelChain: ids map to layouts in order; bad orders are refused",
	run = function()
		local LevelChain = require("../src/shared/LevelChain")
		local a, b = levelA(), levelB()
		local resolved = LevelChain.resolve({ "b", "a" }, { a = a, b = b })
		eq(#resolved, 2, "resolved length")
		eq(resolved[1], b, "first resolved level")
		eq(resolved[2], a, "second resolved level")
		local catalog = { ["oaxacan-street"] = DebugLayout }
		eq(LevelChain.resolve(Config.levelPlayOrder, catalog)[1], DebugLayout, "real play order")
		local function refused(order: { string }, cat: any): boolean
			return not pcall(LevelChain.resolve, order, cat)
		end
		assert(refused({}, catalog), "an empty play order must be refused")
		assert(refused({ "missing" }, catalog), "an unknown level id must be refused")
		assert(refused({ "a", "a" }, { a = a }), "a repeated level id must be refused")
	end,
})

table.insert(cases, {
	name = "one-level chain: the run completes at the finale as before",
	run = function()
		local RD = require("../src/shared/RunDriver")
		local only = levelA()
		local d = RD.new({ layout = only, levels = { only }, automated = true })
		runUntil(d, function()
			return d:outcome() ~= nil
		end)
		eq(d:outcome(), "completed", "outcome")
		eq(d:snapshot().level, 1, "level")
	end,
})

table.insert(cases, {
	name = "level 1 finale moves the run to level 2 and keeps the crowd total exact",
	run = function()
		local d = chain()
		local before = d:total()
		runUntil(d, function()
			return d:snapshot().level == 2
		end)
		eq(d:snapshot().level, 2, "level after level 1's finale")
		eq(d:outcome(), nil, "run is still going")
		eq(d:snapshot().phase, "running", "phase")
		-- Level A's only change is its gate (left add 15, the lead at x 0 takes the left side).
		eq(d:total(), CrowdMath.applyOp(before, { kind = "add", value = 15 }), "carried total")
	end,
})

table.insert(cases, {
	name = "level 2 has its own gates and clusters, starting from the carried total",
	run = function()
		local probe: any = { done = false }
		local hooks = {
			shots = function(ctx: any)
				if ctx.layout.name == "level-b" and not probe.done then
					probe.done = true
					probe.unknown = ctx.state:creditCluster("c1")
					probe.own = ctx.state:creditCluster("c2")
				end
			end,
		}
		local d = chain(hooks)
		runUntil(d, function()
			return d:snapshot().level == 2
		end)
		-- Only the events after the finale: level 1's gate is not level 2's.
		local events = runUntil(d, function()
			return probe.own ~= nil and countKind(d:events(), "gate") >= 2
		end, 120)
		assert(probe.own ~= nil, "level 2's own cluster was never probed")
		eq(probe.unknown.ok, false, "level 1's cluster id is unknown in level 2")
		eq(probe.unknown.reason, "unknown cluster", "rejection reason")
		eq(probe.own.ok, true, "level 2's own cluster is credited")
		local gate = firstOfKind(events, "gate")
		assert(gate ~= nil, "level 2 gate event missing")
		eq(gate.before, probe.own.after, "gate starts from the carried total plus the cluster")
		eq(
			gate.after,
			CrowdMath.applyOp(gate.before, { kind = "multiply", value = 2 }),
			"level 2 gate op"
		)
	end,
})

table.insert(cases, {
	name = "the last level's finale ends the run, completed, and does not advance",
	run = function()
		local d = chain()
		local events = runUntil(d, function()
			return d:outcome() ~= nil
		end)
		eq(d:outcome(), "completed", "outcome")
		eq(d:snapshot().level, 2, "level stays at the last level")
		eq(countKind(events, "complete"), 1, "one complete event")
		eq(d:snapshot().score, d:total(), "score is the final crowd total")
	end,
})

table.insert(cases, {
	name = "defeat before a finale ends the run and does not advance",
	run = function()
		local hooks = {
			endCheck = function(ctx: any): boolean
				return ctx.t1 >= 2
			end,
		}
		local d = chain(hooks)
		runUntil(d, function()
			return d:outcome() ~= nil
		end)
		eq(d:outcome(), "defeated", "outcome")
		eq(d:snapshot().level, 1, "level stays at level 1")
	end,
})

table.insert(cases, {
	name = "replay resets to the first level of the play order",
	run = function()
		local d = chain()
		runUntil(d, function()
			return d:outcome() ~= nil
		end)
		eq(d:snapshot().level, 2, "level before replay")
		assert(d:replay(100), "replay after the run ends must be accepted")
		eq(d:snapshot().level, 1, "level after replay")
		eq(d:total(), CrowdMath.startingTotal(), "replay restores the starting total")
		local events = runUntil(d, function()
			return countKind(d:events(), "gate") >= 1
		end, 60)
		local gate = firstOfKind(events, "gate")
		assert(gate ~= nil, "level 1 gate after replay missing")
		eq(gate.id, 1, "gate id after replay")
		eq(gate.before, CrowdMath.startingTotal(), "gate starts from the starting total")
		eq(
			gate.after,
			CrowdMath.applyOp(gate.before, { kind = "add", value = 15 }),
			"level 1 gate op"
		)
	end,
})

local results = {}
for _, c in cases do
	table.insert(results, { name = c.name, run = c.run })
end
return results
