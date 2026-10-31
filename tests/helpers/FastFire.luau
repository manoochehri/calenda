--!strict
-- Issue #234: tests that pin firing MECHANICS (hit/miss, credit-once, targeting, scheduling on a
-- fixed clock) need a steady, fast fire stream independent of the shipped recruit table. This
-- config reproduces the pre-#234 curve (6 shots/s plus 1 per 50 recruits, cap 20) with no limit on
-- projectiles in flight. It is a TEST fixture only; the shipped table is Config.firing.tiers.
local Config = require("../../src/shared/Config")

local FastFire = {}

function FastFire.config(): any
	local cfg = table.clone(Config) :: any
	local tiers = {}
	for n = 0, 14 do
		table.insert(tiers, {
			minRecruits = n * Config.sectionSize,
			shotsPerSecond = 6 + n,
			speed = 67.5,
			maxInFlight = 1000,
		})
	end
	cfg.firing = { tiers = tiers, range = Config.firing.range }
	return cfg
end

return FastFire
