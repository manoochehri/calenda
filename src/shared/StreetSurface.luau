--!strict
-- Issue #54 (Amendment 9): the street's ground surfaces. The road surface is 30 studs wide (edges at
-- |x| = 15, one stud further out than the old 28-stud road), inside the unchanged 40-stud corridor
-- (halfWidth 20); the sidewalks take the rest. The earth plate under the street is sized from the
-- high camera's visible ground, so no empty or checker ground shows beyond the buildings. Pure: no
-- Roblox APIs, so the width and the coverage bound are testable under Lune.
local CameraRig = require("./CameraRig")

local StreetSurface = {}

-- How far the road edge sits inside the corridor edge (halfWidth). 5 gives a 30-stud road.
StreetSurface.ROAD_INSET = 5
-- Margin (studs) the earth plate extends beyond the street on every side.
StreetSurface.GROUND_MARGIN = 1500

-- Half width (studs) of the road surface for a corridor of `halfWidth`.
function StreetSurface.roadHalfWidth(halfWidth: number): number
	return halfWidth - StreetSurface.ROAD_INSET
end

-- Width (studs) of one sidewalk: the corridor edge minus the road edge.
function StreetSurface.sidewalkWidth(halfWidth: number): number
	return halfWidth - StreetSurface.roadHalfWidth(halfWidth)
end

-- The earth plate under everything: x in [x0, x1], z in [z0, z1] (studs, world coordinates).
export type Plate = { x0: number, x1: number, z0: number, z1: number }

function StreetSurface.groundPlate(streetLength: number): Plate
	return {
		x0 = -StreetSurface.GROUND_MARGIN,
		x1 = StreetSurface.GROUND_MARGIN,
		z0 = -StreetSurface.GROUND_MARGIN,
		z1 = streetLength + StreetSurface.GROUND_MARGIN,
	}
end

-- Distance along the ground from the camera's foot to where a ray `depressionDegrees` below the
-- horizon lands, given the camera height `distanceBelow` above the ground.
local function ground(distanceBelow: number, depressionDegrees: number): number
	return distanceBelow / math.tan(math.rad(depressionDegrees))
end

-- Farthest ground z the camera can see on the centre line: the top edge of the vertical field of
-- view. A top edge at or above the horizon sees the sky, so the result is math.huge (not covered).
function StreetSurface.farVisibleGroundZ(pose: CameraRig.Pose): number
	local top = CameraRig.pitchDegrees(pose) - CameraRig.FIELD_OF_VIEW / 2
	if top <= 0 then
		return math.huge
	end
	return pose.pz + ground(pose.py, top)
end

-- Nearest ground z the camera can see on the centre line: the bottom edge of the view. Past
-- vertical the bottom edge points back toward the camera, so ground behind it is visible.
function StreetSurface.nearVisibleGroundZ(pose: CameraRig.Pose): number
	local bottom = CameraRig.pitchDegrees(pose) + CameraRig.FIELD_OF_VIEW / 2
	if bottom < 90 then
		return pose.pz + ground(pose.py, bottom)
	end
	return pose.pz - ground(pose.py, 180 - bottom)
end

return StreetSurface
