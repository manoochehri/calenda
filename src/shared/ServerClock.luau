--!strict
-- Smoothed render timeline for the lead (issue #85, items 2 and 3). The server sends State at
-- about 10 Hz; each State carries the run time `t` it was taken at (30 Hz tick) and `z = speed * t`.
-- Main used to dead-reckon from the newest State with the local clock, so every State arrival
-- re-based the lead by the network jitter and the 30 Hz tick rounding of `t`: the drawn lead (and
-- the camera that follows it) stepped by up to several times its per-frame advance, 10 times a
-- second, and the lateral x only changed at 10 Hz. That reads as a shimmer of the whole scene.
--
-- ServerClock instead keeps ONE continuous timeline:
--   * each State yields a sample of the offset `now - t`; a low-pass filter (EWMA) estimates the
--     offset, so jitter averages out instead of being copied to the screen;
--   * the offset actually used slews toward that estimate at no more than SLEW seconds per second,
--     so the render clock runs at 0.96x..1.04x speed and can never snap;
--   * z is the analytic line through the latest State at the render time (so a new State on the
--     same line moves nothing); x is interpolated between States a little in the past and
--     rate-limited to the server's own lateral speed limit.
-- Duplicates and stale States are ignored; run time going back by more than REPLAY_BACKSTEP is a
-- replay and resets everything. Pure: the caller passes the clock reading (os.clock()).
local Remotes = require("./Remotes")
local Steering = require("./Steering")

local ServerClock = {}

ServerClock.ALPHA = 0.1 -- [default] weight of each new offset sample in the low-pass filter
ServerClock.SLEW = 0.04 -- [default] max change of the applied offset, seconds per second (4% speed)
ServerClock.MAX_INNOVATION = 0.25 -- [default] one offset sample moves the estimate by at most this (s)
ServerClock.MAX_EXTRAPOLATION = 0.35 -- [default] same bound as RunView.MAX_EXTRAPOLATION
ServerClock.REPLAY_BACKSTEP = 1 -- [default] run time going back by more than this (s) = new run
ServerClock.LATERAL_DELAY = 0.1 -- [default] s behind the render time that x is interpolated at
ServerClock.LATERAL_EXTRAPOLATION = 0.15 -- [default] s x may be projected past the newest State
ServerClock.LATERAL_HEADROOM = 1.04 -- [default] x follower speed limit as a share of the server's
ServerClock.MAX_QUERY_DT = 0.25 -- [default] longest frame gap the slew/follower integrate over

local KEEP = 8

type Sample = { t: number, x: number }
type Latest = { t: number, z: number, x: number, over: boolean, stopped: boolean, holdZ: number? }

export type ServerClock = {
	-- Feed a State (fields t, z, x, over) received at local time `now`; false when ignored.
	observe: (self: ServerClock, state: any, now: number) -> boolean,
	-- Drawn lead for local time `now`: x, z, run time t. Call once per frame.
	sample: (
		self: ServerClock,
		now: number,
		speed: number,
		maxZ: number
	) -> (number, number, number),
	reset: (self: ServerClock) -> (),
}

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

function ServerClock.new(): ServerClock
	local latest: Latest? = nil
	local samples: { Sample } = {}
	local target = 0 -- low-pass estimate of (now - t)
	local applied = 0 -- the offset in use; slews toward target
	local lastQuery: number? = nil
	local follower: number? = nil -- drawn x

	local self = {} :: ServerClock

	function self.reset(_)
		latest, lastQuery, follower = nil, nil, nil
		table.clear(samples)
	end

	function self.observe(_, state: any, now: number): boolean
		if
			type(state) ~= "table" or not (finite(state.t) and finite(state.z) and finite(state.x))
		then
			return false
		end
		if not finite(now) then
			return false
		end
		local l = latest
		if l ~= nil and state.t <= l.t then
			if l.t - state.t <= ServerClock.REPLAY_BACKSTEP then
				return false -- duplicate or out of order: the newer State already won
			end
			self:reset() -- run time went back: a replay
			l = nil
		end
		local o = now - state.t
		if l == nil then
			target, applied = o, o
		else
			local innovation =
				math.clamp(o - target, -ServerClock.MAX_INNOVATION, ServerClock.MAX_INNOVATION)
			target += ServerClock.ALPHA * innovation
		end
		-- Issue #162: a State is level-triggered, so a missed stop or resume is repaired by the next one.
		-- `stopped` (a fight is on) freezes z; `holdZ` stops the extrapolation at the plane before it.
		latest = {
			t = state.t,
			z = state.z,
			x = state.x,
			over = state.over == true,
			stopped = Remotes.isStage(state.stage) and state.stage ~= "traveling",
			holdZ = if finite(state.holdZ) then state.holdZ else nil,
		}
		table.insert(samples, { t = state.t, x = state.x })
		if #samples > KEEP then
			table.remove(samples, 1)
		end
		return true
	end

	-- x on the server's path at run time `rt`: interpolated between States, or projected past the
	-- newest one along the last segment's slope (capped at the server's lateral speed limit).
	local function pathX(rt: number): number
		local n = #samples
		local last = samples[n]
		if rt >= last.t then
			if n < 2 then
				return last.x
			end
			local prev = samples[n - 1]
			local slope = (last.x - prev.x) / (last.t - prev.t)
			local vmax = Steering.MAX_LATERAL_SPEED
			slope = math.clamp(slope, -vmax, vmax)
			return last.x + slope * math.min(rt - last.t, ServerClock.LATERAL_EXTRAPOLATION)
		end
		for i = n - 1, 1, -1 do
			local a, b = samples[i], samples[i + 1]
			if rt >= a.t then
				return a.x + (b.x - a.x) * (rt - a.t) / (b.t - a.t)
			end
		end
		return samples[1].x
	end

	function self.sample(_, now: number, speed: number, maxZ: number): (number, number, number)
		local l = latest
		if l == nil or not finite(now) then
			return follower or 0, 0, 0
		end
		local q = lastQuery
		local dt = if q == nil then 0 else math.clamp(now - q, 0, ServerClock.MAX_QUERY_DT)
		lastQuery = now

		if l.over then
			follower = l.x
			return l.x, l.z, l.t -- the end is drawn exactly where the server left it
		end

		local step = ServerClock.SLEW * dt
		applied += math.clamp(target - applied, -step, step)
		local rt = math.clamp(
			now - applied,
			l.t - ServerClock.MAX_EXTRAPOLATION,
			l.t + ServerClock.MAX_EXTRAPOLATION
		)
		local z = if l.stopped then l.z else math.min(maxZ, l.z + speed * (rt - l.t))
		if l.holdZ ~= nil then
			z = math.min(z, math.max(l.holdZ, l.z))
		end

		local want = pathX(rt - ServerClock.LATERAL_DELAY)
		local fx = follower
		if fx == nil then
			fx = want
		else
			local maxMove = Steering.MAX_LATERAL_SPEED * ServerClock.LATERAL_HEADROOM * dt
			fx += math.clamp(want - fx, -maxMove, maxMove)
		end
		follower = fx
		return fx :: number, z, rt
	end

	return self
end

return ServerClock
