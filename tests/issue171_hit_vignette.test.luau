--!strict
-- Issue #171: hit feedback must not flash the screen.
local HitFeedback = require("../src/shared/HitFeedback")

return {
	{
		name = "hits never produce a screen flash",
		run = function()
			local fx = HitFeedback.new()
			for _ = 1, 120 do
				fx:hit(1)
				assert(fx:sample().flash == 0, "hit flash must remain disabled")
				fx:step(1 / 60)
			end
		end,
	},
}
