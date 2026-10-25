--!strict
-- Issue #104: typography and contrast tokens for on-screen text. Pure data so the choices are
-- tested in Lune; src/client/TypeStyle.luau applies them to the Roblox instances.
-- Font values are Enum.Font member names. VERIFIED_FONTS are the names confirmed on the Roblox
-- Enum.Font reference (https://create.roblox.com/docs/reference/engine/enums/Font, checked
-- 2026-10-24). How they render on a phone is UNVERIFIED until the Studio checklist in the PR.
local UiType = {}

UiType.VERIFIED_FONTS = table.freeze({ "LuckiestGuy", "FredokaOne", "Bangers", "GothamBold" })

UiType.FONT = table.freeze({
	title = "LuckiestGuy", -- titles, popups, the defeat line
	number = "Bangers", -- HUD numbers and fast alerts
	alert = "Bangers",
	button = "FredokaOne", -- buttons
	body = "GothamBold", -- subtext
})

-- Dark purple-brown outline on every main text label, thickness in pixels (3 to 5).
UiType.STROKE_THICKNESS = 4
UiType.STROKE_RGB = table.freeze({ 38, 22, 30 })

-- Vertical title gradient, top to bottom (#FFE600 to #FF9900).
UiType.TITLE_TOP_RGB = table.freeze({ 255, 230, 0 })
UiType.TITLE_BOTTOM_RGB = table.freeze({ 255, 153, 0 })

-- Semi-transparent rounded backing behind floating world text.
UiType.BACKING_RGB = table.freeze({ 30, 20, 30 })
UiType.BACKING_TRANSPARENCY = 0.35
UiType.BACKING_CORNER_PX = 10

-- Primary buttons are pills: a corner radius of half the height.
UiType.PILL_SCALE = 0.5

return UiType
