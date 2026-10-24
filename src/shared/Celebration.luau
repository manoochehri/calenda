--!strict
-- Finale celebration tiers (spec s9, issue #16). Pure. The tier is how many Config.finaleThresholds
-- (provisional 50/150/300) the final crowd total reaches: 0 below the first, 3 at the last. It is
-- chosen for completed runs only; a defeated run never gets one (Amendment 1).
local Config = require("./Config")
local Strings = require("./Strings")

export type Profile = {
	dancers: number, -- party members drawn spreading across the plaza (<= visual budget)
	bursts: number, -- confetti bursts over the finale
	confettiPerBurst: number,
	gifts: number, -- gift tosses over the finale
}

-- [default] by tier 0..3. Dancers stay inside Config.visualBudget.looseAvatars; confetti is capped
-- by the shared Bits pool, so more bursts never mean more parts than Bits.MAX.
local PROFILES: { Profile } = {
	{ dancers = 8, bursts = 4, confettiPerBurst = 8, gifts = 3 },
	{ dancers = 14, bursts = 6, confettiPerBurst = 12, gifts = 5 },
	{ dancers = 20, bursts = 9, confettiPerBurst = 16, gifts = 8 },
	{ dancers = 24, bursts = 12, confettiPerBurst = 20, gifts = 12 },
}

local Celebration = {}

function Celebration.tierFor(total: any, thresholds: { number }?): number
	if type(total) ~= "number" or total ~= total or total == math.huge or total < 0 then
		return 0
	end
	local whole = math.floor(total)
	local tier = 0
	for _, threshold in thresholds or Config.finaleThresholds do
		if whole >= threshold then
			tier += 1
		end
	end
	return tier
end

function Celebration.profile(tier: number): Profile
	local clamped = math.clamp(math.floor(tier), 0, #PROFILES - 1)
	return PROFILES[clamped + 1]
end

function Celebration.banner(tier: number): string?
	return Strings.tierBanner[tier]
end

return Celebration
