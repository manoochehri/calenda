--!strict
local Crossing = require("../src/shared/Crossing")
local Level = require("../src/shared/Level")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local layout: Level.Layout = {
	name = "t",
	seed = 0,
	streetLength = 1600,
	plazaStart = 1440,
	halfWidth = 20,
	maxTotal = 1000,
	intendedRecruitTotal = 0,
	gates = {
		{
			id = 2,
			z = 100,
			left = { kind = "add", value = 1 },
			right = { kind = "add", value = 2 },
		},
		{
			id = 1,
			z = 100,
			left = { kind = "add", value = 1 },
			right = { kind = "add", value = 2 },
		},
		{
			id = 3,
			z = 200,
			left = { kind = "add", value = 1 },
			right = { kind = "add", value = 2 },
		},
	},
	obstacles = {
		{ id = 1, z = 300, side = "left" },
		{ id = 2, z = 300, side = "right" },
	},
	clusters = {},
}

local function ids(list: { { id: number } }): string
	local out = {}
	for _, v in list do
		table.insert(out, tostring(v.id))
	end
	return table.concat(out, ",")
end

return {
	{
		name = "gate is crossed once when z passes its plane (z0 < gate.z <= z1)",
		run = function()
			eq(ids(Crossing.gatesCrossed(layout, 99, 101)), "1,2", "both at z100 in id order")
			eq(ids(Crossing.gatesCrossed(layout, 100, 101)), "", "already at the plane, not again")
			eq(ids(Crossing.gatesCrossed(layout, 99, 100)), "1,2", "exactly on the plane counts")
			eq(ids(Crossing.gatesCrossed(layout, 0, 150)), "1,2", "no tunnelling to z200")
			eq(
				ids(Crossing.gatesCrossed(layout, 0, 250)),
				"1,2,3",
				"big step crosses several, in order"
			)
			eq(ids(Crossing.gatesCrossed(layout, 250, 99)), "", "backwards crosses nothing")
		end,
	},
	{
		name = "gate crossing ignores lateral position (the pair resolves it)",
		run = function()
			eq(#Crossing.gatesCrossed(layout, 150, 250), 1, "one gate")
		end,
	},
	{
		name = "obstacle: lead hitbox overlapping the closed lane hits it",
		run = function()
			-- lead on the left, far from the right lane
			eq(ids(Crossing.obstaclesHit(layout, 299, 301, -10, -10)), "1", "left lane only")
			eq(ids(Crossing.obstaclesHit(layout, 299, 301, 10, 10)), "2", "right lane only")
		end,
	},
	{
		name = "obstacle: centre line is inside the hitbox of both lanes",
		run = function()
			eq(ids(Crossing.obstaclesHit(layout, 299, 301, 0, 0)), "1,2", "both")
		end,
	},
	{
		name = "obstacle: misses when short of or past the obstacle depth",
		run = function()
			local c = Crossing
			eq(ids(c.obstaclesHit(layout, 280, 285, -10, -10)), "", "short")
			eq(ids(c.obstaclesHit(layout, 310, 320, -10, -10)), "", "past")
		end,
	},
	{
		name = "obstacle: a large step does not tunnel through the obstacle",
		run = function()
			eq(ids(Crossing.obstaclesHit(layout, 250, 350, -10, -10)), "1", "swept")
		end,
	},
	{
		name = "obstacle: lateral sweep within the tick counts",
		run = function()
			-- starts well on the right, ends on the left: touches left lane
			eq(ids(Crossing.obstaclesHit(layout, 299, 301, 10, -10)), "1,2", "both swept")
		end,
	},
	{
		name = "obstacle hitbox is the lead's fixed size, not the parade's",
		run = function()
			local hb = Crossing.LEAD_HITBOX
			assert(hb.halfWidth > 0 and hb.halfDepth > 0, "positive")
			eq(table.isfrozen(hb), true, "frozen")
			-- just outside the lead hitbox of the left lane's inner edge (x = 0)
			eq(
				ids(
					Crossing.obstaclesHit(
						layout,
						299,
						301,
						hb.halfWidth + 0.01,
						hb.halfWidth + 0.01
					)
				),
				"2",
				"only right"
			)
		end,
	},
	{
		name = "non-finite inputs never hit or cross anything",
		run = function()
			eq(#Crossing.gatesCrossed(layout, 0 / 0, 500), 0, "nan z0")
			eq(#Crossing.gatesCrossed(layout, 0, math.huge), 0, "inf z1")
			eq(#Crossing.obstaclesHit(layout, 290, 310, 0 / 0, 0), 0, "nan x")
		end,
	},
}
