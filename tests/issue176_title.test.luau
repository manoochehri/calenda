--!strict
-- Issue #176: the title card's element layout is pure data (src/shared/TitleLayout), so it is
-- checked at every supported aspect ratio instead of eyeballed in Studio.
local okTitle, TitleLayout = pcall(require, "../src/shared/TitleLayout")
local ScreenLayout = require("../src/shared/ScreenLayout")

local EPS = 1e-6

local function playRect(a: ScreenLayout.Aspect): ScreenLayout.Rect
	local play = ScreenLayout.element("Play") :: ScreenLayout.Element
	return ScreenLayout.elementRect(play, ScreenLayout.safeRect(a))
end

return {
	{
		name = "the title screen has the named elements it places (issue #211 drops the avatar box and footer)",
		run = function()
			assert(okTitle, `TitleLayout module missing: {tostring(TitleLayout)}`)
			local names = {}
			for _, e in TitleLayout.ELEMENTS do
				table.insert(names, e.name)
			end
			assert(
				table.concat(names, ",") == "Banner,Logo,Subtitle,Loading",
				table.concat(names, ",")
			)
		end,
	},
	{
		name = "Play is a touch-sized button at every aspect",
		run = function()
			for _, a in ScreenLayout.ASPECTS do
				local play = playRect(a)
				assert(play.w >= ScreenLayout.MIN_TOUCH - EPS, `{a.name} Play width {play.w}`)
				assert(play.h >= ScreenLayout.MIN_TOUCH - EPS, `{a.name} Play height {play.h}`)
			end
		end,
	},
}
