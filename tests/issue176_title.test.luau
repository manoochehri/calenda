--!strict
-- Issue #176: the title card's element layout is pure data (src/shared/TitleLayout), so it is
-- checked at every supported aspect ratio instead of eyeballed in Studio.
local okTitle, TitleLayout = pcall(require, "../src/shared/TitleLayout")
local ScreenLayout = require("../src/shared/ScreenLayout")

local EPS = 1e-6
local UNIT = { x = 0, y = 0, w = 1, h = 1 }

local function cardRect(a: ScreenLayout.Aspect): ScreenLayout.Rect
	local full = ScreenLayout.screenRect(a)
	local tc = ScreenLayout.TITLE_CARD
	local w, h = tc.w * full.w, tc.h * full.h
	return { x = tc.x * full.w - w / 2, y = tc.y * full.h - h / 2, w = w, h = h }
end

local function overlap(a: ScreenLayout.Rect, b: ScreenLayout.Rect): boolean
	return a.x < b.x + b.w - EPS
		and b.x < a.x + a.w - EPS
		and a.y < b.y + b.h - EPS
		and b.y < a.y + a.h - EPS
end

local function playRect(a: ScreenLayout.Aspect): ScreenLayout.Rect
	local play = ScreenLayout.element("Play") :: ScreenLayout.Element
	return ScreenLayout.elementRect(play, ScreenLayout.safeRect(a))
end

return {
	{
		name = "the title card has the named elements the screen places: Logo, Subtitle, Loading, Version",
		run = function()
			assert(okTitle, `TitleLayout module missing: {tostring(TitleLayout)}`)
			local names = {}
			for _, e in TitleLayout.ELEMENTS do
				table.insert(names, e.name)
			end
			assert(
				table.concat(names, ",") == "Logo,Subtitle,Loading,Version",
				table.concat(names, ",")
			)
		end,
	},
	{
		name = "every title element sits inside the card at every aspect",
		run = function()
			assert(okTitle, `TitleLayout module missing: {tostring(TitleLayout)}`)
			for _, a in ScreenLayout.ASPECTS do
				for _, e in TitleLayout.ELEMENTS do
					local r = ScreenLayout.elementRect(e, UNIT)
					assert(r.x >= -EPS and r.y >= -EPS, `{e.name} {a.name} origin`)
					assert(r.x + r.w <= 1 + EPS, `{e.name} {a.name} right`)
					assert(r.y + r.h <= 1 + EPS, `{e.name} {a.name} bottom`)
				end
			end
		end,
	},
	{
		name = "stacked title elements do not overlap one another",
		run = function()
			assert(okTitle, `TitleLayout module missing: {tostring(TitleLayout)}`)
			for i, e in TitleLayout.ELEMENTS do
				for j = i + 1, #TitleLayout.ELEMENTS do
					local other = TitleLayout.ELEMENTS[j]
					local a = ScreenLayout.elementRect(e, UNIT)
					local b = ScreenLayout.elementRect(other, UNIT)
					assert(not overlap(a, b), `{e.name} overlaps {other.name}`)
				end
			end
		end,
	},
	{
		name = "the card ends above the Play button at every aspect (Play never covers the title)",
		run = function()
			for _, a in ScreenLayout.ASPECTS do
				local card = cardRect(a)
				local play = playRect(a)
				assert(
					card.y + card.h <= play.y + EPS,
					`{a.name}: card bottom {card.y + card.h} past Play top {play.y}`
				)
			end
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
	{
		name = "the logo text is readable (>= 24 px) inside its box at every aspect",
		run = function()
			assert(okTitle, `TitleLayout module missing: {tostring(TitleLayout)}`)
			local logo = nil
			for _, e in TitleLayout.ELEMENTS do
				if e.name == "Logo" then
					logo = e
				end
			end
			assert(logo and logo.text, "Logo element with a text spec")
			for _, a in ScreenLayout.ASPECTS do
				local px = ScreenLayout.fitTextPx(logo :: ScreenLayout.Element, cardRect(a))
				assert(px >= 24, `{a.name} logo fits at {px} px`)
			end
		end,
	},
}
