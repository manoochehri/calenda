--!strict
-- Issue #93 (ADR 0006): a gift is two meter hits on its one cluster (credit once, no overflow); a
-- note or heart is still one hit. Rey is a bonus target that only takes shots no cluster can, pays
-- +5 once per run, and never moves a cluster meter. The gift arc is a pure look with its own
-- tunables. Every number is read from Config so these tests fail if a tunable is hard-coded.
local ClusterFeed = require("../src/shared/ClusterFeed")
local Config = require("../src/shared/Config")
local DebugLayout = require("../src/shared/DebugLayout")
local GiftVisual = require("../src/shared/GiftVisual")
local Level = require("../src/shared/Level")
local ReyFormation = require("../src/shared/ReyFormation")
local RunHooks = require("../src/shared/RunHooks")
local RunState = require("../src/shared/RunState")
local Targeting = require("../src/shared/Targeting")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function near(actual: number, expected: number, name: string)
	assert(math.abs(actual - expected) < 1e-6, `{name}: expected {expected}, got {actual}`)
end

local function copy(t: any): any
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in t do
		out[k] = copy(v)
	end
	return out
end

local function cluster(id: number, x: number, z: number, kind: string, spawnTime: number?)
	return {
		id = id,
		wave = 1,
		type = kind,
		spawnTime = spawnTime or 0,
		spawn = { x = x, z = z },
		path = {},
	}
end

local function layoutOf(clusters: { any }): Level.Layout
	return {
		name = "t",
		seed = 0,
		streetLength = 1600,
		plazaStart = 1440,
		halfWidth = 20,
		maxTotal = 1000,
		intendedRecruitTotal = 0,
		gates = {},
		obstacles = {},
		clusters = clusters,
	}
end

local function runStateFor(layout: Level.Layout): RunState.RunState
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

-- Every shot from `from` to `to` in steps of dt (hits and misses), with one fixed steer.
local function driveAll(
	session: any,
	from: number,
	to: number,
	dt: number,
	sections: number,
	steer: string?
)
	local shots: { any } = {}
	local t = from
	while t <= to + 1e-9 do
		for _, s in session:advance(t, sections, (steer or "center") :: any).shots do
			table.insert(shots, s)
		end
		t += dt
	end
	return shots
end

return {
	{
		name = "tunables: giftMeterHits 2, Rey bonus 5, rey and gift arc numbers live in Config and validate",
		run = function()
			eq(Config.giftMeterHits, 2, "gift meter hits")
			eq(Config.rey.bonus, 5, "Rey bonus")
			eq(Config.rey.aheadStuds <= Config.firing.range, true, "Rey is inside firing range")
			eq(Config.rey.roadInset, 6, "road inset matches the client's Rey lane")
			eq(Config.giftArc.loops, 1, "one loop")
			local ok, why = Config.validate(copy(Config))
			eq(ok, true, `defaults validate: {tostring(why)}`)
			for _, bad in
				{
					{ "giftMeterHits", 0 },
					{ "giftMeterHits", 1.5 },
				}
			do
				local c = copy(Config)
				c[bad[1]] = bad[2]
				eq(Config.validate(c), false, `rejects {bad[1]}={bad[2]}`)
			end
			local c1 = copy(Config)
			c1.rey.bonus = 0
			eq(Config.validate(c1), false, "rejects Rey bonus 0")
			local c2 = copy(Config)
			c2.rey.aheadStuds = Config.firing.range + 1
			eq(Config.validate(c2), false, "rejects Rey beyond firing range")
			local c3 = copy(Config)
			c3.giftArc.slowdown = 0
			eq(Config.validate(c3), false, "rejects a non-positive slowdown")
		end,
	},
	{
		name = "a gift is two meter hits: a large cluster fills in four gifts and pays its reward once",
		run = function()
			local layout = layoutOf({ cluster(1, 16, 30, "large") })
			local cfg = copy(Config)
			cfg.giftEveryNthShot = 1 -- every shot a gift once a dancer section exists (3 sections)
			local rs = runStateFor(layout)
			local before = rs:total()
			local session = Targeting.new({ layout = layout, runState = rs, config = cfg })
			local hits: { any } = {}
			local credits = 0
			for _, s in driveAll(session, 0, 0.6, 1 / 60, 3) do
				if s.targetId ~= nil then -- after A fills, later shots are Rey fallbacks, not gifts
					table.insert(hits, s)
					if s.credit ~= nil then
						credits += 1
					end
				end
			end
			eq(#hits, 4, "four gift shots fill eight hits")
			for i, s in hits do
				eq(s.kind, "gift", `shot {i} is a gift`)
				eq(s.hits, 2 * i, `meter after gift {i}`)
			end
			eq(hits[4].filled, true, "the fourth gift fills")
			eq(credits, 1, "credited once")
			eq(rs:total() - before, Config.clusterTypes.large.reward, "reward paid once")
		end,
	},
	{
		name = "no overflow: the second hit of a filling gift never reaches the next cluster",
		run = function()
			-- A is nearer (z 30) and needs 3 hits; B (z 35) is the next target.
			local layout = layoutOf({ cluster(1, 16, 30, "small"), cluster(2, -16, 35, "small") })
			local cfg = copy(Config)
			cfg.giftEveryNthShot = 1
			local rs = runStateFor(layout)
			local session = Targeting.new({ layout = layout, runState = rs, config = cfg })
			-- Two gift shots at t = 0 and 1/9 s (rate 9 with three sections), both still aimed at A.
			local first = session:advance(0, 3, "center")
			local second = session:advance(1 / 9, 3, "center")
			local all = {}
			for _, s in first.shots do
				table.insert(all, s)
			end
			for _, s in second.shots do
				table.insert(all, s)
			end
			eq(#all, 2, "two shots")
			eq(all[1].targetId, 1, "first gift at A")
			eq(all[2].targetId, 1, "second gift at A")
			local aHits, aNeed = session:meter(1)
			eq(aHits, 3, "A filled by its own two gift hits, capped at 3")
			eq(aNeed, 3, "A needs 3")
			eq(all[2].credit ~= nil, true, "the filling gift credits A")
			local bHits = session:meter(2)
			eq(bHits, 0, "B untouched: no overflow")
			local third = session:advance(2 / 9, 3, "center")
			eq(third.shots[1].targetId, 2, "the next shot goes to B")
		end,
	},
	{
		name = "notes and hearts stay one hit: a note moves a large cluster by exactly one",
		run = function()
			local layout = layoutOf({ cluster(1, 16, 30, "large") })
			local rs = runStateFor(layout)
			local session = Targeting.new({ layout = layout, runState = rs, config = Config })
			local first = session:advance(0, 0, "center")
			eq(first.shots[1].kind, "note", "no dancers: a note")
			eq(first.shots[1].hits, 1, "one hit")
		end,
	},
	{
		name = "Rey is a bonus target: with no cluster in range, every shot is a Rey hit and +5 is paid once",
		run = function()
			-- The only cluster has not spawned, so no cluster is eligible and Rey takes the shots.
			local layout = layoutOf({ cluster(1, 16, 30, "large", 100) })
			local rs = runStateFor(layout)
			local before = rs:total()
			local session = Targeting.new({ layout = layout, runState = rs, config = Config })
			local shots = driveAll(session, 0, 2, 1 / 30, 0, "right")
			local reyHits, credits = 0, 0
			for _, s in shots do
				eq(s.miss, false, "a Rey shot is not a miss")
				eq(s.targetId, nil, "a Rey shot has no cluster id")
				eq(s.rey, true, "flagged as a Rey hit")
				reyHits += 1
				if s.credit ~= nil then
					credits += 1
				end
			end
			assert(reyHits > 0, "Rey took shots")
			eq(credits, 1, "Rey pays once in the run")
			eq(rs:total() - before, Config.rey.bonus, "+5 followers")
			local hits = session:meter(1)
			eq(hits, 0, "a Rey shot never moves a cluster meter")
			eq(Config.rey.bonus > 0, true, "bonus is positive")
		end,
	},
	{
		name = "a cluster in range is preferred over Rey: no Rey shot while a cluster is eligible",
		run = function()
			local layout = layoutOf({ cluster(1, 16, 30, "large") })
			local rs = runStateFor(layout)
			local session = Targeting.new({ layout = layout, runState = rs, config = Config })
			for _, s in driveAll(session, 0, 0.5, 1 / 30, 0) do
				eq(s.rey == true, false, "no Rey shot")
				eq(s.targetId, 1, "every shot at the cluster")
			end
		end,
	},
	{
		name = "Rey's +5 is per run: a reset run pays it again, and the fire schedule is unchanged",
		run = function()
			local layout = layoutOf({ cluster(1, 16, 30, "large", 100) })
			local rs = runStateFor(layout)
			local before = rs:total()
			local session = Targeting.new({ layout = layout, runState = rs, config = Config })
			local shots = session:advance(1, 0, "right").shots
			eq(#shots, 7, "rate 6 over one second: shots at 0 .. 1 inclusive")
			local later = session:advance(3, 0, "right").shots
			eq(#later > 0, true, "more Rey shots later in the run")
			for _, s in later do
				eq(s.credit, nil, "no second award in the same run")
			end
			eq(rs:total() - before, Config.rey.bonus, "+5 in total so far")
			rs:reset()
			local again = Targeting.new({ layout = layout, runState = rs, config = Config })
			local hit = again:advance(0, 0, "right").shots[1]
			eq(hit.credit ~= nil, true, "a new run pays Rey again")
			eq(rs:total() - before, Config.rey.bonus, "+5 after the reset")
		end,
	},
	{
		name = "RunHooks emits a Rey payload per Rey shot, flagged bonus only on the first",
		run = function()
			local layout = layoutOf({ cluster(1, 16, 30, "large", 100) })
			local rs = runStateFor(layout)
			local hooks = RunHooks.new(layout, Config)
			local emitted: { any } = {}
			local function ctx(t0: number, t1: number)
				return {
					t0 = t0,
					t1 = t1,
					z0 = 0,
					z1 = 0,
					x = 16, -- steering right: the lane Rey is drawn in for seed 0
					state = rs,
					emit = function(e: any)
						table.insert(emitted, e)
					end,
					passedClusters = {},
				}
			end
			hooks.shots(ctx(0, 1 / 30))
			hooks.shots(ctx(1 / 30, 2 / 30))
			eq(#emitted >= 1, true, "a Rey shot was emitted")
			eq(emitted[1].kind, "rey", "payload kind rey")
			eq(emitted[1].bonus, true, "first Rey shot carries the bonus")
			for i = 2, #emitted do
				eq(emitted[i].kind, "rey", `payload {i} kind`)
				eq(emitted[i].bonus, false, `payload {i} pays nothing`)
			end
		end,
	},
	{
		name = "Rey stands ahead of the lead, inside range, in the outer lane (so shots can reach him)",
		run = function()
			local pose = ReyFormation.pose(0, 50, 1, DebugLayout.halfWidth - Config.rey.roadInset)
			near(pose.z, 50 + Config.rey.aheadStuds, "ahead of the lead by aheadStuds")
			assert(pose.z - 50 > 0 and pose.z - 50 <= Config.firing.range, "in range")
		end,
	},
	{
		name = "ClusterFeed carries a Rey shot: validated both ways, never a cluster id",
		run = function()
			local payload = ClusterFeed.encode({
				targetId = nil,
				hits = 0,
				kind = "gift",
				miss = false,
				rey = true,
				number = 9,
				credit = { ok = true },
			} :: any)
			assert(payload ~= nil, "encodes")
			eq(payload.kind, "rey", "kind")
			eq(payload.shot, "gift", "variant")
			eq(payload.n, 9, "shot number")
			eq(payload.bonus, true, "bonus when credited")
			local decoded = ClusterFeed.decodeRey(payload)
			assert(decoded ~= nil, "decodes")
			eq(decoded.n, 9, "decoded n")
			eq(decoded.bonus, true, "decoded bonus")
			eq(
				ClusterFeed.decodeRey({ kind = "rey", shot = "note", n = 0, bonus = false }),
				nil,
				"n must be >= 1"
			)
			eq(
				ClusterFeed.decodeRey({ kind = "rey", shot = "bad", n = 1, bonus = false }),
				nil,
				"bad shot"
			)
			eq(
				ClusterFeed.decodeRey({ kind = "rey", shot = "note", n = 1, bonus = "yes" }),
				nil,
				"bonus must be boolean"
			)
			eq(
				ClusterFeed.decodeRey({ kind = "cluster", id = 1, hits = 1, shot = "note" }),
				nil,
				"not a rey payload"
			)
		end,
	},
	{
		name = "gift arc: starts and ends on the street, peaks at giftArc.height, loops and stays bounded",
		run = function()
			local a = GiftVisual.arc(0)
			near(a.dy, 0, "lift at launch")
			near(a.dx, 0, "no sway at launch")
			local b = GiftVisual.arc(1)
			near(b.dy, 0, "lift at landing")
			near(b.dx, 0, "no sway at landing")
			near(GiftVisual.arc(0.5).dy, Config.giftArc.height, "apex is giftArc.height")
			local peakSway = 0
			for i = 0, 100 do
				local p = GiftVisual.arc(i / 100)
				assert(
					p.dy >= -1e-9 and p.dy <= Config.giftArc.height + 1e-9,
					"lift stays within the apex"
				)
				peakSway = math.max(peakSway, math.abs(p.dx))
			end
			assert(peakSway <= Config.giftArc.loopRadius + 1e-9, "sway bounded by loopRadius")
			assert(peakSway > Config.giftArc.loopRadius * 0.99, "the loop reaches its radius")
		end,
	},
	{
		name = "gift flights are slower than notes: flightSeconds scales by giftArc.slowdown",
		run = function()
			near(GiftVisual.flightSeconds(0.5), 0.5 * Config.giftArc.slowdown, "scaled")
			assert(Config.giftArc.slowdown > 1, "slower than a note")
		end,
	},
}
