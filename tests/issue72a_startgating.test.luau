--!strict
-- Issue #72 part 1: the run is created ready-but-paused and starts on ONE client request.
local DebugLayout = require("../src/shared/DebugLayout")
local Remotes = require("../src/shared/Remotes")
local RunDriver = require("../src/shared/RunDriver")

local DT = RunDriver.TICK_DT

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function ready(): RunDriver.RunDriver
	return RunDriver.new({ layout = DebugLayout, automated = false, startReady = true })
end

local function runToEnd(d: RunDriver.RunDriver)
	for _ = 1, 30 * 200 do
		d:tick(DT)
		if d:outcome() ~= nil then
			return
		end
	end
	error("run never ended")
end

return {
	{
		name = "a driver without startReady runs at once (existing behaviour kept)",
		run = function()
			local d = RunDriver.new({ layout = DebugLayout, automated = false })
			eq(d:phase(), "running", "phase")
			d:tick(DT)
			assert(d:snapshot().time > 0, "advanced")
		end,
	},
	{
		name = "ready -> running -> over",
		run = function()
			local d = ready()
			eq(d:phase(), "ready", "initial")
			eq(d:start(100), true, "start accepted")
			eq(d:phase(), "running", "after start")
			runToEnd(d)
			eq(d:phase(), "over", "after end")
		end,
	},
	{
		name = "a paused run does not advance, log, or emit events",
		run = function()
			local d = ready()
			local before = #d:events()
			for _ = 1, 600 do
				eq(#d:tick(DT), 0, "no events")
			end
			local s = d:snapshot()
			eq(s.time, 0, "time")
			eq(s.z, 0, "z")
			eq(s.outcome, nil, "outcome")
			eq(#d:events(), before, "log untouched")
			eq(d:steer(1, { x = 5 }), false, "steer ignored while ready")
			eq(d:snapshot().x, 0, "x")
		end,
	},
	{
		name = "start is ignored when not ready: second Start while running",
		run = function()
			local d = ready()
			eq(d:start(10), true, "first")
			d:tick(DT)
			local t = d:snapshot().time
			eq(d:start(20), false, "second ignored")
			eq(d:snapshot().time, t, "run not restarted")
			eq(d:phase(), "running", "still running")
		end,
	},
	{
		name = "start after the run ended is ignored (Replay handles that)",
		run = function()
			local d = ready()
			d:start(10)
			runToEnd(d)
			eq(d:start(50), false, "start refused when over")
			eq(d:phase(), "over", "still over")
			eq(d:replay(60), true, "replay restarts")
			eq(d:phase(), "running", "replay runs")
		end,
	},
	{
		name = "replay is refused while ready",
		run = function()
			local d = ready()
			eq(d:replay(10), false, "replay while ready")
			eq(d:phase(), "ready", "still ready")
		end,
	},
	{
		name = "forged or non-finite times never start the run",
		run = function()
			for _, bad in { "x", true, {}, 0 / 0, math.huge, -math.huge } do
				local d = ready()
				eq(d:start(bad :: any), false, "bad now")
				eq(d:phase(), "ready", "still ready")
			end
		end,
	},
	{
		name = "forged Start payloads are ignored: the contract reads no arguments",
		run = function()
			eq(Remotes.names.start, "Start", "name")
			for _, junk in { { total = 999999 }, { z = 1e9 }, "go", 5, true } do
				eq(Remotes.decodeStart(junk :: any, junk :: any), true, "ignores args")
			end
			-- start() takes only the server clock; a payload cannot be passed through it
			local d = ready()
			d:start(1)
			eq(d:snapshot().total, ready():snapshot().total, "total untouched")
		end,
	},
	{
		name = "rate limit: constants allow a small burst then refill on the injected clock",
		run = function()
			local Steering = require("../src/shared/Steering")
			assert(RunDriver.START_PER_SECOND > 0 and RunDriver.START_PER_SECOND <= 2, "rate")
			assert(RunDriver.START_BURST >= 1 and RunDriver.START_BURST <= 3, "burst")
			local l = Steering.newLimiter(RunDriver.START_PER_SECOND, RunDriver.START_BURST)
			local allowed = 0
			for _ = 1, 1000 do
				if l.allow(50) then
					allowed += 1
				end
			end
			eq(allowed, RunDriver.START_BURST, "burst only")
			eq(l.allow(50 + 10), true, "refilled")
		end,
	},
	{
		name = "a backwards or repeated server clock after an accepted Start never restarts anything",
		run = function()
			local d = ready()
			eq(d:start(1000), true, "first")
			d:tick(DT)
			local t = d:snapshot().time
			for _, now in { 1000, 999, 1000.1, 5000 } do
				eq(d:start(now), false, "refused")
			end
			eq(d:snapshot().time, t, "unchanged")
			eq(RunDriver.START_COOLDOWN > 0, true, "cooldown constant")
		end,
	},
	{
		name = "encodeState carries a validated phase",
		run = function()
			local base = { time = 0, z = 0, x = 0, total = 1, hp = 3, maxHp = 3, best = 1 }
			local function with(phase: any, outcome: string?): Remotes.StatePayload
				local s = table.clone(base) :: any
				s.phase = phase
				s.outcome = outcome
				return Remotes.encodeState(s)
			end
			eq(with("ready", nil).phase, "ready", "ready")
			eq(with("running", nil).phase, "running", "running")
			eq(with("over", "completed").phase, "over", "over")
			eq(with(nil, nil).phase, "running", "derived running")
			eq(with(nil, "defeated").phase, "over", "derived over")
			eq(with("bogus", nil).phase, "running", "invalid replaced")
			eq(with("ready", "completed").phase, "over", "outcome wins")
			eq(ready():snapshot().phase, "ready", "snapshot ready")
		end,
	},
}
