--!strict
local GateLabel = require("../src/shared/GateLabel")

return {
	{
		name = "add gate label includes its result",
		run = function()
			local operation, result = GateLabel.format({ kind = "add", value = 20 }, 10)
			assert(operation == "+20", "add operation")
			assert(result == "→ 30", "add result")
		end,
	},
	{
		name = "multiply gate label includes its result",
		run = function()
			local operation, result = GateLabel.format({ kind = "multiply", value = 2 }, 10)
			assert(operation == "x2", "multiply operation")
			assert(result == "→ 20", "multiply result")
		end,
	},
	{
		name = "gate label result uses the current total each time",
		run = function()
			local op: GateLabel.Op = { kind = "add", value = 20 }
			local initialOperation, initialResult = GateLabel.format(op, 10)
			local updatedOperation, updatedResult = GateLabel.format(op, 25)
			assert(initialOperation == "+20" and initialResult == "→ 30", "initial result")
			assert(updatedOperation == "+20" and updatedResult == "→ 45", "updated result")
		end,
	},
	{
		name = "gate labels reject invalid totals and operations",
		run = function()
			assert(not pcall(GateLabel.format, { kind = "add", value = 1 }, -1), "negative total")
			assert(not pcall(GateLabel.format, { kind = "loss", value = 1 }, 10), "unsupported op")
		end,
	},
}
