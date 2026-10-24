--!strict
-- Pure per-type facts about sections (issue #14, spec s7, s8). Only the puppet is described now;
-- globo and dancers register here when issues #19 and #20 land.
local SectionRegistry = require("./SectionRegistry")

export type Descriptor = {
	entourage: number, -- decorative companions drawn beside one representative
	addsFollowers: boolean, -- always false: entourages are decoration (spec s8)
}

local descriptors = SectionRegistry.new() :: SectionRegistry.Registry<Descriptor>
descriptors:register("puppet", { entourage = 3, addsFollowers = false }) -- [default] spec: "small"

return {
	descriptors = descriptors,
}
