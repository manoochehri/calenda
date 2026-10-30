--!strict
-- Issues #176 and #203: the title screen's element layout as pure data, so the start screen's
-- placement is tested at every aspect ratio (tests/issue203_title_layout.test.luau).
-- Positions are fractions of the FULL screen (the title ScreenGui covers it). The title (logo,
-- subtitle, loading) is the left column; the player's marching avatar slot is the right column;
-- the papel picado banner runs across the top and PROTOTIPO is a small footer. The Play button
-- is not here: it is ScreenLayout's primary button, in the lower safe corner, under the slot.
-- Shape matches ScreenLayout.Element, so ScreenLayout.elementRect and fitTextPx apply directly.
local ScreenLayout = require("./ScreenLayout")

local TitleLayout = {}

local TITLE = table.freeze({ title = true })

TitleLayout.ELEMENTS = table.freeze({
	table.freeze({
		name = "Banner",
		phases = TITLE,
		ax = 0,
		ay = 0,
		x = 0,
		y = 0,
		w = 1,
		h = 0.13,
	} :: ScreenLayout.Element),
	table.freeze({
		name = "Logo",
		phases = TITLE,
		ax = 0,
		ay = 0,
		x = 0.06,
		y = 0.2,
		w = 0.5,
		h = 0.24,
		text = table.freeze({ minSize = 24, maxSize = 110, sample = "CALENDA" }),
	} :: ScreenLayout.Element),
	table.freeze({
		name = "Subtitle",
		phases = TITLE,
		ax = 0,
		ay = 0,
		x = 0.06,
		y = 0.46,
		w = 0.54,
		h = 0.1,
		text = table.freeze({
			minSize = 14,
			maxSize = 28,
			sample = "Música, fiesta y una gran calenda",
			widthShare = 0.5, -- wraps onto two lines
		}),
	} :: ScreenLayout.Element),
	table.freeze({
		name = "Loading",
		phases = TITLE,
		ax = 0,
		ay = 0,
		x = 0.06,
		y = 0.62,
		w = 0.46,
		h = 0.17,
	} :: ScreenLayout.Element),
	table.freeze({
		name = "AvatarSlot",
		phases = TITLE,
		ax = 1,
		ay = 0,
		x = 0.94,
		y = 0.16,
		w = 0.32,
		h = 0.5,
	} :: ScreenLayout.Element),
	table.freeze({
		name = "Version",
		phases = TITLE,
		ax = 0,
		ay = 1,
		x = 0.06,
		y = 0.97,
		w = 0.2,
		h = 0.05,
		text = table.freeze({ minSize = 10, maxSize = 14, sample = "PROTOTIPO" }),
	} :: ScreenLayout.Element),
})

-- The countdown numeral, centred over the street (shown after Jugar, over the game camera).
TitleLayout.COUNTDOWN = table.freeze({
	name = "Countdown",
	phases = table.freeze({ title = true }),
	ax = 0.5,
	ay = 0.5,
	x = 0.5,
	y = 0.42,
	w = 0.3,
	h = 0.4,
	text = table.freeze({ minSize = 48, maxSize = 160, sample = "tres" }),
} :: ScreenLayout.Element)

function TitleLayout.element(name: string): ScreenLayout.Element?
	for _, e in TitleLayout.ELEMENTS do
		if e.name == name then
			return e
		end
	end
	return nil
end

return TitleLayout
