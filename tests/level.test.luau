--!strict
local Config = require("../src/shared/Config")
local Level = require("../src/shared/Level")

local function near(actual: number, expected: number, name: string)
	assert(math.abs(actual - expected) < 1e-6, `{name}: expected {expected}, got {actual}`)
end

local function layout(): Level.Layout
	return {
		name = "t",
		seed = 0,
		streetLength = 1600,
		plazaStart = 1440,
		halfWidth = 20,
		leadLimit = 15,
		maxTotal = 1000,
		intendedRecruitTotal = 0,
		gates = {},
		obstacles = {},
		clusters = {
			-- straight down the left sidewalk, active from t = 2
			{
				id = 1,
				wave = 1,
				type = "small",
				spawnTime = 2,
				spawn = { x = -16, z = 200 },
				path = {},
			},
			-- 3-4-5 triangle leg then straight on: (0,100) -> (30,140) is length 50
			{
				id = 2,
				wave = 1,
				type = "large",
				spawnTime = 0,
				spawn = { x = 0, z = 100 },
				path = { { x = 30, z = 60 } },
				lane = "center",
			},
		},
	}
end

return {
	{
		name = "cluster waits at spawn until spawnTime",
		run = function()
			local p = Level.clusterPosition(layout(), 1, 0)
			near(p.x, -16, "x@0")
			near(p.z, 200, "z@0")
			local q = Level.clusterPosition(layout(), 1, 2)
			near(q.z, 200, "z@spawnTime")
		end,
	},
	{
		name = "straight cluster advances at approachSpeed toward the parade (-z)",
		run = function()
			local v = Config.spectators.approachSpeed
			local p = Level.clusterPosition(layout(), 1, 5)
			near(p.x, -16, "x")
			near(p.z, 200 - v * 3, "z")
		end,
	},
	{
		name = "polyline: arclength along waypoints, then straight on in -z",
		run = function()
			local v = Config.spectators.approachSpeed
			-- segment (0,100)->(30,60) is length 50
			local mid = Level.clusterPosition(layout(), 2, 25 / v)
			near(mid.x, 15, "mid x")
			near(mid.z, 80, "mid z")
			local atEnd = Level.clusterPosition(layout(), 2, 50 / v)
			near(atEnd.x, 30, "end x")
			near(atEnd.z, 60, "end z")
			local past = Level.clusterPosition(layout(), 2, 50 / v + 2)
			near(past.x, 30, "past x")
			near(past.z, 60 - 2 * v, "past z")
		end,
	},
	{
		name = "position is a pure function: same inputs, same output",
		run = function()
			local l = layout()
			local a = Level.clusterPosition(l, 2, 3.7)
			local b = Level.clusterPosition(l, 2, 3.7)
			near(a.x, b.x, "x")
			near(a.z, b.z, "z")
		end,
	},
	{
		name = "an explicit config overrides approachSpeed",
		run = function()
			local cfg = { spectators = { approachSpeed = 10, centerTolerance = 3 }, speed = 16 }
			local p = Level.clusterPosition(layout(), 1, 3, cfg :: any)
			near(p.z, 190, "z with speed 10")
		end,
	},
	{
		name = "unknown cluster id and negative time are errors",
		run = function()
			assert(not pcall(Level.clusterPosition, layout(), 99, 1), "unknown id")
			assert(not pcall(Level.clusterPosition, layout(), 1, -1), "negative t")
		end,
	},
	{
		name = "sideOf uses the sign of x and centerTolerance",
		run = function()
			assert(Level.sideOf(-16) == "left", "sideOf")
			assert(Level.sideOf(16) == "right", "sideOf")
			assert(Level.sideOf(0) == "center", "sideOf")
			assert(Level.sideOf(Config.spectators.centerTolerance) == "center", "sideOf")
			assert(Level.sideOf(Config.spectators.centerTolerance + 0.01) == "right", "sideOf")
			assert(Level.sideOf(-Config.spectators.centerTolerance - 0.01) == "left", "sideOf")
		end,
	},
	{
		name = "leadZ and timeAtZ are inverse at Config speed",
		run = function()
			near(Level.leadZ(10), 10 * Config.speed, "leadZ")
			near(Level.timeAtZ(Level.leadZ(7.5)), 7.5, "roundtrip")
		end,
	},
}
