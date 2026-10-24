--!strict
local Config = require("../src/shared/Config")
local CrowdMath = require("../src/shared/CrowdMath")
local DebugLayout = require("../src/shared/DebugLayout")
local Level = require("../src/shared/Level")
local LayoutValidator = require("../src/shared/LayoutValidator")
local RunDriver = require("../src/shared/RunDriver")
local RunHooks = require("../src/shared/RunHooks")

local DT = RunDriver.TICK_DT

local function clone(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = clone(v)
	end
	return out
end

local function broken(mutate: (l: any) -> ()): any
	local l = clone(DebugLayout)
	mutate(l)
	return l
end

-- A hand-broken layout must be rejected, and the report must name the problem.
local function rejects(
	name: string,
	needle: string,
	mutate: (l: any) -> ()
): { name: string, run: () -> () }
	return {
		name = `rejects: {name}`,
		run = function()
			local report = LayoutValidator.check(broken(mutate))
			assert(not report.ok, `layout was accepted: {name}`)
			local joined = table.concat(report.errors, " | ")
			assert(string.find(joined, needle, 1, true), `expected "{needle}" in: {joined}`)
		end,
	}
end

local function gate(l: any, id: number): any
	for _, g in l.gates do
		if g.id == id then
			return g
		end
	end
	error(`no gate {id}`)
end

local function cluster(l: any, id: number): any
	for _, c in l.clusters do
		if c.id == id then
			return c
		end
	end
	error(`no cluster {id}`)
end

local function runHpScenario(competent: boolean): LayoutValidator.HPScenario
	local driver = RunDriver.new({
		layout = DebugLayout,
		automated = true,
		hooks = RunHooks.new(DebugLayout),
	})
	local trajectory = { { time = 0, hp = driver:snapshot().hp } }
	local attacks = {}
	local nextInput = 0
	for _ = 1, math.ceil(100 / DT) do
		local snapshot = driver:snapshot()
		if competent and snapshot.time >= nextInput - 1e-9 then
			local targetX = 0
			local leadZ = snapshot.z
			local closestCluster: Level.Cluster? = nil
			local closestClusterDistance = math.huge
			local closestLarge: Level.Cluster? = nil
			local closestLargeDistance = math.huge
			for _, c in DebugLayout.clusters do
				if snapshot.time >= c.spawnTime then
					local position = Level.clusterPosition(DebugLayout, c.id, snapshot.time)
					local distance = position.z - leadZ
					if distance > 0 and distance < closestClusterDistance then
						closestCluster = c
						closestClusterDistance = distance
					end
					if c.type == "large" and distance < closestLargeDistance then
						closestLarge = c
						closestLargeDistance = distance
					end
				end
			end
			-- Competent policy: steer toward the nearest large threat to prevent its larger HP loss;
			-- otherwise follow the nearest active cluster. The no-input control never steers.
			local clusterTarget = closestLarge or closestCluster
			if clusterTarget then
				targetX = if clusterTarget.spawn.x < 0 then -16 else 16
			end

			-- Prefer the gate with the larger current result when it is close enough to steer to.
			for _, g in DebugLayout.gates do
				local distance = g.z - leadZ
				if distance > 0 and distance <= Config.speed * 1.25 then
					local left = CrowdMath.applyOp(snapshot.total, g.left)
					local right = CrowdMath.applyOp(snapshot.total, g.right)
					targetX = if right > left then 16 else -16
					break
				end
			end
			assert(driver:steer(snapshot.time, { x = targetX }), "competent input accepted")
			nextInput = snapshot.time + 0.05
		end

		local beforeHp = snapshot.hp
		local events = driver:tick(DT)
		for _, event in events do
			if event.kind == "attack" then
				local attackedCluster = Level.findCluster(DebugLayout, event.id)
				table.insert(
					attacks,
					`{event.id}:{attackedCluster.type}@{string.format(
						"%.3f",
						driver:snapshot().time
					)}`
				)
			end
		end
		local after = driver:snapshot()
		if after.hp ~= beforeHp then
			table.insert(trajectory, { time = after.time, hp = after.hp })
		end
		if after.outcome ~= nil then
			return {
				outcome = after.outcome,
				hp = after.hp,
				trajectory = trajectory,
				attacks = attacks,
			}
		end
	end
	return { outcome = nil, hp = driver:snapshot().hp, trajectory = trajectory, attacks = attacks }
end

return {
	{
		name = "march pace is modestly slower while the fixed route still fits the spec timeline",
		run = function()
			assert(Config.speed < 16, `forward pace still {Config.speed} studs/s`)
			assert(Config.speed >= 13.6, `forward pace is more than 15% slower: {Config.speed}`)
			local r = LayoutValidator.check(DebugLayout)
			assert(r.ok, `slower-pace layout rejected: {table.concat(r.errors, " | ")}`)
			assert(math.abs(r.plazaTime - 90) <= 2, `plaza at {r.plazaTime} s`)
			assert(r.firstConversionTime <= 10, `first conversion at {r.firstConversionTime} s`)
			assert(r.firstSectionTimeWorst <= 25, `first section at {r.firstSectionTimeWorst} s`)
			assert(r.finalGateTime >= 65 and r.finalGateTime <= 90, `final gate at {r.finalGateTime} s`)
		end,
	},
	{
		name = "debug layout passes the validator",
		run = function()
			local report = LayoutValidator.check(DebugLayout)
			assert(report.ok, `rejected: {table.concat(report.errors, " | ")}`)
			local ok, err = LayoutValidator.validate(DebugLayout)
			assert(ok and err == nil, "validate() agrees")
		end,
	},
	{
		name = "debug layout is deeply frozen",
		run = function()
			assert(table.isfrozen(DebugLayout))
			assert(table.isfrozen(DebugLayout.gates))
			assert(table.isfrozen(DebugLayout.gates[1]))
			assert(table.isfrozen(DebugLayout.clusters[1].spawn))
		end,
	},
	{
		name = "report: positions fall in the spec 9 time windows at Config speed",
		run = function()
			local r = LayoutValidator.check(DebugLayout)
			assert(r.firstEncounterTime <= 10, `first cluster encounter {r.firstEncounterTime}`)
			assert(r.firstConversionTime <= 10, `first conversion {r.firstConversionTime}`)
			local early = 0
			for _, g in r.gateTimes do
				if g >= 10 and g <= 25 then
					early += 1
				end
			end
			assert(early >= 2, `gates in 10-25s: {early}`)
			assert(r.firstSectionTimeWorst <= 25, `first section {r.firstSectionTimeWorst}`)
			assert(r.finalGateTime >= 65 and r.finalGateTime <= 90, `final gate {r.finalGateTime}`)
			assert(
				r.largestGainGateTime >= 65 and r.largestGainGateTime <= 90,
				"largest growth window"
			)
			assert(math.abs(r.plazaTime - 90) <= 2, `plaza at {r.plazaTime}`)
			assert(
				math.abs(r.plazaTime - DebugLayout.plazaStart / Config.speed) < 1e-9,
				"uses Config.speed"
			)
		end,
	},
	{
		name = "report: growth bounded, completable, top tier reachable",
		run = function()
			local r = LayoutValidator.check(DebugLayout)
			assert(r.bestFinal <= DebugLayout.maxTotal, `best {r.bestFinal} > cap`)
			assert(r.worstFinal >= Config.sectionSize, `worst {r.worstFinal}`)
			assert(r.bestFinal >= Config.finaleThresholds[#Config.finaleThresholds], "top tier")
			assert(r.routeCount == 2 ^ #DebugLayout.gates, "all routes enumerated")
		end,
	},
	{
		name = "report: recruit total reachable at base fire rate",
		run = function()
			local r = LayoutValidator.check(DebugLayout)
			assert(
				r.recruitTotalBaseRate >= DebugLayout.intendedRecruitTotal,
				`recruited {r.recruitTotalBaseRate} < intended {DebugLayout.intendedRecruitTotal}`
			)
			assert(r.recruitTotalBaseRate <= r.recruitTotalAvailable, "cannot exceed available")
		end,
	},
	{
		name = "report: per-cluster arrival data is exposed for the HP extension (#36/#17)",
		run = function()
			local r = LayoutValidator.check(DebugLayout)
			for _, c in DebugLayout.clusters do
				local info = r.clusters[c.id]
				assert(info, `cluster {c.id} missing`)
				assert(info.reachTime ~= nil or info.convertTime ~= nil, "resolved before plaza")
				if info.convertTime == nil then
					assert(info.reachTime ~= nil, "unconverted clusters have a reach time")
				end
			end
		end,
	},
	{
		name = "extra checks plug in and can reject",
		run = function()
			local seen = false
			local ok = LayoutValidator.check(DebugLayout, nil, {
				function(ctx)
					seen = ctx.report.ok
					return true, nil
				end,
			})
			assert(ok.ok and seen, "extra check ran with the base report")
			local bad = LayoutValidator.check(DebugLayout, nil, {
				function(_ctx)
					return false, "hp trajectory: no-input run not defeated"
				end,
			})
			assert(not bad.ok, "extra failing check rejects")
			assert(string.find(table.concat(bad.errors, " "), "hp trajectory", 1, true))
		end,
	},
	{
		name = "HP extra check runs no-input and competent DebugLayout scenarios through RunHooks",
		run = function()
			local scenarios: { [string]: any } = {}
			local report = LayoutValidator.check(DebugLayout, nil, {
				function(ctx)
					assert(ctx.report.ok, "base layout checks pass before HP check")
					scenarios.noInput = runHpScenario(false)
					scenarios.competent = runHpScenario(true)
					ctx.report.hpScenarios = scenarios
					local function path(points: { LayoutValidator.HPTrajectoryPoint }): string
						local out = {}
						for _, point in points do
							table.insert(out, `{string.format("%.3f", point.time)}:{point.hp}`)
						end
						return table.concat(out, ",")
					end
					local noInputPath = path(scenarios.noInput.trajectory)
					local competentPath = path(scenarios.competent.trajectory)
					print(
						`HP scenarios (DebugLayout, samples=1 each): no-input outcome={scenarios.noInput.outcome} hp={scenarios.noInput.hp} trajectory={noInputPath}; attacks={table.concat(
							scenarios.noInput.attacks,
							","
						)}; competent outcome={scenarios.competent.outcome} hp={scenarios.competent.hp} trajectory={competentPath}; attacks={table.concat(
							scenarios.competent.attacks,
							","
						)}`
					)
					local ok = scenarios.noInput.outcome == "defeated"
						and scenarios.competent.outcome == "completed"
						and scenarios.competent.hp > 0
					return ok,
						`HP trajectory: no-input outcome={scenarios.noInput.outcome}, hp={scenarios.noInput.hp}; competent outcome={scenarios.competent.outcome}, hp={scenarios.competent.hp}`
				end,
			})
			assert(report.ok, `HP check rejected layout: {table.concat(report.errors, " | ")}`)
			assert(
				scenarios.noInput ~= nil and scenarios.competent ~= nil,
				"both runs were reported"
			)
			assert(
				scenarios.competent.trajectory[2].hp == 95,
				"competent policy accepts a small attack"
			)
			assert(
				scenarios.noInput.trajectory[#scenarios.noInput.trajectory].hp == 0,
				"no-input HP reaches zero"
			)
			assert(
				scenarios.competent.trajectory[#scenarios.competent.trajectory].hp > 0,
				"competent run preserves the configured remainder"
			)
		end,
	},
	{
		name = "timings come from Config speed: a slower lead breaks the windows",
		run = function()
			local slow = clone(Config)
			slow.speed = 8
			local report = LayoutValidator.check(DebugLayout, slow)
			assert(not report.ok, "layout tuned for speed 16 must fail at speed 8")
		end,
	},
	{
		name = "rejects: not a table",
		run = function()
			local ok, err = LayoutValidator.validate(42)
			assert(not ok and err == "layout must be a table", `got {err}`)
		end,
	},
	rejects("duplicate gate id", "duplicate gate id", function(l)
		l.gates[2].id = l.gates[1].id
	end),
	rejects("duplicate cluster id", "duplicate cluster id", function(l)
		l.clusters[2].id = l.clusters[1].id
	end),
	rejects("gates out of order", "gates must be sorted", function(l)
		l.gates[1], l.gates[2] = l.gates[2], l.gates[1]
	end),
	rejects("multiply by 1", "invalid op", function(l)
		gate(l, 1).right = { kind = "multiply", value = 1 }
	end),
	rejects("unknown op kind", "invalid op", function(l)
		gate(l, 1).left = { kind = "subtract", value = 5 }
	end),
	rejects("unknown cluster type", "unknown cluster type", function(l)
		l.clusters[1].type = "huge"
	end),
	rejects("cluster spawn behind the lead's start", "spawn", function(l)
		l.clusters[1].spawn.z = -5
	end),
	rejects("cluster path walks away from the parade", "path", function(l)
		l.clusters[1].path = { { x = -16, z = l.clusters[1].spawn.z + 50 } }
	end),
	rejects("cluster off the street", "outside street", function(l)
		l.clusters[1].spawn.x = 99
	end),
	rejects("plaza far from 90 s", "plaza", function(l)
		l.plazaStart = 800
	end),
	rejects("street shorter than plaza", "streetLength", function(l)
		l.streetLength = 1000
	end),
	rejects("first cluster too late", "first cluster", function(l)
		for _, c in l.clusters do
			c.spawnTime += 30
		end
	end),
	rejects("gate before 10 s", "before 10", function(l)
		gate(l, 1).z = 100
	end),
	rejects("fewer than two early gates", "early gates", function(l)
		gate(l, 2).z = 28 * Config.speed
	end),
	rejects("first section too late", "first section", function(l)
		gate(l, 1).left = { kind = "add", value = 1 }
		gate(l, 1).right = { kind = "add", value = 1 }
		gate(l, 2).left = { kind = "add", value = 1 }
		gate(l, 2).right = { kind = "add", value = 1 }
		-- At the continuous-fire rate (6/s base, ADR 0004) the early clusters alone reach a section
		-- in time, so the late clusters are also pushed past the 25 s window.
		for _, c in l.clusters do
			if c.id > 2 then
				c.spawnTime += 40
				c.spawn.z += 40 * Config.speed
			end
		end
	end),
	rejects("obstacle before the early gates are done", "early", function(l)
		l.obstacles[1].z = 15 * Config.speed
	end),
	rejects("waves not alternating", "alternat", function(l)
		for _, c in l.clusters do
			if c.wave == 3 then
				c.spawn.x = -c.spawn.x
				for _, p in c.path do
					p.x = -p.x
				end
			end
		end
	end),
	rejects("wave mixes sides", "mixes sides", function(l)
		cluster(l, 2).wave = cluster(l, 1).wave
	end),
	rejects("gates too close to read", "too close", function(l)
		gate(l, 4).z = gate(l, 3).z + Config.speed
	end),
	rejects("final route decision outside 65-90 s", "final", function(l)
		table.remove(l.gates)
		table.remove(l.gates)
	end),
	rejects("largest growth not in 65-90 s", "largest growth", function(l)
		gate(l, 3).right = { kind = "multiply", value = 60 }
		gate(l, 3).left = { kind = "multiply", value = 60 }
		l.maxTotal = 10 ^ 9
		for _, id in { 4, 5, 6, 7 } do
			gate(l, id).left = { kind = "add", value = 1 }
			gate(l, id).right = { kind = "add", value = 1 }
		end
	end),
	rejects("growth unbounded", "maxTotal", function(l)
		l.maxTotal = 100
	end),
	rejects("worst route collapses (needs spending to recover)", "worst route", function(l)
		for _, g in l.gates do
			if Level.timeAtZ(g.z) > 30 then
				g.left = { kind = "add", value = 1 }
				g.right = { kind = "add", value = 1 }
			end
		end
		for _, o in l.obstacles do
			o.side = "left"
		end
		l.clusters = {}
		l.intendedRecruitTotal = 0
	end),
	rejects("intended recruit total unreachable at base rate", "recruit", function(l)
		l.intendedRecruitTotal = 100000
	end),
	rejects("wave crowd too dense to convert at base rate", "recruit", function(l)
		-- ten large clusters arriving together: base rate cannot clear them
		for i = 1, 10 do
			table.insert(l.clusters, {
				id = 100 + i,
				wave = 2,
				type = "large",
				spawnTime = 14,
				spawn = { x = 16, z = 14 * Config.speed + 150 + i },
				path = {},
			})
		end
		local total = 0
		for _, c in l.clusters do
			total += Config.clusterTypes[c.type].reward
		end
		l.intendedRecruitTotal = total
	end),
	rejects("cluster never reaches the parade before the plaza", "plaza", function(l)
		cluster(l, 1).spawnTime = 200
	end),
	rejects("no obstacle", "obstacle", function(l)
		l.obstacles = {}
	end),
	rejects("obstacle with invalid side", "obstacle", function(l)
		l.obstacles[1].side = "middle"
	end),
}
