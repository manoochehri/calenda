--!strict
-- Issue #240: the pure decisions behind the Config.debug A/B switches for horde and parade motion.
-- With every switch false (the default) each function returns its input unchanged, so the normal
-- game is untouched. The client calls these at the one site where each motion is applied.
-- Display only; nothing here touches a hit, a credit, a count or a target.
local MotionSwitches = {}

export type Flags = {
	noMobStride: boolean, -- horde figures: no hop, no arm pump (lean and advance remain)
	calmMobStride: boolean, -- horde figures: small hop, no arm pump
	noBreath: boolean, -- parade: no per-beat size pulse
	noCrowdFeel: boolean, -- parade: no join bounce, cheer hop or flinch dip
	noFollowerDance: boolean, -- parade: no beat-synced dance hop, sway or spin
	noFollowerMarch: boolean, -- parade: no march hop and no squash/stretch
}

MotionSwitches.CALM_HOP_SHARE = 0.3 -- [default] share of the stride hop kept by calmMobStride

-- A charging horde figure's (hop, lean, arm height). `armRest` is the un-pumped arm height.
function MotionSwitches.mobStride(
	debug: Flags,
	hop: number,
	lean: number,
	arm: number,
	armRest: number
): (number, number, number)
	if debug.noMobStride then
		return 0, lean, armRest
	end
	if debug.calmMobStride then
		return hop * MotionSwitches.CALM_HOP_SHARE, lean, armRest
	end
	return hop, lean, arm
end

-- Parade size pulse on the beat (1 = none).
function MotionSwitches.breath(debug: Flags, scale: number): number
	return if debug.noBreath then 1 else scale
end

-- Join bounce + cheer + flinch: (hop, scaleY, scaleXZ).
function MotionSwitches.crowdFeel(
	debug: Flags,
	hop: number,
	sy: number,
	sxz: number
): (number, number, number)
	if debug.noCrowdFeel then
		return 0, 1, 1
	end
	return hop, sy, sxz
end

-- Beat-synced dance: (hop, sway, spin).
function MotionSwitches.dance(
	debug: Flags,
	hop: number,
	sway: number,
	spin: number
): (number, number, number)
	if debug.noFollowerDance then
		return 0, 0, 0
	end
	return hop, sway, spin
end

-- March hop with squash and stretch: (hop, scaleY, scaleXZ).
function MotionSwitches.march(
	debug: Flags,
	hop: number,
	sy: number,
	sxz: number
): (number, number, number)
	if debug.noFollowerMarch then
		return 0, 1, 1
	end
	return hop, sy, sxz
end

return MotionSwitches
