--!strict
-- Pure decisions behind the lead musician, who is the player's own Roblox avatar (issue #55,
-- ADR 0003). The client (src/client/LeadAvatar, src/client/CrowdView) turns these numbers into
-- Roblox positions; nothing here touches the engine, so Lune tests them.
-- The server never sees the avatar: the lead's hitbox stays the fixed Crossing hitbox.
local ViewMap = require("./ViewMap")
local DanceConfig = require("./DanceConfig")

local LeadPose = {}

LeadPose.BOB_HEIGHT = DanceConfig.leadBobStuds
LeadPose.BOB_RATE = DanceConfig.leadBobRadiansPerSecond
LeadPose.FACING_YAW = math.pi -- a Roblox front is -z; the parade walks toward +z
LeadPose.FALLBACK_GRACE = 3 -- [default] seconds without an avatar before the block stand-in shows
LeadPose.AVATAR_TOP = 6 -- studs: a default avatar with a tall hat or hair stays under this
-- Issue #114: the lead is bigger and its ground ring wider. AVATAR_SCALE is applied to the player's
-- character by LeadAvatar (Model:ScaleTo). DEFAULT_AVATAR_HEIGHT is a standing default R15 avatar,
-- about 5 studs: UNVERIFIED in Studio. The scaled lead must stay under CameraRig.LEAD_TOP.
LeadPose.AVATAR_SCALE = 1.15 -- [default]
LeadPose.DEFAULT_AVATAR_HEIGHT = 5 -- studs, UNVERIFIED (see above)
LeadPose.RING_DIAMETER = 10 -- [default] studs; was 8. Fits the road (FollowerSlots.roadHalfWidth).

export type Pose = { x: number, y: number, z: number }

-- Height of the HumanoidRootPart's centre above the ground for a standing rig. R15 stands on its
-- hips (Humanoid.HipHeight); R6 has no hip height, its legs are 2 studs.
function LeadPose.rootHeight(rigType: string, hipHeight: number, rootSizeY: number): number
	local half = math.max(rootSizeY, 0.1) / 2
	if rigType == "R6" then
		return 2 + half
	end
	return math.max(hipHeight, 0) + half
end

-- Where the root goes this frame. `worldX` is the (smoothed) world x and goes through ViewMap.x;
-- `lift` is the breakup hop (issue #16); the bob is a march when no animation is available.
function LeadPose.at(worldX: number, z: number, clock: number, lift: number, standing: number): Pose
	return {
		x = ViewMap.x(worldX),
		y = standing + LeadPose.BOB_HEIGHT * math.abs(math.sin(clock * LeadPose.BOB_RATE)) + lift,
		z = z,
	}
end

-- Seconds the lead has been without an avatar (reset the moment one is present).
function LeadPose.absence(previous: number, hasAvatar: boolean, dt: number): number
	if hasAvatar then
		return 0
	end
	return previous + dt
end

-- Seconds without an avatar before the block shows: plain FALLBACK_GRACE for the join case (no
-- character has loaded yet), but after a reset or removal the server's respawn (Players.RespawnTime)
-- must be waited out first so the block never flashes.
function LeadPose.graceFor(hadAvatar: boolean, respawnTime: number): number
	if hadAvatar then
		return math.max(respawnTime, 0) + LeadPose.FALLBACK_GRACE
	end
	return LeadPose.FALLBACK_GRACE
end

-- The primitive block shows only when no avatar has been available for the whole grace period.
function LeadPose.showFallback(hasAvatar: boolean, absent: number, grace: number?): boolean
	return (not hasAvatar) and absent >= (grace or LeadPose.FALLBACK_GRACE)
end

return LeadPose
