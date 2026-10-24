--!strict
-- Spring follow for one coordinate (issue #68). Pure. A damped spring toward a moving target with
-- velocity feed-forward (so a lead moving at constant speed leaves zero steady lag; only changes in
-- the target's motion make followers lag, each by its own omega, which is what ripples the crowd).
-- Integrated in small fixed sub-steps (semi-implicit Euler) and with the frame time clamped, so a
-- hitch or a huge dt can never blow up: the state stays finite and settles at the target.
local FollowerSpring = {}

FollowerSpring.SUBSTEP = 1 / 120 -- seconds
FollowerSpring.MAX_DT = 0.25 -- seconds of simulated time per call; more is dropped
FollowerSpring.MAX_OMEGA = 40 -- keeps omega * SUBSTEP well inside the stable range

-- Returns the new position and velocity.
function FollowerSpring.step(
	pos: number,
	vel: number,
	target: number,
	targetVel: number,
	dt: number,
	omega: number,
	zeta: number
): (number, number)
	if not (dt > 0) then
		return pos, vel
	end
	local w = math.clamp(omega, 0.1, FollowerSpring.MAX_OMEGA)
	local z = math.max(zeta, 0)
	local remaining = math.min(dt, FollowerSpring.MAX_DT)
	-- The target moved by targetVel * dt during this step: measure the error from where it WAS.
	local before = if dt <= FollowerSpring.MAX_DT then target - targetVel * dt else target
	local e, ev = pos - before, vel - targetVel
	while remaining > 1e-9 do
		local h = math.min(remaining, FollowerSpring.SUBSTEP)
		ev += (-w * w * e - 2 * z * w * ev) * h
		e += ev * h
		remaining -= h
	end
	if dt > FollowerSpring.MAX_DT then
		-- A pause longer than the clamp: the crowd has long since settled; hand back the remainder.
		local decay = 0.05
		e, ev = e * decay, ev * decay
	end
	return target + e, targetVel + ev
end

return FollowerSpring
