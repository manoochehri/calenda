--!strict
-- Witness search for authored layouts (issue #144). Pure: no Roblox APIs.
--
-- Plays a layout through the production RunDriver (with RunHooks, so the steer token-bucket limiter
-- and the real firing, conversion and hazard rules apply) under a fixed set of steering policies and
-- seeds, and reports the highest final crowd total observed. Each run is a real simulation, so a
-- witness is evidence that a total is reachable. It is NOT a proof of a bound: finding no witness
-- above a limit says nothing about runs the policies did not try.
local Config = require("./Config")
local CrowdMath = require("./CrowdMath")
local Level = require("./Level")
local RunDriver = require("./RunDriver")
local RunHooks = require("./RunHooks")
local StreetGeometry = require("./StreetGeometry")

local LayoutWitness = {}

export type View = { time: number, z: number, x: number, total: number, layout: Level.Layout }
-- decide returns the lateral target to steer to, or nil to send no steer this decision.
export type Policy = { name: string, period: number, decide: (view: View) -> number? }
export type Witness = { policy: string, seed: number, total: number, outcome: string? }
export type Result = {
	runs: number, -- policies x seeds actually simulated
	policies: number,
	seeds: number,
	worst: Witness?, -- the highest final total; first one found on ties
}

LayoutWitness.SEEDS = { 1, 2, 3, 4, 5 } -- [default] run seeds; seed drives hazards and random policies
LayoutWitness.MAX_SECONDS = 100 -- [default] a run is simulated at most this long
local DT = RunDriver.TICK_DT
local SIDE = StreetGeometry.LANE_CENTER -- lane centre |x| (ADR 0011), where outer-lane waves approach

-- Deterministic LCG for seeded policies: floats in [0, 1).
local function rng(seed: number): () -> number
	local s = (seed * 2654435761 + 12345) % 4294967296
	local function nextValue(): number
		s = (s * 1664525 + 1013904223) % 4294967296
		return s / 4294967296
	end
	for _ = 1, 8 do
		nextValue()
	end
	return nextValue
end

local function sideX(positive: boolean): number
	return if positive then SIDE else -SIDE
end

-- The nearest cluster ahead of the lead (optionally large only) that has spawned.
local function nearest(view: View, largeOnly: boolean): Level.Cluster?
	local best: Level.Cluster? = nil
	local bestDist = math.huge
	for _, c in view.layout.clusters do
		if view.time >= c.spawnTime and (not largeOnly or c.type == "large") then
			local d = Level.clusterPosition(view.layout, c.id, view.time).z - view.z
			if d > 0 and d < bestDist then
				best, bestDist = c, d
			end
		end
	end
	return best
end

-- Within 1.25 s of a gate, take the side whose result is larger.
local function gateTarget(view: View): number?
	for _, g in view.layout.gates do
		local d = g.z - view.z
		if d > 0 and d <= Config.speed * 1.25 then
			local left = CrowdMath.applyOp(view.total, g.left)
			local right = CrowdMath.applyOp(view.total, g.right)
			return sideX(right > left)
		end
	end
	return nil
end

local function clusterSide(c: Level.Cluster?): number
	if c == nil then
		return 0
	end
	return sideX(c.spawn.x >= 0)
end

-- Nearest large cluster (signed distance, as in tests/helpers/BotHarness), else nearest any ahead,
-- then the gate preference.
local function scripted(view: View): number
	local anyAhead: Level.Cluster? = nil
	local anyDist = math.huge
	local large: Level.Cluster? = nil
	local largeDist = math.huge
	for _, c in view.layout.clusters do
		if view.time >= c.spawnTime then
			local d = Level.clusterPosition(view.layout, c.id, view.time).z - view.z
			if d > 0 and d < anyDist then
				anyAhead, anyDist = c, d
			end
			if c.type == "large" and d < largeDist then
				large, largeDist = c, d
			end
		end
	end
	return gateTarget(view) or clusterSide(large or anyAhead)
end

-- Fresh policy instances for one seed (some carry state or a seeded RNG).
local function policies(seed: number): { Policy }
	local r = rng(seed)
	local alt = false
	local lastCheck, lapseUntil, lapseX = 0, 0, 0
	return {
		{
			name = "always-left",
			period = 0.5,
			decide = function()
				return -SIDE
			end,
		},
		{
			name = "always-right",
			period = 0.5,
			decide = function()
				return SIDE
			end,
		},
		{
			name = "alternate-2.5s",
			period = 2.5,
			decide = function()
				alt = not alt
				return sideX(alt)
			end,
		},
		{
			name = "random-side-0.5s",
			period = 0.5,
			decide = function()
				return sideX(r() < 0.5)
			end,
		},
		{
			name = "nearest-cluster-only",
			period = 0.05,
			decide = function(view)
				return clusterSide(nearest(view, false))
			end,
		},
		{
			name = "nearest-large-only",
			period = 0.05,
			decide = function(view)
				return clusterSide(nearest(view, true))
			end,
		},
		{
			name = "nearest-any+gate-pref",
			period = 0.05,
			decide = function(view)
				return gateTarget(view) or clusterSide(nearest(view, false))
			end,
		},
		{
			name = "scripted",
			period = 0.05,
			decide = scripted,
		},
		{
			-- Scripted, but every 0.25 s it may lapse (probability 0.25) and hold a random side for 0.5 s.
			name = "noisy-scripted",
			period = 0.05,
			decide = function(view)
				if view.time >= lapseUntil - 1e-9 and view.time - lastCheck >= 0.25 - 1e-9 then
					lastCheck = view.time
					if r() < 0.25 then
						lapseUntil = view.time + 0.5
						lapseX = sideX(r() < 0.5)
					end
				end
				if view.time < lapseUntil - 1e-9 then
					return lapseX
				end
				return scripted(view)
			end,
		},
	}
end

-- Plays one run through the production driver. Returns the final total and the outcome.
local function play(layout: Level.Layout, policy: Policy, seed: number): (number, string?)
	local clock = 0 -- session clock: the steer limiter's time (server seconds in production)
	local driver = RunDriver.new({
		layout = layout,
		automated = true,
		hooks = RunHooks.new(layout),
		runSeed = seed,
		now = function()
			return clock
		end,
	})
	local nextDecision = 0
	for _ = 1, math.ceil(LayoutWitness.MAX_SECONDS / DT) do
		clock += DT
		local snap = driver:snapshot()
		if policy.period > 0 and snap.time >= nextDecision - 1e-9 then
			local target = policy.decide({
				time = snap.time,
				z = snap.z,
				x = snap.x,
				total = snap.total,
				layout = layout,
			})
			if target ~= nil then
				driver:steer(clock, { x = target })
			end
			nextDecision = snap.time + policy.period
		end
		driver:tick(DT)
		if driver:outcome() ~= nil then
			break
		end
	end
	return driver:total(), driver:outcome()
end

-- Runs every fixed policy under every seed and returns the highest final total with its witness.
local function searchUncached(layout: Level.Layout, seeds: { number }?): Result
	local seedList = seeds or LayoutWitness.SEEDS
	local result: Result = { runs = 0, policies = 0, seeds = #seedList, worst = nil }
	for _, seed in seedList do
		local list = policies(seed)
		result.policies = #list
		for _, policy in list do
			local total, outcome = play(layout, policy, seed)
			result.runs += 1
			local worst = result.worst
			if worst == nil or total > worst.total then
				result.worst =
					{ policy = policy.name, seed = seed, total = total, outcome = outcome }
			end
		end
	end
	return result
end

-- Results for frozen layouts (the authored catalogue and the debug layout), keyed by table. A frozen
-- layout cannot change, so its search is a pure function of its contents and can be reused. Layouts
-- that are not frozen (test clones, mutated copies) are never cached.
local cache: { [Level.Layout]: Result } = setmetatable({}, { __mode = "k" }) :: any

-- Runs every fixed policy under every seed and returns the highest final total with its witness.
function LayoutWitness.search(layout: Level.Layout, seeds: { number }?): Result
	local frozen = seeds == nil and table.isfrozen(layout :: any)
	if frozen and cache[layout] ~= nil then
		return cache[layout]
	end
	local result = searchUncached(layout, seeds)
	if frozen then
		cache[layout] = result
	end
	return result
end

return LayoutWitness
