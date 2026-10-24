--!strict
local Smoke = require("../src/shared/Smoke")

return {
	{
		name = "harness loads a src/shared module",
		run = function()
			assert(Smoke.add(2, 3) == 5, "expected 2 + 3 == 5")
		end,
	},
}
