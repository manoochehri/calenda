--!strict
-- Pure server-side crossing and overlap detection (issue #8, spec s6, s9). The server decides
-- what the lead touched from the layout and its own positions; no client claim is involved.
-- Coordinates follow Level: z along the street (+z forward), x lateral (negative = left).
local LaneGeometry = require("./LaneGeometry")
local Level = require("./Level")

local Crossing = {}

-- The lead's fixed hitbox (spec s9): decorative parade size never enlarges it.
Crossing.LEAD_HITBOX = table.freeze({ halfWidth = 1.5, halfDepth = 1.0 }) -- [default] studs
-- A closed streetwork lane fills its half of the street from the kerb to the centre line.
Crossing.OBSTACLE_HALF_DEPTH = 1.5 -- [default] studs along the street

local function isFinite(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- Gates whose plane the lead passed this tick (z0 < gate.z <= z1), in (z, id) order.
-- A pair is evaluated once by RunState; this only reports which planes were passed.
function Crossing.gatesCrossed(layout: Level.Layout, z0: any, z1: any): { Level.Gate }
	local out: { Level.Gate } = {}
	if not isFinite(z0) or not isFinite(z1) then
		return out
	end
	for _, g in layout.gates do
		if g.z > z0 and g.z <= z1 then
			table.insert(out, g)
		end
	end
	table.sort(out, function(a, b)
		if a.z ~= b.z then
			return a.z < b.z
		end
		return a.id < b.id
	end)
	return out
end

-- Obstacles the lead's hitbox overlapped while moving from (x0, z0) to (x1, z1) this tick.
-- The hitbox is swept, so a long step cannot tunnel through an obstacle. In (z, id) order.
function Crossing.obstaclesHit(
	layout: Level.Layout,
	z0: any,
	z1: any,
	x0: any,
	x1: any
): { Level.Obstacle }
	local out: { Level.Obstacle } = {}
	if not (isFinite(z0) and isFinite(z1) and isFinite(x0) and isFinite(x1)) then
		return out
	end
	local hb = Crossing.LEAD_HITBOX
	local zMin, zMax = math.min(z0, z1) - hb.halfDepth, math.max(z0, z1) + hb.halfDepth
	local xMin, xMax = math.min(x0, x1) - hb.halfWidth, math.max(x0, x1) + hb.halfWidth
	for _, o in layout.obstacles do
		local lo, hi =
			if o.side == "left" then -layout.halfWidth else 0,
			if o.side == "left" then 0 else layout.halfWidth
		local depthOk = zMin < o.z + Crossing.OBSTACLE_HALF_DEPTH
			and zMax > o.z - Crossing.OBSTACLE_HALF_DEPTH
		if depthOk and xMin < hi and xMax > lo then
			table.insert(out, o)
		end
	end
	table.sort(out, function(a, b)
		if a.z ~= b.z then
			return a.z < b.z
		end
		return a.id < b.id
	end)
	return out
end

-- Pickups whose distance plane the lead crossed this tick and whose lane the lead occupied there
-- (ADR 0010, Amendment 9). The plane is crossed when z0 < pickup.z <= z1, which also requires forward
-- progress, so stationary lateral movement cannot collect one. The lead's x at the crossing is
-- interpolated linearly between x0 and x1. Passing in another lane returns nothing: the pickup
-- expires with no reward or loss. In (z, id) order.
function Crossing.pickupsAwarded(
	layout: Level.Layout,
	z0: any,
	z1: any,
	x0: any,
	x1: any
): { Level.Pickup }
	local out: { Level.Pickup } = {}
	if not (isFinite(z0) and isFinite(z1) and isFinite(x0) and isFinite(x1)) then
		return out
	end
	local list = layout.pickups or {}
	for _, p in list do
		if z0 < p.z and p.z <= z1 then
			local f = (p.z - z0) / (z1 - z0)
			local xAt = x0 + (x1 - x0) * f
			if LaneGeometry.laneOf(xAt) == p.lane then
				table.insert(out, p)
			end
		end
	end
	table.sort(out, function(a, b)
		if a.z ~= b.z then
			return a.z < b.z
		end
		return a.id < b.id
	end)
	return out
end

return Crossing
