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
	{
		name = "disabled recorder never reads the clock or emits, and is a shared no-op",
		run = function()
			local clockCalls, emits = 0, 0
			local function counting(): number
				clockCalls += 1
				return clockCalls
			end
			local trace = StartupTiming.new(false, 0, counting, function()
				emits += 1
			end)
			local startedAt = trace:begin()
			trace:span("x", startedAt)
			trace:mark("y")
			trace:recordDuration("z", 0, 1)
			trace:setStartAt(-1)
			eq(trace:measure("m", function()
				return 7
			end), 7, "measure result")
			eq(trace:has("y"), false, "has")
			eq(trace:finish("timeout"), false, "finish")
			eq(trace.enabled, false, "enabled flag")
			eq(clockCalls, 0, "clock calls")
			eq(emits, 0, "emit calls")
		end,
	},
	{
		name = "has is a set lookup and begin/span record a duration",
		run = function()
			local now = 1
			local output: { string } = {}
			local trace = StartupTiming.new(true, 1, function()
				return now
			end, function(line)
				table.insert(output, line)
			end)
			eq(trace.enabled, true, "enabled flag")
			local startedAt = trace:begin()
			now = 1.75
			trace:span("GateView.new", startedAt)
			eq(trace:has("GateView.new"), true, "has recorded")
			eq(trace:has("other"), false, "has missing")
			trace:finish()
			assert(string.find(output[1], "GateView.new (0.750s)", 1, true), output[1])
		end,
	},
	{
		name = "partial report prints once with the reason and the labels still missing",
		run = function()
			local output: { string } = {}
			local trace = StartupTiming.new(true, 0, function()
				return 2
			end, function(line)
				table.insert(output, line)
			end)
			trace:mark("WorldBuilder built")
			eq(trace:finish("timeout after 30s"), true, "first")
			eq(trace:finish("again"), false, "second")
			eq(#output, 1, "output count")
			assert(string.find(output[1], "INCOMPLETE: timeout after 30s", 1, true), output[1])
		end,
	},
}
