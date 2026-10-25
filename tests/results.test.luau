--!strict
local HudMeters = require("../src/shared/HudMeters")
local Results = require("../src/shared/Results")
local RunFlow = require("../src/shared/RunFlow")
local RunView = require("../src/shared/RunView")
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

-- A flow already on the results screen for `final`.
local function finished(final: any, bestBefore: number): any
	local f = RunFlow.new()
	RunFlow.step(f, state({ best = bestBefore }), 0.1)
	for _ = 1, 400 do
		RunFlow.step(f, final, 0.05)
	end
	return f
end

return {
	{
		name = "score is the final crowd total (completed)",
		run = function()
			local final =
				state({ over = true, outcome = "completed", total = 187, score = 187, best = 187 })
			local r = Results.build(final, finished(final, 0))
			eq(r.scoreValue, 187, "score value")
			eq(r.outcome, "completed", "outcome")
			eq(r.tier, 2, "tier")
			eq(r.score, `{Strings.score}: 187`, "score text")
		end,
	},
	{
		name = "score falls back to the crowd total when the server sent none",
		run = function()
			local final = state({ over = true, outcome = "completed", total = 75 })
			eq(Results.build(final, finished(final, 0)).scoreValue, 75, "fallback")
		end,
	},
	{
		name = "defeated: score is the crowd total at the end, no tier, no new best, best untouched",
		run = function()
			local final =
				state({ over = true, outcome = "defeated", total = 500, score = 500, best = 120 })
			local r = Results.build(final, finished(final, 120))
			eq(r.scoreValue, 500, "score is the crowd total at the end")
			eq(r.outcome, "defeated", "outcome")
			eq(r.tier, 0, "no tier on defeat")
			eq(r.newBest, false, "a defeat is never a best")
			eq(r.bestValue, 120, "best stays the completed-run best")
			eq(r.title, Strings.defeated, "title")
		end,
	},
	{
		name = "session best counts completed runs only, in any order",
		run = function()
			local best, isNew = Results.sessionBest(0, "completed", 100)
			eq(best, 100, "first completed")
			eq(isNew, true, "first completed is a best")
			best, isNew = Results.sessionBest(best, "defeated", 900)
			eq(best, 100, "defeat ignored")
			eq(isNew, false, "defeat is not a best")
			best, isNew = Results.sessionBest(best, "completed", 80)
			eq(best, 100, "lower completed ignored")
			eq(isNew, false, "lower is not a best")
			best, isNew = Results.sessionBest(best, "completed", 100)
			eq(isNew, false, "a tie is not a new best")
			best, isNew = Results.sessionBest(best, "completed", 140)
			eq(best, 140, "higher completed wins")
			eq(isNew, true, "new best")
			best, isNew = Results.sessionBest(best, "mystery", 9999)
			eq(best, 140, "unknown outcome ignored")
			eq(Results.sessionBest(0, "completed", 0), 0, "a zero score is no best")
			eq(select(2, Results.sessionBest(0, "completed", 0)), false, "zero is not new")
		end,
	},
	{
		name = "completed run beating the best is flagged and shown with the badge",
		run = function()
			local final =
				state({ over = true, outcome = "completed", total = 200, score = 200, best = 200 })
			local r = Results.build(final, finished(final, 150))
			eq(r.newBest, true, "new best")
			eq(r.bestValue, 200, "best")
			eq(r.best, `{Strings.best}: 200 {Strings.newBest}`, "best text")
			local plain =
				state({ over = true, outcome = "completed", total = 100, score = 100, best = 150 })
			local p = Results.build(plain, finished(plain, 150))
			eq(p.newBest, false, "not a best")
			eq(p.best, `{Strings.best}: 150`, "best text without the badge")
		end,
	},
	{
		name = "apply keeps the results hidden until the flow reaches them",
		run = function()
			local final =
				state({ over = true, outcome = "completed", total = 60, score = 60, best = 60 })
			local f = RunFlow.new()
			RunFlow.step(f, final, 0.1) -- finale starts
			local early = Results.apply(RunView.hud(final), final, f)
			eq(early.showEnd, false, "hidden during the finale")
			local done = Results.apply(RunView.hud(final), final, finished(final, 0))
			eq(done.showEnd, true, "shown at the end")
			eq(done.endTitle, Strings.completed, "title")
			eq(done.counter, "60", "counter untouched")
		end,
	},
	{
		name = "section meter: exact sections, fraction toward the next one",
		run = function()
			local m = HudMeters.sectionMeter(120)
			eq(m.sections, 2, "sections")
			eq(m.loose, 20, "loose")
			eq(m.fraction, 0.4, "fraction")
			eq(m.toNext, 30, "to next")
			eq(m.label, "Próxima sección en 30", "label")
			eq(HudMeters.sectionMeter(10).fraction, 0.2, "start")
			eq(HudMeters.sectionMeter(50).sections, 1, "boundary")
			eq(HudMeters.sectionMeter(50).fraction, 0, "boundary fraction")
			eq(HudMeters.sectionMeter(-3).sections, 0, "garbage")
			eq(HudMeters.sectionMeter(10000).sections, 200, "large")
		end,
	},
}
