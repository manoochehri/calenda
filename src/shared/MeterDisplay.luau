--!strict
-- The smoothed bar fill of one pooled cluster slot (issue #12). Pure. A slot is reused across
-- clusters and across replays, so the displayed fill is bound to the cluster id and cleared when
-- the slot is hidden or the run resets: a new binding snaps to its target instead of easing from
-- whatever the previous occupant showed (review round 1: the bar must start empty after a replay).
local CameraRig = require("./CameraRig")

export type Meter = {
	step: (self: Meter, id: number, target: number, dt: number, rate: number) -> number,
	clear: (self: Meter) -> (),
}

local MeterDisplay = {}

function MeterDisplay.new(): Meter
	local boundId = -1
	local shown = 0
	local self = {} :: Meter

	function self.step(_, id: number, target: number, dt: number, rate: number): number
		if id ~= boundId then
			boundId, shown = id, target
		else
			shown = CameraRig.smooth(shown, target, dt, rate)
		end
		return shown
	end

	function self.clear(_)
		boundId, shown = -1, 0
	end

	return self
end

return MeterDisplay
