--!strict
-- The one remote contract between server and client (issue #8). Names and payload shapes live
-- here and nowhere else; the server creates the instances, the client looks them up by `names`.
--
-- Trust model: the client may send exactly three things: a steering intent, a replay request and
-- a start request (issue #72; Start and Replay carry no payload, every argument is ignored).
-- It can never send a total, a gate or cluster id, a position, a hit or a score. The server
-- decodes with `decodeSteer` (shape check only; clamping and rate limiting are in Steering and
-- RunDriver) and ignores every other field. Server -> client payloads are display-only.
local Remotes = {}

Remotes.folderName = "CalendaRemotes"

Remotes.names = table.freeze({
	steer = "Steer", -- client -> server RemoteEvent: SteerPayload
	replay = "Replay", -- client -> server RemoteEvent: no payload (arguments ignored)
	start = "Start", -- client -> server RemoteEvent: no payload (arguments ignored); begins a ready run
	state = "State", -- server -> client RemoteEvent: StatePayload (about 10 Hz)
	event = "Event", -- server -> client RemoteEvent: EventPayload (discrete, immediate)
})

-- Client -> server. `x` is the desired lateral position (studs, negative = left).
export type SteerPayload = { x: number }

-- Issue #156 (ADR 0010 item 5): the one lane encounter the client may show. Display only: it never
-- awards a follower or consumes a target. `lane` is the pickup's authored lane; `progress` in [0,1]
-- is how far the lead is through the encounter's approach span; `remaining` is studs to its plane.
export type Encounter = {
	id: string, -- kind prefix + number: p<n> pickup, r<n> recruit, u<n> unlock, b<n> boss (ENCOUNTER_ID_PREFIX)
	kind: string, -- "pickup" | "recruit" | "unlock" | "boss"; see decodeEncounter
	lane: string, -- "left" | "center" | "right"
	progress: number, -- 0..1
	remaining: number, -- 0..ENCOUNTER_MAX_REMAINING studs to the plane
	active: boolean, -- true once the lead is inside the span
}

-- Server -> client. Compact and display-only. `over` is true once the run has ended.
export type StatePayload = {
	t: number,
	z: number,
	x: number,
	total: number,
	best: number,
	over: boolean,
	phase: string, -- "ready" (paused, waiting for Start) | "running" | "over"; see isPhase
	outcome: string?,
	score: number?,
	level: number, -- issue #128: 1-based index of the level being played (the server decides it)
	levelName: string, -- issue #129: the authored display name for the current level
	encounter: Encounter?, -- issue #156: the lane encounter to show; absent when none is pending
	stage: string, -- issue #162: "traveling" | "mini-boss-combat" | "final-boss-combat"; see isStage
	holdZ: number?, -- issue #162: z of the next unresolved checkpoint plane (or the one held at)
	-- Issue #162 wire contract (ADR 0010 item 5, spec Amendments 15 and 16). Level-triggered: a client
	-- that missed any event recovers all of this from the next State.
	v: number, -- Remotes.VERSION; a client refuses any other
	runId: number, -- positive integer; +1 on every accepted Replay
	levelId: string, -- "level<level>"; the once-only key's level part
	simTime: number, -- the combat clock (same value as t); restarts at 0 on each level and replay
	zVelocity: number, -- studs/s the lead moves forward now; 0 whenever stage is not "traveling"
	boostExpiry: number?, -- simTime at which the marching-drum boost ends; absent = no boost
	roster: { string }, -- named members in acquisition order; opaque ids, at most ROSTER_MAX
}

-- Server -> client discrete events. ids are layout ids, for animation lookup only.
export type EventPayload = {
	kind: string,
	id: number?,
	side: string?,
	before: number?,
	after: number?,
	score: number?,
	hits: number?, -- cluster: meter value after the shot, integer 0..1000 (ClusterFeed)
	shot: string?, -- cluster, miss: "note" | "gift"
	n: number?, -- miss: shot number, integer 1..1000000 (ClusterFeed); look only
}

local EVENT_KINDS: { [string]: boolean } = {
	gate = true,
	obstacle = true,
	complete = true,
	cluster = true,
	miss = true, -- continuous-fire shot with no target (ADR 0004); display only
	attack = true,
	defeated = true,
	pickup = true, -- issue #156: an optional +1 pickup was collected (display and log only)
}

function Remotes.isEventKind(kind: any): boolean
	return type(kind) == "string" and EVENT_KINDS[kind] == true
end

local function isFinite(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- Upper bound on Encounter.remaining (studs). Any authored distance beyond it is clamped, so the
-- wire value is always finite and bounded.
Remotes.ENCOUNTER_MAX_REMAINING = 1000 -- [default] studs

-- Issue #162: the kind decides the id prefix, so a forged kind/id pair cannot pass.
local ENCOUNTER_ID_PREFIX: { [string]: string } = {
	pickup = "p",
	recruit = "r",
	unlock = "u",
	boss = "b",
}
local ENCOUNTER_LANES: { [string]: boolean } = { left = true, center = true, right = true }

-- The one validation of an encounter, used for the server's encode and the client's decode. Returns
-- a fresh table holding only the known fields, or nil for anything malformed. Extra fields are
-- never copied, so no reward or target field can pass through.
function Remotes.decodeEncounter(e: any): Encounter?
	if type(e) ~= "table" then
		return nil
	end
	local r = e :: any
	local id, kind, lane = r.id, r.kind, r.lane
	if type(kind) ~= "string" or ENCOUNTER_ID_PREFIX[kind] == nil then
		return nil
	end
	if
		type(id) ~= "string"
		or #id < 2
		or #id > 16
		or string.match(id, `^{ENCOUNTER_ID_PREFIX[kind]}%d+$`) == nil
	then
		return nil
	end
	if type(lane) ~= "string" or ENCOUNTER_LANES[lane] ~= true then
		return nil
	end
	local progress, remaining, active = r.progress, r.remaining, r.active
	if not isFinite(progress) or progress < 0 or progress > 1 then
		return nil
	end
	if not isFinite(remaining) or remaining < 0 or remaining > Remotes.ENCOUNTER_MAX_REMAINING then
		return nil
	end
	if type(active) ~= "boolean" then
		return nil
	end
	return {
		id = id,
		kind = kind,
		lane = lane,
		progress = progress,
		remaining = remaining,
		active = active,
	}
end

local PHASES: { [string]: boolean } = { ready = true, running = true, over = true }

function Remotes.isPhase(p: any): boolean
	return type(p) == "string" and PHASES[p] == true
end

-- Issue #162 (ADR 0010 item 5): where the lead is in the route. Distinct from `phase`.
local STAGES: { [string]: boolean } = {
	traveling = true,
	["mini-boss-combat"] = true,
	["final-boss-combat"] = true,
	cleared = true, -- the final boss is down; the celebration runs before the next level
}

function Remotes.isStage(s: any): boolean
	return type(s) == "string" and STAGES[s] == true
end

-- Start (and Replay) take no data. Any arguments are discarded; always returns true so the
-- handler's only inputs are the sender and the server clock.
function Remotes.decodeStart(...: any): boolean
	local _ignored = select("#", ...) -- count only; no argument is ever read
	return true
end

-- Returns the requested lateral position, or nil for any payload that is not exactly a table
-- holding a finite number `x`. Extra fields are never read.
function Remotes.decodeSteer(payload: any): number?
	if type(payload) ~= "table" then
		return nil
	end
	local x = (payload :: any).x
	if not isFinite(x) then
		return nil
	end
	return x
end

local function round2(v: number): number
	return math.floor(v * 100 + 0.5) / 100
end

export type Snapshot = {
	time: number,
	z: number,
	x: number,
	total: number,
	best: number,
	phase: string?, -- optional; derived from outcome when absent or invalid
	outcome: string?,
	score: number?,
	level: number?, -- issue #128: 1-based index of the level being played; absent = 1
	levelName: string?, -- issue #129: authored display name; absent = the level index
	encounter: Encounter?, -- issue #156: the lane encounter to show, if any
	stage: string?, -- issue #162: absent or invalid = "traveling"
	holdZ: number?, -- issue #162: hold plane; dropped unless finite
	runId: number?, -- issue #162: positive integer; absent or invalid = 1
	levelId: string?, -- issue #162: "level<n>"; absent or invalid = derived from `level`
	zVelocity: number?, -- issue #162: clamped to 0..MAX_Z_VELOCITY; absent or invalid = 0
	boostExpiry: number?, -- issue #162: dropped unless finite and >= 0
	roster: { string }?, -- issue #162: dropped (empty) unless valid; see isRoster
}

-- Issue #162 contract bounds. Everything below is display-only data: none of it can award anything.
Remotes.VERSION = 2 -- bump on any incompatible State change; a client refuses a different value
Remotes.RUN_ID_MAX = 1000000 -- [default] bound so a forged huge id cannot lock a receiver out
Remotes.ROSTER_MAX = 8 -- [default] the roster size ceiling (spec Amendment 16)
Remotes.MAX_Z_VELOCITY = 100 -- [default] studs/s; far above Config.speed, so only forgeries exceed it

local function isRunId(v: any): boolean
	return isFinite(v) and v >= 1 and v <= Remotes.RUN_ID_MAX and v == math.floor(v)
end

local function levelIndexOf(levelId: any): number?
	if type(levelId) ~= "string" or #levelId > 14 then
		return nil
	end
	local n = string.match(levelId, "^level(%d+)$")
	return if n ~= nil then tonumber(n) else nil
end

local function isLevelId(v: any): boolean
	local n = levelIndexOf(v)
	return n ~= nil and n >= 1
end

-- A roster is an ordered, distinct list of opaque ids (lowercase letters and underscores), at most
-- ROSTER_MAX long. `allowed` (the active roster's ids, when the caller has them) narrows it further.
function Remotes.isRoster(r: any, allowed: { [string]: boolean }?): boolean
	if type(r) ~= "table" then
		return false
	end
	local list = r :: { any }
	local n = #list
	if n > Remotes.ROSTER_MAX then
		return false
	end
	local keys = 0
	for _ in list do
		keys += 1
	end
	if keys ~= n then
		return false
	end
	local seen: { [string]: boolean } = {}
	for i = 1, n do
		local id = list[i]
		if
			type(id) ~= "string"
			or #id < 1
			or #id > 24
			or string.match(id, "^[a-z][a-z_]*$") == nil
		then
			return false
		end
		if seen[id] or (allowed ~= nil and allowed[id] ~= true) then
			return false
		end
		seen[id] = true
	end
	return true
end

function Remotes.encodeState(s: Snapshot): StatePayload
	-- A finished run is always "over"; otherwise a valid supplied phase, else "running".
	local phase = if s.outcome ~= nil
		then "over"
		elseif Remotes.isPhase(s.phase) and s.phase ~= "over" then s.phase :: string
		else "running"
	local level = if type(s.level) == "number" and s.level >= 1 then math.floor(s.level) else 1
	return {
		v = Remotes.VERSION,
		runId = if isRunId(s.runId) then s.runId :: number else 1,
		levelId = if isLevelId(s.levelId) then s.levelId :: string else `level{level}`,
		simTime = round2(s.time),
		zVelocity = if isFinite(s.zVelocity)
			then math.clamp(round2(s.zVelocity :: number), 0, Remotes.MAX_Z_VELOCITY)
			else 0,
		boostExpiry = if isFinite(s.boostExpiry) and (s.boostExpiry :: number) >= 0
			then round2(s.boostExpiry :: number)
			else nil,
		roster = if Remotes.isRoster(s.roster) then table.clone(s.roster :: { string }) else {},
		phase = phase,
		t = round2(s.time),
		z = round2(s.z),
		x = round2(s.x),
		total = s.total,
		best = s.best,
		over = s.outcome ~= nil,
		outcome = s.outcome,
		score = s.score,
		level = level,
		levelName = if type(s.levelName) == "string" and s.levelName ~= "" then s.levelName else "",
		encounter = Remotes.decodeEncounter(s.encounter),
		stage = if Remotes.isStage(s.stage) then s.stage :: string else "traveling",
		holdZ = if isFinite(s.holdZ) then round2(s.holdZ :: number) else nil,
	}
end

-- The client's one validation of a State. Whole-payload and strict: it returns a fresh table holding
-- only the known fields, or nil if ANY field is malformed (a forged or corrupted State is dropped, not
-- repaired). `allowedRoster` optionally restricts roster ids to the active roster. Everything
-- Remotes.encodeState produces decodes.
function Remotes.decodeState(p: any, allowedRoster: { [string]: boolean }?): StatePayload?
	if type(p) ~= "table" then
		return nil
	end
	local r = p :: any
	if r.v ~= Remotes.VERSION or not isRunId(r.runId) or not isLevelId(r.levelId) then
		return nil
	end
	if type(r.level) ~= "number" or r.level ~= math.floor(r.level) or r.level < 1 then
		return nil
	end
	if r.levelId ~= `level{r.level}` then
		return nil
	end
	if not Remotes.isPhase(r.phase) or not Remotes.isStage(r.stage) then
		return nil
	end
	if type(r.over) ~= "boolean" or type(r.levelName) ~= "string" or #r.levelName > 64 then
		return nil
	end
	for _, key in { "t", "simTime", "total", "best" } do
		if not isFinite(r[key]) or r[key] < 0 then
			return nil
		end
	end
	if not isFinite(r.z) or not isFinite(r.x) then
		return nil
	end
	if not isFinite(r.zVelocity) or r.zVelocity < 0 or r.zVelocity > Remotes.MAX_Z_VELOCITY then
		return nil
	end
	if r.boostExpiry ~= nil and (not isFinite(r.boostExpiry) or r.boostExpiry < 0) then
		return nil
	end
	if r.holdZ ~= nil and not isFinite(r.holdZ) then
		return nil
	end
	if r.outcome ~= nil and (type(r.outcome) ~= "string" or #r.outcome > 32) then
		return nil
	end
	if r.score ~= nil and not isFinite(r.score) then
		return nil
	end
	if not Remotes.isRoster(r.roster, allowedRoster) then
		return nil
	end
	local encounter = nil
	if r.encounter ~= nil then
		encounter = Remotes.decodeEncounter(r.encounter)
		if encounter == nil then
			return nil
		end
	end
	return {
		v = r.v,
		runId = r.runId,
		levelId = r.levelId,
		simTime = r.simTime,
		zVelocity = r.zVelocity,
		boostExpiry = r.boostExpiry,
		roster = table.clone(r.roster),
		t = r.t,
		z = r.z,
		x = r.x,
		total = r.total,
		best = r.best,
		over = r.over,
		phase = r.phase,
		outcome = r.outcome,
		score = r.score,
		level = r.level,
		levelName = r.levelName,
		encounter = encounter,
		stage = r.stage,
		holdZ = r.holdZ,
	}
end

export type Receiver = {
	accept: (payload: any, allowedRoster: { [string]: boolean }?) -> StatePayload?,
	runId: () -> number?,
}

-- A client's gate on incoming States (issue #162: recover from state, not from events). A State is
-- accepted when it decodes and is not older than the newest accepted one: a lower runId (a replayed
-- State from before a Replay), a lower level within the run, or an earlier simTime within the same
-- (runId, levelId) is refused. The first State a late joiner receives is accepted whole, so stage,
-- encounter, boost and roster come from state alone. A resend of the same State is idempotent.
function Remotes.newReceiver(): Receiver
	local lastRun: number? = nil
	local lastLevel = 0
	local lastSim = 0
	local self = {} :: Receiver
	function self.accept(payload: any, allowedRoster: { [string]: boolean }?): StatePayload?
		local s = Remotes.decodeState(payload, allowedRoster)
		if s == nil then
			return nil
		end
		local level = levelIndexOf(s.levelId) :: number
		if lastRun ~= nil then
			if s.runId < lastRun then
				return nil
			end
			if s.runId == lastRun then
				if level < lastLevel or (level == lastLevel and s.simTime < lastSim) then
					return nil
				end
			end
		end
		lastRun, lastLevel, lastSim = s.runId, level, s.simTime
		return s
	end
	function self.runId(): number?
		return lastRun
	end
	return self
end

-- Issue #162 / spec Amendment 15: every consumption (pickup, unlock fill, recruit station, checkpoint
-- entry, boss victory, resume, clearance) is keyed (runId, levelId, encounterId) and applies once.
-- nil for any component that is not a valid id, so a forged key claims nothing.
function Remotes.encounterKey(runId: any, levelId: any, encounterId: any): string?
	if not isRunId(runId) or not isLevelId(levelId) then
		return nil
	end
	if
		type(encounterId) ~= "string"
		or #encounterId < 2
		or #encounterId > 16
		or string.match(encounterId, "^[prub]%d+$") == nil
	then
		return nil
	end
	return `{runId}|{levelId}|{encounterId}`
end

export type OnceSet = { claim: (runId: any, levelId: any, encounterId: any) -> boolean }

-- True the first time a valid key is claimed, false for a duplicate or an invalid key.
function Remotes.newOnceSet(): OnceSet
	local claimed: { [string]: boolean } = {}
	local self = {} :: OnceSet
	function self.claim(runId: any, levelId: any, encounterId: any): boolean
		local key = Remotes.encounterKey(runId, levelId, encounterId)
		if key == nil or claimed[key] then
			return false
		end
		claimed[key] = true
		return true
	end
	return self
end

return Remotes
