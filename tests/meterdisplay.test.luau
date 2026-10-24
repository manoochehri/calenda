--!strict
local MeterDisplay = require("../src/shared/MeterDisplay")

local function near(actual: number, expected: number, name: string)
	assert(math.abs(actual - expected) < 1e-6, `{name}: expected {expected}, got {actual}`)
end

-- One pooled slot, as the client uses it: the same slot and cluster id are reused after a replay.
local function playRun(m: MeterDisplay.Meter, fills: { number })
	local first = 0
	for i, f in fills do
		local shown = m:step(1, f, 0.1, 14)
		if i == 1 then
			first = shown
		end
	end
	return first
end

return {
	{
		name = "a bound meter starts at its first target, then eases toward it",
		run = function()
			local m = MeterDisplay.new()
			near(m:step(7, 0.5, 0.1, 14), 0.5, "snaps on first bind")
			local v = m:step(7, 1, 0.1, 14)
			assert(v > 0.5 and v < 1, "eases")
		end,
	},
	{
		name = "replay twice: the same slot and id start empty again, never drain from the old fill",
		run = function()
			local m = MeterDisplay.new()
			for _ = 1, 40 do
				m:step(1, 1, 0.1, 14) -- run 1: cluster 1 ends full
			end
			m:clear() -- the pool hid the slot (cluster gone or reset)
			near(playRun(m, { 0, 0.33 }), 0, "run 2 starts empty")
			for _ = 1, 40 do
				m:step(1, 1, 0.1, 14)
			end
			m:clear()
			near(playRun(m, { 0 }), 0, "run 3 starts empty")
		end,
	},
	{
		name = "a different cluster id in the same slot also starts at its own fill",
		run = function()
			local m = MeterDisplay.new()
			m:step(1, 1, 0.1, 14)
			near(m:step(2, 0, 0.1, 14), 0, "new id snaps")
		end,
	},
}
