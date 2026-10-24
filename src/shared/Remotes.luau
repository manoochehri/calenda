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

-- Server -> client. Compact and display-only. `over` is true once the run has ended.
export type StatePayload = {
	t: number,
	z: number,
	x: number,
	total: number,
	hp: number,
	maxHp: number,
	best: number,
	over: boolean,
	phase: string, -- "ready" (paused, waiting for Start) | "running" | "over"; see isPhase
	outcome: string?,
	score: number?,
}

-- Server -> client discrete events. ids are layout ids, for animation lookup only.
export type EventPayload = {
	kind: string,
	id: number?,
	side: string?,
	before: number?,
	after: number?,
	hpBefore: number?,
	hpAfter: number?,
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
}

function Remotes.isEventKind(kind: any): boolean
	return type(kind) == "string" and EVENT_KINDS[kind] == true
end

local PHASES: { [string]: boolean } = { ready = true, running = true, over = true }

function Remotes.isPhase(p: any): boolean
	return type(p) == "string" and PHASES[p] == true
end

-- Start (and Replay) take no data. Any arguments are discarded; always returns true so the
-- handler's only inputs are the sender and the server clock.
function Remotes.decodeStart(...: any): boolean
	local _ignored = select("#", ...) -- count only; no argument is ever read
	return true
end

local function isFinite(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
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
	hp: number,
	maxHp: number,
	best: number,
	phase: string?, -- optional; derived from outcome when absent or invalid
	outcome: string?,
	score: number?,
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
		hp = s.hp,
		maxHp = s.maxHp,
		best = s.best,
		over = s.outcome ~= nil,
		outcome = s.outcome,
		score = s.score,
	}
end

return Remotes
