--!strict
-- The per-player run simulation (issue #8, spec s3, s6, s9, s11, Amendment 1). Pure: no Roblox
-- APIs, so it is Lune-tested; src/server/RunServer.server.luau is a thin wiring around it.
--
-- Trust: the driver's only inputs from a client are `steer(now, payload)` (a lateral-position
-- intent) and `replay(now)`. RunState is built here from a COPY of the authored layout and never
-- from caller data; opts.startingTotal is not read. Gate crossings, obstacle overlaps and run
-- completion are detected here from server positions and applied through RunState.
--
-- Same-tick order (Amendment 1): (1) shots/conversions, (2) lead moves, gates, then obstacle,
-- (3) attacks, (4) end checks (defeat wins over reaching the plaza). The hooks below are the
-- extension points: #9 plugs targeting/shooting into `shots`, #36 plugs cluster attacks into
-- `attacks` and HP defeat into `endCheck`.
-- A defeat is recorded in RunState's log (event "defeated"), so runLog() shows the outcome.
local Crossing = require("./Crossing")
local Config = require("./Config")
local Hazards = require("./Hazards")
local Level = require("./Level")
local Remotes = require("./Remotes")
local RunLog = require("./RunLog")
local RunState = require("./RunState")
local Steering = require("./Steering")

local RunDriver = {}

RunDriver.MAX_DT = 0.1 -- [default] seconds; a longer frame is simulated as this long
RunDriver.TICK_DT = 1 / 30 -- shared fixed step for server and validator
-- Hard cap on shot events ("cluster" hits, "miss"es and Rey hits together, ADR 0006) one tick may return. Firing is
-- continuous (ADR 0004), so every shot is one event. The fire rate is at most Config.firing.cap
-- (20) shots/s and one step is at most MAX_DT (0.1 s): at most floor(20 * 0.1) + 1 = 3 shots per
-- step (1 per 1/30 s tick). 8 leaves headroom and only matters if a hook misbehaves. Excess is
-- dropped. Worst case: 8 events x 30 ticks/s = 240 events/s hard ceiling per player, about
-- 20 events/s in practice (see PR for bytes).
RunDriver.MAX_CLUSTER_EVENTS_PER_TICK = 8 -- [default]
RunDriver.REPLAY_COOLDOWN = 1 -- [default] seconds between accepted replay requests
-- Start (issue #72): a ready run begins on one client request. Attempts are rate limited on the
-- server clock; START_COOLDOWN is defence in depth after an accepted Start.
RunDriver.START_COOLDOWN = 1 -- [default] seconds
RunDriver.START_PER_SECOND = 1 -- [default] refill rate of the Start limiter
RunDriver.START_BURST = 2 -- [default] attempts in a burst

-- Passed to hooks. `state` is server-only; `emit` queues an event for replication.
export type DriverEvent = {
	kind: string,
	id: number?,
	side: string?,
	before: number?,
	after: number?,
	hpBefore: number?,
	hpAfter: number?,
	score: number?,
	hits: number?, -- cluster: meter value after the shot, integer 0..1000
	shot: ("note" | "gift")?, -- cluster, miss: visual variant
	hazard: string?, -- hazard events (issue #96): "tomato" | "cart"
	at: number?, -- hazard_warning: run time of the impact
	x: number?, -- hazard events: lateral lane or gap centre
	n: number?, -- miss: shot number (look only)
}
export type TickContext = {
	t0: number,
	t1: number,
	z0: number,
	z1: number,
	x: number,
	state: RunState.RunState,
	emit: (DriverEvent) -> (),
	passedClusters: { number },
	giftTimes: { number }, -- landed gift shots this tick (RunHooks fills; issue #96 blocking)
}
export type Hooks = {
	shots: ((TickContext) -> ())?, -- phase 1, before the lead moves (issue #9)
	attacks: ((TickContext) -> ())?, -- phase 3, after gates and the obstacle (issue #36)
	endCheck: ((TickContext) -> boolean)?, -- phase 4, true = the run ends defeated (issue #36)
	reset: (() -> ())?, -- clear per-run hook state when replay begins
}
export type Options = {
	layout: Level.Layout,
	automated: boolean?,
	hooks: Hooks?,
	startReady: boolean?, -- true: begin "ready" (paused) until start(); default begins "running"
	now: (() -> number)?, -- event clock forwarded to RunState (server-side only); lets tests use a fake clock
	runSeed: number?, -- seeds the level's hazard schedule (issue #96); defaults to layout.seed
}

export type Snapshot = Remotes.Snapshot

export type RunDriver = {
	steer: (self: RunDriver, now: any, payload: any) -> boolean,
	tick: (self: RunDriver, dt: any) -> { DriverEvent },
	replay: (self: RunDriver, now: any) -> boolean,
	start: (self: RunDriver, now: any) -> boolean,
	phase: (self: RunDriver) -> "ready" | "running" | "over",
	snapshot: (self: RunDriver) -> Snapshot,
	total: (self: RunDriver) -> number,
	outcome: (self: RunDriver) -> string?,
	events: (self: RunDriver) -> { RunState.Event },
	replays: (self: RunDriver) -> { RunLog.ReplayEntry },
	runLog: (self: RunDriver) -> RunLog.StructuredLog,
}

-- Copies the authored layout into RunState's layout. Fresh tables only: nothing is shared with
-- the source, so a later change to either cannot reach the other. Ids become strings
-- ("g1", "c1", "o1"). Gate anchors sit at +-halfWidth/2 (the middle of each half street).
function RunDriver.toRunLayout(layout: Level.Layout, hazards: { Hazards.Hazard }?): RunState.Layout
	local anchor = layout.halfWidth / 2
	local gatePairs: { RunState.GatePair } = {}
	for _, g in layout.gates do
		table.insert(gatePairs, {
			id = `g{g.id}`,
			left = { x = -anchor, op = { kind = g.left.kind, value = g.left.value } },
			right = { x = anchor, op = { kind = g.right.kind, value = g.right.value } },
		})
	end
	local clusters: { RunState.ClusterDef } = {}
	for _, c in layout.clusters do
		table.insert(clusters, { id = `c{c.id}`, type = c.type :: RunState.ClusterKind })
	end
	local obstacles: { RunState.ObstacleDef } = {}
	for _, o in layout.obstacles do
		table.insert(obstacles, { id = `o{o.id}` })
	end
	-- Issue #96: a cart is an obstacle (one crowd loss, once); a tomato is an HP hazard.
	local tomatoes: { RunState.ObstacleDef } = {}
	for _, h in hazards or {} do
		if h.kind == "cart" then
			table.insert(obstacles, { id = `h{h.id}` })
		else
			table.insert(tomatoes, { id = `t{h.id}` })
		end
	end
	return { gatePairs = gatePairs, clusters = clusters, obstacles = obstacles, tomatoes = tomatoes }
end

local function isFinite(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- Detection works on a private copy of the numbers it needs, so mutating the caller's layout
-- after construction cannot move a gate or obstacle.
local function copyForDetection(layout: Level.Layout): Level.Layout
	local gates: { Level.Gate } = {}
	for _, g in layout.gates do
		table.insert(gates, {
			id = g.id,
			z = g.z,
			left = { kind = g.left.kind, value = g.left.value },
			right = { kind = g.right.kind, value = g.right.value },
		})
	end
	local obstacles: { Level.Obstacle } = {}
	for _, o in layout.obstacles do
		table.insert(obstacles, { id = o.id, z = o.z, side = o.side })
	end
	return {
		name = layout.name,
		seed = layout.seed,
		hazardSet = layout.hazardSet,
		startPlazaEnd = layout.startPlazaEnd,
		streetLength = layout.streetLength,
		plazaStart = layout.plazaStart,
		halfWidth = layout.halfWidth,
		maxTotal = layout.maxTotal,
		intendedRecruitTotal = layout.intendedRecruitTotal,
		gates = gates,
		obstacles = obstacles,
		clusters = {},
	}
end

function RunDriver.new(opts: Options): RunDriver
	assert(type(opts) == "table" and type(opts.layout) == "table", "layout required")
	local layout = copyForDetection(opts.layout)
	local hooks: Hooks = opts.hooks or {}
	-- Issue #96: the hazard schedule is drawn from the run seed, once, here on the server. Replay
	-- keeps the same seed, so the same hazards come back.
	local runSeed = opts.runSeed or layout.seed
	local hazards = Hazards.schedule(layout.hazardSet, runSeed, layout.halfWidth, Config.speed)
	-- Deliberately NOT forwarded: any startingTotal on opts (never client or caller data).
	local state = RunState.new({
		seed = runSeed,
		automated = opts.automated == true,
		layout = RunDriver.toRunLayout(opts.layout, hazards),
		now = opts.now,
	})
	-- Hazard runtime (per run; cleared on replay). Gifts are landed gift shots still able to block.
	local hazardWarned: { [number]: boolean } = {}
	local hazardDone: { [number]: boolean } = {}
	local gifts: { { t: number, used: boolean } } = {}
	local bound = Steering.bound(layout.halfWidth)

	local time, z, x, target = 0, 0, 0, 0
	local ended = false
	local finalOutcome: string? = nil
	local finalScore: number? = nil
	local steerLimiter = Steering.newLimiter(Steering.MESSAGES_PER_SECOND, Steering.BURST)
	local lastReplay: number? = nil
	local started = opts.startReady ~= true -- false = "ready": paused, nothing advances or logs
	local startLimiter = Steering.newLimiter(RunDriver.START_PER_SECOND, RunDriver.START_BURST)
	local lastStart: number? = nil
	local replays: { RunLog.ReplayEntry } = {}

	local self = {} :: RunDriver

	function self.steer(_, now: any, payload: any): boolean
		if not started or not steerLimiter.allow(now) then
			return false
		end
		local want = Remotes.decodeSteer(payload)
		if want == nil then
			return false
		end
		local clamped = Steering.clampTarget(want, bound)
		if clamped == nil then
			return false
		end
		target = clamped
		return true
	end

	function self.tick(_, dt: any): { DriverEvent }
		local events: { DriverEvent } = {}
		local clusterEvents = 0
		if not started or ended or not isFinite(dt) or (dt :: number) <= 0 then
			return events
		end
		local step = math.min(dt :: number, RunDriver.MAX_DT)
		local t0, t1 = time, time + step
		local z0, x0 = z, x
		local z1 = Level.leadZ(t1, Config)
		local x1 = Steering.step(x0, target, step, Steering.MAX_LATERAL_SPEED)
		local ctx: TickContext = {
			t0 = t0,
			t1 = t1,
			z0 = z0,
			z1 = z1,
			x = x0,
			state = state,
			emit = function(e: DriverEvent)
				if e.kind == "cluster" or e.kind == "miss" or e.kind == "rey" then
					if clusterEvents >= RunDriver.MAX_CLUSTER_EVENTS_PER_TICK then
						return
					end
					clusterEvents += 1
				end
				table.insert(events, e)
			end,
			passedClusters = {},
			giftTimes = {},
		}

		-- (1) shots land, meters fill, conversions credited (issue #9)
		if hooks.shots then
			hooks.shots(ctx)
		end

		for _, t in ctx.giftTimes do
			table.insert(gifts, { t = t, used = false })
		end

		-- (2) the lead moves, then gates resolve, then the obstacle applies
		time, z, x = t1, z1, x1
		ctx.x = x1
		for _, g in Crossing.gatesCrossed(layout, z0, z1) do
			local r = state:resolveGate(`g{g.id}`, x1)
			if r.ok then
				table.insert(events, {
					kind = "gate",
					id = g.id,
					side = r.side,
					before = r.before,
					after = r.after,
				})
			end
		end
		for _, o in Crossing.obstaclesHit(layout, z0, z1, x0, x1) do
			local r = state:hitObstacle(`o{o.id}`)
			if r.ok then
				table.insert(
					events,
					{ kind = "obstacle", id = o.id, before = r.before, after = r.after }
				)
			end
		end

		-- (2b) hazards (issue #96). Warnings first, then each hazard resolves once: a tomato at its
		-- impact (in its lane? a landed gift in its warning window blocks it; otherwise HP), a cart
		-- on the sweep through its blocked band (crowd loss).
		for _, h in hazards do
			if not hazardWarned[h.id] and t1 >= h.warnAt then
				hazardWarned[h.id] = true
				table.insert(events, {
					kind = "hazard_warning",
					id = h.id,
					hazard = h.kind,
					at = h.impactAt,
					x = h.x,
					side = h.side,
				})
			end
			if not hazardDone[h.id] then
				if h.kind == "tomato" and t1 >= h.impactAt then
					hazardDone[h.id] = true
					if not Hazards.tomatoHit(h, x1) then
						table.insert(
							events,
							{ kind = "hazard_dodged", id = h.id, hazard = "tomato" }
						)
					else
						local blocker = nil
						for i, g in gifts do
							if not g.used and g.t >= h.warnAt and g.t <= h.impactAt then
								blocker = i
								break
							end
						end
						if blocker ~= nil then
							gifts[blocker].used = true
							table.insert(
								events,
								{ kind = "hazard_blocked", id = h.id, hazard = "tomato" }
							)
						else
							local r = state:hitTomato(`t{h.id}`)
							if r.ok then
								table.insert(events, {
									kind = "hazard_hit",
									id = h.id,
									hazard = "tomato",
									hpBefore = r.hpBefore,
									hpAfter = r.hpAfter,
								})
							end
						end
					end
				elseif
					h.kind == "cart" and Hazards.cartHit(h, z0, z1, x0, x1, layout.halfWidth)
				then
					hazardDone[h.id] = true
					local r = state:hitObstacle(`h{h.id}`)
					if r.ok then
						table.insert(events, {
							kind = "hazard_hit",
							id = h.id,
							hazard = "cart",
							before = r.before,
							after = r.after,
						})
					end
				end
			end
		end
		-- A gift can only block a tomato whose warning window it falls in; older ones are spent.
		local kept = {}
		for _, g in gifts do
			if g.t >= t1 - Hazards.TOMATO_WARNING then
				table.insert(kept, g)
			end
		end
		gifts = kept

		-- (3) unconverted clusters that reached the parade attack (issue #36)
		if hooks.attacks then
			hooks.attacks(ctx)
		end

		-- (4) end checks: defeat wins over reaching the plaza on the same tick
		local defeated = state:outcome() == "defeated"
			or (hooks.endCheck ~= nil and hooks.endCheck(ctx) == true)
		if defeated then
			if state:outcome() == nil then
				state:defeat() -- an end-check hook ended it: record the outcome in the run log
			end
			ended, finalOutcome, finalScore = true, "defeated", state:score() or state:total()
			table.insert(events, { kind = "defeated", score = finalScore })
		elseif z1 >= layout.plazaStart then
			local r = state:complete()
			ended, finalOutcome, finalScore = true, "completed", r.score
			table.insert(events, { kind = "complete", score = r.score })
		end
		return events
	end

	-- Replay starts a fresh run. Refused mid-run, rate limited, never trusts the caller's time.
	function self.replay(_, now: any): boolean
		if not started or not ended or not isFinite(now) then
			return false
		end
		if lastReplay ~= nil and (now :: number) - lastReplay < RunDriver.REPLAY_COOLDOWN then
			return false
		end
		lastReplay = now :: number
		-- The replay is recorded as an event on the NEXT run's log (runLog().replays); the finished
		-- run is logged once, when it ends. History is capped so a long session cannot grow it.
		table.insert(replays, { time = now :: number })
		while #replays > RunLog.MAX_LOGS_PER_PLAYER do
			table.remove(replays, 1)
		end
		state:reset()
		if hooks.reset then
			hooks.reset()
		end
		time, z, x, target = 0, 0, 0, 0
		ended, finalOutcome, finalScore = false, nil, nil
		hazardWarned, hazardDone, gifts = {}, {}, {}
		return true
	end

	-- Start (issue #72): only a "ready" run starts, once. Reads no client data: the caller passes
	-- the SERVER clock. A second Start while running, or after the end (Replay's job), is ignored.
	function self.start(_, now: any): boolean
		if not startLimiter.allow(now) or started or ended then
			return false
		end
		if lastStart ~= nil and (now :: number) - lastStart < RunDriver.START_COOLDOWN then
			return false
		end
		lastStart = now :: number
		started = true
		return true
	end

	function self.phase(_): "ready" | "running" | "over"
		if not started then
			return "ready"
		end
		return if ended then "over" else "running"
	end

	function self.snapshot(_): Snapshot
		return {
			phase = self:phase(),
			time = time,
			z = z,
			x = x,
			total = state:total(),
			hp = state:hp(),
			maxHp = Config.hp.max,
			best = state:best(),
			outcome = finalOutcome,
			score = finalScore,
		}
	end

	function self.total(_): number
		return state:total()
	end

	function self.outcome(_): string?
		return finalOutcome
	end

	function self.events(_): { RunState.Event }
		return state:events()
	end

	function self.replays(_): { RunLog.ReplayEntry }
		return table.clone(replays)
	end

	function self.runLog(_): RunLog.StructuredLog
		return RunLog.fromEvents(state:events(), { replays = replays })
	end

	return self
end

return RunDriver
