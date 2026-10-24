--!strict
local DefeatPlan = require("../src/shared/DefeatPlan")
local FinalePlan = require("../src/shared/FinalePlan")
local HitFeedback = require("../src/shared/HitFeedback")
local ResetPlan = require("../src/shared/ResetPlan")
local RunFlow = require("../src/shared/RunFlow")
local Strings = require("../src/shared/Strings")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function state(over: { [string]: any }?): any
	local s: { [string]: any } = { t = 4, z = 64, x = 0, total = 10, best = 0, over = false }
	for k, v in over or {} do
		s[k] = v
	end
	return s
end

local function sameFlow(a: any, b: any, name: string)
	for _, k in { "phase", "elapsed", "outcome", "tier", "score", "bestBefore" } do
		eq(a[k], b[k], `{name}.{k}`)
	end
end

-- Runs a flow to its results screen with the given final state; returns the phases it went through.
local function playOut(flow: any, final: any): { string }
	local seen = {}
	local function note()
		if seen[#seen] ~= flow.phase then
			table.insert(seen, flow.phase)
		end
	end
	for _ = 1, 40 do
		RunFlow.step(flow, state({ t = 1, best = final.best, total = final.total }), 0.1)
		note()
	end
	for _ = 1, 400 do
		RunFlow.step(flow, final, 0.05)
		note()
	end
	return seen
end

return {
	{
		name = "a running run shows no banner and no results",
		run = function()
			local f = RunFlow.new()
			RunFlow.step(f, state(), 0.1)
			eq(f.phase, "running", "phase")
			eq(RunFlow.resultsVisible(f), false, "results hidden")
			eq(RunFlow.banner(f), nil, "no banner")
		end,
	},
	{
		name = "completed: finale (with the tier), then results",
		run = function()
			local f = RunFlow.new()
			local seen =
				playOut(f, state({ over = true, outcome = "completed", total = 180, score = 180 }))
			eq(table.concat(seen, ","), "running,finale,results", "phases")
			eq(f.tier, 2, "180 is tier 2")
			eq(f.outcome, "completed", "outcome")
			eq(RunFlow.resultsVisible(f), true, "results shown")
		end,
	},
	{
		name = "the finale holds for its whole duration before results",
		run = function()
			local f = RunFlow.new()
			local final = state({ over = true, outcome = "completed", total = 60, score = 60 })
			RunFlow.step(f, final, 0.0)
			eq(f.phase, "finale", "enters the finale")
			eq(RunFlow.banner(f), Strings.tierBanner[1], "tier banner during the finale")
			RunFlow.step(f, final, FinalePlan.DURATION - 0.1)
			eq(f.phase, "finale", "still in the finale")
			eq(RunFlow.resultsVisible(f), false, "results not yet")
			RunFlow.step(f, final, 0.2)
			eq(f.phase, "results", "results after the duration")
			eq(RunFlow.banner(f), nil, "banner gone")
		end,
	},
	{
		name = "defeated: breakup beat with the defeat banner, then results, never a finale or tier",
		run = function()
			local f = RunFlow.new()
			local final = state({ over = true, outcome = "defeated", total = 400, score = 400 })
			local seen = playOut(f, final)
			eq(table.concat(seen, ","), "running,breakup,results", "phases")
			eq(f.tier, 0, "no tier even with a huge crowd")
			local g = RunFlow.new()
			RunFlow.step(g, final, 0.0)
			eq(g.phase, "breakup", "enters the breakup")
			eq(RunFlow.banner(g), Strings.defeated, "playful banner")
			RunFlow.step(g, final, DefeatPlan.DURATION + 0.1)
			eq(g.phase, "results", "results after the beat")
			eq(g.tier, 0, "still no tier")
		end,
	},
	{
		name = "an unknown outcome goes straight to results",
		run = function()
			local f = RunFlow.new()
			RunFlow.step(
				f,
				state({ over = true, outcome = "mystery", total = 30, score = 30 }),
				0.1
			)
			eq(f.phase, "results", "phase")
			eq(f.tier, 0, "no tier")
		end,
	},
	{
		name = "bestBefore is the best seen while the run was still going",
		run = function()
			local f = RunFlow.new()
			RunFlow.step(f, state({ best = 120 }), 0.1)
			RunFlow.step(
				f,
				state({ best = 120, over = true, outcome = "completed", total = 200, score = 200 }),
				0.1
			)
			eq(f.bestBefore, 120, "frozen at the run's end")
		end,
	},
	{
		name = "ResetPlan lists the full client checklist",
		run = function()
			for _, need in
				{
					"counters",
					"sections",
					"clusters",
					"obstacles",
					"bits",
					"finale",
					"results",
					"flow",
					"input",
					"music",
					"audio",
					"hp",
				}
			do
				assert(table.find(ResetPlan.items, need) ~= nil, `checklist has {need}`)
			end
		end,
	},
	{
		name = "ResetPlan.apply calls every item once, in order",
		run = function()
			local calls = {}
			local handlers: { [string]: () -> () } = {}
			for _, item in ResetPlan.items do
				handlers[item] = function()
					table.insert(calls, item)
				end
			end
			local warnings = {}
			ResetPlan.apply(handlers, function(m)
				table.insert(warnings, m)
			end)
			eq(table.concat(calls, ","), table.concat(ResetPlan.items, ","), "order and count")
			eq(#warnings, 0, "no warnings")
		end,
	},
	{
		name = "ResetPlan.apply never throws: a missing, unknown or failing handler warns and the rest still run",
		run = function()
			local calls = {}
			local handlers: { [string]: () -> () } = {}
			for _, item in ResetPlan.items do
				handlers[item] = function()
					table.insert(calls, item)
				end
			end
			handlers.bits = nil :: any
			handlers.typo = function() end
			handlers.clusters = function()
				error("boom")
			end
			local warnings = {}
			local ok = pcall(ResetPlan.apply, handlers, function(m)
				table.insert(warnings, m)
			end)
			eq(ok, true, "does not throw")
			eq(#warnings, 3, "one warning each")
			local text = table.concat(warnings, "|")
			assert(string.find(text, "bits") ~= nil, "names the missing item")
			assert(string.find(text, "typo") ~= nil, "names the unknown handler")
			assert(string.find(text, "clusters") ~= nil, "names the failing handler")
			eq(table.find(calls, "flow") ~= nil, true, "later items still ran")
			eq(table.find(calls, "results") ~= nil, true, "results still reset")
		end,
	},
	{
		name = "replay twice leaves no stale flow state",
		run = function()
			local f = RunFlow.new()
			local handlers: { [string]: () -> () } = {}
			local resets: { [string]: number } = {}
			for _, item in ResetPlan.items do
				handlers[item] = function()
					resets[item] = (resets[item] or 0) + 1
				end
			end
			handlers.flow = function()
				resets.flow = (resets.flow or 0) + 1
				RunFlow.reset(f)
			end
			-- Issue #50: a hit still playing when the run ends must not leak into the next one.
			local hit = HitFeedback.new()
			handlers.hp = function()
				resets.hp = (resets.hp or 0) + 1
				hit:reset()
			end
			hit:hit(1)
			-- Round 1: a big completed run, then replay.
			playOut(
				f,
				state({ over = true, outcome = "completed", total = 320, score = 320, best = 0 })
			)
			eq(f.phase, "results", "round 1 reached results")
			ResetPlan.apply(handlers)
			sameFlow(f, RunFlow.new(), "after replay 1")
			eq(hit:sample().flash, 0, "hit feedback cleared by replay 1")
			hit:hit(1)
			-- Round 2: a defeat, then replay again.
			playOut(
				f,
				state({ over = true, outcome = "defeated", total = 90, score = 90, best = 320 })
			)
			eq(f.phase, "results", "round 2 reached results")
			eq(f.tier, 0, "defeat has no tier")
			ResetPlan.apply(handlers)
			sameFlow(f, RunFlow.new(), "after replay 2")
			eq(hit:sample().flash, 0, "hit feedback cleared by replay 2")
			for _, item in ResetPlan.items do
				eq(resets[item], 2, `{item} reset once per replay`)
			end
			eq(RunFlow.resultsVisible(f), false, "no results left over")
			eq(RunFlow.banner(f), nil, "no banner left over")
		end,
	},
	{
		name = "a state that is no longer over returns a stray flow to running",
		run = function()
			local f = RunFlow.new()
			playOut(f, state({ over = true, outcome = "completed", total = 60, score = 60 }))
			RunFlow.step(f, state({ t = 0.1 }), 0.1)
			sameFlow(f, RunFlow.new(), "back to a fresh flow")
		end,
	},
}
