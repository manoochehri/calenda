--!strict
-- Level of detail for spectator MOBS (issue #65). A cluster is still one cluster (id, type,
-- reward, hits, path); its mob is DECORATION derived on the client: hundreds to thousands of
-- spectators drawn as a few real figures near the camera plus particle swarms for the rest.
-- Pure and reusable: the ambient street crowds of #54 phase 2 use the same functions.
-- Display only: nothing here decides a hit, a credit, damage or a total.
local QualityConfig = require("./QualityConfig")

local MobLod = {}

MobLod.MOB_PER_REWARD = 60 -- [default] spectators represented per reward point (small 5 -> 300)
MobLod.MIN_MOB = 40 -- [default] never fewer
MobLod.NEAR_FRACTION = 0.02 -- [default] a figure this share of screen height or more: all figures
MobLod.FAR_FRACTION = 0.011 -- [default] this share or less: all particles
MobLod.LIFETIME = 0.7 -- [default] seconds a swarm particle lives
MobLod.WIDTH_BASE = 4 -- [default] studs, footprint width of a tiny mob
MobLod.WIDTH_PER_ROOT = 0.35 -- [default] studs of width per sqrt(spectator)
MobLod.DEPTH_RATIO = 1.1 -- [default] footprint depth / width
MobLod.MAX_WIDTH = 20 -- [default] studs
MobLod.ADMIT_RATE = 3 -- [default] fade per second when a mob is admitted or released (no pop)
MobLod.STREET_LIMIT_X = 21.5 -- [default] studs; no figure reaches past |x| (facades start at 28, flags 23.5)
MobLod.FIGURE_HALF = 0.6 -- studs, half the width of a figure

-- Spectators the mob represents. Grows with reward and the quality level; hard-capped.
function MobLod.mobSize(reward: number, quality: any): number
	local level = QualityConfig.get(quality)
	local r = if type(reward) == "number" and reward == reward then math.max(0, reward) else 0
	local raw = math.floor(r * MobLod.MOB_PER_REWARD * level.mobScale)
	return math.clamp(raw, math.min(MobLod.MIN_MOB, level.maxMobSize), level.maxMobSize)
end

-- Footprint (width, depth) in studs of a mob of `size` spectators.
function MobLod.footprint(size: number): (number, number)
	local w =
		math.min(MobLod.MAX_WIDTH, MobLod.WIDTH_BASE + MobLod.WIDTH_PER_ROOT * math.sqrt(size))
	return w, w * MobLod.DEPTH_RATIO
end

-- Share (0..1) of the mob drawn as real figures, from the screen share a figure takes.
function MobLod.nearWeight(figureScreenFraction: number): number
	local lo, hi = MobLod.FAR_FRACTION, MobLod.NEAR_FRACTION
	local x = math.clamp((figureScreenFraction - lo) / (hi - lo), 0, 1)
	return x * x * (3 - 2 * x)
end

export type Split = { figures: number, dots: number }

-- Figures + particles for one mob. Spectators not drawn as figures are particles, so the
-- represented density stays constant through the crossfade (until a cap clips it).
function MobLod.split(size: number, nearWeight: number, quality: any): Split
	local level = QualityConfig.get(quality)
	local figures = math.floor(math.min(size, level.maxFiguresPerMob) * nearWeight)
	local dots = math.min(size - figures, level.maxDots)
	return { figures = figures, dots = math.max(0, dots) }
end

export type MobIn = { size: number, nearWeight: number, fade: number }
export type MobOut = { figures: number, dots: number, rate: number, drawn: boolean }

-- Share out the global caps. `mobs` MUST be sorted nearest first. Mobs past maxMobs are not drawn;
-- figures and dots are handed out nearest first until maxFigures / maxTotalDots run out. A
-- fade < 1 (still emerging at the far end) scales both down so a mob never pops.
function MobLod.allocate(mobs: { MobIn }, quality: any): { MobOut }
	local level = QualityConfig.get(quality)
	local out: { MobOut } = {}
	local figuresLeft, dotsLeft = level.maxFigures, level.maxTotalDots
	for i, m in mobs do
		if i > level.maxMobs then
			out[i] = { figures = 0, dots = 0, rate = 0, drawn = false }
			continue
		end
		local s = MobLod.split(m.size, m.nearWeight, quality)
		local f = math.min(s.figures, figuresLeft)
		-- spectators a clipped figure budget could not show fall back to particles
		local d = math.min(s.dots + (s.figures - f), level.maxDots, dotsLeft)
		d = math.floor(d * math.clamp(m.fade, 0, 1))
		f = math.floor(f * math.clamp(m.fade, 0, 1))
		figuresLeft -= f
		dotsLeft -= d
		out[i] = { figures = f, dots = d, rate = MobLod.rate(d), drawn = true }
	end
	return out
end

-- ParticleEmitter Rate for `dots` live particles: "Number of particles = Rate * Lifetime"
-- (Roblox ParticleEmitter docs), so Rate = dots / Lifetime.
function MobLod.rate(dots: number): number
	return dots / MobLod.LIFETIME
end

-- Emitters in use for `n` drawn mobs: one swarm each plus dust on the nearest maxDust.
function MobLod.emitterCount(drawnMobs: number, quality: any): number
	local level = QualityConfig.get(quality)
	local n = math.min(drawnMobs, level.maxMobs)
	return n + math.min(n, level.maxDust)
end

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
