--!strict
local ClusterVisual = require("../src/shared/ClusterVisual")
local Config = require("../src/shared/Config")
local Emergence = require("../src/shared/Emergence")
local Level = require("../src/shared/Level")
local MobCharge = require("../src/shared/MobCharge")

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
	leadLimit = 15,
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
		name = "unfilled: the mob CHARGES straight in (no veer-away), stops at the lead and waits for the attack Event",
		run = function()
			local tr = ClusterVisual.new(layout)
			-- cluster 2 (right side, x=16) walks straight toward -z from z=300 at t=5
			local cz = Level.clusterPosition(layout, 2, 6).z
			local before = find(tr:views(6, 0, cz - 40), 2)
			assert(before ~= nil, "visible")
			eq(before.phase, "walking", "still walking")
			near(before.x, 16, "straight down the lane")
			-- the lead catches up with the mob: it never swings out, whatever the distance
			for _, past in { 0, 3, 10, 20, 30 } do
				local v = find(tr:views(6, 0, cz + past), 2)
				assert(v ~= nil, `drawn at {past} studs past (waiting for the Event)`)
				near(v.x, 16, `no sideways swing at {past}`)
				eq(v.phase, "walking", "pinned in front of the lead, not passing")
				near(v.z, cz + past + MobCharge.SLAM_GAP, "front stays SLAM_GAP ahead of the lead")
			end
		end,
	},
	{
		name = "the attack Event starts the slam, then the mob disperses to the sidewalk, then it is gone; a lost Event still plays after SLAM_FALLBACK",
		run = function()
			local tr = ClusterVisual.new(layout)
			local cz = Level.clusterPosition(layout, 2, 6).z
			local leadZ = cz + 1 -- the mob has reached the parade
			assert(find(tr:views(6, 0, leadZ), 2) ~= nil, "find(tr:views(6, 0, leadZ), 2) ~= nil")
			tr:attack(2, 6.05)
			local slam = find(tr:views(6.2, 0, leadZ), 2)
			assert(slam ~= nil, "visible")
			eq(slam.phase, "slamming", "slamming")
			assert(slam.phaseT > 0 and slam.phaseT < 1, "progress")
			local disp = find(tr:views(6.05 + MobCharge.SLAM_SECONDS + 0.3, 0, leadZ), 2)
			assert(disp ~= nil, "visible")
			eq(disp.phase, "dispersing", "dispersing")
			eq(disp.hits, 0, "no change to the meter")
			eq(
				find(
					tr:views(
						6.05 + MobCharge.SLAM_SECONDS + MobCharge.DISPERSE_SECONDS + 30,
						0,
						leadZ
					),
					2
				),
				nil,
				"gone after last independent arrival"
			)
			-- the same Event twice does not restart the slam
			tr:attack(2, 7.5)
			eq(find(tr:views(6.2, 0, leadZ), 2).phase, "slamming", "first Event wins")
			-- no Event at all: the fallback plays the slam anyway
			local lost = ClusterVisual.new(layout)
			assert(
				find(lost:views(6, 0, leadZ), 2) ~= nil,
				"find(lost:views(6, 0, leadZ), 2) ~= nil"
			)
			eq(find(lost:views(6.2, 0, leadZ), 2).phase, "walking", "still waiting")
			eq(
				find(lost:views(6 + MobCharge.SLAM_FALLBACK + 0.1, 0, leadZ), 2).phase,
				"slamming",
				"fallback slam"
			)
		end,
	},
	{
		name = "a converted mob never slams or disperses: it recolours and streams in",
		run = function()
			local tr = ClusterVisual.new(layout)
			tr:shot({ id = 2, hits = 8, shot = "note" }, 6)
			tr:attack(2, 6.1) -- a stray Event after the fill changes nothing
			local v = find(tr:views(6.5, 0, 40), 2)
			assert(v ~= nil, "visible")
			eq(v.phase, "cheering", "cheering")
			assert(v.age > 0.4 and v.age < 0.6, "age since the fill")
		end,
	},
	{
		name = "mobs beyond the visible depth plus margin are not drawn at all (no pop at the far end)",
		run = function()
			local tr = ClusterVisual.new(layout)
			local _, deepest = Emergence.depthRange()
			local far = Level.clusterPosition(layout, 2, 6).z
			eq(find(tr:views(6, 0, far - deepest - Emergence.SPAWN_MARGIN - 5), 2), nil, "culled")
			assert(find(tr:views(6, 0, far - deepest), 2) ~= nil, "drawn inside the view")
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
		name = "the number of mobs drawn at once is bounded",
		run = function()
			local tr = ClusterVisual.new(layout)
			assert(ClusterVisual.MAX_VISIBLE_CLUSTERS >= 8, "pool limit exists")
			assert(
				#tr:views(6, 0, 100) <= ClusterVisual.MAX_VISIBLE_CLUSTERS,
				"never exceeds the limit"
			)
		end,
	},
	{
		name = "with more clusters than the cap, views still fills the cap exactly (scan stops early)",
		run = function()
			local many = table.clone(layout)
			local clusters = {}
			for i = 1, ClusterVisual.MAX_VISIBLE_CLUSTERS + 10 do
				clusters[i] = {
					id = i,
					wave = i,
					type = "small",
					spawnTime = 0,
					spawn = { x = -16, z = 130 },
					path = { { x = -5, z = 70 } },
				}
			end
			many.clusters = clusters
			local tr = ClusterVisual.new(many)
			local views = tr:views(0, 0, 0)
			eq(#views, ClusterVisual.MAX_VISIBLE_CLUSTERS, "exactly the cap is drawn")
		end,
	},
	{
		name = "the veer-away constants are gone",
		run = function()
			eq((ClusterVisual :: any).PASS_SWING, nil, "PASS_SWING removed")
			eq((ClusterVisual :: any).PASS_DISTANCE, nil, "PASS_DISTANCE removed")
		end,
	},
	{
		name = "round 1: the slam start is LATCHED (late Event inside the slam, Event after dispersal, duplicate Events, lost Event)",
		run = function()
			local cz = Level.clusterPosition(layout, 2, 6).z
			local leadZ = cz + 1
			local function fresh(): ClusterVisual.Tracker
				local tr = ClusterVisual.new(layout)
				assert(find(tr:views(6, 0, leadZ), 2) ~= nil, "reached the parade at t=6")
				return tr
			end
			local slamEnd = 6 + MobCharge.SLAM_FALLBACK + MobCharge.SLAM_SECONDS
			local goneAt = slamEnd + MobCharge.DISPERSE_SECONDS
			-- a late Event after the fallback has started the slam must not restart it
			local late = fresh()
			eq(find(late:views(6.6, 0, leadZ), 2).phase, "slamming", "fallback slam running")
			late:attack(2, 6.7)
			eq(
				find(late:views(slamEnd + 0.05, 0, leadZ), 2).phase,
				"dispersing",
				"the slam still ends on the fallback schedule"
			)
			-- an Event long after the mob dispersed and left must not bring it back
			local gone = fresh()
			local afterAllIndividuals = goneAt + 30
			assert(
				find(gone:views(afterAllIndividuals, 0, leadZ), 2) == nil,
				"gone after last independent arrival"
			)
			gone:attack(2, afterAllIndividuals)
			eq(
				find(gone:views(afterAllIndividuals + 0.1, 0, leadZ), 2),
				nil,
				"an Event never resurrects a mob"
			)
			-- an Event that arrives before the views notice the fallback is also ignored
			local between = fresh()
			between:attack(2, 6 + MobCharge.SLAM_FALLBACK + 0.2)
			eq(
				find(between:views(slamEnd + 0.05, 0, leadZ), 2).phase,
				"dispersing",
				"fallback schedule wins over a late Event"
			)
			-- duplicate Events: the first one wins
			local dup = fresh()
			dup:attack(2, 6.1)
			dup:attack(2, 6.3)
			eq(
				find(dup:views(6.1 + MobCharge.SLAM_SECONDS + 0.05, 0, leadZ), 2).phase,
				"dispersing",
				"first Event"
			)
			-- a lost Event: the fallback plays the slam, once
			local lost = fresh()
			eq(find(lost:views(6.2, 0, leadZ), 2).phase, "walking", "still waiting")
			eq(find(lost:views(6.6, 0, leadZ), 2).phase, "slamming", "fallback")
			assert(
				find(lost:views(goneAt + 0.1, 0, leadZ), 2) ~= nil,
				"late individuals still arrive independently"
			)
			assert(find(lost:views(goneAt + 30, 0, leadZ), 2) == nil, "and stays gone")
		end,
	},
}
