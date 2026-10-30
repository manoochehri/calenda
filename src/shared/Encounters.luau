--!strict
-- Lane encounter state (issue #156, ADR 0010 item 5). Pure: no Roblox APIs.
-- Server-owned and derived: the authored layout, the lead's distance and the outcome of each
-- pickup decide what is shown. Nothing here awards a follower or consumes a target; RunState and
-- the driver do that. The snapshot carries at most ONE encounter, because a validated layout has
-- no two encounter spans that overlap (LayoutValidator, ADR 0010 item 5).
--
-- A pickup's span is the distance window before its plane: it is live once the lead is inside
-- it, and it is resolved when the lead crosses the plane (collected in its lane, missed otherwise).
local Level = require("./Level")
local Remotes = require("./Remotes")

local Encounters = {}

Encounters.SPAN = 24 -- [default] studs of approach before a pickup's plane; the active span length

export type Outcome = "collected" | "missed"
export type Encounter = Remotes.Encounter

-- [lo, hi] of a pickup's span along z. Half-open at the top in practice: hi is the plane.
function Encounters.spanOf(p: Level.Pickup): (number, number)
	return p.z - Encounters.SPAN, p.z
end

local function isFinite(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- Pickups in (z, id) order, skipping any whose z is not a finite number (LayoutValidator reports
-- those; they never form a span).
local function sortedPickups(layout: any): { Level.Pickup }
	local out: { Level.Pickup } = {}
	for _, p in layout.pickups or {} do
		if isFinite(p.z) then
			table.insert(out, p)
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

-- ok = false when two pickup spans share any length (ADR 0010 item 5). Touching spans are fine.
-- The message names the first overlapping pair.
function Encounters.validateSpans(layout: any): (boolean, string?)
	local list = sortedPickups(layout)
	for i = 1, #list do
		local loA, hiA = Encounters.spanOf(list[i])
		for j = i + 1, #list do
			local loB, hiB = Encounters.spanOf(list[j])
			if loB >= hiA then
				break -- sorted by z: no later pickup can start before this span ends
			end
			if loA < hiB and loB < hiA then
				return false,
					`pickups {list[i].id} and {list[j].id} overlap in their encounter spans`
			end
		end
	end
	return true, nil
end

-- The encounter to show at lead distance z, or nil when every pickup is resolved. The first
-- unresolved pickup in (z, id) order is chosen; it is active once the lead is inside its span.
-- `outcomes` maps pickup id to "collected" | "missed"; any resolved pickup is skipped.
function Encounters.current(layout: any, z: any, outcomes: { [number]: string }?): Encounter?
	if not isFinite(z) then
		return nil
	end
	local resolved = outcomes or {}
	for _, p in sortedPickups(layout) do
		if resolved[p.id] == nil and p.z > z then
			local lo, hi = Encounters.spanOf(p)
			local active = z >= lo
			local progress = if active then math.clamp((z - lo) / Encounters.SPAN, 0, 1) else 0
			local remaining = math.clamp(hi - z, 0, Remotes.ENCOUNTER_MAX_REMAINING)
			return {
				id = `p{p.id}`,
				kind = "pickup",
				lane = p.lane,
				progress = progress,
				remaining = remaining,
				active = active,
			}
		end
	end
	return nil
end

return Encounters
