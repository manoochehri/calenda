--!strict
-- Issue #193 (owner report: "there's no lanes like in mob control"). The street's visible lane
-- markings, as data: pure, no Roblox APIs, so the placement is testable under Lune. Every x comes
-- from LaneGeometry (the module the server resolves lanes with); nothing here repeats a lane centre or
-- -5/5. The client (LaneView) turns each spec into a flat Part. Presentation only: it changes no
-- lane, crowd or authority.
--
-- Readable without colour: a solid divider line on each lane boundary, and on each lane centre a
-- row of forward arrows (a shaft and two angled barbs). The lane's side is its position on the
-- street, the arrow's shape says "run this way". The lead's own lane is marked by a bracket of two
-- bars across the lane that sits under the lead (LaneMarkings.leadBracket).
local LaneGeometry = require("./LaneGeometry")
local LayerHeights = require("./LayerHeights")

local LaneMarkings = {}

LaneMarkings.DIVIDER_WIDTH = 0.4 -- [default] studs
LaneMarkings.ARROW_SPACING = 48 -- [default] studs between arrow rows along the street
LaneMarkings.ARROW_LENGTH = 6 -- [default] studs, the arrow's extent along the street
LaneMarkings.ARROW_WIDTH = 6 -- [default] studs, the arrow's extent across the lane (shaft plus both barbs, 5.8)
LaneMarkings.CLEARANCE = 4 -- [default] studs kept free around a gate or obstacle line
LaneMarkings.BRACKET_BAR_DEPTH = 0.6 -- [default] studs
LaneMarkings.BRACKET_HALF_LENGTH = 5 -- [default] studs the bracket reaches behind and ahead of the lead
LaneMarkings.BRACKET_INSET = 0.5 -- [default] studs kept clear of the lane boundary on each side

LaneMarkings.SHAFT_WIDTH = 0.6 -- [default] studs
LaneMarkings.BARB_LENGTH = 3 -- [default] studs
LaneMarkings.BARB_WIDTH = 0.6 -- [default] studs
LaneMarkings.BARB_GAP = 0.05 -- [default] studs of clear air between a barb's footprint and the shaft's

export type Spec = {
	name: string,
	kind: string, -- "divider" | "arrow"
	lane: string?, -- the lane an arrow marks the centre of
	x: number, -- lateral centre (lane units, before ViewMap mirroring)
	z: number, -- centre along the street
	sx: number,
	sz: number,
	top: number, -- the flat top height, a named LayerHeights layer
	yaw: number, -- degrees about the vertical axis (0 for the whole bar)
}

export type LayoutInfo = {
	plazaStart: number,
	startPlazaEnd: number?,
	gates: { { z: number } }?,
	obstacles: { { z: number } }?,
	clusters: { { lane: string } }?,
	pickups: { { lane: string } }?,
}

local LANES = { "left", "center", "right" }
LaneMarkings.lanes = table.freeze(table.clone(LANES))

-- WorldBuilder's centre-line dashes: 24 long, every 96 from z = 48. The centre-lane arrows skip them.
local function onDash(z: number, layout: LayoutInfo): boolean
	for d = 48, layout.plazaStart - 48, 96 do
		if math.abs(z - d) < 12 + LaneMarkings.ARROW_LENGTH / 2 then
			return true
		end
	end
	return false
end

local function nearLine(z: number, layout: LayoutInfo): boolean
	local clear = LaneMarkings.CLEARANCE + LaneMarkings.ARROW_LENGTH / 2
	for _, g in layout.gates or {} do
		if math.abs(z - g.z) < clear then
			return true
		end
	end
	for _, o in layout.obstacles or {} do
		if math.abs(z - o.z) < clear then
			return true
		end
	end
	return false
end

-- Every static marking from the start of the street to the plaza.
function LaneMarkings.specs(layout: LayoutInfo): { Spec }
	local list: { Spec } = {}
	local z0 = layout.startPlazaEnd or 0
	local z1 = layout.plazaStart
	-- Dividers on the two lane boundaries: LEFT_EDGE and RIGHT_EDGE.
	for _, edge in
		{ { "LeftDivider", LaneGeometry.LEFT_EDGE }, { "RightDivider", LaneGeometry.RIGHT_EDGE } }
	do
		table.insert(list, {
			name = edge[1] :: string,
			kind = "divider",
			x = edge[2] :: number,
			z = (z0 + z1) / 2,
			sx = LaneMarkings.DIVIDER_WIDTH,
			sz = z1 - z0,
			top = LayerHeights.MARKING,
			yaw = 0,
		})
	end
	-- One arrow on each lane centre, row by row, skipping rows that would sit on a gate line or
	-- obstacle line (those have their own crossing strips and cones).
	local z = math.ceil((z0 + LaneMarkings.ARROW_LENGTH) / LaneMarkings.ARROW_SPACING)
		* LaneMarkings.ARROW_SPACING
	while z + LaneMarkings.ARROW_LENGTH / 2 < z1 do
		if not nearLine(z, layout) then
			for _, lane in LANES do
				if lane == "center" and onDash(z, layout) then
					continue
				end
				table.insert(list, {
					name = `Arrow_{lane}_{math.floor(z)}`,
					kind = "arrow",
					lane = lane,
					x = LaneGeometry.centerOf(lane :: LaneGeometry.Lane),
					z = z,
					sx = LaneMarkings.ARROW_WIDTH,
					sz = LaneMarkings.ARROW_LENGTH,
					top = LayerHeights.MARKING,
					yaw = 0,
				})
			end
		end
		z += LaneMarkings.ARROW_SPACING
	end
	return list
end

-- Lane roles (issue #193), read from the layout's authored data, never fixed per lane: the spec
-- gives no lane a standing job. A lane holds a horde where a cluster is authored in it and +1
-- people where a pickup is.
export type Role = { horde: boolean, pickup: boolean }

function LaneMarkings.roles(layout: LayoutInfo): { left: Role, center: Role, right: Role }
	local out = {
		left = { horde = false, pickup = false },
		center = { horde = false, pickup = false },
		right = { horde = false, pickup = false },
	}
	for _, c in layout.clusters or {} do
		local r = (out :: any)[c.lane]
		if r then
			r.horde = true
		end
	end
	for _, k in layout.pickups or {} do
		local r = (out :: any)[k.lane]
		if r then
			r.pickup = true
		end
	end
	return out
end

-- The words a lane's job is painted with. Empty when the layout puts nothing in the lane.
function LaneMarkings.roleText(role: Role): string
	local words = {}
	if role.horde then
		table.insert(words, "SHOOT HORDE")
	end
	if role.pickup then
		table.insert(words, "+1 PEOPLE")
	end
	return table.concat(words, " / ")
end

LaneMarkings.LABEL_SPACING = 96 -- [default] studs between label rows
LaneMarkings.LABEL_OFFSET = 24 -- [default] studs; rows sit between the arrow rows (multiples of 48) and the centre dashes
LaneMarkings.LABEL_WIDTH = 9 -- [default] studs across the lane (the band is 10)
LaneMarkings.LABEL_LENGTH = 8 -- [default] studs along the street

export type Label = {
	name: string,
	lane: string,
	text: string, -- lane word, then (when the layout gives the lane a job) a line break and the role
	x: number,
	z: number,
	sx: number,
	sz: number,
	top: number,
}

-- One painted text label per lane per row, from the street's start to the plaza.
function LaneMarkings.labelSpecs(layout: LayoutInfo): { Label }
	local list: { Label } = {}
	local roles = LaneMarkings.roles(layout)
	local z0 = layout.startPlazaEnd or 0
	local half = LaneMarkings.LABEL_LENGTH / 2
	local first = math.ceil((z0 + half - LaneMarkings.LABEL_OFFSET) / LaneMarkings.LABEL_SPACING)
	local z = LaneMarkings.LABEL_OFFSET + first * LaneMarkings.LABEL_SPACING
	while z + half < layout.plazaStart do
		local clear = LaneMarkings.CLEARANCE + half
		local blocked = false
		for _, g in layout.gates or {} do
			blocked = blocked or math.abs(z - g.z) < clear
		end
		for _, o in layout.obstacles or {} do
			blocked = blocked or math.abs(z - o.z) < clear
		end
		if not blocked then
			for _, lane in LANES do
				local role = LaneMarkings.roleText((roles :: any)[lane])
				table.insert(list, {
					name = `Label_{lane}_{math.floor(z)}`,
					lane = lane,
					text = if role == ""
						then string.upper(lane)
						else `{string.upper(lane)}\n{role}`,
					x = LaneGeometry.centerOf(lane :: LaneGeometry.Lane),
					z = z,
					sx = LaneMarkings.LABEL_WIDTH,
					sz = LaneMarkings.LABEL_LENGTH,
					top = LayerHeights.MARKING,
				})
			end
		end
		z += LaneMarkings.LABEL_SPACING
	end
	return list
end

export type Part = {
	name: string,
	side: number, -- 0 for the shaft; -1 or 1 for a barb, the lane-unit side it leans toward
	x: number, -- lateral centre (lane units, before ViewMap mirroring)
	z: number,
	sx: number, -- the part's own size before rotation
	sz: number,
	top: number,
	x0: number, -- the axis-aligned footprint after rotation (conservative for the 45 degree barbs)
	x1: number,
	z0: number,
	z1: number,
}

-- The Parts of one forward arrow: a shaft along the street and two barbs sweeping back from the
-- tip. No two footprints overlap, so every Part can share the one MARKING layer without the #85
-- z-fight: each barb is pushed out so its footprint clears the shaft and the other barb. LaneView
-- draws exactly these (barb yaw is -45 * side, mirrored by ViewMap).
function LaneMarkings.arrowParts(s: Spec): { Part }
	local shaftW, len, bw =
		LaneMarkings.SHAFT_WIDTH, LaneMarkings.BARB_LENGTH, LaneMarkings.BARB_WIDTH
	local h = (len + bw) / 2 / math.sqrt(2) -- half extent of a barb rotated 45 degrees
	local cx = shaftW / 2 + LaneMarkings.BARB_GAP + h
	local tip = s.z + s.sz / 2
	local parts: { Part } = {
		{
			name = s.name,
			side = 0,
			x = s.x,
			z = s.z,
			sx = shaftW,
			sz = s.sz,
			top = s.top,
			x0 = s.x - shaftW / 2,
			x1 = s.x + shaftW / 2,
			z0 = s.z - s.sz / 2,
			z1 = tip,
		},
	}
	for _, side in { -1, 1 } do
		local x, z = s.x + side * cx, tip - h
		table.insert(parts, {
			name = `{s.name}_Barb{if side < 0 then "L" else "R"}`,
			side = side,
			x = x,
			z = z,
			sx = bw,
			sz = len,
			top = s.top,
			x0 = x - h,
			x1 = x + h,
			z0 = z - h,
			z1 = z + h,
		})
	end
	return parts
end

-- The lane the lead's marker belongs to for lateral position x; positions outside the street clamp
-- to the nearest lane so the marker never vanishes.
function LaneMarkings.leadLane(x: number): LaneGeometry.Lane
	local lane = LaneGeometry.laneOf(math.clamp(x, LaneGeometry.MIN_X, LaneGeometry.MAX_X))
	return lane or "center"
end

export type Bar = { x: number, z: number, sx: number, sz: number, top: number }

LaneMarkings.BRACKET_TOP = LayerHeights.LANE_LEAD

-- The lead's lane centre for lateral position x (what leadBracket centres on), allocation-free.
function LaneMarkings.leadCentre(x: number): number
	return LaneGeometry.centerOf(LaneMarkings.leadLane(x))
end

-- The bracket bars' constant lateral size.
function LaneMarkings.bracketWidth(): number
	return (LaneGeometry.RIGHT_EDGE - LaneGeometry.LEFT_EDGE) - 2 * LaneMarkings.BRACKET_INSET
end

-- The lead's lane marker: a front bar and a rear bar across the lane, centred on the lane centre.
-- Pure of time: it only moves when the lead moves or changes lane, it never pulses.
function LaneMarkings.leadBracket(x: number, z: number): { Bar }
	local lane = LaneMarkings.leadLane(x)
	local centre = LaneGeometry.centerOf(lane)
	local width = LaneMarkings.bracketWidth()
	local h = LaneMarkings.BRACKET_HALF_LENGTH
	return {
		{
			x = centre,
			z = z + h,
			sx = width,
			sz = LaneMarkings.BRACKET_BAR_DEPTH,
			top = LayerHeights.LANE_LEAD,
		},
		{
			x = centre,
			z = z - h,
			sx = width,
			sz = LaneMarkings.BRACKET_BAR_DEPTH,
			top = LayerHeights.LANE_LEAD,
		},
	}
end

return LaneMarkings
