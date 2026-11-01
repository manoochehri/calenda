--!strict
-- Issue #171 / #236 (road flashing). ClusterView's per-frame shot loop used to set every shot's
-- body and extras to Parent = nil and then back to the folder on every frame. The body anchors a
-- Neon Trail (LightEmission = 1); taking its attachments out of the DataModel each frame resets the
-- trail history, so a fresh streak is drawn from nothing every frame across the road. A shown shot
-- must stay parented; it is hidden only on the frame it goes. These are source checks (the Roblox
-- Trail cannot run headlessly): they fail on the code before the fix. On-device look is UNVERIFIED.
local fs = require("@lune/fs")

local function loopSource(): string
	local text = fs.readFile("src/client/ClusterView.luau")
	local a = string.find(text, "local ps = projectilePool:setCount(#live)", 1, true)
	assert(a ~= nil, "marker not found: projectile loop start")
	local b = string.find(text, "-- Muzzle pops at the lead", a, true)
	assert(b ~= nil, "marker not found: projectile loop end")
	return string.sub(text, a, b - 1)
end

return {
	{
		name = "issue 171: a shown shot is not detached before it is drawn each frame",
		run = function()
			local loop = loopSource()
			local goneAt = string.find(loop, "if gone then", 1, true)
			assert(goneAt ~= nil, "projectile loop lost its `if gone` branch")
			local before = string.sub(loop, 1, goneAt - 1)
			assert(
				string.find(before, "Parent = nil", 1, true) == nil,
				"shot parts are set to Parent = nil every frame before the gone check (Trail history reset)"
			)
		end,
	},
	{
		name = "issue 171: a shot part is re-parented only when it is not already in the folder",
		run = function()
			local loop = loopSource()
			assert(
				string.find(loop, "if part.Parent ~= folder then", 1, true) ~= nil,
				"shot parts are re-parented unconditionally every frame"
			)
		end,
	},
}
