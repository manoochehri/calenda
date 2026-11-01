--!strict
-- Issue #171: the pure decisions behind the Config.debug A/B switches for the road-flash
-- candidates. With every switch false (the default) each function returns its input unchanged, so
-- the normal game is untouched. The client calls these at the one site where each effect is set.
local DebugSwitches = {}

export type Flags = {
	noTrails: boolean,
	noHitShake: boolean,
	noTransparentStrips: boolean,
	noDust: boolean,
	noShotExtras: boolean?,
	noGateStrip: boolean?,
	noRewardFloaters: boolean?,
	noLeadRing: boolean?,
}

-- Shot Trail: off when `noTrails`, otherwise whatever the shot wants.
function DebugSwitches.trailEnabled(debug: Flags, wanted: boolean): boolean
	return wanted and not debug.noTrails
end

-- Hit camera shake offsets (camera space): zero when `noHitShake`.
function DebugSwitches.hitShake(debug: Flags, x: number, y: number): (number, number)
	if debug.noHitShake then
		return 0, 0
	end
	return x, y
end

-- Translucent ground strip / ring: fully opaque when `noTransparentStrips`; a hidden part (1) stays hidden.
function DebugSwitches.stripTransparency(debug: Flags, transparency: number): number
	if debug.noTransparentStrips and transparency < 1 then
		return 0
	end
	return transparency
end

-- ParticleEmitter dust (warning chevrons, charging mobs): no emission when `noDust`.
function DebugSwitches.dustRate(debug: Flags, rate: number): number
	return if debug.noDust then 0 else rate
end

function DebugSwitches.allowDustPuff(debug: Flags): boolean
	return not debug.noDust
end

-- Issue #255 calm screen. Builders ask first so an off effect creates no Instance at all.

-- Shot Trail and its two Attachments are built only when `noTrails` is off.
function DebugSwitches.shotTrailBuilt(debug: Flags): boolean
	return not debug.noTrails
end

-- Extra Neon parts per shot: `wanted`, or 0 when `noShotExtras`.
function DebugSwitches.shotExtraParts(debug: Flags, wanted: number): number
	return if debug.noShotExtras then 0 else wanted
end

-- Dust ParticleEmitters (chevron and mob) are built only when `noDust` is off.
function DebugSwitches.dustBuilt(debug: Flags): boolean
	return not debug.noDust
end

-- The translucent gate crossing strip: hidden (1) when `noGateStrip`.
function DebugSwitches.gateStripTransparency(debug: Flags, transparency: number): number
	return if debug.noGateStrip then 1 else transparency
end

-- "+N" reward floaters over the lane.
function DebugSwitches.rewardFloaters(debug: Flags): boolean
	return not debug.noRewardFloaters
end

-- The lead ring Part is built only when `noLeadRing` is off.
function DebugSwitches.leadRingBuilt(debug: Flags): boolean
	return not debug.noLeadRing
end

return DebugSwitches
