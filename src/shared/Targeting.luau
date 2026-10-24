--!strict
-- Targeting and fire scheduler (issue #9; spec s3, s4, Amendment 1). Pure: no Roblox APIs.
-- Coordinates follow Level: z is distance along the street (the lead's forward position is
-- Level.leadZ(t)), x is lateral. A target's distance is z - leadZ.
--
-- Rules (Amendment 1): eligible = in range (distance <= firing.range), meter not full, not yet
-- passed (z > leadZ), and already spawned. Steering toward a side prefers eligible targets on that
-- side (Level.sideOf, which applies spectators.centerTolerance); otherwise, or if that side has none,
-- the nearest to the lead is chosen. No eligible target means no shots. A cluster that reaches the
-- parade unfilled is only REPORTED here (`passed`); the attack and any HP cost are issue #36.
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
	number: number, -- 1-based shot count for this session
	time: number,
	targetId: number,
	kind: ShotKind, -- visual variant only; every shot is exactly one hit
	hits: number, -- meter value after this hit
	needed: number,
	filled: boolean, -- true when the meter is full (this hit or earlier)
	credit: RunState.Result?, -- set only on the hit that fills the meter
}
export type HitResult = { hits: number, needed: number, filled: boolean, credit: RunState.Result? }
export type Step = { shots: { Shot }, passed: { number } }

export type Session = {
	advance: (self: Session, t: number, sectionCount: number, steer: Steer) -> Step,
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

-- Spec s4: min(12, 3 + sectionCount) hits per second, all numbers from Config.firing.
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
-- section exists; otherwise a note. Both are one hit. Hearts/snacks are client-side variants.
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

-- Pure target choice. Returns the chosen id or nil (no eligible target => no shots).
function Targeting.selectTarget(
	candidates: { Candidate },
	leadZ: number,
	steer: Steer,
	config: any?
): number?
	local cfg = config or Config
	local best: Candidate? = nil
	local bestDist = math.huge
	local bestOnSide = false
	for _, c in candidates do
		local dist = c.z - leadZ
		if not c.full and dist > 0 and dist <= cfg.firing.range then
			local onSide = steer ~= "center" and Level.sideOf(c.x, cfg) == steer
			local better = false
			if best == nil then
				better = true
			elseif onSide ~= bestOnSide then
				better = onSide
			elseif dist ~= bestDist then
				better = dist < bestDist
			else
				better = c.id < best.id
			end
			if better then
				best, bestDist, bestOnSide = c, dist, onSide
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

	function self.advance(_, t: number, sectionCount: number, steer: Steer): Step
		if type(t) ~= "number" or t ~= t or t < 0 then
			error(`t must be a non-negative number, got {t}`, 2)
		end
		if t < lastT then
			error(`time went backwards: {t} < {lastT}`, 2)
		end
		lastT = t
		local interval = 1 / Targeting.fireRate(sectionCount, cfg)
		local shots: { Shot } = {}

		while nextShot <= t do
			local at = nextShot
			local target = pick(at, steer)
			if target == nil and at < t then
				at = t -- nothing at the scheduled time: retry at the end of this step
				target = pick(at, steer)
			end
			if target == nil then
				nextShot = t -- no target => no shots, and no banked shots for later
				break
			end
			shotCount += 1
			local kind = Targeting.shotKind(shotCount, sectionCount, cfg)
			local r = self:hit(target)
			table.insert(shots, {
				number = shotCount,
				time = at,
				targetId = target,
				kind = kind,
				hits = r.hits,
				needed = r.needed,
				filled = r.filled,
				credit = r.credit,
			})
			nextShot = at + interval
		end

		-- Clusters that reached the parade unfilled: reported once, no credit, no penalty here.
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
