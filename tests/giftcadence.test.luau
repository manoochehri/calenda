--!strict
-- Issue #20: the gift cadence (spec s4, s7). The pure rule is Targeting.shotKind; these tests pin it
-- to how the game derives "a dancer section is present" (CrowdMath/VisualBudget/SectionTypes),
-- including more than three logical sections and a dancer present only from the third section, and
-- show a gift is exactly one hit, never an extra reward.
local Config = require("../src/shared/Config")
local CrowdMath = require("../src/shared/CrowdMath")
local Level = require("../src/shared/Level")
local RunState = require("../src/shared/RunState")
local SectionTypes = require("../src/shared/SectionTypes")
local Targeting = require("../src/shared/Targeting")
local VisualBudget = require("../src/shared/VisualBudget")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function kinds(sectionCount: number, from: number, to: number): string
	local out = {}
	for n = from, to do
		table.insert(out, Targeting.shotKind(n, sectionCount))
	end
	return table.concat(out, ",")
end

local function layoutOf(clusters: { Level.Cluster }): Level.Layout
	return {
		name = "t",
		seed = 0,
		streetLength = 1600,
		plazaStart = 1440,
		halfWidth = 20,
		leadLimit = 15,
		maxTotal = 1000,
		intendedRecruitTotal = 0,
		gates = {},
		obstacles = {},
		clusters = clusters,
	}
end

-- One large cluster right ahead of the lead; runs a session at a fixed sectionCount. `config` may
-- be a modified copy of Config (giftEveryNthShot huge = a notes-only baseline at the same fire rate).
local function runLarge(sectionCount: number, config: any?): ({ any }, number, number)
	local layout = layoutOf({
		{
			id = 1,
			wave = 1,
			type = "large",
			spawnTime = 0,
			spawn = { x = 10, z = 30 },
			path = {},
			lane = "right",
		},
	})
	local rs = RunState.new({
		seed = 1,
		automated = true,
		layout = {
			gatePairs = {},
			clusters = { { id = "1", type = "large" } },
			obstacles = {},
		},
		now = function()
			return 0
		end,
	})
	local session = Targeting.new({ layout = layout, runState = rs, config = config })
	local shots: { any } = {}
	local credits = 0
	local t = 0.0
	while t <= 5 do
		for _, s in session:advance(t, sectionCount, "right").shots do
			if s.miss then
				continue -- continuous fire: misses are display only (they still count as shots)
			end
			table.insert(shots, s)
			if s.credit ~= nil then
				credits += 1
			end
		end
		t += 1 / 60
	end
	return shots, credits, rs:total()
end

return {
	{
		name = "no dancer section means no gifts: 0, 1 and 2 logical sections give 24 notes",
		run = function()
			for sections = 0, 2 do
				eq(kinds(sections, 1, 24), string.rep("note,", 23) .. "note", `{sections} sections`)
			end
		end,
	},
	{
		name = "with a dancer section every 4th shot is a gift: 3 sections, six gifts in 24 shots",
		run = function()
			eq(kinds(3, 1, 8), "note,note,note,gift,note,note,note,gift", "first eight")
			local gifts = 0
			for n = 1, 24 do
				if Targeting.shotKind(n, 3) == "gift" then
					gifts += 1
					eq(n % Config.giftEveryNthShot, 0, "only multiples of the cadence")
				end
			end
			eq(gifts, 6, "six gifts in 24")
		end,
	},
	{
		name = "more than three logical sections keep the same cadence (4, 5, 6, 7, 40)",
		run = function()
			for _, sections in { 4, 5, 6, 7, 9, 40 } do
				eq(
					kinds(sections, 1, 8),
					"note,note,note,gift,note,note,note,gift",
					`{sections} sections`
				)
			end
		end,
	},
	{
		name = "presence follows the section sequence: the dancer is the 3rd section, from total 150",
		run = function()
			local function hasDancerRep(total: number): boolean
				for _, r in VisualBudget.allocate(total).representatives do
					if r.sectionType == "dancers" then
						return true
					end
				end
				return false
			end
			for _, total in { 0, 49, 50, 99, 100, 149 } do
				eq(hasDancerRep(total), false, `no dancer rep at {total}`)
				eq(Targeting.shotKind(4, CrowdMath.sectionCount(total)), "note", `note at {total}`)
			end
			for _, total in { 150, 151, 199, 200, 2000 } do
				eq(hasDancerRep(total), true, `dancer rep at {total}`)
				eq(Targeting.shotKind(4, CrowdMath.sectionCount(total)), "gift", `gift at {total}`)
			end
			eq(
				VisualBudget.allocate(150).representatives[3].sectionType,
				"dancers",
				"3rd is dancers"
			)
		end,
	},
	{
		name = "cadence is derived from the registry: gifts exactly when a section that tosses gifts exists",
		run = function()
			for sections = 0, 12 do
				local present = false
				for i = 1, sections do
					local d = SectionTypes.descriptors:get(CrowdMath.sectionType(i))
					if d ~= nil and d.tossesGifts then
						present = true
					end
				end
				eq(
					Targeting.shotKind(4, sections) == "gift",
					present,
					`{sections} sections: tossing section present`
				)
			end
		end,
	},
	{
		name = "with 2000 followers: 40 logical sections, six representatives, gift cadence unchanged",
		run = function()
			local plan = VisualBudget.allocate(2000)
			eq(plan.logicalSections, 40, "logical sections")
			eq(#plan.representatives, 6, "six representatives")
			eq(Targeting.shotKind(4, plan.logicalSections), "gift", "gift")
			eq(Targeting.shotKind(5, plan.logicalSections), "note", "note")
			eq(Targeting.fireRate(plan.logicalSections), 20, "rate capped by logical sections")
		end,
	},
	{
		name = "the cadence follows the session shot number, and a lost dancer section stops gifts at once",
		run = function()
			eq(Targeting.shotKind(4, 3), "gift", "4th with dancers")
			eq(Targeting.shotKind(8, 2), "note", "8th after the crowd fell below 150")
			eq(Targeting.shotKind(12, 3), "gift", "12th after it came back")
			eq(Targeting.shotKind(5, 3), "note", "no catch-up gifts")
		end,
	},
	{
		name = "a gift is one hit like a note: same shots to fill, same credit once, same reward",
		run = function()
			local notesOnly = table.clone(Config)
			notesOnly.giftEveryNthShot = 1e9
			local plain, plainCredits, plainTotal = runLarge(3, notesOnly)
			local gifty, giftCredits, giftTotal = runLarge(3)
			eq(#plain, Config.clusterTypes.large.hits, "notes fill in the cluster's hits")
			eq(#gifty, Config.clusterTypes.large.hits, "gifts fill in the same hits")
			eq(plainCredits, 1, "credited once (notes)")
			eq(giftCredits, 1, "credited once (gifts)")
			eq(giftTotal, plainTotal, "same total, so no extra reward")
			eq(giftTotal, Config.startingTotal + Config.clusterTypes.large.reward, "start + reward")
			local giftCount = 0
			for i, s in gifty do
				eq(s.hits, plain[i].hits, `hit value of shot {i}`)
				eq(s.targetId, plain[i].targetId, `target of shot {i}`)
				if s.kind == "gift" then
					giftCount += 1
				end
			end
			eq(giftCount, 2, "shots 4 and 8 of 8 are gifts")
			eq(gifty[8].kind, "gift", "the filling shot may be a gift")
			eq(gifty[8].filled, true, "and still fills once")
		end,
	},
}
