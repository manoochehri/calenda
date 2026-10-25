--!strict
-- Issue #121 (ADR 0006, spec Amendment 4): the parade size is the life bar. An unconverted horde
-- and an unblocked tomato each remove a share of the parade as it stood before the hit (floor of
-- percent of the total, at least Config.minShareLoss); the -10 obstacle stays fixed. The run ends
-- defeated the moment the total reaches zero. There is no separate HP anywhere.
local Config = require("../src/shared/Config")
local CrowdMath = require("../src/shared/CrowdMath")
local DebugLayout = require("../src/shared/DebugLayout")
local Remotes = require("../src/shared/Remotes")
local RunDriver = require("../src/shared/RunDriver")
local RunState = require("../src/shared/RunState")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {expected}, got {actual}`)
end

local function clusters(kinds: { string }): { RunState.ClusterDef }
	local out: { RunState.ClusterDef } = {}
	for i, kind in kinds do
		table.insert(out, { id = `c{i}`, type = kind :: any })
	end
	return out
end

local function run(startingTotal: number, kinds: { string }, tomatoes: { RunState.ObstacleDef }?)
	return RunState.new({
		seed = 1,
		automated = true,
		layout = {
			gatePairs = {},
			clusters = clusters(kinds),
			obstacles = { { id = "o1" } },
			tomatoes = tomatoes,
		},
		startingTotal = startingTotal,
	})
end

local function snapshotText(r: RunState.RunState): string
	return table.concat({ r:total(), tostring(r:outcome()), tostring(r:score()), #r:events() }, "|")
end

return {
	{
		name = "share rule: floor of the percent of the parade, at least minShareLoss",
		run = function()
			eq(
				CrowdMath.shareLoss(0, 10, 1),
				1,
				"empty parade still loses the minimum (clamped later)"
			)
			eq(CrowdMath.shareLoss(5, 10, 1), 1, "5 followers: 10% floors to 0, minimum 1")
			eq(CrowdMath.shareLoss(9, 10, 1), 1, "9 followers: 0.9 floors to 0, minimum 1")
			eq(CrowdMath.shareLoss(10, 10, 1), 1, "10 followers: exactly 1")
			eq(CrowdMath.shareLoss(95, 10, 1), 9, "95 followers: 9.5 floors to 9")
			eq(CrowdMath.shareLoss(1000, 10, 1), 100, "1000 followers: 100")
			eq(CrowdMath.shareLoss(100, 25, 1), 25, "the percent is a parameter, not a constant")
			eq(CrowdMath.shareLoss(10, 1, 3), 3, "the minimum wins over a small share")
		end,
	},
	{
		name = "a horde that reaches the parade removes 10% of it, once",
		run = function()
			local r = run(40, { "small" })
			local first = r:attackCluster("c1")
			assert(first.ok, "first attack is accepted")
			eq(first.before, 40, "before")
			eq(r:total(), 36, "40 - floor(10% of 40)")
			eq(r:outcome(), nil, "still running")
			local before = snapshotText(r)
			local again = r:attackCluster("c1")
			assert(not again.ok, "a second attack on the same horde is rejected")
			eq(snapshotText(r), before, "a repeated hit changes nothing")
		end,
	},
	{
		name = "the share is the same for every horde type and uses the parade size before the hit",
		run = function()
			local r = run(100, { "large" })
			assert(r:attackCluster("c1").ok, "attack")
			eq(r:total(), 90, "large horde: 100 - 10")
			local s = run(100, { "small" })
			assert(s:attackCluster("c1").ok, "attack")
			eq(s:total(), 90, "small horde: 100 - 10")
		end,
	},
	{
		name = "a same-batch pair of hits: the second share is taken from the total after the first",
		run = function()
			local r = run(100, { "small", "small" })
			local results = r:attackClusters({ "c1", "c2" })
			assert(results[1].ok and results[2].ok, "both accepted")
			eq(results[1].before, 100, "first before")
			eq(results[1].after, 90, "first after")
			eq(results[2].before, 90, "second before is the total before its own hit")
			eq(results[2].after, 81, "90 - floor(10% of 90)")
		end,
	},
	{
		name = "minimum of 1: a small parade still loses one follower per hit",
		run = function()
			local r = run(5, { "small" })
			assert(r:attackCluster("c1").ok, "attack")
			eq(r:total(), 4, "5 - max(1, floor(0.5))")
		end,
	},
	{
		name = "losses clamp at zero: the total never goes negative",
		run = function()
			local r = run(1, { "small", "small" })
			local results = r:attackClusters({ "c1", "c2" })
			assert(results[1].ok and results[2].ok, "both accepted")
			eq(r:total(), 0, "clamped at zero")
			eq(results[2].after, 0, "result reports the clamped total")
		end,
	},
	{
		name = "a total at zero defeats the run once; later events are ignored; score is 0",
		run = function()
			local r = run(1, { "small", "small" })
			assert(r:attackCluster("c1").ok, "lethal attack")
			eq(r:total(), 0, "total at zero")
			eq(r:outcome(), "defeated", "defeated at zero")
			eq(r:score(), 0, "defeat score is the crowd total at that moment")
			eq(r:best(), 0, "defeat does not raise the session best")
			local before = snapshotText(r)
			local later = r:attackCluster("c2")
			assert(not later.ok, "an attack after defeat is ignored")
			eq(snapshotText(r), before, "nothing changes after defeat")
			local defeats = 0
			for _, e in r:events() do
				if e.kind == "defeated" then
					defeats += 1
				end
			end
			eq(defeats, 1, "defeat logged once")
		end,
	},
	{
		name = "the obstacle stays a fixed -Config.obstacleLoss",
		run = function()
			local r = run(25, {}, nil)
			assert(r:hitObstacle("o1").ok, "obstacle hit")
			eq(r:total(), 25 - Config.obstacleLoss, "25 - 10")
			local empty = run(Config.obstacleLoss, {})
			assert(empty:hitObstacle("o1").ok, "obstacle hit")
			eq(empty:total(), 0, "total at zero")
			eq(empty:outcome(), "defeated", "an obstacle that empties the parade defeats the run")
		end,
	},
	{
		name = "an unblocked tomato removes tomatoSharePercent of the parade once",
		run = function()
			local r = run(55, {}, { { id = "t1" } })
			assert(r:hitTomato("t1").ok, "tomato hit")
			eq(r:total(), 50, "55 - floor(10% of 55) = 55 - 5")
			local before = snapshotText(r)
			assert(not r:hitTomato("t1").ok, "the same tomato cannot hit twice")
			eq(snapshotText(r), before, "no second loss")
			eq(r:outcome(), nil, "still running")
		end,
	},
	{
		name = "a tomato on a small parade removes the minimum of 1 and can defeat at zero",
		run = function()
			local r = run(1, {}, { { id = "t1" } })
			assert(r:hitTomato("t1").ok, "tomato hit")
			eq(r:total(), 0, "1 - max(1, 0)")
			eq(r:outcome(), "defeated", "defeated at zero")
		end,
	},
	{
		name = "there is no HP: no hp field on RunState, Config, the run snapshot or the State payload",
		run = function()
			local r = run(10, {})
			eq((r :: any).hp, nil, "RunState has no hp")
			eq((Config :: any).hp, nil, "Config has no hp table")
			eq((Config :: any).clusterTypes.small.attackDamage, nil, "no HP-damage key")
			local driver = RunDriver.new({ layout = DebugLayout })
			local snap = driver:snapshot() :: any
			eq(snap.hp, nil, "snapshot has no hp")
			eq(snap.maxHp, nil, "snapshot has no maxHp")
			local payload = Remotes.encodeState({
				time = 0,
				z = 0,
				x = 0,
				total = 10,
				best = 0,
			} :: any) :: any
			eq(payload.hp, nil, "State has no hp")
			eq(payload.maxHp, nil, "State has no maxHp")
		end,
	},
	{
		name = "share percents and the minimum are server config, positive whole numbers",
		run = function()
			local p = Config.attackSharePercent
			assert(
				type(p) == "number" and p >= 1 and p <= 100 and p == math.floor(p),
				"attackSharePercent"
			)
			local t = Config.hazards.tomatoSharePercent
			assert(
				type(t) == "number" and t >= 1 and t <= 100 and t == math.floor(t),
				"tomatoSharePercent"
			)
			local m = Config.minShareLoss
			assert(type(m) == "number" and m >= 1 and m == math.floor(m), "minShareLoss")
		end,
	},
}
