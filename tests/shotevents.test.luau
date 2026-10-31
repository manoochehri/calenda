--!strict
-- Issue #48: the server emits one display-only "cluster" Event per landed shot (spec Amendment 1).
local FastFire = require("./helpers/FastFire")
local ClusterFeed = require("../src/shared/ClusterFeed")
local Config = require("../src/shared/Config")
local Level = require("../src/shared/Level")
local RunDriver = require("../src/shared/RunDriver")
local RunHooks = require("../src/shared/RunHooks")
local RunState = require("../src/shared/RunState")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function layoutWith(spawnZ: number): Level.Layout
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
			{
				id = 1,
				wave = 1,
				type = "large",
				spawnTime = 0,
				spawn = { x = 10, z = spawnZ },
				path = {},
				lane = "right",
			},
		},
	}
end

-- Runs the production shots hook for one step and returns the emitted events.
local function shotsFor(
	layout: Level.Layout,
	startingTotal: number,
	t1: number,
	config: any?
): { any }
	local state = RunState.new({
		seed = 1,
		automated = true,
		startingTotal = startingTotal,
		layout = { gatePairs = {}, clusters = { { id = "c1", type = "large" } }, obstacles = {} },
		now = function()
			return 0
		end,
	})
	local out: { any } = {}
	local hooks = RunHooks.new(layout, config or FastFire.config())
	hooks.shots({
		t0 = 0,
		t1 = t1,
		z0 = 0,
		z1 = 0,
		x = 10,
		state = state,
		passedClusters = {},
		emit = function(e: any)
			table.insert(out, e)
		end,
	})
	return out
end

return {
	{
		name = "one cluster event per shot, each a valid bounded payload with rising hits",
		run = function()
			local events = shotsFor(layoutWith(30), 0, 0.4)
			assert(#events >= 2, `expected several shots, got {#events}`)
			for i, e in events do
				local s = ClusterFeed.decode(e)
				assert(s ~= nil, `event {i} decodes`)
				eq(s.id, 1, "id")
				eq(s.hits, i, "hits after shot")
				assert(s.hits >= 0 and s.hits <= ClusterFeed.MAX_HITS, "hits bounded")
				eq(s.shot, "note", "no dancers means notes")
			end
		end,
	},
	{
		name = "with no target in range every event is a bounded display-only miss",
		run = function()
			local events = shotsFor(layoutWith(900), 0, 1)
			assert(#events >= 6, "continuous fire keeps shooting")
			for i, e in events do
				eq(ClusterFeed.decode(e), nil, `event {i} is not a hit`)
				local m = ClusterFeed.decodeMiss(e)
				assert(m ~= nil, `event {i} is a valid miss`)
				eq(m.n, i, "shot number")
			end
		end,
	},
	{
		name = "with a dancer section present the Config.giftEveryNthShot-th shot is a gift",
		run = function()
			-- A 4-shot cadence keeps the sample short; the default cadence is pinned elsewhere.
			local cfg = table.clone(Config)
			cfg.giftEveryNthShot = 4
			local events = shotsFor(layoutWith(30), 150, 0.8, cfg)
			assert(#events >= 5, `need at least 5 shots, got {#events}`)
			for i, e in events do
				eq(e.shot, if i % 4 == 0 then "gift" else "note", `shot {i}`)
			end
		end,
	},
	{
		name = "the driver caps cluster events per tick so a long frame cannot flood",
		run = function()
			local cap = RunDriver.MAX_CLUSTER_EVENTS_PER_TICK
			assert(type(cap) == "number" and cap >= 1 and cap <= 24, "cap is a small number")
			local driver = RunDriver.new({
				layout = layoutWith(30),
				automated = true,
				hooks = {
					shots = function(ctx)
						for i = 1, 500 do
							ctx.emit({ kind = "cluster", id = 1, hits = i % 8, shot = "note" })
						end
						ctx.emit({ kind = "attack", id = 1 })
					end,
				},
			})
			local n, other = 0, 0
			for _, e in driver:tick(RunDriver.TICK_DT) do
				if e.kind == "cluster" then
					n += 1
				else
					other += 1
				end
			end
			eq(n, cap, "cluster events kept")
			eq(other, 1, "other event kinds are not capped")
		end,
	},
	{
		name = "encode rejects an unknown shot kind, a bad id and out of bounds hits",
		run = function()
			local function enc(t: any): any
				return (ClusterFeed.encode :: any)(t)
			end
			eq(enc({ targetId = 1, hits = 1, kind = "rocket" }), nil, "bad kind")
			eq(enc({ targetId = 1, hits = 1, kind = nil }), nil, "missing kind")
			eq(enc({ targetId = 0, hits = 1, kind = "note" }), nil, "id 0")
			eq(enc({ targetId = 1.5, hits = 1, kind = "note" }), nil, "fractional id")
			eq(enc({ targetId = 1, hits = -1, kind = "note" }), nil, "negative hits")
			eq(enc({ targetId = 1, hits = 1001, kind = "note" }), nil, "hits too big")
			eq(enc({ targetId = 1, hits = 0 / 0, kind = "note" }), nil, "nan hits")
			eq(enc("x"), nil, "not a table")
			assert(enc({ targetId = 2, hits = 1000, kind = "gift" }) ~= nil, "bounds are inclusive")
		end,
	},
}
