--!strict
-- Crowd feel tuning (issue #178). Display only: none of these numbers can change a hit, a credit,
-- a crowd total or the 10% loss rule, which stay on the server. Times are seconds, distances studs,
-- squash is a share of height, breath spread is in beats.
return table.freeze({
	-- Per-follower breathing offset (at most this many beats), so the crowd does not pulse in lockstep.
	BREATH_SPREAD_BEATS = 0.5,
	-- A follower who joins hops once and squashes on the landing frame, then settles.
	JOIN_SECONDS = 0.45,
	JOIN_HOP = 0.6,
	JOIN_SQUASH = 0.22,
	-- The whole parade hops once when the total goes up (a cheer).
	CHEER_SECONDS = 0.6,
	CHEER_HOP = 0.7,
	-- The whole parade dips and squashes once when the total goes down (short, not a freeze).
	FLINCH_SECONDS = 0.5,
	FLINCH_DIP = 0.5,
	FLINCH_SQUASH = 0.15,
	-- Clamps applied to the sum of every active feel term, so stacked events stay bounded.
	MAX_SQUASH = 0.35,
	MAX_HOP = 1.6,
	MIN_HOP = -0.6,
})
