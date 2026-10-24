--!strict
local Config = require("../src/shared/Config")
local Crossing = require("../src/shared/Crossing")
local Formation = require("../src/shared/Formation")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function distinct(slots: { { dx: number, dz: number } }, minGap: number, name: string)
	for i = 1, #slots do
		for j = i + 1, #slots do
			local dx, dz = slots[i].dx - slots[j].dx, slots[i].dz - slots[j].dz
			assert(math.sqrt(dx * dx + dz * dz) >= minGap, `{name}: slots {i} and {j} overlap`)
		end
	end
end

return {
	{
		name = "visual budget: loose slots for totals 0, 1, 24, 49 and 10,000",
		run = function()
			local budget = Config.visualBudget.looseAvatars
			eq(#Formation.forTotal(0).slots, 0, "0")
			eq(#Formation.forTotal(1).slots, 1, "1")
			eq(#Formation.forTotal(24).slots, 24, "24")
			eq(#Formation.forTotal(49).slots, budget, "49 is capped at the budget")
			eq(#Formation.forTotal(10000).slots, 0, "10,000 is 200 sections and 0 loose")
			eq(#Formation.forTotal(10001).slots, 1, "10,001 has one loose follower")
			eq(#Formation.forTotal(10049).slots, budget, "10,049 is capped at the budget")
		end,
	},
	{
		name = "section slots honor the representative budget (6) at 0, 1, 24, 49, 10,000",
		run = function()
			eq(#Formation.forTotal(0).sections, 0, "0")
			eq(#Formation.forTotal(49).sections, 0, "49")
			eq(#Formation.forTotal(50).sections, 1, "50")
			eq(#Formation.forTotal(300).sections, 6, "300")
			eq(
				#Formation.forTotal(10000).sections,
				Config.visualBudget.sectionRepresentatives,
				"10,000"
			)
		end,
	},
	{
		name = "the exact loose count is carried separately from what is drawn",
		run = function()
			eq(Formation.forTotal(49).plan.looseCount, 49, "49 exact")
			eq(#Formation.forTotal(49).slots, 24, "49 drawn")
			eq(Formation.forTotal(10001).plan.looseCount, 1, "10,001 exact")
		end,
	},
	{
		name = "slots are compact rows behind the lead, never inside its fixed hitbox",
		run = function()
			local hb = Crossing.LEAD_HITBOX
			for _, total in { 1, 24, 49 } do
				local f = Formation.forTotal(total)
				distinct(f.slots, 1.5, `total {total}`)
				for i, s in f.slots do
					assert(s.dz < -hb.halfDepth, `total {total} slot {i} is behind the lead`)
					assert(
						math.abs(s.dx) > hb.halfWidth or s.dz < -hb.halfDepth - 1,
						`total {total} slot {i} clear of the hitbox`
					)
					assert(math.abs(s.dx) <= Formation.PER_ROW * 4, "stays compact sideways")
				end
			end
		end,
	},
	{
		name = "rows fill front to back, at most PER_ROW wide, last row centered",
		run = function()
			local slots = Formation.slots(8, 1)
			local rowZ: { [number]: number } = {}
			local rows = 0
			for _, s in slots do
				local key = math.floor(s.dz * 100 + 0.5)
				rowZ[key] = (rowZ[key] or 0) + 1
			end
			for _, n in rowZ do
				rows += 1
				assert(n <= Formation.PER_ROW, "row too wide")
			end
			eq(rows, 2, "8 followers use two rows")
			-- the second row holds 2 followers, centered on the lead's axis
			local last = slots[#slots]
			local prev = slots[#slots - 1]
			assert(math.abs(last.dx + prev.dx) < 1e-9, "last row is centered")
		end,
	},
	{
		name = "denser formation is tighter",
		run = function()
			assert(Formation.spacing(1) < Formation.spacing(0.5), "density 1 tighter than 0.5")
			local loose, tight = Formation.slots(6, 0.5), Formation.slots(6, 1)
			assert(math.abs(loose[1].dx) > math.abs(tight[1].dx), "row is wider when loose")
		end,
	},
	{
		name = "slots depend only on count and density, not on any visual size",
		run = function()
			local a, b = Formation.slots(24, 1), Formation.slots(24, 1)
			for i = 1, 24 do
				eq(a[i].dx, b[i].dx, "dx")
				eq(a[i].dz, b[i].dz, "dz")
			end
		end,
	},
	{
		name = "a bad count is an error; counts above the budget are not silently drawn",
		run = function()
			assert(not pcall(Formation.slots, -1, 1), "negative")
			assert(not pcall(Formation.slots, 1.5, 1), "fractional")
			assert(
				not pcall(Formation.slots, Config.visualBudget.looseAvatars + 1, 1),
				"over budget"
			)
			assert(not pcall(Formation.forTotal, -5), "negative total")
		end,
	},
	{
		name = "section slots sit behind every possible loose slot and do not overlap",
		run = function()
			local deepestLoose = 0
			for _, s in Formation.slots(Config.visualBudget.looseAvatars, 0) do
				deepestLoose = math.min(deepestLoose, s.dz)
			end
			local sections = Formation.sectionSlots(6)
			eq(#sections, 6, "six")
			distinct(sections, 4, "sections")
			for i, s in sections do
				assert(s.dz < deepestLoose, `section {i} is behind the loose followers`)
			end
			assert(not pcall(Formation.sectionSlots, 7), "over the representative budget")
		end,
	},
}
