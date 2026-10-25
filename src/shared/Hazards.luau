--!strict
-- Level hazards (issue #96). Pure: no Roblox APIs, Lune-tested.
--
-- A level lists the hazard kinds it uses (Level.Layout.hazardSet). The server draws the concrete
-- schedule from the run seed, so the same seed gives the same hazards and nothing is chosen by the
-- client. Two kinds exist so far:
--  * "tomato": thrown from a building side. Warned TOMATO_WARNING s ahead. Only a landed gift
--    shot inside the warning window blocks it; a note does not. Unblocked, it hits a lead standing
--    in its lane and costs Config.hazards.tomatoLoss followers, once.
--  * "cart": a tlayuda cart across the street with one clear gap. Warned CART_WARNING s ahead.
--    The lead must be in the gap when it passes; a collision costs the existing obstacle loss,
--    once.
-- [default] values are tuning defaults; the issue names no numbers.
local Crossing = require("./Crossing")
local Steering = require("./Steering")

local Hazards = {}

export type Kind = "tomato" | "cart"
export type Set = {
	kinds: { string },
	firstAt: number, -- run seconds: earliest impact
	lastAt: number, -- run seconds: no impact after this
	minGap: number, -- seconds between hazards, lower bound
	maxGap: number, -- seconds between hazards, upper bound
}
-- x: tomato landing lane, or the cart's gap centre. z: cart position along the street.
export type Hazard = {
	id: number,
	kind: Kind,
	warnAt: number,
	impactAt: number,
	x: number,
	z: number?,
	side: ("left" | "right")?, -- tomato: the building side that throws
}

Hazards.MIN_START = 8 -- [default] seconds; no warning before this run time
Hazards.TOMATO_WARNING = 2.5 -- [default] seconds of warning before a tomato lands
Hazards.CART_WARNING = 2.0 -- [default] seconds of warning before the cart reaches the lead
Hazards.TOMATO_HALF_WIDTH = 2.5 -- [default] studs: lead half width 1.5 plus tomato radius 1.0
Hazards.CART_HALF_DEPTH = 3 -- [default] studs along the street the cart occupies
Hazards.CART_CLEAR_WIDTH = 4.5 -- [default] studs of clear gap; the lead needs 3

local KNOWN: { [string]: boolean } = { tomato = true, cart = true }

-- Park-Miller minimal standard generator. Integer-exact in doubles, so reproducible on any host.
function Hazards.rng(seed: number): () -> number
	assert(
		type(seed) == "number" and seed == seed and math.abs(seed) < math.huge,
		"finite seed required"
	)
	local state = math.floor(math.abs(seed)) % 2147483646 + 1
	return function(): number
		state = (state * 16807) % 2147483647
		return (state - 1) / 2147483646
	end
end

-- The concrete schedule for one run, in impact order. Empty when the level has no hazard set.
function Hazards.schedule(set: Set?, seed: number, halfWidth: number, speed: number): { Hazard }
	local out: { Hazard } = {}
	if set == nil or #set.kinds == 0 then
		return out
	end
	for _, k in set.kinds do
		assert(KNOWN[k] == true, `unknown hazard kind {k}`)
	end
	assert(set.minGap > 0 and set.maxGap >= set.minGap, "hazard gaps must be positive and ordered")
	local rng = Hazards.rng(seed)
	local bound = Steering.bound(halfWidth)
	local t = math.max(set.firstAt, Hazards.MIN_START + Hazards.TOMATO_WARNING)
	local id = 0
	while t <= set.lastAt do
		local kind = set.kinds[math.floor(rng() * #set.kinds) + 1]
		id += 1
		if kind == "tomato" then
			local side = if rng() < 0.5 then "left" else "right"
			local lane = (0.2 + 0.8 * rng()) * bound
			table.insert(out, {
				id = id,
				kind = "tomato",
				warnAt = t - Hazards.TOMATO_WARNING,
				impactAt = t,
				x = if side == "left" then -lane else lane,
				side = side,
			})
		else
			table.insert(out, {
				id = id,
				kind = "cart",
				warnAt = t - Hazards.CART_WARNING,
				impactAt = t,
				x = (2 * rng() - 1) * bound,
				z = speed * t,
			})
		end
		t += set.minGap + rng() * (set.maxGap - set.minGap)
	end
	return out
end

-- A tomato hits when the lead's centre is within the lane band at impact.
function Hazards.tomatoHit(h: Hazard, leadX: number): boolean
	return math.abs(leadX - h.x) <= Hazards.TOMATO_HALF_WIDTH
end

-- The lead's hitbox swept from (z0, x0) to (z1, x1) overlaps a blocked band of the cart.
-- Blocked: everything across the street except the clear gap centred on h.x.
function Hazards.cartHit(
	h: Hazard,
	z0: number,
	z1: number,
	x0: number,
	x1: number,
	halfWidth: number
): boolean
	local cz = h.z or 0
	local hb = Crossing.LEAD_HITBOX
	local zMin, zMax = math.min(z0, z1) - hb.halfDepth, math.max(z0, z1) + hb.halfDepth
	if not (zMin < cz + Hazards.CART_HALF_DEPTH and zMax > cz - Hazards.CART_HALF_DEPTH) then
		return false
	end
	local xMin, xMax = math.min(x0, x1) - hb.halfWidth, math.max(x0, x1) + hb.halfWidth
	local gapLeft = h.x - Hazards.CART_CLEAR_WIDTH / 2
	local gapRight = h.x + Hazards.CART_CLEAR_WIDTH / 2
	-- Blocked bands: [-halfWidth, gapLeft] and [gapRight, halfWidth].
	local leftBand = xMin < gapLeft and xMax > -halfWidth
	local rightBand = xMax > gapRight and xMin < halfWidth
	return leftBand or rightBand
end

return Hazards
