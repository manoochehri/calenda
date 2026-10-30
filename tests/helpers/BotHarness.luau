--!strict
-- Headless bot harness (issue #17). Plays a layout through the REAL RunDriver + RunHooks (the
-- same code path as src/server/RunServer.server.luau; no Roblox APIs) and returns what happened.
-- Test-only: lives under tests/, is not loaded by the game. Nothing here asserts balance; it
-- produces evidence (policy outcomes) and the event log that failing assertions print.
local Config = require("../../src/shared/Config")
local CrowdMath = require("../../src/shared/CrowdMath")
local Level = require("../../src/shared/Level")
local RunDriver = require("../../src/shared/RunDriver")
local RunHooks = require("../../src/shared/RunHooks")
local RunLog = require("../../src/shared/RunLog")
local RunState = require("../../src/shared/RunState")

local BotHarness = {}

export type View = {
	time: number,
	z: number,
	x: number,
	total: number,
	layout: Level.Layout,
}
-- decide returns the lateral target to steer to, or nil to send no steer message this decision.
export type Policy = {
	name: string,
	period: number, -- seconds between decisions (0 = never decides)
	decide: (view: View) -> number?,
}
export type Attack = { id: number, kind: string, time: number, before: number, after: number }
export type Result = {
	policy: string,
	outcome: string?,
	time: number, -- simulated seconds when the run ended (or maxSeconds)
	total: number,
	score: number?,
	trajectory: { { time: number, total: number } }, -- every change of the crowd total
	attacks: { Attack },
	credits: number,
	events: { RunState.Event },
	runLog: RunLog.StructuredLog,
	driver: RunDriver.RunDriver,
}
export type PlayOptions = {
	hz: number?, -- tick rate, default 30
	maxSeconds: number?, -- default 100
	run: Run?, -- reuse an earlier run's driver (e.g. after replay); default a fresh one
}
-- A driver plus the simulated clock that stamps its run-log events.
-- `t` is run time (event stamps); `session` never goes backwards across replays (steer/replay clock).
export type Run = { driver: RunDriver.RunDriver, clock: { t: number, session: number } }

local SIDE = 10 -- lane center |x| (ADR 0011), where the authored outer-lane waves approach

-- Deterministic LCG (no os/time dependence). Returns a function giving floats in [0, 1).
function BotHarness.rng(seed: number): () -> number
	local s = (seed * 2654435761 + 12345) % 4294967296
	local function next(): number
		s = (s * 1664525 + 1013904223) % 4294967296
		return s / 4294967296
	end
	for _ = 1, 8 do
		next()
	end
	return next
end

local function sideX(positive: boolean): number
	return if positive then SIDE else -SIDE
end

-- Cluster info the scripted controllers read (positions are the level's time-based positions).
local function nearest(view: View, largeOnly: boolean): Level.Cluster?
	local best: Level.Cluster? = nil
	local bestDist = math.huge
	for _, c in view.layout.clusters do
		if view.time >= c.spawnTime and (not largeOnly or c.type == "large") then
			local d = Level.clusterPosition(view.layout, c.id, view.time).z - view.z
			if d > 0 and d < bestDist then
				best, bestDist = c, d
			end
		end
	end
	return best
end

-- Gate preference from tests/layoutvalidator.test.luau: within 1.25 s of a gate, take the larger result.
local function gateTarget(view: View): number?
	for _, g in view.layout.gates do
		local d = g.z - view.z
		if d > 0 and d <= Config.speed * 1.25 then
			local left = CrowdMath.applyOp(view.total, g.left)
			local right = CrowdMath.applyOp(view.total, g.right)
			return sideX(right > left)
		end
	end
	return nil
end

local function clusterSide(c: Level.Cluster?): number
	if c == nil then
		return 0
	end
	return sideX(c.spawn.x >= 0)
end

-- The scripted controller of tests/layoutvalidator.test.luau, reproduced faithfully (decided every
-- 0.05 s): nearest large else nearest any ahead, then the gate preference. Quirk kept on purpose
-- so the numbers match the validator's: its "nearest large" has no distance > 0 test, so it picks
-- the large cluster with the smallest SIGNED distance, which can be one already passed.
local function scripted(view: View): number
	local anyAhead: Level.Cluster? = nil
	local anyDist = math.huge
	local large: Level.Cluster? = nil
	local largeDist = math.huge
	for _, c in view.layout.clusters do
		if view.time >= c.spawnTime then
			local d = Level.clusterPosition(view.layout, c.id, view.time).z - view.z
			if d > 0 and d < anyDist then
				anyAhead, anyDist = c, d
			end
			if c.type == "large" and d < largeDist then
				large, largeDist = c, d
			end
		end
	end
	return gateTarget(view) or clusterSide(large or anyAhead)
end

-- Same plan but "nearest large" only counts clusters still ahead of the lead.
local function scriptedAheadOnly(view: View): number
	local c = nearest(view, true) or nearest(view, false)
	return gateTarget(view) or clusterSide(c)
end

-- A policy is built per run (some carry a seeded RNG), so factories take the seed.
function BotHarness.policies(seed: number): { Policy }
	local r = BotHarness.rng(seed)
	local alt = false
	local lastCheck, lapseUntil, lapseX = 0, 0, 0
	return {
		{
			name = "none",
			period = 0,
			decide = function()
				return nil
			end,
		},
		{
			name = "always-center",
			period = 0.5,
			decide = function()
				return 0
			end,
		},
		{
			name = "always-left",
			period = 0.5,
			decide = function()
				return -SIDE
			end,
		},
		{
			name = "always-right",
			period = 0.5,
			decide = function()
				return SIDE
			end,
		},
		{
			name = "alternate-2.5s",
			period = 2.5,
			decide = function()
				alt = not alt
				return sideX(alt)
			end,
		},
		{
			name = "random-side-0.5s",
			period = 0.5,
			decide = function()
				return sideX(r() < 0.5)
			end,
		},
		{
			name = "nearest-cluster-only",
			period = 0.05,
			decide = function(view)
				return clusterSide(nearest(view, false))
			end,
		},
		{
			name = "nearest-large-only",
			period = 0.05,
			decide = function(view)
				return clusterSide(nearest(view, true))
			end,
		},
		{
			name = "nearest-any+gate-pref",
			period = 0.05,
			decide = function(view)
				return gateTarget(view) or clusterSide(nearest(view, false))
			end,
		},
		{
			name = "scripted",
			period = 0.05,
			decide = scripted,
		},
		{
			name = "scripted-ahead-only",
			period = 0.05,
			decide = scriptedAheadOnly,
		},
		{
			-- Scripted, but every 0.25 s it lapses with probability 0.25: it ignores the plan and holds
			-- a random side for 0.5 s (a distracted player). Seeded.
			name = "noisy-scripted",
			period = 0.05,
			decide = function(view)
				if view.time >= lapseUntil - 1e-9 and view.time - lastCheck >= 0.25 - 1e-9 then
					lastCheck = view.time
					if r() < 0.25 then
						lapseUntil = view.time + 0.5
						lapseX = sideX(r() < 0.5)
					end
				end
				if view.time < lapseUntil - 1e-9 then
					return lapseX
				end
				return scripted(view)
			end,
		},
	}
end

function BotHarness.policy(name: string, seed: number): Policy
	for _, p in BotHarness.policies(seed) do
		if p.name == name then
			return p
		end
	end
	error(`unknown policy {name}`)
end

-- A fresh production-wired driver: real RunDriver + real RunHooks, as RunServer builds them. The
-- event clock is the simulated clock, so run-log times are simulated seconds.
function BotHarness.newRun(layout: Level.Layout): Run
	local clock = { t = 0, session = 0 }
	local driver = RunDriver.new({
		layout = layout,
		automated = true,
		hooks = RunHooks.new(layout),
		now = function()
			return clock.t
		end,
	})
	return { driver = driver, clock = clock }
end

-- Plays a run (a fresh one, or opts.run again after a replay) until it ends or maxSeconds pass.
function BotHarness.play(layout: Level.Layout, policy: Policy, opts: PlayOptions?): Result
	local o = opts or {}
	local hz = o.hz or 30
	local dt = 1 / hz
	local maxSeconds = o.maxSeconds or 100
	local run = o.run or BotHarness.newRun(layout)
	local driver = run.driver
	local snap = driver:snapshot()
	local trajectory = { { time = snap.time, total = snap.total } }
	local attacks: { Attack } = {}
	local credits = 0
	local nextDecision = 0
	for _ = 1, math.ceil(maxSeconds * hz) do
		snap = driver:snapshot()
		run.clock.t = snap.time + dt
		run.clock.session += dt
		if policy.period > 0 and snap.time >= nextDecision - 1e-9 then
			local view: View = {
				time = snap.time,
				z = snap.z,
				x = snap.x,
				total = snap.total,
				layout = layout,
			}
			local target = policy.decide(view)
			if target ~= nil then
				driver:steer(run.clock.session, { x = target })
			end
			nextDecision = snap.time + policy.period
		end
		local before = snap.total
		for _, e in driver:tick(dt) do
			if e.kind == "attack" then
				local c = Level.findCluster(layout, e.id :: number)
				table.insert(attacks, {
					id = c.id,
					kind = c.type,
					time = driver:snapshot().time,
					before = e.before :: number,
					after = e.after :: number,
				})
			end
		end
		snap = driver:snapshot()
		if snap.total ~= before then
			table.insert(trajectory, { time = snap.time, total = snap.total })
		end
		if snap.outcome ~= nil then
			break
		end
	end
	for _, e in driver:events() do
		if e.kind == "cluster_credit" then
			credits += 1
		end
	end
	snap = driver:snapshot()
	return {
		policy = policy.name,
		outcome = snap.outcome,
		time = snap.time,
		total = snap.total,
		score = snap.score,
		trajectory = trajectory,
		attacks = attacks,
		credits = credits,
		events = driver:events(),
		runLog = driver:runLog(),
		driver = driver,
	}
end

-- Readable event log, printed with every failing assertion.
function BotHarness.formatLog(result: Result): string
	local lines = {
		`policy={result.policy} outcome={tostring(result.outcome)} total={result.total} t={string.format(
			"%.3f",
			result.time
		)}`,
	}
	for _, e in result.events do
		table.insert(
			lines,
			string.format(
				"  #%d t=%7.3f %-14s id=%s side=%s %s -> %s%s",
				e.index,
				e.time,
				e.kind,
				tostring(e.id),
				tostring(e.side),
				tostring(e.before),
				tostring(e.after),
				""
			)
		)
	end
	return table.concat(lines, "\n")
end

-- assert that prints the event log on failure.
function BotHarness.check(cond: boolean, message: string, result: Result)
	if not cond then
		error(`{message}\n{BotHarness.formatLog(result)}`, 2)
	end
end

local function copyLayout(layout: Level.Layout): Level.Layout
	local out: any = table.clone(layout :: any)
	local clusters = {}
	for _, c in layout.clusters do
		table.insert(clusters, {
			id = c.id,
			wave = c.wave,
			type = c.type,
			spawnTime = c.spawnTime,
			spawn = { x = c.spawn.x, z = c.spawn.z },
			path = {},
			lane = c.lane,
		})
	end
	out.clusters = clusters
	return out :: Level.Layout
end

-- Seeded perturbation: cluster spawn times +-0.75 s and spawn z (offset ahead of the lead) +-8
-- studs, quantized to 0.01. Gates, obstacles, sides (x) and the plaza are unchanged.
function BotHarness.perturb(layout: Level.Layout, seed: number): Level.Layout
	local r = BotHarness.rng(seed)
	local out = copyLayout(layout)
	out.name = `{layout.name}~p{seed}`
	for _, c in out.clusters do
		c.spawnTime =
			math.max(0, math.floor((c.spawnTime + (r() * 2 - 1) * 0.75) * 100 + 0.5) / 100)
		c.spawn.z = math.floor((c.spawn.z + (r() * 2 - 1) * 8) * 100 + 0.5) / 100
	end
	return out
end

-- Distribution helpers for reports.
function BotHarness.quantile(sorted: { number }, q: number): number
	if #sorted == 0 then
		return 0 / 0
	end
	local idx = math.clamp(math.ceil(#sorted * q), 1, #sorted)
	return sorted[idx]
end

return BotHarness
