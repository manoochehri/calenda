--!strict
-- Owner report: gift lobs were far too frequent. The gift share over the shot stream must be about
-- one in 100 shots, with a dancer section present (the only time gifts are thrown). Pinned over a
-- large deterministic sample so the share is a measured number, not an eyeballed one.
local Config = require("../src/shared/Config")
local Targeting = require("../src/shared/Targeting")

local SAMPLE_SHOTS = 10000 -- shots 1..10000, a deterministic schedule, so the sample is exact
local SECTIONS = 3 -- a dancer section is present (3rd logical section tosses gifts)
local TARGET_SHARE = 1 / 100
local TOLERANCE = 0.002 -- accept 0.8% to 1.2%; the deterministic schedule gives exactly 1%

return {
	{
		name = "gift share is about 1 in 100 shots over 10000 shots with a dancer section",
		run = function()
			local gifts = 0
			for n = 1, SAMPLE_SHOTS do
				if Targeting.shotKind(n, SECTIONS) == "gift" then
					gifts += 1
				end
			end
			local share = gifts / SAMPLE_SHOTS
			assert(
				math.abs(share - TARGET_SHARE) <= TOLERANCE,
				`gift share {share} over {SAMPLE_SHOTS} shots (gifts {gifts}, every {Config.giftEveryNthShot}th shot) is outside {TARGET_SHARE} +/- {TOLERANCE}`
			)
		end,
	},
}
