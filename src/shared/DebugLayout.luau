--!strict
-- The fixed debug layout (issue #7), authored against the spec s9 timeline at Config.speed = 16
-- (1 s = 16 studs, plaza at 1440 studs = 90 s). Plain data; LayoutValidator proves the timeline.
-- Waves alternate left, right, left, ... Left is negative x. Sidewalks are |x| = 16; this fixed
-- layout keeps clusters on their authored sidewalk as they approach.
local Level = require("./Level")

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
	local smallZ = 16 * spawnTime + 30
	-- Move the high-hit target closer as the authored route raises the fire rate. Center fire
	-- first spends 3 hits on the small target; steering toward the large target early can finish
	-- its 8-hit meter before it reaches the parade.
	local largeOffset = if pair <= 3
		then 72
		elseif pair <= 6 then 55
		elseif pair <= 8 then 45
		elseif pair == 9 then 38
		else 28
	local largeZ = 16 * spawnTime + largeOffset
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
	streetLength = 1600,
	plazaStart = 1440,
	halfWidth = 20,
	maxTotal = 1500,
	intendedRecruitTotal = 30,
	gates = {
		{
			id = 1,
			z = 192,
			left = { kind = "add", value = 15 },
			right = { kind = "multiply", value = 2 },
		}, -- 12s
		{
			id = 2,
			z = 320,
			left = { kind = "multiply", value = 2 },
			right = { kind = "add", value = 20 },
		}, -- 20s
		{
			id = 3,
			z = 512,
			left = { kind = "add", value = 30 },
			right = { kind = "add", value = 40 },
		}, -- 32s
		{
			id = 4,
			z = 736,
			left = { kind = "add", value = 40 },
			right = { kind = "add", value = 50 },
		}, -- 46s
		{
			id = 5,
			z = 928,
			left = { kind = "add", value = 50 },
			right = { kind = "add", value = 40 },
		}, -- 58s
		{
			id = 6,
			z = 1152,
			left = { kind = "add", value = 80 },
			right = { kind = "add", value = 100 },
		}, -- 72s
		{
			id = 7,
			z = 1344,
			left = { kind = "multiply", value = 3 },
			right = { kind = "add", value = 200 },
		}, -- 84s
	},
	obstacles = {
		{ id = 1, z = 640, side = "left" }, -- 40s
		{ id = 2, z = 1024, side = "right" }, -- 64s
		{ id = 3, z = 1408, side = "left" }, -- 88s
	},
	clusters = clusters,
}

return deepFreeze(layout)
