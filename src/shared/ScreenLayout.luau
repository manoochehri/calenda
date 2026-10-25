--!strict
-- Issue #78: landscape is the only supported orientation (docs/landscape.md). Pure model of the
-- supported aspect ratios, the safe area (notches, rounded corners, Roblox top bar) and the HUD
-- layout, so the layout is tested at every ratio instead of eyeballed on one emulator.
-- Rects are in pixels at REFERENCE_HEIGHT (a 390 px tall landscape phone); HUD elements are
-- placed in fractions of the SAFE rect, which is what a ScreenGui with ScreenInsets =
-- CoreUISafeInsets gives (its 0..1 space is the safe area). The inset VALUES are estimates
-- (UNVERIFIED on devices): see the Studio checklist in the PR.
local Strings = require("./Strings")

local ScreenLayout = {}

export type Aspect = { name: string, ratio: number, notched: boolean }
export type Rect = { x: number, y: number, w: number, h: number }
export type Phases = { run: boolean?, results: boolean? }
export type TextSpec = {
	minSize: number, -- UITextSizeConstraint.MinTextSize, px
	maxSize: number, -- UITextSizeConstraint.MaxTextSize, px
	sample: string, -- the longest realistic string, for the width check
	heightShare: number?, -- share of the element height the text box gets (default 1)
	widthShare: number?, -- share of the element width the text box gets (default 1)
}
export type Element = {
	name: string,
	ax: number, -- AnchorPoint
	ay: number,
	x: number, -- Position, fraction of the safe rect
	y: number,
	w: number, -- Size, fraction of the safe rect
	h: number,
	phases: Phases, -- when it is on screen: during the run, on the results panel
	text: TextSpec?,
	touch: boolean?, -- a button: >= MIN_TOUCH px each way
	primary: boolean?, -- a primary button: must sit in a lower corner
}

ScreenLayout.REFERENCE_HEIGHT = 390 -- px; the realistic landscape phone height
ScreenLayout.CORNER_MARGIN = 12 -- [default] px kept clear on every side for rounded corners
ScreenLayout.NOTCH_SIDE = 47 -- [default] px each side on a notched phone (landscape cutout)
ScreenLayout.HOME_BAR = 21 -- [default] px at the bottom on a notched phone
ScreenLayout.TOPBAR_HEIGHT = 44 -- [default] px the Roblox top bar and cutout take at the top
ScreenLayout.MIN_TEXT = 14 -- px floor for any HUD text
ScreenLayout.MIN_TOUCH = 44 -- px, each way
ScreenLayout.GLYPH_EM = 0.62 -- estimate: average advance of a bold sans glyph, in em

ScreenLayout.ASPECTS = table.freeze({
	table.freeze({ name = "16:9", ratio = 16 / 9, notched = false } :: Aspect),
	table.freeze({ name = "4:3", ratio = 4 / 3, notched = false } :: Aspect),
	table.freeze({ name = "19.5:9", ratio = 19.5 / 9, notched = true } :: Aspect),
	table.freeze({ name = "21:9", ratio = 21 / 9, notched = true } :: Aspect),
})

function ScreenLayout.screenRect(a: Aspect): Rect
	return {
		x = 0,
		y = 0,
		w = math.floor(ScreenLayout.REFERENCE_HEIGHT * a.ratio + 0.5),
		h = ScreenLayout.REFERENCE_HEIGHT,
	}
end

-- The area a ScreenGui with ScreenInsets = CoreUISafeInsets covers.
function ScreenLayout.safeRect(a: Aspect): Rect
	local full = ScreenLayout.screenRect(a)
	local side = if a.notched then ScreenLayout.NOTCH_SIDE else ScreenLayout.CORNER_MARGIN
	local bottom = if a.notched then ScreenLayout.HOME_BAR else ScreenLayout.CORNER_MARGIN
	local top = ScreenLayout.TOPBAR_HEIGHT
	return { x = side, y = top, w = full.w - 2 * side, h = full.h - top - bottom }
end

local function el(
	name: string,
	ax: number,
	ay: number,
	x: number,
	y: number,
	w: number,
	h: number,
	phases: Phases,
	text: TextSpec?
): Element
	return {
		name = name,
		ax = ax,
		ay = ay,
		x = x,
		y = y,
		w = w,
		h = h,
		phases = phases,
		text = text,
	}
end

local RUN = { run = true }
local BOTH = { run = true, results = true }
local RESULTS = { results = true }

-- The primary button, shared so the start screen's "Jugar" (issue #72) reuses the same corner.
ScreenLayout.PRIMARY_BUTTON = table.freeze({ ax = 1, ay = 1, x = 1, y = 1, w = 0.28, h = 0.17 })

local replay = el("Replay", 1, 1, 1, 1, 0.28, 0.17, RESULTS, {
	minSize = 14,
	maxSize = 32,
	sample = "¡Otra calenda!",
})
replay.touch = true
replay.primary = true

-- Top row: HP bar left, crowd counter centre, "+N secciones" right. The centre column below the
-- counter holds the meter; the middle of the screen is left to the street and the portals.
local ELEMENTS = {
	el(
		"MusicToggle",
		1,
		0,
		1,
		0,
		0.22,
		0.15,
		BOTH,
		{ minSize = 14, maxSize = 24, sample = Strings.musicOn }
	),
	el(
		"HpBar",
		0,
		0,
		0,
		0,
		0.22,
		0.10,
		BOTH,
		{ minSize = 14, maxSize = 26, sample = "100/100", heightShare = 0.7, widthShare = 0.8 }
	),
	el(
		"Caption",
		0.5,
		0,
		0.5,
		0,
		0.30,
		0.07,
		BOTH,
		{ minSize = 14, maxSize = 24, sample = "Seguidores" }
	),
	el(
		"Counter",
		0.5,
		0,
		0.5,
		0.07,
		0.40,
		0.17,
		BOTH,
		{ minSize = 14, maxSize = 72, sample = "99999" }
	),
	el(
		"Detail",
		0.5,
		0,
		0.5,
		0.24,
		0.50,
		0.07,
		BOTH,
		{ minSize = 14, maxSize = 24, sample = "Sueltos 20 · Secciones 12" }
	),
	el(
		"PlusSections",
		1,
		0,
		1,
		0.17,
		0.24,
		0.09,
		RUN,
		{ minSize = 14, maxSize = 32, sample = "+99 secciones" }
	),
	el(
		"SectionMeter",
		0.5,
		0,
		0.5,
		0.33,
		0.50,
		0.10,
		RUN,
		{ minSize = 14, maxSize = 28, sample = "Próxima sección en 30" }
	),
	el(
		"Banner",
		0.5,
		0,
		0.5,
		0.46,
		0.70,
		0.14,
		RUN,
		{ minSize = 14, maxSize = 72, sample = "¡Calenda legendaria!" }
	),
	el(
		"Hint",
		0.5,
		0,
		0.5,
		0.82,
		0.40,
		0.10,
		RUN,
		{ minSize = 14, maxSize = 32, sample = "Arrastra para moverte" }
	),
	el(
		"Title",
		0.5,
		0,
		0.5,
		0.34,
		0.70,
		0.12,
		RESULTS,
		{ minSize = 14, maxSize = 72, sample = "¡Calenda completada!" }
	),
	el(
		"Score",
		0.5,
		0,
		0.5,
		0.48,
		0.50,
		0.09,
		RESULTS,
		{ minSize = 14, maxSize = 48, sample = "Puntos: 99999" }
	),
	el(
		"Best",
		0.5,
		0,
		0.5,
		0.58,
		0.40,
		0.07,
		RESULTS,
		{ minSize = 14, maxSize = 32, sample = "Mejor: 99999" }
	),
	replay,
}
for _, e in ELEMENTS do
	if e.name == "MusicToggle" then
		e.touch = true
	end
end
ScreenLayout.ELEMENTS = table.freeze(ELEMENTS)

function ScreenLayout.element(name: string): Element?
	for _, e in ScreenLayout.ELEMENTS do
		if e.name == name then
			return e
		end
	end
	return nil
end

-- Pixel rect of an element inside `safe` (accounts for the anchor point).
function ScreenLayout.elementRect(e: Element, safe: Rect): Rect
	local w, h = e.w * safe.w, e.h * safe.h
	return {
		x = safe.x + e.x * safe.w - e.ax * w,
		y = safe.y + e.y * safe.h - e.ay * h,
		w = w,
		h = h,
	}
end

-- Estimated width in px of `text` at `size` px.
function ScreenLayout.textWidthPx(text: string, size: number): number
	return (utf8.len(text) or #text) * ScreenLayout.GLYPH_EM * size
end

-- Size TextScaled settles on: the box height, held between the min and max constraints.
function ScreenLayout.effectiveTextPx(e: Element, safe: Rect): number
	local t = e.text :: TextSpec
	local boxH = ScreenLayout.elementRect(e, safe).h * (t.heightShare or 1)
	return math.clamp(boxH, t.minSize, t.maxSize)
end

return ScreenLayout
