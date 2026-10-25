--!strict
-- Deepest world-space trail from the lead among drawn followers and section representatives.
-- Used by GateView so a portal stays see-through until the whole parade has crossed it.
local Formation = require("./Formation")
local FollowerSlots = require("./FollowerSlots")

local ParadeTail = {}

function ParadeTail.depth(total: number): number
	local formation = Formation.forTotal(total)
	local depth = 0
	for _, slot in formation.slots do
		depth = math.max(depth, -slot.dz)
	end
	for _, slot in formation.sections do
		-- a section's figures and companions reach past its base (FollowerSlots.BASE_FOOTPRINT)
		depth = math.max(depth, -slot.dz + FollowerSlots.BASE_FOOTPRINT)
	end
	return depth
end

return ParadeTail
