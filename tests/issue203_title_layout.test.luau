--!strict
-- Issue #203: the title screen puts the title on the left and the player's marching avatar slot
-- on the right, at every supported aspect ratio. Element rects are fractions of the FULL screen.
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

local LEFT = { "Logo", "Subtitle", "Loading", "Version" }

return {
	{
		name = "the layout has Banner, Logo, Subtitle, Loading, AvatarSlot and Version",
		run = function()
			assert(okTitle, `TitleLayout module missing: {tostring(TitleLayout)}`)
			for _, n in { "Banner", "Logo", "Subtitle", "Loading", "AvatarSlot", "Version" } do
				assert(TitleLayout.element(n), `missing element {n}`)
			end
		end,
	},
	{
		name = "title elements are entirely left of the avatar slot at every aspect",
		run = function()
			for _, a in ScreenLayout.ASPECTS do
				local slot = rect("AvatarSlot", a)
				for _, n in LEFT do
					local r = rect(n, a)
					assert(r.x + r.w <= slot.x + EPS, `{a.name}: {n} reaches the avatar slot`)
					assert(r.x + r.w / 2 < slot.x, `{a.name}: {n} is not left of the slot`)
				end
				local full = ScreenLayout.screenRect(a)
				assert(slot.x + slot.w / 2 > full.w / 2, `{a.name}: slot is not on the right`)
			end
		end,
	},
	{
		name = "everything sits inside the safe area sideways, and the slot clears Play",
		run = function()
			for _, a in ScreenLayout.ASPECTS do
				local safe = ScreenLayout.safeRect(a)
				local play = ScreenLayout.elementRect(
					ScreenLayout.element("Play") :: ScreenLayout.Element,
					safe
				)
				for _, n in { "Logo", "Subtitle", "Loading", "AvatarSlot", "Version" } do
					local r = rect(n, a)
					assert(r.x >= safe.x - EPS, `{a.name}: {n} left of the safe area`)
					assert(r.x + r.w <= safe.x + safe.w + EPS, `{a.name}: {n} right of safe`)
					assert(
						r.y + r.h <= ScreenLayout.screenRect(a).h + EPS,
						`{a.name}: {n} below the screen`
					)
				end
				local slot = rect("AvatarSlot", a)
				assert(slot.y + slot.h <= play.y + EPS, `{a.name}: slot runs into Play`)
			end
		end,
	},
	{
		name = "left-column elements do not overlap one another or the banner or the slot",
		run = function()
			for _, a in ScreenLayout.ASPECTS do
				local names = { "Banner", "Logo", "Subtitle", "Loading", "Version", "AvatarSlot" }
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
		name = "the logo is readable (>= 24 px) and the footer at least 10 px at every aspect",
		run = function()
			assert(okTitle, `TitleLayout module missing: {tostring(TitleLayout)}`)
			for _, a in ScreenLayout.ASPECTS do
				local full = ScreenLayout.screenRect(a)
				local logo = TitleLayout.element("Logo") :: ScreenLayout.Element
				local px = ScreenLayout.fitTextPx(logo, full)
				assert(px >= 24, `{a.name}: logo fits at {px} px`)
				local ver = TitleLayout.element("Version") :: ScreenLayout.Element
				assert(ScreenLayout.fitTextPx(ver, full) >= 10, `{a.name}: footer too small`)
			end
		end,
	},
	{
		name = "the avatar slot is at least 120 px wide and tall at every aspect",
		run = function()
			for _, a in ScreenLayout.ASPECTS do
				local slot = rect("AvatarSlot", a)
				assert(slot.w >= 120 and slot.h >= 120, `{a.name}: slot {slot.w}x{slot.h}`)
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
}
