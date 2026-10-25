--!strict
-- Issue #104: typography and contrast tokens. Checks the choices, not the rendering (UNVERIFIED
-- until the Studio check in the PR).
local UiType = require("../src/shared/UiType")

local function isVerified(name: string): boolean
	for _, v in UiType.VERIFIED_FONTS do
		if v == name then
			return true
		end
	end
	return false
end

local function inRange(v: number, lo: number, hi: number): boolean
	return v >= lo and v <= hi
end

return {
	{
		name = "every font role maps to a verified Enum.Font name",
		run = function()
			for role, name in UiType.FONT do
				assert(isVerified(name), `{role} uses unverified font {name}`)
			end
		end,
	},
	{
		name = "the font roles match the issue: titles, numbers, buttons, subtext",
		run = function()
			assert(UiType.FONT.title == "LuckiestGuy", "title font")
			assert(
				UiType.FONT.number == "Bangers" and UiType.FONT.alert == "Bangers",
				"number font"
			)
			assert(UiType.FONT.button == "FredokaOne", "button font")
			assert(UiType.FONT.body == "GothamBold", "body font")
		end,
	},
	{
		name = "the outline is 3 to 5 px and dark (every channel under 64)",
		run = function()
			assert(inRange(UiType.STROKE_THICKNESS, 3, 5), `thickness {UiType.STROKE_THICKNESS}`)
			for _, c in UiType.STROKE_RGB do
				assert(c < 64, `stroke channel {c}`)
			end
		end,
	},
	{
		name = "the title gradient runs #FFE600 (top) to #FF9900 (bottom)",
		run = function()
			assert(UiType.TITLE_TOP_RGB[1] == 255 and UiType.TITLE_TOP_RGB[2] == 230, "top")
			assert(UiType.TITLE_TOP_RGB[3] == 0, "top blue")
			assert(
				UiType.TITLE_BOTTOM_RGB[1] == 255 and UiType.TITLE_BOTTOM_RGB[2] == 153,
				"bottom"
			)
			assert(UiType.TITLE_BOTTOM_RGB[3] == 0, "bottom blue")
		end,
	},
	{
		name = "the backing is semi-transparent (between 0.2 and 0.5) with a rounded corner",
		run = function()
			assert(inRange(UiType.BACKING_TRANSPARENCY, 0.2, 0.5), "transparency")
			assert(UiType.BACKING_CORNER_PX > 0, "corner")
		end,
	},
	{
		name = "primary buttons are pills (scale 0.5)",
		run = function()
			assert(UiType.PILL_SCALE == 0.5, "pill scale")
		end,
	},
}
