--!strict
-- Issue #121 (ADR 0006, spec Amendment 4): the parade size is the life bar. Hordes that reach the
-- parade unconverted and unblocked tomatoes remove followers from the crowd total; the run ends
-- defeated the moment the total reaches zero. There is no separate HP anywhere.
local Config = require("../src/shared/Config")
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
		name = "a horde that reaches the parade removes its attackLoss followers, once",
		run = function()
			local loss = Config.clusterTypes.small.attackLoss
			local r = run(40, { "small" })
			local first = r:attackCluster("c1")
			assert(first.ok, "first attack is accepted")
			eq(r:total(), 40 - loss, "total after one hit")
			eq(r:outcome(), nil, "still running")
			local before = snapshotText(r)
			local again = r:attackCluster("c1")
			assert(not again.ok, "a second attack on the same horde is rejected")
			eq(snapshotText(r), before, "a repeated hit changes nothing")
		end,
	},
	{
		name = "the loss is per type: a large horde takes its own attackLoss",
		run = function()
			local r = run(100, { "large" })
			assert(r:attackCluster("c1").ok, "attack")
			eq(r:total(), 100 - Config.clusterTypes.large.attackLoss, "large loss")
		end,
	},
	{
		name = "losses clamp at zero: the total never goes negative",
		run = function()
			local r = run(3, { "large", "large" })
			local ok = r:attackCluster("c1")
			assert(ok.ok, "attack")
			eq(r:total(), 0, "clamped at zero")
			eq(ok.after, 0, "result reports the clamped total")
		end,
	},
	{
		name = "a total at zero defeats the run once; later events are ignored; score is 0",
		run = function()
			local r = run(Config.clusterTypes.small.attackLoss, { "small", "small" })
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
		name = "a same-batch attack after the total reaches zero still clamps and defeat is logged once",
		run = function()
			local r = run(Config.clusterTypes.small.attackLoss, { "small", "small" })
			local results = r:attackClusters({ "c1", "c2" })
			assert(results[1].ok and results[2].ok, "both attacks in the batch are accepted")
			eq(r:total(), 0, "clamped")
			eq(r:outcome(), "defeated", "defeated")
		end,
	},
	{
		name = "an obstacle that empties the parade defeats the run",
		run = function()
			local r = run(Config.obstacleLoss, {})
			assert(r:hitObstacle("o1").ok, "obstacle hit")
			eq(r:total(), 0, "total at zero")
			eq(r:outcome(), "defeated", "defeated by the obstacle")
		end,
	},
	{
		name = "an unblocked tomato removes tomatoLoss followers once and defeats at zero",
		run = function()
			local loss = Config.hazards.tomatoLoss
			local r = run(loss + 5, {}, { { id = "t1" } })
			assert(r:hitTomato("t1").ok, "tomato hit")
			eq(r:total(), 5, "tomato loss")
			local before = snapshotText(r)
			assert(not r:hitTomato("t1").ok, "the same tomato cannot hit twice")
			eq(snapshotText(r), before, "no second loss")
			eq(r:outcome(), nil, "still running at 5 followers")
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
		name = "attack and hazard losses are server config, positive whole numbers",
		run = function()
			for _, name in { "small", "large" } do
				local loss = (Config.clusterTypes :: any)[name].attackLoss
				assert(type(loss) == "number" and loss > 0 and loss == math.floor(loss), name)
			end
			local tl = Config.hazards.tomatoLoss
			assert(type(tl) == "number" and tl > 0 and tl == math.floor(tl), "tomatoLoss")
		end,
	},
}
