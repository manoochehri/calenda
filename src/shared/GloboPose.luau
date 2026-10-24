--!strict
-- Pure globo / marmota animation (issue #19, spec s7): a large decorated sphere on a visible pole,
-- rotating and tilting with its carriers, and decorative musical rings on the beat. Angles are
-- radians, lengths studs; time is seconds and the beat comes from Config.music. Rings are timing and
-- look only: nothing here reads or changes the crowd total, and rings never recruit (spec s7).
local Config = require("./Config")
local DanceConfig = require("./DanceConfig")

local GloboPose = {}

GloboPose.MAX_TILT = DanceConfig.globoTiltRadians
GloboPose.SPIN_BEATS = DanceConfig.globoSpinBeats -- [default] one turn across the four-bar dance phrase
GloboPose.WOBBLE_BEATS = 4 -- [default] the lean circles the pole once per bar
GloboPose.LIFT_STUDS = DanceConfig.globoLiftStuds
GloboPose.CARRIER_RADIUS = 2.6 -- [default] studs from the pole to each carrier
GloboPose.RING_SECONDS = 0.8 -- [default] life of one ring
GloboPose.RING_START_RADIUS = 4.2 -- [default] just outside the sphere (radius 3.75)
GloboPose.RING_END_RADIUS = 9 -- [default]
GloboPose.RING_RISE = 1.5 -- [default] studs a ring drifts upward while it fades
GloboPose.MAX_RINGS = 10 -- [default] rings alive at once; extras are not drawn (spec s8 budget)

local TAU = 2 * math.pi
local EPS = 1e-9 -- beats landing exactly on a frame boundary must not be lost to rounding

export type Pose = {
	spin: number, -- rotation of the sphere about its own pole, unwrapped (always increasing)
	tiltX: number, -- lean of the whole pole about X
	tiltZ: number, -- lean of the whole pole about Z
	lift: number, -- studs the sphere rises on the beat, 0..LIFT_STUDS
	carrierStep: number, -- 0..1, carriers bob on each step
}
export type Ring = { radius: number, alpha: number, rise: number }
export type Offset = { dx: number, dz: number }

local function beatsAt(time: number, phase: number): number
	return time * Config.music.bpm / 60 + phase
end

-- `phase` (in beats) offsets one globo from another.
function GloboPose.pose(time: number, phase: number): Pose
	local beats = beatsAt(time, phase)
	local w = TAU * beats / GloboPose.WOBBLE_BEATS
	local pop = 0.5 + 0.5 * math.cos(TAU * beats) -- 1 on every beat
	return {
		spin = TAU * beats / GloboPose.SPIN_BEATS,
		-- An ellipse, never zero: the pole always visibly leans, and the lean travels around.
		tiltX = GloboPose.MAX_TILT * math.sin(w),
		tiltZ = GloboPose.MAX_TILT * 0.6 * math.cos(w),
		lift = GloboPose.LIFT_STUDS * pop ^ 4,
		carrierStep = math.abs(math.sin(math.pi * beats)),
	}
end

local function beatIndex(time: number): number
	return math.floor(time * Config.music.bpm / 60 + EPS)
end

-- How many beats fell in (prev, now]. The sum over any sequence of frames is the same at any
-- frame rate; time that stands still or runs backwards rings nothing.
function GloboPose.beatsIn(prev: number, now: number): number
	return math.max(0, beatIndex(now) - beatIndex(prev))
end

-- The ring born on a beat, `age` seconds after it. Expands and fades; gone at RING_SECONDS.
function GloboPose.ring(age: number): Ring
	local f = math.clamp(age / GloboPose.RING_SECONDS, 0, 1)
	local ease = 1 - (1 - f) ^ 2
	return {
		radius = GloboPose.RING_START_RADIUS
			+ (GloboPose.RING_END_RADIUS - GloboPose.RING_START_RADIUS) * ease,
		alpha = (1 - f) ^ 2,
		rise = GloboPose.RING_RISE * f,
	}
end

-- 1-based palette slot for the ring of beat `beat` (the colors live in the client).
function GloboPose.ringColorIndex(beat: number, colors: number): number
	return beat % colors + 1
end

-- Where each of `n` carriers stands around the pole base, evenly spaced on one circle.
function GloboPose.carrierOffsets(n: number): { Offset }
	local out: { Offset } = {}
	for i = 1, n do
		local a = TAU * (i - 1) / n + math.pi / 4
		table.insert(out, {
			dx = math.cos(a) * GloboPose.CARRIER_RADIUS,
			dz = math.sin(a) * GloboPose.CARRIER_RADIUS,
		})
	end
	return out
end

return GloboPose
