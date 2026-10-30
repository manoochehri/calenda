--!strict
local Config = require("../src/shared/Config")
local SectionDirector = require("../src/shared/SectionDirector")
local SectionEvents = require("../src/shared/SectionEvents")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

return {
	{
		name = "director: the first observation and sub-threshold growth start nothing",
		run = function()
			local d = SectionDirector.new(10)
			eq(d:observe(10), nil, "same total")
			eq(d:observe(30), nil, "growth within a section")
			eq(d:active(), nil, "nothing active")
		end,
	},
	{
		name = "director: a gate crossing several thresholds starts exactly one celebration",
		run = function()
			local d = SectionDirector.new(40)
			local p = d:observe(200)
			assert(p ~= nil, "plan")
			eq(p.count, 4, "count")
			eq(d:observe(200), nil, "no second start for the same total")
			local a = d:active()
			assert(a ~= nil, "active")
			eq(a.plan.count, 4, "active plan")
		end,
	},
	{
		name = "director: a second crossing during the window merges into the same celebration",
		run = function()
			local d = SectionDirector.new(40)
			d:observe(60) -- 1 section
			d:step(0.3)
			local merged = d:observe(160) -- 2 more
			assert(merged ~= nil, "merged plan")
			eq(merged.count, 3, "1 + 2 sections")
			eq(#merged.types, 3, "types combined")
			local a = d:active()
			assert(a ~= nil, "active")
			eq(a.plan.count, 3, "still one active celebration")
			eq(a.elapsed, 0, "window restarts so the new puppets rise fully")
		end,
	},
	{
		name = "director: the celebration ends after its duration while play continues",
		run = function()
			local d = SectionDirector.new(40)
			local p = d:observe(60)
			assert(p ~= nil, "plan")
			d:step(p.duration * 0.5)
			local a = d:active()
			assert(a ~= nil, "mid-way active")
			assert(math.abs(a.progress - 0.5) < 1e-9, "progress is half")
			d:step(p.duration)
			eq(d:active(), nil, "finished")
		end,
	},
	{
		name = "director: a drop disperses the newest section and cancels a running celebration",
		run = function()
			local d = SectionDirector.new(40)
			d:observe(60)
			local p = d:observe(45)
			assert(p ~= nil, "plan")
			eq(p.kind, "disperse", "kind")
			local a = d:active()
			assert(a ~= nil, "active")
			eq(a.plan.kind, "disperse", "disperse replaces celebrate")
			eq(d:observe(45), nil, "no repeat")
		end,
	},
	{
		name = "director: reset adopts a total without any celebration (new run)",
		run = function()
			local d = SectionDirector.new(40)
			d:observe(60)
			d:reset(10)
			eq(d:active(), nil, "cleared")
			eq(d:observe(30), nil, "no event after reset")
			eq(d:shownTotal(), 30, "tracks total")
		end,
	},
	{
		name = "merge: the re-plan repeats reps already shown; toBuild skips them (no duplicate figures)",
		run = function()
			local d = SectionDirector.new(40)
			local built: { [number]: boolean } = {}
			local first = d:observe(110) -- 2 sections
			assert(first ~= nil, "first")
			for _, r in SectionEvents.toBuild(first.reps, built) do
				built[r.index] = true
			end
			eq(#first.reps.appeared, 2, "two appear")
			d:step(0.3)
			local merged = d:observe(160) -- inside the window: 3 sections in total
			assert(merged ~= nil, "merged")
			eq(#merged.reps.appeared, 3, "the merged plan lists all three, two already built")
			local fresh = SectionEvents.toBuild(merged.reps, built)
			eq(#fresh, 1, "only the new representative is built")
			eq(fresh[1].index, 3, "index 3")
		end,
	},
	{
		name = "merge: repeated crossings never build more representatives than the budget",
		run = function()
			local d = SectionDirector.new(0)
			local built: { [number]: boolean } = {}
			local builtCount = 0
			local total = 0
			for _ = 1, 30 do
				total += 130
				local plan = d:observe(total)
				if plan then
					for _, r in SectionEvents.toBuild(plan.reps, built) do
						built[r.index] = true
						builtCount += 1
					end
				end
				d:step(0.1)
			end
			eq(builtCount <= Config.visualBudget.sectionRepresentatives, true, "within budget")
			eq(
				builtCount,
				Config.visualBudget.sectionRepresentatives,
				"all six eventually exist once"
			)
		end,
	},
	{
		name = "replace: celebrate then a drop becomes a disperse, and a rise after a drop is a fresh celebrate",
		run = function()
			local d = SectionDirector.new(40)
			d:observe(60)
			local down = d:observe(40)
			assert(down ~= nil, "down")
			eq(down.kind, "disperse", "disperse")
			eq(down.from, 60, "from the shown total, not the old start")
			local up = d:observe(70)
			assert(up ~= nil, "up")
			eq(up.kind, "celebrate", "celebrate")
			eq(up.from, 40, "fresh from the shown total")
			local a = d:active()
			assert(a ~= nil, "active")
			eq(a.plan.kind, "celebrate", "celebrate replaced the disperse")
		end,
	},
}
