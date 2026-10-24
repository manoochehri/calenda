--!strict
local CrowdMath = require("../src/shared/CrowdMath")
local SectionRegistry = require("../src/shared/SectionRegistry")
local SectionTypes = require("../src/shared/SectionTypes")
local VisualBudget = require("../src/shared/VisualBudget")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

return {
	{
		name = "registry: register and get by CrowdMath section type; unknown types are rejected",
		run = function()
			local r = SectionRegistry.new() :: SectionRegistry.Registry<string>
			eq(r:has("puppet"), false, "empty")
			r:register("puppet", "P")
			eq(r:get("puppet"), "P", "get")
			eq(r:get("globo"), nil, "unregistered type is nil, not an error")
			local ok = pcall(function()
				r:register("tuba" :: any, "x")
			end)
			eq(ok, false, "unknown type rejected")
			local twice = pcall(function()
				r:register("puppet", "again")
			end)
			eq(twice, false, "double registration rejected")
		end,
	},
	{
		name = "registry: every type in the CrowdMath sequence is registrable (globo/dancers plug in later)",
		run = function()
			local r = SectionRegistry.new() :: SectionRegistry.Registry<number>
			for i = 1, 3 do
				r:register(CrowdMath.sectionType(i), i)
			end
			eq(r:get("puppet"), 1, "puppet")
			eq(r:get("globo"), 2, "globo")
			eq(r:get("dancers"), 3, "dancers")
		end,
	},
	{
		name = "section types: puppet is described, with a small entourage that adds no followers",
		run = function()
			local puppet = SectionTypes.descriptors:get("puppet")
			assert(puppet ~= nil, "puppet descriptor")
			assert(puppet.entourage >= 1 and puppet.entourage <= 5, "small entourage")
			eq(puppet.addsFollowers, false, "entourage adds no followers")
			-- The visual plan is a function of the total only: an entourage cannot change it.
			local plan = VisualBudget.allocate(120)
			eq(plan.looseCount, 20, "loose count unchanged by entourage")
			eq(plan.total, 120, "total unchanged")
		end,
	},
	{
		name = "section types: globo (issue #19) is registered at sequence index 1 and emits decorative rings",
		run = function()
			eq(SectionTypes.sequenceIndex("puppet"), 0, "puppet index")
			eq(SectionTypes.sequenceIndex("globo"), 1, "globo is the second section: index 1")
			eq(SectionTypes.sequenceIndex("dancers"), 2, "dancers index")
			eq(CrowdMath.sectionType(2), "globo", "the 2nd logical section is a globo")
			eq(VisualBudget.allocate(100).representatives[2].sectionType, "globo", "rep 2 at 100")
			local globo = SectionTypes.descriptors:get("globo")
			assert(globo ~= nil, "globo must be registered")
			eq(globo.emitsRings, true, "rings on the beat")
			eq(globo.tossesGifts, false, "globos do not toss gifts")
			eq(globo.addsFollowers, false, "carriers and rings never recruit or add followers")
			assert(globo.entourage >= 2 and globo.entourage <= 6, "visible carriers")
		end,
	},
	{
		name = "section types: dancers (issue #20) are registered and are the only gift tossers",
		run = function()
			local dancers = SectionTypes.descriptors:get("dancers")
			assert(dancers ~= nil, "dancers must be registered")
			eq(dancers.tossesGifts, true, "dancers toss gifts")
			eq(dancers.emitsRings, false, "dancers do not emit rings")
			eq(dancers.addsFollowers, false, "dancers add no followers")
			for i = 1, 3 do
				local d = SectionTypes.descriptors:get(CrowdMath.sectionType(i))
				assert(d ~= nil, `type {i} registered`)
				eq(d.addsFollowers, false, "no entourage adds followers")
				eq(d.tossesGifts, CrowdMath.sectionType(i) == "dancers", "only dancers toss")
				eq(d.emitsRings, CrowdMath.sectionType(i) == "globo", "only globos emit rings")
			end
		end,
	},
}
