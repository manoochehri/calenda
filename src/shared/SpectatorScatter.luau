--!strict
-- Spectators as INDIVIDUALS (issue #65, owner direction 2026-10-25: "we want random individuals
-- coming at the player", not grouped bunches). Pure: each spectator is one figure on its own
-- spot in a loose, jittered scatter across the lane, so no two stand closer than
-- Config.spectators.scatter.minSeparation and no spectator has more than maxBunch of its
-- group within bunchRadius. Figures are capped per mob (QualityConfig.maxFiguresPerMob) and on
-- screen (QualityConfig.maxFigures, nearest mobs first). Display only: nothing here decides a
-- hit, a credit, damage or a total. Every tunable comes from Config or QualityConfig; none here.
local QualityConfig = require("./QualityConfig")

local SpectatorScatter = {}

export type Scatter = {
	perReward: number,
	spreadHalfWidth: number,
	colSpacing: number,
	rowSpacing: number,
	jitter: number,
	minSeparation: number,
	bunchRadius: number,
	maxBunch: number,
	minScreenFraction: number,
	maxScale: number,
}

export type Offset = { dx: number, dz: number }

-- Deterministic 0..1 noise (same look for the same seed; no math.random).
local function noise(i: number, salt: number): number
	local x = math.sin(i * 12.9898 + salt * 78.233) * 43758.5453
	return x - math.floor(x)
end

-- Individuals one cluster shows: reward x perReward, never above the per-mob figure cap.
function SpectatorScatter.individuals(reward: number, quality: any, p: Scatter): number
	local level = QualityConfig.get(quality)
	local r = if type(reward) == "number" and reward == reward then math.max(0, reward) else 0
	return math.clamp(math.floor(r * p.perReward), 0, level.maxFiguresPerMob)
end

-- Where `count` individuals stand, relative to the mob's front (dz > 0 is behind the front; the
-- mob charges toward -z). A jittered grid across the lane: column spacing is at least colSpacing
-- and rows are rowSpacing apart, each individual moves at most `jitter` of a spacing from its
-- grid point, so neighbours never come closer than (1 - 2 * jitter) of a spacing.
function SpectatorScatter.place(count: number, seed: number, p: Scatter): { Offset }
	local out: { Offset } = {}
	if count <= 0 then
		return out
	end
	local width = 2 * p.spreadHalfWidth
	local cols = math.clamp(math.floor(width / p.colSpacing), 1, count)
	local spacingX = width / cols
	local spacingZ = p.rowSpacing
	for i = 1, count do
		local row = (i - 1) // cols
		local col = (i - 1) % cols
		local key = i + seed * 1009
		local jx = (noise(key, 1) - 0.5) * 2 * p.jitter * spacingX
		local jz = (noise(key, 2) - 0.5) * 2 * p.jitter * spacingZ
		local dx = -p.spreadHalfWidth + (col + 0.5) * spacingX + jx
		out[i] = { dx = dx, dz = row * spacingZ + jz }
	end
	return out
end

-- Depth (studs) and half-width of the scatter for `count` individuals: the footprint the mob's
-- front and the tags use.
function SpectatorScatter.extent(count: number, p: Scatter): (number, number)
	if count <= 0 then
		return 0, 0
	end
	local cols = math.clamp(math.floor(2 * p.spreadHalfWidth / p.colSpacing), 1, count)
	local rows = math.ceil(count / cols)
	return rows * p.rowSpacing, p.spreadHalfWidth
end

-- Figures shown for each mob, nearest first (`mobs` MUST be sorted nearest first). Each mob shows
-- at most its own count (capped per mob), mobs past maxMobs show none, and the total never
-- passes maxFigures. A mob still fading in (fade 0..1) shows the individuals that have started
-- to rise (see `risen`), so a mob never pops in whole.
function SpectatorScatter.allocate(
	mobs: { { count: number, fade: number } },
	quality: any
): { number }
	local level = QualityConfig.get(quality)
	local out: { number } = {}
	local left = level.maxFigures
	for i, m in mobs do
		if i > level.maxMobs then
			out[i] = 0
			continue
		end
		local want = math.min(math.max(0, math.floor(m.count)), level.maxFiguresPerMob, left)
		local f = math.clamp(m.fade, 0, 1)
		local shown = if f > 0 then math.min(want, math.ceil(want * f)) else 0
		out[i] = shown
		left -= shown
	end
	return out
end

-- Figure scale (1..maxScale) that keeps a figure readable: `frac` is its share of screen height
-- from the camera. A figure that already reads at minScreenFraction is drawn at its real size;
-- one further away (at the top of the lane) is drawn up to maxScale so it still reads.
function SpectatorScatter.legibleScale(frac: number, p: Scatter): number
	if frac <= 0 then
		return p.maxScale
	end
	return math.clamp(p.minScreenFraction / frac, 1, p.maxScale)
end

-- How far individual k (1-based) of n has risen out of the road at a mob fade (0..1): the
-- individuals rise one after another as the fade passes them, never all at once.
function SpectatorScatter.risen(k: number, n: number, fade: number): number
	return math.clamp(n * math.clamp(fade, 0, 1) - (k - 1), 0, 1)
end

return SpectatorScatter
