--!strict
-- Pure puppet animation curves (issue #14, spec s7): bobbing head, loose swinging arms, claps and
-- sway to the beat, and the rise pop. Angles are radians, lengths studs; the client applies them
-- to primitive Parts. Time is seconds; the beat comes from Config.music.
local Config = require("./Config")
local DanceConfig = require("./DanceConfig")

local PuppetPose = {}

PuppetPose.MAX_ARM_RADIANS = DanceConfig.puppetArmRadians
PuppetPose.MAX_SWAY_RADIANS = DanceConfig.puppetSwayRadians
PuppetPose.BOW_RADIANS = DanceConfig.puppetBowRadians
PuppetPose.MAX_INTENSITY = DanceConfig.maxAmplitude
PuppetPose.HEAD_BOB_STUDS = DanceConfig.puppetHeadBobStuds
local INTENSITY_PER_SECTION = DanceConfig.puppetIntensityPerSection
local OVERSHOOT = DanceConfig.puppetRiseOvershoot

export type Pose = {
	headBob: number, -- studs, 0..HEAD_BOB_STUDS-ish, two bobs per beat pair
	headTilt: number, -- radians
	armLeft: number, -- swing angle about the shoulder
	armRight: number,
	clap: number, -- 0 open .. 1 hands together, peaks on each beat
	sway: number, -- body lean, radians
	bow: number, -- forward nod at the downbeat of the four-bar phrase
}

-- `phase` offsets decorrelate the entourage from the main puppet.
function PuppetPose.into(out: Pose, time: number, phase: number): Pose
	local beats = time * Config.music.bpm / 60 + phase
	local tau = 2 * math.pi
	local beatWave = math.cos(tau * beats) -- 1 on every beat
	local halfBar = beats / 2
	local swingBase = math.sin(tau * halfBar)
	local phraseBeat = beats % DanceConfig.cycleBeats
	local bow = if phraseBeat < 0.35 then PuppetPose.BOW_RADIANS * (1 - phraseBeat / 0.35) else 0
	local chorus = if phraseBeat >= 8 then 1 else 0
	out.headBob = PuppetPose.HEAD_BOB_STUDS * (0.5 + 0.5 * beatWave)
	out.headTilt = 0.2 * math.sin(tau * halfBar + 0.8)
	-- Loose arms: a slow swing plus a lagging second harmonic, left and right offset.
	out.armLeft = math.clamp(
		DanceConfig.puppetArmBaseRadians * swingBase
			+ DanceConfig.puppetArmSecondaryRadians * math.sin(tau * beats + 1.1)
			+ chorus * 0.7,
		-PuppetPose.MAX_ARM_RADIANS,
		PuppetPose.MAX_ARM_RADIANS
	)
	out.armRight = math.clamp(
		DanceConfig.puppetArmBaseRadians * math.sin(tau * halfBar + 2.2)
			+ DanceConfig.puppetArmSecondaryRadians * math.sin(tau * beats - 0.7)
			+ chorus * 0.7,
		-PuppetPose.MAX_ARM_RADIANS,
		PuppetPose.MAX_ARM_RADIANS
	)
	out.clap = math.clamp(0.5 + 0.5 * beatWave, 0, 1) ^ DanceConfig.puppetClapPower
	out.sway = PuppetPose.MAX_SWAY_RADIANS * 0.8 * math.sin(tau * halfBar / 2)
	out.bow = bow
	return out
end

function PuppetPose.pose(time: number, phase: number): Pose
	return PuppetPose.into({
		headBob = 0,
		headTilt = 0,
		armLeft = 0,
		armRight = 0,
		clap = 0,
		sway = 0,
		bow = 0,
	}, time, phase)
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
