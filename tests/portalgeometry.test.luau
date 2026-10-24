--!strict
-- Issue #70: standing gate portals. Pure geometry from the layout; the client only draws it.
local CameraRig = require("../src/shared/CameraRig")
local DebugLayout = require("../src/shared/DebugLayout")
local PortalGeometry = require("../src/shared/PortalGeometry")
local ViewMap = require("../src/shared/ViewMap")

local ADD = { kind = "add", value = 20 }
local MUL = { kind = "multiply", value = 2 }

return {
	{
		name = "two portals tile the lane: left half negative x, right half positive x, mirrored",
		run = function()
			local l = PortalGeometry.forGate("left", 20, 192, ADD)
			local r = PortalGeometry.forGate("right", 20, 192, MUL)
			assert(l.centerX < 0 and r.centerX > 0, "left is negative world x")
			assert(l.centerX == -r.centerX, "mirrored about the centre line")
			assert(l.outerWidth == 20 and r.outerWidth == 20, "each spans the lane half-width")
			assert(l.centerX + l.outerWidth / 2 == 0, "left half ends at the centre line")
			assert(r.centerX - r.outerWidth / 2 == 0, "right half starts at the centre line")
		end,
	},
	{
		name = "the opening is the lane half-width less the two posts, and wider than the lead",
		run = function()
			local g = PortalGeometry.forGate("left", 20, 192, ADD)
			assert(g.opening == 20 - 2 * PortalGeometry.POST_W, "opening")
			assert(g.opening >= 0.8 * 20, "opening is nearly the whole half")
			assert(g.opening > 3 * 3, "far wider than the lead's hitbox")
			assert(g.postOffset == g.opening / 2 + PortalGeometry.POST_W / 2, "post centres")
		end,
	},
	{
		name = "the banner is clearly taller than the lead and the crowd, and the lead walks under it",
		run = function()
			assert(PortalGeometry.BANNER_BOTTOM > CameraRig.LEAD_TOP, "lead fits under the banner")
			assert(PortalGeometry.TOP > 11, "taller than the 11 stud puppet (PuppetFigure.HEIGHT)")
			assert(PortalGeometry.TOP >= 3 * CameraRig.LEAD_TOP, "at least three lead heights")
			local g = PortalGeometry.forGate("right", 20, 192, ADD)
			assert(g.bannerTop == PortalGeometry.TOP, "descriptor top")
			assert(g.bannerTop - g.bannerBottom == PortalGeometry.BANNER_HEIGHT, "banner height")
			assert(g.bannerCenterY == (g.bannerBottom + g.bannerTop) / 2, "centre")
		end,
	},
	{
		name = "adders and multipliers differ in SHAPE and symbol, not only color",
		run = function()
			local a = PortalGeometry.style("add")
			local m = PortalGeometry.style("multiply")
			assert(a.postShape ~= m.postShape, "post shape")
			assert(a.crown ~= m.crown, "crown")
			assert(a.icon ~= m.icon, "icon")
			assert(a.paletteKey ~= m.paletteKey, "palette")
			assert(not pcall(PortalGeometry.style, "loss"), "unknown kind rejected")
			local g = PortalGeometry.forGate("left", 20, 192, MUL)
			assert(g.style.crown == true and g.style.postShape == m.postShape, "descriptor uses it")
		end,
	},
	{
		name = "all builds one descriptor per gate and side from the layout, ops and z kept",
		run = function()
			local all = PortalGeometry.all(DebugLayout)
			assert(#all == 2 * #DebugLayout.gates, "two portals per pair")
			local first = all[1]
			assert(
				first.gateId == 1 and first.side == "left" and first.z == 192,
				"first is gate 1 left"
			)
			assert(first.op.kind == "add" and first.op.value == 15, "gate 1 left is +15")
			assert(all[2].side == "right" and all[2].op.kind == "multiply", "gate 1 right is x2")
		end,
	},
	{
		name = "the left op draws on the screen's left (ViewMap mirror, applied once)",
		run = function()
			local l = PortalGeometry.forGate("left", 20, 192, ADD)
			-- CameraRig looks along +Z: screen-left is Roblox +X, so the drawn x must be positive.
			assert(ViewMap.x(l.centerX) > 0, "left portal draws at +X = screen-left")
			assert(
				ViewMap.x(l.centerX - l.postOffset) > ViewMap.x(l.centerX + l.postOffset),
				"posts too"
			)
		end,
	},
	{
		name = "numerals are sized from CameraRig: >= 3% of the screen height at the nearest row, all pullbacks",
		run = function()
			for _, pullback in { 1, 1.2, 1.4 } do
				local pose = CameraRig.pose(0, 0, pullback)
				local f = CameraRig.screenFraction(
					pose,
					PortalGeometry.BANNER_CENTER_Y,
					CameraRig.GATE_NEAR,
					PortalGeometry.NUMERAL_STUDS
				)
				assert(f >= PortalGeometry.MIN_NUMERAL_FRACTION, `pullback {pullback}: {f}`)
			end
			local pose = CameraRig.pose(0, 0, 1)
			local studs = CameraRig.studsForScreenFraction(
				pose,
				PortalGeometry.BANNER_CENTER_Y,
				CameraRig.GATE_NEAR,
				0.04
			)
			assert(PortalGeometry.NUMERAL_STUDS >= studs, "at least 4% at the default pullback")
		end,
	},
	{
		name = "label layout: result line is smaller than the operation line, canvas matches the banner",
		run = function()
			local L = PortalGeometry.LABEL
			assert(L.opShare > L.resultShare, "operation is the big line")
			assert(L.opShare + L.resultShare <= 1, "both lines fit")
			local g = PortalGeometry.forGate("left", 20, 192, ADD)
			local w, h = PortalGeometry.canvas(g)
			assert(math.abs(w / h - g.bannerWidth / PortalGeometry.BANNER_HEIGHT) < 1e-6, "aspect")
			assert(w == g.bannerWidth * PortalGeometry.PX_PER_STUD, "px per stud")
		end,
	},
}
