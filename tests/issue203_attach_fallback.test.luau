--!strict
-- Issue #203 follow-up (reviewer suggestion on PR #205): the avatar attach runs inside a
-- RenderStepped callback, so a throw in the post-clone setup must not repeat every poll. The
-- decision is a pure seam in shared/AvatarSlot (attachNext, shouldPoll); the pcall wiring in
-- client/StartupScreen is covered only by a source-level check, which is weak evidence.
-- On-device behaviour is UNVERIFIED.
local fs = require("@lune/fs")
local okSlot, AvatarSlot = pcall(require, "../src/shared/AvatarSlot")

local function slot(): any
	assert(okSlot, `AvatarSlot failed to load: {tostring(AvatarSlot)}`)
	return AvatarSlot
end

return {
	{
		name = "attachNext: not ready keeps polling, built attaches, a throw latches to the puppet",
		run = function()
			local s = slot()
			assert(s.attachNext("pending", "notready") == "pending", "pending + notready")
			assert(s.attachNext("pending", "built") == "attached", "pending + built")
			assert(s.attachNext("pending", "threw") == "puppet", "pending + threw")
		end,
	},
	{
		name = "attachNext: a latched puppet and an attached avatar never change",
		run = function()
			local s = slot()
			for _, outcome in { "notready", "built", "threw" } do
				assert(s.attachNext("puppet", outcome) == "puppet", `puppet changed on {outcome}`)
				assert(
					s.attachNext("attached", outcome) == "attached",
					`attached changed on {outcome}`
				)
			end
		end,
	},
	{
		name = "shouldPoll: only while pending (a latched failure is not retried)",
		run = function()
			local s = slot()
			assert(s.shouldPoll("pending") == true, "shouldPoll pending")
			assert(s.shouldPoll("puppet") == false, "shouldPoll puppet")
			assert(s.shouldPoll("attached") == false, "shouldPoll attached")
		end,
	},
	{
		name = "StartupScreen guards the post-clone setup with pcall and uses the latch (source check)",
		run = function()
			local src = fs.readFile("src/client/StartupScreen.luau")
			assert(
				string.find(src, "AvatarSlot.attachNext", 1, true) ~= nil,
				"StartupScreen does not use AvatarSlot.attachNext"
			)
			assert(
				string.find(src, "AvatarSlot.shouldPoll", 1, true) ~= nil,
				"StartupScreen does not stop polling once latched"
			)
			assert(
				string.find(src, "local function build(", 1, true) ~= nil
					and string.find(src, "pcall(build", 1, true) ~= nil,
				"post-clone setup is not run under pcall"
			)
		end,
	},
}
