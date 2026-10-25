--!strict
-- Pure formation slots (issue #13, spec s3, s8; reworked in issue #68). Offsets are relative to the
-- lead, in studs: dx is lateral (negative = left), dz is along the street (negative = behind). Slots
-- depend only on counts, never on how big a model looks, and never enter the lead's fixed gameplay
-- hitbox (Crossing.LEAD_HITBOX). There are no rows or columns: loose followers and section bases
-- both come from the organic layout in FollowerSlots. Counts honor the visual budget (VisualBudget).
local Config = require("./Config")
local FollowerSlots = require("./FollowerSlots")
local VisualBudget = require("./VisualBudget")

export type Slot = { dx: number, dz: number }
export type Layout = {
	plan: VisualBudget.Plan,
	slots: { Slot }, -- one per drawn loose avatar (<= budget)
	sections: { Slot }, -- one per section representative (<= budget)
}

local Formation = {}

local function checkCount(n: any, max: number, what: string)
	if type(n) ~= "number" or n ~= math.floor(n) or n < 0 or n > max then
		error(`{what} must be an integer from 0 to {max}, got {tostring(n)}`, 3)
	end
end

-- The first `count` organic slots (follower k keeps slot k). `density` is accepted and ignored.
function Formation.slots(count: number, _density: number?): { Slot }
	checkCount(count, Config.visualBudget.looseAvatars, "count")
	local out: { Slot } = {}
	for i = 1, count do
		local s = FollowerSlots.slot(i)
		table.insert(out, { dx = s.dx, dz = s.dz })
	end
	return out
end

-- Section stand-ins stand INSIDE the loose crowd at the irregular bases FollowerSlots reserves: the
-- cloud keeps a hole around every base, so loose followers never move into them.
function Formation.sectionSlots(count: number): { Slot }
	checkCount(count, Config.visualBudget.sectionRepresentatives, "count")
	local out: { Slot } = {}
	for i = 1, count do
		local b = FollowerSlots.base(i)
		table.insert(out, { dx = b.dx, dz = b.dz })
	end
	return out
end

-- Everything the client may draw for an authoritative crowd total.
function Formation.forTotal(total: number): Layout
	local plan = VisualBudget.allocate(total) -- errors on a negative or fractional total
	return {
		plan = plan,
		slots = Formation.slots(plan.looseAvatars),
		sections = Formation.sectionSlots(#plan.representatives),
	}
end

return Formation
