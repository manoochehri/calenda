--!strict
-- Issue #144: the validator's maxTotal guard is a witness search (real RunDriver runs under fixed
-- policies and seeds), not a proof. These tests pin the reported witness and the sample sizes.
local DebugLayout = require("../src/shared/DebugLayout")
local LayoutValidator = require("../src/shared/LayoutValidator")
local LayoutWitness = require("../src/shared/LayoutWitness")
local Layouts = require("../src/shared/Layouts")

-- A shallow copy with a different maxTotal. The layout data itself is not changed.
local function withMaxTotal(layout: any, maxTotal: number): any
	local copy = table.clone(layout)
	copy.maxTotal = maxTotal
	return copy
end

local function joined(errors: { string }): string
	return table.concat(errors, " | ")
end

return {
	{
		-- Known witness (issue #144): portal-del-sur is Layouts.select(1), seed 1. Against a limit of
		-- 2500 the guard must report a real run above it, with its policy, seed and total. On the
		-- unchanged code this fails: the enumerated best route is reported instead, with no witness.
		name = "witness: portal-del-sur seed 1 above maxTotal 2500 is reported with policy, seed, total",
		run = function()
			local layout = withMaxTotal(Layouts.select(1), 2500)
			assert(layout.name == "portal-del-sur", `expected portal-del-sur, got {layout.name}`)
			local report = LayoutValidator.check(layout)
			assert(not report.ok, "a witness above maxTotal must reject the layout")
			assert(report.witness ~= nil, "witness search result missing from the report")
			local worst = report.witness.worst
			assert(worst ~= nil, "no witness recorded")
			assert(worst.seed == 1, `witness seed {worst.seed}, expected 1`)
			assert(worst.total > 2500, `witness total {worst.total} does not exceed 2500`)
			assert(type(worst.policy) == "string" and worst.policy ~= "", "witness policy missing")
			local text = joined(report.errors)
			assert(string.find(text, "witness", 1, true), `no witness in: {text}`)
			assert(string.find(text, "maxTotal", 1, true), `no maxTotal in: {text}`)
		end,
	},
	{
		name = "witness: sample sizes are reported (policies x seeds runs)",
		run = function()
			local report = LayoutValidator.check(DebugLayout)
			local w = report.witness
			assert(w ~= nil, "witness search result missing")
			assert(w.policies >= 8, `only {w.policies} policies`)
			assert(w.seeds == #LayoutWitness.SEEDS, `seeds {w.seeds}`)
			assert(w.runs == w.policies * w.seeds, `runs {w.runs} != {w.policies} x {w.seeds}`)
		end,
	},
	{
		-- A witness is a real run, not a bound: a layout whose witness stays under the limit passes,
		-- and the report carries the highest witness, not a claim about every possible run.
		name = "witness: debug layout passes with its highest witness recorded, not a bound",
		run = function()
			local report = LayoutValidator.check(DebugLayout)
			assert(report.ok, `rejected: {joined(report.errors)}`)
			assert(report.witness.worst.total <= DebugLayout.maxTotal, "witness above limit")
			assert(string.find(joined(report.errors), "bound") == nil, "no bound wording")
		end,
	},
	{
		name = "witness: search is deterministic for a fixed layout and seeds",
		run = function()
			local a = LayoutWitness.search(DebugLayout)
			local b = LayoutWitness.search(DebugLayout)
			assert(a.worst ~= nil and b.worst ~= nil, "no witness")
			assert(a.worst.policy == b.worst.policy, "policy differs between runs")
			assert(a.worst.seed == b.worst.seed, "seed differs between runs")
			assert(a.worst.total == b.worst.total, "total differs between runs")
		end,
	},
}
