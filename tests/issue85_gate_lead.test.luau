--!strict
-- Issue #85 (gate banners): GateView drove the portal fade, pulse and transparency from the raw
-- 10 Hz State dead-reckoning (RunView.leadPosition), while Main draws the lead and camera from the
-- smoothed ServerClock timeline. Each State re-based the banner distance by the network jitter and
-- the 30 Hz tick rounding, so a banner's transparency stepped 10 times a second as it passed the
-- lead. These cases pin GateView to the same ServerClock lead Main uses, and measure the step.
local fs = require("@lune/fs")
local Config = require("../src/shared/Config")
local PortalFx = require("../src/shared/PortalFx")
local RunView = require("../src/shared/RunView")
local ServerClock = require("../src/shared/ServerClock")

local FPS = 60
local SPEED = Config.speed
local MAX_Z = 1440
local CLIENT_OFFSET = 1000.123
local GATE_Z = SPEED * 20 -- the same 20-second pass at any configured forward pace
local TAIL = 4 -- stands in for ParadeTail.depth(total): a small parade behind the lead

local seed = 4242
local function rand(): number -- deterministic LCG in [0, 1)
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end

-- States every 0.1 s, t rounded down to the 30 Hz tick, delivered in order with jitter.
local function packets(duration: number, jitter: number): { { arrival: number, state: any } }
	local out = {}
	local lastArrival = -1
	local tick = 0
	for i = 1, math.floor(duration / 0.1) do
		local send = i * 0.1
		while (tick + 1) / 30 <= send + 1e-9 do
			tick += 1
		end
		local t = tick / 30
		local arrival = send + 0.05 + (rand() * 2 - 1) * jitter
		arrival = math.max(arrival, lastArrival + 0.0005)
		lastArrival = arrival
		table.insert(out, {
			arrival = arrival,
			state = { t = t, z = SPEED * t, x = 0, total = 10, over = false },
		})
	end
	return out
end

-- Banner fade error per rendered frame: the fade from the lead the client used, minus the fade from
-- a noise-free lead on the server timeline (a constant lag). "raw" is the old GateView lead;
-- "clock" is ServerClock. The error changes smoothly only if the lead does.
local function fadeTrace(mode: string, jitter: number): { number }
	seed = 4242
	local duration = 30
	local pk = packets(duration, jitter)
	local clock = ServerClock.new()
	local nextPacket = 1
	local latest: any, receivedAt = nil, 0
	local out = {}
	for f = 1, math.floor(duration * FPS) do
		local serverNow = f / FPS
		local now = serverNow + CLIENT_OFFSET
		while nextPacket <= #pk and pk[nextPacket].arrival <= serverNow do
			latest, receivedAt = pk[nextPacket].state, now
			clock:observe(latest, now)
			nextPacket += 1
		end
		if latest then
			local _, leadZ
			if mode == "raw" then
				_, leadZ = RunView.leadPosition(latest, now - receivedAt, SPEED, MAX_Z)
			else
				_, leadZ = clock:sample(now, SPEED, MAX_Z)
			end
			local idealZ = math.min(MAX_Z, SPEED * math.max(0, serverNow - 0.05))
			table.insert(
				out,
				PortalFx.fade(leadZ - GATE_Z, TAIL) - PortalFx.fade(idealZ - GATE_Z, TAIL)
			)
		end
	end
	return out
end

-- Largest frame-to-frame change of the fade error (a State re-base shows as a spike).
local function worstKink(series: { number }, from: number): number
	local worst = 0
	for i = from + 1, #series do
		worst = math.max(worst, math.abs(series[i] - series[i - 1]))
	end
	return worst
end

local WARMUP = 2 * FPS

local cases = {}

table.insert(cases, {
	name = "GateView takes its lead from ServerClock, not the raw 10 Hz State extrapolation",
	run = function()
		local source = fs.readFile("src/client/GateView.luau")
		assert(
			string.find(source, "ServerClock.new()", 1, true),
			"GateView must own a ServerClock (the same lead timeline Main draws)"
		)
		assert(
			string.find(source, "serverClock:sample(", 1, true),
			"GateView's Heartbeat must sample the smoothed lead"
		)
		assert(
			string.find(source, "Config.debug.rawExtrapolation", 1, true),
			"the raw path may only remain behind Config.debug.rawExtrapolation"
		)
	end,
})

table.insert(cases, {
	name = "banner fade error has no 10 Hz kink under +-0.03 s State jitter (ServerClock timeline)",
	run = function()
		local kink = worstKink(fadeTrace("clock", 0.03), WARMUP)
		-- ServerClock's own floor here is about 0.05 (EWMA + 4% slew); the raw path is about 0.27.
		assert(kink <= 0.06, `clock fade kink {kink} per frame (limit 0.06)`)
	end,
})

table.insert(cases, {
	name = "documents the defect: the raw State lead kinks the banner fade under jitter",
	run = function()
		local raw = worstKink(fadeTrace("raw", 0.03), WARMUP)
		local clock = worstKink(fadeTrace("clock", 0.03), WARMUP)
		print(
			`  banner fade kink per frame, +-0.03 s jitter: raw {string.format("%.4f", raw)}, clock {string.format(
				"%.4f",
				clock
			)}`
		)
		assert(raw > 3 * clock, `expected the raw path to kink more: raw {raw}, clock {clock}`)
	end,
})

return cases
