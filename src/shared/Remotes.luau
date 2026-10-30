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
	id: string, -- "p<pickup id>", e.g. "p1"
	kind: string, -- "pickup"; see decodeEncounter
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

local ENCOUNTER_KINDS: { [string]: boolean } = { pickup = true }
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
	if type(id) ~= "string" or #id < 2 or #id > 16 or string.match(id, "^p%d+$") == nil then
		return nil
	end
	if type(kind) ~= "string" or ENCOUNTER_KINDS[kind] ~= true then
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
}

function Remotes.encodeState(s: Snapshot): StatePayload
	-- A finished run is always "over"; otherwise a valid supplied phase, else "running".
	local phase = if s.outcome ~= nil
		then "over"
		elseif Remotes.isPhase(s.phase) and s.phase ~= "over" then s.phase :: string
		else "running"
	return {
		phase = phase,
		t = round2(s.time),
		z = round2(s.z),
		x = round2(s.x),
		total = s.total,
		best = s.best,
		over = s.outcome ~= nil,
		outcome = s.outcome,
		score = s.score,
		level = if type(s.level) == "number" and s.level >= 1 then math.floor(s.level) else 1,
		levelName = if type(s.levelName) == "string" and s.levelName ~= "" then s.levelName else "",
		encounter = Remotes.decodeEncounter(s.encounter),
		stage = if Remotes.isStage(s.stage) then s.stage :: string else "traveling",
		holdZ = if isFinite(s.holdZ) then round2(s.holdZ :: number) else nil,
	}
end

return Remotes
