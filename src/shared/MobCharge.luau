--!strict
-- How a mob MOVES and LOOKS (issue #65): the wedge formation, the charging stride (hop, forward
-- lean, raised pumping arms), the slam into the parade, the dispersal to the sidewalks, the
-- recolour of a converted mob and the palettes. Pure and display only: no Roblox APIs, nothing
-- here decides a hit, a credit, damage or a total. Spectators are attackers until converted, so
-- the unconverted palette is an "angry mob" (hot red/orange, leaning in, arms up) and the
-- converted one is party fans (festive blues, gold, pink): friendly cartoon tone, no violence.
-- Colors are 0..255 triples. The client (MobView) only turns these numbers into Parts.
local MobCharge = {}

MobCharge.SPACING_MIN = 0.6 -- [default] studs between figures, never tighter
MobCharge.SPACING_MAX = 2.4 -- [default]
MobCharge.STRIDE_HZ = 2.6 -- [default] steps per second
MobCharge.STRIDE_HOP = 0.45 -- [default] studs
MobCharge.LEAN = 0.32 -- [default] radians forward lean while charging
MobCharge.ARM_DOWN = 1.35 -- [default] studs, arm bar height at rest
MobCharge.ARM_UP = 2.6 -- [default] studs, arm bar height raised
MobCharge.ARM_PUMP = 0.25 -- [default] studs the raised arms pump
MobCharge.SLAM_SECONDS = 0.4 -- [default]
MobCharge.SLAM_COMPRESS = 0.4 -- [default] share of the mob's depth squeezed away at the deepest
MobCharge.SLAM_HOP = 1.6 -- [default] studs the front figures bump up
MobCharge.SLAM_GAP = 3 -- [default] studs ahead of the lead where the mob's front stops
MobCharge.SLAM_FALLBACK = 0.5 -- [default] seconds after reaching the parade the slam plays even if the Event is late
MobCharge.DISPERSE_SECONDS = 1.3 -- [default]
MobCharge.DISPERSE_HOP = 2.2 -- [default]
MobCharge.SIDEWALK_X = 18 -- [default] |x| the dispersing mob heads for
MobCharge.SINK = 2.6 -- [default] studs a figure sinks into the road to disappear (no Size writes)
MobCharge.RECOLOUR_SECONDS = 0.3 -- [default] angry -> party palette
MobCharge.STREAM_SECONDS = 2 -- [default] converted mob streams into the parade
MobCharge.STREAM_SHRINK_FROM = 0.35 -- [default] share of the stream after which the mob thins out

MobCharge.ANGRY = table.freeze({
	table.freeze({ 214, 58, 46 }),
	table.freeze({ 236, 104, 40 }),
	table.freeze({ 176, 42, 62 }),
	table.freeze({ 240, 150, 52 }),
})
MobCharge.PARTY = table.freeze({
	table.freeze({ 64, 142, 255 }),
	table.freeze({ 255, 204, 48 }),
	table.freeze({ 255, 96, 164 }),
	table.freeze({ 72, 212, 172 }),
})
MobCharge.ALERT = table.freeze({ 255, 236, 130 }) -- the pulse brightens toward this
MobCharge.HEADS = table.freeze({
	table.freeze({ 255, 214, 170 }),
	table.freeze({ 222, 168, 120 }),
	table.freeze({ 176, 120, 84 }),
	table.freeze({ 243, 190, 148 }),
})

-- Deterministic 0..1 noise from an index (no math.random: the look is reproducible).
function MobCharge.noise(i: number, salt: number?): number
	local x = math.sin(i * 12.9898 + (salt or 0) * 78.233) * 43758.5453
	return x - math.floor(x)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Wedge slot of figure i (1-based) in a full wedge of `capacity` figures filling `width` x
-- `depth` studs. Row r holds up to 2r+1 figures; slot 1 is the apex at the FRONT. Returns
-- (dx lateral offset, dz studs BEHIND the front; the mob charges toward -z so behind = +z).
function MobCharge.wedgeSlot(
	i: number,
	capacity: number,
	width: number,
	depth: number
): (number, number)
	local rows = math.max(1, math.ceil(math.sqrt(capacity)))
	local r = math.ceil(math.sqrt(i)) - 1
	local inRow = math.min(2 * r + 1, capacity - r * r)
	local k = i - r * r - 1
	local dxs = if rows > 1 then width / (2 * (rows - 1)) else 0
	local dzs = depth / rows
	dxs = math.clamp(dxs, MobCharge.SPACING_MIN, MobCharge.SPACING_MAX)
	dzs = math.clamp(dzs, MobCharge.SPACING_MIN, MobCharge.SPACING_MAX)
	local jx = (MobCharge.noise(i) - 0.5) * dxs * 0.4
	local jz = (MobCharge.noise(i, 1) - 0.5) * dzs * 0.4
	return (k - (inRow - 1) / 2) * dxs + jx, r * dzs + jz
end

-- Charging pose of a figure: hop height, forward lean (radians), arm bar height.
function MobCharge.stride(i: number, clock: number): (number, number, number)
	local phase = MobCharge.noise(i, 2) * math.pi * 2
	local s = math.sin(clock * MobCharge.STRIDE_HZ * math.pi * 2 + phase)
	local hop = MobCharge.STRIDE_HOP * math.abs(s)
	local arm = MobCharge.ARM_UP + MobCharge.ARM_PUMP * s
	return hop, MobCharge.LEAN, arm
end

-- Slam envelope for `age` seconds after the attack Event: 0 outside, peaks early, quick decay.
function MobCharge.slam(age: number): number
	if age < 0 or age >= MobCharge.SLAM_SECONDS then
		return 0
	end
	local k = 1 - age / MobCharge.SLAM_SECONDS
	return k * k
end

-- Compress factor on the mob's depth during the slam (1 = none): the back piles into the front.
function MobCharge.slamDepth(age: number): number
	return 1
		- MobCharge.SLAM_COMPRESS
			* math.min(1, math.max(0, age) / (MobCharge.SLAM_SECONDS * 0.4))
end

-- Dispersal of a figure at lateral `x0` (mob centre `centerX`) after `f` (0..1) of the dispersal:
-- (x, hop, sink). It hops to the sidewalk on its side, then sinks into the road to vanish.
function MobCharge.disperse(x0: number, centerX: number, f: number): (number, number, number)
	local side = if x0 ~= 0 then (if x0 < 0 then -1 else 1) else (if centerX < 0 then -1 else 1)
	local k = 1 - (1 - f) * (1 - f)
	local x = lerp(x0, side * MobCharge.SIDEWALK_X, k)
	local hop = MobCharge.DISPERSE_HOP * 4 * f * (1 - f)
	local sink = MobCharge.SINK * math.clamp((f - 0.7) / 0.3, 0, 1)
	return x, hop, sink
end

-- Colour mix toward the party palette (0 angry .. 1 party) `since` seconds after the fill.
function MobCharge.partyMix(since: number): number
	return math.clamp(since / MobCharge.RECOLOUR_SECONDS, 0, 1)
end

-- Share of a converted mob still standing `since` seconds after the fill: it thins out as its
-- members stream into the parade.
function MobCharge.streamKeep(since: number): number
	local f = math.clamp(since / MobCharge.STREAM_SECONDS, 0, 1)
	local g =
		math.clamp((f - MobCharge.STREAM_SHRINK_FROM) / (1 - MobCharge.STREAM_SHRINK_FROM), 0, 1)
	return 1 - g * g * (3 - 2 * g)
end

-- Colour of figure i: palette entry blended by the party mix and brightened by the pulse.
-- Returns r, g, b (0..255). `head` selects the skin tones.
function MobCharge.colour(
	i: number,
	party: number,
	pulse: number,
	head: boolean
): (number, number, number)
	local a, b
	if head then
		a = MobCharge.HEADS[(i - 1) % #MobCharge.HEADS + 1]
		b = a
	else
		a = MobCharge.ANGRY[(i - 1) % #MobCharge.ANGRY + 1]
		b = MobCharge.PARTY[(i - 1) % #MobCharge.PARTY + 1]
	end
	local p = math.clamp(pulse, 0, 1) * 0.35 * (1 - party) -- only an angry mob alerts
	local alert = MobCharge.ALERT
	return lerp(lerp(a[1], b[1], party), alert[1], p),
		lerp(lerp(a[2], b[2], party), alert[2], p),
		lerp(lerp(a[3], b[3], party), alert[3], p)
end

return MobCharge
