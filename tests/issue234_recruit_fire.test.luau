--!strict
-- Issue #234 (owner rule 2026-10-31): the projectile speed and fire rate reflect how many parade
-- people are recruited. With zero recruits the parade fires ONE projectile at a time: the next shot
-- waits until the current one has resolved (hit, missed, or left the playfield). More recruits means
-- faster projectiles and a higher fire rate. Supersedes the cadence line of #148 and the rate curve
-- of ADR 0004. The table values are provisional and UNVERIFIED for feel; the tests pin the SHAPE
-- (one in flight at zero, non-decreasing, strictly higher at the top), not specific numbers.
local ClusterFeed = require("../src/shared/ClusterFeed")
local Config = require("../src/shared/Config")
local FeedbackMath = require("../src/shared/FeedbackMath")
local Level = require("../src/shared/Level")
local RunDriver = require("../src/shared/RunDriver")
local RunState = require("../src/shared/RunState")
local ShotLook = require("../src/shared/ShotLook")
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

local function sessionFor(layout: Level.Layout): Targeting.Session
	local defs: { RunState.ClusterDef } = {}
	for _, c in layout.clusters do
		table.insert(defs, { id = tostring(c.id), type = c.type :: RunState.ClusterKind })
	end
	local rs = RunState.new({
		seed = 1,
		automated = true,
		layout = { gatePairs = {}, clusters = defs, obstacles = {} },
		now = function()
			return 0
		end,
	})
	return Targeting.new({ layout = layout, runState = rs })
end

-- All shots over `seconds` of 30 Hz server steps at a fixed section count.
local function shotsOver(layout: Level.Layout, seconds: number, sections: number): { any }
	local session = sessionFor(layout)
	local out = {}
	local t = 0.0
	while t <= seconds do
		for _, s in session:advance(t, sections, "right").shots do
			table.insert(out, s)
		end
		t += RunDriver.TICK_DT
	end
	return out
end

local function tiersOrFail(): { any }
	local tiers = (Config.firing :: any).tiers
	assert(type(tiers) == "table" and #tiers >= 2, "Config.firing.tiers is the recruit table")
	return tiers
end

return {
	{
		name = "0 recruits: a miss is not followed by another shot until it has left the playfield",
		run = function()
			local shots = shotsOver(layoutOf({}), 6, 0)
			assert(#shots >= 2, "fires repeatedly")
			for i = 2, #shots do
				assert(shots[i].miss, "all misses")
				local gap = shots[i].time - shots[i - 1].time
				assert(
					gap >= ShotLook.MISS_SECONDS - 1e-6,
					`shot {i} started {gap} s after the previous miss, which flies {ShotLook.MISS_SECONDS} s or more`
				)
			end
		end,
	},
	{
		name = "0 recruits: a hit is not followed by another shot until it has landed",
		run = function()
			local shots = shotsOver(layoutOf({ cluster(1, 40, "large") }), 6, 0)
			local hits = 0
			for i = 2, #shots do
				if not shots[i - 1].miss then
					hits += 1
					local gap = shots[i].time - shots[i - 1].time
					assert(
						gap >= FeedbackMath.MIN_FLIGHT - 1e-6,
						`shot {i} started {gap} s after a hit; the shortest flight is {FeedbackMath.MIN_FLIGHT} s`
					)
				end
			end
			assert(hits >= 1, "the scenario produced a hit followed by another shot")
		end,
	},
	{
		name = "table: rate, speed and max in flight are non-decreasing and strictly higher at the top",
		run = function()
			local tiers = tiersOrFail()
			eq(tiers[1].minRecruits, 0, "first row starts at zero recruits")
			eq(tiers[1].maxInFlight, 1, "zero recruits fire one at a time")
			for i = 2, #tiers do
				assert(tiers[i].minRecruits > tiers[i - 1].minRecruits, `row {i} ascending`)
				assert(tiers[i].shotsPerSecond >= tiers[i - 1].shotsPerSecond, `row {i} rate`)
				assert(tiers[i].speed >= tiers[i - 1].speed, `row {i} speed`)
				assert(tiers[i].maxInFlight >= tiers[i - 1].maxInFlight, `row {i} in flight`)
			end
			local top = tiers[#tiers]
			assert(top.shotsPerSecond > tiers[1].shotsPerSecond, "top rate above zero-recruit rate")
			assert(top.speed > tiers[1].speed, "top speed above zero-recruit speed")
			assert(top.shotsPerSecond <= 30, "one event per 30 Hz tick")
		end,
	},
	{
		name = "table lookup is non-decreasing in recruit count across 0..1000",
		run = function()
			local FireTable = (require :: any)("../src/shared/FireTable")
			local lastRate, lastSpeed = 0, 0
			for recruits = 0, 1000 do
				local rate = FireTable.rate(recruits)
				local speed = FireTable.speed(recruits)
				assert(rate >= lastRate and speed >= lastSpeed, `recruits {recruits}`)
				lastRate, lastSpeed = rate, speed
			end
			assert(FireTable.rate(1000) > FireTable.rate(0), "rate rises")
			assert(FireTable.speed(1000) > FireTable.speed(0), "speed rises")
		end,
	},
	{
		name = "more recruits fire more shots over the same time (misses, 10 s)",
		run = function()
			local few = #shotsOver(layoutOf({}), 10, 0)
			local many = #shotsOver(layoutOf({}), 10, 10) -- 500 recruits
			assert(many > few * 2, `500 recruits fired {many}, 0 recruits fired {few}`)
		end,
	},
	{
		name = "preserved: gift share stays 1 in 100 and a dancer section is still required",
		run = function()
			eq(Config.giftEveryNthShot, 100, "giftEveryNthShot")
			local gifts = 0
			for n = 1, 10000 do
				if Targeting.shotKind(n, 3) == "gift" then
					gifts += 1
				end
			end
			eq(gifts, 100, "gifts in 10000 shots")
			eq(Targeting.shotKind(100, 0), "note", "no dancer section, no gift")
		end,
	},
	{
		name = "preserved: each shot is one hit and the nearest in-lane target wins",
		run = function()
			local shots =
				shotsOver(layoutOf({ cluster(1, 50, "small"), cluster(2, 30, "small") }), 30, 0)
			eq(shots[1].targetId, 2, "nearest target first")
			local lastHits = 0
			for _, s in shots do
				if s.targetId == 2 then
					eq(s.hits, lastHits + 1, "hit strength is one per shot")
					lastHits = s.hits
				end
			end
			assert(lastHits >= 1, "target 2 was hit")
			local other = { id = 1, x = 0, z = 40, full = false, lane = "left" :: any }
			eq(
				Targeting.selectTarget({ other }, 0, "right"),
				nil,
				"lane rule: no fallback to another lane"
			)
		end,
	},
	{
		name = "a crowd with many recruits overlaps shots; the in-flight limit is the table's, not a constant",
		run = function()
			local shots = shotsOver(layoutOf({}), 6, 10) -- 500 recruits: top row
			local overlapped = false
			for i = 2, #shots do
				if shots[i].time - shots[i - 1].time < ShotLook.MISS_SECONDS - 1e-6 then
					overlapped = true
				end
			end
			assert(overlapped, "the top row has several projectiles in flight")
		end,
	},
	{
		name = "recruits passed to advance decide the tier, not the section count",
		run = function()
			local session = sessionFor(layoutOf({}))
			local n = 0
			local t = 0.0
			while t <= 6 do
				n += #session:advance(t, 10, "right", nil, nil, 0).shots
				t += RunDriver.TICK_DT
			end
			local one = #shotsOver(layoutOf({}), 6, 0)
			eq(n, one, "recruits = 0 behaves as the zero-recruit row even if sections say 10")
		end,
	},
	{
		name = "flight time at the reference speed is unchanged; slower speed is slower at every range",
		run = function()
			for _, d in { 0, 5, 20, 40, 60, 100 } do
				eq(
					FeedbackMath.flightSeconds(d, FeedbackMath.FLIGHT_SPEED),
					FeedbackMath.flightSeconds(d),
					`d {d}`
				)
				assert(
					FeedbackMath.flightSeconds(d, 45) >= FeedbackMath.flightSeconds(d, 67.5) - 1e-9,
					`slower speed is not faster at {d}`
				)
				assert(
					FeedbackMath.flightSeconds(d, 100) <= FeedbackMath.flightSeconds(d, 67.5) + 1e-9,
					`faster speed is not slower at {d}`
				)
			end
			eq(ShotLook.missSeconds(nil), ShotLook.MISS_SECONDS, "reference miss flight")
			assert(ShotLook.missSeconds(45) > ShotLook.MISS_SECONDS, "slower miss flies longer")
		end,
	},
	{
		name = "the server speed rides the shot event, validated; absent or hostile values are dropped",
		run = function()
			local hit =
				ClusterFeed.encode({ targetId = 3, hits = 1, kind = "note", speed = 45 } :: any)
			assert(hit ~= nil, "encoded")
			eq((hit :: any).v, 45, "hit v")
			eq((ClusterFeed.decode(hit) :: any).speed, 45, "hit round trip")
			local miss =
				ClusterFeed.encode({ miss = true, number = 2, kind = "note", speed = 52 } :: any)
			eq((ClusterFeed.decodeMiss(miss) :: any).speed, 52, "miss round trip")
			eq(
				(ClusterFeed.decode({ kind = "cluster", id = 1, hits = 1, shot = "note" }) :: any).speed,
				nil,
				"absent"
			)
			for _, bad in { 0, -5, 1e9, "fast", 0 / 0 } do
				local p = { kind = "cluster", id = 1, hits = 1, shot = "note", v = bad }
				eq((ClusterFeed.decode(p) :: any).speed, nil, `bad speed {tostring(bad)}`)
			end
		end,
	},
}
