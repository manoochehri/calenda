--!strict
-- Pure presentation math for spectator and obstacle feedback (issues #12, #15). No Roblox APIs.
-- Everything here is display-only: it never decides a hit, a credit or a total.
local FeedbackMath = {}

FeedbackMath.MIN_FLIGHT = 0.25 -- [default] seconds
FeedbackMath.MAX_FLIGHT = 0.7 -- [default] seconds
FeedbackMath.FLIGHT_SPEED = 67.5 -- [default] studs/second of a projectile (was 90; owner asked for ~25% slower)
FeedbackMath.ARC_HEIGHT = 7 -- [default] studs above the straight line at the apex

-- Parabolic arc from (fx,fy,fz) to (tx,ty,tz); f in 0..1 (clamped); `height` is the apex lift.
function FeedbackMath.arc(
	fx: number,
	fy: number,
	fz: number,
	tx: number,
	ty: number,
	tz: number,
	f: number,
	height: number
): (number, number, number)
	local k = math.clamp(f, 0, 1)
	return fx + (tx - fx) * k, fy + (ty - fy) * k + 4 * height * k * (1 - k), fz + (tz - fz) * k
end

-- Flight time over `distance` studs at `speed` studs/s (default FLIGHT_SPEED). Issue #234: a slower
-- projectile (fewer recruits) stretches the clamp with it, so it is slower at every range; at
-- FLIGHT_SPEED the result is exactly the former one.
function FeedbackMath.flightSeconds(distance: number, speed: number?): number
	local v = speed or FeedbackMath.FLIGHT_SPEED
	local stretch = FeedbackMath.FLIGHT_SPEED / v
	return math.clamp(
		distance / v,
		FeedbackMath.MIN_FLIGHT * stretch,
		FeedbackMath.MAX_FLIGHT * stretch
	)
end

-- Fill fraction of the excitement meter. needed <= 0 reads as full (never divides by zero).
function FeedbackMath.meterFraction(hits: number, needed: number): number
	if needed <= 0 then
		return 1
	end
	return math.clamp(hits / needed, 0, 1)
end

export type Particle = { dx: number, dy: number, dz: number, alpha: number, size: number }

local GOLDEN_ANGLE = 2.399963229728653
FeedbackMath.BURST_RADIUS = 7 -- [default] studs a chunk travels over the burst
FeedbackMath.BURST_LIFT = 5 -- [default] studs the chunk rises before it falls

-- Dust and rubble: particle i of n at progress f (0..1). Directions follow the golden angle so
-- no two chunks share a heading; speed varies by index. Deterministic, no random state.
function FeedbackMath.burst(i: number, n: number, f: number): Particle
	local k = math.clamp(f, 0, 1)
	local angle = i * GOLDEN_ANGLE
	local reach = FeedbackMath.BURST_RADIUS * (0.55 + 0.45 * ((i * 7) % n) / math.max(1, n - 1))
	local out = 1 - (1 - k) * (1 - k) -- fast start, settles
	return {
		dx = math.cos(angle) * reach * out,
		dz = math.sin(angle) * reach * out,
		dy = FeedbackMath.BURST_LIFT * 4 * k * (1 - k) * 0.5 + 0.3 * k,
		alpha = 1 - k,
		size = 1 + 2 * k,
	}
end

-- Issue #206: the world reward floater is a small billboard that never draws over a gate banner
-- (the old 160 x 70 px AlwaysOnTop label covered the gate numbers).
FeedbackMath.FLOAT_GUI_SIZE = { x = 64, y = 28 } -- [default] pixels
FeedbackMath.FLOAT_ALWAYS_ON_TOP = false

-- Floating "+N": rises and fades.
function FeedbackMath.floatText(f: number): { dy: number, alpha: number }
	local k = math.clamp(f, 0, 1)
	return { dy = 4 * k, alpha = 1 - k * k * k }
end

-- A spectator running from (fx,fz) to (tx,tz): x, z and a small hop height that lands at 0.
function FeedbackMath.run(
	fx: number,
	fz: number,
	tx: number,
	tz: number,
	f: number
): (number, number, number)
	local k = math.clamp(f, 0, 1)
	local hop = math.abs(math.sin(k * math.pi * 4)) * 0.8 * (1 - k * k)
	return fx + (tx - fx) * k, fz + (tz - fz) * k, if k >= 1 then 0 else hop
end

return FeedbackMath
