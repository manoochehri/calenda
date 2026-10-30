--!strict
-- Issue #151: which projectile a shot looks like, and how a gift flies. Pure: no Roblox APIs, so
-- the rule and the arc are Lune-tested; ClusterView only turns the answers into Parts.
-- Visual only: nothing here decides a hit, a credit, a firing rate or the gift cadence. The
-- cadence is Targeting.shotKind (every Config.giftEveryNthShot-th shot, spec s4 / ADR 0004).
local CameraRig = require("./CameraRig")
local FeedbackMath = require("./FeedbackMath")

local ProjectileVisual = {}

export type Kind = "note" | "heart" | "gift"

-- One camera-plane primitive of a silhouette. Units are normalized (about -1..1), not studs; x and
-- y are the centre, w and h the full size, roll the tilt in radians. A ball is an ellipse, a block
-- a rectangle. A ribbon marks the gift's crossed ribbons.
export type Piece = {
	shape: "ball" | "block",
	x: number,
	y: number,
	w: number,
	h: number,
	roll: number,
	ribbon: boolean,
}

-- A gift is slower than a note over the same distance and arcs higher (a lazy, looping toss).
ProjectileVisual.GIFT_FLIGHT_SCALE = 1.6 -- [default] x the note flight time
ProjectileVisual.GIFT_APEX = 14 -- [default] studs above the straight line at the top (notes: 7)
ProjectileVisual.GIFT_LOOPS = 2 -- [default] full loops of the arc in flight
ProjectileVisual.GIFT_LOOP_RADIUS = 2.5 -- [default] studs; the loop's largest sideways and up reach

-- The silhouette faces the gameplay camera: tilted by the camera's downward pitch (about 52 degrees
-- at pullback 1, where CameraRig holds the pitch constant). Unfaced, the high camera would squash
-- every vertical detail to about 0.62 of its size.
ProjectileVisual.TILT = math.rad(CameraRig.pitchDegrees(CameraRig.pose(0, 0, 1)))

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

-- The silhouettes, each at most four primitives (a body and three extras, the part budget). The
-- note is a head, stem and flag; the heart is two lobes and a pointed body with its cleft left
-- empty; the gift is a box, a lid and two crossed ribbons, with no spherical core.
local GEOMETRY: { [Kind]: { Piece } } = {
	note = {
		{ shape = "ball", x = 0, y = -0.5, w = 0.8, h = 0.6, roll = 0, ribbon = false },
		{ shape = "block", x = 0.35, y = 0.1, w = 0.4, h = 0.9, roll = 0, ribbon = false },
		{ shape = "block", x = 0.6, y = 0.68, w = 0.5, h = 0.36, roll = 0, ribbon = false },
	},
	heart = {
		{ shape = "ball", x = -0.36, y = 0.43, w = 0.44, h = 0.44, roll = 0, ribbon = false },
		{ shape = "ball", x = 0.36, y = 0.43, w = 0.44, h = 0.44, roll = 0, ribbon = false },
		-- A square turned 45 degrees: its top stays below the cleft and its point reaches down.
		{
			shape = "block",
			x = 0,
			y = -0.2,
			w = 0.71,
			h = 0.71,
			roll = math.pi / 4,
			ribbon = false,
		},
	},
	gift = {
		{ shape = "block", x = 0, y = -0.2, w = 1.3, h = 1.0, roll = 0, ribbon = false }, -- box
		{ shape = "block", x = 0, y = 0.45, w = 1.6, h = 0.38, roll = 0, ribbon = false }, -- lid
		{ shape = "block", x = 0, y = 0, w = 0.4, h = 1.6, roll = 0, ribbon = true }, -- ribbon
		{ shape = "block", x = 0, y = 0.45, w = 1.6, h = 0.4, roll = 0, ribbon = true }, -- ribbon
	},
}

-- The camera-plane primitives of a projectile's silhouette. The result is shared: do not mutate it.
function ProjectileVisual.geometry(kind: Kind): { Piece }
	return GEOMETRY[kind]
end

-- The same primitives in studs, for a projectile of `size` studs across: a new table, so the
-- caller can keep it. ClusterView turns each entry into one Part, in order.
function ProjectileVisual.place(kind: Kind, size: number): { Piece }
	local out = {}
	for i, piece in GEOMETRY[kind] do
		out[i] = {
			shape = piece.shape,
			x = piece.x * size,
			y = piece.y * size,
			w = piece.w * size,
			h = piece.h * size,
			roll = piece.roll,
			ribbon = piece.ribbon,
		}
	end
	return out
end

-- Height in studs above the flight path at progress f (0..1). A gift lobs on both its aimed and
-- its miss flight, with the same parabola as FeedbackMath.arc, so it is zero at launch and landing.
-- Notes and hearts add nothing: their hits keep the FeedbackMath arc and their misses ShotLook.miss.
-- A gift lobs the same whether it hits or misses, so `_miss` is unused.
function ProjectileVisual.lift(kind: Kind, f: number, _miss: boolean): number
	if kind ~= "gift" then
		return 0
	end
	local k = math.clamp(f, 0, 1)
	return 4 * ProjectileVisual.GIFT_APEX * k * (1 - k)
end

return ProjectileVisual
