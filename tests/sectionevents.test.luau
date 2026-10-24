--!strict
local Config = require("../src/shared/Config")
local SectionEvents = require("../src/shared/SectionEvents")
local Strings = require("../src/shared/Strings")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

return {
	{
		name = "plan: no threshold crossed means no event",
		run = function()
			eq(SectionEvents.plan(10, 49).kind, "none", "10->49")
			eq(SectionEvents.plan(60, 60).kind, "none", "same")
			eq(SectionEvents.plan(120, 140).kind, "none", "within a section")
		end,
	},
	{
		name = "plan: crossing 50 is a celebration of the Config assembly duration, no +N indicator for one",
		run = function()
			local p = SectionEvents.plan(40, 60)
			eq(p.kind, "celebrate", "kind")
			eq(p.count, 1, "count")
			eq(p.types[1], "puppet", "first section is a puppet")
			eq(p.duration, Config.durations.assemblySeconds, "duration from Config")
			eq(p.indicator, nil, "single threshold has no indicator")
		end,
	},
	{
		name = "plan: one gate crossing 3 thresholds is ONE celebration with '+3 secciones'",
		run = function()
			local p = SectionEvents.plan(40, 200) -- x5-ish: sections 0 -> 4 ... 40 -> 200 crosses 4
			eq(p.kind, "celebrate", "kind")
			eq(p.count, 4, "count")
			eq(p.indicator, "+4 secciones", "indicator")
			eq(p.indicator, Strings.sectionsGained(4), "from Strings")
			local p3 = SectionEvents.plan(60, 160)
			eq(p3.count, 2, "50x1 -> 3 sections is 2 new")
			eq(p3.indicator, "+2 secciones", "two")
		end,
	},
	{
		name = "plan: celebrate carries the section types in sequence order (registry key)",
		run = function()
			local p = SectionEvents.plan(0, 150)
			eq(p.types[1], "puppet", "1")
			eq(p.types[2], "globo", "2")
			eq(p.types[3], "dancers", "3")
		end,
	},
	{
		name = "plan: a drop across a threshold disperses the newest section, no indicator",
		run = function()
			local p = SectionEvents.plan(55, 45)
			eq(p.kind, "disperse", "kind")
			eq(p.count, 1, "count")
			eq(p.sections[1], 1, "newest section")
			eq(p.indicator, nil, "no indicator")
			eq(p.duration, Config.durations.dispersalSeconds, "dispersal duration")
			local multi = SectionEvents.plan(160, 40)
			eq(multi.count, 3, "three disperse at once")
			eq(multi.sections[1], 3, "newest first")
		end,
	},
	{
		name = "plan: representative diff - new section appears as a representative",
		run = function()
			local p = SectionEvents.plan(40, 60)
			eq(#p.reps.appeared, 1, "appeared")
			eq(p.reps.appeared[1].index, 1, "index")
			eq(#p.reps.changed, 0, "changed")
			eq(#p.reps.removed, 0, "removed")
		end,
	},
	{
		name = "plan: beyond 6 representatives sections stack into xN badges instead of new reps",
		run = function()
			local p = SectionEvents.plan(300, 350) -- 6 -> 7 sections: still 6 reps, one stack grows
			eq(p.kind, "celebrate", "kind")
			eq(#p.reps.appeared, 0, "no new rep")
			eq(#p.reps.changed, 1, "one stack grew")
			local c = p.reps.changed[1]
			eq(c.fromCount, 1, "from")
			eq(c.toCount, 2, "to")
			eq(c.showBadge, true, "badge now shown")
			eq(c.index, 1, "first rep carries the extra section")
		end,
	},
	{
		name = "plan: huge jump keeps representatives within the budget of 6",
		run = function()
			local p = SectionEvents.plan(0, 2000)
			eq(p.count, 40, "40 logical sections")
			eq(#p.reps.appeared, Config.visualBudget.sectionRepresentatives, "6 appear")
			eq(p.indicator, "+40 secciones", "indicator")
		end,
	},
	{
		name = "plan: dropping from 7 sections to 6 shrinks a stack; dropping to 5 removes a rep",
		run = function()
			local a = SectionEvents.plan(350, 300)
			eq(a.kind, "disperse", "kind")
			eq(#a.reps.removed, 0, "none removed")
			eq(a.reps.changed[1].toCount, 1, "stack back to 1")
			eq(a.reps.changed[1].showBadge, false, "badge hidden")
			local b = SectionEvents.plan(300, 250)
			eq(#b.reps.removed, 1, "one rep removed")
			eq(b.reps.removed[1], 6, "the newest rep")
		end,
	},
	{
		name = "phases: swirl, confetti and rise are 0..1, rise completes, confetti is brief and ends early",
		run = function()
			local p0 = SectionEvents.phases(0)
			eq(p0.rise, 0, "rise starts at 0")
			eq(p0.confetti, 0, "confetti starts at 0")
			local p1 = SectionEvents.phases(1)
			eq(p1.rise, 1, "rise ends at 1")
			eq(p1.confetti, 0, "confetti is gone at the end")
			eq(p1.swirl, 0, "swirl is gone at the end")
			local prev = 0
			for i = 0, 20 do
				local p = SectionEvents.phases(i / 20)
				for _, v in { p.swirl, p.confetti, p.rise } do
					assert(v >= 0 and v <= 1, "phase value out of range")
				end
				assert(p.rise >= prev, "rise must not go backwards")
				prev = p.rise
			end
			local peak = false
			for i = 0, 20 do
				if SectionEvents.phases(i / 20).confetti > 0.9 then
					peak = true
				end
			end
			eq(peak, true, "confetti peaks")
			local ok = pcall(function()
				SectionEvents.phases(1.5)
			end)
			eq(ok, true, "out-of-range progress is clamped, not an error")
		end,
	},
	{
		name = "swirl: 0 leaves a slot alone; peak pulls it toward the pivot and never past it",
		run = function()
			local x0, z0 = SectionEvents.swirlSlot(6, -10, 0)
			eq(x0, 6, "x at 0")
			eq(z0, -10, "z at 0")
			local pz = SectionEvents.SWIRL_PIVOT_DZ
			local before = math.sqrt(6 * 6 + (-10 - pz) ^ 2)
			local x1, z1 = SectionEvents.swirlSlot(6, -10, 1)
			local after = math.sqrt(x1 * x1 + (z1 - pz) ^ 2)
			assert(after < before, "closer to the pivot")
			assert(after > 0, "still apart")
			local xp, zp = SectionEvents.swirlSlot(0, pz, 1)
			assert(math.abs(xp) < 1e-9 and math.abs(zp - pz) < 1e-9, "pivot is fixed")
		end,
	},
}
