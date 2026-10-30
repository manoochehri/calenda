--!strict
-- Layout validator (issue #7). Pure: no Roblox APIs. Proves, from Config speed and the authored data,
-- that a layout matches the spec s9 timeline, grows by a bounded amount, can be completed with no
-- spending, has safe early gates, and that the intended recruit total is reachable at the BASE fire
-- rate (conservative: sections would only make firing faster).
--
-- Extension point (issues #36 / #17): `check(layout, config, extraChecks)` runs each extra check
-- `(ctx) -> (boolean, string?)` after the base checks, with ctx = { layout, config, report }.
-- report.clusters[id] = { encounterTime, convertTime, reachTime } is the per-cluster arrival data
-- (an unconverted cluster has reachTime and no convertTime: that is when it attacks). The life
-- trajectory checks (no-input run defeated, competent run completed with followers left, ADR 0006)
-- plug in there.
-- Those checks use the same RunDriver.TICK_DT and phase order as the server.
local CrowdMath = require("./CrowdMath")
local Config = require("./Config")
local Emergence = require("./Emergence")
local LaneGeometry = require("./LaneGeometry")
local Level = require("./Level")
local RunDriver = require("./RunDriver")

type Layout = Level.Layout

export type ClusterInfo = { encounterTime: number?, convertTime: number?, reachTime: number? }
export type LifeTrajectoryPoint = { time: number, total: number }
export type LifeScenario = { outcome: string?, total: number, trajectory: { LifeTrajectoryPoint } }
export type Report = {
	ok: boolean,
	errors: { string },
	firstEncounterTime: number,
	firstConversionTime: number,
	gateTimes: { number },
	firstSectionTimeWorst: number,
	finalGateTime: number,
	largestGainGateTime: number,
	plazaTime: number,
	bestFinal: number,
	worstFinal: number,
	routeCount: number,
	recruitTotalBaseRate: number,
	recruitTotalAvailable: number,
	clusters: { [number]: ClusterInfo },
	lifeScenarios: { [string]: LifeScenario }?,
}
export type Context = { layout: any, config: any, report: Report }
export type ExtraCheck = (ctx: Context) -> (boolean, string?)

-- Spec s9 timeline windows (seconds of run time).
local FIRST_CLUSTER_BY = 10
local EARLY_FROM, EARLY_TO = 10, 25
local FINAL_FROM, FINAL_TO = 65, 90
local PLAZA_TIME, PLAZA_TOLERANCE = 90, 2
local MIN_DECISION_SECONDS = 3 -- spec s6: enough distance to read and steer
local MAX_GATES = 12 -- routes are enumerated (2^gates)
local DT = RunDriver.TICK_DT

local function emptyReport(): Report
	return {
		ok = false,
		errors = {},
		firstEncounterTime = math.huge,
		firstConversionTime = math.huge,
		gateTimes = {},
		firstSectionTimeWorst = math.huge,
		finalGateTime = 0,
		largestGainGateTime = 0,
		plazaTime = 0,
		bestFinal = 0,
		worstFinal = 0,
		routeCount = 0,
		recruitTotalBaseRate = 0,
		recruitTotalAvailable = 0,
		clusters = {},
	}
end

local function isNum(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function validOp(op: any): boolean
	if type(op) ~= "table" or not isNum(op.value) or op.value ~= math.floor(op.value) then
		return false
	end
	return (op.kind == "add" and op.value >= 1) or (op.kind == "multiply" and op.value >= 2)
end

-- Structural checks; every problem found is appended to errs.
local function structure(layout: any, cfg: any, errs: { string })
	local function bad(msg: string)
		table.insert(errs, msg)
	end
	for _, key in
		{
			"streetLength",
			"plazaStart",
			"halfWidth",
			"leadLimit",
			"maxTotal",
			"intendedRecruitTotal",
			"seed",
		}
	do
		if not isNum(layout[key]) then
			bad(`{key} must be a finite number`)
		end
	end
	if
		isNum(layout.leadLimit) and (layout.leadLimit <= 0 or layout.leadLimit > layout.halfWidth)
	then
		bad(`leadLimit must be above 0 and at most halfWidth {layout.halfWidth}`)
	end
	if
		type(layout.gates) ~= "table"
		or type(layout.clusters) ~= "table"
		or type(layout.obstacles) ~= "table"
	then
		bad("gates, clusters and obstacles must be lists")
		return
	end
	if #errs > 0 then
		return
	end
	if layout.streetLength < layout.plazaStart then
		bad("streetLength must be >= plazaStart")
	end
	local plazaTime = Level.timeAtZ(layout.plazaStart, cfg)
	if math.abs(plazaTime - PLAZA_TIME) > PLAZA_TOLERANCE then
		bad(`plaza at {plazaTime} s at Config speed, expected about {PLAZA_TIME} s`)
	end

	local seenGate: { [number]: boolean } = {}
	local prevZ = 0
	for i, g in layout.gates do
		if seenGate[g.id] then
			bad(`duplicate gate id {g.id}`)
		end
		seenGate[g.id] = true
		if not isNum(g.z) or g.z <= 0 or g.z >= layout.plazaStart then
			bad(`gate {g.id} z must be between 0 and plazaStart`)
			continue
		end
		if i > 1 then
			if g.z <= prevZ then
				bad("gates must be sorted by z, strictly ascending")
			elseif Level.timeAtZ(g.z - prevZ, cfg) < MIN_DECISION_SECONDS then
				bad(
					`gate {g.id} too close to the previous gate (under {MIN_DECISION_SECONDS} s to read and steer)`
				)
			end
		end
		prevZ = g.z
		if not validOp(g.left) or not validOp(g.right) then
			bad(`gate {g.id} has an invalid op (add >= 1 or multiply >= 2, integers)`)
		end
	end
	if #layout.gates > MAX_GATES then
		bad(`more than {MAX_GATES} gates cannot be enumerated`)
	end

	if #layout.obstacles == 0 then
		bad("layout needs at least one obstacle")
	end
	for _, o in layout.obstacles do
		if o.side ~= "left" and o.side ~= "right" then
			bad(`obstacle {o.id} has an invalid side`)
		end
		if not isNum(o.z) or o.z <= 0 or o.z >= layout.plazaStart then
			bad(`obstacle {o.id} z must be between 0 and plazaStart`)
		elseif Level.timeAtZ(o.z, cfg) < EARLY_TO then
			bad(`obstacle {o.id} falls in the early safe phase (before {EARLY_TO} s)`)
		end
	end

	local seenPickup: { [number]: boolean } = {}
	for _, p in layout.pickups or {} do
		if seenPickup[p.id] then
			bad(`duplicate pickup id {p.id}`)
		end
		seenPickup[p.id] = true
		if not isNum(p.z) or p.z <= 0 or p.z >= layout.plazaStart then
			bad(`pickup {p.id} z must be between 0 and plazaStart`)
		end
		if p.lane ~= "left" and p.lane ~= "center" and p.lane ~= "right" then
			bad(`pickup {p.id} has an invalid lane`)
		end
	end

	local seenCluster: { [number]: boolean } = {}
	local waveLane: { [number]: string } = {}
	for _, c in layout.clusters do
		if seenCluster[c.id] then
			bad(`duplicate cluster id {c.id}`)
		end
		seenCluster[c.id] = true
		if Config.clusterTypes[c.type] == nil then
			bad(`cluster {c.id}: unknown cluster type {c.type}`)
		end
		if not isNum(c.spawnTime) or c.spawnTime < 0 then
			bad(`cluster {c.id}: spawnTime must be >= 0`)
		end
		if
			type(c.spawn) ~= "table"
			or not isNum(c.spawn.x)
			or not isNum(c.spawn.z)
			or type(c.path) ~= "table"
		then
			bad(`cluster {c.id}: needs spawn point and path list`)
			continue
		end
		if c.spawn.z <= 0 then
			bad(`cluster {c.id}: spawn must be ahead of the lead's start (z > 0)`)
		end
		local pz = c.spawn.z
		local inside = math.abs(c.spawn.x) <= layout.halfWidth
		for _, p in c.path do
			if not isNum(p.x) or not isNum(p.z) then
				bad(`cluster {c.id}: path points need numeric x and z`)
				break
			end
			if p.z > pz then
				bad(`cluster {c.id}: path must not move away from the parade`)
			end
			pz = p.z
			inside = inside and math.abs(p.x) <= layout.halfWidth
		end
		if not inside then
			bad(`cluster {c.id}: outside street (halfWidth {layout.halfWidth})`)
		end
		-- ADR 0010 item 2: the authored lane must be the lane that owns the spawn's x.
		local lane = LaneGeometry.laneOf(c.spawn.x)
		if c.lane ~= lane then
			bad(
				`cluster {c.id}: lane {tostring(c.lane)} does not match spawn x {c.spawn.x} (lane {tostring(
					lane
				)})`
			)
		end
		if waveLane[c.wave] == nil then
			waveLane[c.wave] = c.lane
		elseif waveLane[c.wave] ~= c.lane then
			bad(`wave {c.wave} mixes lanes`)
		end
	end
	local waves: { number } = {}
	for w in waveLane do
		table.insert(waves, w)
	end
	table.sort(waves)
	for i = 1, #waves do
		local lane = waveLane[waves[i]]
		if lane == "center" then
			bad(`wave {waves[i]} must start on a sidewalk, not the center`)
		elseif i > 1 and lane == waveLane[waves[i - 1]] then
			bad(`waves must alternate sides (wave {waves[i]} repeats {lane})`)
		end
	end
end

type Event = {
	tick: number,
	phase: number,
	order: number,
	kind: string,
	gate: number?,
	reward: number?,
	obstacle: number?,
}

local function simulate(layout: any, cfg: any, report: Report, errs: { string })
	local rate = cfg.firing.base
	local range = cfg.firing.range
	local plazaTime = Level.timeAtZ(layout.plazaStart, cfg)
	local ticks = math.ceil(plazaTime / DT)
	local events: { Event } = {}
	local order = 0
	local function push(e: Event)
		order += 1
		e.order = order
		table.insert(events, e)
	end

	local state: { [number]: { hits: number, converted: boolean, reached: boolean } } = {}
	local clusters: { any } = {}
	for _, c in layout.clusters do
		state[c.id] = { hits = 0, converted = false, reached = false }
		report.clusters[c.id] = {}
		table.insert(clusters, c)
		report.recruitTotalAvailable += Config.clusterTypes[c.type].reward
	end
	table.sort(clusters, function(a, b)
		return a.id < b.id
	end)

	local acc = 0
	for k = 1, ticks do
		local t0 = (k - 1) * DT
		local t1 = k * DT
		local z0, z1 = Level.leadZ(t0, cfg), Level.leadZ(t1, cfg)

		-- 1. shots land, meters fill, conversions credited
		local function pickTarget(): any?
			local best: any? = nil
			local bestD = math.huge
			for _, c in clusters do
				local s = state[c.id]
				if t0 >= c.spawnTime and not s.converted and not s.reached then
					local d = Level.clusterPosition(layout, c.id, t0, cfg).z - z0
					if d <= range then
						local info = report.clusters[c.id]
						if info.encounterTime == nil then
							info.encounterTime = t0
						end
						if d < bestD then
							best, bestD = c, d
						end
					end
				end
			end
			return best
		end
		acc += rate * DT
		local target = pickTarget()
		if target == nil then
			-- Continuous fire (ADR 0004): with nothing in range the due shots are misses; they
			-- are spent, not banked, so only the fractional progress to the next shot carries on.
			acc -= math.floor(acc + 1e-9)
		end
		while target ~= nil and acc >= 1 - 1e-9 do
			acc -= 1
			local s = state[target.id]
			local def = Config.clusterTypes[target.type]
			s.hits += 1
			if s.hits >= def.hits then
				s.converted = true
				report.clusters[target.id].convertTime = t0
				push({ tick = k, phase = 0, order = 0, kind = "convert", reward = def.reward })
				target = pickTarget()
			end
		end

		-- 2. lead moves, gates then obstacles resolve
		for _, g in layout.gates do
			if g.z > z0 and g.z <= z1 then
				push({ tick = k, phase = 1, order = 0, kind = "gate", gate = g.id })
			end
		end
		for _, o in layout.obstacles do
			if o.z > z0 and o.z <= z1 then
				push({ tick = k, phase = 2, order = 0, kind = "obstacle", obstacle = o.id })
			end
		end

		-- 3. unconverted clusters that reached the parade (attack time for the life extension)
		for _, c in clusters do
			local s = state[c.id]
			if t0 >= c.spawnTime and not s.converted and not s.reached then
				if Level.clusterPosition(layout, c.id, t1, cfg).z <= z1 then
					s.reached = true
					report.clusters[c.id].reachTime = t1
				end
			end
		end
	end

	for _, c in clusters do
		local info = report.clusters[c.id]
		if info.convertTime == nil and info.reachTime == nil then
			table.insert(
				errs,
				`cluster {c.id} neither converts nor reaches the parade before the plaza`
			)
		end
		if info.convertTime ~= nil then
			report.recruitTotalBaseRate += Config.clusterTypes[c.type].reward
			report.firstConversionTime = math.min(report.firstConversionTime, info.convertTime)
		end
		if info.encounterTime ~= nil then
			report.firstEncounterTime = math.min(report.firstEncounterTime, info.encounterTime)
		end
	end

	table.sort(events, function(a, b)
		if a.tick ~= b.tick then
			return a.tick < b.tick
		end
		if a.phase ~= b.phase then
			return a.phase < b.phase
		end
		return a.order < b.order
	end)
	return events
end

local function routes(layout: any, cfg: any, events: { Event }, report: Report)
	local gateById: { [number]: any } = {}
	local gateIndex: { [number]: number } = {}
	for i, g in layout.gates do
		gateById[g.id] = g
		gateIndex[g.id] = i
	end
	local obstacleById: { [number]: any } = {}
	for _, o in layout.obstacles do
		obstacleById[o.id] = o
	end
	local n = #layout.gates
	local count = 2 ^ n
	report.routeCount = count
	local bestFinal, worstFinal = 0, math.huge
	local worstSection = 0
	local gainMax: { number } = {}
	for i = 1, n do
		gainMax[i] = 0
	end

	for r = 0, count - 1 do
		local hit = Config.startingTotal
		local dodge = hit
		local side: string? = nil
		local sectionAt: number? = if hit >= cfg.sectionSize then 0 else nil
		for _, e in events do
			local at = e.tick * DT
			if e.kind == "convert" then
				hit += e.reward :: number
				dodge += e.reward :: number
			elseif e.kind == "gate" then
				local gi = gateIndex[e.gate :: number]
				local g = gateById[e.gate :: number]
				local bit = (r // (2 ^ (gi - 1))) % 2
				local op = if bit == 1 then g.right else g.left
				side = if bit == 1 then "right" else "left"
				local before = dodge
				hit = CrowdMath.applyOp(hit, op)
				dodge = CrowdMath.applyOp(dodge, op)
				gainMax[gi] = math.max(gainMax[gi], dodge - before)
			else
				if obstacleById[e.obstacle :: number].side == side then
					hit = CrowdMath.applyOp(hit, CrowdMath.obstacleOp())
				end
			end
			if sectionAt == nil and hit >= cfg.sectionSize then
				sectionAt = at
			end
		end
		bestFinal = math.max(bestFinal, dodge)
		worstFinal = math.min(worstFinal, hit)
		worstSection = math.max(worstSection, sectionAt or math.huge)
	end
	report.bestFinal = bestFinal
	report.worstFinal = worstFinal
	report.firstSectionTimeWorst = worstSection

	local bestGate, bestGain = 0, -1
	for i = 1, n do
		if gainMax[i] > bestGain then
			bestGate, bestGain = i, gainMax[i]
		end
	end
	if n > 0 then
		report.largestGainGateTime = Level.timeAtZ(layout.gates[bestGate].z, cfg)
	end
end

local function check(layout: any, config: any?, extraChecks: { ExtraCheck }?): Report
	local cfg = config or Config
	local report = emptyReport()
	local errs = report.errors
	if type(layout) ~= "table" then
		table.insert(errs, "layout must be a table")
		return report
	end
	structure(layout, cfg, errs)
	if #errs > 0 then
		return report
	end

	report.plazaTime = Level.timeAtZ(layout.plazaStart, cfg)
	for _, g in layout.gates do
		table.insert(report.gateTimes, Level.timeAtZ(g.z, cfg))
	end
	local events = simulate(layout, cfg, report, errs)
	routes(layout, cfg, events, report)

	-- spec s9 windows
	if report.firstEncounterTime > FIRST_CLUSTER_BY then
		table.insert(
			errs,
			`first cluster encountered at {report.firstEncounterTime} s, after {FIRST_CLUSTER_BY} s`
		)
	end
	if report.firstConversionTime > FIRST_CLUSTER_BY then
		table.insert(
			errs,
			`first cluster conversion at {report.firstConversionTime} s, after {FIRST_CLUSTER_BY} s`
		)
	end
	local early = 0
	for i, t in report.gateTimes do
		if t < EARLY_FROM then
			table.insert(errs, `gate {layout.gates[i].id} crosses at {t} s, before {EARLY_FROM} s`)
		elseif t <= EARLY_TO then
			early += 1
		end
	end
	if early < 2 then
		table.insert(errs, `need two early gates in {EARLY_FROM}-{EARLY_TO} s, found {early}`)
	end
	if report.firstSectionTimeWorst > EARLY_TO then
		table.insert(
			errs,
			`first section ({cfg.sectionSize} followers) at {report.firstSectionTimeWorst} s on the worst route, after {EARLY_TO} s`
		)
	end
	local nGates = #report.gateTimes
	report.finalGateTime = if nGates > 0 then report.gateTimes[nGates] else 0
	if report.finalGateTime < FINAL_FROM or report.finalGateTime > FINAL_TO then
		table.insert(
			errs,
			`final route decision at {report.finalGateTime} s, outside {FINAL_FROM}-{FINAL_TO} s`
		)
	end
	if report.largestGainGateTime < FINAL_FROM or report.largestGainGateTime > FINAL_TO then
		table.insert(
			errs,
			`largest growth gate at {report.largestGainGateTime} s, outside {FINAL_FROM}-{FINAL_TO} s`
		)
	end

	-- tension from the top (issue #65): waves spawn beyond the camera's view, are in view for at
	-- least MIN_APPROACH_SECONDS before they arrive, and nothing is in view during the calm opening
	for _, e in Emergence.check(layout, cfg) do
		table.insert(errs, e)
	end

	-- growth and completability (no spending exists in the model: only recruits, gates, obstacles)
	if report.bestFinal > layout.maxTotal then
		table.insert(
			errs,
			`best route reaches {report.bestFinal}, above maxTotal {layout.maxTotal}`
		)
	end
	if report.bestFinal < cfg.finaleThresholds[#cfg.finaleThresholds] then
		table.insert(errs, `best route {report.bestFinal} cannot reach the top finale tier`)
	end
	if report.worstFinal < cfg.sectionSize then
		table.insert(
			errs,
			`worst route ends with {report.worstFinal}, below one section (needs spending to recover)`
		)
	end
	if report.recruitTotalBaseRate < layout.intendedRecruitTotal then
		table.insert(
			errs,
			`recruit total {report.recruitTotalBaseRate} at base fire rate is below intended {layout.intendedRecruitTotal}`
		)
	end

	report.ok = #errs == 0
	for _, extra in extraChecks or {} do
		local ok, msg = extra({ layout = layout, config = cfg, report = report })
		if not ok then
			table.insert(errs, msg or "extra check failed")
		end
	end
	report.ok = #errs == 0
	return report
end

local function validate(layout: any, config: any?): (boolean, string?)
	local report = check(layout, config)
	return report.ok, report.errors[1]
end

return { check = check, validate = validate }
