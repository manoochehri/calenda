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
}

local PortalGeometry = {}

PortalGeometry.POST_W = 1.6 -- [default] studs, square or round post
PortalGeometry.BANNER_BOTTOM = 7 -- [default] studs; above the lead (CameraRig.LEAD_TOP = 6)
PortalGeometry.BANNER_HEIGHT = 12 -- [default] studs
PortalGeometry.TOP = PortalGeometry.BANNER_BOTTOM + PortalGeometry.BANNER_HEIGHT -- 19: taller than a puppet (11)
PortalGeometry.BANNER_CENTER_Y = PortalGeometry.BANNER_BOTTOM + PortalGeometry.BANNER_HEIGHT / 2
PortalGeometry.BANNER_DEPTH = 0.8 -- [default] studs along the street
PortalGeometry.FINIAL = 2.4 -- [default] diameter of a multiplier's finial ball; it ends AT TOP, so the camera rule is unchanged

-- Numerals. The banner face is a SurfaceGui canvas at PX_PER_STUD; the operation line gets opShare
-- of the height (big), the result line resultShare (smaller). A glyph's cap height is about 72% of
-- the line box, and the width of four characters ("x100", "+200") limits the box, so the numerals
-- come out near NUMERAL_STUDS tall. CameraRig.screenFraction turns that into a share of the screen
-- height at the nearest row (GATE_NEAR ahead): MIN_NUMERAL_FRACTION is the floor kept at every
-- pullback up to 1.4 (about 12 px on a 390 px tall landscape phone, 25 px in portrait), the pulse
-- and the approach make it bigger as the row nears.
PortalGeometry.PX_PER_STUD = 12.5 -- [default]
PortalGeometry.LABEL = table.freeze({ opShare = 0.66, resultShare = 0.3 }) -- [default]
PortalGeometry.NUMERAL_STUDS = 5.5 -- [default] cap height of the big numerals
PortalGeometry.MIN_NUMERAL_FRACTION = 0.03 -- [default] of the screen height, at the nearest row

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
