--!strict
-- Issue #67: the pure look numbers (ShotLook). The in-engine appearance is UNVERIFIED; these tests
-- pin the knobs, the pool sizing against the firing cap, and the shape of the curves.
local Config = require("../src/shared/Config")
local FireTable = require("../src/shared/FireTable")
local FeedbackMath = require("../src/shared/FeedbackMath")
local ShotLook = require("../src/shared/ShotLook")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function near(actual: number, expected: number, name: string)
	assert(math.abs(actual - expected) < 1e-9, `{name}: expected {expected}, got {actual}`)
end

return {
	{
		name = "projectile pool covers rate x flight time at the firing cap, within the hard cap",
		run = function()
			local rate = FireTable.maxRate(Config)
			local cap = ShotLook.projectileCapacity(rate, FeedbackMath.MAX_FLIGHT)
			assert(
				cap >= rate * ShotLook.longestFlight(FeedbackMath.MAX_FLIGHT),
				`pool {cap} < rate x flight`
			)
			assert(cap <= ShotLook.PROJECTILE_HARD_CAP, "within the hard cap")
			eq(cap, 22, "20/s x 0.9 s = 18, plus 4 slack") -- the number stated in the PR
			eq(ShotLook.projectileCapacity(1000, 1), ShotLook.PROJECTILE_HARD_CAP, "hard cap wins")
			eq(ShotLook.projectileCapacity(0, 0.1), ShotLook.CAPACITY_SLACK, "at least slack")
		end,
	},
	{
		name = "muzzle and impact pools cover their rate x duration at the firing cap",
		run = function()
			local rate = FireTable.maxRate(Config)
			assert(ShotLook.MUZZLE_CAPACITY >= rate * ShotLook.MUZZLE_SECONDS, "muzzle")
			assert(ShotLook.IMPACT_CAPACITY >= rate * ShotLook.IMPACT_SECONDS, "impact")
		end,
	},
	{
		name = "shots are bigger than the old 0.9 note and the three kinds look different",
		run = function()
			for _, name in { "note", "heart", "gift" } do
				assert(ShotLook.LOOKS[name].size >= 1.8, `{name} is bigger`)
			end
			local seen: { [string]: boolean } = {}
			for _, name in { "note", "heart", "gift" } do
				local c = ShotLook.LOOKS[name].core
				local key = `{c[1]},{c[2]},{c[3]}`
				assert(not seen[key], `{name} core color repeats`)
				seen[key] = true
			end
			assert(ShotLook.HALO_SCALE > 1, "halo larger than the core")
		end,
	},
	{
		name = "pop swells and fades; recoil pushes back and returns",
		run = function()
			local a, b = ShotLook.pop(0), ShotLook.pop(1)
			assert(a.scale < b.scale and a.alpha == 1 and b.alpha == 0, "swell and fade")
			assert(ShotLook.pop(-5).alpha == 1 and ShotLook.pop(9).alpha == 0, "clamped")
			near(ShotLook.recoil(0), 0, "start")
			near(ShotLook.recoil(1), 0, "end")
			assert(ShotLook.recoil(0.5) == ShotLook.RECOIL, "peak")
		end,
	},
	{
		name = "squash dips and springs back, and is neutral outside its window",
		run = function()
			eq(ShotLook.squash(-1).y, 1, "before")
			eq(ShotLook.squash(ShotLook.SQUASH_SECONDS).y, 1, "after")
			local mid = ShotLook.squash(ShotLook.SQUASH_SECONDS / 2)
			assert(mid.y < 1 and mid.xz > 1, "shorter and wider")
			near(mid.y, 1 - ShotLook.SQUASH_AMOUNT, "deepest")
		end,
	},
	{
		name = "a miss flies straight ahead, far, shrinking and fading to nothing",
		run = function()
			local p0, p1 = ShotLook.miss(0, 3), ShotLook.miss(1, 3)
			near(p0.dz, 0, "starts at the lead")
			near(p1.dz, ShotLook.MISS_DISTANCE, "ends far ahead")
			eq(p0.alpha, 1, "opaque at the start")
			eq(p1.alpha, 0, "gone at the end")
			assert(p1.scale < p0.scale, "shrinks")
			local last = 2
			for i = 0, 20 do
				local a = ShotLook.miss(i / 20, 7).alpha
				assert(a <= last + 1e-12, "alpha never rises")
				last = a
			end
			eq(ShotLook.miss(0.3, 12).dx, ShotLook.miss(0.3, 12).dx, "deterministic")
			assert(
				math.abs(ShotLook.miss(1, 9).dx) <= 2 * ShotLook.MISS_SPREAD + 1e-9,
				"bounded lane"
			)
		end,
	},
	{
		name = "pulse stays within its band",
		run = function()
			for i = 0, 20 do
				local p = ShotLook.pulse(i / 20)
				assert(p >= 1 - ShotLook.PULSE - 1e-9 and p <= 1 + ShotLook.PULSE + 1e-9, "band")
			end
		end,
	},
}
