--!strict
-- Authoritative state for one run (spec s4, s5, s6, s9, s11, s12). Pure: no game/Instance access.
-- The server owns consumption: each gate pair, spectator cluster and obstacle applies at most once,
-- and an unknown or already-consumed id is rejected with no state change and no log entry.
-- All numbers come from Config and CrowdMath. Clients may only ask; they never supply amounts.
--
-- Open for Amendment 1 (parade HP, issue #36): `Outcome` already allows "defeated", and cluster
-- consumption is a single kind per cluster (`ClusterUse`), so a later attack consumption shares the
-- same slot as a credit: a cluster is credited or attacks, never both and never twice.
local Config = require("./Config")
local CrowdMath = require("./CrowdMath")

export type Outcome = "completed" | "defeated"
export type ClusterUse = "credited" | "attacked"
export type Side = "left" | "right"
export type ClusterKind = "small" | "large"

export type GateSide = { x: number, op: CrowdMath.Op }
export type GatePair = { id: string, left: GateSide, right: GateSide }
export type ClusterDef = { id: string, type: ClusterKind }
export type ObstacleDef = { id: string }
export type Layout =
	{ gatePairs: { GatePair }, clusters: { ClusterDef }, obstacles: { ObstacleDef } }

export type Options = {
	seed: number,
	automated: boolean, -- true for automated QA sessions, false for human playtests (spec s12)
	layout: Layout,
	now: (() -> number)?, -- clock for event timestamps; defaults to os.clock
	startingTotal: number?, -- test hook; defaults to Config.startingTotal via CrowdMath
}

-- Outcome of a request. On rejection only `ok` and `reason` are set and nothing changed.
export type Result = {
	ok: boolean,
	reason: string?,
	side: Side?,
	before: number?,
	after: number?,
	score: number?,
	hpBefore: number?,
	hpAfter: number?,
}

-- Spec s12 Record: run start/seed, first recruitment, gate choice with before/after totals,
-- first assembly, obstacle losses, completion/final total.
export type Event = {
	index: number,
	kind: string, -- run_start | gate | cluster_credit | obstacle | cluster_attack | complete
	time: number,
	seed: number,
	automated: boolean,
	id: string?,
	side: Side?,
	before: number,
	after: number,
	score: number?,
	firstRecruit: boolean?,
	firstAssembly: boolean?,
	hpBefore: number?,
	hpAfter: number?,
	outcome: Outcome?,
}

export type RunState = {
	resolveGate: (self: RunState, pairId: any, leadX: any) -> Result,
	creditCluster: (self: RunState, id: any) -> Result,
	attackCluster: (self: RunState, id: any) -> Result,
	hitObstacle: (self: RunState, id: any) -> Result,
	complete: (self: RunState) -> Result,
	reset: (self: RunState, seed: number?) -> (),
	total: (self: RunState) -> number,
	hp: (self: RunState) -> number,
	isComplete: (self: RunState) -> boolean,
	outcome: (self: RunState) -> Outcome?,
	score: (self: RunState) -> number?,
	best: (self: RunState) -> number,
	seed: (self: RunState) -> number,
	clusterConsumption: (self: RunState, id: string) -> ClusterUse?,
	events: (self: RunState) -> { Event },
}

local function reject(reason: string): Result
	return { ok = false, reason = reason }
end

local function isId(v: any): boolean
	return type(v) == "string" and v ~= ""
end

local function isFinite(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function checkLayout(layout: any)
	assert(type(layout) == "table", "layout must be a table")
	local function section(name: string, seen: { [string]: boolean }, check: (any) -> ())
		local list = layout[name]
		assert(type(list) == "table", `layout.{name} must be a list`)
		for _, item in list do
			assert(type(item) == "table" and isId(item.id), `layout.{name} entry needs a string id`)
			assert(not seen[item.id], `duplicate {name} id {item.id}`)
			seen[item.id] = true
			check(item)
		end
	end
	local function checkSide(s: any)
		assert(type(s) == "table" and isFinite(s.x), "gate side needs a finite x")
		assert(
			type(s.op) == "table" and (s.op.kind == "add" or s.op.kind == "multiply"),
			"gate op must be add or multiply"
		)
		CrowdMath.applyOp(0, s.op) -- validates the value; errors if malformed
	end
	section("gatePairs", {}, function(p)
		checkSide(p.left)
		checkSide(p.right)
	end)
	section("clusters", {}, function(c)
		assert(Config.clusterTypes[c.type :: ClusterKind] ~= nil, `unknown cluster type {c.type}`)
	end)
	section("obstacles", {}, function() end)
end

local function new(opts: Options): RunState
	assert(type(opts) == "table", "options must be a table")
	assert(isFinite(opts.seed), "seed must be a number")
	assert(type(opts.automated) == "boolean", "automated must be a boolean")
	checkLayout(opts.layout)
	-- Only the server may set this, and never from client data (issue #8). Still validated.
	if opts.startingTotal ~= nil then
		local v: any = opts.startingTotal
		assert(
			type(v) == "number" and v >= 0 and v == math.floor(v) and v < math.huge,
			"startingTotal must be a non-negative integer"
		)
	end

	local gates: { [string]: GatePair } = {}
	for _, p in opts.layout.gatePairs do
		gates[p.id] = p
	end
	local clusters: { [string]: ClusterDef } = {}
	for _, c in opts.layout.clusters do
		clusters[c.id] = c
	end
	local obstacles: { [string]: ObstacleDef } = {}
	for _, o in opts.layout.obstacles do
		obstacles[o.id] = o
	end
	local now: () -> number = opts.now or os.clock
	local startTotal = opts.startingTotal or CrowdMath.startingTotal()

	-- Per-run state. Everything below is replaced wholesale by reset().
	local seed = opts.seed
	local crowdTotal = startTotal
	local paradeHp = Config.hp.max
	local outcome: Outcome? = nil
	local finalScore: number? = nil
	local usedGates: { [string]: boolean } = {}
	local usedClusters: { [string]: ClusterUse } = {}
	local usedObstacles: { [string]: boolean } = {}
	local log: { Event } = {}
	local seenRecruit = false
	local seenAssembly = false
	-- Session state: survives reset (spec s9 session best).
	local bestScore = 0

	local self = {} :: RunState

	local function record(
		kind: string,
		before: number,
		after: number,
		extra: { [string]: any }?
	): Event
		local e: any = {
			index = #log + 1,
			kind = kind,
			time = now(),
			seed = seed,
			automated = opts.automated,
			before = before,
			after = after,
		}
		if extra then
			for k, v in extra do
				e[k] = v
			end
		end
		table.insert(log, e :: Event)
		return e :: Event
	end

	local function start(newSeed: number)
		seed = newSeed
		crowdTotal = startTotal
		paradeHp = Config.hp.max
		outcome = nil
		finalScore = nil
		usedGates = {}
		usedClusters = {}
		usedObstacles = {}
		log = {}
		seenRecruit = false
		seenAssembly = false
		record("run_start", crowdTotal, crowdTotal)
	end

	-- Applies a new total and returns the assembly flag for the event (true once per run).
	local function setTotal(after: number): boolean?
		local before = crowdTotal
		crowdTotal = after
		if
			not seenAssembly
			and CrowdMath.sectionCount(before) == 0
			and CrowdMath.sectionCount(after) >= 1
		then
			seenAssembly = true
			return true
		end
		return nil
	end

	local function guard(): Result?
		if outcome ~= nil then
			return reject("run already ended")
		end
		return nil
	end

	function self.resolveGate(_, pairId: any, leadX: any): Result
		local blocked = guard()
		if blocked then
			return blocked
		end
		if not isId(pairId) then
			return reject("invalid pair id")
		end
		local pair = gates[pairId]
		if pair == nil then
			return reject("unknown gate pair")
		end
		if usedGates[pairId] then
			return reject("gate pair already consumed")
		end
		if not isFinite(leadX) then
			return reject("invalid lead position")
		end
		-- Nearest gate wins; an exact tie goes to the left gate (spec s6).
		local side: Side = "left"
		if math.abs(leadX - pair.right.x) < math.abs(leadX - pair.left.x) then
			side = "right"
		end
		local chosen = if side == "left" then pair.left else pair.right
		local before = crowdTotal
		local after = CrowdMath.applyOp(before, chosen.op)
		usedGates[pairId] = true
		local assembled = setTotal(after)
		record("gate", before, after, { id = pairId, side = side, firstAssembly = assembled })
		return { ok = true, side = side, before = before, after = after }
	end

	function self.creditCluster(_, id: any): Result
		local blocked = guard()
		if blocked then
			return blocked
		end
		if not isId(id) then
			return reject("invalid cluster id")
		end
		local cluster = clusters[id]
		if cluster == nil then
			return reject("unknown cluster")
		end
		if usedClusters[id] ~= nil then
			return reject(`cluster already {usedClusters[id]}`)
		end
		local before = crowdTotal
		local after = CrowdMath.applyOp(
			before,
			{ kind = "add", value = Config.clusterTypes[cluster.type].reward }
		)
		usedClusters[id] = "credited"
		local assembled = setTotal(after)
		local first: boolean? = nil
		if not seenRecruit then
			seenRecruit = true
			first = true
		end
		record(
			"cluster_credit",
			before,
			after,
			{ id = id, firstRecruit = first, firstAssembly = assembled }
		)
		return { ok = true, before = before, after = after }
	end

	function self.hitObstacle(_, id: any): Result
		local blocked = guard()
		if blocked then
			return blocked
		end
		if not isId(id) then
			return reject("invalid obstacle id")
		end
		if obstacles[id] == nil then
			return reject("unknown obstacle")
		end
		if usedObstacles[id] then
			return reject("obstacle already consumed")
		end
		local before = crowdTotal
		local after = CrowdMath.applyOp(before, CrowdMath.obstacleOp())
		usedObstacles[id] = true
		setTotal(after)
		record("obstacle", before, after, { id = id })
		return { ok = true, before = before, after = after }
	end

	function self.attackCluster(_, id: any): Result
		local blocked = guard()
		if blocked then
			return blocked
		end
		if not isId(id) then
			return reject("invalid cluster id")
		end
		local cluster = clusters[id]
		if cluster == nil then
			return reject("unknown cluster")
		end
		if usedClusters[id] ~= nil then
			return reject(`cluster already {usedClusters[id]}`)
		end
		local before = paradeHp
		paradeHp = math.max(0, paradeHp - Config.clusterTypes[cluster.type].attackDamage)
		usedClusters[id] = "attacked"
		if paradeHp == 0 then
			outcome = "defeated"
			finalScore = crowdTotal
		end
		record("cluster_attack", crowdTotal, crowdTotal, {
			id = id,
			hpBefore = before,
			hpAfter = paradeHp,
			outcome = outcome,
		})
		return {
			ok = true,
			before = before,
			after = paradeHp,
			hpBefore = before,
			hpAfter = paradeHp,
		}
	end

	function self.complete(_): Result
		local blocked = guard()
		if blocked then
			return blocked
		end
		outcome = "completed"
		finalScore = crowdTotal -- spec s9: score equals the final crowd total, no bonus
		bestScore = math.max(bestScore, crowdTotal)
		record("complete", crowdTotal, crowdTotal, { score = crowdTotal })
		return { ok = true, before = crowdTotal, after = crowdTotal, score = crowdTotal }
	end

	function self.reset(_, newSeed: number?)
		if newSeed ~= nil then
			assert(isFinite(newSeed), "seed must be a number")
		end
		start(newSeed or seed)
	end

	function self.total(_)
		return crowdTotal
	end
	function self.hp(_)
		return paradeHp
	end
	function self.isComplete(_)
		return outcome == "completed"
	end
	function self.outcome(_)
		return outcome
	end
	function self.score(_)
		return finalScore
	end
	function self.best(_)
		return bestScore
	end
	function self.seed(_)
		return seed
	end
	function self.clusterConsumption(_, id: string): ClusterUse?
		return usedClusters[id]
	end
	function self.events(_): { Event }
		local copy: { Event } = {}
		for i, e in log do
			copy[i] = table.clone(e)
		end
		return copy
	end

	start(seed)
	return self
end

return { new = new }
