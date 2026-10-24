--!strict
local Beats = require("../src/shared/Beats")
local Celebration = require("../src/shared/Celebration")
local Config = require("../src/shared/Config")
local FinalePlan = require("../src/shared/FinalePlan")
local Strings = require("../src/shared/Strings")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function near(actual: number, expected: number, name: string)
	assert(math.abs(actual - expected) < 1e-9, `{name}: expected {expected}, got {actual}`)
end

-- Sums FinalePlan.due over a run of fixed steps.
local function sumDue(tier: number, step: number): (number, number)
	local bursts, gifts = 0, 0
	local prev = -1e-9
	local t = 0.0
	while t <= FinalePlan.DURATION + step do
		local d = FinalePlan.due(prev, t, tier)
		bursts += d.bursts
		gifts += d.gifts
		prev = t
		t += step
	end
	return bursts, gifts
end

return {
	{
		name = "tierFor uses the Config thresholds 50/150/300 inclusively",
		run = function()
			eq(#Config.finaleThresholds, 3, "three thresholds")
			eq(Celebration.tierFor(0), 0, "0")
			eq(Celebration.tierFor(49), 0, "49")
			eq(Celebration.tierFor(50), 1, "50")
			eq(Celebration.tierFor(149), 1, "149")
			eq(Celebration.tierFor(150), 2, "150")
			eq(Celebration.tierFor(299), 2, "299")
			eq(Celebration.tierFor(300), 3, "300")
			eq(Celebration.tierFor(10000), 3, "10000 stays at the top tier")
		end,
	},
	{
		name = "tierFor takes custom thresholds and survives garbage",
		run = function()
			eq(Celebration.tierFor(10, { 5, 20 }), 1, "custom")
			eq(Celebration.tierFor(20, { 5, 20 }), 2, "custom top")
			eq(Celebration.tierFor(-5), 0, "negative")
			eq(Celebration.tierFor(0 / 0), 0, "nan")
			eq(Celebration.tierFor(math.huge), 0, "inf is not a total")
			eq(Celebration.tierFor("300" :: any), 0, "string")
			eq(Celebration.tierFor(50.9), 1, "fractional floors")
		end,
	},
	{
		name = "profiles grow with the tier, stay inside the visual budget, tier 0 has no banner",
		run = function()
			local prev = Celebration.profile(0)
			for tier = 1, 3 do
				local p = Celebration.profile(tier)
				assert(p.dancers > prev.dancers, `dancers grow at tier {tier}`)
				assert(p.bursts > prev.bursts, `bursts grow at tier {tier}`)
				assert(p.gifts > prev.gifts, `gifts grow at tier {tier}`)
				assert(p.dancers <= Config.visualBudget.looseAvatars, "dancers within budget")
				prev = p
			end
			eq(Celebration.banner(0), nil, "no banner below the first threshold")
			eq(Celebration.banner(1), Strings.tierBanner[1], "banner 1")
			eq(Celebration.banner(3), Strings.tierBanner[3], "banner 3")
			eq(Celebration.profile(99).dancers, Celebration.profile(3).dancers, "clamped high")
			eq(Celebration.profile(-1).dancers, Celebration.profile(0).dancers, "clamped low")
		end,
	},
	{
		name = "Beats.evenly and Beats.countIn",
		run = function()
			eq(#Beats.evenly(0, 1, 2), 0, "none")
			eq(Beats.evenly(1, 1, 2)[1], 1, "one")
			local t = Beats.evenly(3, 1, 3)
			near(t[1], 1, "first")
			near(t[2], 2, "mid")
			near(t[3], 3, "last")
			eq(Beats.countIn(t, 0, 1), 1, "(0,1] includes 1")
			eq(Beats.countIn(t, 1, 2), 1, "(1,2] excludes 1")
			eq(Beats.countIn(t, 0, 10), 3, "all")
			eq(Beats.countIn(t, 2, 2), 0, "empty window")
		end,
	},
	{
		name = "finale lasts 8-10 s (spec s2)",
		run = function()
			assert(FinalePlan.DURATION >= 8 and FinalePlan.DURATION <= 10, "duration in spec range")
			eq(FinalePlan.at(0).phase, "spread", "starts spreading")
			eq(FinalePlan.at(FinalePlan.DURATION - 0.01).done, false, "not done just before")
			eq(FinalePlan.at(FinalePlan.DURATION).done, true, "done at the end")
			eq(FinalePlan.at(FinalePlan.DURATION).phase, "done", "done phase")
		end,
	},
	{
		name = "finale phases in order: spread, party, peak; spread and music only rise",
		run = function()
			local order = {}
			local prevSpread, prevMusic = -1.0, -1.0
			local t = 0.0
			while t < FinalePlan.DURATION do
				local f = FinalePlan.at(t)
				if order[#order] ~= f.phase then
					table.insert(order, f.phase)
				end
				assert(f.spread >= prevSpread, "spread never shrinks")
				assert(f.musicIntensity >= prevMusic, "music never drops")
				assert(f.spread >= 0 and f.spread <= 1, "spread in 0..1")
				assert(f.musicIntensity >= 0 and f.musicIntensity <= 1, "music in 0..1")
				prevSpread, prevMusic = f.spread, f.musicIntensity
				t += 0.05
			end
			eq(table.concat(order, ","), "spread,party,peak", "phase order")
			near(FinalePlan.at(0).spread, 0, "party starts together")
			near(FinalePlan.at(FinalePlan.DURATION - 0.01).spread, 1, "fully spread by the end")
			near(FinalePlan.at(FinalePlan.DURATION - 0.01).musicIntensity, 1, "music peaks")
			assert(FinalePlan.at(5).cameraPullback > 1, "camera pulls back to show the plaza")
		end,
	},
	{
		name = "plaza slots stay inside the plaza and are all different",
		run = function()
			local seen: { [string]: boolean } = {}
			for i = 1, 24 do
				local dx, dz = FinalePlan.slot(i, 24, 20, 120)
				assert(math.abs(dx) <= 18, "inside the plaza width")
				assert(dz >= 6 and dz <= 120, "ahead of the lead and inside the depth")
				local key = string.format("%.3f,%.3f", dx, dz)
				assert(not seen[key], "distinct slots")
				seen[key] = true
			end
		end,
	},
	{
		name = "scheduled bursts and gifts total the profile, whatever the frame step",
		run = function()
			for tier = 0, 3 do
				local p = Celebration.profile(tier)
				for _, step in { 1 / 60, 1 / 30, 0.25, 1.7 } do
					local bursts, gifts = sumDue(tier, step)
					eq(bursts, p.bursts, `tier {tier} bursts at step {step}`)
					eq(gifts, p.gifts, `tier {tier} gifts at step {step}`)
				end
			end
		end,
	},
}
