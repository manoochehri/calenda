--!strict
-- The fixed debug layout (issue #7), authored against the spec s9 timeline at Config.speed = 16
-- (1 s = 16 studs, plaza at 1440 studs = 90 s). Plain data; LayoutValidator proves the timeline.
-- Waves alternate left, right, left, ... Left is negative x. Sidewalks are |x| = 16; clusters turn
-- into the lane (|x| = 5) and walk on toward the parade.
local Level = require("./Level")

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
	intendedRecruitTotal = 145,
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
	clusters = {
		{
			id = 1,
			wave = 1,
			type = "small",
			spawnTime = 0,
			spawn = { x = -16, z = 130 },
			path = { { x = -5, z = 70 } },
		},
		{
			id = 2,
			wave = 1,
			type = "small",
			spawnTime = 0,
			spawn = { x = -16, z = 190 },
			path = { { x = -5, z = 130 } },
		},
		{
			id = 3,
			wave = 2,
			type = "large",
			spawnTime = 9,
			spawn = { x = 16, z = 314 },
			path = { { x = 5, z = 254 } },
		},
		{
			id = 4,
			wave = 2,
			type = "small",
			spawnTime = 9,
			spawn = { x = 16, z = 384 },
			path = { { x = 5, z = 324 } },
		},
		{
			id = 5,
			wave = 3,
			type = "large",
			spawnTime = 22,
			spawn = { x = -16, z = 522 },
			path = { { x = -5, z = 462 } },
		},
		{
			id = 6,
			wave = 3,
			type = "small",
			spawnTime = 22,
			spawn = { x = -16, z = 592 },
			path = { { x = -5, z = 532 } },
		},
		{
			id = 7,
			wave = 4,
			type = "large",
			spawnTime = 36,
			spawn = { x = 16, z = 746 },
			path = { { x = 5, z = 686 } },
		},
		{
			id = 8,
			wave = 4,
			type = "small",
			spawnTime = 36,
			spawn = { x = 16, z = 816 },
			path = { { x = 5, z = 756 } },
		},
		{
			id = 9,
			wave = 5,
			type = "large",
			spawnTime = 50,
			spawn = { x = -16, z = 970 },
			path = { { x = -5, z = 910 } },
		},
		{
			id = 10,
			wave = 5,
			type = "small",
			spawnTime = 50,
			spawn = { x = -16, z = 1040 },
			path = { { x = -5, z = 980 } },
		},
		{
			id = 11,
			wave = 5,
			type = "small",
			spawnTime = 50,
			spawn = { x = -16, z = 1100 },
			path = { { x = -5, z = 1040 } },
		},
		{
			id = 12,
			wave = 6,
			type = "large",
			spawnTime = 62,
			spawn = { x = 16, z = 1162 },
			path = { { x = 5, z = 1102 } },
		},
		{
			id = 13,
			wave = 6,
			type = "small",
			spawnTime = 62,
			spawn = { x = 16, z = 1232 },
			path = { { x = 5, z = 1172 } },
		},
		{
			id = 14,
			wave = 7,
			type = "large",
			spawnTime = 72,
			spawn = { x = -16, z = 1322 },
			path = { { x = -5, z = 1262 } },
		},
		{
			id = 15,
			wave = 7,
			type = "large",
			spawnTime = 72,
			spawn = { x = -16, z = 1412 },
			path = { { x = -5, z = 1352 } },
		},
	},
}

return deepFreeze(layout)
