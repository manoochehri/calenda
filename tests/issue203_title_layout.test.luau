--!strict
-- Issues #203 and #211: the title's left column (logo, subtitle, loading) sits inside the safe area
-- at every supported aspect ratio, without overlapping. The avatar now stands in the world (no box)
-- and the PROTOTIPO footer is gone. Element rects are fractions of the FULL screen.
local okTitle, TitleLayout = pcall(require, "../src/shared/TitleLayout")
local ScreenLayout = require("../src/shared/ScreenLayout")

local EPS = 1e-6

local function rect(name: string, a: ScreenLayout.Aspect): ScreenLayout.Rect
	assert(okTitle, `TitleLayout module missing: {tostring(TitleLayout)}`)
	local e = TitleLayout.element(name)
	assert(e, `no TitleLayout element {name}`)
	return ScreenLayout.elementRect(e :: ScreenLayout.Element, ScreenLayout.screenRect(a))
end

local function overlap(a: ScreenLayout.Rect, b: ScreenLayout.Rect): boolean
	return a.x < b.x + b.w - EPS
		and b.x < a.x + a.w - EPS
		and a.y < b.y + b.h - EPS
		and b.y < a.y + a.h - EPS
end

local LEFT = { "Logo", "Subtitle", "Loading" }

return {
	{
		name = "the layout has Banner, Logo, Subtitle and Loading",
		run = function()
			assert(okTitle, `TitleLayout module missing: {tostring(TitleLayout)}`)
			for _, n in { "Banner", "Logo", "Subtitle", "Loading" } do
				assert(TitleLayout.element(n), `missing element {n}`)
			end
		end,
	},
	{
		name = "the title column sits in the left half at every aspect",
		run = function()
			for _, a in ScreenLayout.ASPECTS do
				local full = ScreenLayout.screenRect(a)
				for _, n in LEFT do
					local r = rect(n, a)
					assert(r.x + r.w / 2 < full.w / 2, `{a.name}: {n} is not on the left`)
				end
			end
		end,
	},
	{
		name = "everything sits inside the safe area sideways and on screen",
		run = function()
			for _, a in ScreenLayout.ASPECTS do
				local safe = ScreenLayout.safeRect(a)
				for _, n in { "Logo", "Subtitle", "Loading" } do
					local r = rect(n, a)
					assert(r.x >= safe.x - EPS, `{a.name}: {n} left of the safe area`)
					assert(r.x + r.w <= safe.x + safe.w + EPS, `{a.name}: {n} right of safe`)
					assert(
						r.y + r.h <= ScreenLayout.screenRect(a).h + EPS,
						`{a.name}: {n} below the screen`
					)
				end
			end
		end,
	},
	{
		name = "left-column elements do not overlap one another or the banner",
		run = function()
			for _, a in ScreenLayout.ASPECTS do
				local names = { "Banner", "Logo", "Subtitle", "Loading" }
				for i = 1, #names do
					for j = i + 1, #names do
						assert(
							not overlap(rect(names[i], a), rect(names[j], a)),
							`{a.name}: {names[i]} overlaps {names[j]}`
						)
					end
				end
			end
		end,
	},
	{
		name = "the logo is readable (>= 24 px) at every aspect",
		run = function()
			assert(okTitle, `TitleLayout module missing: {tostring(TitleLayout)}`)
			for _, a in ScreenLayout.ASPECTS do
				local full = ScreenLayout.screenRect(a)
				local logo = TitleLayout.element("Logo") :: ScreenLayout.Element
				local px = ScreenLayout.fitTextPx(logo, full)
				assert(px >= 24, `{a.name}: logo fits at {px} px`)
			end
		end,
	},
	{
		name = "the countdown numeral is centred and on screen at every aspect",
		run = function()
			assert(okTitle, `TitleLayout module missing: {tostring(TitleLayout)}`)
			local c = TitleLayout.COUNTDOWN
			assert(c, "COUNTDOWN element")
			for _, a in ScreenLayout.ASPECTS do
				local full = ScreenLayout.screenRect(a)
				local r = ScreenLayout.elementRect(c, full)
				assert(math.abs(r.x + r.w / 2 - full.w / 2) < 1, `{a.name}: not centred`)
				assert(r.y >= 0 and r.y + r.h <= full.h, `{a.name}: off screen`)
			end
		end,
	},
	{
		name = "the PROTOTIPO footer and the avatar box are gone from the layout",
		run = function()
			assert(TitleLayout.element("Version") == nil, "footer remains")
			assert(TitleLayout.element("AvatarSlot") == nil, "avatar box remains")
		end,
	},
}
