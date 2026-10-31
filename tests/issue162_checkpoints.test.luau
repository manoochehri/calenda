--!strict
-- Issue #162: the checkpoint foundation. Forward route distance is split from monotonic combat
-- time; a test-only authored checkpoint stops the lead (clamped), the fight keeps simulating, and
-- the lead resumes once from the plane. No boss content exists: a checkpoint resolves through the
-- server-side `resolveCheckpoint(id)` hook, which no remote calls.
-- Modules that are new or changed are required inside each case so a missing one fails only its case.
local Config = require("../src/shared/Config")
local FastFire = require("./helpers/FastFire")
local RunDriver = require("../src/shared/RunDriver")
local RunHooks = require("../src/shared/RunHooks")

local DT = RunDriver.TICK_DT
local SPEED = Config.speed
local CP_Z = 72.3 -- not a multiple of speed * MAX_DT (0.72), so a big step overshoots it
local HELD = "mini-boss-combat"

local function eq(actual: any, expected: any, label: string)
	assert(actual == expected, `{label}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function near(actual: number, expected: number, tol: number, label: string)
	assert(math.abs(actual - expected) <= tol, `{label}: expected {expected} +-{tol}, got {actual}`)
end

type Opts = {
	gates: { any }?,
	pickups: { any }?,
	clusters: { any }?,
	hazardSet: any?,
	checkpoints: { any }?,
	name: string?,
}

-- A test-only authored segment: one mini-boss checkpoint at CP_Z unless `checkpoints` says otherwise.
local function layout(o: Opts?): any
	local opts: Opts = o or {}
	return {
		name = opts.name or "issue162",
		seed = 3,
		streetLength = 480,
		plazaStart = 400,
		halfWidth = 20,
		leadLimit = 15,
		maxTotal = 1000,
		intendedRecruitTotal = 0,
		gates = opts.gates or {},
		obstacles = {},
		clusters = opts.clusters or {},
		pickups = opts.pickups,
		hazardSet = opts.hazardSet,
		checkpoints = if opts.checkpoints == nil
			then { { id = 1, z = CP_Z, kind = "mini-boss" } }
			else opts.checkpoints,
	}
end

local function smallMob(id: number, spawnTime: number, z: number): any
	return {
		id = id,
		wave = 1,
		type = "small",
		spawnTime = spawnTime,
		spawn = { x = 0, z = z },
		path = {},
		lane = "center",
	}
end

local function driver(l: any, hooks: RunDriver.Hooks?, levels: { any }?): RunDriver.RunDriver
	return RunDriver.new({
		layout = l,
		levels = levels,
		automated = true,
		hooks = hooks,
		runSeed = 5,
	})
end

local function held(d: RunDriver.RunDriver): boolean
	local stage = (d:snapshot() :: any).stage
	return stage ~= nil and stage ~= "traveling"
end

-- Ticks `dt` until the lead is at the plane `z` (or the run ends), collecting events.
local function toPlane(d: RunDriver.RunDriver, dt: number, z: number): { RunDriver.DriverEvent }
	local all = {}
	for _ = 1, 4000 do
		for _, e in d:tick(dt) do
			table.insert(all, e)
		end
		if d:snapshot().z >= z - 1e-9 or d:outcome() ~= nil then
			break
		end
	end
	return all
end

local function toCheckpoint(d: RunDriver.RunDriver, dt: number): { RunDriver.DriverEvent }
	return toPlane(d, dt, CP_Z)
end

local function resolve(d: RunDriver.RunDriver, id: number): boolean
	local f = (d :: any).resolveCheckpoint
	assert(type(f) == "function", "driver has no resolveCheckpoint hook")
	return f(d, id)
end

local function count(events: { RunDriver.DriverEvent }, kinds: { [string]: boolean }): number
	local n = 0
	for _, e in events do
		if kinds[e.kind] then
			n += 1
		end
	end
	return n
end

local function tickN(d: RunDriver.RunDriver, n: number, into: { RunDriver.DriverEvent }?)
	for _ = 1, n do
		for _, e in d:tick(DT) do
			if into then
				table.insert(into, e)
			end
		end
	end
end

-- Sim time of the first "cluster" event, ticking at DT up to `seconds`; nil if none.
local function firstClusterTime(d: RunDriver.RunDriver, seconds: number): number?
	for _ = 1, math.ceil(seconds / DT) do
		for _, e in d:tick(DT) do
			if e.kind == "cluster" then
				return d:snapshot().time
			end
		end
	end
	return nil
end

return {
	{
		name = "overshoot: a step that crosses the plane is clamped to it, and the lead stays there",
		run = function()
			local d = driver(layout())
			toCheckpoint(d, 0.1)
			eq(d:snapshot().z, CP_Z, "clamped to the plane, no overshoot")
			eq((d:snapshot() :: any).stage, HELD, "stage names the fight")
			local t0 = d:snapshot().time
			for _ = 1, 30 do
				d:tick(0.1)
				eq(d:snapshot().z, CP_Z, "still at the plane")
			end
			near(d:snapshot().time - t0, 3, 1e-6, "combat time advanced three seconds")
			for _ = 1, 1000 do
				d:tick(0.1)
			end
			eq(d:outcome(), nil, "the street end cannot complete past an unresolved checkpoint")
			eq(d:snapshot().z, CP_Z, "no distance accumulates while held")
		end,
	},
	{
		name = "stationary firing: shots keep landing and converting while the lead is stopped",
		run = function()
			-- Spawns before the stop at route 9.5 s, far enough ahead that it enters range mid-hold.
			local l = layout({ clusters = { smallMob(1, 9.5, 170) } })
			local d = driver(l, RunHooks.new(l, FastFire.config()))
			toCheckpoint(d, DT)
			local events: { RunDriver.DriverEvent } = {}
			tickN(d, 240, events)
			eq(d:snapshot().z, CP_Z, "lead stayed at the plane")
			assert(
				count(events, { cluster = true }) >= 3,
				"the meter filled from the stationary lead"
			)
			eq(
				d:total(),
				Config.startingTotal + Config.clusterTypes.small.reward,
				"conversion paid once"
			)
		end,
	},
	{
		name = "stationary steering: the lead slides sideways while forward travel is stopped",
		run = function()
			local d = driver(layout())
			toCheckpoint(d, DT)
			assert(d:steer(0, { x = 10 }), "steer accepted")
			tickN(d, 60)
			near(d:snapshot().x, 10, 1e-6, "lateral motion reached the target")
			eq(d:snapshot().z, CP_Z, "forward position unchanged")
			assert(d:steer(5, { x = -10 }), "steer accepted again")
			tickN(d, 60)
			near(d:snapshot().x, -10, 1e-6, "and back")
			eq(d:snapshot().z, CP_Z, "forward position unchanged")
		end,
	},
	{
		name = "no repeats: gates, pickups and spawns ahead stay quiet while stationary and fire once after resume",
		run = function()
			local function gate(id: number, z: number): any
				return {
					id = id,
					z = z,
					left = { kind = "add", value = 15 },
					right = { kind = "multiply", value = 2 },
				}
			end
			local l = layout({
				gates = { gate(1, CP_Z), gate(2, 100) },
				pickups = {
					{ id = 1, z = CP_Z, lane = "center" },
					{ id = 2, z = 110, lane = "center" },
				},
				clusters = { smallMob(1, 12, 150) },
			})
			local d = driver(l, RunHooks.new(l, FastFire.config()))
			local all = toCheckpoint(d, DT)
			local totalAtStop = d:total()
			-- Ten seconds held, sliding across every lane the whole time.
			local now = 0
			for i = 1, 300 do
				if i % 60 == 1 then
					now += 1
					d:steer(now, { x = if (i // 60) % 2 == 0 then 10 else -10 })
				end
				for _, e in d:tick(DT) do
					table.insert(all, e)
				end
			end
			eq(d:total(), totalAtStop, "nothing paid or charged while held")
			eq(d:snapshot().z, CP_Z, "still held")
			-- The plane's own gate and pickup fire once, on the entry tick (z0 < plane <= z1).
			eq(
				count(all, { gate = true, pickup = true, cluster = true, attack = true }),
				2,
				"only the gate and pickup AT the plane fired, once each"
			)
			assert(d:steer(now + 1, { x = 0 }), "steer back to the centre lane")
			tickN(d, 90)
			assert(resolve(d, 1), "checkpoint resolved")
			tickN(d, 30 * 25, all)
			eq(count(all, { gate = true }), 2, "each gate fired exactly once")
			eq(count(all, { pickup = true }), 2, "each pickup fired exactly once")
			assert(count(all, { cluster = true }) >= 3, "the late mob appears after the resume")
		end,
	},
	{
		name = "hazards: a warning already issued completes on combat time; no new warning while held",
		run = function()
			-- Impacts at route 20 s and 34 s (warnings at 17.5 s and 31.5 s). The stop is at route 18 s.
			local set =
				{ kinds = { "tomato" }, firstAt = 20, lastAt = 34, minGap = 14, maxGap = 14 }
			local l = layout({
				hazardSet = set,
				checkpoints = { { id = 1, z = 18 * SPEED, kind = "mini-boss" } },
			})
			local d = driver(l)
			local impact = { hazard_hit = true, hazard_dodged = true, hazard_blocked = true }
			local events = toPlane(d, DT, 18 * SPEED)
			eq(count(events, { hazard_warning = true }), 1, "first warning issued before the stop")
			-- Forty seconds of combat time pass while held.
			local impactAt: number? = nil
			for _ = 1, 1200 do
				for _, e in d:tick(DT) do
					table.insert(events, e)
					if impact[e.kind] and impactAt == nil then
						impactAt = d:snapshot().time
					end
				end
			end
			eq(
				count(events, { hazard_warning = true }),
				1,
				"no route-driven warning while stationary"
			)
			eq(count(events, impact), 1, "the warned hazard resolved once, during the hold")
			near(impactAt or -1, 20, 2 * DT, "impact lands on combat time, 20 s into the run")
			assert(resolve(d, 1), "checkpoint resolved")
			local resumed = d:snapshot().time
			local secondAt: number? = nil
			for _ = 1, 30 * 40 do
				for _, e in d:tick(DT) do
					table.insert(events, e)
					if impact[e.kind] and secondAt == nil and count(events, impact) == 2 then
						secondAt = d:snapshot().time
					end
				end
			end
			eq(
				count(events, { hazard_warning = true }),
				2,
				"the next warning fires after the resume"
			)
			eq(count(events, impact), 2, "and resolves once")
			near(
				secondAt or -1,
				resumed + (34 - 18),
				3 * DT,
				"second impact is route-timed from the resume"
			)
		end,
	},
	{
		name = "mobs keep their own age through a stop: one spawned before it arrives on combat time",
		run = function()
			-- Spawned at route 9 s at z 400 (before the stop at route ~10.04 s), center lane. The lead is
			-- held at 72.3, so it is in range (60 studs) once the mob has walked (400 - 132.3) studs.
			local l = layout({ clusters = { smallMob(1, 9, 400) } })
			local d = driver(l, RunHooks.new(l, FastFire.config()))
			toCheckpoint(d, DT)
			local at = firstClusterTime(d, 60)
			local expected = 9
				+ (400 - (CP_Z + Config.firing.range)) / Config.spectators.approachSpeed
			assert(at ~= nil, "mob never came into range")
			assert(
				at >= expected - 1e-6 and at <= expected + 0.35,
				`first hit at {at}, expected within [{expected}, {expected + 0.35}]`
			)
		end,
	},
	{
		name = "smooth resume: no jump, no queued burst, and a later spawn arrives shifted by exactly the hold",
		run = function()
			local mob = { smallMob(1, 12, 300) }
			-- Control: the same mob with no checkpoint.
			local cl = layout({ clusters = mob, checkpoints = {} })
			local control = driver(cl, RunHooks.new(cl, FastFire.config()))
			local tControl = firstClusterTime(control, 60)
			assert(tControl ~= nil, "control mob never came into range")

			local l = layout({ clusters = mob })
			local d = driver(l, RunHooks.new(l, FastFire.config()))
			toCheckpoint(d, DT)
			tickN(d, 100) -- hold 100 ticks
			eq(d:snapshot().z, CP_Z, "held")
			assert(resolve(d, 1), "resolved")
			local zPrev = d:snapshot().z
			local maxShots = 0
			local at: number? = nil
			local firstStep: number? = nil
			for _ = 1, 30 * 60 do
				local events = d:tick(DT)
				local z = d:snapshot().z
				assert(z >= zPrev - 1e-9, "never moves backwards")
				assert(z - zPrev <= SPEED * DT + 1e-9, `lead jumped {z - zPrev} in one tick`)
				if firstStep == nil and z > zPrev then
					firstStep = z - zPrev
				end
				zPrev = z
				maxShots = math.max(maxShots, count(events, { cluster = true, miss = true }))
				if at == nil then
					for _, e in events do
						if e.kind == "cluster" then
							at = d:snapshot().time
						end
					end
				end
			end
			near(
				firstStep or 0,
				SPEED * DT,
				1e-6,
				"the first step after the resume is one ordinary step"
			)
			assert(maxShots <= 3, `a burst of {maxShots} shot events in one tick`)
			assert(at ~= nil, "mob never came into range after the resume")
			-- The shift between the runs is the time spent stationary: combat time minus route time.
			local s = d:snapshot()
			local shift = s.time - s.z / SPEED
			assert(shift > 100 * DT - 1e-6, `the shift {shift} is at least the hold`)
			near(
				(at :: number) - (tControl :: number),
				shift,
				1 / FastFire.config().firing.tiers[1].shotsPerSecond + DT, -- the shot grid is the only slack
				"arrival shifted by exactly the hold"
			)
		end,
	},
	{
		name = "identity: resolve is refused before the plane, accepted once at it, never twice, never for other ids",
		run = function()
			local d = driver(layout())
			eq(resolve(d, 1), false, "cannot skip a checkpoint not yet reached")
			toCheckpoint(d, DT)
			eq((d:snapshot() :: any).stage, HELD, "still stops after the refused early resolve")
			eq(resolve(d, 2), false, "unknown id refused")
			eq(resolve(d, 1), true, "accepted once")
			eq(resolve(d, 1), false, "a repeated message is refused")
			tickN(d, 3)
			eq(resolve(d, 1), false, "and after the resume")
			assert(d:snapshot().z > CP_Z, "travelling again")
			tickN(d, 300)
			assert(not held(d), "the resolved checkpoint never stops the lead again")
		end,
	},
	{
		name = "defeat wins: crowd exhaustion on the tick a resolution is pending ends the run defeated",
		run = function()
			local doomed = false
			local d = driver(layout(), {
				endCheck = function(): boolean
					return doomed
				end,
			})
			toCheckpoint(d, DT)
			eq(held(d), true, "held")
			doomed = true
			eq(resolve(d, 1), true, "resolution requested")
			d:tick(DT)
			eq(d:outcome(), "defeated", "defeat takes precedence")
			assert(held(d), "the resolution did not resume a finished run")
			eq(resolve(d, 1), false, "nothing resolves after the end")
		end,
	},
	{
		name = "resolution without defeat resumes on the next tick",
		run = function()
			local d = driver(layout())
			toCheckpoint(d, DT)
			eq(resolve(d, 1), true, "requested")
			d:tick(DT)
			eq(d:outcome(), nil, "not over")
			eq((d:snapshot() :: any).stage, "traveling", "resumed")
		end,
	},
	{
		name = "reset: a level change re-arms level-local checkpoint ids and replay clears them",
		run = function()
			local l1 = layout({ name = "one" })
			local l2 = layout({ name = "two" })
			local d = driver(l1, nil, { l1, l2 })
			toCheckpoint(d, DT)
			assert(resolve(d, 1), "level one checkpoint resolved")
			for _ = 1, 30 * 90 do
				d:tick(DT)
				if d:snapshot().level == 2 then
					break
				end
			end
			eq(d:snapshot().level, 2, "advanced to level two")
			eq((d:snapshot() :: any).stage, "traveling", "level two starts travelling")
			toCheckpoint(d, DT)
			eq(d:snapshot().z, CP_Z, "level two stops at its own checkpoint 1")
			eq((d:snapshot() :: any).stage, HELD, "level-local id 1 is live again")
			assert(resolve(d, 1), "and resolves once there")
			for _ = 1, 30 * 90 do
				d:tick(DT)
				if d:outcome() ~= nil then
					break
				end
			end
			eq(d:outcome(), "completed", "the run completes only after both were resolved")

			-- Replay after a defeat mid-hold.
			local doomed = false
			local r = driver(layout({ name = "three" }), {
				endCheck = function(): boolean
					return doomed
				end,
			})
			toCheckpoint(r, DT)
			eq(held(r), true, "held")
			doomed = true
			r:tick(DT)
			eq(r:outcome(), "defeated", "defeated while held")
			doomed = false
			assert(r:replay(100), "replay accepted")
			eq(r:snapshot().z, 0, "back at the start")
			eq((r:snapshot() :: any).stage, "traveling", "no stale stage")
			toCheckpoint(r, DT)
			eq((r:snapshot() :: any).stage, HELD, "the checkpoint is armed again")
			assert(resolve(r, 1), "and resolves again")
			eq(resolve(r, 1), false, "still only once")
		end,
	},
	{
		name = "client ServerClock: a missed stop is recovered from the hold plane carried by every State",
		run = function()
			local ServerClock = require("../src/shared/ServerClock")
			local clock = ServerClock.new()
			local offset = 500.25
			-- Traveling States up to run time 9.9 s (z 71.28) announce the plane at 72.3.
			for i = 1, 99 do
				local t = i * 0.1
				clock:observe(
					{ t = t, z = SPEED * t, x = 0, stage = "traveling", holdZ = CP_Z },
					t + offset
				)
			end
			-- Every later State is lost. The client must not draw past the plane.
			local maxZ = 0
			for k = 0, 120 do
				local _, z = clock:sample(9.9 + offset + k / 60, SPEED, 1440)
				maxZ = math.max(maxZ, z)
			end
			assert(maxZ <= CP_Z + 1e-9, `drew z {maxZ} past the hold plane {CP_Z}`)
		end,
	},
	{
		name = "client ServerClock: stopped States hold z but lateral motion and run time keep going",
		run = function()
			local ServerClock = require("../src/shared/ServerClock")
			local clock = ServerClock.new()
			local offset = 77.5
			local lastT = -1
			local firstX: number? = nil
			local lastX = 0
			local zs: { number } = {}
			for i = 0, 40 do
				local t = 10 + i * 0.1
				clock:observe({
					t = t,
					z = CP_Z,
					x = math.min(10, 24 * math.max(0, t - 10)),
					stage = HELD,
				}, t + offset)
				for f = 0, 5 do -- 60 fps between 10 Hz States
					local x, z, rt = clock:sample(t + offset + f / 60, SPEED, 1440)
					table.insert(zs, z)
					firstX = firstX or x
					lastX = x
					assert(rt >= lastT - 1e-9, "run time never goes backwards")
					lastT = rt
				end
			end
			for _, z in zs do
				eq(z, CP_Z, "z constant while stopped")
			end
			assert(lastX > (firstX :: number) + 5, `x did not slide: {firstX} -> {lastX}`)
		end,
	},
	{
		name = "client ServerClock: a resume whose States were partly missed never draws z backwards",
		run = function()
			local ServerClock = require("../src/shared/ServerClock")
			local clock = ServerClock.new()
			local offset = 12.5
			for i = 0, 20 do
				local t = 10 + i * 0.1
				clock:observe({ t = t, z = CP_Z, x = 0, stage = HELD }, t + offset)
			end
			local last = -1
			local function sampleAt(now: number)
				local _, z = clock:sample(now, SPEED, 1440)
				assert(z >= last - 1e-9, `z went back: {last} -> {z}`)
				last = z
			end
			for k = 0, 30 do
				sampleAt(12 + offset + k / 60)
			end
			-- Resume States at 13.0 .. 13.2 were lost; the next to arrive is at 13.3.
			clock:observe(
				{ t = 13.3, z = CP_Z + SPEED * 0.3, x = 0, stage = "traveling" },
				13.3 + offset
			)
			for k = 0, 90 do
				sampleAt(13.3 + offset + k / 60)
			end
			assert(last > CP_Z, "travelling again")
		end,
	},
	{
		name = "Remotes: stage and hold plane are validated on the wire",
		run = function()
			local R: any = require("../src/shared/Remotes")
			assert(type(R.isStage) == "function", "Remotes.isStage missing")
			eq(R.isStage("traveling"), true, "traveling")
			eq(R.isStage("mini-boss-combat"), true, "mini-boss-combat")
			eq(R.isStage("ready"), false, "ready is a phase, not a stage")
			eq(R.isStage("anything"), false, "unknown")
			eq(R.isStage(7), false, "non-string")
			local good: any = R.encodeState({
				time = 12.345,
				z = CP_Z,
				x = 1,
				total = 10,
				best = 10,
				stage = HELD,
				holdZ = CP_Z,
			})
			eq(good.stage, HELD, "stage encoded")
			eq(good.holdZ, CP_Z, "holdZ encoded")
			local bad: any = R.encodeState({
				time = 1,
				z = 1,
				x = 0,
				total = 10,
				best = 10,
				stage = "hax",
				holdZ = 0 / 0,
			})
			eq(bad.stage, "traveling", "unknown stage falls back to traveling")
			eq(bad.holdZ, nil, "non-finite holdZ dropped")
			local none: any = R.encodeState({ time = 1, z = 1, x = 0, total = 10, best = 10 })
			eq(none.stage, "traveling", "default stage")
			eq(none.holdZ, nil, "no hold plane by default")
		end,
	},
	{
		name = "RunView debug extrapolation also stops at a held stage and at the hold plane",
		run = function()
			local RunView = require("../src/shared/RunView")
			local stopped: any = { t = 10, z = CP_Z, x = 0, over = false, stage = HELD }
			local _, z = RunView.leadPosition(stopped, 0.3, SPEED, 1440)
			eq(z, CP_Z, "no extrapolation while held")
			local approaching: any =
				{ t = 9.9, z = 71.28, x = 0, over = false, stage = "traveling", holdZ = CP_Z }
			local _, z2 = RunView.leadPosition(approaching, 0.3, SPEED, 1440)
			assert(z2 <= CP_Z + 1e-9, `extrapolated to {z2} past the plane`)
		end,
	},
	{
		name = "LayoutValidator: checkpoints must be ordered, inside the street, unique and a known kind",
		run = function()
			local Layouts = require("../src/shared/Layouts")
			local LayoutValidator = require("../src/shared/LayoutValidator")
			local base: any = Layouts.all[1]
			local function with(list: any): any
				local copy = table.clone(base)
				copy.checkpoints = list
				return copy
			end
			eq(
				LayoutValidator.validate(with({ { id = 1, z = 400, kind = "mini-boss" } })),
				true,
				"valid"
			)
			eq(
				LayoutValidator.validate(with({ { id = 1, z = 0, kind = "mini-boss" } })),
				false,
				"z must be positive"
			)
			eq(
				LayoutValidator.validate(
					with({ { id = 1, z = base.plazaStart, kind = "mini-boss" } })
				),
				false,
				"z must be before the plaza"
			)
			eq(
				LayoutValidator.validate(with({
					{ id = 1, z = 500, kind = "mini-boss" },
					{ id = 1, z = 600, kind = "mini-boss" },
				})),
				false,
				"ids unique"
			)
			eq(
				LayoutValidator.validate(with({
					{ id = 1, z = 600, kind = "mini-boss" },
					{ id = 2, z = 500, kind = "mini-boss" },
				})),
				false,
				"z ascending"
			)
			eq(
				LayoutValidator.validate(with({ { id = 1, z = 400, kind = "wizard" } })),
				false,
				"known kind"
			)
		end,
	},
}
