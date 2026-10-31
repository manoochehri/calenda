--!strict
-- Targeting and fire scheduler (issue #9; spec s3, s4, Amendment 1). Pure: no Roblox APIs.
-- Coordinates follow Level: z is distance along the street (the lead's forward position is
-- Level.leadZ(t)), x is lateral. A target's distance is z - leadZ.
--
-- Rules (Amendment 1, as amended for issue #142): eligible = in range (distance <= firing.range),
-- meter not full, not yet passed (z > leadZ), and already spawned. The lead's lane decides which
-- hordes it can engage (ADR 0010 item 1, issue #156): a horde is engaged only from its authored lane,
-- and center engages the center lane. There is no fallback to another lane. Among eligible hordes in
-- the lead's lane, the nearest to the lead is chosen. Reaching the parade reports an unfilled cluster in `passed` for the attack phase; later
-- hits to a passed cluster are inert.
--
-- Firing is CONTINUOUS (ADR 0004, spec Amendment 2): a shot every 1 / fireRate seconds whether or
-- not anything is in range. Issue #234: the rate, the projectile speed and the number of projectiles
-- allowed in flight at once follow the recruit count (FireTable, Config.firing.tiers). With zero
-- recruits one projectile is in flight at a time: the next shot starts only after the current one
-- has hit, missed out or left the playfield (its server-side flight time, at the tier speed). A shot with an eligible target is a hit (one meter hit, credit-once).
-- A shot with none is a MISS: `miss = true`, no targetId, and it touches no meter, no RunState and
-- no life. Misses still advance the shot counter, so the gift cadence (every Nth shot) is unchanged.
--
-- Per advance() the order matches the same-tick ordering of Amendment 1: shots land, meters fill
-- and conversions are credited (RunState.creditCluster, exactly once), then unconverted clusters
-- that reached the parade are reported. Cluster ids are numbers in Level; RunState ids are the
-- same ids as strings (tostring).
local Config = require("./Config")
local CrowdMath = require("./CrowdMath")
local FireTable = require("./FireTable")
local Level = require("./Level")
local ProjectileVisual = require("./ProjectileVisual")
local RunState = require("./RunState")
local ShotLook = require("./ShotLook")

export type Steer = "left" | "right" | "center"
export type ShotKind = "note" | "gift"
-- A candidate for selectTarget: `z` and `x` are the cluster's current position.
-- `lane` is the cluster's authored lane (ADR 0010 item 2), not a lane derived from its position.
export type Candidate = { id: number, x: number, z: number, full: boolean, lane: Steer }

export type Shot = {
	number: number, -- 1-based shot count for this session (hits and misses)
	time: number,
	miss: boolean, -- true: no eligible target; display only, never credits or damages
	targetId: number?, -- nil exactly when miss
	kind: ShotKind, -- visual variant only; every shot is exactly one hit
	hits: number, -- meter value after this hit (0 for a miss)
	needed: number, -- 0 for a miss
	filled: boolean, -- true when the meter is full (this hit or earlier); false for a miss
	credit: RunState.Result?, -- set only on the hit that fills the meter
	speed: number, -- projectile speed in studs/s the server used for this shot's flight (display)
}
export type HitResult = { hits: number, needed: number, filled: boolean, credit: RunState.Result? }
export type Step = { shots: { Shot }, passed: { number } }
-- Issue #162: route time and combat time are different clocks once the lead can stop. `t` stays the
-- monotonic combat time. `delay` is combat time minus route time at the start of the tick (0 until a
-- stop), `routeT1` the route time reached at the end of the tick, and leadZ0/leadZ1 the lead's real
-- z at its start and end. A mob spawns when ROUTE time reaches its spawnTime and then ages on combat
-- time, so a stop neither releases the mobs ahead nor freezes the ones already walking.
export type Clock = { delay: number, routeT1: number, leadZ0: number, leadZ1: number }

export type Session = {
	advance: (
		self: Session,
		t: number,
		sectionCount: number,
		steer: Steer?,
		shotPositionTime: number?,
		clock: Clock?,
		recruits: number?
	) -> Step,
	hit: (self: Session, id: number) -> HitResult,
	meter: (self: Session, id: number) -> (number, number),
}

export type Options = {
	layout: Level.Layout,
	runState: RunState.RunState,
	config: any?, -- tests may pass a modified copy of Config
	runIdPrefix: string?, -- RunDriver's RunState names clusters with a `c` prefix
}

local Targeting = {}

-- Hard bound on shots one advance() may produce. The server steps at most RunDriver.MAX_DT (0.1 s)
-- and the rate cap is 20/s, so a real step yields at most 3; the bound only matters for a caller
-- that jumps the clock, whose backlog is dropped rather than fired.
Targeting.MAX_SHOTS_PER_ADVANCE = 32 -- [default]

-- Issue #234: shots per second at `sectionCount` whole sections (sectionCount x Config.sectionSize
-- recruits), from the Config.firing.tiers table. Replaces the ADR 0004 min(cap, base + n) curve.
function Targeting.fireRate(sectionCount: number, config: any?): number
	if
		type(sectionCount) ~= "number"
		or sectionCount < 0
		or sectionCount ~= math.floor(sectionCount)
	then
		error(`sectionCount must be a non-negative integer, got {sectionCount}`, 2)
	end
	local cfg = config or Config
	return FireTable.rate(sectionCount * cfg.sectionSize, cfg)
end

local function hasDancers(sectionCount: number): boolean
	for i = 1, sectionCount do
		if CrowdMath.sectionType(i) == "dancers" then
			return true
		end
		if i >= 3 then
			break -- the sequence repeats every 3; no dancer section within the first 3 means none
		end
	end
	return false
end

-- Gift cadence hook (spec s4): every Config.giftEveryNthShot-th shot is a gift once a dancer
-- section exists; otherwise a note. Both are one hit. Notes/hearts/gifts are client-side variants (ProjectileVisual).
function Targeting.shotKind(shotNumber: number, sectionCount: number, config: any?): ShotKind
	if type(shotNumber) ~= "number" or shotNumber < 1 or shotNumber ~= math.floor(shotNumber) then
		error(`shotNumber must be a positive integer, got {shotNumber}`, 2)
	end
	local nth = (config or Config).giftEveryNthShot
	if hasDancers(sectionCount) and shotNumber % nth == 0 then
		return "gift"
	end
	return "note"
end

-- Pure target choice (issue #142, lanes per ADR 0010). Only eligible candidates whose authored lane
-- is the lead's lane are considered; a nil lane (lead outside the lanes) engages nothing. Returns the
-- nearest such id, ties broken by lowest id, or nil.
function Targeting.selectTarget(
	candidates: { Candidate },
	leadZ: number,
	steer: Steer?,
	config: any?
): number?
	if steer == nil then
		return nil
	end
	local cfg = config or Config
	local best: Candidate? = nil
	local bestDist = math.huge
	for _, c in candidates do
		local dist = c.z - leadZ
		if not c.full and dist > 0 and dist <= cfg.firing.range and c.lane == steer then
			if best == nil or dist < bestDist or (dist == bestDist and c.id < best.id) then
				best, bestDist = c, dist
			end
		end
	end
	return if best then best.id else nil
end

function Targeting.new(opts: Options): Session
	local layout = opts.layout
	local runState = opts.runState
	local cfg = opts.config or Config
	local runIdPrefix = opts.runIdPrefix or ""

	local hitsOf: { [number]: number } = {}
	local credited: { [number]: boolean } = {}
	local reported: { [number]: boolean } = {}
	local clusters = table.clone(layout.clusters)
	table.sort(clusters, function(a, b)
		return a.id < b.id
	end)
	local needed: { [number]: number } = {}
	for _, c in clusters do
		local ct = cfg.clusterTypes[c.type]
		assert(ct ~= nil, `unknown cluster type {c.type}`)
		needed[c.id] = ct.hits
		hitsOf[c.id] = 0
	end

	local shotCount = 0
	local nextShot = 0
	-- Issue #234: the times at which the shots still in flight resolve (hit landed, miss left the
	-- playfield). A new shot may start only while fewer than the tier's maxInFlight are unresolved.
	local resolveAt: { number } = {}
	local lastT = -math.huge

	local self = {} :: Session

	function self.meter(_, id: number): (number, number)
		return hitsOf[id], needed[id]
	end

	-- One hit on a meter. The meter caps at full; only the hit that fills it credits, once.
	function self.hit(_, id: number): HitResult
		local need = needed[id]
		assert(need ~= nil, `unknown cluster {id}`)
		if reported[id] then
			return { hits = hitsOf[id], needed = need, filled = hitsOf[id] >= need, credit = nil }
		end
		if hitsOf[id] >= need then
			return { hits = need, needed = need, filled = true, credit = nil }
		end
		hitsOf[id] += 1
		local credit: RunState.Result? = nil
		if hitsOf[id] >= need and not credited[id] then
			credited[id] = true
			credit = runState:creditCluster(`{runIdPrefix}{id}`)
		end
		return { hits = hitsOf[id], needed = need, filled = hitsOf[id] >= need, credit = credit }
	end

	-- Combat-time offset of cluster `c`'s path: the stationary time that had already passed when it
	-- spawned. nil until it has spawned. Without a clock it is 0, the pre-checkpoint behaviour.
	local shiftOf: { [number]: number } = {}
	local function spawnShift(c: Level.Cluster, t: number, clock: Clock?): number?
		local shift = shiftOf[c.id]
		if shift == nil then
			local routeNow = if clock then math.min(t - clock.delay, clock.routeT1) else t
			if routeNow >= c.spawnTime then
				shift = if clock then clock.delay else 0
				shiftOf[c.id] = shift
			end
		end
		return shift
	end

	local function candidatesAt(t: number, clock: Clock?): { Candidate }
		local list: { Candidate } = {}
		for _, c in clusters do
			local shift = spawnShift(c, t, clock)
			if shift ~= nil then
				local p = Level.clusterPosition(layout, c.id, math.max(0, t - shift), cfg)
				table.insert(list, {
					id = c.id,
					x = p.x,
					z = p.z,
					full = hitsOf[c.id] >= needed[c.id],
					lane = c.lane,
				})
			end
		end
		return list
	end

	-- Studs from the lead to the target at the shot's position time: the flight distance. Along the
	-- street only (the lead is in the target's lane when it engages), so the server flight time is a
	-- close, display-independent estimate of the client's. UNVERIFIED against the client's 2D distance.
	local function distanceTo(id: number, t: number, clock: Clock?): number
		local shift = shiftOf[id] or 0
		local leadZ = if clock then clock.leadZ0 else Level.leadZ(t, cfg)
		return math.max(0, Level.clusterPosition(layout, id, math.max(0, t - shift), cfg).z - leadZ)
	end

	local function pick(t: number, steer: Steer?, clock: Clock?): number?
		local leadZ = if clock then clock.leadZ0 else Level.leadZ(t, cfg)
		return Targeting.selectTarget(candidatesAt(t, clock), leadZ, steer, cfg)
	end

	function self.advance(
		_,
		t: number,
		sectionCount: number,
		steer: Steer?,
		shotPositionTime: number?,
		clock: Clock?,
		recruits: number?
	): Step
		if type(t) ~= "number" or t ~= t or t < 0 then
			error(`t must be a non-negative number, got {t}`, 2)
		end
		if t < lastT then
			error(`time went backwards: {t} < {lastT}`, 2)
		end
		if
			shotPositionTime ~= nil
			and (
				type(shotPositionTime) ~= "number"
				or shotPositionTime ~= shotPositionTime
				or shotPositionTime < lastT
				or shotPositionTime > t
			)
		then
			error(`shot position time must be between {lastT} and {t}`, 2)
		end
		lastT = t
		if
			recruits ~= nil and (type(recruits) ~= "number" or recruits ~= recruits or recruits < 0)
		then
			error(`recruits must be a non-negative number, got {tostring(recruits)}`, 2)
		end
		local tier = FireTable.tier(recruits or sectionCount * cfg.sectionSize, cfg)
		local interval = 1 / tier.shotsPerSecond
		local shots: { Shot } = {}

		local fired = 0
		while nextShot <= t do
			local at = nextShot
			-- One in flight (#234): drop what has resolved by `at`; if the tier's allowance is still
			-- used up, the next shot waits for the earliest to resolve.
			local live: { number } = {}
			local earliest = math.huge
			for _, r in resolveAt do
				if r > at then
					table.insert(live, r)
					earliest = math.min(earliest, r)
				end
			end
			resolveAt = live
			if #resolveAt >= tier.maxInFlight then
				nextShot = earliest
				continue
			end
			local target = pick(shotPositionTime or at, steer, clock)
			shotCount += 1
			local kind = Targeting.shotKind(shotCount, sectionCount, cfg)
			if target == nil then
				-- Continuous fire: nothing to hit, so the shot flies on as a display-only miss.
				table.insert(shots, {
					number = shotCount,
					time = at,
					miss = true,
					targetId = nil,
					kind = kind,
					hits = 0,
					needed = 0,
					filled = false,
					credit = nil,
					speed = tier.speed,
				})
				table.insert(resolveAt, at + ShotLook.missSeconds(tier.speed))
			else
				local r = self:hit(target)
				table.insert(shots, {
					number = shotCount,
					time = at,
					miss = false,
					targetId = target,
					kind = kind,
					hits = r.hits,
					needed = r.needed,
					filled = r.filled,
					credit = r.credit,
					speed = tier.speed,
				})
				table.insert(
					resolveAt,
					at
						+ ProjectileVisual.flightSeconds(
							kind,
							distanceTo(target, shotPositionTime or at, clock),
							tier.speed
						)
				)
			end
			nextShot = at + interval
			fired += 1
			if fired >= Targeting.MAX_SHOTS_PER_ADVANCE then
				nextShot = math.max(nextShot, t + interval) -- drop the backlog of a clock jump
				break
			end
		end

		-- Clusters that reached the parade unfilled are reported once for the attack phase.
		local passed: { number } = {}
		local z = if clock then clock.leadZ1 else Level.leadZ(t, cfg)
		for _, c in clusters do
			local shift = spawnShift(c, t, clock)
			if shift ~= nil and not reported[c.id] and hitsOf[c.id] < needed[c.id] then
				if Level.clusterPosition(layout, c.id, math.max(0, t - shift), cfg).z <= z then
					reported[c.id] = true
					table.insert(passed, c.id)
				end
			end
		end
		return { shots = shots, passed = passed }
	end

	return self
end

return Targeting
