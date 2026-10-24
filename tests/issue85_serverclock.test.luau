--!strict
-- Issue #85 item 2/3: the 10 Hz State must not make the drawn lead or the camera shimmer.
-- Pure simulation of State delivery with jitter (server 30 Hz ticks, State every 0.1 s, 60 FPS client).
local CameraRig = require("../src/shared/CameraRig")
local Config = require("../src/shared/Config")
local RunView = require("../src/shared/RunView")
local ServerClock = require("../src/shared/ServerClock")
local Steering = require("../src/shared/Steering")
local ViewMap = require("../src/shared/ViewMap")

local FPS = 60
local DT = 1 / FPS
local SPEED = Config.speed
local MAX_Z = 1440
local CLIENT_OFFSET = 1000.123 -- the client's os.clock() has nothing to do with server time
local NOMINAL = SPEED * DT -- studs the lead advances per frame

local seed = 12345
local function rand(): number -- deterministic LCG in [0, 1)
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end

type Packet = { arrival: number, state: any }
type Scenario = { jitter: number, late: { [number]: number }?, steerAt: { [number]: number }? }

-- Server states every 0.1 s (t rounded down to the 30 Hz tick), delivered in order with jitter.
local function packets(duration: number, sc: Scenario): { Packet }
	local out: { Packet } = {}
	local x, target, lastArrival = 0, 0, -1
	local tick = 0
	for i = 1, math.floor(duration / 0.1) do
		local send = i * 0.1
		local steer = sc.steerAt and sc.steerAt[i]
		if steer then
			target = steer
		end
		while (tick + 1) / 30 <= send + 1e-9 do
			tick += 1
			x = Steering.step(x, target, 1 / 30, Steering.MAX_LATERAL_SPEED)
		end
		local t = tick / 30
		local arrival = send + 0.05 + (rand() * 2 - 1) * sc.jitter + ((sc.late and sc.late[i]) or 0)
		arrival = math.max(arrival, lastArrival + 0.0005) -- RemoteEvents are ordered
		lastArrival = arrival
		table.insert(out, {
			arrival = arrival,
			state = { t = t, z = SPEED * t, x = x, total = 10, over = false },
		})
	end
	return out
end

type Trace = { z: { number }, x: { number }, camX: { number }, camZ: { number }, err: { number } }

-- Runs the client render loop. `mode` "old" is the pre-#85 Main logic; "clock" is ServerClock.
local function run(mode: string, duration: number, sc: Scenario): Trace
	local pk = packets(duration, sc)
	local nextPacket = 1
	local clock = ServerClock.new()
	local latest: any, receivedAt = nil, 0
	local drawnX = 0
	local tr: Trace = { z = {}, x = {}, camX = {}, camZ = {}, err = {} }
	for f = 1, math.floor(duration * FPS) do
		local serverNow = f * DT
		local now = serverNow + CLIENT_OFFSET
		while nextPacket <= #pk and pk[nextPacket].arrival <= serverNow do
			local s = pk[nextPacket].state
			latest, receivedAt = s, now
			clock:observe(s, now)
			nextPacket += 1
		end
		if latest then
			local x, z
			if mode == "old" then
				x, z = RunView.leadPosition(latest, now - receivedAt, SPEED, MAX_Z)
			else
				x, z = clock:sample(now, SPEED, MAX_Z)
			end
			drawnX = CameraRig.smooth(drawnX, x, DT, 8) -- Main's CAMERA_X_RATE
			local pose = CameraRig.pose(ViewMap.x(drawnX), z, 1)
			table.insert(tr.z, z)
			table.insert(tr.x, drawnX)
			table.insert(tr.camX, pose.px)
			table.insert(tr.camZ, pose.pz + CameraRig.BACK) -- == z, tests the pose path too
			table.insert(tr.err, z - SPEED * (serverNow - 0.05)) -- vs the server lead a latency ago
		end
	end
	return tr
end

local WARMUP = 1.5 * FPS -- frames: the first States establish the clock

-- Largest and smallest per-frame advance, as a multiple of the nominal one.
local function stepRatios(
	series: { number },
	from: number,
	to: number,
	nominal: number
): (number, number)
	local hi, lo = -math.huge, math.huge
	for i = from + 1, math.min(to, #series) do
		local r = (series[i] - series[i - 1]) / nominal
		hi, lo = math.max(hi, r), math.min(lo, r)
	end
	return hi, lo
end

local SCENARIOS: { { name: string, sc: Scenario } } = {
	{ name = "steady", sc = { jitter = 0 } },
	{ name = "jitter +-0.03 s", sc = { jitter = 0.03 } },
	{ name = "one late packet (+0.25 s)", sc = { jitter = 0.03, late = { [50] = 0.25 } } },
	{ name = "burst of two (+0.1 s on one)", sc = { jitter = 0.03, late = { [60] = 0.1 } } },
	{ name = "heavy jitter +-0.06 s", sc = { jitter = 0.06 } },
}

local cases = {}
for _, s in SCENARIOS do
	table.insert(cases, {
		name = `lead z advances within 0.95..1.05 x nominal every frame: {s.name}`,
		run = function()
			seed = 12345
			local tr = run("clock", 20, s.sc)
			local hi, lo = stepRatios(tr.z, WARMUP, #tr.z, NOMINAL)
			assert(hi <= 1.05, `max z step {hi} x nominal`)
			assert(lo >= 0.95, `min z step {lo} x nominal`)
			local chi = stepRatios(tr.camZ, WARMUP, #tr.camZ, NOMINAL)
			assert(chi <= 1.05, `camera z max step {chi} x nominal`)
		end,
	})
end

table.insert(cases, {
	name = "baseline: today's snap-to-State logic exceeds the bound under jitter (documents the defect)",
	run = function()
		seed = 12345
		local tr = run("old", 20, { jitter = 0.03 })
		local hi, lo = stepRatios(tr.z, WARMUP, #tr.z, NOMINAL)
		print(
			`  old logic with +-0.03 s jitter: z step {string.format("%.2f", lo)}..{string.format(
				"%.2f",
				hi
			)} x nominal`
		)
		assert(hi > 1.5 or lo < 0.5, `expected the old logic to snap, got {lo}..{hi}`)
	end,
})

table.insert(cases, {
	name = "drawn lead stays close to the server lead (bounded lag/lead) under jitter",
	run = function()
		seed = 12345
		local tr = run("clock", 20, { jitter = 0.03 })
		local worst = 0
		for i = WARMUP, #tr.err do
			worst = math.max(worst, math.abs(tr.err[i]))
		end
		assert(worst <= SPEED * 0.12, `lead off by {worst} studs (limit {SPEED * 0.12})`)
	end,
})

local STEER = { steerAt = { [30] = 40 } } -- at t=3 s ask for x=40: a 1.7 s slide at 24 studs/s

for _, mode in { "clock" } do
	table.insert(cases, {
		name = "lateral slide is smooth: per-frame x speed ripple under 5% with jitter",
		run = function()
			seed = 12345
			local tr = run(mode, 8, { jitter = 0.03, steerAt = STEER.steerAt })
			-- 3.7 s .. 4.4 s: well inside the slide (it ends near 4.9 s)
			local hi, lo = stepRatios(tr.x, math.floor(3.7 * FPS), math.floor(4.4 * FPS), 1)
			assert(lo > 0, "should be moving")
			assert((hi - lo) / ((hi + lo) / 2) <= 0.05, `x step ripple {lo}..{hi}`)
			local chi, clo = stepRatios(tr.camX, math.floor(3.7 * FPS), math.floor(4.4 * FPS), 1)
			assert((chi - clo) / ((chi + clo) / 2) <= 0.05, `camera x step ripple {clo}..{chi}`)
		end,
	})
end

table.insert(cases, {
	name = "baseline: today's x path ripples at 10 Hz (documents the defect)",
	run = function()
		seed = 12345
		local tr = run("old", 8, { jitter = 0.03, steerAt = STEER.steerAt })
		local hi, lo = stepRatios(tr.x, math.floor(3.7 * FPS), math.floor(4.4 * FPS), 1)
		local ripple = (hi - lo) / ((hi + lo) / 2)
		print(
			`  old x path: step {string.format("%.3f", lo)}..{string.format("%.3f", hi)} studs/frame, ripple {string.format(
				"%.0f%%",
				ripple * 100
			)}`
		)
		assert(ripple > 0.15, `expected visible ripple, got {ripple}`)
	end,
})

table.insert(cases, {
	name = "x never moves faster than the server's lateral speed limit (+5%)",
	run = function()
		seed = 12345
		local tr =
			run("clock", 10, { jitter = 0.06, steerAt = { [30] = 40, [60] = -40, [62] = 10 } })
		local hi, lo = stepRatios(tr.x, 2, #tr.x, Steering.MAX_LATERAL_SPEED * DT)
		assert(hi <= 1.05 and lo >= -1.05, `x step {lo}..{hi} x the lateral limit`)
	end,
})

table.insert(cases, {
	name = "duplicate and out-of-order States are ignored; the lead does not move backwards",
	run = function()
		local c = ServerClock.new()
		local function st(t: number, x: number?): any
			return { t = t, z = SPEED * t, x = x or 0, total = 10, over = false }
		end
		local base = 500
		assert(c:observe(st(1.0), base + 1.05))
		assert(c:observe(st(1.1), base + 1.15))
		assert(not c:observe(st(1.1), base + 1.16), "duplicate")
		assert(not c:observe(st(1.0), base + 1.17), "stale")
		local _, z1 = c:sample(base + 1.2, SPEED, MAX_Z)
		local _, z2 = c:sample(base + 1.2 + DT, SPEED, MAX_Z)
		assert(z2 > z1, "keeps advancing")
	end,
})

table.insert(cases, {
	name = "a replay (run time jumps back) resets the clock: no stale position, no slew from the old run",
	run = function()
		local c = ServerClock.new()
		local base = 500
		for i = 1, 100 do
			c:observe(
				{ t = i * 0.1, z = SPEED * i * 0.1, x = 5, total = 10, over = false },
				base + i * 0.1 + 0.05
			)
		end
		c:observe({ t = 0, z = 0, x = 0, total = 10, over = false }, base + 20)
		local x, z, t = c:sample(base + 20, SPEED, MAX_Z)
		assert(
			math.abs(z) < 1 and math.abs(t) < 0.1 and math.abs(x) < 0.01,
			`after replay got x={x} z={z} t={t}`
		)
	end,
})

table.insert(cases, {
	name = "a finished run is drawn exactly where the server left it",
	run = function()
		local c = ServerClock.new()
		c:observe({ t = 10, z = 160, x = 3, total = 10, over = true, outcome = "completed" }, 100)
		local x, z, t = c:sample(105, SPEED, MAX_Z)
		assert(z == 160 and t == 10 and x == 3, `got {x} {z} {t}`)
	end,
})

table.insert(cases, {
	name = "the lead never extrapolates past maxZ, and an outage freezes it after MAX_EXTRAPOLATION",
	run = function()
		local c = ServerClock.new()
		c:observe({ t = 89, z = 1424, x = 0, total = 10, over = false }, 100)
		local _, z = c:sample(105, SPEED, MAX_Z)
		assert(z <= MAX_Z, "capped at the plaza")
		local c2 = ServerClock.new()
		c2:observe({ t = 10, z = 160, x = 0, total = 10, over = false }, 100)
		local _, zFar = c2:sample(110, SPEED, MAX_Z)
		assert(zFar <= 160 + SPEED * RunView.MAX_EXTRAPOLATION + 1e-6, `outage z {zFar}`)
	end,
})

return cases
