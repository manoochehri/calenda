--!strict
-- Icon and meter data that keeps the HUD readable with the sound off (spec s3, issue #16). Pure.
local Config = require("./Config")
local CrowdMath = require("./CrowdMath")
local RunView = require("./RunView")
local Strings = require("./Strings")

export type SectionMeter = {
	sections: number, -- logical sections (exact)
	loose: number, -- loose followers (exact)
	fraction: number, -- 0..1 toward the next section
	toNext: number, -- followers still needed for the next section
	label: string, -- "Próxima sección en 30"
}

local HudMeters = {}

function HudMeters.sectionMeter(total: number): SectionMeter
	local whole = RunView.wholeTotal(total)
	local loose = CrowdMath.looseFollowers(whole)
	return {
		sections = CrowdMath.sectionCount(whole),
		loose = loose,
		fraction = loose / Config.sectionSize,
		toNext = Config.sectionSize - loose,
		label = Strings.nextSectionIn(Config.sectionSize - loose),
	}
end

return HudMeters
