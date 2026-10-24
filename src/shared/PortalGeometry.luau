--!strict
-- Standing gate portals (issue #70). Pure geometry from the layout: each gate pair is two portals,
-- one per lane half. A portal is two posts and a tall banner (the lintel) facing the camera; the
-- lead walks under it. Positions are WORLD coordinates (left = negative x); the client converts
-- every x with ViewMap.x exactly once when it builds a Roblox position. Values marked [default]
-- are tuning defaults. No Roblox APIs, so Lune tests cover it; the drawing is UNVERIFIED.
local ViewMap = require("./ViewMap")

export type Op = { kind: "add" | "multiply", value: number }
export type Style = {
	postShape: "block" | "cylinder", -- adders: square posts; multipliers: round pillars
	crown: boolean, -- multipliers carry a ball finial on each round pillar; adders are flat-topped
	icon: string, -- the badge symbol on the banner, in addition to the numerals
	paletteKey: "adder" | "multiplier", -- client palette (the Oaxacan theme, issue #54, swaps it)
}
export type Portal = {
	gateId: number,
	side: "left" | "right",
	z: number,
	op: Op,
	style: Style,
	centerX: number, -- world x of the portal's centre (±halfWidth/2)
	outerWidth: number, -- the lane half-width: the two portals tile the lane
	opening: number, -- clear width between the inner faces of the posts
	postOffset: number, -- distance from centerX to each post centre
	bannerWidth: number, -- the banner spans the opening (posts hold its ends)
	bannerBottom: number,
	bannerTop: number,
	bannerCenterY: number,
	bannerCenterDz: number, -- the leaning banner's centre is this far ahead of the plane
}

local PortalGeometry = {}

PortalGeometry.POST_W = 1.6 -- [default] studs, square or round post
PortalGeometry.BANNER_BOTTOM = 7 -- [default] studs; above the lead (CameraRig.LEAD_TOP = 6)
PortalGeometry.BANNER_HEIGHT = 12 -- [default] studs, the length of the banner face
-- Issue #82: the banner leans back (top away from the camera) on a hinge at its underside, so the
-- high camera sees it far more face-on (see CameraRig.screenFraction with `lean`). The leaning top
-- is lower than a vertical one, which also keeps the camera rule easier.
PortalGeometry.LEAN = math.rad(30) -- [default]
PortalGeometry.TOP = PortalGeometry.BANNER_BOTTOM
	+ PortalGeometry.BANNER_HEIGHT * math.cos(PortalGeometry.LEAN) -- 17.4: taller than a puppet (11)
PortalGeometry.BANNER_CENTER_Y = PortalGeometry.BANNER_BOTTOM
	+ PortalGeometry.BANNER_HEIGHT / 2 * math.cos(PortalGeometry.LEAN)
PortalGeometry.BANNER_CENTER_DZ = PortalGeometry.BANNER_HEIGHT / 2 * math.sin(PortalGeometry.LEAN)
PortalGeometry.BANNER_DEPTH = 0.8 -- [default] studs along the street
PortalGeometry.FINIAL = 2.4 -- [default] diameter of a multiplier's finial ball; it ends AT TOP, so the camera rule is unchanged

-- Numerals (issue #82). The banner face is a SurfaceGui canvas (16.8 x 12 studs at PX_PER_STUD =
-- 210 x 150 px). The big line is ONE heavy rounded font, FredokaOne (a member of the Roblox Font
-- enum, verified in the Roblox docs, narrower than GothamBlack), with no "+" (the badge carries it).
-- TextScaled fits the text in its box: the em size is the smaller of the box height / LINE_FACTOR
-- and the width available / the string's glyph advance. The advance and cap ratio are ESTIMATES of
-- FredokaOne (UNVERIFIED in Studio): digits 0.62 em, "x" 0.55 em, caps 0.70 em.
-- CameraRig.screenFraction turns the cap height into a share of the screen height.
PortalGeometry.FONT = "FredokaOne"
PortalGeometry.PX_PER_STUD = 12.5 -- [default]
PortalGeometry.DIGIT_ADVANCE_EM = 0.62 -- estimate
PortalGeometry.X_ADVANCE_EM = 0.55 -- estimate
PortalGeometry.CAP_RATIO = 0.70 -- estimate: cap height / em
PortalGeometry.LINE_FACTOR = 1.15 -- estimate: text line box / em
PortalGeometry.FIT = 0.94 -- share of the width the text may use
-- The badge ("+" / "x") sits in the result row, left of the result text, never under the big line.
PortalGeometry.LABEL = table.freeze({
	opShare = 0.76,
	resultShare = 0.22,
	iconX = 0.01,
	iconW = 0.14,
	iconY = 0.76,
	resultX = 0.16,
}) -- [default]
PortalGeometry.MIN_NUMERAL_FRACTION = 0.04 -- [default] of the screen height, any pullback to 1.4

-- Horizontal advance of `text` in em.
function PortalGeometry.glyphAdvanceEm(text: string): number
	local total = 0
	for i = 1, #text do
		total += if string.sub(text, i, i) == "x"
			then PortalGeometry.X_ADVANCE_EM
			else PortalGeometry.DIGIT_ADVANCE_EM
	end
	return total
end

-- Estimated cap height in studs of the big numerals for `text` on a banner `bannerWidth` wide.
function PortalGeometry.numeralCapStuds(text: string, bannerWidth: number): number
	local byHeight = PortalGeometry.LABEL.opShare
		* PortalGeometry.BANNER_HEIGHT
		/ PortalGeometry.LINE_FACTOR
	local byWidth = bannerWidth * PortalGeometry.FIT / PortalGeometry.glyphAdvanceEm(text)
	return PortalGeometry.CAP_RATIO * math.min(byHeight, byWidth)
end

PortalGeometry.NUMERAL_STUDS = PortalGeometry.numeralCapStuds("200", 20 - 2 * PortalGeometry.POST_W) -- three characters on the standard 16.8 stud banner

local STYLES: { [string]: Style } = {
	add = table.freeze({
		postShape = "block",
		crown = false,
		icon = "+",
		paletteKey = "adder",
	} :: Style),
	multiply = table.freeze({
		postShape = "cylinder",
		crown = true,
		icon = "×",
		paletteKey = "multiplier",
	} :: Style),
}

function PortalGeometry.style(kind: string): Style
	local s = STYLES[kind]
	if s == nil then
		error(`gate op must be add or multiply, got {tostring(kind)}`, 2)
	end
	return s
end

function PortalGeometry.forGate(
	side: "left" | "right",
	halfWidth: number,
	z: number,
	op: Op,
	gateId: number?
): Portal
	local opening = halfWidth - 2 * PortalGeometry.POST_W
	return {
		gateId = gateId or 0,
		side = side,
		z = z,
		op = op,
		style = PortalGeometry.style(op.kind),
		centerX = ViewMap.gateWorldX(side, halfWidth),
		outerWidth = halfWidth,
		opening = opening,
		postOffset = opening / 2 + PortalGeometry.POST_W / 2,
		bannerWidth = opening,
		bannerBottom = PortalGeometry.BANNER_BOTTOM,
		bannerTop = PortalGeometry.TOP,
		bannerCenterY = PortalGeometry.BANNER_CENTER_Y,
		bannerCenterDz = PortalGeometry.BANNER_CENTER_DZ,
	}
end

-- Every portal of a layout, in gate order, left then right.
function PortalGeometry.all(layout: { halfWidth: number, gates: { any } }): { Portal }
	local out: { Portal } = {}
	for _, g in layout.gates do
		table.insert(out, PortalGeometry.forGate("left", layout.halfWidth, g.z, g.left, g.id))
		table.insert(out, PortalGeometry.forGate("right", layout.halfWidth, g.z, g.right, g.id))
	end
	return out
end

-- SurfaceGui canvas size in pixels for a portal's banner face.
function PortalGeometry.canvas(p: Portal): (number, number)
	return p.bannerWidth * PortalGeometry.PX_PER_STUD,
		PortalGeometry.BANNER_HEIGHT * PortalGeometry.PX_PER_STUD
end

return PortalGeometry
