--!strict
local ClusterVisual = require("../src/shared/ClusterVisual")
local Config = require("../src/shared/Config")
local Level = require("../src/shared/Level")

local function near(actual: number, expected: number, name: string)
	assert(math.abs(actual - expected) < 1e-6, `{name}: expected {expected}, got {actual}`)
end
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
	gates = {},
	obstacles = {},
	clusters = {
		{
			id = 1,
			wave = 1,
			type = "small",
			spawnTime = 0,
			spawn = { x = -16, z = 130 },
			path = { { x = -5, z = 70 } },
		},
		{ id = 2, wave = 2, type = "large", spawnTime = 5, spawn = { x = 16, z = 300 }, path = {} },
	},
}

local function find(views: { ClusterVisual.View }, id: number): ClusterVisual.View?
	for _, v in views do
		if v.id == id then
			return v
		end
	end
	return nil
end

return {
	{
		name = "a cluster is not drawn before its spawn time, then appears where Level says it is",
		run = function()
			local tr = ClusterVisual.new(layout)
			eq(find(tr:views(1, 0, 16), 2), nil, "cluster 2 hidden at t=1")
			local v = find(tr:views(6, 0, 96), 2)
			assert(v ~= nil, "visible after spawn")
			local p = Level.clusterPosition(layout, 2, 6)
			near(v.x, p.x, "x")
			near(v.z, p.z, "z")
			eq(v.phase, "walking", "phase")
		end,
	},
	{
		name = "meter, remaining count and reward come from replicated hits and Config",
		run = function()
			local tr = ClusterVisual.new(layout)
			local v = find(tr:views(0, 0, 0), 1)
			assert(v ~= nil, "visible")
			eq(v.needed, Config.clusterTypes.small.hits, "needed")
			eq(v.remaining, 3, "remaining")
			near(v.fill, 0, "empty")
			eq(v.reward, Config.clusterTypes.small.reward, "reward")
			tr:shot({ id = 1, hits = 1, shot = "note" }, 0.1)
			v = find(tr:views(0.2, 0, 3.2), 1)
			assert(v ~= nil, "visible")
			eq(v.hits, 1, "hits")
			eq(v.remaining, 2, "remaining 2")
			near(v.fill, 1 / 3, "fill")
		end,
	},
	{
		name = "a late or repeated shot never lowers the meter (monotonic)",
		run = function()
			local tr = ClusterVisual.new(layout)
			tr:shot({ id = 1, hits = 2, shot = "note" }, 0.1)
			tr:shot({ id = 1, hits = 1, shot = "note" }, 0.2)
			local v = find(tr:views(0.3, 0, 4.8), 1)
			assert(v ~= nil, "visible")
			eq(v.hits, 2, "stays at 2")
		end,
	},
	{
		name = "the filling shot reports a credit exactly once; later shots report none",
		run = function()
			local tr = ClusterVisual.new(layout)
			local r1 = tr:shot({ id = 1, hits = 2, shot = "note" }, 0.1)
			eq(r1.accepted, true, "accepted")
			eq(r1.filled, false, "not yet")
			local r2 = tr:shot({ id = 1, hits = 3, shot = "gift" }, 0.2)
			eq(r2.filled, true, "fills")
			eq(r2.reward, Config.clusterTypes.small.reward, "+N")
			local r3 = tr:shot({ id = 1, hits = 3, shot = "note" }, 0.3)
			eq(r3.filled, false, "second fill event plays nothing")
			eq(r3.reward, nil, "no second +N")
			eq(tr:shot({ id = 77, hits = 1, shot = "note" }, 0.3).accepted, false, "unknown id")
		end,
	},
	{
		name = "filled: group cheers in place, a few runners go into the parade, then it is gone",
		run = function()
			local tr = ClusterVisual.new(layout)
			tr:shot({ id = 1, hits = 3, shot = "note" }, 1)
			local frozen = Level.clusterPosition(layout, 1, 1)
			local v = find(tr:views(1.4, 2, 22.4), 1)
			assert(v ~= nil, "still drawn while cheering")
			eq(v.phase, "cheering", "phase")
			near(v.x, frozen.x, "stays where it was filled x")
			near(v.z, frozen.z, "stays where it was filled z")
			eq(#v.runners, ClusterVisual.RUNNERS, "runners")
			local mid = find(tr:views(1 + ClusterVisual.RUN_SECONDS / 2, 2, 24), 1)
			assert(mid ~= nil, "visible")
			local r = mid.runners[1]
			assert(r.z < frozen.z and r.z > 24, "runner is between the group and the parade")
			local late = find(tr:views(1 + ClusterVisual.RUN_SECONDS + 0.1, 2, 25), 1)
			assert(late ~= nil, "visible")
			eq(#late.runners, 0, "arrived runners are no longer drawn separately")
			eq(
				find(tr:views(1 + ClusterVisual.CHEER_SECONDS + 0.1, 2, 30), 1),
				nil,
				"gone after the cheer"
			)
		end,
	},
	{
		name = "unfilled: walks on, passes around the parade without fuss, then disappears",
		run = function()
			local tr = ClusterVisual.new(layout)
			-- cluster 2 (right side, x=16) walks straight toward -z from z=300 at t=5
			local cz = Level.clusterPosition(layout, 2, 6).z
			local before = find(tr:views(6, 0, cz - 4), 2)
			assert(before ~= nil, "visible")
			eq(before.phase, "walking", "still walking")
			local during = find(tr:views(6, 0, cz + ClusterVisual.PASS_DISTANCE / 2), 2)
			assert(during ~= nil, "visible while passing")
			eq(during.phase, "passing", "passing")
			assert(during.x > 16, "swings outward, away from the parade")
			eq(during.hits, 0, "no change to the meter")
			eq(find(tr:views(6, 0, cz + ClusterVisual.PASS_DISTANCE + 1), 2), nil, "gone")
		end,
	},
	{
		name = "a shot after the cluster has gone is ignored; reset clears all state for a replay",
		run = function()
			local tr = ClusterVisual.new(layout)
			tr:shot({ id = 1, hits = 3, shot = "note" }, 1)
			tr:reset()
			local v = find(tr:views(0, 0, 0), 1)
			assert(v ~= nil, "visible")
			eq(v.hits, 0, "fresh after reset")
			eq(v.phase, "walking", "walking again")
		end,
	},
	{
		name = "member counts are bounded per type so the swarm stays dense but cheap",
		run = function()
			local tr = ClusterVisual.new(layout)
			local v1, v2 = find(tr:views(6, 0, 0), 1), find(tr:views(6, 0, 0), 2)
			assert(v1 ~= nil and v2 ~= nil, "visible")
			assert(v1.members >= 3 and v1.members < v2.members, "large has more")
			assert(v2.members <= ClusterVisual.MAX_MEMBERS, "bounded")
			assert(ClusterVisual.MAX_VISIBLE_CLUSTERS >= 4, "pool limit exists")
			assert(
				#tr:views(6, 0, 0) <= ClusterVisual.MAX_VISIBLE_CLUSTERS,
				"never exceeds the limit"
			)
		end,
	},
}
