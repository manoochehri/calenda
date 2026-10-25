--!strict
-- Pure dancer animation (issue #20, spec s7): swirling skirts, coordinated steps, and the gift
-- toss. Angles are radians, lengths studs; the beat comes from Config.music. Steps depend only on
-- time, so every dancer in a group steps together; only the skirt swirl takes a per-dancer phase.
local Config = require("./Config")
local DanceConfig = require("./DanceConfig")

local DancerPose = {}

DancerPose.HOP_STUDS = DanceConfig.dancerHopStuds
DancerPose.FOOT_LIFT = DanceConfig.dancerFootLiftStuds
DancerPose.MAX_SWIRL = DanceConfig.dancerMaxSwirlRadians
DancerPose.FLARE_MIN = DanceConfig.dancerFlareMin
DancerPose.TOSS_SECONDS = DanceConfig.dancerTossSeconds
DancerPose.SIDE_SPACING = DanceConfig.dancerSideSpacing
DancerPose.RANK_DEPTH = DanceConfig.dancerRankDepth
DancerPose.FOLLOWER_SCALE = DanceConfig.dancerFollowerScale

local TAU = 2 * math.pi

export type Pose = {
	hop: number, -- body rises, lands on every step
	footL: number, -- one foot up at a time
	footR: number,
	swirl: number, -- skirt yaw about the waist, radians, both ways
	flare: number, -- skirt width, FLARE_MIN..1, open on the beat
	sway: number, -- body lean, radians
	armSwing: number, -- free arm swing, radians
}
export type Toss = { raise: number, lift: number } -- both 0..1
export type Slot = { dx: number, dz: number, scale: number }

function DancerPose.into(out: Pose, time: number, swirlPhase: number): Pose
	local beats = time * Config.music.bpm / 60
	local step = math.sin(math.pi * beats)
	local phraseBeat = beats % DanceConfig.cycleBeats
	local chorus = if phraseBeat >= 8 then 1 else 0
	out.hop = DancerPose.HOP_STUDS * math.abs(step)
	out.footL = DancerPose.FOOT_LIFT * math.max(0, step)
	out.footR = DancerPose.FOOT_LIFT * math.max(0, -step)
	out.swirl = DancerPose.MAX_SWIRL * math.sin(TAU * (beats / 4 + swirlPhase))
	out.flare = DancerPose.FLARE_MIN
		+ (1 - DancerPose.FLARE_MIN) * (0.5 + 0.5 * math.cos(TAU * beats))
	out.sway = DanceConfig.dancerSwayRadians * (1 + chorus * 0.5) * math.sin(math.pi * beats / 2)
	out.armSwing = DanceConfig.dancerArmRadians * (1 + chorus * 0.4) * math.sin(math.pi * beats)
	return out
end

function DancerPose.pose(time: number, swirlPhase: number): Pose
	return DancerPose.into({
		hop = 0,
		footL = 0,
		footR = 0,
		swirl = 0,
		flare = 0,
		sway = 0,
		armSwing = 0,
	}, time, swirlPhase)
end

-- The basket arm's throw, `age` seconds after a gift shot: quick wind-up, peak mid-throw, settle.
function DancerPose.toss(age: number): Toss
	if age <= 0 or age >= DancerPose.TOSS_SECONDS then
		return { raise = 0, lift = 0 }
	end
	local s = math.sin(math.pi * age / DancerPose.TOSS_SECONDS)
	return { raise = s ^ 0.7, lift = s ^ 2 }
end

-- Where each of `n` dancers of one section stands: the lead first, the rest in a V behind it.
function DancerPose.formation(n: number): { Slot }
	local out: { Slot } = {}
	for i = 1, n do
		if i == 1 then
			table.insert(out, { dx = 0, dz = 0, scale = 1 })
		else
			local rank = (i - 2) // 2 + 1
			local side = if i % 2 == 0 then -1 else 1
			table.insert(out, {
				dx = side * rank * DancerPose.SIDE_SPACING,
				dz = -rank * DancerPose.RANK_DEPTH,
				scale = DancerPose.FOLLOWER_SCALE,
			})
		end
	end
	return out
end

return DancerPose
