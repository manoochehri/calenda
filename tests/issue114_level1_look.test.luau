--!strict
-- Issue #114 (Level 1 look, part 2): pure sizing checks behind the presentation changes.
-- Presentation itself is UNVERIFIED until a Studio checklist is run. The section cropping item is
-- NOT covered here: see the PR (it conflicts with the #68 spacing and sight-line tests).
local CameraRig = require("../src/shared/CameraRig")
local FollowerLook = require("../src/shared/FollowerLook")
local FollowerSlots = require("../src/shared/FollowerSlots")
local LeadPose = require("../src/shared/LeadPose")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function rgbKey(c: { number }): string
	return `{c[1]},{c[2]},{c[3]}`
end

return {
	{
		name = "issue 114: the lead ring is wider than before (diameter at least 10) and fits the road",
		run = function()
			local diameter = LeadPose.RING_DIAMETER
			assert(type(diameter) == "number", "LeadPose.RING_DIAMETER must be a number")
			assert(diameter >= 10, `ring diameter {diameter} must be at least 10 (was 8)`)
			assert(
				diameter / 2 <= FollowerSlots.roadHalfWidth(),
				`ring radius {diameter / 2} must fit the road half width {FollowerSlots.roadHalfWidth()}`
			)
		end,
	},
	{
		name = "issue 114: the lead avatar is scaled up, and its scaled height is still under the camera's lead hat height",
		run = function()
			local scale = LeadPose.AVATAR_SCALE
			assert(type(scale) == "number", "LeadPose.AVATAR_SCALE must be a number")
			assert(scale >= 1.15, `lead scale {scale} must be at least 1.15`)
			-- DEFAULT_AVATAR_HEIGHT: a standing default R15 avatar, about 5 studs. UNVERIFIED in Studio.
			local scaled = LeadPose.DEFAULT_AVATAR_HEIGHT * scale
			assert(
				scaled <= CameraRig.LEAD_TOP,
				`scaled lead {scaled} studs tall must stay under CameraRig.LEAD_TOP {CameraRig.LEAD_TOP}`
			)
			assert(scaled <= LeadPose.AVATAR_TOP, "scaled lead must stay under AVATAR_TOP")
		end,
	},
	{
		name = "issue 114: a follower has one dominant costume colour (body and skirt match), a skin-tone head, and at most three colours",
		run = function()
			local tints = FollowerLook.tints
			assert(type(tints) == "function", "FollowerLook.tints must exist")
			for id = 1, 200 do
				local t = tints(FollowerLook.of(id))
				assert(
					rgbKey(t.body) == rgbKey(t.skirt),
					`follower {id}: body and skirt must share the dominant costume colour`
				)
				eq(rgbKey(t.head), rgbKey(FollowerLook.SKIN), `follower {id} head is skin tone`)
				local seen: { [string]: boolean } = {}
				for _, k in { "body", "skirt", "head", "accent" } do
					seen[rgbKey((t :: any)[k])] = true
				end
				local n = 0
				for _ in seen do
					n += 1
				end
				assert(n <= 3, `follower {id} shows {n} colours; at most 3 (costume, skin, accent)`)
			end
		end,
	},
	{
		name = "issue 114: a follower is built from at most five pieces, no arms",
		run = function()
			local pieces = FollowerLook.PIECES
			assert(type(pieces) == "table", "FollowerLook.PIECES must exist")
			assert(#pieces <= 5, `a follower has {#pieces} pieces; at most 5`)
			for _, p in pieces do
				assert(p ~= "armL" and p ~= "armR", "arms are dropped from the follower silhouette")
			end
		end,
	},
}
