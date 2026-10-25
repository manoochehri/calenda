--!strict
-- The fixed debug layout (issue #7), authored against the spec s9 timeline. Its original authored
-- distances use a 16 studs/s baseline; scale them with Config.speed so the ~90 s route and beats
-- stay stable when the forward pace is tuned. LayoutValidator proves the timeline.
-- Waves alternate left, right, left, ... Left is negative x. Sidewalks are |x| = 16; this fixed
-- layout keeps clusters on their authored sidewalk as they approach.
local Level = require("./Level")
local Config = require("./Config")

local BASE_SPEED = 16
local START_PLAZA_BASE_LENGTH = 80
local START_PLAZA_LENGTH = START_PLAZA_BASE_LENGTH * Config.speed / BASE_SPEED
local function paceDistance(baseZ: number): number
	return baseZ * Config.speed / BASE_SPEED
end
local function waveSpawnZ(spawnTime: number, baseGap: number): number
	-- Keep the original run-time until a wave reaches the lead as the lead speed changes. Both
	-- speeds contribute to closure; only the authored spawn gap needs to compensate.
	local currentClosingSpeed = Config.speed + Config.spectators.approachSpeed
	local baselineClosingSpeed = BASE_SPEED + Config.spectators.approachSpeed
	return Config.speed * spawnTime + baseGap * currentClosingSpeed / baselineClosingSpeed
end

-- Each pair presents one small and one large target on alternating sides. Their offsets tighten
-- through the route as the authored gates raise firing rate: unattended fire converts early small
-- targets but leaves large threats unfilled, while a player can pre-steer to those threats.
local clusters: { Level.Cluster } = {}
for pair = 1, 10 do
	local spawnTime = 1 + (pair - 1) * 2.5
	local smallWave = pair * 2 - 1
	local largeWave = pair * 2
	local smallX = if smallWave % 2 == 1 then -16 else 16
	local largeX = if largeWave % 2 == 1 then -16 else 16
	local smallZ = waveSpawnZ(spawnTime, 20)
	-- Retuned for continuous fire (ADR 0004: base 6/s, cap 20/s; was 3/s, 12/s, offsets 30 and
	-- 72..28): every offset is shorter so unsteered fire still loses the large targets. Provisional
	-- until the #17 ladder is re-run.
	-- Move the high-hit target closer as the authored route raises the fire rate. Center fire
	-- first spends 3 hits on the small target; steering toward the large target early can finish
	-- its 8-hit meter before it reaches the parade.
	local largeOffset = if pair <= 3
		then 40
		elseif pair <= 6 then 30
		elseif pair <= 8 then 25
		elseif pair == 9 then 20
		else 15
	local largeZ = waveSpawnZ(spawnTime, largeOffset)
	table.insert(clusters, {
		id = #clusters + 1,
		wave = smallWave,
		type = "small",
		spawnTime = spawnTime,
		spawn = { x = smallX, z = smallZ },
		path = {},
	})
	table.insert(clusters, {
		id = #clusters + 1,
		wave = largeWave,
		type = "large",
		spawnTime = spawnTime,
		spawn = { x = largeX, z = largeZ },
		path = {},
	})
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
}

return deepFreeze(layout)
