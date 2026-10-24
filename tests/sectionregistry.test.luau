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
}
