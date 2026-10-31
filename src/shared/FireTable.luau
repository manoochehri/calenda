--!strict
-- Issue #234 (owner rule 2026-10-31): the player's projectile speed and fire rate reflect how many
-- parade people are recruited. One table, `Config.firing.tiers`, maps a recruit count to
-- (shots per second, projectile speed, most projectiles in flight at once). Row 0 has
-- maxInFlight = 1: the initial player fires ONE projectile at a time, and the next shot waits until
-- the current one has resolved (see Targeting). Pure: no Roblox APIs. The server owns the lookup;
-- the client only draws the speed the server used.
local Config = require("./Config")

export type Tier =
	{ minRecruits: number, shotsPerSecond: number, speed: number, maxInFlight: number }

local FireTable = {}

local function check(recruits: any)
	if type(recruits) ~= "number" or recruits ~= recruits or recruits < 0 then
		error(`recruits must be a non-negative number, got {tostring(recruits)}`, 3)
	end
end

-- The highest row whose minRecruits is at or below `recruits` (rows are ascending).
function FireTable.tier(recruits: number, config: any?): Tier
	check(recruits)
	local tiers: { Tier } = (config or Config).firing.tiers
	local row = tiers[1]
	for _, t in tiers do
		if t.minRecruits <= recruits then
			row = t
		else
			break
		end
	end
	return row
end

function FireTable.rate(recruits: number, config: any?): number
	return FireTable.tier(recruits, config).shotsPerSecond
end

function FireTable.speed(recruits: number, config: any?): number
	return FireTable.tier(recruits, config).speed
end

function FireTable.maxInFlight(recruits: number, config: any?): number
	return FireTable.tier(recruits, config).maxInFlight
end

-- The highest rate in the table (the last row, since rows never decrease); sizes the client pools.
function FireTable.maxRate(config: any?): number
	local tiers: { Tier } = (config or Config).firing.tiers
	return tiers[#tiers].shotsPerSecond
end

return FireTable
