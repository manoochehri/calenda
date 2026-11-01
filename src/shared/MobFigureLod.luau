--!strict
-- Issue #256 / #147: per-figure level of detail for the horde. The number of figures never changes
-- (the owner wants dense people-like crowds, not a lower enemy count); only the Parts per figure do.
-- `frac` is the figure's share of screen height (CameraRig.screenFraction at scale 1).
--   tier 3 (near): body + head + arms = 3 Parts
--   tier 2 (mid):  body + head        = 2 Parts (arms are sub-pixel here)
--   tier 1 (far):  one taller body    = 1 Part (a head-and-shoulders capsule silhouette)
-- Thresholds are [default] values; hysteresis stops a figure flickering between tiers on a boundary.
-- Pure: Lune-tested. The frame-time benefit is UNVERIFIED until measured with the perf overlay.
local MobFigureLod = {}

MobFigureLod.NEAR_FRAC = 0.022 -- [default] at or above this the figure keeps all 3 Parts (= minScreenFraction)
MobFigureLod.MID_FRAC = 0.011 -- [default] at or above this (and below NEAR) 2 Parts; below, 1 Part
MobFigureLod.HYSTERESIS = 0.12 -- [default] share of a threshold a figure must cross to change tier

-- Parts drawn for a figure at `frac`, given the tier it had last frame (nil = first frame).
function MobFigureLod.tier(frac: number, prev: number?): number
	local near, mid, h = MobFigureLod.NEAR_FRAC, MobFigureLod.MID_FRAC, MobFigureLod.HYSTERESIS
	-- moving to a MORE detailed tier needs the threshold plus the margin; to a LESS detailed one,
	-- the threshold minus it.
	local nearAt = if prev == 3 then near * (1 - h) else near * (1 + h)
	local midAt = if prev ~= nil and prev >= 2 then mid * (1 - h) else mid * (1 + h)
	if prev == nil then
		nearAt, midAt = near, mid
	end
	if frac >= nearAt then
		return 3
	elseif frac >= midAt then
		return 2
	end
	return 1
end

-- The single-Part far figure absorbs the head: its body is this much longer (a share of body height).
function MobFigureLod.bodyStretch(tier: number, bodyHeight: number, headDiameter: number): number
	if tier == 1 then
		return (bodyHeight + headDiameter * 0.8) / bodyHeight
	end
	return 1
end

-- Total Parts for figures at the given screen fractions, each starting fresh (no hysteresis).
function MobFigureLod.partsFor(fracs: { number }): number
	local total = 0
	for _, f in fracs do
		total += MobFigureLod.tier(f, nil)
	end
	return total
end

return MobFigureLod
