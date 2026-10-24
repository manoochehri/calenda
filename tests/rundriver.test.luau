--!strict
local Config = require("../src/shared/Config")
local DebugLayout = require("../src/shared/DebugLayout")
local Level = require("../src/shared/Level")
local RunDriver = require("../src/shared/RunDriver")
local RunHooks = require("../src/shared/RunHooks")
local Steering = require("../src/shared/Steering")

local DT = RunDriver.TICK_DT

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

-- Short street: gate at z 64 (4 s), obstacle on the left at z 160 (10 s), plaza at z 320 (20 s).
local function fixture(): Level.Layout
	return {
		name = "fixture",
		seed = 7,
		streetLength = 400,
		plazaStart = 320,
		halfWidth = 20,
		maxTotal = 1000,
		intendedRecruitTotal = 0,
		gates = {
			{
				id = 1,
				z = 64,
				left = { kind = "add", value = 15 },
				right = { kind = "multiply", value = 2 },
			},
		},
		obstacles = { { id = 1, z = 160, side = "left" } },
		clusters = {
			{
				id = 1,
				wave = 1,
				type = "small",
				spawnTime = 0,
				spawn = { x = -16, z = 200 },
				path = {},
			},
		},
	}
end

local function newDriver(layout: Level.Layout?, hooks: RunDriver.Hooks?): RunDriver.RunDriver
	return RunDriver.new({ layout = layout or fixture(), automated = true, hooks = hooks })
end

-- Ticks until the run ends (or a safety cap), collecting every event.
local function runOut(d: RunDriver.RunDriver, maxSeconds: number?): { RunDriver.DriverEvent }
	local all: { RunDriver.DriverEvent } = {}
	for _ = 1, math.ceil((maxSeconds or 200) / DT) do
		for _, e in d:tick(DT) do
			table.insert(all, e)
		end
		if d:outcome() ~= nil then
			break
		end
	end
	return all
end

local function kinds(events: { RunDriver.DriverEvent }): string
	local out = {}
	for _, e in events do
		table.insert(out, e.kind)
	end
	return table.concat(out, ",")
end

local function steerAndSettle(d: RunDriver.RunDriver, x: number, now: number)
	assert(d:steer(now, { x = x }), "steer accepted")
	for _ = 1, 60 do
		d:tick(DT)
	end
end

return {
	{
		name = "starts at Config.startingTotal on the centre line, at z 0, no outcome",
		run = function()
			local d = newDriver()
			local s = d:snapshot()
			eq(s.total, Config.startingTotal, "total")
			eq(s.z, 0, "z")
			eq(s.x, 0, "x")
			eq(s.outcome, nil, "outcome")
		end,
	},
	{
		name = "lead advances along +z at Config.speed",
		run = function()
			local d = newDriver()
			for _ = 1, 30 do
				d:tick(DT)
			end
			assert(math.abs(d:snapshot().z - Config.speed) < 1e-6, "one second of travel")
		end,
	},
	{
		name = "no input: centre tie goes left gate, hits the left obstacle, completes at the plaza",
		run = function()
			local d = newDriver()
			local events = runOut(d)
			eq(kinds(events), "gate,obstacle,complete", "event order")
			eq(events[1].side, "left", "tie break")
			eq(events[1].before, 10, "gate before")
			eq(events[1].after, 25, "gate after")
			eq(events[2].after, 15, "obstacle loss")
			eq(d:outcome(), "completed", "outcome")
			eq(d:snapshot().score, 15, "score == final total")
			assert(d:snapshot().z >= 320, "reached plaza")
		end,
	},
	{
		name = "steering right takes the x2 gate and dodges the left obstacle",
		run = function()
			local d = newDriver()
			steerAndSettle(d, 10, 0) -- 2 s: reaches x = 10 well before z 64 (4 s)
			local events = runOut(d)
			eq(kinds(events), "gate,complete", "no obstacle event")
			eq(events[1].side, "right", "side")
			eq(d:snapshot().score, 20, "10 x 2")
		end,
	},
	{
		name = "gate and obstacle each apply at most once even if the run is ticked on",
		run = function()
			local d = newDriver()
			local events = runOut(d)
			local before = d:total()
			for _ = 1, 100 do
				eq(#d:tick(DT), 0, "ended run ignores ticks")
			end
			eq(d:total(), before, "total unchanged")
			local gates = 0
			for _, e in events do
				if e.kind == "gate" then
					gates += 1
				end
			end
			eq(gates, 1, "one gate event")
		end,
	},
	{
		name = "lateral motion is rate limited to the server maximum",
		run = function()
			local d = newDriver()
			assert(d:steer(0, { x = 18 }), "accepted")
			d:tick(0.1)
			assert(d:snapshot().x <= Steering.MAX_LATERAL_SPEED * 0.1 + 1e-9, "no teleport")
			assert(d:snapshot().x > 0, "moves")
		end,
	},
	{
		name = "steering target is clamped to the street bound",
		run = function()
			local d = newDriver()
			d:steer(0, { x = 1e9 })
			for _ = 1, 300 do
				d:tick(DT)
				if d:outcome() ~= nil then
					break
				end
			end
			assert(d:snapshot().x <= Steering.bound(20) + 1e-9, "right bound")
			local d2 = newDriver()
			d2:steer(0, { x = -1e9 })
			for _ = 1, 300 do
				d2:tick(DT)
			end
			assert(d2:snapshot().x >= -Steering.bound(20) - 1e-9, "left bound")
		end,
	},
	{
		name = "steer message flood is rate limited",
		run = function()
			local d = newDriver()
			local accepted = 0
			for _ = 1, 500 do
				if d:steer(1, { x = 5 }) then
					accepted += 1
				end
			end
			assert(accepted <= Steering.BURST, `accepted {accepted}`)
		end,
	},
	{
		name = "forged payloads are rejected and change nothing",
		run = function()
			local d = newDriver()
			local snap = d:snapshot()
			local now = 0
			for _, bad in
				{
					"total=99999",
					99999,
					true,
					{},
					{ x = 0 / 0 },
					{ x = math.huge },
					{ x = "10" },
					{ x = {} },
					{ total = 99999 },
					{ gate = 1, side = "right" },
				}
			do
				now += 1 -- one second apart so the limiter is not what rejects
				eq(d:steer(now, bad :: any), false, "rejected")
			end
			eq(d:steer(now + 1, nil :: any), false, "nil")
			local after = d:snapshot()
			eq(after.total, snap.total, "total")
			eq(after.x, snap.x, "x")
			eq(after.z, snap.z, "z")
			eq(d:outcome(), nil, "outcome")
		end,
	},
	{
		name = "extra forged fields on a valid steer payload change nothing (same run as clean)",
		run = function()
			local clean = newDriver()
			clean:steer(0, { x = 10 })
			local forged = newDriver()
			forged:steer(
				0,
				{ x = 10, total = 99999, id = "g1", amount = 500, score = 1e9, hp = 99 } :: any
			)
			runOut(clean)
			runOut(forged)
			eq(forged:total(), clean:total(), "total")
			eq(forged:snapshot().score, clean:snapshot().score, "score")
		end,
	},
	{
		name = "opts.startingTotal from a caller never reaches RunState",
		run = function()
			local d = RunDriver.new({
				layout = fixture(),
				automated = true,
				startingTotal = 99999,
			} :: any)
			eq(d:total(), Config.startingTotal, "total")
		end,
	},
	{
		name = "layout is copied: mutating the source or the converted layout cannot change the run",
		run = function()
			local source = fixture()
			local d = newDriver(source)
			source.gates[1].left.value = 9999
			source.gates[1].right.value = 9999
			source.obstacles[1].z = 5
			table.insert(source.clusters, {
				id = 99,
				wave = 1,
				type = "large",
				spawnTime = 0,
				spawn = { x = 0, z = 1 },
				path = {},
			})
			runOut(d)
			eq(d:snapshot().score, 15, "run used the original values")
			local converted = RunDriver.toRunLayout(fixture())
			local again = RunDriver.toRunLayout(fixture())
			converted.gatePairs[1].left.op.value = 12345
			eq(again.gatePairs[1].left.op.value, 15, "independent copies")
		end,
	},
	{
		name = "toRunLayout maps ids, gate anchors and cluster types",
		run = function()
			local rl = RunDriver.toRunLayout(fixture())
			eq(rl.gatePairs[1].id, "g1", "gate id")
			eq(rl.gatePairs[1].left.x, -10, "left anchor is -halfWidth/2")
			eq(rl.gatePairs[1].right.x, 10, "right anchor")
			eq(rl.clusters[1].id, "c1", "cluster id")
			eq(rl.clusters[1].type, "small", "type")
			eq(rl.obstacles[1].id, "o1", "obstacle id")
		end,
	},
	{
		name = "invalid dt is ignored; huge dt is clamped so the lead cannot skip the street",
		run = function()
			local d = newDriver()
			for _, bad in { 0 / 0, math.huge, -1, 0, "1" } do
				eq(#d:tick(bad :: any), 0, "no events")
			end
			eq(d:snapshot().z, 0, "no motion on bad dt")
			d:tick(1000)
			assert(d:snapshot().z <= Config.speed * RunDriver.MAX_DT + 1e-9, "clamped")
			eq(d:outcome(), nil, "not skipped to the plaza")
		end,
	},
	{
		name = "a large clamped step still resolves crossings once and in order",
		run = function()
			local d = newDriver()
			local events = runOut(d)
			local seen: { [string]: number } = {}
			for _, e in events do
				seen[e.kind] = (seen[e.kind] or 0) + 1
			end
			eq(seen.gate, 1, "gate")
			eq(seen.obstacle, 1, "obstacle")
			eq(seen.complete, 1, "complete")
		end,
	},
	{
		name = "replay: refused mid-run, allowed after the end, resets everything but session best",
		run = function()
			local d = newDriver()
			d:tick(DT)
			eq(d:replay(0), false, "mid-run replay refused")
			eq(d:snapshot().z > 0, true, "run continues")
			runOut(d)
			eq(d:snapshot().score, 15, "first score")
			eq(d:replay(100), true, "replay accepted")
			local s = d:snapshot()
			eq(s.total, Config.startingTotal, "total reset")
			eq(s.z, 0, "z reset")
			eq(s.x, 0, "x reset")
			eq(s.outcome, nil, "outcome reset")
			eq(s.score, nil, "score reset")
			eq(s.best, 15, "best kept")
			local events = runOut(d)
			eq(kinds(events), "gate,obstacle,complete", "gates apply again in the new run")
		end,
	},
	{
		name = "replay is rate limited and cannot be spammed into resets",
		run = function()
			local d = newDriver()
			runOut(d)
			eq(d:replay(100), true, "first")
			runOut(d)
			eq(d:replay(100.1), false, "inside the cooldown")
			eq(d:replay(100 + RunDriver.REPLAY_COOLDOWN + 0.01), true, "after the cooldown")
			eq(d:replay(0 / 0), false, "nan time")
		end,
	},
	{
		name = "replay also clears a pending steering target",
		run = function()
			local d = newDriver()
			d:steer(0, { x = 15 })
			runOut(d)
			d:replay(50)
			d:tick(1)
			eq(d:snapshot().x, 0, "lead stays centred until new input")
		end,
	},
	{
		name = "same-tick order: shots, move+gates+obstacle, attacks, end check (extension hooks)",
		run = function()
			local order: { string } = {}
			local totals: { string } = {}
			local d = newDriver(nil, {
				shots = function(ctx)
					table.insert(order, "shots")
					table.insert(totals, `shots:{ctx.state:total()}`)
				end,
				attacks = function(ctx)
					table.insert(order, "attacks")
					table.insert(totals, `attacks:{ctx.state:total()}`)
				end,
				endCheck = function(_ctx)
					table.insert(order, "end")
					return false
				end,
			})
			-- run to the first tick that crosses the gate (z 64 -> tick 120)
			local gateTick = 0
			for i = 1, 200 do
				table.clear(order)
				table.clear(totals)
				local events = d:tick(DT)
				if #events > 0 and events[1].kind == "gate" then
					gateTick = i
					break
				end
			end
			assert(gateTick > 0, "gate crossed")
			eq(table.concat(order, ","), "shots,attacks,end", "phase order")
			eq(totals[1], "shots:10", "shots see the pre-move total")
			eq(totals[2], "attacks:25", "attacks see the post-gate total")
		end,
	},
	{
		name = "server driver attacks passed clusters in ID order before ending defeated",
		run = function()
			local clusters: { Level.Cluster } = {}
			local lethalAttackCount =
				math.ceil(Config.hp.max / Config.clusterTypes.large.attackDamage)
			local attackCount = lethalAttackCount + 2
			for i = attackCount, 1, -1 do
				table.insert(clusters, {
					id = i,
					wave = 1,
					type = "large",
					spawnTime = 0,
					spawn = { x = 16, z = 1 },
					path = {},
				})
			end
			local layout: Level.Layout = {
				name = "attack",
				seed = 8,
				streetLength = 400,
				plazaStart = Config.speed * 0.1,
				halfWidth = 20,
				maxTotal = 1000,
				intendedRecruitTotal = 0,
				gates = {},
				obstacles = {},
				clusters = clusters,
			}
			local d =
				RunDriver.new({ layout = layout, automated = true, hooks = RunHooks.new(layout) })
			local events: { RunDriver.DriverEvent } = {}
			for _ = 1, 100 do
				for _, event in d:tick(DT) do
					if event.kind ~= "cluster" then -- shot events (#48) are covered by shotevents.test
						table.insert(events, event)
					end
				end
				if d:outcome() ~= nil then
					break
				end
			end
			local ids = {}
			for _, event in events do
				if event.kind == "attack" then
					table.insert(ids, event.id)
				end
			end
			eq(#ids, attackCount, "attacked clusters")
			for i, id in ids do
				eq(id, i, "cluster attack order")
			end
			eq(
				kinds(events),
				table.concat(table.create(attackCount, "attack"), ",") .. ",defeated",
				"event order"
			)
			eq(events[1].hpBefore, Config.hp.max, "first attack HP before")
			eq(events[lethalAttackCount].hpAfter, 0, "lethal attack clamps HP")
			eq(events[attackCount].hpBefore, 0, "same-tick attacks continue at zero HP")
			eq(events[attackCount].hpAfter, 0, "HP stays clamped for later same-tick attacks")
			eq(d:outcome(), "defeated", "outcome")
			eq(d:total(), Config.startingTotal, "crowd unchanged")
			eq(d:snapshot().hp, 0, "HP exposed in snapshot")
			assert(d:replay(1), "defeated run replays")
			eq(d:snapshot().hp, Config.hp.max, "replay restores HP")
			eq(d:outcome(), nil, "replay clears outcome")
			for _ = 1, 4 do
				d:tick(DT)
			end
			eq(d:outcome(), "defeated", "replayed clusters are processed again")
		end,
	},
	{
		name = "cluster converted before passing does not attack the parade",
		run = function()
			local layout = fixture()
			layout.clusters = {
				{
					id = 1,
					wave = 1,
					type = "small",
					spawnTime = 0,
					spawn = { x = 16, z = 14.67 },
					path = {},
				},
			}
			local d =
				RunDriver.new({ layout = layout, automated = true, hooks = RunHooks.new(layout) })
			local events: { RunDriver.DriverEvent } = {}
			for _ = 1, 40 do
				for _, event in d:tick(DT) do
					table.insert(events, event)
				end
			end
			for _, event in events do
				assert(event.kind ~= "attack", "converted cluster must not attack")
			end
			eq(
				d:total(),
				Config.startingTotal + Config.clusterTypes.small.reward,
				"converted reward"
			)
			eq(d:snapshot().hp, Config.hp.max, "HP unchanged")
		end,
	},
	{
		name = "filling shot and parade arrival in one fixed tick convert before attack",
		run = function()
			local layout = fixture()
			layout.clusters = {
				{
					id = 1,
					wave = 1,
					type = "small",
					spawnTime = 0,
					spawn = {
						x = 16,
						z = (Config.speed + Config.spectators.approachSpeed) * 0.66,
					},
					path = {},
				},
			}
			local testConfig = table.clone(Config)
			testConfig.firing = table.clone(Config.firing)
			testConfig.firing.base = 3.1
			local hooks = RunHooks.new(layout, testConfig)
			local shots = hooks.shots
			local crossingTick = false
			hooks.shots = function(ctx)
				if shots then
					shots(ctx)
				end
				local before = Level.clusterPosition(layout, 1, ctx.t0)
				local after = Level.clusterPosition(layout, 1, ctx.t1)
				if before.z > ctx.z0 and after.z <= ctx.z1 then
					crossingTick = true
					eq(
						ctx.state:clusterConsumption("c1"),
						"credited",
						"shot converted before attack phase"
					)
					local runEvents = ctx.state:events()
					eq(
						runEvents[#runEvents].kind,
						"cluster_credit",
						"conversion event recorded this tick"
					)
					eq(#ctx.passedClusters, 0, "converted cluster not reported passed")
				end
			end
			local d = RunDriver.new({ layout = layout, automated = true, hooks = hooks })
			local events: { RunDriver.DriverEvent } = {}
			for _ = 1, 30 do
				for _, event in d:tick(RunDriver.TICK_DT) do
					table.insert(events, event)
				end
			end
			assert(crossingTick, "the cluster crossed during the shot filling tick")
			for _, event in events do
				assert(event.kind ~= "attack", "conversion precedes same-tick attack")
			end
			eq(d:total(), Config.startingTotal + Config.clusterTypes.small.reward, "reward once")
			eq(d:snapshot().hp, Config.hp.max, "no attack damage")
		end,
	},
	{
		name = "session best updates only from completed runs through the driver",
		run = function()
			local shouldDefeat = false
			local layout: Level.Layout = {
				name = "best",
				seed = 9,
				streetLength = 64,
				plazaStart = 32,
				halfWidth = 20,
				maxTotal = 1000,
				intendedRecruitTotal = 0,
				gates = {
					{
						id = 1,
						z = 16,
						left = { kind = "add", value = 1 },
						right = { kind = "add", value = 200 },
					},
				},
				obstacles = {},
				clusters = {},
			}
			local hooks = RunHooks.new(layout)
			hooks.endCheck = function(ctx)
				return shouldDefeat and ctx.z1 >= 16
			end
			local d = RunDriver.new({
				layout = layout,
				automated = true,
				hooks = hooks,
			})
			runOut(d)
			eq(d:outcome(), "completed", "first run completed")
			eq(d:snapshot().best, 11, "completed score becomes session best")
			shouldDefeat = true
			assert(d:replay(100), "replay accepted")
			assert(d:steer(101, { x = 10 }), "steer right for the higher gate")
			runOut(d)
			eq(d:outcome(), "defeated", "second run defeated")
			eq(d:snapshot().score, 210, "defeated score is higher")
			eq(d:snapshot().best, 11, "defeat does not update session best")
		end,
	},
	{
		name = "lethal RunHooks attacks on the plaza tick defeat instead of completing",
		run = function()
			local dt = RunDriver.TICK_DT
			local t1 = 2 * dt
			local spawnTime = dt + dt / 4
			local spawnZ = Config.speed * t1
				+ Config.spectators.approachSpeed * (t1 - spawnTime)
				- 1e-6 -- place every unconverted cluster just behind the lead at the plaza tick
			local clusters: { Level.Cluster } = {}
			for id = 1, math.ceil(Config.hp.max / Config.clusterTypes.large.attackDamage) do
				table.insert(clusters, {
					id = id,
					wave = 1,
					type = "large",
					spawnTime = spawnTime,
					spawn = { x = 16, z = spawnZ },
					path = {},
				})
			end
			local layout: Level.Layout = {
				name = "lethal-plaza-tie",
				seed = 10,
				streetLength = 20,
				plazaStart = Config.speed * t1,
				halfWidth = 20,
				maxTotal = 1000,
				intendedRecruitTotal = 0,
				gates = {},
				obstacles = {},
				clusters = clusters,
			}
			local d =
				RunDriver.new({ layout = layout, automated = true, hooks = RunHooks.new(layout) })
			local events: { RunDriver.DriverEvent } = {}
			for _ = 1, 4 do
				for _, event in d:tick(dt) do
					if event.kind ~= "miss" then -- continuous fire (ADR 0004): display-only misses
						table.insert(events, event)
					end
				end
			end
			eq(d:outcome(), "defeated", "lethal attacks beat plaza completion")
			eq(
				kinds(events),
				table.concat(table.create(#clusters, "attack"), ",") .. ",defeated",
				"same-tick attack and end-check events"
			)
			assert(not string.find(kinds(events), "complete", 1, true), "no plaza completion")
			eq(d:snapshot().hp, 0, "HP reaches zero")
		end,
	},
	{
		name = "end check wins over reaching the plaza on the same tick; later events are ignored",
		run = function()
			local d = newDriver(nil, {
				endCheck = function(ctx)
					return ctx.z1 >= 320
				end,
			})
			local events = runOut(d)
			eq(d:outcome(), "defeated", "defeated, not completed")
			eq(kinds(events), "gate,obstacle,defeated", "no complete event")
			local score = d:snapshot().score
			eq(score, 15, "score is the total at the end")
			eq(#d:tick(DT), 0, "ignored after end")
			eq(d:snapshot().score, score, "unchanged")
		end,
	},
	{
		name = "hooks may emit events and never receive a way to set totals from outside",
		run = function()
			local fired = false
			local d = newDriver(nil, {
				shots = function(ctx)
					if not fired then
						fired = true
						ctx.emit({ kind = "cluster", id = 1, before = 10, after = 10 })
					end
				end,
			})
			local events = d:tick(DT)
			eq(kinds(events), "cluster", "hook event is passed through")
		end,
	},
	{
		name = "full DebugLayout: no input completes, each gate/obstacle id appears once, score == total",
		run = function()
			local d = RunDriver.new({ layout = DebugLayout, automated = true })
			local events = runOut(d, 200)
			eq(d:outcome(), "completed", "completed")
			local gates: { [number]: number } = {}
			local obstacles: { [number]: number } = {}
			for _, e in events do
				if e.kind == "gate" then
					gates[e.id :: number] = (gates[e.id :: number] or 0) + 1
				elseif e.kind == "obstacle" then
					obstacles[e.id :: number] = (obstacles[e.id :: number] or 0) + 1
				end
			end
			for _, g in DebugLayout.gates do
				eq(gates[g.id], 1, `gate {g.id} once`)
			end
			for _, n in obstacles do
				eq(n, 1, "obstacle once")
			end
			eq(d:snapshot().score, d:total(), "score equals final total")
			assert(d:total() <= DebugLayout.maxTotal, "within authored bound")
		end,
	},
}
