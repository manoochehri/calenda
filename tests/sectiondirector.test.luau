--!strict
local SectionDirector = require("../src/shared/SectionDirector")

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
			eq(p.indicator, "+4 secciones", "indicator")
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
			eq(merged.indicator, "+3 secciones", "combined indicator")
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
}
