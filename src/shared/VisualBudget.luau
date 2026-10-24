--!strict
-- Visual budget allocator (spec section 8). Pure: no game/Instance access, no state.
-- Turns the authoritative crowd total into what the client may draw: at most
-- Config.visualBudget.sectionRepresentatives section stand-ins (each with an xN stack count)
-- and at most Config.visualBudget.looseAvatars loose avatars, while still exposing the exact
-- loose count for the counter. Entourages are decorative and never add followers.
local Config = require("./Config")
local CrowdMath = require("./CrowdMath")

export type Representative = {
	index: number, -- 1-based slot, also the position in the puppet/globo/dancers sequence
	sectionType: CrowdMath.SectionType,
	count: number, -- logical sections this representative stands for (the xN value)
	showBadge: boolean, -- true when count > 1
}
export type Plan = {
	total: number,
	logicalSections: number, -- exact; the firing-rate formula uses this
	representatives: { Representative },
	looseCount: number, -- exact loose followers, shown by the counter
	looseAvatars: number, -- how many loose avatars to draw (<= budget)
	cameraPullback: number,
	formationDensity: number,
}

-- Saturating linear curve: `start` at 0 sections, `max` at curve.sectionsToMax and beyond.
local function curve(c: Config.Curve, sections: number): number
	local t = math.clamp(sections / c.sectionsToMax, 0, 1)
	return c.start + (c.max - c.start) * t
end

local function allocate(total: number): Plan
	-- CrowdMath validates the total (non-negative integer) and errors otherwise.
	local sections = CrowdMath.sectionCount(total)
	local loose = CrowdMath.looseFollowers(total)
	local budget = Config.visualBudget

	local repCount = math.min(sections, budget.sectionRepresentatives)
	local reps: { Representative } = {}
	if repCount > 0 then
		local base = sections // repCount
		local extra = sections % repCount
		for i = 1, repCount do
			-- Balanced stacks: the first `extra` representatives carry one more section.
			local count = base + (if i <= extra then 1 else 0)
			table.insert(reps, {
				index = i,
				sectionType = CrowdMath.sectionType(i),
				count = count,
				showBadge = count > 1,
			})
		end
	end

	return {
		total = total,
		logicalSections = sections,
		representatives = reps,
		looseCount = loose,
		looseAvatars = math.min(loose, budget.looseAvatars),
		cameraPullback = curve(budget.cameraPullback, sections),
		formationDensity = curve(budget.formationDensity, sections),
	}
end

return {
	allocate = allocate,
	curve = curve,
}
