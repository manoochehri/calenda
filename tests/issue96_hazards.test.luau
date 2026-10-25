--!strict
-- Issue #96: level-specific hazards (tomato throws from the buildings, a tlayuda cart).
-- Fail-first: these were written before src/shared/Hazards.luau and the RunDriver wiring existed.
local Config = require("../src/shared/Config")
local CrowdMath = require("../src/shared/CrowdMath")
local Crossing = require("../src/shared/Crossing")
local Hazards = require("../src/shared/Hazards")
local RunDriver = require("../src/shared/RunDriver")
local Steering = require("../src/shared/Steering")

local function eq(actual: any, expected: any, label: string)
	assert(actual == expected, `{label}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function near(actual: number, expected: number, label: string)
	assert(math.abs(actual - expected) < 1e-9, `{label}: expected {expected}, got {actual}`)
end

local HALF_WIDTH = 20
local SPEED = Config.speed
local BOUND = Steering.bound(HALF_WIDTH)

local MIXED = { kinds = { "tomato", "cart" }, firstAt = 20, lastAt = 80, minGap = 14, maxGap = 22 }
local ONLY_TOMATO_ONCE =
	{ kinds = { "tomato" }, firstAt = 20, lastAt = 20, minGap = 14, maxGap = 14 }
local ONLY_CART_ONCE = { kinds = { "cart" }, firstAt = 20, lastAt = 20, minGap = 14, maxGap = 14 }

-- Minimal layout for the driver: no gates, no clusters, no streetwork obstacles, one hazard set.
local function layoutWith(set: any): any
	return {
		name = "issue96",
		seed = 0,
		startPlazaEnd = nil,
		streetLength = 1600,
		plazaStart = 1440,
		halfWidth = HALF_WIDTH,
		maxTotal = 1000,
		intendedRecruitTotal = 0,
		gates = {},
		obstacles = {},
		clusters = {},
		hazardSet = set,
	}
end

-- Drives the real RunDriver for `seconds` at 30 Hz, steering to `targetX` first.
-- `onShots` lets a test stand in for the server's landed gift shots (RunHooks reports them).
local function drive(set: any, runSeed: number, targetX: number, seconds: number, giftAt: number?)
	local driver = RunDriver.new({
		layout = layoutWith(set),
		startReady = true,
		runSeed = runSeed,
		now = function()
			return 0
		end,
		hooks = {
			shots = function(ctx: any)
				if giftAt ~= nil and ctx.t0 <= giftAt and giftAt < ctx.t1 then
					table.insert(ctx.giftTimes, giftAt)
				end
			end,
		},
	})
	driver:start(0)
	driver:steer(1, { x = targetX })
	local events = {}
	local now = 0
	local steps = math.floor(seconds / RunDriver.TICK_DT)
	for _ = 1, steps do
		now += RunDriver.TICK_DT
		for _, e in driver:tick(RunDriver.TICK_DT) do
			table.insert(events, e)
		end
	end
	return driver, events
end

local function countKind(events: { any }, kind: string): number
	local n = 0
	for _, e in events do
		if e.kind == kind then
			n += 1
		end
	end
	return n
end

local function firstOf(set: any, runSeed: number): any
	local list = Hazards.schedule(set, runSeed, HALF_WIDTH, SPEED)
	assert(#list == 1, `expected exactly one hazard, got {#list}`)
	return list[1]
end

return {
	{
		name = "the seeded schedule is reproducible and changes with the seed",
		run = function()
			local a = Hazards.schedule(MIXED, 7, HALF_WIDTH, SPEED)
			local b = Hazards.schedule(MIXED, 7, HALF_WIDTH, SPEED)
			eq(#a, #b, "same seed, same count")
			assert(#a >= 2, "the authored window should hold more than one hazard")
			for i = 1, #a do
				eq(a[i].kind, b[i].kind, `kind {i}`)
				eq(a[i].impactAt, b[i].impactAt, `impact {i}`)
				eq(a[i].x, b[i].x, `x {i}`)
			end
			local c = Hazards.schedule(MIXED, 8, HALF_WIDTH, SPEED)
			local differs = #c ~= #a
			for i = 1, math.min(#a, #c) do
				if a[i].x ~= c[i].x or a[i].impactAt ~= c[i].impactAt then
					differs = true
				end
			end
			assert(differs, "a different seed must give a different schedule")
		end,
	},
	{
		name = "no hazard warns before the run has started and all stay in the authored window",
		run = function()
			for seed = 1, 50 do
				for _, h in Hazards.schedule(MIXED, seed, HALF_WIDTH, SPEED) do
					assert(
						h.warnAt >= Hazards.MIN_START,
						`seed {seed}: warning at {h.warnAt} is too early`
					)
					assert(h.impactAt <= MIXED.lastAt, `seed {seed}: impact past the window`)
					assert(h.impactAt >= MIXED.firstAt, `seed {seed}: impact before the window`)
				end
			end
		end,
	},
	{
		name = "the hazard set comes from level configuration only",
		run = function()
			for _, h in Hazards.schedule(ONLY_CART_ONCE, 3, HALF_WIDTH, SPEED) do
				eq(h.kind, "cart", "cart-only set yields carts")
			end
			eq(
				#Hazards.schedule(
					{ kinds = {}, firstAt = 20, lastAt = 80, minGap = 14, maxGap = 22 },
					3,
					HALF_WIDTH,
					SPEED
				),
				0,
				"empty set yields nothing"
			)
			eq(#Hazards.schedule(nil, 3, HALF_WIDTH, SPEED), 0, "no set yields nothing")
			local ok = pcall(
				Hazards.schedule,
				{ kinds = { "unknown" }, firstAt = 20, lastAt = 20, minGap = 14, maxGap = 14 },
				3,
				HALF_WIDTH,
				SPEED
			)
			eq(ok, false, "an unknown kind is refused")
		end,
	},
	{
		name = "a tomato warning gives the authored lead time before impact",
		run = function()
			local h = firstOf(ONLY_TOMATO_ONCE, 5)
			eq(h.kind, "tomato", "kind")
			near(h.impactAt - h.warnAt, Hazards.TOMATO_WARNING, "warning lead")
			assert(Hazards.TOMATO_WARNING >= 2, "a tomato needs at least two seconds to answer")
		end,
	},
	{
		name = "steering clearance: from anywhere on the street the gap is reachable inside the cart warning",
		run = function()
			-- Worst case: the lead is at one edge of the steering bound and the gap at the other.
			local reach = (2 * BOUND) / Steering.MAX_LATERAL_SPEED
			assert(
				reach <= Hazards.CART_WARNING,
				`reach {reach}s exceeds warning {Hazards.CART_WARNING}s`
			)
			-- The clear gap is wider than the lead, so a centred lead is never hit.
			assert(
				Hazards.CART_CLEAR_WIDTH >= 2 * Crossing.LEAD_HITBOX.halfWidth,
				"gap narrower than the lead"
			)
		end,
	},
	{
		name = "a cart collision is decided by the lead's sweep against the blocked band",
		run = function()
			local cart = { id = 1, kind = "cart", x = 0, z = 1000, impactAt = 70, warnAt = 68 }
			-- Inside the gap: no hit. Outside it (either side): hit.
			eq(
				Hazards.cartHit(cart :: any, 999, 1000, 0, 0, HALF_WIDTH),
				false,
				"centred lead clears the cart"
			)
			eq(
				Hazards.cartHit(cart :: any, 999, 1000, 5, 5, HALF_WIDTH),
				true,
				"lead right of the gap hits"
			)
			eq(
				Hazards.cartHit(cart :: any, 999, 1000, -5, -5, HALF_WIDTH),
				true,
				"lead left of the gap hits"
			)
			eq(
				Hazards.cartHit(cart :: any, 900, 901, 5, 5, HALF_WIDTH),
				false,
				"cart not reached yet"
			)
		end,
	},
	{
		name = "a tomato lands on the lead only within the lane band",
		run = function()
			local tomato = { id = 1, kind = "tomato", x = 4, impactAt = 30, warnAt = 27.5 }
			eq(Hazards.tomatoHit(tomato :: any, 4), true, "directly under the throw")
			eq(Hazards.tomatoHit(tomato :: any, 10), false, "well clear of the throw")
		end,
	},
	{
		name = "a note shot does not block a tomato; the unblocked hit costs the configured followers once",
		run = function()
			local seed = 5
			local h = firstOf(ONLY_TOMATO_ONCE, seed)
			local driver, events = drive(ONLY_TOMATO_ONCE, seed, h.x, h.impactAt + 4)
			eq(countKind(events, "hazard_warning"), 1, "one warning")
			eq(countKind(events, "hazard_blocked"), 0, "notes never block")
			eq(countKind(events, "hazard_hit"), 1, "one hit, applied once")
			eq(
				driver:snapshot().total,
				Config.startingTotal
					- CrowdMath.shareLoss(
						Config.startingTotal,
						Config.hazards.tomatoSharePercent,
						Config.minShareLoss
					),
				"followers lost once"
			)
		end,
	},
	{
		name = "a landed gift shot inside the warning window blocks the tomato and costs no followers",
		run = function()
			local seed = 5
			local h = firstOf(ONLY_TOMATO_ONCE, seed)
			local driver, events =
				drive(ONLY_TOMATO_ONCE, seed, h.x, h.impactAt + 4, h.impactAt - 1)
			eq(countKind(events, "hazard_blocked"), 1, "gift blocks")
			eq(countKind(events, "hazard_hit"), 0, "a blocked tomato does not hit")
			eq(driver:snapshot().total, Config.startingTotal, "no followers lost")
		end,
	},
	{
		name = "a gift before the warning window does not block the tomato",
		run = function()
			local seed = 5
			local h = firstOf(ONLY_TOMATO_ONCE, seed)
			local driver = drive(ONLY_TOMATO_ONCE, seed, h.x, h.impactAt + 4, h.warnAt - 1)
			eq(
				driver:snapshot().total,
				Config.startingTotal
					- CrowdMath.shareLoss(
						Config.startingTotal,
						Config.hazards.tomatoSharePercent,
						Config.minShareLoss
					),
				"followers lost"
			)
		end,
	},
	{
		name = "a cart collision applies the existing obstacle loss once and is then consumed",
		run = function()
			local seed = 9
			local cart = firstOf(ONLY_CART_ONCE, seed)
			-- Steer to the side of the cart opposite its gap, so the lead must cross the blocked band.
			local target = if cart.x >= 0 then -BOUND else BOUND
			assert(
				math.abs(target - cart.x) > Hazards.CART_CLEAR_WIDTH / 2 + 1,
				"test needs a target outside the gap"
			)
			local driver, events = drive(ONLY_CART_ONCE, seed, target, cart.impactAt + 4)
			eq(countKind(events, "hazard_hit"), 1, "one collision")
			eq(
				driver:total(),
				10 - Config.obstacleLoss > 0 and 10 - Config.obstacleLoss or 0,
				"obstacle loss applied once"
			)
		end,
	},
	{
		name = "a cart the lead clears inside the gap costs nothing",
		run = function()
			local seed = 9
			local cart = firstOf(ONLY_CART_ONCE, seed)
			local driver, events = drive(ONLY_CART_ONCE, seed, cart.x, cart.impactAt + 4)
			eq(countKind(events, "hazard_hit"), 0, "no collision in the gap")
			eq(driver:total(), 10, "crowd unchanged")
		end,
	},
	{
		name = "a layout without a hazard set behaves as before: no hazard events",
		run = function()
			local _, events = drive(nil, 1, 0, 100)
			eq(countKind(events, "hazard_warning"), 0, "no warnings")
			eq(countKind(events, "hazard_hit"), 0, "no hits")
		end,
	},
}
