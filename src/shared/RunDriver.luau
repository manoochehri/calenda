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
local Config = require("./Config")
local Crossing = require("./Crossing")
local Level = require("./Level")
local Remotes = require("./Remotes")
local RunState = require("./RunState")
local Steering = require("./Steering")

local RunDriver = {}

RunDriver.MAX_DT = 0.1 -- [default] seconds; a longer frame is simulated as this long
RunDriver.REPLAY_COOLDOWN = 1 -- [default] seconds between accepted replay requests

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
}
export type Hooks = {
	shots: ((TickContext) -> ())?, -- phase 1, before the lead moves (issue #9)
	attacks: ((TickContext) -> ())?, -- phase 3, after gates and the obstacle (issue #36)
	endCheck: ((TickContext) -> boolean)?, -- phase 4, true = the run ends defeated (issue #36)
	reset: (() -> ())?, -- clear per-run hook state when replay begins
}
export type Options = { layout: Level.Layout, automated: boolean?, hooks: Hooks? }

export type Snapshot = Remotes.Snapshot

export type RunDriver = {
	steer: (self: RunDriver, now: any, payload: any) -> boolean,
	tick: (self: RunDriver, dt: any) -> { DriverEvent },
	replay: (self: RunDriver, now: any) -> boolean,
	snapshot: (self: RunDriver) -> Snapshot,
	total: (self: RunDriver) -> number,
	outcome: (self: RunDriver) -> string?,
}

-- Copies the authored layout into RunState's layout. Fresh tables only: nothing is shared with
-- the source, so a later change to either cannot reach the other. Ids become strings
-- ("g1", "c1", "o1"). Gate anchors sit at +-halfWidth/2 (the middle of each half street).
function RunDriver.toRunLayout(layout: Level.Layout): RunState.Layout
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
	return { gatePairs = gatePairs, clusters = clusters, obstacles = obstacles }
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
	-- Deliberately NOT forwarded: any startingTotal on opts (never client or caller data).
	local state = RunState.new({
		seed = layout.seed,
		automated = opts.automated == true,
		layout = RunDriver.toRunLayout(opts.layout),
	})
	local bound = Steering.bound(layout.halfWidth)

	local time, z, x, target = 0, 0, 0, 0
	local ended = false
	local finalOutcome: string? = nil
	local finalScore: number? = nil
	local steerLimiter = Steering.newLimiter(Steering.MESSAGES_PER_SECOND, Steering.BURST)
	local lastReplay: number? = nil

	local self = {} :: RunDriver

	function self.steer(_, now: any, payload: any): boolean
		if not steerLimiter.allow(now) then
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
		if ended or not isFinite(dt) or (dt :: number) <= 0 then
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
				table.insert(events, e)
			end,
			passedClusters = {},
		}

		-- (1) shots land, meters fill, conversions credited (issue #9)
		if hooks.shots then
			hooks.shots(ctx)
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

		-- (3) unconverted clusters that reached the parade attack (issue #36)
		if hooks.attacks then
			hooks.attacks(ctx)
		end

		-- (4) end checks: defeat wins over reaching the plaza on the same tick
		local defeated = state:outcome() == "defeated"
			or (hooks.endCheck ~= nil and hooks.endCheck(ctx) == true)
		if defeated then
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
		if not ended or not isFinite(now) then
			return false
		end
		if lastReplay ~= nil and (now :: number) - lastReplay < RunDriver.REPLAY_COOLDOWN then
			return false
		end
		lastReplay = now :: number
		state:reset()
		if hooks.reset then
			hooks.reset()
		end
		time, z, x, target = 0, 0, 0, 0
		ended, finalOutcome, finalScore = false, nil, nil
		return true
	end

	function self.snapshot(_): Snapshot
		return {
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

	return self
end

return RunDriver
