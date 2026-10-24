--!strict
-- Presentation plan for the server's "obstacle" Event (issue #15, spec s9). Pure. The server
-- already applied the loss exactly once (RunState); this decides what to PLAY, and plays it
-- once per obstacle per run: a second event for the same obstacle returns nil. No injury
-- visuals: dust and rubble at the obstacle, and a few followers hop to the sidewalk to cheer.
-- The new total reaches the HUD through State as before.
local Level = require("./Level")

export type Plan = {
	id: number,
	side: "left" | "right",
	x: number, -- obstacle center (lateral)
	z: number,
	puffs: number, -- dust/rubble chunks
	peelers: number, -- followers that peel off to cheer (<= PEEL_MAX and <= followers there were)
	sidewalkX: { number }, -- one cheering spot per peeler, on the obstacle's sidewalk
	sidewalkZ: { number },
}
export type Feedback = {
	handle: (self: Feedback, payload: any) -> Plan?,
	reset: (self: Feedback) -> (),
}

local ObstacleFeedback = {}

ObstacleFeedback.PUFFS = 12 -- [default] dust/rubble chunks per hit
ObstacleFeedback.PEEL_MAX = 6 -- [default] followers peeling off per obstacle
ObstacleFeedback.SIDEWALK_WIDTH = 6 -- [default] matches WorldBuilder's sidewalk
ObstacleFeedback.PEEL_SPACING = 2.4 -- [default] studs between cheering followers along the street

function ObstacleFeedback.new(layout: Level.Layout): Feedback
	local byId: { [number]: Level.Obstacle } = {}
	for _, o in layout.obstacles do
		byId[o.id] = o
	end
	local seen: { [number]: boolean } = {}
	local self = {} :: Feedback

	function self.handle(_, payload: any): Plan?
		if type(payload) ~= "table" or payload.kind ~= "obstacle" then
			return nil
		end
		local id = payload.id
		if type(id) ~= "number" then
			return nil
		end
		local o = byId[id]
		if o == nil or seen[id] then
			return nil
		end
		seen[id] = true

		local before = payload.before
		local followers = if type(before) == "number"
				and before == before
				and before > 0
			then math.floor(before)
			else 0
		local peelers = math.min(ObstacleFeedback.PEEL_MAX, followers)
		local spotX = (layout.halfWidth - ObstacleFeedback.SIDEWALK_WIDTH / 2)
			* (if o.side == "left" then -1 else 1)
		local xs, zs = {}, {}
		for i = 1, peelers do
			xs[i] = spotX + (if o.side == "left" then 1 else -1) * ((i - 1) % 2) * 1.5
			zs[i] = o.z - 2 - (i - 1) * ObstacleFeedback.PEEL_SPACING
		end
		return {
			id = id,
			side = o.side,
			x = if o.side == "left" then -layout.halfWidth * 0.85 else layout.halfWidth * 0.85,
			z = o.z,
			puffs = ObstacleFeedback.PUFFS,
			peelers = peelers,
			sidewalkX = xs,
			sidewalkZ = zs,
		}
	end

	function self.reset(_)
		seen = {}
	end

	return self
end

return ObstacleFeedback
