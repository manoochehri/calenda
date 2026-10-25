--!strict
-- The fixed debug layout (issue #7), authored against the spec s9 timeline. Its original authored
-- distances use a 16 studs/s baseline; scale them with Config.speed so the ~90 s route and beats
-- stay stable when the forward pace is tuned. LayoutValidator proves the timeline.
-- Waves alternate left, right, left, ... Left is negative x. Sidewalks are |x| = 16; this fixed
-- layout keeps clusters on their authored sidewalk as they approach.
local Config = require("./Config")
local Emergence = require("./Emergence")
local Level = require("./Level")

local BASE_SPEED = 16
local START_PLAZA_BASE_LENGTH = 80
local START_PLAZA_LENGTH = START_PLAZA_BASE_LENGTH * Config.speed / BASE_SPEED
local function paceDistance(baseZ: number): number
	return baseZ * Config.speed / BASE_SPEED
end

-- Issue #65 (tension from the top). DATA CHANGE for the skeptic; provisional like the
-- continuous-fire retune until the #17 ladder is re-run. Why the numbers moved:
--  * Waves must EMERGE from beyond the camera's view (Emergence.requiredSpawnOffset, about 208
--    studs ahead) instead of popping in 15-40 studs ahead. A cluster is therefore in firing range
--    (60 studs) for the whole approach, 60 / (speed + approachSpeed) seconds, instead of the 1 s the
--    old spawn offsets gave, so the same wave is far easier to convert. To keep the Amendment 1
--    checks true (no-input run defeated, competent run completed with followers left, ADR 0006) the data changes:
--    1. spectators.approachSpeed 6 -> 20 (Config): the mob CHARGES; closing speed 34.4 studs/s keeps
--       the visible approach at 3.7 s (a rule, tested) and the range window at 1.7 s.
--    2. WAVE_DELAY: every pair arrives 9 s later than before (a calm opening: the first wave is
--       first in view after 5 s).
--    3. SOAKS: each pair grows a line of extra small groups on the left, a little nearer the lead
--       than the big group on the right ("waves of rising size"). Unsteered fire spends its hits on
--       the nearest groups, so the big group is not converted; a player who steers right converts
--       it and still has hits left over for the soaks. Rising size matches the rising fire rate.
--  * Each cluster's path is extended BACKWARD along its straight line (spawn earlier and farther
--    away, rounded up to quarter seconds) until it spawns beyond the visible depth + margin. From
--    the old geometry on, positions are unchanged.
local WAVE_DELAY = 9 -- seconds [default]
local SOAKS = { 0, 1, 1, 2, 2, 3, 3, 4, 4, 4 } -- [default] extra small groups per pair
local SOAK_STEP = 1.5 -- [default] studs each soak sits nearer the lead than the one before

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
for pair = 1, 10 do
	local arrive = 1 + (pair - 1) * 2.5 + WAVE_DELAY -- the old spawn time, shifted
	local base = Config.speed * arrive + 20 -- z of the small group, as before
	add(pair * 2 - 1, "small", -16, arrive, base)
	add(pair * 2, "large", 16, arrive, base)
	for soak = 1, SOAKS[pair] do
		add(pair * 2 - 1, "small", -16, arrive, base - SOAK_STEP * soak)
	end
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

local layout: Level.Layout = {
	name = "debug-1",
	seed = 0,
	startPlazaEnd = START_PLAZA_LENGTH,
	streetLength = paceDistance(1600),
	plazaStart = paceDistance(1440),
	halfWidth = 20,
	-- 2500 (was 1500): the continuous-fire base rate of 6/s (ADR 0004) converts more clusters on the
	-- best route (real scripted run 2010, noisy runs up to about 2430; the validator reports 1785). Provisional until the #17 ladder is re-run.
	maxTotal = 2500,
	intendedRecruitTotal = 30,
	gates = {
		{
			id = 1,
			z = paceDistance(192),
			left = { kind = "add", value = 15 },
			right = { kind = "multiply", value = 2 },
		}, -- 12s
		{
			id = 2,
			z = paceDistance(320),
			left = { kind = "multiply", value = 2 },
			right = { kind = "add", value = 20 },
		}, -- 20s
		{
			id = 3,
			z = paceDistance(512),
			left = { kind = "add", value = 30 },
			right = { kind = "add", value = 40 },
		}, -- 32s
		{
			id = 4,
			z = paceDistance(736),
			left = { kind = "add", value = 40 },
			right = { kind = "add", value = 50 },
		}, -- 46s
		{
			id = 5,
			z = paceDistance(928),
			left = { kind = "add", value = 50 },
			right = { kind = "add", value = 40 },
		}, -- 58s
		{
			id = 6,
			z = paceDistance(1152),
			left = { kind = "add", value = 80 },
			right = { kind = "add", value = 100 },
		}, -- 72s
		{
			id = 7,
			z = paceDistance(1344),
			left = { kind = "multiply", value = 3 },
			right = { kind = "add", value = 200 },
		}, -- 84s
	},
	obstacles = {
		{ id = 1, z = paceDistance(640), side = "left" }, -- 40s
		{ id = 2, z = paceDistance(1024), side = "right" }, -- 64s
		{ id = 3, z = paceDistance(1408), side = "left" }, -- 88s
	},
	clusters = clusters,
	-- Issue #96: the first Oaxacan level's hazards. Tomatoes from the buildings and a tlayuda cart.
	hazardSet = {
		kinds = { "tomato", "cart" },
		firstAt = 20,
		lastAt = 80,
		minGap = 14,
		maxGap = 22,
	},
}

return deepFreeze(layout)
