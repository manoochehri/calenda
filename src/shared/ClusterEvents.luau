--!strict
-- Client-side limits for the display-only "cluster" and "attack" Events (issue #60, #50). The
-- server already caps events per tick (RunDriver.MAX_CLUSTER_EVENTS_PER_TICK); these are defense
-- in depth so a flood or a duplicate costs the client almost nothing. Pure.
local ClusterEvents = {}

ClusterEvents.EVENTS_PER_FRAME = 8 -- [default] cluster events handled per rendered frame
ClusterEvents.ATTACKS_PER_FRAME = 4 -- [default] attack reactions per rendered frame
ClusterEvents.MAX_TRACKED = 256 -- [default] ids the attack dedupe remembers

export type Budget = {
	take: (self: Budget) -> boolean,
	newFrame: (self: Budget) -> (),
}

-- A per-frame allowance: `take` is true up to `limit` times until `newFrame`.
function ClusterEvents.budget(limit: number): Budget
	local left = math.max(0, limit)
	local self = {} :: Budget
	function self.take(_): boolean
		if left <= 0 then
			return false
		end
		left -= 1
		return true
	end
	function self.newFrame(_)
		left = math.max(0, limit)
	end
	return self
end

-- What to do with a decoded shot. `accepted`: the tracker knows this cluster; `alreadyFilled`:
-- it was filled before this shot (a duplicate event); `visible`: the cluster is still drawn.
-- "launch" draws a projectile; "skip" and "drop" draw nothing (skip = duplicate, drop = orphan:
-- a hidden part must never take a pool slot).
function ClusterEvents.shotAction(
	accepted: boolean,
	alreadyFilled: boolean,
	visible: boolean
): string
	if not accepted or not visible then
		return "drop"
	end
	if alreadyFilled then
		return "skip"
	end
	return "launch"
end

export type PlanInput = {
	accepted: boolean,
	alreadyFilled: boolean,
	filled: boolean, -- this shot was the cluster's first fill
	reward: number?,
	visible: boolean, -- the cluster's position is known (it is drawn)
	inBudget: boolean, -- this frame's visual budget still had room
}
export type Plan = { track: boolean, projectile: boolean, float: boolean }

-- What to do with a cluster event. The tracker is ALWAYS fed (counts, fill and cheer must never
-- be lost to a budget); only the projectile is gated by budget, duplicates and orphans; the +N
-- plays on the first fill whatever else was suppressed.
function ClusterEvents.plan(i: PlanInput): Plan
	return {
		track = true,
		projectile = i.inBudget
			and ClusterEvents.shotAction(i.accepted, i.alreadyFilled, i.visible) == "launch",
		float = i.accepted and i.filled and i.reward ~= nil,
	}
end

export type Dedupe = {
	first: (self: Dedupe, id: number?) -> boolean,
	reset: (self: Dedupe) -> (),
	size: (self: Dedupe) -> number,
}

-- True the first time an id is seen. Events without an id always pass; once full, the memory is
-- cleared rather than grown.
function ClusterEvents.dedupe(): Dedupe
	local seen: { [number]: boolean } = {}
	local n = 0
	local self = {} :: Dedupe
	function self.first(_, id: number?): boolean
		if id == nil then
			return true
		end
		if seen[id] then
			return false
		end
		if n >= ClusterEvents.MAX_TRACKED then
			seen, n = {}, 0
		end
		seen[id] = true
		n += 1
		return true
	end
	function self.reset(_)
		seen, n = {}, 0
	end
	function self.size(_): number
		return n
	end
	return self
end

return ClusterEvents
