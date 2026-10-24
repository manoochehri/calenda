--!strict
-- How big the section figures stand in the parade (issue #68). Pure. Puppets and globos TOWER over
-- the crowd that surrounds their bases; dancers stand a little above it. Heights are the figure's
-- tallest point at scale 1 (mirrors PuppetFigure.HEIGHT and GloboFigure's pole, sphere and knob);
-- the view multiplies a figure's scale by `scaleOf`. CameraRig.TALLEST_PROP must cover `tallest()`.
local Config = require("./Config")
local FollowerSlots = require("./FollowerSlots")

local SectionScale = {}

SectionScale.HEIGHT_AT_ONE = table.freeze({
	puppet = 11, -- PuppetFigure.HEIGHT
	globo = 16.5, -- GloboFigure: SPHERE_Y 11.5 + radius 3.75 + knob
	dancers = 8.3, -- DancerFigure: flower at 7.5 plus its size
})
SectionScale.TYPE_SCALE = table.freeze({
	puppet = 1.75, -- [default] about 19 studs: tall over a 2-stud follower
	globo = 1.3, -- [default] the sphere rides about 15 studs up on its pole
	dancers = 1.35, -- [default]
})
SectionScale.VARIATION = 0.08 -- [default] +- share of size variation per figure

-- Size multiplier of representative `index` (stable per index).
function SectionScale.scaleOf(sectionType: string, index: number): number
	local base = SectionScale.TYPE_SCALE[sectionType]
	if base == nil then
		error(`unknown section type {tostring(sectionType)}`, 2)
	end
	return base * (1 + (FollowerSlots.unit(index, 51) * 2 - 1) * SectionScale.VARIATION)
end

function SectionScale.heightOf(sectionType: string, index: number): number
	return SectionScale.HEIGHT_AT_ONE[sectionType] * SectionScale.scaleOf(sectionType, index)
end

-- Tallest figure any representative can reach (largest variation included).
function SectionScale.tallest(): number
	local tallest = 0
	for i = 1, Config.visualBudget.sectionRepresentatives do
		for t in SectionScale.TYPE_SCALE do
			tallest = math.max(tallest, SectionScale.heightOf(t, i))
		end
	end
	return tallest
end

return SectionScale
