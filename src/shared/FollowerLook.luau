--!strict
-- How each follower looks and moves (issue #68): every tuning knob for the parade's punch lives
-- here as a named [default] constant. Pure: a follower's costume colour, size, hat or flower, bounce
-- height and tempo all come from a seeded hash of its id (so the same follower always looks the same),
-- and the per-frame functions take time and return numbers; the client only turns them into Parts.
local Config = require("./Config")
local FollowerSlots = require("./FollowerSlots")
local DanceConfig = require("./DanceConfig")

export type Look = {
	color: { number }, -- RGB 0..255 of the costume (ribbon-skirt tone)
	accent: { number }, -- RGB of the hat or flower
	scale: number, -- size multiplier
	topper: string, -- "none" | "hat" | "flower"
	bounce: number, -- studs of hop at the top of a step
	tempo: number, -- radians/second of the march
	phase: number, -- radians, so no two bounce together
}
export type March = { y: number, squashY: number, squashXZ: number }

local FollowerLook = {}

-- Festive costume tones: red, blue, pink, yellow, green, orange. Saturated and distinct from the
-- gray road and the lead's gold so the crowd reads as a colourful swarm.
FollowerLook.PALETTE = table.freeze({
	table.freeze({ 235, 60, 70 }),
	table.freeze({ 45, 120, 235 }),
	table.freeze({ 245, 110, 175 }),
	table.freeze({ 250, 205, 40 }),
	table.freeze({ 70, 205, 110 }),
	table.freeze({ 250, 135, 40 }),
})
FollowerLook.ACCENT = table.freeze({
	table.freeze({ 255, 255, 255 }),
	table.freeze({ 255, 230, 90 }),
	table.freeze({ 120, 60, 200 }),
})
FollowerLook.SCALE_MIN = 0.9 -- [default]
FollowerLook.SCALE_MAX = 1.18 -- [default]
FollowerLook.HAT_SHARE = 0.25 -- [default] share of followers with a hat
FollowerLook.FLOWER_SHARE = 0.2 -- [default] share with a flower (the rest wear neither)
FollowerLook.BOUNCE_MIN = DanceConfig.followerBounceMin
FollowerLook.BOUNCE_MAX = DanceConfig.followerBounceMax
FollowerLook.TEMPO_MIN = DanceConfig.followerTempoMin
FollowerLook.TEMPO_MAX = DanceConfig.followerTempoMax
FollowerLook.SQUASH = 0.16 -- [default] share of height lost on landing / gained at the top
FollowerLook.BREATH = 0.05 -- [default] crowd scale pulse on the beat, +- share
FollowerLook.BREATH_POWER = 3 -- [default] sharpness of the pulse (higher = a quick pop)
FollowerLook.LEAN_PER_SPEED = 0.05 -- [default] radians of lean per stud/second of sideways speed
FollowerLook.MAX_LEAN = 0.45 -- [default] radians
FollowerLook.DUST_CAP = 10 -- [default] puffs alive at once (a budget, not a wish)
FollowerLook.DUST_SECONDS = 0.55 -- [default]
FollowerLook.DUST_CHANCE = 0.12 -- [default] share of footfalls that raise a puff
FollowerLook.DUST_SIZE = 1.6 -- [default] studs at the end of a puff

local function pick(id: number, salt: number, n: number): number
	return math.floor(FollowerSlots.unit(id, salt) * n) + 1
end

function FollowerLook.of(id: number): Look
	local u = FollowerSlots.unit
	local roll = u(id, 65)
	local topper = "none"
	if roll < FollowerLook.HAT_SHARE then
		topper = "hat"
	elseif roll < FollowerLook.HAT_SHARE + FollowerLook.FLOWER_SHARE then
		topper = "flower"
	end
	return {
		color = FollowerLook.PALETTE[pick(id, 61, #FollowerLook.PALETTE)],
		accent = FollowerLook.ACCENT[pick(id, 62, #FollowerLook.ACCENT)],
		scale = FollowerLook.SCALE_MIN
			+ u(id, 63) * (FollowerLook.SCALE_MAX - FollowerLook.SCALE_MIN),
		topper = topper,
		bounce = FollowerLook.BOUNCE_MIN
			+ u(id, 64) * (FollowerLook.BOUNCE_MAX - FollowerLook.BOUNCE_MIN),
		tempo = FollowerLook.TEMPO_MIN
			+ u(id, 66) * (FollowerLook.TEMPO_MAX - FollowerLook.TEMPO_MIN),
		phase = u(id, 67) * math.pi * 2,
	}
end

-- The march at `time`: a hop with squash on landing and stretch at the top.
function FollowerLook.march(look: Look, time: number): March
	local step = math.abs(math.sin(time * look.tempo * 0.5 + look.phase)) -- 0 on the foot, 1 at the top
	local sy = 1 + FollowerLook.SQUASH * (2 * step - 1)
	return { y = look.bounce * step, squashY = sy, squashXZ = 1 / math.sqrt(sy) }
end

-- True when a foot came down between `prev` and `now` (the step wave crossed zero).
function FollowerLook.footfall(look: Look, prev: number, now: number): boolean
	local function index(t: number): number
		return math.floor((t * look.tempo * 0.5 + look.phase) / math.pi)
	end
	return index(now) > index(prev)
end

-- Whether that footfall raises a dust puff (a seeded share, so the cloud stays sparse).
function FollowerLook.raisesDust(id: number, footfallCount: number): boolean
	return FollowerSlots.unit(id * 131 + footfallCount, 68) < FollowerLook.DUST_CHANCE
end

-- Crowd-wide breathing scale, pulsing on the beat (Config.music.bpm); 1 on average.
function FollowerLook.breath(time: number): number
	local beats = time * Config.music.bpm / 60
	local pop = (0.5 + 0.5 * math.cos(2 * math.pi * beats)) ^ FollowerLook.BREATH_POWER
	return 1 + FollowerLook.BREATH * (2 * pop - 1)
end

-- Roll in radians for a follower moving sideways at `viewVx` studs/second (view space: positive
-- is screen-right); leans into the turn.
function FollowerLook.lean(viewVx: number): number
	return math.clamp(
		-viewVx * FollowerLook.LEAN_PER_SPEED,
		-FollowerLook.MAX_LEAN,
		FollowerLook.MAX_LEAN
	)
end

return FollowerLook
