--!strict
-- Pinhole projection through a CameraRig.Pose (issue #68). Pure. Used by tests (and any layout
-- check) to ask whether a point in the world lands inside the visible screen rectangle. Returns
-- normalized device coordinates: x and y in -1..1 are on screen; depth <= 0 means behind the camera.
-- The pose is in VIEW space (x already through ViewMap.x), like the camera the client builds.
local CameraRig = require("./CameraRig")

local ScreenProject = {}

export type Ndc = { x: number, y: number, depth: number }

function ScreenProject.project(
	pose: CameraRig.Pose,
	aspect: number,
	px: number,
	py: number,
	pz: number
): Ndc
	local fx, fy, fz = pose.lx - pose.px, pose.ly - pose.py, pose.lz - pose.pz
	local fl = math.sqrt(fx * fx + fy * fy + fz * fz)
	fx, fy, fz = fx / fl, fy / fl, fz / fl
	-- right = forward x up(0,1,0); then true up = right x forward
	local rx, ry, rz = -fz, 0, fx
	local rl = math.sqrt(rx * rx + rz * rz)
	rx, rz = rx / rl, rz / rl
	local ux, uy, uz = ry * fz - rz * fy, rz * fx - rx * fz, rx * fy - ry * fx
	local dx, dy, dz = px - pose.px, py - pose.py, pz - pose.pz
	local depth = dx * fx + dy * fy + dz * fz
	if depth <= 1e-6 then
		return { x = 0, y = 0, depth = depth }
	end
	local t = math.tan(math.rad(CameraRig.FIELD_OF_VIEW) / 2)
	return {
		x = (dx * rx + dy * ry + dz * rz) / (depth * t * aspect),
		y = (dx * ux + dy * uy + dz * uz) / (depth * t),
		depth = depth,
	}
end

-- True when the point is inside the screen with `margin` (share of the half-extent) to spare.
function ScreenProject.onScreen(ndc: Ndc, margin: number): boolean
	local limit = 1 - margin
	return ndc.depth > 0 and math.abs(ndc.x) <= limit and math.abs(ndc.y) <= limit
end

return ScreenProject
