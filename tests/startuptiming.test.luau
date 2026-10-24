--!strict
local StartupTiming = require("../src/shared/StartupTiming")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {expected}, got {actual}`)
end

local function clock(values: { number }): () -> number
	local index = 0
	return function()
		index += 1
		return values[index] or values[#values]
	end
end

return {
	{
		name = "disabled trace runs measured work without logging",
		run = function()
			local output: { string } = {}
			local trace = StartupTiming.new(false, 0, clock({ 1, 2 }), function(line)
				table.insert(output, line)
			end)
			local result = trace:measure("require module", function()
				return 42
			end)
			eq(result, 42, "result")
			trace:mark("first state")
			trace:finish()
			eq(#output, 0, "output count")
		end,
	},
	{
		name = "enabled trace records durations and emits once",
		run = function()
			local now = 10
			local output: { string } = {}
			local trace = StartupTiming.new(true, now, function()
				return now
			end, function(line)
				table.insert(output, line)
			end)
			trace:mark("script start", now)
			now = 10.25
			local result = trace:measure("require Config", function()
				now += 0.5
				return "config"
			end)
			eq(result, "config", "measured result")
			trace:mark("first state", 11)
			eq(trace:finish(), true, "first finish")
			eq(trace:finish(), false, "second finish")
			eq(#output, 1, "output count")
			assert(string.find(output[1], "script start", 1, true))
			assert(string.find(output[1], "require Config", 1, true))
			assert(string.find(output[1], "0.500", 1, true))
			assert(string.find(output[1], "first state", 1, true))
		end,
	},
	{
		name = "baseline can move earlier before the one-time report",
		run = function()
			local now = 5
			local output: { string } = {}
			local trace = StartupTiming.new(true, now, function()
				return now
			end, function(line)
				table.insert(output, line)
			end)
			trace:setStartAt(4)
			trace:mark("client script start", 4)
			trace:finish()
			assert(string.find(output[1], "+0.000s client script start", 1, true))
		end,
	},
}
