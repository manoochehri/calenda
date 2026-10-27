--!strict
-- Issue #151: which projectile a shot looks like, and how a gift flies. Pure: no Roblox APIs, so
-- the rule and the arc are Lune-tested; ClusterView only turns the answers into Parts.
-- Visual only: nothing here decides a hit, a credit, a firing rate or the gift cadence. The
-- cadence is Targeting.shotKind (every Config.giftEveryNthShot-th shot, spec s4 / ADR 0004).
local FeedbackMath = require("./FeedbackMath")

local ProjectileVisual = {}

export type Kind = "note" | "heart" | "gift"

-- A gift is slower than a note over the same distance and arcs higher (a lazy, looping toss).
ProjectileVisual.GIFT_FLIGHT_SCALE = 1.6 -- [default] x the note flight time
ProjectileVisual.GIFT_APEX = 14 -- [default] studs above the straight line at the top (notes: 7)
ProjectileVisual.GIFT_LOOPS = 2 -- [default] full loops of the arc in flight
ProjectileVisual.GIFT_LOOP_RADIUS = 2.5 -- [default] studs; the loop's largest sideways and up reach

-- The look of a shot. A gift is always a gift. A regular shot alternates note and heart by the
-- index: odd is a heart, even is a note. The index is the shot number for a miss, and the cluster's
-- hit count for a hit (the wire carries no shared shot number for hits).
function ProjectileVisual.kind(shot: string, index: number): Kind
	if shot == "gift" then
		return "gift"
	end
	return if index % 2 == 1 then "heart" else "note"
end

-- Longest any projectile flies: a gift's flight at the note's maximum flight time.
function ProjectileVisual.longestFlight(): number
	return FeedbackMath.MAX_FLIGHT * ProjectileVisual.GIFT_FLIGHT_SCALE
end

-- Flight time in seconds for a shot of this kind over `distance` studs. Notes and hearts keep the
-- FeedbackMath flight; a gift takes GIFT_FLIGHT_SCALE times as long.
function ProjectileVisual.flightSeconds(shot: string, distance: number): number
	local base = FeedbackMath.flightSeconds(distance)
	if shot == "gift" then
		return base * ProjectileVisual.GIFT_FLIGHT_SCALE
	end
	return base
end

-- The loop a gift adds on top of its arc at flight progress f (0..1): offsets in studs. It starts
-- and ends at zero, so the gift still lands on its target, and it never dips below the arc.
function ProjectileVisual.giftLoop(f: number): { dx: number, dy: number, dz: number }
	local k = math.clamp(f, 0, 1)
	local theta = 2 * math.pi * ProjectileVisual.GIFT_LOOPS * k
	local envelope = math.sin(math.pi * k) -- 0 at both ends, 1 mid-flight
	local r = ProjectileVisual.GIFT_LOOP_RADIUS * envelope
	return {
		dx = r * math.sin(theta),
		dy = r * (1 - math.cos(theta)),
		dz = 0,
	}
end

return ProjectileVisual
