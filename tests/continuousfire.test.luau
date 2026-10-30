--!strict
-- Issue #67 (ADR 0004, spec Amendment 2): continuous fire. A shot with an eligible target is a hit
-- (credit-once, meters, gift cadence as before); a shot with none is a visual-only miss that never
-- credits, damages or consumes anything. Misses are replicated as a bounded, owner-only,
-- display-only "miss" Event, validated on encode and decode.
local ClusterFeed = require("../src/shared/ClusterFeed")
local Config = require("../src/shared/Config")
local Level = require("../src/shared/Level")
local Remotes = require("../src/shared/Remotes")
local RunDriver = require("../src/shared/RunDriver")
local RunHooks = require("../src/shared/RunHooks")
local RunState = require("../src/shared/RunState")
local Targeting = require("../src/shared/Targeting")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function layoutOf(clusters: { Level.Cluster }): Level.Layout
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
		clusters = clusters,
	}
end

local function cluster(id: number, z: number, kind: string): Level.Cluster
	return {
		id = id,
		wave = 1,
		type = kind,
		spawnTime = 0,
		spawn = { x = 10, z = z },
		path = {},
		lane = "right",
	}
end

local function stateFor(layout: Level.Layout): RunState.RunState
	local defs: { RunState.ClusterDef } = {}
	for _, c in layout.clusters do
		table.insert(defs, { id = tostring(c.id), type = c.type :: RunState.ClusterKind })
	end
	return RunState.new({
		seed = 1,
		automated = true,
		layout = { gatePairs = {}, clusters = defs, obstacles = {} },
		now = function()
			return 0
		end,
	})
end

-- Runs a Targeting session on the server's fixed step and returns every shot.
local function run(
	layout: Level.Layout,
	seconds: number,
	sections: number,
	config: any?
): ({ any }, RunState.RunState)
	local rs = stateFor(layout)
	local session = Targeting.new({ layout = layout, runState = rs, config = config })
	local out: { any } = {}
	local t = 0.0
	while t <= seconds do
		for _, s in session:advance(t, sections, "right").shots do
			table.insert(out, s)
		end
		t += RunDriver.TICK_DT
	end
	return out, rs
end

return {
	{
		name = "rate curve: 6 base, +1 per section, cap 20, at 0, 1, 9 and 100 sections",
		run = function()
			eq(Targeting.fireRate(0), 6, "0")
			eq(Targeting.fireRate(1), 7, "1")
			eq(Targeting.fireRate(9), 15, "9")
			eq(Targeting.fireRate(100), 20, "100")
			eq(Config.firing.perSection, 1, "perSection kept")
		end,
	},
	{
		name = "with no clusters at all the parade still fires: only misses, at the curve rate",
		run = function()
			local shots, rs = run(layoutOf({}), 2.05, 0)
			eq(#shots, 13, "shots at 6/s over [0, 2]") -- 0, 1/6, ... 12/6
			for i, s in shots do
				eq(s.miss, true, `shot {i} miss`)
				eq(s.targetId, nil, "no target")
				eq(s.credit, nil, "no credit")
				eq(s.number, i, "numbered")
			end
			eq(rs:total(), Config.startingTotal, "total unchanged")
			eq((rs :: any).hp, nil, "no HP field (ADR 0006)")
			eq(#rs:events(), 1, "only the run-start event; a miss logs nothing")
		end,
	},
	{
		name = "misses never credit, damage or consume: an out-of-range cluster stays untouched",
		run = function()
			local layout = layoutOf({ cluster(1, 900, "small") })
			local shots, rs = run(layout, 2, 3)
			for _, s in shots do
				eq(s.miss, true, "out of range")
			end
			eq(rs:total(), Config.startingTotal, "total")
			eq((rs :: any).hp, nil, "no HP field (ADR 0006)")
			eq(rs:clusterConsumption("1"), nil, "cluster not consumed")
		end,
	},
	{
		name = "hits still credit exactly once; surplus shots after the fill are misses",
		run = function()
			local layout = layoutOf({ cluster(1, 40, "small") })
			local shots, rs = run(layout, 0.6, 0)
			local hits, credits = 0, 0
			for _, s in shots do
				if not s.miss then
					hits += 1
				end
				if s.credit ~= nil then
					credits += 1
				end
			end
			eq(hits, Config.clusterTypes.small.hits, "exactly the cluster's hits")
			eq(credits, 1, "credited once")
			eq(rs:total(), Config.startingTotal + Config.clusterTypes.small.reward, "reward once")
			local late = 0
			for _, s in shots do
				if s.miss and s.number > hits then
					late += 1
				end
			end
			assert(late >= 1, "the shots after the fill keep flying as misses")
		end,
	},
	{
		name = "gift cadence is unchanged: every giftEveryNthShot-th shot number is a gift, hit or miss",
		run = function()
			-- A 4-shot cadence keeps the sample short; the default cadence is pinned elsewhere.
			local cfg = table.clone(Config)
			cfg.giftEveryNthShot = 4
			local shots = run(layoutOf({ cluster(1, 40, "large") }), 2.05, 3, cfg)
			assert(#shots >= 12, "enough shots")
			local sawMissGift, sawHitGift = false, false
			for i, s in shots do
				eq(s.kind, if i % cfg.giftEveryNthShot == 0 then "gift" else "note", `shot {i}`)
				if s.kind == "gift" then
					if s.miss then
						sawMissGift = true
					else
						sawHitGift = true
					end
				end
			end
			assert(sawMissGift and sawHitGift, "gifts occur on both hits and misses")
		end,
	},
	{
		name = "fixed-clock determinism: identical runs give identical hits and misses",
		run = function()
			local layout = layoutOf({ cluster(1, 40, "small"), cluster(2, 300, "large") })
			local function sig(): string
				local out = {}
				for _, s in run(layout, 3, 4) do
					table.insert(out, `{s.number}:{s.time}:{s.miss}:{s.targetId}:{s.kind}:{s.hits}`)
				end
				return table.concat(out, "|")
			end
			eq(sig(), sig(), "runs differ")
		end,
	},
	{
		name = "a clock jump cannot fire a flood: at most MAX_SHOTS_PER_ADVANCE shots, backlog dropped",
		run = function()
			local rs = stateFor(layoutOf({}))
			local session = Targeting.new({ layout = layoutOf({}), runState = rs })
			local step = session:advance(1000, 100, "center")
			eq(#step.shots, Targeting.MAX_SHOTS_PER_ADVANCE, "bounded")
			eq(#session:advance(1000, 100, "center").shots, 0, "no backlog")
		end,
	},
	{
		name = "per-tick cap holds at the top rate: real hooks, 30 ticks/s and the longest 0.1 s step",
		run = function()
			local layout = layoutOf({})
			for _, dt in { RunDriver.TICK_DT, RunDriver.MAX_DT } do
				local driver = RunDriver.new({
					layout = layout,
					automated = true,
					hooks = RunHooks.new(layout),
				})
				local worst, total, seconds = 0, 0, 0
				for _ = 1, 600 do
					local n = 0
					for _, e in driver:tick(dt) do
						if e.kind == "miss" then
							n += 1
						end
					end
					worst = math.max(worst, n)
					total += n
					seconds += math.min(dt, RunDriver.MAX_DT)
				end
				assert(worst <= RunDriver.MAX_CLUSTER_EVENTS_PER_TICK, `worst {worst}`)
				local bound = math.floor(Config.firing.base * dt) + 1
				assert(worst <= bound, `dt {dt}: {worst} shots in one tick, bound {bound}`)
				-- steady state at the base rate (no sections): about 6 shot events per second
				assert(
					math.abs(total / seconds - Config.firing.base) < 0.5,
					`rate {total / seconds}`
				)
			end
			-- Even the cap rate fits: floor(20 * 0.1) + 1 = 3 shots per step, under the per-tick cap.
			assert(
				math.floor(Config.firing.cap * RunDriver.MAX_DT) + 1
					<= RunDriver.MAX_CLUSTER_EVENTS_PER_TICK,
				"cap rate fits the per-tick cap"
			)
		end,
	},
	{
		name = "miss and cluster events share the per-tick cap; other kinds are not capped",
		run = function()
			local cap = RunDriver.MAX_CLUSTER_EVENTS_PER_TICK
			local driver = RunDriver.new({
				layout = layoutOf({}),
				automated = true,
				hooks = {
					shots = function(ctx)
						for i = 1, 500 do
							ctx.emit({ kind = "miss", shot = "note", n = i })
							ctx.emit({ kind = "cluster", id = 1, hits = 1, shot = "note" })
						end
						ctx.emit({ kind = "attack", id = 1 })
					end,
				},
			})
			local shotEvents, other = 0, 0
			for _, e in driver:tick(RunDriver.TICK_DT) do
				if e.kind == "miss" or e.kind == "cluster" then
					shotEvents += 1
				else
					other += 1
				end
			end
			eq(shotEvents, cap, "shot events kept")
			eq(other, 1, "other kinds uncapped")
		end,
	},
	{
		name = "worst-case remote traffic is stated and bounded",
		run = function()
			local ticksPerSecond = math.floor(1 / RunDriver.TICK_DT + 0.5)
			eq(ticksPerSecond, 30, "server ticks per second")
			-- Hard ceiling from the per-tick cap: 8 x 30 = 240 events/s. Steady state from the rate
			-- cap: 20 events/s. Both are per player and owner-only.
			eq(RunDriver.MAX_CLUSTER_EVENTS_PER_TICK * ticksPerSecond, 240, "hard ceiling")
			assert(
				Config.firing.cap <= ticksPerSecond,
				"config validation bounds the rate by the tick"
			)
		end,
	},
	{
		name = "the replicated miss is a closed shape: encode and decode both validate",
		run = function()
			assert(Remotes.isEventKind("miss"), "miss is a known kind")
			local p =
				ClusterFeed.encode({ miss = true, number = 7, kind = "gift", hits = 0 } :: any)
			assert(p ~= nil, "encoded")
			eq(p.kind, "miss", "kind")
			local m = ClusterFeed.decodeMiss(p)
			assert(m ~= nil, "round trip")
			eq(m.shot, "gift", "shot")
			eq(m.n, 7, "n")
			eq(ClusterFeed.decode(p), nil, "a miss is not a cluster hit")
			eq(
				ClusterFeed.decodeMiss({ kind = "cluster", id = 1, hits = 1, shot = "note" }),
				nil,
				"hit"
			)
			local function enc(s: any): any
				return (ClusterFeed.encode :: any)(s)
			end
			eq(enc({ miss = true, number = 0, kind = "note" }), nil, "n 0")
			eq(enc({ miss = true, number = 1.5, kind = "note" }), nil, "fractional n")
			eq(
				enc({ miss = true, number = ClusterFeed.MAX_SHOT_NUMBER + 1, kind = "note" }),
				nil,
				"big"
			)
			eq(enc({ miss = true, number = 1, kind = "rocket" }), nil, "bad kind")
			eq(enc({ miss = true, number = 0 / 0, kind = "note" }), nil, "nan")
			assert(
				enc({ miss = true, number = ClusterFeed.MAX_SHOT_NUMBER, kind = "note" }),
				"inclusive"
			)
			local bad: { any } = {
				"x",
				{},
				{ kind = "miss" },
				{ kind = "miss", shot = "note" },
				{ kind = "miss", shot = "note", n = 0 },
				{ kind = "miss", shot = "note", n = -3 },
				{ kind = "miss", shot = "note", n = 2.5 },
				{ kind = "miss", shot = "rocket", n = 1 },
				{ kind = "miss", shot = "note", n = math.huge },
				{ kind = "miss", shot = "note", n = 0 / 0 },
				{ kind = "miss", shot = "note", n = ClusterFeed.MAX_SHOT_NUMBER + 1 },
				{ kind = "miss", shot = 5, n = 1 },
			}
			for i, b in bad do
				eq(ClusterFeed.decodeMiss(b), nil, `bad miss {i}`)
			end
			-- Extra fields (a forged id or reward) are never read.
			local forged =
				ClusterFeed.decodeMiss({ kind = "miss", shot = "note", n = 1, id = 9, reward = 99 })
			assert(
				forged ~= nil and (forged :: any).id == nil and (forged :: any).reward == nil,
				"extras dropped"
			)
		end,
	},
	{
		name = "no hook path can turn a miss into a credit: hooks emit misses with no id",
		run = function()
			local layout = layoutOf({})
			local driver = RunDriver.new({
				layout = layout,
				automated = true,
				hooks = RunHooks.new(layout),
			})
			local seen = 0
			for _ = 1, 90 do
				for _, e in driver:tick(RunDriver.TICK_DT) do
					if e.kind == "miss" then
						seen += 1
						eq(e.id, nil, "no cluster id on a miss")
						eq(e.hits, nil, "no hits on a miss")
					end
				end
			end
			assert(seen >= 10, "misses were emitted")
			eq(driver:total(), Config.startingTotal, "total unchanged")
			eq((driver:snapshot() :: any).hp, nil, "no HP field (ADR 0006)")
		end,
	},
}
