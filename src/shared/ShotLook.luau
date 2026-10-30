--!strict
-- Every knob for how a shot LOOKS (issue #67, ADR 0004): size, glow, trail, muzzle pop, impact,
-- squash, the miss flight and the hard caps of the pools behind them. Pure: no Roblox APIs, so the
-- numbers and the curves are Lune-tested; the client (ClusterView) only turns them into Parts.
-- Display only: nothing here decides a hit, a credit or a total. Colors are 0..255 triples.
-- The owner tunes by editing a `[default]` line below. In-engine look is UNVERIFIED (PR checklist).
local ShotLook = {}

export type Variant = "note" | "heart" | "gift"
export type Look = {
	size: number, -- studs, diameter of the bright core
	core: { number }, -- RGB of the glowing core
	glow: { number }, -- RGB of the halo and trail
}

-- Shot bodies (was 0.9 studs for a note).
ShotLook.LOOKS = (
	table.freeze({
		note = table.freeze({
			size = 4, -- [default] was 1.9; the note's stem and flag must read at phone size (#151)
			core = table.freeze({ 255, 235, 60 }),
			glow = table.freeze({ 255, 190, 40 }),
		}),
		heart = table.freeze({
			size = 3.45, -- [default] was 2.3; 1.5x, as the note (#151)
			core = table.freeze({ 255, 80, 140 }),
			glow = table.freeze({ 255, 120, 190 }),
		}),
		gift = table.freeze({
			size = 3.8, -- [default] the wrapped treat's width; its colors come from GiftVisual (was 2.3)
			core = table.freeze({ 200, 30, 200 }),
			glow = table.freeze({ 90, 220, 255 }),
		}),
	}) :: any
) :: { [string]: Look }

ShotLook.HALO_SCALE = 1.9 -- [default] halo diameter / core diameter
ShotLook.HALO_TRANSPARENCY = 0.65 -- [default] 0 opaque .. 1 invisible
ShotLook.PULSE = 0.18 -- [default] fraction the core swells and shrinks while flying
ShotLook.PULSE_HZ = 3 -- [default] full pulses per flight

-- Trail behind a shot (a Roblox Trail on the body).
ShotLook.TRAIL_SECONDS = 0.22 -- [default] lifetime of the streak
ShotLook.TRAIL_WIDTH = 0.8 -- [default] fraction of the core size
ShotLook.TRAIL_ALPHA = 0.25 -- [default] starting transparency; it fades to 1

-- Muzzle pop at the lead: a bright ball that swells and fades, with a tiny recoil bob. The recoil
-- moves the pop only. The lead is the player's own avatar and is never touched (ADR 0003).
ShotLook.MUZZLE_SECONDS = 0.16 -- [default]
ShotLook.MUZZLE_SIZE = 3 -- [default] studs at full swell
ShotLook.MUZZLE_HEIGHT = 2.5 -- [default] studs above the street
ShotLook.MUZZLE_FORWARD = 1.5 -- [default] studs ahead of the lead
ShotLook.RECOIL = 0.45 -- [default] studs the pop is pushed back, then returns

-- Impact on the target group: a swelling burst ball, plus a squash of the spectators.
ShotLook.IMPACT_SECONDS = 0.28 -- [default]
ShotLook.IMPACT_SIZE = 5 -- [default] studs at full swell
ShotLook.IMPACT_HEIGHT = 3 -- [default]
ShotLook.SQUASH_SECONDS = 0.22 -- [default]
ShotLook.SQUASH_AMOUNT = 0.22 -- [default] fraction squashed at the deepest (height down, width up)

-- A miss flies straight ahead of the lead, off into the distance, and fades.
ShotLook.MISS_SECONDS = 0.9 -- [default]
ShotLook.MISS_DISTANCE = 110 -- [default] studs it travels
ShotLook.MISS_LIFT = 3 -- [default] studs it rises over the flight
ShotLook.MISS_SPREAD = 0.7 -- [default] studs of lateral variety between neighbours (deterministic)
ShotLook.MISS_FADE_FROM = 0.45 -- [default] flight fraction where it starts to fade
ShotLook.MISS_SHRINK = 0.5 -- [default] fraction of its size it has left at the end

-- Hard caps. The projectile pool must cover rate x longest flight at the firing cap (see
-- projectileCapacity); the others bound a burst of events. Extra effects are simply not drawn.
ShotLook.CAPACITY_SLACK = 4 -- [default] spare projectile slots over rate x flight time
ShotLook.PROJECTILE_HARD_CAP = 32 -- [default] never more live shots than this
ShotLook.MUZZLE_CAPACITY = 4 -- [default] live muzzle pops (20/s x 0.16 s is about 3)
ShotLook.IMPACT_CAPACITY = 10 -- [default] live impact bursts (20/s x 0.28 s is about 6)

-- The longest any shot stays alive: a miss's fixed flight or the slowest aimed flight.
function ShotLook.longestFlight(maxAimedFlight: number): number
	return math.max(maxAimedFlight, ShotLook.MISS_SECONDS)
end

-- Live shots needed at `rate` shots per second: rate x longest flight, rounded up, plus slack,
-- never above the hard cap. At the Config cap (20/s) and the 0.9 s miss flight: 18 + 4 = 22.
function ShotLook.projectileCapacity(rate: number, maxAimedFlight: number): number
	local need = math.ceil(rate * ShotLook.longestFlight(maxAimedFlight)) + ShotLook.CAPACITY_SLACK
	return math.min(ShotLook.PROJECTILE_HARD_CAP, math.max(1, need))
end

-- Swelling flash: scale 0..1 grows fast and eases out, alpha 1..0. `f` is progress 0..1.
function ShotLook.pop(f: number): { scale: number, alpha: number }
	local k = math.clamp(f, 0, 1)
	local out = 1 - (1 - k) * (1 - k)
	return { scale = 0.35 + 0.65 * out, alpha = 1 - k }
end

-- Recoil offset (studs, backwards) of the muzzle pop at progress f: a quick push and return.
function ShotLook.recoil(f: number): number
	local k = math.clamp(f, 0, 1)
	return ShotLook.RECOIL * math.sin(math.pi * k)
end

-- Squash of a target spectator `age` seconds after a hit: heights shrink, widths grow, springing
-- back. 1, 1 outside the window.
function ShotLook.squash(age: number): { y: number, xz: number }
	if age < 0 or age >= ShotLook.SQUASH_SECONDS then
		return { y = 1, xz = 1 }
	end
	local s = math.sin(math.pi * age / ShotLook.SQUASH_SECONDS)
	return { y = 1 - ShotLook.SQUASH_AMOUNT * s, xz = 1 + ShotLook.SQUASH_AMOUNT * 0.6 * s }
end

-- Pulse multiplier of the core at flight progress f (1 +- PULSE).
function ShotLook.pulse(f: number): number
	return 1 + ShotLook.PULSE * math.sin(2 * math.pi * ShotLook.PULSE_HZ * math.clamp(f, 0, 1))
end

export type MissPose = { dx: number, dy: number, dz: number, scale: number, alpha: number }

-- A miss at flight progress f (0..1), shot number n: offsets from where it left the lead. It goes
-- straight ahead (+z), rises a little, shrinks and fades out; alpha is the opacity 1..0. `lateral`
-- (issue #63) is the stream's constant sideways offset in studs; without it the old 5-lane spread.
function ShotLook.miss(f: number, n: number, lateral: number?): MissPose
	local k = math.clamp(f, 0, 1)
	local lane = (n % 5) - 2 -- -2..2, deterministic variety
	local fade = math.clamp((k - ShotLook.MISS_FADE_FROM) / (1 - ShotLook.MISS_FADE_FROM), 0, 1)
	local dx = lane * ShotLook.MISS_SPREAD * k
	if lateral ~= nil then
		dx = lateral * math.min(1, 3 * k) -- a parallel stream: it eases out to its lane early
	end
	return {
		dx = dx,
		dy = ShotLook.MISS_LIFT * k,
		dz = ShotLook.MISS_DISTANCE * k,
		scale = 1 - (1 - ShotLook.MISS_SHRINK) * k,
		alpha = 1 - fade,
	}
end

return ShotLook
