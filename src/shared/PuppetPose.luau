--!strict
-- Pure puppet animation curves (issue #14, spec s7): bobbing head, loose swinging arms, claps and
-- sway to the beat, and the rise pop. Angles are radians, lengths studs; the client applies them
-- to primitive Parts. Time is seconds; the beat comes from Config.music.
local Config = require("./Config")

local PuppetPose = {}

PuppetPose.MAX_ARM_RADIANS = 1.4 -- [default]
PuppetPose.MAX_SWAY_RADIANS = 0.12 -- [default]
PuppetPose.MAX_INTENSITY = 1.5 -- [default] music/decoration intensity grows but is capped (spec s8)
PuppetPose.HEAD_BOB_STUDS = 0.6 -- [default]
local INTENSITY_PER_SECTION = 0.05 -- [default]
local OVERSHOOT = 1.70158 -- standard ease-out-back constant

export type Pose = {
	headBob: number, -- studs, 0..HEAD_BOB_STUDS-ish, two bobs per beat pair
	headTilt: number, -- radians
	armLeft: number, -- swing angle about the shoulder
	armRight: number,
	clap: number, -- 0 open .. 1 hands together, peaks on each beat
	sway: number, -- body lean, radians
}

-- `phase` offsets decorrelate the entourage from the main puppet.
function PuppetPose.pose(time: number, phase: number): Pose
	local beats = time * Config.music.bpm / 60 + phase
	local tau = 2 * math.pi
	local beatWave = math.cos(tau * beats) -- 1 on every beat
	local halfBar = beats / 2
	local swingBase = math.sin(tau * halfBar)
	return {
		headBob = PuppetPose.HEAD_BOB_STUDS * (0.5 + 0.5 * beatWave),
		headTilt = 0.2 * math.sin(tau * halfBar + 0.8),
		-- Loose arms: a slow swing plus a lagging second harmonic, left and right offset.
		armLeft = math.clamp(
			0.9 * swingBase + 0.35 * math.sin(tau * beats + 1.1),
			-PuppetPose.MAX_ARM_RADIANS,
			PuppetPose.MAX_ARM_RADIANS
		),
		armRight = math.clamp(
			0.9 * math.sin(tau * halfBar + 2.2) + 0.35 * math.sin(tau * beats - 0.7),
			-PuppetPose.MAX_ARM_RADIANS,
			PuppetPose.MAX_ARM_RADIANS
		),
		clap = math.clamp(0.5 + 0.5 * beatWave, 0, 1) ^ 4,
		sway = PuppetPose.MAX_SWAY_RADIANS * 0.8 * math.sin(tau * halfBar / 2),
	}
end

-- Extra liveliness for more sections: bigger bounce, more confetti. Bounded, never endless.
function PuppetPose.intensity(logicalSections: number): number
	return math.min(
		PuppetPose.MAX_INTENSITY,
		1 + INTENSITY_PER_SECTION * math.max(0, logicalSections - 1)
	)
end

-- Rise scale for progress 0..1: ease-out-back, so the puppet pops slightly past full size.
function PuppetPose.rise(t: number): number
	if t <= 0 then
		return 0
	elseif t >= 1 then
		return 1
	end
	local u = t - 1
	return 1 + (OVERSHOOT + 1) * u * u * u + OVERSHOOT * u * u
end

return PuppetPose
