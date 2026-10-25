--!strict
-- The run's play order (issue #128). Pure: maps Config.levelPlayOrder ids onto authored layouts.
-- The server supplies the catalog (id -> layout); this module only looks ids up, so no level name
-- is checked in code. A bad order is an authoring error and is raised, never silently skipped.
local Level = require("./Level")

local LevelChain = {}

-- Returns the layouts in play order. Errors on an empty order, a non-id entry, a repeated id, or
-- an id the catalog does not hold.
function LevelChain.resolve(
	order: { string },
	catalog: { [string]: Level.Layout }
): { Level.Layout }
	assert(type(order) == "table" and #order > 0, "play order must not be empty")
	local seen: { [string]: boolean } = {}
	local levels: { Level.Layout } = {}
	for i, id in order do
		assert(type(id) == "string" and id ~= "", `play order entry {i} is not a level id`)
		assert(not seen[id], `play order repeats level {id}`)
		seen[id] = true
		local layout = catalog[id]
		assert(layout ~= nil, `play order names unknown level {id}`)
		table.insert(levels, layout)
	end
	return levels
end

return LevelChain
