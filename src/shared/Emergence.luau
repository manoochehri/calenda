--!strict
-- Tension from the top (issue #65, owner feedback 2026-10-24: "the crowd just suddenly appears;
-- shouldn't they start from the top?"). Pure rules that make every wave EMERGE from beyond the
-- camera's visible range and run down the lane; nothing here changes gameplay (it only judges and
-- shapes where clusters START and how they are drawn):
--  * visible depth: how far ahead of the lead the TOP edge of the screen reaches the road, from
--    CameraRig's pose (pullback, LOOK_AHEAD, FOV). In Roblox's default FieldOfViewMode (Vertical)
--    the top edge's ground depth does not depend on the aspect ratio (16:9, 4:3, 19.5:9 give the
--    same depth; only the width at that depth changes, see halfWidthAt), so tests check all three.
--  * spawn rule: a cluster spawns at least visible depth + SPAWN_MARGIN ahead of the lead.
--  * approach time: the wave is in view for at least MIN_APPROACH_SECONDS before it arrives.
--  * calm opening: nothing is in view before CALM_OPENING_SECONDS.
--  * no pop: fade/scale-in curve, telegraph window, threat and pulse curves for the presentation.
local CameraRig = require("./CameraRig")
local Config = require("./Config")
local Level = require("./Level")

local Emergence = {}

Emergence.SPAWN_MARGIN = 30 -- [default] studs beyond the visible depth (camera lag, shake, rounding)
Emergence.MIN_APPROACH_SECONDS = 3 -- [default] owner: at least 3 s of visible approach
Emergence.CALM_OPENING_SECONDS = 5 -- [default] owner: nothing in view for the first 5-8 s
Emergence.FADE_BAND = 45 -- [default] studs over which a mob fades and scales in below the top edge
Emergence.SCALE_FROM = 0.35 -- [default] size share at the far end of the fade
Emergence.ASPECTS = table.freeze({ 16 / 9, 4 / 3, 19.5 / 9 }) -- landscape targets
Emergence.PULLBACK_STEPS = 20 -- samples across the pullback curve
Emergence.TELEGRAPH_EXTRA = 30 -- [default] studs beyond the spawn margin where the chevron appears
Emergence.THREAT_FAR = 90 -- [default] studs ahead of the lead where the threat pulse starts
Emergence.THREAT_NEAR = 15 -- [default] studs where it is at full strength
Emergence.PULSE_HZ_MIN = 1.5 -- [default]
Emergence.PULSE_HZ_MAX = 4.5 -- [default]
Emergence.STEP = 1 / 30 -- seconds, the stepping resolution of the time rules

local function smooth(x: number): number
	local c = math.clamp(x, 0, 1)
	return c * c * (3 - 2 * c)
end

-- Ground depth ahead of the lead (leadZ = 0) of the screen's top edge for a camera at `pullback`.
function Emergence.visibleDepthAhead(pullback: number, fov: number?): number
	local pose = CameraRig.pose(0, 0, pullback)
	local ray = CameraRig.pitchDegrees(pose) - (fov or CameraRig.FIELD_OF_VIEW) / 2
	ray = math.max(ray, 1) -- a top edge at or above the horizon sees the road out to the far fog
	return pose.pz + pose.py / math.tan(math.rad(ray))
end

-- Smallest and largest top-edge depth over the camera's pullback range (Config curve).
function Emergence.depthRange(config: any?): (number, number)
	local curve = (config or Config).visualBudget.cameraPullback
	local lo, hi = math.huge, -math.huge
	for i = 0, Emergence.PULLBACK_STEPS do
		local p = curve.start + (curve.max - curve.start) * i / Emergence.PULLBACK_STEPS
		local d = Emergence.visibleDepthAhead(p)
		lo, hi = math.min(lo, d), math.max(hi, d)
	end
	return lo, hi
end

-- Half width of the visible road at `ahead` studs in front of the lead, for a viewport aspect.
function Emergence.halfWidthAt(pullback: number, ahead: number, aspect: number): number
	local pose = CameraRig.pose(0, 0, pullback)
	local dy, dz = pose.ly - pose.py, pose.lz - pose.pz
	local len = math.sqrt(dy * dy + dz * dz)
	local depth = (0 - pose.py) * (dy / len) + (ahead - pose.pz) * (dz / len)
	return depth * math.tan(math.rad(CameraRig.FIELD_OF_VIEW / 2)) * aspect
end

-- The least distance ahead of the lead, at spawnTime, that a cluster may spawn at.
function Emergence.requiredSpawnOffset(config: any?): number
	local _, hi = Emergence.depthRange(config)
	return hi + Emergence.SPAWN_MARGIN
end

function Emergence.spawnOffset(_layout: Level.Layout, cluster: Level.Cluster, config: any?): number
	return cluster.spawn.z - Level.leadZ(cluster.spawnTime, config)
end

-- Seconds the cluster is inside the visible depth before it reaches the lead (its z <= lead z).
-- 0 when it already starts inside the view (a pop). math.huge if it never reaches the lead.
function Emergence.approachSeconds(
	layout: Level.Layout,
	cluster: Level.Cluster,
	depth: number,
	config: any?
): number
	local t = cluster.spawnTime
	local enteredAt: number? = nil
	while t < cluster.spawnTime + 600 do
		local ahead = Level.clusterPosition(layout, cluster.id, t, config).z
			- Level.leadZ(t, config)
		if enteredAt == nil and ahead <= depth then
			if t == cluster.spawnTime then
				return 0
			end
			enteredAt = t
		end
		if ahead <= 0 then
			return if enteredAt == nil then 0 else t - enteredAt
		end
		t += Emergence.STEP
	end
	return math.huge
end

-- First run time at which any cluster is inside the visible depth.
function Emergence.firstVisibleTime(layout: Level.Layout, depth: number, config: any?): number
	local first = math.huge
	for _, c in layout.clusters do
		local t = c.spawnTime
		while t < math.min(first, c.spawnTime + 600) do
			local ahead = Level.clusterPosition(layout, c.id, t, config).z - Level.leadZ(t, config)
			if ahead <= depth then
				first = math.min(first, t)
				break
			end
			t += Emergence.STEP
		end
	end
	return first
end

-- Layout rules as error strings (empty = fine). Used by LayoutValidator.
function Emergence.check(layout: Level.Layout, config: any?): { string }
	local errs: { string } = {}
	local lo, hi = Emergence.depthRange(config)
	local need = hi + Emergence.SPAWN_MARGIN
	for _, c in layout.clusters do
		local off = Emergence.spawnOffset(layout, c, config)
		if off < need then
			table.insert(
				errs,
				`cluster {c.id} spawns {off} studs ahead of the lead, inside the visible depth + margin {need}`
			)
		end
		local secs = Emergence.approachSeconds(layout, c, lo, config)
		if secs < Emergence.MIN_APPROACH_SECONDS then
			table.insert(
				errs,
				`cluster {c.id} is in view only {secs} s before it arrives, under {Emergence.MIN_APPROACH_SECONDS} s`
			)
		end
	end
	local first = Emergence.firstVisibleTime(layout, lo, config)
	if first < Emergence.CALM_OPENING_SECONDS then
		table.insert(
			errs,
			`a wave is in view at {first} s, inside the calm opening of {Emergence.CALM_OPENING_SECONDS} s`
		)
	end
	return errs
end

-- Presentation curves. `ahead` = cluster z minus lead z; `depth` = the current visible depth.

-- 0 at and beyond the top edge, 1 once FADE_BAND studs below it. Monotone, never a step.
function Emergence.fade(ahead: number, depth: number): number
	return smooth((depth - ahead) / Emergence.FADE_BAND)
end

-- Size multiplier that grows with the fade (SCALE_FROM .. 1).
function Emergence.scaleIn(ahead: number, depth: number): number
	export type Bar = { x: number, z: number, yaw: number, length: number, width: number }

	Emergence.CHEVRON_ARM = 6 -- [default] studs, length of one arm
	Emergence.CHEVRON_WIDTH = 1.6 -- [default] studs
	Emergence.CHEVRON_ANGLE = math.rad(40) -- [default] each arm's angle from the lane axis
	Emergence.CHEVRON_GAP = 1.2 -- [default] studs from the apex to where an arm starts (no overlap)

	-- The warning chevron as two flat bars in ROBLOX space (x already mirrored by the caller): a "v"
	-- whose apex points down the lane (toward the parade, -z) at (x, z); the arms run back toward the
	-- camera (+z) and outward. `yaw` is the CFrame.Angles(0, yaw, 0) rotation that turns a bar's
	-- long X axis along its arm: Roblox maps +X to (cos yaw, -sin yaw) in (x, z).
	function Emergence.chevronBars(x: number, z: number): { Bar }
		local out: { Bar } = {}
		for _, side in { -1, 1 } do
			local dx, dz =
				side * math.sin(Emergence.CHEVRON_ANGLE), math.cos(Emergence.CHEVRON_ANGLE)
			local reach = Emergence.CHEVRON_GAP + Emergence.CHEVRON_ARM / 2
			table.insert(out, {
				x = x + dx * reach,
				z = z + dz * reach,
				yaw = math.atan2(-dz, dx),
				length = Emergence.CHEVRON_ARM,
				width = Emergence.CHEVRON_WIDTH,
			})
		end
		return out
	end

	return Emergence.SCALE_FROM + (1 - Emergence.SCALE_FROM) * Emergence.fade(ahead, depth)
end

-- Warning chevron at the top of the lane: 0 far beyond the spawn, 1 around the top edge, fading
-- out once the mob is big enough to read (ahead < 0.6 * depth).
function Emergence.telegraph(ahead: number, depth: number): number
	local top = depth + Emergence.SPAWN_MARGIN + Emergence.TELEGRAPH_EXTRA
	local rampIn = smooth((top + 20 - ahead) / 20)
	local rampOut = smooth((ahead - depth * 0.5) / (depth * 0.15))
	return math.min(rampIn, rampOut)
end

-- 0 far away, 1 when the mob is about to hit.
function Emergence.threat(ahead: number): number
	return smooth((Emergence.THREAT_FAR - ahead) / (Emergence.THREAT_FAR - Emergence.THREAT_NEAR))
end

-- Pulse 0..1 whose rate rises with the threat. Phase is the integral of the rate, so pass the
-- running phase accumulated with `pulseRate`.
function Emergence.pulseRate(threat: number): number
	export type Bar = { x: number, z: number, yaw: number, length: number, width: number }

	Emergence.CHEVRON_ARM = 6 -- [default] studs, length of one arm
	Emergence.CHEVRON_WIDTH = 1.6 -- [default] studs
	Emergence.CHEVRON_ANGLE = math.rad(40) -- [default] each arm's angle from the lane axis
	Emergence.CHEVRON_GAP = 1.2 -- [default] studs from the apex to where an arm starts (no overlap)

	-- The warning chevron as two flat bars in ROBLOX space (x already mirrored by the caller): a "v"
	-- whose apex points down the lane (toward the parade, -z) at (x, z); the arms run back toward the
	-- camera (+z) and outward. `yaw` is the CFrame.Angles(0, yaw, 0) rotation that turns a bar's
	-- long X axis along its arm: Roblox maps +X to (cos yaw, -sin yaw) in (x, z).
	function Emergence.chevronBars(x: number, z: number): { Bar }
		local out: { Bar } = {}
		for _, side in { -1, 1 } do
			local dx, dz =
				side * math.sin(Emergence.CHEVRON_ANGLE), math.cos(Emergence.CHEVRON_ANGLE)
			local reach = Emergence.CHEVRON_GAP + Emergence.CHEVRON_ARM / 2
			table.insert(out, {
				x = x + dx * reach,
				z = z + dz * reach,
				yaw = math.atan2(-dz, dx),
				length = Emergence.CHEVRON_ARM,
				width = Emergence.CHEVRON_WIDTH,
			})
		end
		return out
	end

	return Emergence.PULSE_HZ_MIN + (Emergence.PULSE_HZ_MAX - Emergence.PULSE_HZ_MIN) * threat
end

function Emergence.pulse(threat: number, phase: number): number
	return threat * (0.5 + 0.5 * math.sin(phase * math.pi * 2))
end

export type Bar = { x: number, z: number, yaw: number, length: number, width: number }

Emergence.CHEVRON_ARM = 6 -- [default] studs, length of one arm
Emergence.CHEVRON_WIDTH = 1.6 -- [default] studs
Emergence.CHEVRON_ANGLE = math.rad(40) -- [default] each arm's angle from the lane axis
Emergence.CHEVRON_GAP = 1.2 -- [default] studs from the apex to where an arm starts (no overlap)

-- The warning chevron as two flat bars in ROBLOX space (x already mirrored by the caller): a "v"
-- whose apex points down the lane (toward the parade, -z) at (x, z); the arms run back toward the
-- camera (+z) and outward. `yaw` is the CFrame.Angles(0, yaw, 0) rotation that turns a bar's
-- long X axis along its arm: Roblox maps +X to (cos yaw, -sin yaw) in (x, z).
function Emergence.chevronBars(x: number, z: number): { Bar }
	local out: { Bar } = {}
	for _, side in { -1, 1 } do
		local dx, dz = side * math.sin(Emergence.CHEVRON_ANGLE), math.cos(Emergence.CHEVRON_ANGLE)
		local reach = Emergence.CHEVRON_GAP + Emergence.CHEVRON_ARM / 2
		table.insert(out, {
			x = x + dx * reach,
			z = z + dz * reach,
			yaw = math.atan2(-dz, dx),
			length = Emergence.CHEVRON_ARM,
			width = Emergence.CHEVRON_WIDTH,
		})
	end
	return out
end

return Emergence
