--!strict
-- Targeting and fire scheduler (issue #9; spec s3, s4, Amendment 1). Pure: no Roblox APIs.
-- Coordinates follow Level: z is distance along the street (the lead's forward position is
-- Level.leadZ(t)), x is lateral. A target's distance is z - leadZ.
--
-- Rules (Amendment 1, as amended for issue #142): eligible = in range (distance <= firing.range),
-- meter not full, not yet passed (z > leadZ), and already spawned. Steering decides the side:
-- steer left engages only eligible hordes on the left, steer right only on the right (Level.sideOf,
-- which applies spectators.centerTolerance). Center steering engages nothing, and there is no
-- fallback to the other side. Among eligible hordes on the steered side, the nearest to the lead is
-- chosen. Reaching the parade reports an unfilled cluster in `passed` for the attack phase; later
-- hits to a passed cluster are inert.
--
-- Firing is CONTINUOUS (ADR 0004, spec Amendment 2): a shot every 1 / fireRate seconds whether or
-- not anything is in range. A shot with an eligible target is a hit (one meter hit, credit-once).
-- A shot with none is a MISS: `miss = true`, no targetId, and it touches no meter, no RunState and
-- no life. Misses still advance the shot counter, so the gift cadence (every Nth shot) is unchanged.
--
-- Per advance() the order matches the same-tick ordering of Amendment 1: shots land, meters fill
-- and conversions are credited (RunState.creditCluster, exactly once), then unconverted clusters
-- that reached the parade are reported. Cluster ids are numbers in Level; RunState ids are the
-- same ids as strings (tostring).
local Config = require("./Config")
local CrowdMath = require("./CrowdMath")
local Level = require("./Level")
local RunState = require("./RunState")

export type Steer = "left" | "right" | "center"
export type ShotKind = "note" | "gift"
-- A candidate for selectTarget: `z` and `x` are the cluster's current position.
export type Candidate = { id: number, x: number, z: number, full: boolean }

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
}
export type HitResult = { hits: number, needed: number, filled: boolean, credit: RunState.Result? }
export type Step = { shots: { Shot }, passed: { number } }

export type Session = {
	advance: (
		self: Session,
		t: number,
		sectionCount: number,
		steer: Steer,
		shotPositionTime: number?
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

-- Spec s4 as amended (Amendment 2): min(cap, base + perSection * sectionCount) shots per second,
-- all numbers from Config.firing (defaults 6, 20, +1 per section).
function Targeting.fireRate(sectionCount: number, config: any?): number
	if
		type(sectionCount) ~= "number"
		or sectionCount < 0
		or sectionCount ~= math.floor(sectionCount)
	then
		error(`sectionCount must be a non-negative integer, got {sectionCount}`, 2)
	end
	local f = (config or Config).firing
	return math.min(f.cap, f.base + f.perSection * sectionCount)
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

-- Pure target choice (issue #142). Only eligible candidates on the steered side are considered;
-- center steering considers none. Returns the nearest such id, ties broken by lowest id, or nil.
function Targeting.selectTarget(
	candidates: { Candidate },
	leadZ: number,
	steer: Steer,
	config: any?
): number?
	if steer == "center" then
		return nil
	end
	local cfg = config or Config
	local best: Candidate? = nil
	local bestDist = math.huge
	for _, c in candidates do
		local dist = c.z - leadZ
		if
			not c.full
			and dist > 0
			and dist <= cfg.firing.range
			and Level.sideOf(c.x, cfg) == steer
		then
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

	local function candidatesAt(t: number): { Candidate }
		local list: { Candidate } = {}
		for _, c in clusters do
			if t >= c.spawnTime then
				local p = Level.clusterPosition(layout, c.id, t, cfg)
				table.insert(
					list,
					{ id = c.id, x = p.x, z = p.z, full = hitsOf[c.id] >= needed[c.id] }
				)
			end
		end
		return list
	end

	local function pick(t: number, steer: Steer): number?
		return Targeting.selectTarget(candidatesAt(t), Level.leadZ(t, cfg), steer, cfg)
	end

	function self.advance(
		_,
		t: number,
		sectionCount: number,
		steer: Steer,
		shotPositionTime: number?
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
		local interval = 1 / Targeting.fireRate(sectionCount, cfg)
		local shots: { Shot } = {}

		local fired = 0
		while nextShot <= t do
			local at = nextShot
			local target = pick(shotPositionTime or at, steer)
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
				})
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
				})
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
		local z = Level.leadZ(t, cfg)
		for _, c in clusters do
			if t >= c.spawnTime and not reported[c.id] and hitsOf[c.id] < needed[c.id] then
				if Level.clusterPosition(layout, c.id, t, cfg).z <= z then
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
