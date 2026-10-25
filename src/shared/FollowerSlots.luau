--!strict
-- Organic follower slots and embedded section bases (issue #68, spec s3 and s8). Pure.
-- The crowd is one irregular cloud behind the lead (a sunflower/golden-angle scatter with seeded
-- jitter), never rows or columns. Up to MAX_BASES section bases (puppets, globos, dancers) stand
-- INSIDE that cloud at fixed, irregular spots; the cloud keeps a clear hole around every base, whether
-- or not that section exists yet, so followers never move when a section appears or goes.
-- Slot k depends only on k, so a follower keeps its slot while others join or leave.
-- Offsets are relative to the lead, in studs: dx lateral (left negative), dz along the street
-- (negative = behind). The client mirrors dx with ViewMap.x when it draws.
local Config = require("./Config")
local DebugLayout = require("./DebugLayout")

export type Slot = { dx: number, dz: number }

local FollowerSlots = {}

FollowerSlots.CENTER_DZ = -9.5 -- [default] middle of the cloud, studs behind the lead
FollowerSlots.RADIUS_STEP = 2.6 -- [default] studs; the disc slot k draws from has radius RADIUS_STEP * sqrt(k) + 1.5
FollowerSlots.DEPTH_SCALE = 0.75 -- [default] the cloud is flatter along the street than across it
FollowerSlots.CANDIDATES = 1200 -- [default] seeded candidates tried per slot
FollowerSlots.MIN_DZ = -19 -- [default] deepest a follower stands (the camera is 24 behind the lead)
FollowerSlots.MAX_DZ = -3.5 -- [default] stays out of the lead's hitbox (Crossing.LEAD_HITBOX)
FollowerSlots.SIDEWALK_WIDTH = 6 -- mirrors WorldBuilder: the road is DebugLayout.halfWidth - 6 wide per side
FollowerSlots.FOLLOWER_MARGIN = 1.15 -- [default] follower half width (0.83) + idle sway (0.3)
FollowerSlots.BASE_FOOTPRINT = 3.0 -- [default] widest section footprint (SectionScale.footprint, tested <=)
FollowerSlots.BASE_HOLES = table.freeze({ 4.4, 3.7, 4.9, 4.4, 3.7, 4.9 }) -- scaled for each section's footprint
FollowerSlots.BASE_HOLE = 4.9 -- [default] widest reserved hole; individual bases use BASE_HOLES
-- Half width of the road the parade must stay on (followers and figures never stand on the sidewalk).
function FollowerSlots.roadHalfWidth(): number
	return DebugLayout.halfWidth - FollowerSlots.SIDEWALK_WIDTH
end
-- How far the whole cloud (followers and section footprints) may reach to either side of its centre.
-- Kept well under the road half width so the cloud stays attached to the lead (see `layout`).
FollowerSlots.CROWD_REACH = 10 -- [default] studs, not counting the wider section footprints
FollowerSlots.REACH = 10.4 -- [default] studs including the widest section footprint
FollowerSlots.MIN_WIDTH = 0.9 -- [default] the cloud is squeezed to at most this share near the road edge
FollowerSlots.MAX_DX = FollowerSlots.CROWD_REACH - FollowerSlots.FOLLOWER_MARGIN -- widest a follower stands
FollowerSlots.MAX_BASES = 6 -- spec s8: at most 6 section representatives

-- Section bases, in the order sections form (puppet, globo, dancers, puppet, globo, dancers).
-- Irregular on purpose: a loose V and scatter, staggered in depth, no two in a row or column.
FollowerSlots.BASES = table.freeze({
	table.freeze({ dx = -5, dz = -10.3 }),
	table.freeze({ dx = -0.5, dz = -12.5 }),
	table.freeze({ dx = 4, dz = -9.9 }),
	table.freeze({ dx = -4.4, dz = -16.5 }),
	table.freeze({ dx = 0.9, dz = -16.8 }),
	table.freeze({ dx = 5.5, dz = -16.2 }),
})

-- Deterministic unit float in [0, 1) from an integer and a salt (xorshift on 32 bits).
function FollowerSlots.unit(i: number, salt: number): number
	local x = bit32.bxor(
		bit32.band(math.floor(i) * 747796405 + salt * 2891336453, 0xFFFFFFFF),
		0x9E3779B9
	)
	for _ = 1, 2 do
		x = bit32.bxor(x, bit32.lshift(x, 13))
		x = bit32.bxor(x, bit32.rshift(x, 17))
		x = bit32.bxor(x, bit32.lshift(x, 5))
	end
	return x / 4294967296
end

local function nearBase(dx: number, dz: number): boolean
	for i, b in FollowerSlots.BASES do
		local hole = FollowerSlots.BASE_HOLES[i]
		if (dx - b.dx) ^ 2 + (dz - b.dz) ^ 2 < hole * hole then
			return true
		end
	end
	return false
end

-- Best-candidate scatter: slot k takes the seeded candidate (inside a disc that grows with k, in
-- bounds, clear of every base) farthest from the slots already placed. Even and organic, never a
-- grid, and slot k never depends on how many slots come after it.
local function build(): { Slot }
	local out: { Slot } = {
		table.freeze({ dx = -8.5, dz = FollowerSlots.MAX_DZ }),
		table.freeze({ dx = 8.5, dz = FollowerSlots.MAX_DZ }),
	}
	for k = 3, Config.visualBudget.looseAvatars do
		local best: Slot? = nil
		local bestGap = -1
		local reach = FollowerSlots.RADIUS_STEP * math.sqrt(k) + 4
		for c = 1, FollowerSlots.CANDIDATES * 3 do
			if c == FollowerSlots.CANDIDATES + 1 and best ~= nil then
				break
			elseif c > FollowerSlots.CANDIDATES and (c - 1) % FollowerSlots.CANDIDATES == 0 then
				reach *= 1.6 -- nothing fit: search a wider disc
			end
			local rad = reach * math.sqrt(FollowerSlots.unit(k * 977 + c, 3))
			local a = FollowerSlots.unit(k * 977 + c, 4) * math.pi * 2
			local dx = math.cos(a) * rad
			local dz = FollowerSlots.CENTER_DZ + math.sin(a) * rad * FollowerSlots.DEPTH_SCALE
			if
				math.abs(dx) <= FollowerSlots.MAX_DX
				and dz >= FollowerSlots.MIN_DZ
				and dz <= FollowerSlots.MAX_DZ
				and not nearBase(dx, dz)
			then
				local gap = math.huge
				for _, o in out do
					gap = math.min(gap, (o.dx - dx) ^ 2 + (o.dz - dz) ^ 2)
				end
				if gap > bestGap then
					best, bestGap = table.freeze({ dx = dx, dz = dz }), gap
				end
			end
		end
		table.insert(out, best or table.freeze({ dx = 0, dz = FollowerSlots.CENTER_DZ }))
	end
	return out
end

local SLOTS = build()

-- Slot of follower index k (1-based). `density` is accepted for call compatibility and ignored:
-- slots never move when sections form.
function FollowerSlots.slot(index: number, _density: number?): Slot
	if type(index) ~= "number" or index ~= math.floor(index) or index < 1 then
		error(`slot index must be a positive integer, got {tostring(index)}`, 2)
	end
	local s = SLOTS[index]
	if s == nil then
		error(`slot index {index} is over the loose avatar budget`, 2)
	end
	return s
end

-- Where section representative `index` (1-based, <= MAX_BASES) stands.
function FollowerSlots.base(index: number): Slot
	local b = FollowerSlots.BASES[index]
	if b == nil then
		error(`section base {tostring(index)} out of range`, 2)
	end
	return b
end

function FollowerSlots.baseHole(index: number): number
	if
		type(index) ~= "number"
		or index ~= math.floor(index)
		or index < 1
		or index > #FollowerSlots.BASE_HOLES
	then
		error(
			`base hole index must be between 1 and {#FollowerSlots.BASE_HOLES}, got {tostring(index)}`,
			2
		)
	end
	return FollowerSlots.BASE_HOLES[index]
end

-- Lowest slot index not in `taken` (a set).
function FollowerSlots.lowestFree(taken: { [number]: boolean }): number
	local k = 1
	while taken[k] do
		k += 1
	end
	return k
end

-- How many slots exist: the visual budget's loose avatar cap (spec s8).
function FollowerSlots.capacity(): number
	return #SLOTS
end

-- The cloud follows the lead until it nears a road edge; then it squeezes horizontally to preserve
-- the follower and section footprints while keeping the whole crowd on the road.
function FollowerSlots.layout(leadX: number): (number, number)
	local road = FollowerSlots.roadHalfWidth()
	local margin = FollowerSlots.BASE_FOOTPRINT
	local span = FollowerSlots.REACH - margin
	local limit = road - margin - FollowerSlots.MIN_WIDTH * span
	local c = math.clamp(leadX, -limit, limit)
	return c, math.min(1, (road - margin - math.abs(c)) / span)
end

function FollowerSlots.worldX(leadX: number, dx: number): number
	local c, w = FollowerSlots.layout(leadX)
	return c + w * dx
end

return FollowerSlots
