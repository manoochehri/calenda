--!strict
-- The one named table of ground-layer heights (issues #54, #85). From the high camera (46+ studs)
-- depth precision is far coarser than 0.05 studs, so two flat surfaces that overlap in x/z and sit
-- within a few hundredths of each other z-fight (the owner's "strobe on the road"). Every flat
-- thing drawn on or just above the ground takes its TOP height from here, and any two that overlap
-- differ by at least MIN_STEP studs. Pure: no Roblox APIs. Values are tuning defaults.
local LayerHeights = {}

LayerHeights.MIN_STEP = 0.2 -- studs; the least separation between two overlapping flat tops

LayerHeights.EARTH = -1.1 -- Backdrop earth plate under everything
LayerHeights.ROAD_BASE = -0.2 -- road slab (WorldBuilder Street, Backdrop RunIn): a kerb below the sidewalks
LayerHeights.GROUND = 0 -- sidewalks, forecourt, plaza floor, flagstone road courses (over ROAD_BASE)
LayerHeights.MARKING = 0.2 -- curb stripes, centre-line dashes, plaza paving checker
LayerHeights.DECAL = 0.4 -- gate crossing strips, traffic cone feet
LayerHeights.RING = 0.6 -- the lead's ground ring
LayerHeights.PASS_RING = 0.8 -- the expanding ring when the parade passes a gate
LayerHeights.DEBRIS = 1.0 -- confetti that has landed
LayerHeights.TELEGRAPH = 1.2 -- the warning chevron where a spectator wave is about to appear (issue #65)

-- Every named layer, for tests ("each flat top is a named layer").
LayerHeights.all = table.freeze({
	EARTH = LayerHeights.EARTH,
	ROAD_BASE = LayerHeights.ROAD_BASE,
	GROUND = LayerHeights.GROUND,
	MARKING = LayerHeights.MARKING,
	DECAL = LayerHeights.DECAL,
	RING = LayerHeights.RING,
	PASS_RING = LayerHeights.PASS_RING,
	DEBRIS = LayerHeights.DEBRIS,
	TELEGRAPH = LayerHeights.TELEGRAPH,
})

export type Surface = {
	name: string,
	top: number,
	x0: number, -- world x extent (mirror-symmetric where it matters)
	x1: number,
	z0: number,
	z1: number,
}

local function surface(name: string, top: number, x0: number, x1: number, z0: number, z1: number)
	return { name = name, top = top, x0 = x0, x1 = x1, z0 = z0, z1 = z1 } :: Surface
end

export type LayoutInfo = {
	streetLength: number,
	plazaStart: number,
	halfWidth: number,
	runIn: number?,
	gates: { { z: number } }?,
	obstacles: { { z: number } }?,
}

-- Flat surfaces drawn by WorldBuilder, Backdrop, GateView, CrowdView, WorldBuilder's cones and
-- Bits (confetti), with their extents. OaxacaStreet's own surfaces come from StreetLayoutGen.
function LayerHeights.surfaces(layout: LayoutInfo): { Surface }
	local runIn = layout.runIn or 80
	local half, road = layout.halfWidth, layout.halfWidth - 6
	local list: { Surface } = {}
	local function add(s: Surface)
		table.insert(list, s)
	end
	add(surface("EarthPlate", LayerHeights.EARTH, -1500, 1500, -1500, layout.streetLength + 1500))
	add(surface("RunIn", LayerHeights.ROAD_BASE, -road, road, -runIn, 0))
	add(surface("Street", LayerHeights.ROAD_BASE, -road, road, 0, layout.plazaStart))
	add(surface("LeftSidewalk", LayerHeights.GROUND, -half, -road, 0, layout.plazaStart))
	add(surface("RightSidewalk", LayerHeights.GROUND, road, half, 0, layout.plazaStart))
	add(surface("Plaza", LayerHeights.GROUND, -half, half, layout.plazaStart, layout.streetLength))
	for z = 48, layout.plazaStart - 48, 96 do
		add(surface(`RoadMark{z}`, LayerHeights.MARKING, -0.225, 0.225, z - 12, z + 12))
	end
	for _, gate in layout.gates or {} do
		add(
			surface(
				`CrossingStrip{gate.z}`,
				LayerHeights.DECAL,
				-half,
				half,
				gate.z - 0.6,
				gate.z + 0.6
			)
		)
	end
	for _, o in layout.obstacles or {} do
		add(surface(`Cones{o.z}`, LayerHeights.DECAL, -half, half, o.z - 0.45, o.z + 0.45))
	end
	add(surface("LeadRing", LayerHeights.RING, -half, half, -runIn, layout.streetLength))
	for _, gate in layout.gates or {} do
		add(
			surface(
				`PassRing{gate.z}`,
				LayerHeights.PASS_RING,
				-half,
				half,
				gate.z - half / 2,
				gate.z + half / 2
			)
		)
	end
	add(surface("LandedConfetti", LayerHeights.DEBRIS, -half, half, -runIn, layout.streetLength))
	add(
		surface(
			"TelegraphChevron",
			LayerHeights.TELEGRAPH,
			-half,
			half,
			-runIn,
			layout.streetLength
		)
	)
	return list
end

local function overlap(a: Surface, b: Surface): boolean
	local e = 1e-6 -- touching edges (and float noise) are not an overlap
	return a.x0 < b.x1 - e and b.x0 < a.x1 - e and a.z0 < b.z1 - e and b.z0 < a.z1 - e
end

-- Pairs that overlap in x/z yet differ by less than MIN_STEP. Empty = no z-fight risk.
function LayerHeights.conflicts(list: { Surface }): { string }
	local out: { string } = {}
	for i = 1, #list do
		for j = i + 1, #list do
			local a, b = list[i], list[j]
			if overlap(a, b) and math.abs(a.top - b.top) < LayerHeights.MIN_STEP - 1e-9 then
				table.insert(out, `{a.name} ({a.top}) vs {b.name} ({b.top})`)
			end
		end
	end
	return out
end

return LayerHeights
