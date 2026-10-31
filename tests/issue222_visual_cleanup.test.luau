-- P0 visual cleanup for the owner's screenshot: no screen-edge red wash, no dark
-- floating rectangles, and rounded horde silhouettes at phone size.
local fs = require("@lune/fs")

local function source(path: string): string
	return fs.readFile(path)
end

return {
	{
		name = "issue 171/222: threat feedback does not tint the whole screen",
		run = function()
			local cluster = source("src/client/ClusterView.luau")
			assert(
				not cluster:find("CalendaThreat", 1, true),
				"red screen-edge threat overlay remains"
			)
			assert(not cluster:find("EDGE_MAX_ALPHA", 1, true), "screen-edge threat alpha remains")
		end,
	},
	{
		name = "issue 222: spectator tags do not render as unexplained dark rectangles",
		run = function()
			local cluster = source("src/client/ClusterView.luau")
			assert(
				cluster:find("back.BackgroundTransparency = 1", 1, true),
				"spectator tag backing remains an opaque rectangle"
			)
		end,
	},
	{
		name = "issue 65: horde bodies use rounded silhouettes",
		run = function()
			local mobs = source("src/client/MobView.luau")
			assert(
				mobs:find("newPart(folder, Enum.PartType.Cylinder, BODY_PART_SIZE", 1, true),
				"horde body is still a block"
			)
			assert(
				mobs:find("CFrame.Angles(0, 0, math.pi / 2)", 1, true),
				"rounded horde body is not oriented upright"
			)
		end,
	},
}
