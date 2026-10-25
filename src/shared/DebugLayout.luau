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

-- Issue #65: the authored wave layout keeps its delayed opening, increasing wave sizes, and
-- backward path extension so mobs emerge beyond the visible depth + margin. `add` derives the
-- required spawn offset from camera emergence and the current lead + mob closing speed.
local WAVE_DELAY = 9.5 -- seconds [default]
local function waveOffset(pair: number): number
	return (pair - 1) * 7.8 -- five-group packs overlap within the low-quality visible cap
end
local SOAKS = { 4, 5, 2, 1 } -- front-load groups for earlier attacks; keep later packs lighter
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
for pair = 1, 4 do
	local arrive = 1 + waveOffset(pair) + WAVE_DELAY
	local base = Config.speed * arrive + 20 -- z of the small group, as before
	add(pair * 2 - 1, "small", -16, arrive, base)
	if pair == 4 then
		add(pair * 2, "large", 16, arrive, base + 20)
		for soak = 1, 4 do
			add(pair * 2 - 1, "small", -16, arrive, base - SOAK_STEP * soak)
		end
		add(pair * 2 - 1, "large", -16, arrive, base - SOAK_STEP * 7)
		for soak = 1, 3 do
			add(pair * 2, "large", 16, arrive, base + 20 - SOAK_STEP * soak)
		end
	else
		local largeBase = if pair == 1 then base + 20 else base
		add(pair * 2, "large", 16, arrive, largeBase)
		for soak = 1, SOAKS[pair] do
			local x = if pair == 1 then 16 else -16
			local wave = if pair == 1 then pair * 2 else pair * 2 - 1
			add(wave, "large", x, arrive, largeBase - SOAK_STEP * soak)
		end
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
}

return deepFreeze(layout)
