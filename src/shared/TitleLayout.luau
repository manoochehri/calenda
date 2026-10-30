--!strict
-- Issue #176: the title card's element layout as pure data, so the start screen's placement is
-- tested at every aspect ratio (tests/issue176_title.test.luau). Positions are fractions of the
-- CARD, which itself is ScreenLayout.TITLE_CARD (a fraction of the full screen). The Play button
-- is not here: it is ScreenLayout's primary button, in the lower safe corner.
-- Shape matches ScreenLayout.Element, so ScreenLayout.elementRect and fitTextPx apply directly.
local ScreenLayout = require("./ScreenLayout")

local TitleLayout = {}

local TITLE = table.freeze({ title = true })

-- Element order is the top-to-bottom reading order of the card.
TitleLayout.ELEMENTS = table.freeze({
	table.freeze({
		name = "Logo",
		phases = TITLE,
		ax = 0.5,
		ay = 0,
		x = 0.5,
		y = 0.15,
		w = 0.9,
		h = 0.2,
		text = table.freeze({ minSize = 24, maxSize = 96, sample = "CALENDA" }),
	} :: ScreenLayout.Element),
	table.freeze({
		name = "Subtitle",
		phases = TITLE,
		ax = 0.5,
		ay = 0,
		x = 0.5,
		y = 0.39,
		w = 0.86,
		h = 0.08,
		text = table.freeze({
			minSize = 14,
			maxSize = 28,
			sample = "Música, fiesta y una gran calenda",
		}),
	} :: ScreenLayout.Element),
	table.freeze({
		name = "Loading",
		phases = TITLE,
		ax = 0.5,
		ay = 0,
		x = 0.5,
		y = 0.53,
		w = 0.72,
		h = 0.17,
	} :: ScreenLayout.Element),
	table.freeze({
		name = "Version",
		phases = TITLE,
		ax = 0.5,
		ay = 1,
		x = 0.5,
		y = 0.91,
		w = 0.36,
		h = 0.06,
		text = table.freeze({ minSize = 10, maxSize = 14, sample = "PROTOTIPO" }),
	} :: ScreenLayout.Element),
})

function TitleLayout.element(name: string): ScreenLayout.Element?
	for _, e in TitleLayout.ELEMENTS do
		if e.name == name then
			return e
		end
	end
	return nil
end

return TitleLayout
