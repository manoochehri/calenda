--!strict
-- Three authored layouts selected by a recorded seed (issue #23, spec s9). Pure: no Roblox APIs.
-- Times are authored in run seconds and converted with Config.speed, so the spec timeline holds
-- when the forward pace is tuned. Each layout must pass LayoutValidator (tested in
-- tests/issue23_layouts.test.luau). Gates alternate add/multiply kinds across the route so each
-- layout offers a tradeoff; the lateral side of the big group changes per layout.
-- Select with Layouts.select(seed): the same seed always gives the same layout, and the returned
-- copy carries that seed so RunDriver records it in the run log.
local Config = require("./Config")
local Emergence = require("./Emergence")
local Level = require("./Level")

local Layouts = {}

type Gate = Level.Gate
type Obstacle = Level.Obstacle

local SOAK_STEP = 1.5 -- studs each soak sits nearer the lead than the one before
local PAIRS = 4

local function waveOffset(pair: number): number
	return (pair - 1) * 7.8 -- five-group packs overlap within the low-quality visible cap
end

local function at(seconds: number): number
	return seconds * Config.speed
end

local function op(kind: "add" | "multiply", value: number): Level.Op
	return { kind = kind, value = value }
end

local function gate(id: number, seconds: number, left: Level.Op, right: Level.Op): Gate
	return { id = id, z = at(seconds), left = left, right = right }
end

local function obstacle(id: number, seconds: number, side: "left" | "right"): Obstacle
	return { id = id, z = at(seconds), side = side }
end

-- Waves: pair p sends a small group (wave 2p-1) and a large group (wave 2p) that arrive together.
-- Waves alternate sides. `bigOnLeft` puts the large group on the left sidewalk. `soaks[p]` extra
-- large groups trail the small group nearer the lead.
type WaveSpec = { waveDelay: number, soaks: { number }, bigOnLeft: boolean }

local function buildClusters(spec: WaveSpec): { Level.Cluster }
	local needOffset = Emergence.requiredSpawnOffset()
	local closing = Config.speed + Config.spectators.approachSpeed
	local clusters: { Level.Cluster } = {}
	local function add(wave: number, kind: string, x: number, spawnTime: number, spawnZ: number)
		local offset = spawnZ - Config.speed * spawnTime
		local back = math.max(0, math.ceil((needOffset - offset) / closing * 4) / 4)
		table.insert(clusters, {
			id = #clusters + 1,
			wave = wave,
			type = kind,
			spawnTime = spawnTime - back,
			spawn = { x = x, z = spawnZ + Config.spectators.approachSpeed * back },
			path = {},
		})
	end
	local smallX = if spec.bigOnLeft then 16 else -16
	local bigX = -smallX
	for pair = 1, PAIRS do
		local arrive = 1 + waveOffset(pair) + spec.waveDelay + 0.5
		local base = Config.speed * arrive + 20
		add(pair * 2 - 1, "small", smallX, arrive, base)
		if pair == PAIRS then
			add(pair * 2, "large", bigX, arrive, base + 20)
			for soak = 1, 7 do
				local kind = if soak == 7 then "large" else "small"
				add(pair * 2 - 1, kind, smallX, arrive, base - SOAK_STEP * soak)
			end
			for soak = 1, 3 do
				add(pair * 2, "large", bigX, arrive, base + 20 - SOAK_STEP * soak)
			end
		else
			add(pair * 2, "large", bigX, arrive, base)
			for soak = 1, spec.soaks[pair] do
				local x = if pair == 1 then bigX else smallX
				add(pair * 2 - 1, "large", x, arrive, base - SOAK_STEP * soak)
			end
		end
	end
	return clusters
end

local function deepFreeze<T>(t: T): T
	if type(t) == "table" then
		for _, child in t :: any do
			deepFreeze(child)
		end
		table.freeze(t :: any)
	end
	return t
end

local function make(
	name: string,
	seed: number,
	gates: { Gate },
	obstacles: { Obstacle },
	waves: WaveSpec
): Level.Layout
	return deepFreeze({
		name = name,
		seed = seed,
		startPlazaEnd = at(5),
		streetLength = at(100),
		plazaStart = at(90),
		halfWidth = 20,
		maxTotal = 2500,
		intendedRecruitTotal = 30,
		gates = gates,
		obstacles = obstacles,
		clusters = buildClusters(waves),
	} :: Level.Layout)
end

-- Layout A: the big group on the right, the familiar rhythm with a late add-200 / triple finale.
local calleMercado = make("calle-del-mercado", 0, {
	gate(1, 12, op("add", 15), op("multiply", 2)),
	gate(2, 22, op("multiply", 2), op("add", 20)),
	gate(3, 34, op("add", 30), op("add", 40)),
	gate(4, 48, op("add", 40), op("multiply", 2)),
	gate(5, 60, op("add", 50), op("add", 40)),
	gate(6, 72, op("add", 60), op("add", 100)),
	gate(7, 84, op("multiply", 3), op("add", 150)),
}, {
	obstacle(1, 40, "left"),
	obstacle(2, 64, "right"),
	obstacle(3, 88, "left"),
}, {
	waveDelay = 9,
	soaks = { 3, 4, 3, 3 },
	bigOnLeft = false,
})

-- Layout B: the large group on the left, a multiply early and a risky add-100 mid-route.
local portalDelSur = make("portal-del-sur", 1, {
	gate(1, 11, op("add", 25), op("add", 15)),
	gate(2, 20, op("add", 20), op("multiply", 2)),
	gate(3, 30, op("add", 40), op("add", 30)),
	gate(4, 44, op("add", 60), op("add", 50)),
	gate(5, 56, op("add", 40), op("add", 50)),
	gate(6, 70, op("add", 60), op("multiply", 2)),
	gate(7, 82, op("add", 120), op("multiply", 3)),
}, {
	obstacle(1, 36, "right"),
	obstacle(2, 60, "left"),
	obstacle(3, 86, "right"),
}, {
	waveDelay = 9,
	soaks = { 3, 4, 3, 3 },
	bigOnLeft = true,
})

-- Layout C: heavier opening groups and a multiply mid-route.
local esquinaDeLaBanda = make("esquina-de-la-banda", 2, {
	gate(1, 13, op("add", 20), op("add", 10)),
	gate(2, 24, op("add", 30), op("add", 20)),
	gate(3, 36, op("add", 40), op("add", 30)),
	gate(4, 50, op("add", 50), op("add", 40)),
	gate(5, 62, op("add", 40), op("multiply", 2)),
	gate(6, 76, op("add", 40), op("add", 80)),
	gate(7, 86, op("multiply", 3), op("add", 100)),
}, {
	obstacle(1, 42, "left"),
	obstacle(2, 66, "right"),
	obstacle(3, 80, "left"),
}, {
	waveDelay = 9,
	soaks = { 3, 4, 3, 3 },
	bigOnLeft = false,
})

Layouts.all = { calleMercado, portalDelSur, esquinaDeLaBanda }

-- Pure seed selection. A seed is a non-negative integer; it picks a layout by modulus. The
-- returned copy records the seed (layout.seed) so the run log shows which seed ran.
function Layouts.select(seed: number): Level.Layout
	if type(seed) ~= "number" or seed ~= seed or seed < 0 or seed == math.huge then
		error("seed must be a finite non-negative number", 2)
	end
	if seed ~= math.floor(seed) then
		error("seed must be an integer", 2)
	end
	local base = Layouts.all[(seed % #Layouts.all) + 1]
	local copy = table.clone(base :: any)
	copy.seed = seed
	return table.freeze(copy) :: any
end

return Layouts
