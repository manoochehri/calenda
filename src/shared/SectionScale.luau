--!strict
-- How big the section figures stand in the parade (issue #68). Pure. Puppets and globos TOWER over
-- the crowd that surrounds their bases; dancers stand a little above it. Heights are the figure's
-- tallest point at scale 1 (mirrors PuppetFigure.HEIGHT and GloboFigure's pole, sphere and knob);
-- the view multiplies a figure's scale by `scaleOf`. CameraRig.SECTION_TALLEST must cover `tallest()`.
local Config = require("./Config")
local DancerPose = require("./DancerPose")
local FollowerSlots = require("./FollowerSlots")
local GloboPose = require("./GloboPose")
local SectionTypes = require("./SectionTypes")

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
SectionScale.ENTOURAGE_RADIUS = 1.1 -- [default] studs: puppet companions ring (SectionFigure)
SectionScale.GLOBO_CARRIER_FACTOR = 0.25 -- [default] carriers hug the pole (GloboFigure)
SectionScale.DANCER_SPREAD = 0.2 -- [default] dancers stand close together (DancerFigure)
SectionScale.DECOR_HALF = 0.6 -- [default] half width of a companion figure
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

-- Radius of the ground area a section occupies around its base: the companion ring plus a companion's
-- half width. Followers must stay clear of this (plus their own body, sway and spring overshoot).
function SectionScale.footprint(sectionType: string, index: number): number
	local scale = SectionScale.scaleOf(sectionType, index)
	local ring = 0
	if sectionType == "puppet" then
		ring = SectionScale.ENTOURAGE_RADIUS
	elseif sectionType == "globo" then
		ring = GloboPose.CARRIER_RADIUS * scale * SectionScale.GLOBO_CARRIER_FACTOR
	else
		local d = SectionTypes.descriptors:get(sectionType :: any)
		local n = if d then d.entourage + 1 else 1
		for _, slot in DancerPose.formation(n) do
			ring = math.max(
				ring,
				math.sqrt(slot.dx ^ 2 + slot.dz ^ 2) * scale * SectionScale.DANCER_SPREAD
			)
		end
	end
	return ring + SectionScale.DECOR_HALF
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
