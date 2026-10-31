--!strict
-- Issue #156: lane geometry, lane-bounded steering, targeting and contact, and optional +1 pickups
-- (ADR 0010, ADR 0011, spec Amendment 9). Modules are required inside each case so a missing module
-- fails only its own case, not the whole runner.
local Config = require("../src/shared/Config")
local CrowdMath = require("../src/shared/CrowdMath")
local Level = require("../src/shared/Level")
local RunDriver = require("../src/shared/RunDriver")

local function eq(actual: any, expected: any, label: string)
	assert(actual == expected, `{label}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function near(actual: number, expected: number, label: string)
	assert(math.abs(actual - expected) < 1e-9, `{label}: expected {expected}, got {actual}`)
end

local function deepCopy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, child in v do
		out[k] = deepCopy(child)
	end
	return out
end

-- Minimal layout with one right-lane (or other) pickup, no gates, obstacles or mobs.
local function pickupLayout(lane: string): Level.Layout
	return {
		name = "issue156-pickup",
		seed = 3,
		streetLength = 400,
		plazaStart = 320,
		halfWidth = 20,
		leadLimit = 15,
		maxTotal = 1000,
		intendedRecruitTotal = 0,
		gates = {},
		obstacles = {},
		clusters = {},
		pickups = { { id = 1, z = 64, lane = lane } },
	} :: any
end

-- Ticks until the run ends (or a safety cap); returns every event.
local function runOut(d: RunDriver.RunDriver, maxSeconds: number): { RunDriver.DriverEvent }
	local all: { RunDriver.DriverEvent } = {}
	for _ = 1, math.ceil(maxSeconds / RunDriver.TICK_DT) do
		for _, e in d:tick(RunDriver.TICK_DT) do
			table.insert(all, e)
		end
		if d:outcome() ~= nil then
			break
		end
	end
	return all
end

local function countKind(events: { RunDriver.DriverEvent }, kind: string): number
	local n = 0
	for _, e in events do
		if e.kind == kind then
			n += 1
		end
	end
	return n
end

local function ids(list: { { id: number } }): string
	local out = {}
	for _, p in list do
		table.insert(out, tostring(p.id))
	end
	table.sort(out)
	return table.concat(out, ",")
end

return {
	{
		name = "LaneGeometry: bands [-15,-5) [-5,5) [5,15], boundary belongs to the right lane",
		run = function()
			local LaneGeometry = require("../src/shared/LaneGeometry")
			eq(LaneGeometry.laneOf(-15), "left", "left edge")
			eq(LaneGeometry.laneOf(-5.0001), "left", "just left of -5")
			eq(LaneGeometry.laneOf(-5), "center", "-5 belongs to center")
			eq(LaneGeometry.laneOf(0), "center", "middle")
			eq(LaneGeometry.laneOf(4.9999), "center", "just left of 5")
			eq(LaneGeometry.laneOf(5), "right", "5 belongs to right")
			eq(LaneGeometry.laneOf(15), "right", "right edge")
			eq(LaneGeometry.laneOf(15.0001), nil, "outside the street lanes")
			eq(LaneGeometry.laneOf(-15.0001), nil, "outside the street lanes, left")
		end,
	},
	{
		name = "LaneGeometry: centers are -10, 0, 10 and each lays in its own lane",
		run = function()
			local LaneGeometry = require("../src/shared/LaneGeometry")
			near(LaneGeometry.centerOf("left"), -10, "left center")
			near(LaneGeometry.centerOf("center"), 0, "center")
			near(LaneGeometry.centerOf("right"), 10, "right center")
			for _, lane in { "left", "center", "right" } do
				eq(LaneGeometry.laneOf(LaneGeometry.centerOf(lane)), lane, `{lane} center in lane`)
			end
		end,
	},
	{
		name = "Steering.bound(halfWidth, leadLimit) is the min of the edge bound and leadLimit",
		run = function()
			local Steering = require("../src/shared/Steering")
			near(Steering.bound(20, 15), 15, "leadLimit binds on a 20 street")
			near(Steering.bound(20, 30), 18.5, "edge margin binds when leadLimit is wide")
			near(Steering.bound(10, 15), 8.5, "edge margin binds on a narrow street")
			near(Steering.bound(1, 15), 0, "never negative")
		end,
	},
	{
		name = "Targeting: a candidate is engaged by its authored lane only (center included)",
		run = function()
			local Targeting = require("../src/shared/Targeting")
			local list = {
				{ id = 1, x = 0, z = 10, full = false, lane = "center" },
				{ id = 2, x = -10, z = 8, full = false, lane = "left" },
			}
			eq(Targeting.selectTarget(list, 0, "center"), 1, "center steer engages center lane")
			eq(Targeting.selectTarget(list, 0, "left"), 2, "left steer engages left lane")
			eq(Targeting.selectTarget(list, 0, "right"), nil, "right steer: no right candidates")
			eq(Targeting.selectTarget(list, 0, nil :: any), nil, "no lane engages nothing")
		end,
	},
	{
		name = "Crossing.pickupsAwarded: interpolated x at the plane decides the lane",
		run = function()
			local Crossing = require("../src/shared/Crossing")
			local layout = {
				halfWidth = 20,
				gates = {},
				obstacles = {},
				clusters = {},
				pickups = {
					{ id = 1, z = 5, lane = "right" },
					{ id = 2, z = 5, lane = "left" },
					{ id = 3, z = 5, lane = "center" },
				},
			} :: any
			-- moving 0 -> 12 over z 0 -> 10: x at z=5 is 6 (right)
			eq(ids(Crossing.pickupsAwarded(layout, 0, 10, 0, 12)), "1", "x 6 is right only")
			-- moving 0 -> 10: x at z=5 is exactly 5, which belongs to right
			eq(ids(Crossing.pickupsAwarded(layout, 0, 10, 0, 10)), "1", "exact 5 is right")
			-- standing at 0: center only
			eq(ids(Crossing.pickupsAwarded(layout, 0, 10, 0, 0)), "3", "center only")
			-- already passed (z0 == z): not crossed again
			eq(
				ids(Crossing.pickupsAwarded(layout, 5, 10, 0, 0)),
				"",
				"z0 equal to plane: no crossing"
			)
			-- plane exactly at z1: crossed this tick
			eq(ids(Crossing.pickupsAwarded(layout, 0, 5, 0, 0)), "3", "z1 equal to plane crosses")
			-- no forward progress: nothing crosses (stationary lateral moves cannot collect)
			eq(ids(Crossing.pickupsAwarded(layout, 5, 5, 0, 12)), "", "no z progress")
		end,
	},
	{
		name = "RunState.addPickup adds exactly one, once per id; unknown ids are rejected",
		run = function()
			local RunState = require("../src/shared/RunState")
			local state = RunState.new({
				seed = 1,
				automated = true,
				layout = {
					gatePairs = {},
					clusters = {},
					obstacles = {},
					pickups = { { id = "p1" } },
				} :: any,
			})
			local start = state:total()
			local r = state:addPickup("p1")
			eq(r.ok, true, "first award accepted")
			eq(state:total(), start + 1, "exactly +1")
			eq(state:addPickup("p1").ok, false, "second award refused")
			eq(state:total(), start + 1, "still +1 after refusal")
			eq(state:addPickup("nope").ok, false, "unknown pickup refused")
			eq(state:total(), start + 1, "unknown pickup changes nothing")
		end,
	},
	{
		name = "RunState.passCluster consumes an off-lane mob with no loss and no credit",
		run = function()
			local RunState = require("../src/shared/RunState")
			local state = RunState.new({
				seed = 1,
				automated = true,
				layout = {
					gatePairs = {},
					clusters = { { id = "c1", type = "small" } },
					obstacles = {},
				} :: any,
			})
			local start = state:total()
			eq(state:passCluster("c1").ok, true, "pass accepted")
			eq(state:total(), start, "no reward, no loss")
			eq(state:clusterConsumption("c1"), "passed", "marked passed")
			eq(state:creditCluster("c1").ok, false, "a passed mob cannot be credited later")
			eq(state:passCluster("c1").ok, false, "a passed mob cannot pass twice")
		end,
	},
	{
		name = "RunState: reset clears pickup and pass consumption",
		run = function()
			local RunState = require("../src/shared/RunState")
			local state = RunState.new({
				seed = 1,
				automated = true,
				layout = {
					gatePairs = {},
					clusters = { { id = "c1", type = "small" } },
					obstacles = {},
					pickups = { { id = "p1" } },
				} :: any,
			})
			local start = state:total()
			state:addPickup("p1")
			state:passCluster("c1")
			state:reset()
			eq(state:total(), start, "reset restores the total")
			eq(state:addPickup("p1").ok, true, "pickup available again after reset")
			eq(state:clusterConsumption("c1"), nil, "pass cleared by reset")
		end,
	},
	{
		name = "RunHooks.attacks: only an in-lane passed mob attacks; an off-lane one is consumed free",
		run = function()
			local RunHooks = require("../src/shared/RunHooks")
			local RunState = require("../src/shared/RunState")
			local layout = {
				name = "t",
				seed = 1,
				streetLength = 400,
				plazaStart = 320,
				halfWidth = 20,
				leadLimit = 15,
				maxTotal = 1000,
				intendedRecruitTotal = 0,
				gates = {},
				obstacles = {},
				clusters = {
					{
						id = 1,
						wave = 1,
						type = "small",
						spawnTime = 0,
						spawn = { x = 10, z = 200 },
						path = {},
						lane = "right",
					},
				},
			} :: any
			local hooks = RunHooks.new(layout)
			local function attackWith(x: number): (number, number, any)
				local state = RunState.new({
					seed = 1,
					automated = true,
					startingTotal = 10, -- exercise share losses on an existing recruited parade
					layout = RunDriver.toRunLayout(layout),
				})
				local before = state:total()
				hooks.attacks({
					layout = layout,
					state = state,
					x = x,
					passedClusters = { 1 },
					emit = function() end,
					giftTimes = {},
				})
				return before, state:total(), state:clusterConsumption("c1")
			end
			local b1, a1, use1 = attackWith(-10)
			eq(a1, b1, "lead in left lane: right mob costs nothing")
			eq(use1, "passed", "off-lane mob is consumed")
			local b2, a2, use2 = attackWith(10)
			local share = CrowdMath.shareLoss(b2, Config.attackSharePercent, Config.minShareLoss)
			eq(a2, b2 - share, "lead in the mob's lane: normal share loss")
			eq(use2, "attacked", "in-lane mob attacks")
		end,
	},
	{
		name = "RunDriver: a right-lane pickup adds +1 once when the lead crosses it in that lane",
		run = function()
			local d = RunDriver.new({ layout = pickupLayout("right"), automated = true })
			local before = d:total()
			assert(d:steer(0, { x = 10 }), "steer accepted")
			local events = runOut(d, 200)
			eq(d:total(), before + 1, "exactly one +1 in the right lane")
			eq(countKind(events, "pickup"), 1, "one pickup event")
			-- once only: the run has ended, and a replay that crosses again awards one more, not two
			eq(d:replay(1000), true, "replay accepted")
			assert(d:steer(1000, { x = 10 }), "steer accepted after replay")
			runOut(d, 200)
			eq(d:total(), before + 1, "replay run also gets exactly one +1")
		end,
	},
	{
		name = "RunDriver: the pickup is passed for nothing outside its lane and for a center lead on a right pickup",
		run = function()
			local d = RunDriver.new({ layout = pickupLayout("right"), automated = true })
			local before = d:total()
			assert(d:steer(0, { x = -10 }), "steer accepted")
			local events = runOut(d, 200)
			eq(d:total(), before, "left lead passes a right pickup for nothing")
			eq(countKind(events, "pickup"), 0, "no pickup event")
			local c = RunDriver.new({ layout = pickupLayout("right"), automated = true })
			local cBefore = c:total()
			runOut(c, 200)
			eq(c:total(), cBefore, "center lead (x=0) passes a right pickup for nothing")
		end,
	},
	{
		name = "RunDriver: a center pickup is awarded to a lead standing at center",
		run = function()
			local d = RunDriver.new({ layout = pickupLayout("center"), automated = true })
			local before = d:total()
			runOut(d, 200)
			eq(d:total(), before + 1, "center lead gets the center pickup")
		end,
	},
	{
		name = "LayoutValidator: lane mismatch, missing or wide leadLimit, bad pickups all fail",
		run = function()
			local Layouts = require("../src/shared/Layouts")
			local LayoutValidator = require("../src/shared/LayoutValidator")
			local base = Layouts.all[1]
			local ok0 = LayoutValidator.validate(base)
			eq(ok0, true, "production layout validates before mutation")

			local wrongLane = deepCopy(base)
			wrongLane.clusters[1].lane = "center"
			local ok1, msg1 = LayoutValidator.validate(wrongLane)
			eq(ok1, false, "cluster lane must equal laneOf(spawn.x)")
			assert(string.find(msg1 :: string, "lane") ~= nil, "message names the lane")

			local noLimit = deepCopy(base)
			noLimit.leadLimit = nil
			eq(LayoutValidator.validate(noLimit), false, "leadLimit is required")

			local wideLimit = deepCopy(base)
			wideLimit.leadLimit = 25
			eq(LayoutValidator.validate(wideLimit), false, "leadLimit above halfWidth fails")

			local badLane = deepCopy(base)
			badLane.pickups = { { id = 1, z = 500, lane = "up" } }
			eq(LayoutValidator.validate(badLane), false, "pickup lane must be left/center/right")

			local dupe = deepCopy(base)
			dupe.pickups =
				{ { id = 1, z = 500, lane = "left" }, { id = 1, z = 600, lane = "right" } }
			eq(LayoutValidator.validate(dupe), false, "pickup ids are unique")

			local outOfRange = deepCopy(base)
			outOfRange.pickups = { { id = 1, z = outOfRange.plazaStart + 10, lane = "left" } }
			eq(LayoutValidator.validate(outOfRange), false, "pickup z stays before the plaza")
		end,
	},
	{
		name = "Layouts: every outer spawn is at a lane center (+-10) and its lane is authored",
		run = function()
			local Layouts = require("../src/shared/Layouts")
			local LaneGeometry = require("../src/shared/LaneGeometry")
			for _, layout in Layouts.all do
				eq(layout.leadLimit, 15, `{layout.name} leadLimit`)
				for _, c in layout.clusters do
					near(math.abs(c.spawn.x), 10, `{layout.name} cluster {c.id} spawn x`)
					eq(c.lane, LaneGeometry.laneOf(c.spawn.x), `{layout.name} cluster {c.id} lane`)
				end
			end
		end,
	},
	{
		name = "DebugLayout (the played level): outer spawns at +-10 with authored lanes",
		run = function()
			local DebugLayout = require("../src/shared/DebugLayout")
			local LaneGeometry = require("../src/shared/LaneGeometry")
			eq(DebugLayout.leadLimit, 15, "leadLimit")
			for _, c in DebugLayout.clusters do
				near(math.abs(c.spawn.x), 10, `cluster {c.id} spawn x`)
				eq(c.lane, LaneGeometry.laneOf(c.spawn.x), `cluster {c.id} lane`)
			end
		end,
	},
	{
		name = "Remotes: the pickup event kind is accepted by the client decoder",
		run = function()
			local Remotes = require("../src/shared/Remotes")
			eq(Remotes.isEventKind("pickup"), true, "pickup is a known event kind")
			eq(Remotes.isEventKind("bogus"), false, "unknown kinds stay rejected")
		end,
	},
}
