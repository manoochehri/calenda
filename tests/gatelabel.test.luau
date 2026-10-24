--!strict
local GateLabel = require("../src/shared/GateLabel")

return {
	{
		name = "add gate label includes its result",
		run = function()
			assert(GateLabel.format({ kind = "add", value = 20 }, 10) == "+20 → 30")
		end,
	},
	{
		name = "multiply gate label includes its result",
		run = function()
			assert(GateLabel.format({ kind = "multiply", value = 2 }, 10) == "x2 → 20")
		end,
	},
	{
		name = "gate label result uses the current total each time",
		run = function()
			local op = { kind = "add" :: const, value = 20 }
			assert(GateLabel.format(op, 10) == "+20 → 30")
			assert(GateLabel.format(op, 25) == "+20 → 45")
		end,
	},
	{
		name = "gate labels reject invalid totals and operations",
		run = function()
			assert(not pcall(GateLabel.format, { kind = "add", value = 1 }, -1))
			assert(not pcall(GateLabel.format, { kind = "loss", value = 1 }, 10))
		end,
	},
}
