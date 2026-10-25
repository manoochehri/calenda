--!strict
-- Issue #85 (ground checkerboard): Studio's New Place template ships a Baseplate Part at Workspace
-- top height 0, which is the GROUND layer. It is coplanar with the sidewalks, plaza and forecourt,
-- covers the ROAD_BASE slab, and shows a grey checker texture. The repo's runbook asks for an empty
-- place, but a place made from the template still has it. WorldBuilder removes it before building.
-- These cases pin the predicate that decides what counts as the stray template Baseplate.
local StrayBaseplate = require("../src/shared/StrayBaseplate")

local function expectTrue(value: boolean, what: string)
	if value ~= true then
		error(`expected true: {what}`, 2)
	end
end

local function expectFalse(value: boolean, what: string)
	if value ~= false then
		error(`expected false: {what}`, 2)
	end
end

return {
	{
		name = "the template Baseplate Part is stray",
		run = function()
			expectTrue(StrayBaseplate.isStray("Baseplate", "Part"), "Baseplate Part")
		end,
	},
	{
		name = "other Workspace children are kept",
		run = function()
			expectFalse(StrayBaseplate.isStray("CalendaWorld", "Model"), "project model")
			expectFalse(StrayBaseplate.isStray("Terrain", "Terrain"), "terrain")
			expectFalse(StrayBaseplate.isStray("SpawnLocation", "SpawnLocation"), "spawn location")
			expectFalse(StrayBaseplate.isStray("Baseplate", "Model"), "a Model named Baseplate")
			expectFalse(StrayBaseplate.isStray("BaseplateCopy", "Part"), "a differently named Part")
		end,
	},
}
