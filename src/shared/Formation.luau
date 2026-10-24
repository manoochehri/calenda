--!strict
-- Pure formation slots (issue #13, spec s3, s8). Offsets are relative to the lead, in studs:
-- dx is lateral (negative = left), dz is along the street (negative = behind the lead). Slots depend
-- only on counts and density, never on how big a model looks, and never enter the lead's fixed
-- gameplay hitbox (Crossing.LEAD_HITBOX). Counts honor the visual budget through VisualBudget.
local Config = require("./Config")
local VisualBudget = require("./VisualBudget")

export type Slot = { dx: number, dz: number }
export type Layout = {
	plan: VisualBudget.Plan,
	slots: { Slot }, -- one per drawn loose avatar (<= budget)
	sections: { Slot }, -- one per section representative (<= budget)
}

local Formation = {}

Formation.PER_ROW = 6 -- [default] followers per row; 24 avatars = 4 compact rows
Formation.FIRST_ROW_DZ = 3.5 -- [default] studs behind the lead (hitbox half depth is 1)
Formation.SPACING_LOOSE = 4 -- [default] studs between followers at density 0
Formation.SPACING_TIGHT = 2 -- [default] studs between followers at density 1
Formation.SECTION_COLUMN_DX = 5 -- [default] section stand-ins sit in two columns this far off axis
Formation.SECTION_ROW_GAP = 9 -- [default] studs between section rows
Formation.SECTION_GAP = 6 -- [default] studs between the last loose row and the first section row

local function checkCount(n: any, max: number, what: string)
	if type(n) ~= "number" or n ~= math.floor(n) or n < 0 or n > max then
		error(`{what} must be an integer from 0 to {max}, got {tostring(n)}`, 3)
	end
end

-- Distance between neighbours; density is 0..1 (VisualBudget.formationDensity).
function Formation.spacing(density: number): number
	local d = math.clamp(density, 0, 1)
	return Formation.SPACING_LOOSE + (Formation.SPACING_TIGHT - Formation.SPACING_LOOSE) * d
end

-- `count` compact rows behind the lead, front row first; a short last row is centered.
function Formation.slots(count: number, density: number): { Slot }
	checkCount(count, Config.visualBudget.looseAvatars, "count")
	local gap = Formation.spacing(density)
	local out: { Slot } = {}
	for i = 0, count - 1 do
		local row = i // Formation.PER_ROW
		local col = i % Formation.PER_ROW
		local inRow = math.min(Formation.PER_ROW, count - row * Formation.PER_ROW)
		table.insert(out, {
			dx = (col - (inRow - 1) / 2) * gap,
			dz = -(Formation.FIRST_ROW_DZ + row * gap),
		})
	end
	return out
end

-- Section stand-ins in two columns behind the deepest possible loose row, so the loose followers
-- never move into them as the count changes.
function Formation.sectionSlots(count: number): { Slot }
	checkCount(count, Config.visualBudget.sectionRepresentatives, "count")
	local rows = math.ceil(Config.visualBudget.looseAvatars / Formation.PER_ROW)
	local deepestLoose = Formation.FIRST_ROW_DZ + (rows - 1) * Formation.SPACING_LOOSE
	local out: { Slot } = {}
	for i = 0, count - 1 do
		local row = i // 2
		local dx = if i % 2 == 0 then -Formation.SECTION_COLUMN_DX else Formation.SECTION_COLUMN_DX
		table.insert(out, {
			dx = dx,
			dz = -(deepestLoose + Formation.SECTION_GAP + row * Formation.SECTION_ROW_GAP),
		})
	end
	return out
end

-- Everything the client may draw for an authoritative crowd total.
function Formation.forTotal(total: number): Layout
	local plan = VisualBudget.allocate(total) -- errors on a negative or fractional total
	return {
		plan = plan,
		slots = Formation.slots(plan.looseAvatars, plan.formationDensity),
		sections = Formation.sectionSlots(#plan.representatives),
	}
end

return Formation
