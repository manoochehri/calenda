--!strict
-- Issue #70: standing gate portals. Pure geometry from the layout; the client only draws it.
local CameraRig = require("../src/shared/CameraRig")
local DebugLayout = require("../src/shared/DebugLayout")
local PortalGeometry = require("../src/shared/PortalGeometry")
local ViewMap = require("../src/shared/ViewMap")

local ADD = { kind = "add", value = 20 }
local MUL = { kind = "multiply", value = 2 }
local firstGateZ = DebugLayout.gates[1].z

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
			assert(
				PortalGeometry.TOP >= 2.5 * CameraRig.LEAD_TOP,
				"at least two and a half lead heights"
			)
			local g = PortalGeometry.forGate("right", 20, 192, ADD)
			assert(g.bannerTop == PortalGeometry.TOP, "descriptor top")
			assert(
				math.abs(
					g.bannerTop
						- g.bannerBottom
						- PortalGeometry.BANNER_HEIGHT * math.cos(PortalGeometry.LEAN)
				) < 1e-9,
				"leaning banner height"
			)
			assert(math.abs(g.bannerCenterY - (g.bannerBottom + g.bannerTop) / 2) < 1e-9, "centre")
			assert(g.bannerCenterDz > 0, "the banner leans back, away from the camera")
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
				first.gateId == 1 and first.side == "left" and first.z == firstGateZ,
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
		name = "the big line drops the plus (the badge carries it) and keeps the multiplier x",
		run = function()
			local GateLabel = require("../src/shared/GateLabel")
			assert(GateLabel.big({ kind = "add", value = 20 }) == "20", "adder is just the number")
			assert(GateLabel.big({ kind = "multiply", value = 3 }) == "x3", "multiplier keeps x")
			assert(not pcall(GateLabel.big, { kind = "loss", value = 1 }), "bad op")
		end,
	},
	{
		name = "numeral cap height is estimated from the font advance, the line box and the banner width",
		run = function()
			local w = 16.8
			local three = PortalGeometry.numeralCapStuds("200", w)
			local four = PortalGeometry.numeralCapStuds("x100", w)
			local two = PortalGeometry.numeralCapStuds("20", w)
			assert(four < three, "four characters are width-limited and smaller")
			assert(two >= three - 1e-9, "never smaller with fewer characters")
			assert(
				PortalGeometry.glyphAdvanceEm("200") > PortalGeometry.glyphAdvanceEm("20"),
				"advance"
			)
			assert(PortalGeometry.FONT == "FredokaOne", "heavy rounded font")
			assert(
				PortalGeometry.NUMERAL_STUDS == three,
				"NUMERAL_STUDS is the 3 character cap height"
			)
		end,
	},
	{
		name = "numerals (landscape 16:9, 4:3, 19.5:9, 21:9): >= 5.5% of the screen height at pullback 1, never under 4%",
		run = function()
			local strings = { "15", "20", "30", "40", "50", "80", "100", "200", "x2", "x3", "999" }
			local worst: { [number]: number } = {}
			for _, pullback in { 1, 1.2, 1.4 } do
				local pose = CameraRig.pose(0, 0, pullback)
				for _, text in strings do
					local cap = PortalGeometry.numeralCapStuds(text, 16.8)
					local f = CameraRig.screenFraction(
						pose,
						PortalGeometry.BANNER_CENTER_Y,
						CameraRig.GATE_NEAR + PortalGeometry.BANNER_CENTER_DZ,
						cap,
						PortalGeometry.LEAN
					)
					worst[pullback] = math.min(worst[pullback] or 1, f)
				end
				-- The whole lane (both portals) must fit the screen WIDTH at the nearest row.
				local depthZ = CameraRig.GATE_NEAR - pose.pz
				for _, aspect in { 16 / 9, 4 / 3, 19.5 / 9, 21 / 9 } do
					local halfVisible = depthZ
						* math.tan(math.rad(CameraRig.FIELD_OF_VIEW / 2))
						* aspect
					assert(
						halfVisible >= 20,
						`lane clipped at aspect {aspect}, pullback {pullback}`
					)
				end
			end
			assert(worst[1] >= 0.055, `pullback 1 worst {worst[1]}`)
			assert(worst[1.2] >= 0.045, `pullback 1.2 worst {worst[1.2]}`)
			assert(worst[1.4] >= 0.04, `pullback 1.4 worst {worst[1.4]}`)
			-- 19.5:9 phone in landscape is 390 px tall: the pixel height of the cap at pullback 1.
			assert(worst[1] * 390 >= 21, "at least 21 px caps on a 390 px tall screen")
			assert(PortalGeometry.MIN_NUMERAL_FRACTION >= 0.04, "stated floor")
		end,
	},
	{
		name = "a four digit-width string like x100 is still readable (>= 4% at pullback 1)",
		run = function()
			local pose = CameraRig.pose(0, 0, 1)
			local f = CameraRig.screenFraction(
				pose,
				PortalGeometry.BANNER_CENTER_Y,
				CameraRig.GATE_NEAR + PortalGeometry.BANNER_CENTER_DZ,
				PortalGeometry.numeralCapStuds("x100", 16.8),
				PortalGeometry.LEAN
			)
			assert(f >= 0.04, `x100 {f}`)
		end,
	},
	{
		name = "the badge sits in the result row and cannot overlap the big numerals",
		run = function()
			local L = PortalGeometry.LABEL
			assert(L.iconY >= L.opShare - 1e-9, "badge starts below the operation line")
			assert(
				L.iconX + L.iconW <= L.resultX + 1e-9,
				"badge ends before the result text starts"
			)
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
			assert(w == 210 and h == 150, "the real canvas is 210x150")
		end,
	},
}
