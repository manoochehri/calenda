--!strict
local Config = require("../src/shared/Config")
local VisualBudget = require("../src/shared/VisualBudget")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {expected}, got {actual}`)
end

local SEQUENCE = { "puppet", "globo", "dancers" }
local TOTALS = { 0, 1, 49, 50, 99, 100, 300, 2000, 10000 }

local function badgeSum(plan: VisualBudget.Plan): number
	local sum = 0
	for _, rep in plan.representatives do
		sum += rep.count
	end
	return sum
end

local function clone(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = clone(v)
	end
	return out
end

return {
	{
		name = "spec s8: 2,000 followers is 40 logical sections shown by 6 representatives",
		run = function()
			local plan = VisualBudget.allocate(2000)
			eq(plan.logicalSections, 40, "logicalSections")
			eq(#plan.representatives, 6, "representatives")
			eq(badgeSum(plan), 40, "badge sum")
			eq(plan.looseCount, 0, "looseCount")
			eq(plan.looseAvatars, 0, "looseAvatars")
		end,
	},
	{
		name = "badges sum to logical sections for every total",
		run = function()
			for _, total in TOTALS do
				local plan = VisualBudget.allocate(total)
				eq(badgeSum(plan), plan.logicalSections, `badge sum at {total}`)
				for _, rep in plan.representatives do
					assert(rep.count >= 1, `empty stack at {total}`)
					eq(rep.showBadge, rep.count > 1, `showBadge at {total}`)
				end
			end
		end,
	},
	{
		name = "budgets (6 representatives, 24 avatars) are never exceeded",
		run = function()
			eq(Config.visualBudget.sectionRepresentatives, 6, "config reps")
			eq(Config.visualBudget.looseAvatars, 24, "config avatars")
			for _, total in { 0, 1, 49, 50, 2000, 10000 } do
				local plan = VisualBudget.allocate(total)
				assert(#plan.representatives <= 6, `reps over budget at {total}`)
				assert(plan.looseAvatars <= 24, `avatars over budget at {total}`)
			end
			for total = 0, 600 do
				local plan = VisualBudget.allocate(total)
				assert(#plan.representatives <= 6 and plan.looseAvatars <= 24, `budget at {total}`)
			end
		end,
	},
	{
		name = "fewer sections than budget: one representative per section, no badge",
		run = function()
			eq(#VisualBudget.allocate(0).representatives, 0, "0")
			eq(#VisualBudget.allocate(49).representatives, 0, "49")
			local one = VisualBudget.allocate(50)
			eq(#one.representatives, 1, "50 reps")
			eq(one.representatives[1].count, 1, "50 count")
			eq(one.representatives[1].showBadge, false, "50 badge")
			local three = VisualBudget.allocate(150)
			eq(#three.representatives, 3, "150 reps")
		end,
	},
	{
		name = "representative types follow puppet -> globo -> dancers",
		run = function()
			for _, total in TOTALS do
				local plan = VisualBudget.allocate(total)
				for i, rep in plan.representatives do
					eq(rep.sectionType, SEQUENCE[(i - 1) % 3 + 1], `type of rep {i} at {total}`)
					eq(rep.index, i, `index of rep {i}`)
				end
			end
		end,
	},
	{
		name = "stacks are balanced (counts differ by at most one)",
		run = function()
			local plan = VisualBudget.allocate(2000)
			local counts = {}
			for _, rep in plan.representatives do
				table.insert(counts, rep.count)
			end
			eq(table.concat(counts, ","), "7,7,7,7,6,6", "40 sections over 6 reps")
			local plan10k = VisualBudget.allocate(10000)
			eq(plan10k.logicalSections, 200, "10,000 sections")
			eq(badgeSum(plan10k), 200, "10,000 badge sum")
		end,
	},
	{
		name = "exact loose count is exposed even when only 24 avatars are drawn",
		run = function()
			local plan = VisualBudget.allocate(49)
			eq(plan.looseCount, 49, "looseCount")
			eq(plan.looseAvatars, 24, "looseAvatars")
			local small = VisualBudget.allocate(10)
			eq(small.looseCount, 10, "start looseCount")
			eq(small.looseAvatars, 10, "start looseAvatars")
			local big = VisualBudget.allocate(10000)
			eq(big.looseCount, 0, "10,000 loose")
			local mixed = VisualBudget.allocate(2023)
			eq(mixed.looseCount, 23, "2023 loose")
			eq(mixed.logicalSections, 40, "2023 sections")
			eq(mixed.total, 2023, "total echoed")
		end,
	},
	{
		name = "camera pullback and formation density come from the Config curve",
		run = function()
			local c = Config.visualBudget
			local zero = VisualBudget.allocate(0)
			eq(zero.cameraPullback, c.cameraPullback.start, "pullback at 0")
			eq(zero.formationDensity, c.formationDensity.start, "density at 0")
			local top = VisualBudget.allocate(10000)
			eq(top.cameraPullback, c.cameraPullback.max, "pullback saturates")
			eq(top.formationDensity, c.formationDensity.max, "density saturates")
			local prev = -1
			for sections = 0, 60 do
				local v = VisualBudget.curve(c.cameraPullback, sections)
				assert(v >= prev, "pullback must be non-decreasing")
				assert(v <= c.cameraPullback.max, "pullback within max")
				prev = v
			end
			local half = VisualBudget.curve({ start = 1, max = 2, sectionsToMax = 10 }, 5)
			eq(half, 1.5, "linear midpoint")
		end,
	},
	{
		name = "invalid totals are rejected",
		run = function()
			for _, bad in { -1, 1.5, 0 / 0, math.huge } do
				assert(not pcall(VisualBudget.allocate, bad), `expected error for {bad}`)
			end
			assert(not pcall(VisualBudget.allocate, "50" :: any), "string rejected")
		end,
	},
	{
		name = "config: curve keys validate and bad curves are rejected",
		run = function()
			local function invalid(mutate: (c: any) -> ()): boolean
				local c = clone(Config)
				mutate(c)
				local ok = Config.validate(c)
				return not ok
			end
			assert(
				invalid(function(c)
					c.visualBudget.cameraPullback = nil
				end),
				"missing cameraPullback"
			)
			assert(
				invalid(function(c)
					c.visualBudget.cameraPullback.max = c.visualBudget.cameraPullback.start - 0.1
				end),
				"pullback max below start"
			)
			assert(
				invalid(function(c)
					c.visualBudget.formationDensity.sectionsToMax = 0
				end),
				"density sectionsToMax zero"
			)
			assert(
				invalid(function(c)
					c.visualBudget.formationDensity.start = -1
				end),
				"density negative start"
			)
			assert(
				invalid(function(c)
					c.visualBudget.cameraPullback.start = "1"
				end),
				"non-number start"
			)
		end,
	},
}
