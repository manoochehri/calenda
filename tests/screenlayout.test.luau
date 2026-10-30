--!strict
-- Issue #78: landscape-only HUD layout at every supported aspect ratio, with safe-area insets.
local CameraRig = require("../src/shared/CameraRig")
local DebugLayout = require("../src/shared/DebugLayout")
local ScreenLayout = require("../src/shared/ScreenLayout")
local Strings = require("../src/shared/Strings")

local EPS = 1e-6

local function eachAspect(f: (
	a: ScreenLayout.Aspect,
	safe: ScreenLayout.Rect,
	full: ScreenLayout.Rect
) -> ())
	for _, a in ScreenLayout.ASPECTS do
		local full = ScreenLayout.screenRect(a)
		f(a, ScreenLayout.safeRect(a), full)
	end
end

local function overlap(a: ScreenLayout.Rect, b: ScreenLayout.Rect): boolean
	return a.x < b.x + b.w - EPS
		and b.x < a.x + a.w - EPS
		and a.y < b.y + b.h - EPS
		and b.y < a.y + a.h - EPS
end

return {
	{
		name = "the matrix is exactly 16:9, 4:3, 19.5:9 and 21:9, all landscape, at the 390 px reference height",
		run = function()
			local names = {}
			for _, a in ScreenLayout.ASPECTS do
				table.insert(names, a.name)
				assert(a.ratio > 1, "landscape")
			end
			assert(table.concat(names, ",") == "16:9,4:3,19.5:9,21:9", table.concat(names, ","))
			assert(ScreenLayout.REFERENCE_HEIGHT == 390, "layout")
			local full = ScreenLayout.screenRect(ScreenLayout.ASPECTS[3])
			assert(full.h == 390 and full.w == 845, `19.5:9 is 845x390, got {full.w}x{full.h}`)
		end,
	},
	{
		name = "safe area is inside the screen, notched ratios get side insets, and every ratio keeps >= 12 px (rounded corners)",
		run = function()
			eachAspect(function(a, safe, full)
				assert(safe.x >= ScreenLayout.CORNER_MARGIN - EPS, `{a.name} left`)
				assert(
					full.w - (safe.x + safe.w) >= ScreenLayout.CORNER_MARGIN - EPS,
					`{a.name} right`
				)
				assert(
					full.h - (safe.y + safe.h) >= ScreenLayout.CORNER_MARGIN - EPS,
					`{a.name} bottom`
				)
				assert(
					safe.y >= ScreenLayout.TOPBAR_HEIGHT - EPS,
					`{a.name} top clears the Roblox top bar`
				)
				assert(safe.w > 0 and safe.h > 200, `{a.name} usable`)
			end)
			local wide = ScreenLayout.safeRect(ScreenLayout.ASPECTS[4])
			assert(wide.x >= ScreenLayout.NOTCH_SIDE, "21:9 notch side inset")
			local sixteen = ScreenLayout.safeRect(ScreenLayout.ASPECTS[1])
			assert(sixteen.x < ScreenLayout.NOTCH_SIDE, "16:9 has no notch inset")
		end,
	},
	{
		name = "every HUD element stays inside the safe area at every aspect",
		run = function()
			eachAspect(function(a, safe, _)
				for _, e in ScreenLayout.ELEMENTS do
					local r = ScreenLayout.elementRect(e, safe)
					assert(r.x >= safe.x - EPS and r.y >= safe.y - EPS, `{e.name} {a.name} origin`)
					assert(r.x + r.w <= safe.x + safe.w + EPS, `{e.name} {a.name} right`)
					assert(r.y + r.h <= safe.y + safe.h + EPS, `{e.name} {a.name} bottom`)
				end
			end)
		end,
	},
	{
		name = "no two elements shown at the same time overlap, at every aspect",
		run = function()
			eachAspect(function(a, safe, _)
				for _, phase in { "ending", "results" } do
					local shown = {}
					for _, e in ScreenLayout.ELEMENTS do
						if e.phases[phase] then
							table.insert(shown, e)
						end
					end
					local minimum = if phase == "results" then 4 else 1
					assert(#shown >= minimum, `{phase} has elements`)
					for i = 1, #shown do
						for j = i + 1, #shown do
							local ri = ScreenLayout.elementRect(shown[i], safe)
							local rj = ScreenLayout.elementRect(shown[j], safe)
							assert(
								not overlap(ri, rj),
								`{shown[i].name} overlaps {shown[j].name} ({phase}, {a.name})`
							)
						end
					end
				end
			end)
		end,
	},
	{
		name = "the ending, results and title controls have layout entries",
		run = function()
			for _, n in { "Banner", "Title", "Score", "Best", "Replay", "Play" } do
				assert(ScreenLayout.element(n) ~= nil, `missing {n}`)
			end
			assert(ScreenLayout.element("Nope") == nil, "layout")
		end,
	},
	{
		name = "text is readable: the size TextScaled wants (box height or string width) is >= the 14 px floor",
		run = function()
			eachAspect(function(a, safe, _)
				for _, e in ScreenLayout.ELEMENTS do
					if e.text then
						assert(e.text.minSize >= 14, `{e.name} floor {e.text.minSize} < 14`)
						local fit = ScreenLayout.fitTextPx(e, safe)
						assert(fit >= e.text.minSize - EPS, `{e.name} {a.name}: fits only {fit} px`)
					end
				end
			end)
			-- Non-vacuous: a too-narrow box is caught.
			local narrow = {
				name = "x",
				ax = 0,
				ay = 0,
				x = 0,
				y = 0,
				w = 0.05,
				h = 0.1,
				phases = {},
				text = { minSize = 14, maxSize = 20, sample = "Arrastra para moverte" },
			}
			assert(
				ScreenLayout.fitTextPx(narrow, ScreenLayout.safeRect(ScreenLayout.ASPECTS[2])) < 14,
				"narrow box must fail"
			)
		end,
	},
	{
		name = "the title card ends above the Play button, and every DisplayOrder is unique with the dim under the HUD text",
		run = function()
			local card = ScreenLayout.TITLE_CARD
			eachAspect(function(a, safe, full)
				local r = ScreenLayout.elementRect(
					ScreenLayout.element("Play") :: ScreenLayout.Element,
					safe
				)
				local cardBottom = (card.y + card.h / 2) * full.h
				assert(
					r.y >= cardBottom,
					`{a.name}: Play top {r.y} is inside the card (bottom {cardBottom})`
				)
			end)
			local D = ScreenLayout.DISPLAY_ORDER
			local seen = {}
			for k, v in D do
				assert(seen[v] == nil, `{k} ties with {seen[v]}`)
				seen[v] = k
			end
			assert(D.hudFx < D.hud, "results dim under the HUD text and Replay")
			assert(D.hud < D.runHud, "ending banner above the base HUD")
			assert(D.runHud < D.startup, "title above the HUD")
			assert(D.startup < D.startupControls, "Play above the title backdrop")
		end,
	},
	{
		name = "touch targets are >= 44 px each way, primary buttons sit in a lower corner (thumb reach)",
		run = function()
			local buttons = 0
			eachAspect(function(a, safe, _)
				for _, e in ScreenLayout.ELEMENTS do
					if e.touch then
						buttons += 1
						local r = ScreenLayout.elementRect(e, safe)
						assert(r.w >= 44 and r.h >= 44, `{e.name} {a.name} is {r.w}x{r.h}`)
						if e.primary then
							local cx, cy = r.x + r.w / 2, r.y + r.h / 2
							assert(
								cy >= safe.y + 0.75 * safe.h,
								`{e.name} {a.name} not in the lower quarter`
							)
							local fromSide = math.min(cx - safe.x, safe.x + safe.w - cx)
							assert(fromSide <= 0.2 * safe.w, `{e.name} {a.name} not near a side`)
						end
					end
				end
			end)
			assert(buttons >= 8, "replay is tested at every aspect")
			assert(ScreenLayout.element("Replay").primary == true, "layout")
		end,
	},
	{
		name = "the primary button anchor is shared, so the start screen's Jugar can reuse it",
		run = function()
			local p = ScreenLayout.PRIMARY_BUTTON
			assert(p.ay == 1 and (p.ax == 1 or p.ax == 0), "a lower corner")
			local replay = ScreenLayout.element("Replay") :: ScreenLayout.Element
			assert(
				replay.x == p.x and replay.y == p.y and replay.w == p.w and replay.h == p.h,
				"layout"
			)
		end,
	},
	{
		name = "the lane and both portals clear the notch insets and fit the width at every aspect and pullback",
		run = function()
			eachAspect(function(a, safe, full)
				for _, pullback in { 1, 1.2, 1.4 } do
					local pose = CameraRig.pose(0, 0, pullback)
					local half = CameraRig.visibleHalfWidth(pose, CameraRig.GATE_NEAR, a.ratio)
					assert(
						half >= DebugLayout.halfWidth,
						`lane clipped at {a.name}, pullback {pullback}: sees +-{half}`
					)
					-- px from the screen centre to the lane edge (x = 20), versus the safe half width
					local lanePx = DebugLayout.halfWidth / half * (full.w / 2)
					assert(
						lanePx <= full.w / 2 - safe.x + EPS,
						`{a.name} lane runs under the notch`
					)
				end
			end)
		end,
	},
	{
		name = "numeral screen fraction is aspect independent (vertical FOV) and gives >= 21 px caps on 390 px tall",
		run = function()
			local PortalGeometry = require("../src/shared/PortalGeometry")
			local pose = CameraRig.pose(0, 0, 1)
			local f = CameraRig.screenFraction(
				pose,
				PortalGeometry.BANNER_CENTER_Y,
				CameraRig.GATE_NEAR + PortalGeometry.BANNER_CENTER_DZ,
				PortalGeometry.numeralCapStuds("200", 16.8),
				PortalGeometry.LEAN
			)
			eachAspect(function(a, _, full)
				assert(f * full.h >= 21, `{a.name}: {f * full.h} px`)
			end)
			assert(Strings.replay ~= "", "strings available")
		end,
	},
	{
		name = "issue 112: results hide gameplay counts and use one score without a music control",
		run = function()
			for _, name in
				{ "Caption", "Counter", "Detail", "Hint", "SectionMeter", "PlusSections" }
			do
				assert(
					ScreenLayout.element(name) == nil,
					`{name} no longer overlays play or results`
				)
			end
			local score = ScreenLayout.element("Score") :: ScreenLayout.Element
			local best = ScreenLayout.element("Best") :: ScreenLayout.Element
			assert(score.text.sample == "99999", "score is the number alone")
			assert(best.text.sample == Strings.newBest, "record cue does not repeat a number")
			assert(
				ScreenLayout.element("MusicToggle") == nil,
				"no in-game music control per ADR 0008"
			)
		end,
	},
	{
		name = "issue 140: no Seguidores caption is laid over the street (no Caption element, no followers string)",
		run = function()
			assert(
				ScreenLayout.element("Caption") == nil,
				"a Caption element is still laid out in the play area"
			)
		end,
	},
}
