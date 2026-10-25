--!strict
-- Pure, seeded generator of the Level 1 street dressing (issue #54 phase 1). From the layout's
-- length and a LevelTheme it returns plain data: facade modules, papel picado flag strips, farol
-- lamps, road/curb ground slabs and the zocalo plaza props. No Roblox APIs; the client
-- (OaxacaStreet) turns it into Parts and SurfaceGuis.
--
-- COORDINATES: everything here is WORLD x (left = negative x, as the server and Level use it).
-- The client applies ViewMap.x to every x (and to a balcony's lateral direction) when it builds a
-- Roblox position; nothing in this module knows about the mirror.
--
-- BUDGETS: the theme's budgets are hard caps; widths, strip lengths, pitches and lamp spacing
-- stretch to fit them (the generator never drops the far end of the street). With
-- LevelTheme.level1 and the debug layout the measured total is about 380 parts (tests print it).
local LayerHeights = require("./LayerHeights")
local LevelTheme = require("./LevelTheme")

local StreetLayoutGen = {}

type Rgb = LevelTheme.Rgb

export type Window = {
	floor: number,
	u: number, -- 0..1 across the module (low z to high z)
	y: number, -- studs above the ground, centre
	w: number,
	h: number,
	arched: boolean,
	grille: boolean,
}
export type Door = { u: number, w: number, h: number, arched: boolean }
export type Arch = { u: number, w: number, h: number }
export type Balcony = { u: number, y: number, w: number, depth: number }

export type Facade = {
	id: number,
	side: "left" | "right",
	kind: string, -- "colonial" | "shop" | "stone" | "portal"
	style: string,
	x: number, -- world x of the wall centre (negative on the left)
	z: number, -- centre along the street
	width: number, -- along z
	depth: number, -- along x
	height: number, -- wall height (cornice adds LevelTheme roofExtra)
	floors: number,
	wall: Rgb,
	trim: Rgb,
	accent: Rgb,
	stone: boolean,
	windows: { Window },
	door: Door?,
	arches: { Arch },
	balconies: { Balcony },
	parts: number,
	gui: number,
}

export type FlagStrip = {
	id: number,
	lane: number,
	side: "left" | "right",
	x: number,
	y: number,
	z0: number,
	z1: number,
	height: number,
	cells: { Rgb }, -- one colored Frame per flag along the strip
	cord: Rgb,
	canvasWidth: number,
	canvasHeight: number,
}

export type Lamp = {
	id: number,
	side: "left" | "right",
	x: number,
	z: number,
	height: number,
	light: boolean,
}

export type Prim = {
	name: string,
	group: string,
	shape: "block" | "cylinder" | "ball", -- cylinder axis is vertical here; the client rotates it
	cx: number,
	cy: number,
	cz: number,
	sx: number,
	sy: number,
	sz: number,
	color: Rgb,
	material: string,
}

export type Counts = {
	facadeParts: number,
	flagCells: number,
	lights: number,
	plazaParts: number,
	groundParts: number,
	guiInstances: number,
	totalParts: number,
}

export type Result = {
	facades: { Facade },
	flags: { FlagStrip },
	lamps: { Lamp },
	ground: { Prim },
	plaza: { Prim },
	counts: Counts,
}

export type LayoutInfo = {
	streetLength: number,
	plazaStart: number,
	startPlazaEnd: number?,
	halfWidth: number,
}

StreetLayoutGen.FLAG_CELL_PX = 32 -- canvas pixels per flag cell
StreetLayoutGen.FLAG_CANVAS_H = 76
StreetLayoutGen.ROOF_CAP_DEPTH_EXTRA = 2
StreetLayoutGen.ROOF_CAP_INNER_SHIFT = 1
StreetLayoutGen.ROOF_CAP_WIDTH_EXTRA = 0.8
local PARTS_PER_MODULE = 3 -- wall + cornice + at most one balcony
local GUI_PER_WINDOW, GUI_PER_DOOR, GUI_PER_ARCH, GUI_PER_BALCONY, GUI_TRIM = 3, 3, 3, 2, 2

-- Park-Miller; products stay under 2^53 so it is exact in doubles.
local function makeRng(seed: number): () -> number
	local state = math.floor(math.abs(seed)) % 2147483646 + 1
	return function()
		state = state * 48271 % 2147483647
		return state / 2147483647
	end
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function sideOf(sign: number): "left" | "right"
	return if sign < 0 then "left" else "right"
end

local function pickStyle(theme: LevelTheme.Theme, rng: () -> number, avoid: number): number
	local total = 0
	for i, s in theme.facades do
		if i ~= avoid then
			total += s.weight
		end
	end
	local roll = rng() * total
	for i, s in theme.facades do
		if i ~= avoid then
			roll -= s.weight
			if roll <= 0 then
				return i
			end
		end
	end
	return if avoid == 1 then 2 else 1
end

local function makeFacade(
	theme: LevelTheme.Theme,
	rng: () -> number,
	id: number,
	sign: number,
	index: number,
	z: number,
	width: number,
	info: LayoutInfo,
	styleIndex: number
): Facade
	local l, h = theme.layout, theme.heights
	local style = theme.facades[styleIndex]
	local kind = "colonial"
	if z <= info.streetLength then
		if z >= info.plazaStart then
			kind = "portal"
		elseif index == 1 or index % 9 == 0 then
			kind = "stone"
		elseif rng() < 0.25 then
			kind = "shop"
		end
	end

	local height: number
	if kind == "shop" or kind == "portal" then
		height = h.facadeMin
	elseif kind == "stone" then
		height = h.facadeMax - rng()
	else
		height = lerp(h.facadeMin + 2, h.facadeMax, rng())
	end
	local floors = if kind == "shop" or kind == "portal" then 1 else 2

	local wall, trim, accent = style.wall, style.trim, style.accent
	if kind == "stone" then
		wall, trim, accent = theme.palette.stone, theme.palette.sidewalk, theme.palette.iron
	end

	local windows: { Window } = {}
	local arches: { Arch } = {}
	local balconies: { Balcony } = {}
	local door: Door? = nil
	local gui = GUI_TRIM

	if kind == "portal" then
		local n = math.max(2, math.floor(width / 6.5))
		for i = 1, n do
			table.insert(arches, { u = (i - 0.5) / n, w = 4, h = 7.5 })
		end
		gui += n * GUI_PER_ARCH
	else
		local n = math.clamp(math.floor(width / 7.5), 2, 4)
		local doorSlot = 1 + math.floor(rng() * n)
		-- Physical balconies give the facades a strong projecting silhouette from the high camera.
		local hasBalcony = floors == 2 and kind ~= "stone"
		for i = 1, n do
			local u = (i - 0.5) / n
			if i == doorSlot then
				door = { u = u, w = 3, h = 6.2, arched = rng() < 0.6 }
				gui += GUI_PER_DOOR
			elseif kind == "shop" then
				table.insert(windows, {
					floor = 1,
					u = u,
					y = height / 2 + 0.5,
					w = 3.6,
					h = 4.6,
					arched = false,
					grille = true,
				})
				gui += GUI_PER_WINDOW
			else
				table.insert(windows, {
					floor = 1,
					u = u,
					y = 4.5,
					w = 2.6,
					h = 3.6,
					arched = rng() < 0.5,
					grille = true,
				})
				gui += GUI_PER_WINDOW
			end
			if floors == 2 then
				table.insert(windows, {
					floor = 2,
					u = u,
					y = l.floorHeight + 4.6,
					w = 2.6,
					h = 4,
					arched = rng() < 0.5,
					grille = not hasBalcony and rng() < 0.5,
				})
				gui += GUI_PER_WINDOW
			end
		end
		if hasBalcony then
			table.insert(balconies, { u = 0.5, y = l.floorHeight, w = width * 0.6, depth = 3 })
			gui += GUI_PER_BALCONY
		end
	end

	return {
		id = id,
		side = sideOf(sign),
		kind = kind,
		style = if kind == "stone" then "stone" else style.name,
		x = sign * (l.facadeInset + l.facadeDepth / 2),
		z = z,
		width = width,
		depth = l.facadeDepth,
		height = height,
		floors = floors,
		wall = wall,
		trim = trim,
		accent = accent,
		stone = kind == "stone",
		windows = windows,
		door = door,
		arches = arches,
		balconies = balconies,
		parts = 2 + #balconies,
		gui = gui,
	}
end

-- Axis-aligned boxes (world coordinates) a facade module occupies: wall, roof cap, balconies.
-- Used by the sight-line tests and by anything that must keep clear of the buildings.
function StreetLayoutGen.facadeBoxes(f: Facade): {
	{
		cx: number,
		cy: number,
		cz: number,
		sx: number,
		sy: number,
		sz: number,
	}
}
	local toward = if f.x < 0 then 1 else -1 -- direction toward the street centre
	local boxes = {
		{ cx = f.x, cy = f.height / 2, cz = f.z, sx = f.depth, sy = f.height, sz = f.width },
		{
			cx = f.x + toward * StreetLayoutGen.ROOF_CAP_INNER_SHIFT,
			cy = f.height + 0.75,
			cz = f.z,
			sx = f.depth + StreetLayoutGen.ROOF_CAP_DEPTH_EXTRA,
			sy = 1.5,
			sz = f.width + StreetLayoutGen.ROOF_CAP_WIDTH_EXTRA,
		},
	}
	for _, b in f.balconies do
		table.insert(boxes, {
			cx = f.x + toward * (f.depth / 2 + b.depth / 2),
			cy = b.y,
			cz = f.z + (b.u - 0.5) * f.width,
			sx = b.depth,
			sy = 0.5,
			sz = b.w,
		})
	end
	return boxes
end

local function prim(
	name: string,
	group: string,
	shape: "block" | "cylinder" | "ball",
	cx: number,
	cy: number,
	cz: number,
	sx: number,
	sy: number,
	sz: number,
	color: Rgb,
	material: string
): Prim
	return {
		name = name,
		group = group,
		shape = shape,
		cx = cx,
		cy = cy,
		cz = cz,
		sx = sx,
		sy = sy,
		sz = sz,
		color = color,
		material = material,
	}
end

local function makeGround(
	theme: LevelTheme.Theme,
	info: LayoutInfo,
	z0: number,
	z1: number
): { Prim }
	local p, l, m = theme.palette, theme.layout, theme.materials
	local ground: { Prim } = {}
	local roadHalf = info.halfWidth - 6
	local streetEnd = info.plazaStart
	local roadStart = info.startPlazaEnd or z0
	local len = streetEnd - roadStart
	local width = roadHalf * 2 / l.courses
	for i = 1, l.courses do
		table.insert(
			ground,
			prim(
				`Course{i}`,
				"road",
				"block",
				-roadHalf + (i - 0.5) * width,
				LayerHeights.GROUND - 0.1,
				(roadStart + streetEnd) / 2,
				width,
				0.2,
				len,
				if i % 2 == 1 then p.road else p.roadAlt,
				m.road
			)
		)
	end
	for _, sign in { -1, 1 } do
		table.insert(
			ground,
			prim(
				`Curb{sideOf(sign)}`,
				"curb",
				"block",
				sign * l.curbX,
				LayerHeights.MARKING - 0.1,
				(roadStart + streetEnd) / 2,
				0.8,
				0.2,
				len,
				p.curb,
				"SmoothPlastic"
			)
		)
		table.insert(
			ground,
			prim(
				`Forecourt{sideOf(sign)}`,
				"forecourt",
				"block",
				sign * (info.halfWidth + l.facadeInset) / 2,
				-0.5,
				(z0 + z1) / 2,
				l.facadeInset - info.halfWidth,
				1,
				z1 - z0,
				p.forecourt,
				m.ground
			)
		)
	end
	return ground
end

local function makePlaza(theme: LevelTheme.Theme, info: LayoutInfo, rng: () -> number): { Prim }
	local p, m = theme.palette, theme.materials
	local plaza: { Prim } = {}
	local depth = info.streetLength - info.plazaStart
	if depth > 8 then
		local cols, rows = 6, math.max(1, math.min(4, math.floor(depth / 20)))
		local w, d = info.halfWidth * 2 / cols, depth / rows
		for r = 1, rows do
			for c = 1, cols do
				table.insert(
					plaza,
					prim(
						`Paving{r}_{c}`,
						"paving",
						"block",
						-info.halfWidth + (c - 0.5) * w,
						LayerHeights.MARKING - 0.1,
						info.plazaStart + (r - 0.5) * d,
						w,
						0.2,
						d,
						if (r + c) % 2 == 0 then p.plazaPaving else p.plazaPavingAlt,
						m.plaza
					)
				)
			end
		end
		-- Trees outside the plaza floor so the finale's dancers keep the whole floor.
		local z = info.plazaStart + 16
		while z < info.streetLength - 8 do
			for _, sign in { -1, 1 } do
				local x = sign * 24.5
				local name = `Tree{#plaza}`
				table.insert(
					plaza,
					prim(`{name}Trunk`, "tree", "cylinder", x, 3, z, 1.4, 6, 1.4, p.trunk, "Wood")
				)
				table.insert(
					plaza,
					prim(`{name}Crown`, "tree", "ball", x, 8, z, 7, 7, 7, p.foliage, "Grass")
				)
				table.insert(
					plaza,
					prim(
						`{name}Top`,
						"tree",
						"ball",
						x,
						11.5,
						z + (rng() - 0.5),
						5,
						5,
						5,
						p.foliageAlt,
						"Grass"
					)
				)
			end
			z += 36
		end
	end
	-- Kiosco (bandstand) and a stone church-like backdrop, both behind the end of the street.
	local kz = info.streetLength + 14
	table.insert(
		plaza,
		prim("KioscoBase", "kiosco", "cylinder", 0, 0.6, kz, 14, 1.2, 14, p.kioscoBase, m.ground)
	)
	for i = 1, 6 do
		local a = (i - 1) / 6 * math.pi * 2
		table.insert(
			plaza,
			prim(
				`KioscoPost{i}`,
				"kiosco",
				"cylinder",
				math.cos(a) * 5.2,
				4.2,
				kz + math.sin(a) * 5.2,
				0.8,
				6,
				0.8,
				p.kioscoBase,
				m.ground
			)
		)
	end
	table.insert(
		plaza,
		prim("KioscoRoof", "kiosco", "cylinder", 0, 7.6, kz, 15, 0.8, 15, p.kioscoRoof, m.ground)
	)
	table.insert(
		plaza,
		prim("KioscoDome", "kiosco", "ball", 0, 9, kz, 6, 6, 6, p.kioscoRoof, m.ground)
	)
	local cz = info.streetLength + 44
	table.insert(
		plaza,
		prim(
			"ChurchWall",
			"cathedral",
			"block",
			0,
			11,
			cz,
			70,
			22,
			8,
			p.cathedral,
			theme.materials.stone
		)
	)
	for _, sign in { -1, 1 } do
		table.insert(
			plaza,
			prim(
				`ChurchTower{sideOf(sign)}`,
				"cathedral",
				"block",
				sign * 26,
				16,
				cz,
				10,
				32,
				10,
				p.cathedral,
				theme.materials.stone
			)
		)
	end
	return plaza
end

-- Generate the street. `seed` makes the colors, kinds and window rhythm repeatable.
function StreetLayoutGen.generate(info: LayoutInfo, theme: LevelTheme.Theme, seed: number): Result
	local rng = makeRng(seed)
	local l, b = theme.layout, theme.budgets
	local z0 = -l.runIn
	local z1 = info.streetLength + l.endExtra
	local len = z1 - z0

	-- Facades: equal-ish modules per side, count capped so parts stay under the budget.
	local facades: { Facade } = {}
	local maxPerSide = math.floor(b.maxFacadeParts / PARTS_PER_MODULE / 2)
	local avg = (l.moduleWidthMin + l.moduleWidthMax) / 2
	local n = math.max(1, math.min(math.floor(len / avg + 0.5), maxPerSide))
	for _, sign in { -1, 1 } do
		local raw: { number } = {}
		local sum = 0
		for i = 1, n do
			raw[i] = 0.85 + 0.3 * rng()
			sum += raw[i]
		end
		local z = z0
		local prevStyle = 0
		for i = 1, n do
			local width = raw[i] / sum * len
			local styleIndex = pickStyle(theme, rng, prevStyle)
			prevStyle = styleIndex
			table.insert(
				facades,
				makeFacade(
					theme,
					rng,
					#facades + 1,
					sign,
					i,
					z + width / 2,
					width,
					info,
					styleIndex
				)
			)
			z += width
		end
	end

	-- Flags: strips of colored cells on a few lanes outside the play corridor.
	local flags: { FlagStrip } = {}
	local laneCount = #l.flagLanes * 2
	local stripLen = math.max(l.flagStripLength, math.ceil(len * laneCount / b.maxFlagStrips))
	local pitch = math.max(l.flagPitch, len * laneCount / b.maxFlagCells + 0.01)
	for laneIndex, lane in l.flagLanes do
		for _, sign in { -1, 1 } do
			local z = z0
			local last = 0
			while z < z1 - 1e-6 do
				local zEnd = math.min(z + stripLen, z1)
				local count = math.max(1, math.floor((zEnd - z) / pitch))
				local cells: { Rgb } = {}
				for i = 1, count do
					local idx = 1 + math.floor(rng() * #theme.flagColors)
					if idx == last then
						idx = idx % #theme.flagColors + 1
					end
					last = idx
					cells[i] = theme.flagColors[idx]
				end
				table.insert(flags, {
					id = #flags + 1,
					lane = laneIndex,
					side = sideOf(sign),
					x = sign * lane.x,
					y = lane.y,
					z0 = z,
					z1 = zEnd,
					height = l.flagHeight,
					cells = cells,
					cord = theme.palette.flagCord,
					canvasWidth = count * StreetLayoutGen.FLAG_CELL_PX,
					canvasHeight = StreetLayoutGen.FLAG_CANVAS_H,
				})
				z = zEnd
			end
		end
	end

	-- Lamps: alternate sides, sparse, only some carry a PointLight.
	local lamps: { Lamp } = {}
	local spacing = math.max(l.lampSpacing, 2 * info.streetLength / b.maxLamps + 0.01)
	local positions: { { z: number, sign: number } } = {}
	for _, sign in { -1, 1 } do
		local z = 24 + (if sign > 0 then spacing / 2 else 0)
		while z < info.streetLength - 8 do
			table.insert(positions, { z = z, sign = sign })
			z += spacing
		end
	end
	table.sort(positions, function(a, c)
		return a.z < c.z
	end)
	local every = math.max(1, math.ceil(#positions / b.maxLights))
	local lights = 0
	for i, pos in positions do
		local light = (i - 1) % every == 0
		if light then
			lights += 1
		end
		table.insert(lamps, {
			id = i,
			side = sideOf(pos.sign),
			x = pos.sign * l.lampX,
			z = pos.z,
			height = theme.heights.lampHeight,
			light = light,
		})
	end

	local ground = makeGround(theme, info, z0, z1)
	local plaza = makePlaza(theme, info, rng)
	local facadeParts, gui = 0, 0
	for _, f in facades do
		facadeParts += f.parts
		gui += f.gui
	end
	local cells = 0
	for _, s in flags do
		cells += #s.cells
	end
	return {
		facades = facades,
		flags = flags,
		lamps = lamps,
		ground = ground,
		plaza = plaza,
		counts = {
			facadeParts = facadeParts,
			flagCells = cells,
			lights = lights,
			plazaParts = #plaza,
			groundParts = #ground,
			guiInstances = gui,
			totalParts = facadeParts + #flags + #lamps * 2 + #plaza + #ground,
		},
	}
end

export type BuildItem = { kind: string, index: number, z: number }

-- Every item once, ordered by z (the start of the street first) so a progressive build shows the
-- part the player sees first. Ground slabs sort by their near end.
function StreetLayoutGen.buildOrder(result: Result): { BuildItem }
	local items: { BuildItem } = {}
	for i, f in result.facades do
		table.insert(items, { kind = "facade", index = i, z = f.z })
	end
	for i, s in result.flags do
		table.insert(items, { kind = "flag", index = i, z = (s.z0 + s.z1) / 2 })
	end
	for i, lamp in result.lamps do
		table.insert(items, { kind = "lamp", index = i, z = lamp.z })
	end
	for i, g in result.ground do
		table.insert(items, { kind = "ground", index = i, z = g.cz - g.sz / 2 })
	end
	for i, p in result.plaza do
		table.insert(items, { kind = "plaza", index = i, z = p.cz })
	end
	local order: { [BuildItem]: number } = {}
	for i, item in items do
		order[item] = i
	end
	table.sort(items, function(a, c)
		if a.z ~= c.z then
			return a.z < c.z
		end
		return (order[a] :: number) < (order[c] :: number)
	end)
	return items
end

return StreetLayoutGen
