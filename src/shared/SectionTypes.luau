--!strict
-- Pure per-type facts about sections (issues #14, #19, #20; spec s7, s8). The three types of the
-- repeating sequence puppet -> globo -> dancers each register one descriptor here and one builder
-- in the client's SectionsView; nothing else changes when a type is added.
local CrowdMath = require("./CrowdMath")
local SectionRegistry = require("./SectionRegistry")

export type Descriptor = {
	entourage: number, -- decorative companions drawn beside one representative (carriers, a chorus)
	addsFollowers: boolean, -- always false: entourages, rings and gifts are decoration (spec s8)
	emitsRings: boolean, -- decorative musical rings on the beat (globo); rings never recruit
	tossesGifts: boolean, -- present means every 4th shot is a gift (dancers; Targeting.shotKind)
}

local descriptors = SectionRegistry.new() :: SectionRegistry.Registry<Descriptor>
descriptors:register("puppet", {
	entourage = 3, -- [default] spec: "small"
	addsFollowers = false,
	emitsRings = false,
	tossesGifts = false,
})
descriptors:register("globo", {
	entourage = 4, -- [default] four visible carriers around the pole
	addsFollowers = false,
	emitsRings = true, -- spec s7: "Emit decorative musical rings on the beat"
	tossesGifts = false,
})
descriptors:register("dancers", {
	entourage = 2, -- [default] a lead and two more dancers: three coordinated steppers
	addsFollowers = false,
	emitsRings = false,
	tossesGifts = true, -- spec s7: "Toss occasional gifts in place of note shots"
})

-- 0-based position of a type in the repeating sequence: puppet 0, globo 1, dancers 2.
local function sequenceIndex(sectionType: CrowdMath.SectionType): number
	for i = 1, 3 do
		if CrowdMath.sectionType(i) == sectionType then
			return i - 1
		end
	end
	error(`unknown section type {tostring(sectionType)}`, 2)
end

return {
	descriptors = descriptors,
	sequenceIndex = sequenceIndex,
}
