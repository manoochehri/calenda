--!strict
-- Visual state of the spectator clusters (issue #12, spec s4, Amendment 1). Pure: it turns the
-- layout (Level.clusterPosition over run time) plus the replicated per-shot hit counts into what
-- to draw this frame. It never credits anything: the +N and the run into the parade are visual
-- only, and a repeated or late fill event plays nothing (the first fill wins).
--
-- Phases: "walking" (meter filling, moving along its path), "cheering" (filled: group cheers in
-- place for CHEER_SECONDS while a few runners hop into the parade), "passing" (reached the parade
-- unfilled: swings out around it and disappears, no penalty visuals; the attack is issue #36's).
local Config = require("./Config")
local FeedbackMath = require("./FeedbackMath")
local Level = require("./Level")

export type Runner = { x: number, z: number, y: number }
export type View = {
	id: number,
	phase: "walking" | "cheering" | "passing",
	x: number,
	z: number,
	hits: number,
	needed: number,
	remaining: number, -- big numeral above the group
	fill: number, -- 0..1 meter bar
	reward: number, -- "+N" shown small beside the numeral
	members: number, -- spectators to draw in the group
	runners: { Runner }, -- spectators running into the parade (cheering phase only)
}
export type ShotResult =
	{ accepted: boolean, filled: boolean, reward: number?, x: number, z: number }
export type Tracker = {
	shot: (self: Tracker, s: { id: number, hits: number, shot: string }, t: number) -> ShotResult,
	views: (self: Tracker, t: number, leadX: number, leadZ: number) -> { View },
	reset: (self: Tracker) -> (),
}

local ClusterVisual = {}

ClusterVisual.MEMBERS = { small = 5, large = 9 } -- [default] drawn spectators per group
ClusterVisual.MAX_MEMBERS = 12 -- [default] bound on any group
ClusterVisual.MAX_VISIBLE_CLUSTERS = 8 -- [default] bound on groups drawn at once
ClusterVisual.RUNNERS = 3 -- [default] "a few" spectators run into the parade
ClusterVisual.RUN_SECONDS = 0.9 -- [default]
ClusterVisual.CHEER_SECONDS = 2 -- [default]
ClusterVisual.PASS_DISTANCE = 24 -- [default] studs past the lead before an unfilled group is gone
ClusterVisual.PASS_SWING = 8 -- [default] studs a passing group swings outward

ClusterVisual.PER_ROW = 4 -- [default] spectators per row in a dense group
ClusterVisual.SPACING = 1.7 -- [default] studs between spectators

-- Dense, centered grid offset of member i (1-based) of n, relative to the group position.
function ClusterVisual.memberOffset(i: number, n: number): (number, number)
	local row = (i - 1) // ClusterVisual.PER_ROW
	local col = (i - 1) % ClusterVisual.PER_ROW
	local inRow = math.min(ClusterVisual.PER_ROW, n - row * ClusterVisual.PER_ROW)
	local rows = math.ceil(n / ClusterVisual.PER_ROW)
	return (col - (inRow - 1) / 2) * ClusterVisual.SPACING,
		(row - (rows - 1) / 2) * ClusterVisual.SPACING
end

function ClusterVisual.new(layout: Level.Layout, config: any?): Tracker
	local cfg = config or Config
	local byId: { [number]: Level.Cluster } = {}
	local order: { Level.Cluster } = {}
	for _, c in layout.clusters do
		byId[c.id] = c
		table.insert(order, c)
	end
	table.sort(order, function(a, b)
		return a.id < b.id
	end)

	local hits: { [number]: number } = {}
	local filledAt: { [number]: number } = {}
	local self = {} :: Tracker

	local function needed(c: Level.Cluster): number
		return cfg.clusterTypes[c.type].hits
	end

	function self.shot(_, s, t): ShotResult
		local c = byId[s.id]
		if c == nil or type(t) ~= "number" or t ~= t or t < 0 then
			return { accepted = false, filled = false, x = 0, z = 0 }
		end
		local need = needed(c)
		-- Replicated counts only ever raise the meter, so a late or duplicate event is harmless.
		hits[s.id] = math.min(need, math.max(hits[s.id] or 0, s.hits))
		local firstFill = false
		if hits[s.id] >= need and filledAt[s.id] == nil then
			filledAt[s.id] = t
			firstFill = true
		end
		local at =
			Level.clusterPosition(layout, s.id, if filledAt[s.id] then filledAt[s.id] else t, cfg)
		return {
			accepted = true,
			filled = firstFill,
			reward = if firstFill then cfg.clusterTypes[c.type].reward else nil,
			x = at.x,
			z = at.z,
		}
	end

	function self.views(_, t, leadX, leadZ): { View }
		local out: { View } = {}
		for _, c in order do
			if t >= c.spawnTime and #out < ClusterVisual.MAX_VISIBLE_CLUSTERS then
				local need = needed(c)
				local h = hits[c.id] or 0
				local members =
					math.min(ClusterVisual.MAX_MEMBERS, ClusterVisual.MEMBERS[c.type] or 5)
				local view: View = {
					id = c.id,
					phase = "walking",
					x = 0,
					z = 0,
					hits = h,
					needed = need,
					remaining = math.max(0, need - h),
					fill = FeedbackMath.meterFraction(h, need),
					reward = cfg.clusterTypes[c.type].reward,
					members = members,
					runners = {},
				}
				local visible = true
				local tf = filledAt[c.id]
				if tf ~= nil then
					local p = Level.clusterPosition(layout, c.id, tf, cfg)
					view.phase, view.x, view.z = "cheering", p.x, p.z
					local since = t - tf
					if since > ClusterVisual.CHEER_SECONDS then
						visible = false
					elseif since < ClusterVisual.RUN_SECONDS then
						local f = since / ClusterVisual.RUN_SECONDS
						for i = 1, math.min(ClusterVisual.RUNNERS, members) do
							local ox = (i - (ClusterVisual.RUNNERS + 1) / 2) * 1.6
							local rx, rz, ry =
								FeedbackMath.run(p.x + ox, p.z, leadX + ox * 0.5, leadZ, f)
							table.insert(view.runners, { x = rx, z = rz, y = ry })
						end
					end
				else
					local p = Level.clusterPosition(layout, c.id, t, cfg)
					view.x, view.z = p.x, p.z
					local past = leadZ - p.z
					if past >= 0 then
						if past > ClusterVisual.PASS_DISTANCE then
							visible = false
						else
							view.phase = "passing"
							local side = if p.x < 0 then -1 else 1
							view.x = p.x
								+ side
									* ClusterVisual.PASS_SWING
									* (past / ClusterVisual.PASS_DISTANCE)
						end
					end
				end
				if visible then
					table.insert(out, view)
				end
			end
		end
		return out
	end

	function self.reset(_)
		hits = {}
		filledAt = {}
	end

	return self
end

return ClusterVisual
