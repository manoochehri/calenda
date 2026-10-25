--!strict
-- Mob presentation helpers shared by the spectator mobs (issue #65) and the ambient street crowds
-- of #54 phase 2: the street limit a mob must stay inside, and the rank-based admission that
-- keeps the number of drawn mobs under the quality cap without a pop. Display only: nothing here
-- decides a hit, a credit, damage or a total. The individual spectators themselves are
-- SpectatorScatter's; their tunables are Config.spectators.scatter and QualityConfig.
local MobLod = {}

MobLod.ADMIT_RATE = 3 -- [default] fade per second when a mob is admitted or released (no pop)
MobLod.STREET_LIMIT_X = 21.5 -- [default] studs; no figure reaches past |x| (facades start at 28, flags 23.5)
MobLod.FIGURE_HALF = 0.6 -- studs, half the width of a figure
-- Where a mob of `width` studs centred at world x `centerX` is drawn so that no figure reaches
-- past STREET_LIMIT_X: shifted toward the lane, never outward. Display only.
function MobLod.lateralFit(centerX: number, width: number): number
	local reach = math.max(0, MobLod.STREET_LIMIT_X - MobLod.FIGURE_HALF - width / 2)
	return math.clamp(centerX, -reach, reach)
end

export type Admission = {
	step: (self: Admission, ids: { number }, dt: number) -> { [number]: number },
	count: (self: Admission) -> number,
	clear: (self: Admission) -> (),
}

-- Rank-based admission under the maxMobs cap, without pops. `ids` are the live mobs nearest first.
-- A mob is admitted (fade 0, rising at ADMIT_RATE) only when a slot is free; when a nearer mob
-- arrives, the farthest occupant fades out and frees its slot only at fade 0. The state never
-- holds more than `cap` mobs, and no fade moves faster than ADMIT_RATE per second.
function MobLod.admission(cap: number): Admission
	local fades: { [number]: number } = {}
	local n = 0
	local self = {} :: Admission
	function self.step(_, ids: { number }, dt: number): { [number]: number }
		local present: { [number]: boolean } = {}
		local desired: { [number]: boolean } = {}
		for i, id in ids do
			present[id] = true
			if i <= cap then
				desired[id] = true
			end
		end
		for id in fades do
			if not present[id] then
				fades[id] = nil -- the mob is gone
				n -= 1
			end
		end
		for _, id in ids do
			if desired[id] and fades[id] == nil and n < cap then
				fades[id] = 0
				n += 1
			end
		end
		local delta = MobLod.ADMIT_RATE * math.max(0, dt)
		local out: { [number]: number } = {}
		for id, f in fades do
			local nf = if desired[id] then math.min(1, f + delta) else math.max(0, f - delta)
			if nf <= 0 and not desired[id] then
				fades[id] = nil
				n -= 1
			else
				fades[id] = nf
				out[id] = nf
			end
		end
		return out
	end
	function self.count(_): number
		return n
	end
	function self.clear(_)
		fades, n = {}, 0
	end
	return self
end

return MobLod
