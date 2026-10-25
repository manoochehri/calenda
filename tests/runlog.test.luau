--!strict
local Config = require("../src/shared/Config")
local CrowdMath = require("../src/shared/CrowdMath")
local Level = require("../src/shared/Level")
local RunDriver = require("../src/shared/RunDriver")
local RunLog = require("../src/shared/RunLog")
local RunState = require("../src/shared/RunState")

-- Whole hits a parade of `total` survives to reach zero under the share rule (ADR 0006).
local function hitsToEmpty(total: number): number
	local n, t = 0, total
	while t > 0 do
		t = math.max(0, t - CrowdMath.shareLoss(t, Config.attackSharePercent, Config.minShareLoss))
		n += 1
	end
	return n
end

local DT = 1 / 30

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function makeLayout(): RunState.Layout
	return {
		gatePairs = {
			{
				id = "g1",
				left = { x = -5, op = { kind = "add", value = 15 } },
				right = { x = 5, op = { kind = "multiply", value = 2 } },
			},
			{
				id = "g2",
				left = { x = -5, op = { kind = "add", value = 30 } },
				right = { x = 5, op = { kind = "multiply", value = 3 } },
			},
		},
		clusters = {
			{ id = "c1", type = "small" },
			{ id = "c2", type = "large" },
		},
		obstacles = {
			{ id = "o1" },
		},
	}
end

local function makeRunState(
	automated: boolean,
	clockStart: number?
): (RunState.RunState, () -> number)
	local t = clockStart or 100
	local function clock()
		t += 1
		return t
	end
	local state = RunState.new({
		seed = 42,
		automated = automated,
		layout = makeLayout(),
		now = clock,
		startingTotal = 10,
	})
	return state, clock
end

-- Fixture for scripted driver run
local function driverFixture(): Level.Layout
	return {
		name = "scripted_run_fixture",
		seed = 1234,
		streetLength = 400,
		plazaStart = 200,
		halfWidth = 20,
		maxTotal = 1000,
		intendedRecruitTotal = 0,
		gates = {
			{
				id = 1,
				z = 40,
				left = { kind = "add", value = 15 },
				right = { kind = "multiply", value = 2 },
			},
			{
				id = 2,
				z = 80,
				left = { kind = "add", value = 30 },
				right = { kind = "multiply", value = 2 },
			},
		},
		obstacles = {
			{ id = 1, z = 120, side = "left" },
		},
		clusters = {
			{
				id = 1,
				wave = 1,
				type = "small",
				spawnTime = 0,
				spawn = { x = -10, z = 20 },
				path = {},
			},
		},
	}
end

return {
	{
		name = "log shape: captures seed, start, flag, gates, firstRecruit, assembly, obstacle, completion",
		run = function()
			local state, _ = makeRunState(false, 10)
			-- Initial total: 10
			-- c1 (+5) -> 15 (first recruit)
			state:creditCluster("c1")
			-- g1 left (+15) -> 30
			state:resolveGate("g1", -5)
			-- g2 left (+30) -> 60 (first assembly: 0 sections -> 1 section at >= 50)
			state:resolveGate("g2", -5)
			-- o1 (-10) -> 50
			state:hitObstacle("o1")
			-- complete
			state:complete()

			local log = RunLog.fromEvents(state:events())

			-- Top-level shape checks
			eq(log.seed, 42, "seed")
			eq(log.automated, false, "automated flag is false for human")
			assert(log.start > 0, "start timestamp recorded")

			-- First recruitment
			assert(log.firstRecruitment ~= nil, "firstRecruitment present")
			eq(log.firstRecruitment.id, "c1", "firstRecruit id")
			eq(log.firstRecruitment.before, 10, "firstRecruit before")
			eq(log.firstRecruitment.after, 15, "firstRecruit after")
			assert(log.firstRecruitment.time > log.start, "firstRecruit time after start")

			-- First assembly time
			assert(log.firstAssemblyTime ~= nil, "firstAssemblyTime present")
			assert(
				log.firstAssemblyTime >= log.firstRecruitment.time,
				"firstAssemblyTime after recruit"
			)

			-- Gates with before/after totals
			eq(#log.gates, 2, "2 gate choices")
			eq(log.gates[1].id, "g1", "g1 id")
			eq(log.gates[1].side, "left", "g1 side")
			eq(log.gates[1].before, 15, "g1 before")
			eq(log.gates[1].after, 30, "g1 after")
			eq(log.gates[2].id, "g2", "g2 id")
			eq(log.gates[2].side, "left", "g2 side")
			eq(log.gates[2].before, 30, "g2 before")
			eq(log.gates[2].after, 60, "g2 after")

			-- Obstacle losses
			eq(#log.obstacleLosses, 1, "1 obstacle loss")
			eq(log.obstacleLosses[1].id, "o1", "o1 id")
			eq(log.obstacleLosses[1].before, 60, "o1 before")
			eq(log.obstacleLosses[1].after, 50, "o1 after")
			eq(log.obstacleLosses[1].loss, Config.obstacleLoss, "loss equals Config.obstacleLoss")

			-- Completion with final total
			assert(log.completion ~= nil, "completion present")
			eq(log.completion.outcome, "completed", "completion outcome")
			eq(log.completion.finalTotal, 50, "completion finalTotal")
			eq(log.completion.score, 50, "completion score")
			assert(log.completion.time >= log.obstacleLosses[1].time, "completion time order")

			-- Replay flag on un-replayed run
			eq(log.replay, false, "replay is false initially")
			eq(log.replayCount, 0, "replayCount is 0 initially")
		end,
	},
	{
		name = "log shape: automated QA session is flagged on log",
		run = function()
			local state = makeRunState(true)
			state:complete()
			local log = RunLog.fromEvents(state:events())
			eq(log.automated, true, "automated QA flag is true")
		end,
	},
	{
		name = "log shape: chronological entries array reflects all milestones",
		run = function()
			local state = makeRunState(false, 0)
			state:creditCluster("c1")
			state:resolveGate("g1", -5)
			state:resolveGate("g2", -5)
			state:hitObstacle("o1")
			state:complete()

			local log = RunLog.fromEvents(state:events())
			assert(#log.entries >= 6, "entries array contains milestones")

			local kinds = {}
			for _, entry in log.entries do
				table.insert(kinds, entry.kind)
			end
			local summary = table.concat(kinds, ",")
			assert(string.find(summary, "start") ~= nil, "has start entry")
			assert(string.find(summary, "first_recruitment") ~= nil, "has first_recruitment entry")
			assert(string.find(summary, "gate") ~= nil, "has gate entry")
			assert(string.find(summary, "first_assembly") ~= nil, "has first_assembly entry")
			assert(string.find(summary, "obstacle") ~= nil, "has obstacle entry")
			assert(string.find(summary, "complete") ~= nil, "has complete entry")
		end,
	},
	{
		name = "replay: records replay entry, count, and updates replay flag",
		run = function()
			local state = makeRunState(false)
			state:complete()
			local log = RunLog.fromEvents(state:events(), {
				replays = { { time = 250, seed = 42 } },
			})
			eq(log.replay, true, "replay flag is true")
			eq(log.replayCount, 1, "replayCount is 1")
			eq(#log.replays, 1, "1 replay record")
			eq(log.replays[1].time, 250, "replay timestamp")
		end,
	},
	{
		name = "per-player cap: a keeper holds at most MAX_LOGS_PER_PLAYER logs, newest kept",
		run = function()
			local keeper = RunLog.newKeeper()
			local state = makeRunState(false)
			state:complete()
			local n = RunLog.MAX_LOGS_PER_PLAYER * 3
			for i = 1, n do
				local log = RunLog.fromEvents(state:events())
				log.start = i -- marker so we can tell which survived
				keeper:add("p1", log)
				assert(
					keeper:count("p1") <= RunLog.MAX_LOGS_PER_PLAYER,
					`count {keeper:count("p1")} exceeds cap after add {i}`
				)
			end
			eq(keeper:count("p1"), RunLog.MAX_LOGS_PER_PLAYER, "full at the cap")
			local kept = keeper:get("p1")
			eq(kept[#kept].start, n, "newest kept")
			eq(kept[1].start, n - RunLog.MAX_LOGS_PER_PLAYER + 1, "oldest kept is the Nth newest")
			-- a second player has an independent list
			keeper:add("p2", RunLog.fromEvents(state:events()))
			eq(keeper:count("p2"), 1, "independent per player")
		end,
	},
	{
		name = "cleanup: release frees a player's logs (PlayerRemoving)",
		run = function()
			local keeper = RunLog.newKeeper()
			local state = makeRunState(false)
			state:complete()
			keeper:add("p1", RunLog.fromEvents(state:events()))
			keeper:add("p2", RunLog.fromEvents(state:events()))
			keeper:release("p1")
			eq(keeper:count("p1"), 0, "p1 released")
			eq(#keeper:get("p1"), 0, "p1 list empty")
			eq(keeper:count("p2"), 1, "p2 untouched")
			eq(keeper:players(), 1, "one player still held")
			keeper:release("p2")
			eq(keeper:players(), 0, "nothing retained")
			keeper:release("never-seen") -- no error
		end,
	},
	{
		name = "no module-global store: RunLog exposes no store/getStored/clearStored",
		run = function()
			local raw = RunLog :: any
			eq(raw.store, nil, "no store")
			eq(raw.getStored, nil, "no getStored")
			eq(raw.clearStored, nil, "no clearStored")
		end,
	},
	{
		name = "formatting: format produces readable structured text with required elements",
		run = function()
			local state = makeRunState(true, 50)
			state:creditCluster("c1")
			state:resolveGate("g1", -5)
			state:hitObstacle("o1")
			state:complete()

			local log = RunLog.fromEvents(state:events())
			local str = RunLog.format(log)
			assert(type(str) == "string", "string returned")
			assert(string.find(str, "seed: 42") ~= nil, "contains seed")
			assert(string.find(str, "automated: true") ~= nil, "contains automated")
			assert(string.find(str, "first_recruitment") ~= nil, "contains first recruit")
			assert(string.find(str, "gate: g1") ~= nil, "contains gate")
			assert(string.find(str, "obstacle: o1") ~= nil, "contains obstacle")
			assert(string.find(str, "complete: completed") ~= nil, "contains complete")
		end,
	},
	{
		name = "scripted-run: simulated run through RunDriver asserts all structured entries and replay",
		run = function()
			local layout = driverFixture()
			local fired = false
			local simTime = 0
			local driver = RunDriver.new({
				layout = layout,
				automated = true,
				now = function()
					return simTime
				end,
				hooks = {
					shots = function(ctx)
						if not fired and ctx.t1 >= 1.0 then
							fired = true
							-- convert cluster 1 at 1.0s
							ctx.state:creditCluster("c1")
						end
					end,
				},
			})

			-- Steer to left to hit obstacle at z 120 (lane = left)
			assert(driver:steer(0.1, { x = -10 }), "steer to left")

			-- Simulate tick by tick until complete
			local totalTicks = math.ceil(15 / DT) -- ~15 seconds to reach plaza at z 200
			for _ = 1, totalTicks do
				simTime += DT
				driver:tick(DT)
				if driver:outcome() ~= nil then
					break
				end
			end

			eq(driver:outcome(), "completed", "run completed")

			-- Check driver:runLog()
			local log = driver:runLog()
			eq(log.seed, layout.seed, "seed matches fixture")
			eq(log.automated, true, "automated QA run")
			eq(log.start, 0, "start at t=0")

			-- First recruit occurred
			assert(log.firstRecruitment ~= nil, "firstRecruitment occurred")
			eq(log.firstRecruitment.id, "c1", "first recruit id is c1")

			-- Gates crossed in order
			eq(#log.gates, 2, "2 gates crossed")
			eq(log.gates[1].id, "g1", "gate 1 id")
			eq(log.gates[1].side, "left", "steered to left gate")
			eq(log.gates[2].id, "g2", "gate 2 id")

			-- First assembly time recorded
			assert(log.firstAssemblyTime ~= nil, "first assembly time recorded")

			-- Obstacle hit
			eq(#log.obstacleLosses, 1, "hit 1 obstacle")
			eq(log.obstacleLosses[1].id, "o1", "hit obstacle o1")
			eq(log.obstacleLosses[1].loss, Config.obstacleLoss, "obstacle loss matches Config")

			-- Completion recorded
			assert(log.completion ~= nil, "completion recorded")
			eq(log.completion.outcome, "completed", "completed outcome")
			eq(log.completion.finalTotal, driver:total(), "finalTotal matches driver")
			eq(log.completion.score, driver:total(), "score matches total")

			-- Now test replay on driver
			local replayTime = 20.0
			assert(driver:replay(replayTime), "replay accepted")
			eq(driver:outcome(), nil, "outcome reset after replay")

			-- No second copy of the finished run is kept; the replay is an event on the NEXT run.
			eq((driver :: any).completedLogs, nil, "driver keeps no completed-log list")
			local nextLog = driver:runLog()
			eq(nextLog.replay, true, "next run's log is flagged as following a replay")
			eq(nextLog.replayCount, 1, "next run's log replayCount is 1")
			eq(nextLog.replays[1].time, replayTime, "replay timestamp recorded")
			eq(nextLog.completion, nil, "next run has not completed")
		end,
	},
	{
		name = "replay history is capped across repeated replays",
		run = function()
			local driver = RunDriver.new({ layout = driverFixture(), automated = true })
			local replays = RunLog.MAX_LOGS_PER_PLAYER * 3
			local t = 0
			for i = 1, replays do
				for _ = 1, math.ceil(20 / DT) do
					driver:tick(DT)
					if driver:outcome() ~= nil then
						break
					end
				end
				eq(driver:outcome(), "completed", `run {i} completed`)
				t += 10 -- past the replay cooldown
				assert(driver:replay(t), `replay {i} accepted`)
				assert(
					#driver:replays() <= RunLog.MAX_LOGS_PER_PLAYER,
					`replay list {#driver:replays()} exceeds cap`
				)
			end
			eq(#driver:replays(), RunLog.MAX_LOGS_PER_PLAYER, "at the cap")
			eq(driver:replays()[#driver:replays()].time, t, "newest replay kept")
		end,
	},
	{
		name = "defeated run: fromEvents and format show the defeated outcome and score",
		run = function()
			local attackCount = hitsToEmpty(12)
			local clusters: { RunState.ClusterDef } = {}
			local ids = {}
			for i = 1, attackCount do
				table.insert(clusters, { id = `c{i}`, type = "large" })
				table.insert(ids, `c{i}`)
			end
			local state = RunState.new({
				seed = 5,
				automated = false,
				layout = { gatePairs = {}, clusters = clusters, obstacles = {} },
				startingTotal = 12,
			})
			state:attackClusters(ids)
			local log = RunLog.fromEvents(state:events())
			assert(log.completion ~= nil, "a defeated run has a completion entry")
			eq((log.completion :: RunLog.Completion).outcome, "defeated", "outcome")
			eq((log.completion :: RunLog.Completion).score, 0, "score is the total at defeat")
			eq((log.completion :: RunLog.Completion).finalTotal, 0, "final total")
			local last = log.entries[#log.entries]
			eq(last.kind, "complete", "terminal entry")
			eq(last.outcome, "defeated", "terminal entry outcome")
			assert(
				string.find(RunLog.format(log), "complete: defeated finalTotal=0 score=0", 1, true),
				"format shows the defeat"
			)
		end,
	},
	{
		name = "driver run log shows the defeat outcome (RunDriver records it)",
		run = function()
			local d = RunDriver.new({
				layout = driverFixture(),
				automated = true,
				hooks = {
					endCheck = function(ctx)
						return ctx.z1 >= 100
					end,
				},
			})
			for _ = 1, 600 do
				d:tick(DT)
				if d:outcome() ~= nil then
					break
				end
			end
			eq(d:outcome(), "defeated", "driver outcome")
			local log = d:runLog()
			assert(log.completion ~= nil, "log has a completion entry")
			eq((log.completion :: RunLog.Completion).outcome, "defeated", "log outcome")
			eq((log.completion :: RunLog.Completion).score, d:snapshot().score, "log score")
		end,
	},
}
