--!strict
-- Data-driven level theme (issue #54 phase 1, spec s8/s10). Pure: no Roblox APIs, no Color3 (colors
-- are {r,g,b} 0..255 tables the client converts). Level 1 is the Oaxacan street; later levels
-- (#57: pueblo, playa) are another table of the same shape, not a rewrite. See
-- docs/art-brief-level-1.md for the words behind every value. Values are tuning defaults.
-- Coordinates are WORLD x (left = negative); the client applies ViewMap.x when it builds Parts.
local CameraRig = require("./CameraRig")
local PortalGeometry = require("./PortalGeometry")

local LevelTheme = {}

-- Tallest standing thing in the play corridor the dressing must stay above: the gate portal (and a
-- puppet, 11). Not CameraRig.TALLEST_PROP, so the theme survives the crowd PR (#76) splitting it.
LevelTheme.PROP_TOP = math.max(16, PortalGeometry.TOP)

export type Rgb = { r: number, g: number, b: number }

export type FacadeStyle = { name: string, wall: Rgb, trim: Rgb, accent: Rgb, weight: number }
export type FlagLane = { x: number, y: number } -- |x| and center height; mirrored to both sides

export type Theme = {
	name: string,
	palette: {
		ground: Rgb, -- the plain earth plate around everything (Backdrop)
		road: Rgb,
		roadAlt: Rgb,
		sidewalk: Rgb,
		forecourt: Rgb,
		curb: Rgb,
		stone: Rgb,
		plazaPaving: Rgb,
		plazaPavingAlt: Rgb,
		iron: Rgb,
		lampGlass: Rgb,
		lampLight: Rgb,
		glass: Rgb,
		trunk: Rgb,
		foliage: Rgb,
		foliageAlt: Rgb,
		kioscoBase: Rgb,
		kioscoRoof: Rgb,
		cathedral: Rgb,
		flagCord: Rgb,
	},
	flagColors: { Rgb },
	facades: { FacadeStyle },
	-- Colors the gameplay already uses (CrowdView, WorldBuilder gates). Copied, not imported: the
	-- client files need Roblox services. Keep in step by hand; contrast tests guard the theme side.
	gameplay: {
		follower: Rgb,
		lead: Rgb,
		ring: Rgb,
		gateLeft: Rgb,
		gateRight: Rgb,
		adderBanner: Rgb,
		multiplierBanner: Rgb,
		spectator: Rgb,
	},
	materials: { wall: string, stone: string, road: string, ground: string, plaza: string },
	lighting: {
		clockTime: number,
		brightness: number,
		ambient: Rgb,
		outdoorAmbient: Rgb,
		colorShiftTop: Rgb,
		colorShiftBottom: Rgb,
		shadowSoftness: number,
		exposureCompensation: number,
		environmentDiffuseScale: number,
		environmentSpecularScale: number,
		atmosphere: {
			density: number,
			offset: number,
			color: Rgb,
			decay: Rgb,
			glare: number,
			haze: number,
		},
	},
	budgets: {
		maxFacadeParts: number,
		maxFlagStrips: number,
		maxFlagCells: number,
		maxLamps: number, -- each lamp is 2 parts (pole + lantern)
		maxLights: number, -- PointLights only on some lamps
		maxPlazaParts: number,
		maxGroundParts: number,
		maxGuiInstances: number, -- Frames/UIStroke/UICorner inside facade SurfaceGuis
	},
	heights: { facadeMin: number, facadeMax: number, roofExtra: number, lampHeight: number },
	layout: {
		facadeInset: number, -- |x| of a facade's street-side face
		facadeDepth: number,
		moduleWidthMin: number,
		moduleWidthMax: number,
		runIn: number, -- studs of street behind z = 0 (matches Backdrop.RUN_IN)
		endExtra: number, -- studs of street past streetLength
		floorHeight: number,
		flagLanes: { FlagLane },
		flagHeight: number,
		flagPitch: number, -- studs per flag cell
		flagStripLength: number,
		lampX: number,
		lampSpacing: number,
		curbX: number, -- |x| of the curb stripe centre, just inside the road edge (halfWidth - 6)
		courses: number, -- lengthwise flagstone courses across the road
	},
}

function LevelTheme.rgb(r: number, g: number, b: number): Rgb
	return table.freeze({ r = r, g = g, b = b })
end
local rgb = LevelTheme.rgb

-- WCAG relative luminance of an sRGB color (0..255 channels).
function LevelTheme.luminance(c: Rgb): number
	local function lin(v: number): number
		local s = v / 255
		return if s <= 0.03928 then s / 12.92 else ((s + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
end

-- WCAG contrast ratio, 1..21, symmetric.
function LevelTheme.contrast(a: Rgb, b: Rgb): number
	local la, lb = LevelTheme.luminance(a), LevelTheme.luminance(b)
	if la < lb then
		la, lb = lb, la
	end
	return (la + 0.05) / (lb + 0.05)
end

LevelTheme.level1 = {
	name = "oaxaca-street-1",
	palette = {
		ground = rgb(170, 140, 100),
		road = rgb(56, 51, 50), -- warm dark flagstone: followers/gates/lead stand out (>=3:1 vs ground)
		roadAlt = rgb(70, 64, 63), -- alternate course, a subtle step (>=3:1 vs ground)
		sidewalk = rgb(205, 196, 172), -- pale cantera
		forecourt = rgb(178, 168, 146),
		curb = rgb(244, 194, 44), -- yellow curb stripe
		stone = rgb(184, 194, 166), -- grey-green cantera
		plazaPaving = rgb(196, 152, 104),
		plazaPavingAlt = rgb(176, 134, 92),
		iron = rgb(30, 28, 30),
		lampGlass = rgb(255, 214, 130),
		lampLight = rgb(255, 200, 120),
		glass = rgb(40, 52, 70),
		trunk = rgb(96, 70, 50),
		foliage = rgb(60, 130, 70),
		foliageAlt = rgb(84, 152, 82),
		kioscoBase = rgb(230, 222, 205),
		kioscoRoof = rgb(200, 90, 60),
		cathedral = rgb(205, 185, 150),
		flagCord = rgb(50, 40, 40),
	},
	-- Dark jewel tones on purpose: a light flag cannot reach 3:1 against the pale sky, and a dark
	-- one is needed to keep 2:1 against the lavender wall. Hue carries the distinction.
	flagColors = {
		rgb(120, 44, 78), -- pink
		rgb(120, 51, 3), -- orange
		rgb(87, 69, 27), -- yellow (dark gold)
		rgb(27, 81, 50), -- green
		rgb(31, 72, 119), -- blue
		rgb(91, 55, 122), -- purple
	},
	facades = {
		{
			name = "ochre",
			wall = rgb(232, 172, 58),
			trim = rgb(250, 242, 226),
			accent = rgb(60, 48, 44),
			weight = 3,
		},
		{
			name = "terracotta",
			wall = rgb(204, 88, 56),
			trim = rgb(250, 242, 226),
			accent = rgb(40, 34, 36),
			weight = 3,
		},
		{
			name = "pink",
			wall = rgb(224, 96, 146),
			trim = rgb(250, 242, 226),
			accent = rgb(44, 36, 44),
			weight = 3,
		},
		{
			name = "lavender",
			wall = rgb(126, 112, 196),
			trim = rgb(250, 242, 226),
			accent = rgb(40, 36, 52),
			weight = 2,
		},
	},
	gameplay = {
		follower = rgb(45, 120, 235), -- CrowdView.FOLLOWER_COLOR
		lead = rgb(255, 221, 0), -- CrowdView.LEAD_COLOR
		ring = rgb(80, 235, 255), -- CrowdView.RING_COLOR
		gateLeft = rgb(174, 66, 193), -- legacy flat panels (before GateView)
		gateRight = rgb(28, 153, 177),
		adderBanner = rgb(36, 112, 226), -- GateView adder banner (#70)
		multiplierBanner = rgb(226, 150, 20), -- GateView multiplier banner
		spectator = rgb(255, 120, 40), -- ClusterView.SPECTATOR_COLOR
	},
	materials = {
		wall = "Concrete",
		stone = "Slate",
		road = "Cobblestone",
		ground = "Concrete",
		plaza = "Cobblestone",
	},
	lighting = {
		clockTime = 14.5,
		brightness = 2.6,
		ambient = rgb(150, 138, 130),
		outdoorAmbient = rgb(170, 160, 150),
		colorShiftTop = rgb(255, 236, 204),
		colorShiftBottom = rgb(0, 0, 0),
		shadowSoftness = 0.6,
		exposureCompensation = 0.1,
		environmentDiffuseScale = 0.6,
		environmentSpecularScale = 0.3,
		atmosphere = {
			density = 0.28,
			offset = 0.25,
			color = rgb(170, 205, 245),
			decay = rgb(255, 214, 170),
			glare = 0.2,
			haze = 0.8,
		},
	},
	budgets = {
		maxFacadeParts = 380,
		maxFlagStrips = 48,
		maxFlagCells = 1900,
		maxLamps = 40,
		maxLights = 14,
		maxPlazaParts = 70,
		maxGroundParts = 12,
		maxGuiInstances = 4400,
	},
	heights = { facadeMin = 13, facadeMax = 20, roofExtra = 1.5, lampHeight = 9 },
	layout = {
		facadeInset = 28,
		facadeDepth = 9,
		moduleWidthMin = 22,
		moduleWidthMax = 32,
		runIn = 80,
		endExtra = 60,
		floorHeight = 8,
		flagLanes = { { x = 23.5, y = 22 }, { x = 26.5, y = 25 } },
		flagHeight = 2.4,
		flagPitch = 4,
		flagStripLength = 160,
		lampX = 21.5,
		lampSpacing = 96,
		curbX = 13.6,
		courses = 6,
	},
} :: Theme

-- Tallest point of any facade (wall + roof/cornice). Facades stand outside the play corridor, so
-- they may exceed LevelTheme.PROP_TOP; the rule is that they stay well under the camera.
function LevelTheme.facadeTopMax(theme: Theme): number
	return theme.heights.facadeMax + theme.heights.roofExtra
end

-- Upper bound of Parts the street and its nine-part moving Rey model may emit under the budgets.
function LevelTheme.maxTotalParts(theme: Theme): number
	local b = theme.budgets
	return b.maxFacadeParts
		+ b.maxFlagStrips
		+ b.maxLamps * 2
		+ b.maxPlazaParts
		+ b.maxGroundParts
		+ 9
end

-- Structural rules tying the theme to CameraRig. The camera sight lines to the lead, the next gate
-- row and the spectators all run between the camera (|x| <= FOLLOW_X * lead x, inside the
-- corridor) and targets inside the corridor |x| <= halfWidth, so anything standing at |x| greater
-- than halfWidth is never on such a line sideways; heights are checked against the camera too.
-- Returns the list of broken rules (empty = fine).
function LevelTheme.validate(theme: Theme, halfWidth: number): { string }
	local problems: { string } = {}
	local l, h = theme.layout, theme.heights
	if l.facadeInset < halfWidth + 6 then
		table.insert(problems, "facades too close to the play corridor")
	end
	if LevelTheme.facadeTopMax(theme) > CameraRig.HEIGHT - 2 * CameraRig.CLEARANCE then
		table.insert(problems, "facades too tall for the camera height")
	end
	if h.facadeMin > h.facadeMax then
		table.insert(problems, "facade height range inverted")
	end
	if l.lampX < halfWidth + 1 then
		table.insert(problems, "lamps inside the play corridor")
	end
	for i, lane in l.flagLanes do
		if lane.x < halfWidth + 2 or lane.x >= l.facadeInset then
			table.insert(problems, `flag lane {i} not between corridor and facades`)
		end
		if lane.y - l.flagHeight / 2 <= LevelTheme.PROP_TOP then
			table.insert(problems, `flag lane {i} not above the tallest prop`)
		end
	end
	if LevelTheme.maxTotalParts(theme) > 600 then
		table.insert(problems, "part budget over 600")
	end
	return problems
end

export type ContrastRow = { name: string, ratio: number, min: number, ok: boolean }

-- Every pair that must stay readable, with its minimum ratio (road vs the colors that matter).
function LevelTheme.contrastReport(theme: Theme): { ContrastRow }
	local rows: { ContrastRow } = {}
	local p, g = theme.palette, theme.gameplay
	local function add(name: string, a: Rgb, b: Rgb, min: number, max: number?)
		local ratio = LevelTheme.contrast(a, b)
		table.insert(rows, {
			name = name,
			ratio = ratio,
			min = min,
			ok = ratio >= min and ratio <= (max or math.huge),
		})
	end
	local road, side, plaza = p.road, p.sidewalk, p.plazaPaving
	-- road vs what must read on it
	add("road vs follower", road, g.follower, 2.2)
	add("road vs gate banner adder", road, g.adderBanner, 1.8)
	add("road vs gate banner multiplier", road, g.multiplierBanner, 3)
	add("road vs legacy gate left", road, g.gateLeft, 2.2)
	add("road vs legacy gate right", road, g.gateRight, 2.2)
	add("road vs lead", road, g.lead, 4)
	add("road vs ring", road, g.ring, 4)
	add("road vs spectator", road, g.spectator, 2.5)
	add("gate banners adder vs multiplier", g.adderBanner, g.multiplierBanner, 1.5)
	add("follower vs lead", g.follower, g.lead, 3)
	-- planes: road, sidewalk, forecourt, ground, plaza
	add("road vs sidewalk", road, side, 3)
	add("road vs curb", road, p.curb, 4)
	add("road vs roadAlt (subtle)", road, p.roadAlt, 1.15, 1.5)
	add("sidewalk vs ground", side, p.ground, 1.3)
	add("sidewalk vs forecourt", side, p.forecourt, 1.3)
	add("forecourt vs ground", p.forecourt, p.ground, 1.3)
	-- the crowd on the sidewalk and on the plaza (finale)
	add("sidewalk vs spectator", side, g.spectator, 1.4)
	add("sidewalk vs follower", side, g.follower, 1.8)
	-- Lead and ring live on the road; at the road edge they meet the sidewalk, kept clearly above
	-- 1.0 (they were 1.04 / 1.02 against the previous sidewalk) without darkening the sidewalk
	-- that followers and spectators need.
	add("sidewalk vs lead", side, g.lead, 1.25)
	add("sidewalk vs ring", side, g.ring, 1.2)
	add("plaza vs follower", plaza, g.follower, 1.4)
	add("plaza vs lead", plaza, g.lead, 1.8)
	add("plaza vs adder banner", plaza, g.adderBanner, 1.5)
	-- Banners hang 7-19 studs up with numerals, an icon and a dark stroke, so they read by shape and
	-- text too; the multiplier stays at a modest value step on the plaza (documented trade-off).
	add("plaza vs multiplier banner", plaza, g.multiplierBanner, 1.05)
	add("plaza vs plazaAlt (subtle)", plaza, p.plazaPavingAlt, 1.1, 1.6)
	for _, style in theme.facades do
		add(`road vs {style.name} wall`, road, style.wall, 2.2)
		add(`plaza vs {style.name} wall`, plaza, style.wall, 1.25)
		add(`forecourt vs {style.name} wall`, p.forecourt, style.wall, 1.15)
		add(`sidewalk vs {style.name} wall`, side, style.wall, 1.1)
		add(`{style.name} wall vs trim`, style.wall, style.trim, 1.15)
	end
	add("road vs stone wall", road, p.stone, 2.2)
	add("plaza vs stone wall", plaza, p.stone, 1.25)
	add("forecourt vs stone wall", p.forecourt, p.stone, 1.15)
	return rows
end

return LevelTheme
