--!strict
-- Issue #162 / spec child task 3: the server-to-client wire contract. State carries runId, levelId,
-- simTime, zVelocity, stage, encounter, boostExpiry and roster; a client recovers from the latest
-- state, never from events; consumption is keyed once by (runId, levelId, encounterId). Contract
-- only: no boss, unlock or roster content exists yet, so those fields are exercised as values.
local Config = require("../src/shared/Config")
local Remotes = require("../src/shared/Remotes")
local RunDriver = require("../src/shared/RunDriver")

local function eq(actual: any, expected: any, label: string)
	assert(actual == expected, `{label}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function snap(over: { [string]: any }?): Remotes.Snapshot
	local s: any = {
		time = 12.5,
		z = 90,
		x = 1,
		total = 40,
		best = 40,
		phase = "running",
		level = 1,
		levelName = "Calle",
		runId = 1,
		levelId = "level1",
		zVelocity = Config.speed,
		stage = "traveling",
	}
	for k, v in over or {} do
		s[k] = v
	end
	return s
end

local function encode(over: { [string]: any }?): any
	return Remotes.encodeState(snap(over))
end

local function enc(kind: string, id: string): any
	return { id = id, kind = kind, lane = "center", progress = 0.5, remaining = 20, active = true }
end

local function req(name: string): any
	local f = (Remotes :: any)[name]
	assert(f ~= nil, `Remotes.{name} does not exist`)
	return f
end

local function newReceiver(): any
	return req("newReceiver")()
end

return {
	{
		name = "encode/decode round trip carries version, runId, levelId, simTime, zVelocity, stage",
		run = function()
			local p = encode({ stage = "mini-boss-combat", zVelocity = 0, time = 33.333 })
			local d = req("decodeState")(p)
			assert(d ~= nil, "decodes")
			eq(d.v, Remotes.VERSION, "version")
			eq(d.runId, 1, "runId")
			eq(d.levelId, "level1", "levelId")
			eq(d.simTime, 33.33, "simTime rounded like t")
			eq(d.zVelocity, 0, "zVelocity")
			eq(d.stage, "mini-boss-combat", "stage")
			eq(d.t, 33.33, "t unchanged")
			eq(d.total, 40, "total passes through untouched")
		end,
	},
	{
		name = "encounter kinds recruit, unlock and boss round trip; unknown kinds and ids are refused",
		run = function()
			for kind, id in { pickup = "p3", recruit = "r1", unlock = "u2", boss = "b1" } do
				local p = encode({ encounter = enc(kind, id) })
				eq(p.encounter ~= nil and p.encounter.kind, kind, `{kind} kept`)
				eq(req("decodeState")(p) ~= nil, true, `{kind} decodes`)
			end
			for _, bad in
				{
					enc("powerup", "p1"),
					enc("recruit", "p1"), -- id prefix must match the kind
					enc("boss", "b"),
					enc("unlock", "u1;drop"),
					enc("pickup", string.rep("p", 40)),
				}
			do
				eq(encode({ encounter = bad }).encounter, nil, "malformed encounter dropped")
			end
		end,
	},
	{
		name = "stage: cleared is valid; ready and unknown strings are not; invalid encodes as traveling",
		run = function()
			eq(Remotes.isStage("cleared"), true, "cleared")
			eq(Remotes.isStage("ready"), false, "ready")
			eq(Remotes.isStage("boss"), false, "unknown")
			eq(Remotes.isStage(nil), false, "nil")
			eq(encode({ stage = "ready" }).stage, "traveling", "fallback")
		end,
	},
	{
		name = "runId and levelId: invalid values encode to safe defaults; decode refuses them",
		run = function()
			eq(encode({ runId = -3 }).runId, 1, "negative runId")
			eq(encode({ runId = 0 / 0 }).runId, 1, "nan runId")
			eq(encode({ levelId = "x y" }).levelId, "level1", "bad levelId")
			local d = req("decodeState")
			for _, patch in
				{
					{ runId = 0 },
					{ runId = 1.5 },
					{ runId = "1" },
					{ levelId = "" },
					{ levelId = "level" },
					{ levelId = "Level1" },
					{ levelId = 7 },
					{ simTime = -1 },
					{ simTime = 0 / 0 },
					{ simTime = math.huge },
					{ zVelocity = -1 },
					{ zVelocity = 1e9 },
					{ zVelocity = "fast" },
					{ stage = "ready" },
					{ phase = "paused" },
					{ v = Remotes.VERSION + 1 },
					{ total = -1 },
					{ total = 0 / 0 },
				}
			do
				local p = encode()
				for k, v in patch do
					p[k] = v
				end
				eq(d(p), nil, "forged payload refused")
			end
			local noVersion = encode()
			noVersion.v = nil
			eq(d(noVersion), nil, "missing version refused")
			eq(d("x"), nil, "non-table")
			eq(d(nil), nil, "nil")
		end,
	},
	{
		name = "boostExpiry: finite non-negative passes; absent stays absent; forged values are refused",
		run = function()
			eq(encode().boostExpiry, nil, "absent")
			eq(encode({ boostExpiry = 20.456 }).boostExpiry, 20.46, "rounded")
			eq(encode({ boostExpiry = 0 / 0 }).boostExpiry, nil, "nan dropped at encode")
			eq(encode({ boostExpiry = -1 }).boostExpiry, nil, "negative dropped at encode")
			local d = req("decodeState")
			local p = encode({ boostExpiry = 20 })
			eq(d(p).boostExpiry, 20, "round trip")
			p.boostExpiry = math.huge
			eq(d(p), nil, "inf refused")
			p.boostExpiry = "soon"
			eq(d(p), nil, "string refused")
		end,
	},
	{
		name = "roster: ordered distinct opaque ids; bad shape, duplicates, overflow and unknown ids refused",
		run = function()
			eq(#encode().roster, 0, "empty by default")
			local ok = encode({ roster = { "trumpet", "china" } })
			eq(ok.roster[1], "trumpet", "order kept")
			eq(ok.roster[2], "china", "order kept")
			local d = req("decodeState")
			eq(d(ok) ~= nil, true, "valid roster decodes")
			-- encode drops an invalid roster entirely (never a partial list)
			eq(#encode({ roster = { "trumpet", "trumpet" } }).roster, 0, "duplicate")
			eq(#encode({ roster = { "Trumpet!" } }).roster, 0, "shape")
			eq(#encode({ roster = { 5 } }).roster, 0, "type")
			local nine = {}
			for i = 1, Remotes.ROSTER_MAX + 1 do
				table.insert(nine, `t{string.char(96 + i)}`)
			end
			eq(#encode({ roster = nine }).roster, 0, "over the cap")
			for _, bad in { { "a", "a" }, { "UP" }, { "" }, { 1 }, "trumpet", { x = "trumpet" } } do
				local p = encode()
				p.roster = bad
				eq(d(p), nil, "forged roster refused")
			end
			-- Against an active roster, an id outside it is refused.
			local allowed = { trumpet = true, china = true }
			eq(
				d(encode({ roster = { "trumpet" } }), allowed) ~= nil,
				true,
				"member of active roster"
			)
			eq(d(encode({ roster = { "tuba" } }), allowed), nil, "not in the active roster")
		end,
	},
	{
		name = "decodeState copies known fields only: forged extras never pass through",
		run = function()
			local p = encode()
			p.hp = 0
			p.amount = 99
			p.grant = "trumpet"
			local d = req("decodeState")(p)
			assert(d ~= nil, "decodes")
			eq((d :: any).hp, nil, "hp")
			eq((d :: any).amount, nil, "amount")
			eq((d :: any).grant, nil, "grant")
		end,
	},
	{
		name = "receiver: a late joiner recovers stage, encounter, boost and roster from ONE state",
		run = function()
			local r = newReceiver()
			local late = encode({
				runId = 4,
				levelId = "level2",
				level = 2,
				stage = "final-boss-combat",
				zVelocity = 0,
				time = 61,
				encounter = enc("boss", "b3"),
				boostExpiry = 66.5,
				roster = { "trumpet" },
			})
			local s = r.accept(late)
			assert(s ~= nil, "first state accepted")
			eq(s.stage, "final-boss-combat", "stage from state")
			eq(s.encounter ~= nil and s.encounter.id, "b3", "encounter from state")
			eq(s.boostExpiry, 66.5, "boost from state")
			eq(s.roster[1], "trumpet", "roster from state")
			eq(r.runId(), 4, "tracks run")
		end,
	},
	{
		name = "receiver: dropped events lose nothing, the next state is the whole truth",
		run = function()
			local r = newReceiver()
			assert(r.accept(encode({ time = 10, stage = "traveling" })), "a")
			-- the mini-boss entry event and several states were all dropped
			local s = r.accept(encode({ time = 19, stage = "mini-boss-combat", zVelocity = 0 }))
			assert(s ~= nil, "later state accepted")
			eq(s.stage, "mini-boss-combat", "stage recovered")
			-- and the resume event was dropped too
			local s2 = r.accept(encode({ time = 27, stage = "traveling" }))
			assert(s2 ~= nil, "resume state accepted")
			eq(s2.stage, "traveling", "resume recovered")
		end,
	},
	{
		name = "receiver: replay changes runId; a stale pre-replay state is refused, the new run accepted",
		run = function()
			local r = newReceiver()
			assert(r.accept(encode({ runId = 1, time = 50 })), "run 1")
			local fresh = r.accept(encode({ runId = 2, time = 0.1, z = 0 }))
			assert(fresh ~= nil, "a new run restarts simTime and is accepted")
			eq(r.runId(), 2, "now run 2")
			eq(r.accept(encode({ runId = 1, time = 51 })), nil, "replayed old-run state refused")
			eq(r.runId(), 2, "still run 2")
		end,
	},
	{
		name = "receiver: replayed or out-of-order states within a run and level are refused",
		run = function()
			local r = newReceiver()
			assert(r.accept(encode({ time = 10 })), "a")
			assert(r.accept(encode({ time = 10.5 })), "b")
			eq(r.accept(encode({ time = 10 })), nil, "older simTime refused")
			assert(r.accept(encode({ time = 10.5 })), "an identical resend is idempotent")
			-- a level change inside the run restarts simTime
			assert(r.accept(encode({ time = 0.2, levelId = "level2", level = 2 })), "level 2")
			eq(
				r.accept(encode({ time = 30, levelId = "level1", level = 1 })),
				nil,
				"back to level 1"
			)
		end,
	},
	{
		name = "receiver: malformed states are refused and do not disturb the last good state",
		run = function()
			local r = newReceiver()
			assert(r.accept(encode({ time = 10 })), "good")
			local bad = encode({ time = 11 })
			bad.stage = "ready"
			eq(r.accept(bad), nil, "bad stage")
			eq(r.accept("junk"), nil, "junk")
			assert(r.accept(encode({ time = 11 })), "good state after junk still accepted")
		end,
	},
	{
		name = "once-only: consumption is keyed by (runId, levelId, encounterId) and applies once",
		run = function()
			local once = req("newOnceSet")()
			eq(once.claim(1, "level1", "p1"), true, "first")
			eq(once.claim(1, "level1", "p1"), false, "duplicate")
			eq(once.claim(1, "level1", "p2"), true, "other encounter")
			eq(once.claim(1, "level2", "p1"), true, "same id in another level")
			eq(once.claim(2, "level1", "p1"), true, "same id in a new run")
			eq(once.claim(2, "level1", "p1"), false, "duplicate in the new run")
			eq(once.claim(0, "level1", "p9"), false, "invalid run id")
			eq(once.claim(1, "bad id", "p9"), false, "invalid level id")
			eq(once.claim(1, "level1", "zz"), false, "invalid encounter id")
			eq(req("encounterKey")(2, "level1", "p1"), "2|level1|p1", "key shape")
			eq(req("encounterKey")(0, "level1", "p1"), nil, "no key for a forged run")
		end,
	},
	{
		name = "driver: snapshot carries runId, levelId, simTime and zVelocity; replay bumps runId",
		run = function()
			local layout: any = {
				name = "wire",
				seed = 3,
				streetLength = 480,
				plazaStart = 400,
				halfWidth = 20,
				leadLimit = 15,
				maxTotal = 1000,
				intendedRecruitTotal = 0,
				gates = {},
				obstacles = {},
				clusters = {},
			}
			local doomed = false
			local d = RunDriver.new({
				layout = layout,
				automated = true,
				runSeed = 5,
				hooks = {
					endCheck = function(): boolean
						return doomed
					end,
				},
			})
			local s0: any = d:snapshot()
			eq(s0.runId, 1, "first run")
			eq(s0.levelId, "level1", "level id")
			d:tick(RunDriver.TICK_DT)
			local s1: any = d:snapshot()
			eq(s1.time > 0, true, "sim clock runs")
			eq(s1.zVelocity, Config.speed, "travelling speed")
			local p = Remotes.encodeState(s1)
			eq(p.simTime, p.t, "simTime mirrors the combat clock")
			doomed = true
			d:tick(RunDriver.TICK_DT)
			eq(d:outcome(), "defeated", "ended")
			eq((d:snapshot() :: any).zVelocity, 0, "no velocity after the end")
			doomed = false
			assert(d:replay(100), "replay accepted")
			eq((d:snapshot() :: any).runId, 2, "replay is a new run")
			eq((d:snapshot() :: any).levelId, "level1", "back to level 1")
			-- the server's own snapshots always pass the client decode
			assert(
				req("decodeState")(Remotes.encodeState(d:snapshot())) ~= nil,
				"server state decodes"
			)
		end,
	},
	{
		name = "driver: a held checkpoint has zero zVelocity and a non-traveling stage",
		run = function()
			local layout: any = {
				name = "wirehold",
				seed = 3,
				streetLength = 480,
				plazaStart = 400,
				halfWidth = 20,
				leadLimit = 15,
				maxTotal = 1000,
				intendedRecruitTotal = 0,
				gates = {},
				obstacles = {},
				clusters = {},
				checkpoints = { { id = 1, z = 72.3, kind = "mini-boss" } },
			}
			local d = RunDriver.new({ layout = layout, automated = true, runSeed = 5 })
			for _ = 1, 4000 do
				d:tick(RunDriver.TICK_DT)
				if (d:snapshot() :: any).stage ~= "traveling" then
					break
				end
			end
			local s: any = d:snapshot()
			eq(s.stage, "mini-boss-combat", "held")
			eq(s.zVelocity, 0, "stopped")
			local p = Remotes.encodeState(s)
			eq(p.zVelocity, 0, "wire zero")
		end,
	},
	{
		name = "canonical keys: leading zeros are refused so one encounter has exactly one key",
		run = function()
			local once = req("newOnceSet")()
			eq(once.claim(1, "level1", "p1"), true, "canonical")
			eq(once.claim(1, "level1", "p01"), false, "p01 is not p1")
			eq(once.claim(1, "level01", "p1"), false, "level01 is not level1")
			eq(once.claim(1, "level1", "p0"), false, "zero id")
			eq(req("encounterKey")(1, "level0", "p1"), nil, "level0")
			eq(encode({ encounter = enc("pickup", "p01") }).encounter, nil, "p01 dropped")
			eq(encode({ encounter = enc("boss", "b007") }).encounter, nil, "b007 dropped")
			eq(encode({ levelId = "level01" }).levelId, "level1", "level01 falls back")
			local p = encode()
			p.levelId = "level01"
			eq(req("decodeState")(p), nil, "decode refuses level01")
		end,
	},
	{
		name = "bounds: 1e308 and out-of-range values are refused, and cannot lock a receiver out",
		run = function()
			local d = req("decodeState")
			for _, patch in
				{
					{ simTime = 1e308, t = 1e308 },
					{ simTime = Remotes.SIM_TIME_MAX + 1, t = Remotes.SIM_TIME_MAX + 1 },
					{ total = Remotes.TOTAL_MAX + 1 },
					{ best = 1e308 },
					{ score = 1e308 },
					{ z = 1e308 },
					{ z = -1 },
					{ x = 1e6 },
					{ holdZ = 1e308 },
					{ boostExpiry = 1e308 },
				}
			do
				local p = encode()
				for k, v in patch do
					p[k] = v
				end
				eq(d(p), nil, "out of range refused")
			end
			local r = newReceiver()
			assert(r.accept(encode({ time = 10 })), "good")
			local forged = encode({ time = 11 })
			forged.simTime, forged.t = 1e308, 1e308
			eq(r.accept(forged), nil, "forged refused")
			assert(r.accept(encode({ time = 12 })), "later legitimate state still accepted")
		end,
	},
	{
		name = "t must equal simTime",
		run = function()
			local p = encode()
			p.t = p.simTime + 1
			eq(req("decodeState")(p), nil, "t differs")
		end,
	},
	{
		name = "receiver reset: a new session's first state (runId back at 1) is accepted",
		run = function()
			local r = newReceiver()
			assert(r.accept(encode({ runId = 7, time = 90 })), "old session")
			eq(r.accept(encode({ runId = 1, time = 0.1 })), nil, "refused without a reset")
			r.reset()
			eq(r.runId(), nil, "forgotten")
			assert(r.accept(encode({ runId = 1, time = 0.1 })), "accepted after reset")
			eq(r.runId(), 1, "tracks the new session")
		end,
	},
}
