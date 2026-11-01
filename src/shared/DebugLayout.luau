--!strict
-- The fixed debug layout (issue #7), authored against the spec s9 timeline. Its original authored
-- distances use a 16 studs/s baseline; scale them with Config.speed so the ~90 s route and beats
-- stay stable when the forward pace is tuned. LayoutValidator proves the timeline.
-- Waves alternate left, right, left, ... Left is negative x. Outer-lane groups spawn at the lane
-- centers, |x| = 10 (ADR 0011, Amendment 9), and each cluster carries its authored lane (ADR 0010).
local Config = require("./Config")
local Emergence = require("./Emergence")
local Level = require("./Level")
local StreetGeometry = require("./StreetGeometry")

local BASE_SPEED = 16
local LANE_CENTER = StreetGeometry.LANE_CENTER -- ADR 0011: outer-lane spawns at the lane centers
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
--    1. spectators.approachSpeed 6 -> 20 (Config): the mob CHARGES; this originally gave 34.4
--       studs/s relative closing speed, a 3.7 s visible approach (tested) and a 1.7 s range window.
--       Issue #174 lowers the lead pace by half and raises approachSpeed to 27.2 to preserve the
--       center-relative closing rate algebraically. This is not a player-balance claim.
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
local SOAKS = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } -- [default] extra small groups per pair (#206: none; one horde lane, as Layouts)
local LARGE_TRAIL = 14 -- studs the large group of a pair sits behind its small group (one lane)
local PLAZA_SECONDS = 90 -- run seconds at which the plaza starts (paceDistance(1440) at Config.speed)
local LAST_ARRIVAL_MARGIN = 2 -- seconds: the last wave arrives at least this long before the plaza
local SOAK_STEP = 1.5 -- [default] studs each soak sits nearer the lead than the one before

local needOffset = Emergence.requiredSpawnOffset()
local closing = Config.speed + Config.spectators.approachSpeed
local clusters: { Level.Cluster } = {}
local function add(
	wave: number,
	kind: string,
	x: number,
	lane: "left" | "center" | "right",
	spawnTime: number,
	spawnZ: number
)
	local offset = spawnZ - Config.speed * spawnTime
	local back = math.max(0, math.ceil((needOffset - offset) / closing * 4) / 4)
	table.insert(clusters, {
		id = #clusters + 1,
		wave = wave,
		type = kind,
		spawnTime = spawnTime - back,
		spawn = { x = x, z = spawnZ + Config.spectators.approachSpeed * back },
		path = {},
		lane = lane,
	})
end
-- Issue #192: the wave rhythm continues to the plaza, as it does in Layouts (issue #142). The loop
-- once stopped at pair 10 (32.5 s), so the played level had no hordes for the last 60 s of a 90 s
-- run. Pairs past the authored soak list repeat its last count.
local pair = 0
while true do
	pair += 1
	local arrive = 1 + (pair - 1) * 2.5 + WAVE_DELAY -- the old spawn time, shifted
	if arrive > PLAZA_SECONDS - LAST_ARRIVAL_MARGIN then
		break
	end
	local base = Config.speed * arrive + 20 -- z of the small group, as before
	-- Issue #206 (Amendment 12): every horde comes down ONE lane (the right), as in Layouts. #213
	-- changed Layouts only, but THIS is the level that is played (RunServer "oaxacan-street").
	-- The large group comes every second pair and trails its pair's small group by LARGE_TRAIL.
	add(pair * 2 - 1, "small", LANE_CENTER, "right", arrive, base)
	if pair % 2 == 0 then
		add(pair * 2, "large", LANE_CENTER, "right", arrive, base + LARGE_TRAIL)
	end
	for soak = 1, SOAKS[math.min(pair, #SOAKS)] do
		add(pair * 2 - 1, "small", LANE_CENTER, "right", arrive, base - SOAK_STEP * soak)
	end
end

-- Spec Amendment 15 schedule (travel-seconds): strips of 4, 4 and 2, 3.4 s apart (spans never overlap).
local pickups: { Level.Pickup } = {}
for _, seconds in { 8, 11.4, 14.8, 18.2, 39, 42.4, 45.8, 49.2, 73.5, 76.9 } do
	table.insert(
		pickups,
		{ id = #pickups + 1, z = paceDistance(seconds * BASE_SPEED), lane = "left" }
	)
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
	halfWidth = StreetGeometry.HALF_WIDTH,
	leadLimit = StreetGeometry.LEAD_LIMIT, -- ADR 0010 item 3: the one per-layout lead clamp
	-- The bound lives in Config.layout.maxTotal (issue #142 owner decision, 2026-10-26).
	maxTotal = Config.layout.maxTotal,
	intendedRecruitTotal = 30,
	-- Issue #238 (P0): every gate row is a REAL choice, +N versus xK, and the crossover (the crowd at
	-- which the two give the same result, N / (K - 1)) lies inside the crowd range actually reached
	-- at that gate. LayoutValidator enforces both (gate dominance over 0..maxTotal, and the crossover
	-- inside the range the LayoutWitness runs reach). The old seven rows had four add-versus-add rows
	-- where one board was better at every crowd size. Seven add-versus-x2 rows also cannot stay under
	-- maxTotal (each greedy run doubles seven times), so the count is four, not seven: the two early
	-- rows and the final row that the spec s9 timeline windows require, plus the 50 s row.
	-- Crowd range reached on arrival (9 policies x 5 seeds = 45 runs, of which 35 to 41 reach each gate; these are about 9 distinct
	-- trajectories, so report distinct crowd values, not runs), and where
	-- each crossover sits in it: tests/issue238_gate_choice.test.luau prints and pins them. Balance
	-- and winnability are UNVERIFIED until the skeptic has reviewed them.
	gates = {
		{
			id = 1,
			z = paceDistance(208),
			left = { kind = "add", value = 20 },
			right = { kind = "multiply", value = 4 },
		}, -- 13s: crossover 7 (reached non-zero crowds 5, 10)
		{
			id = 2,
			z = paceDistance(392),
			left = { kind = "multiply", value = 2 },
			right = { kind = "add", value = 35 },
		}, -- 24.5s: crossover 35
		{
			id = 3,
			z = paceDistance(800),
			left = { kind = "add", value = 80 },
			right = { kind = "multiply", value = 2 },
		}, -- 50s: crossover 80 (refit from 40 for the #156 pickups, which lift the crowd reached here to 44 to 164)
		{
			id = 4,
			z = paceDistance(1280),
			left = { kind = "multiply", value = 2 },
			right = { kind = "add", value = 300 },
		}, -- 80s: crossover 300
	},
	obstacles = {
		{ id = 1, z = paceDistance(640), side = "right" }, -- 40s (right: the left lane is the pickup lane, ADR 0014)
		{ id = 2, z = paceDistance(1024), side = "right" }, -- 64s
		{ id = 3, z = paceDistance(1408), side = "left" }, -- 88s
	},
	clusters = clusters,
	-- Issue #156 / ADR 0014: the horde lane is right, so pickups are left and recruits come down the
	-- center. Ten +1 pickups in three strips (Amendment 15 schedule).
	laneRoles = { pickup = "left", horde = "right", recruit = "center" },
	pickups = pickups,
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
