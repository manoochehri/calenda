--!strict
-- Pure steering rules (issue #8). The client sends only a desired lateral position; the server
-- clamps it, limits how fast the lead may move toward it, and limits how often messages count.
-- Values marked [default] are tuning defaults; spec s3 gives no numbers.
local Steering = {}

Steering.MAX_LATERAL_SPEED = 24 -- [default] studs/second the lead may slide sideways
Steering.EDGE_MARGIN = 1.5 -- [default] studs kept between the lead and the street edge
Steering.MESSAGES_PER_SECOND = 20 -- [default] sustained steer messages accepted per second
Steering.BURST = 5 -- [default] steer messages accepted at once

-- Furthest |x| the lead may be asked to stand at (ADR 0010 item 3): the one clamp on lead x. It is
-- the smaller of the street edge bound and the layout's leadLimit, a constant per layout.
function Steering.bound(halfWidth: number, leadLimit: number): number
	return math.max(0, math.min(halfWidth - Steering.EDGE_MARGIN, leadLimit))
end

-- nil for a non-finite request, otherwise the request clamped to [-bound, bound].
function Steering.clampTarget(x: any, bound: number): number?
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return nil
	end
	return math.clamp(x, -bound, bound)
end

-- One tick of lateral motion toward `target`, at most maxSpeed * dt, never overshooting.
function Steering.step(x: number, target: number, dt: number, maxSpeed: number): number
	local maxMove = maxSpeed * dt
	local delta = target - x
	if math.abs(delta) <= maxMove then
		return target
	end
	return x + (if delta > 0 then maxMove else -maxMove)
end

export type Limiter = { allow: (now: any) -> boolean }

-- Token bucket. `now` is server time in seconds; non-finite or backwards time is refused.
function Steering.newLimiter(perSecond: number, burst: number): Limiter
	local tokens = burst
	local last: number? = nil
	local limiter = {} :: Limiter
	function limiter.allow(now: any): boolean
		if type(now) ~= "number" or now ~= now or now == math.huge or now == -math.huge then
			return false
		end
		if last ~= nil then
			if now < last then
				return false
			end
			tokens = math.min(burst, tokens + (now - last) * perSecond)
		end
		last = now
		if tokens >= 1 - 1e-9 then
			tokens -= 1
			return true
		end
		return false
	end
	return limiter
end

return Steering
