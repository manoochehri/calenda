--!strict
-- Issue #85: the Studio New Place template's Baseplate (a Part named "Baseplate" at Workspace top 0)
-- is coplanar with the GROUND layer and hides the ROAD_BASE slab, so its checker texture z-fights
-- the street and the ground. The project never builds one; WorldBuilder removes it. Pure: no
-- Roblox APIs, so the rule is testable under Lune.
local StrayBaseplate = {}

-- True for a direct Workspace child that is the template Baseplate Part (not a Model of the same
-- name, not a project-built object).
function StrayBaseplate.isStray(name: string, className: string): boolean
	return name == "Baseplate" and className == "Part"
end

return StrayBaseplate
