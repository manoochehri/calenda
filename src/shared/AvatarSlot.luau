--!strict
-- Issue #203: pure maths for the title screen's marching avatar slot. A ViewportFrame shows a
-- clone of the player's own character marching in place (client/StartupScreen). The march here is
-- a small bob and sway on the clone's root, so it marches even when no animation can be played in
-- a viewport. The values are tuning defaults; the on-device look is UNVERIFIED.
local AvatarSlot = {}

AvatarSlot.FOV = 30 -- [default] degrees, vertical, of the slot's camera
AvatarSlot.WIDTH_STUDS = 4.5 -- [default] the widest the avatar gets (arms out, hats), studs
AvatarSlot.MARGIN = 1.15 -- [default] framing margin around the avatar
AvatarSlot.PERIOD = 0.5 -- [default] seconds per step (two steps per second, a march at ~120 bpm)
AvatarSlot.BOB = 0.35 -- [default] studs of lift at the top of a step
AvatarSlot.SWAY = math.rad(4) -- [default] radians of side-to-side roll

-- Distance from the avatar so a `height`-stud avatar fits a slot of width/height `aspect`.
function AvatarSlot.cameraDistance(height: number, fov: number, aspect: number): number
	local tanHalf = math.tan(math.rad(fov) / 2)
	local byHeight = (height / 2) / tanHalf
	local byWidth = (AvatarSlot.WIDTH_STUDS / 2) / (tanHalf * math.max(aspect, 0.05))
	return math.max(byHeight, byWidth) * AvatarSlot.MARGIN
end

export type March = { lift: number, roll: number }

-- The in-place march `clock` seconds in: a lift that is 0 on the ground and BOB at the top of each
-- step, and a roll that swings once per two steps.
function AvatarSlot.march(clock: number): March
	local phase = clock / AvatarSlot.PERIOD * math.pi
	return {
		lift = AvatarSlot.BOB * math.abs(math.sin(phase)),
		roll = AvatarSlot.SWAY * math.sin(phase),
	}
end

-- The attach fallback (reviewer suggestion on PR #205). The title screen tries to attach the
-- player's avatar while `pending`. An attempt reports "notready" (character or appearance not
-- there yet: keep polling), "built" (the viewport works) or "threw" (the setup errored). A throw
-- latches to the "puppet" cutout for good, so a failing setup is not repeated every poll.
export type AttachStatus = "pending" | "attached" | "puppet"
export type AttachOutcome = "notready" | "built" | "threw"

function AvatarSlot.attachNext(status: AttachStatus, outcome: AttachOutcome): AttachStatus
	if status ~= "pending" then
		return status -- attached and puppet are final
	end
	if outcome == "built" then
		return "attached"
	elseif outcome == "threw" then
		return "puppet"
	end
	return "pending"
end

-- Whether the next poll should look for the character at all.
function AvatarSlot.shouldPoll(status: AttachStatus): boolean
	return status == "pending"
end

return AvatarSlot
