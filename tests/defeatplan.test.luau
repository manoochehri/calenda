--!strict
local DefeatPlan = require("../src/shared/DefeatPlan")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function near(actual: number, expected: number, name: string)
	assert(math.abs(actual - expected) < 1e-6, `{name}: expected {expected}, got {actual}`)
end

return {
	{
		name = "the breakup beat is short and has stop, breakup, wander phases in order",
		run = function()
			assert(DefeatPlan.DURATION >= 2 and DefeatPlan.DURATION <= 4, "a short beat")
			local order = {}
			local t = 0.0
			while t < DefeatPlan.DURATION do
				local p = DefeatPlan.at(t).phase
				if order[#order] ~= p then
					table.insert(order, p)
				end
				t += 0.02
			end
			eq(table.concat(order, ","), "stop,breakup,wander", "order")
			eq(DefeatPlan.at(DefeatPlan.DURATION).done, true, "done at the end")
			eq(DefeatPlan.at(DefeatPlan.DURATION - 0.01).done, false, "not done before")
		end,
	},
	{
		name = "the parade is stopped for the whole beat",
		run = function()
			for _, t in { 0, 0.4, 1, 2.5, DefeatPlan.DURATION } do
				eq(DefeatPlan.at(t).paradeStopped, true, `stopped at {t}`)
			end
		end,
	},
	{
		name = "musicians tumble and land upright: never a death pose",
		run = function()
			near(DefeatPlan.at(0).tumble, 0, "upright at the start")
			local moved = false
			local t = 0.0
			while t < DefeatPlan.DURATION do
				local a = DefeatPlan.at(t)
				if math.abs(a.tumble) > 0.5 then
					moved = true
				end
				assert(a.lift >= 0, "never underground")
				t += 0.02
			end
			eq(moved, true, "the lead really tumbles")
			-- a whole number of turns, so the figure ends standing
			near(math.cos(DefeatPlan.at(2.0).tumble), 1, "upright after the tumble")
			near(math.cos(DefeatPlan.at(DefeatPlan.DURATION).tumble), 1, "upright at the end")
			near(DefeatPlan.at(DefeatPlan.DURATION).lift, 0, "on the ground at the end")
		end,
	},
	{
		name = "hats and instruments fly once, followers wander only after the breakup",
		run = function()
			local hats, instruments, bursts, laughs = 0, 0, 0, 0
			local prev = -1e-9
			local t = 0.0
			while t < DefeatPlan.DURATION + 0.5 do
				local d = DefeatPlan.due(prev, t)
				hats += d.hats
				instruments += d.instruments
				bursts += d.bursts
				laughs += d.laughs
				prev = t
				t += 1 / 30
			end
			eq(hats, DefeatPlan.HATS, "hats")
			eq(instruments, DefeatPlan.INSTRUMENTS, "instruments")
			assert(bursts >= 2, "confetti bursts")
			assert(laughs >= 2, "followers laugh as they wander off")
			eq(DefeatPlan.at(0.3).wander, 0, "no wandering yet")
			near(DefeatPlan.at(DefeatPlan.DURATION).wander, 1, "wandered off")
		end,
	},
	{
		name = "the banner shows for the whole beat",
		run = function()
			eq(DefeatPlan.at(0).bannerVisible, true, "at 0")
			eq(DefeatPlan.at(DefeatPlan.DURATION - 0.01).bannerVisible, true, "near the end")
		end,
	},
}
