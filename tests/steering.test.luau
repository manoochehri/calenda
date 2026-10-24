--!strict
local Steering = require("../src/shared/Steering")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

return {
	{
		name = "bound leaves an edge margin inside the street half width",
		run = function()
			eq(Steering.bound(20), 20 - Steering.EDGE_MARGIN, "bound")
			eq(Steering.bound(1), 0, "never negative")
		end,
	},
	{
		name = "clampTarget clamps both ways and rejects non-finite",
		run = function()
			eq(Steering.clampTarget(5, 18), 5, "inside")
			eq(Steering.clampTarget(1e9, 18), 18, "high")
			eq(Steering.clampTarget(-1e9, 18), -18, "low")
			eq(Steering.clampTarget(0 / 0, 18), nil, "nan")
			eq(Steering.clampTarget(math.huge, 18), nil, "inf")
		end,
	},
	{
		name = "step moves toward the target at the capped lateral speed and never overshoots",
		run = function()
			local x = Steering.step(0, 100, 0.5, 10)
			eq(x, 5, "capped move")
			eq(Steering.step(0, -100, 0.5, 10), -5, "left")
			eq(Steering.step(4, 5, 0.5, 10), 5, "reaches target exactly")
			eq(Steering.step(5, 5, 1, 10), 5, "at target")
			eq(Steering.step(0, 100, 0, 10), 0, "zero dt")
		end,
	},
	{
		name = "limiter allows a burst then refuses until tokens refill",
		run = function()
			local l = Steering.newLimiter(10, 3)
			eq(l.allow(0), true, "1")
			eq(l.allow(0), true, "2")
			eq(l.allow(0), true, "3")
			eq(l.allow(0), false, "burst spent")
			eq(l.allow(0.05), false, "half a token")
			eq(l.allow(0.1), true, "one token back")
			eq(l.allow(0.1), false, "spent again")
			eq(l.allow(10), true, "long wait refills")
			eq(l.allow(10), true, "refill capped to burst 1")
			eq(l.allow(10), true, "refill capped to burst 2")
			eq(l.allow(10), false, "refill capped to burst 3")
		end,
	},
	{
		name = "limiter rejects non-finite or backwards time and a flood stays bounded",
		run = function()
			local l = Steering.newLimiter(10, 2)
			eq(l.allow(0 / 0), false, "nan")
			eq(l.allow(math.huge), false, "inf")
			eq(l.allow("1" :: any), false, "string")
			eq(l.allow(5), true, "ok")
			eq(l.allow(4), false, "backwards time refused")
			local accepted = 0
			for _ = 1, 1000 do
				if l.allow(5) then
					accepted += 1
				end
			end
			assert(accepted <= 2, `flood at one instant accepted {accepted}`)
			local steady = Steering.newLimiter(10, 2)
			local n = 0
			for i = 0, 999 do
				if steady.allow(i * 0.001) then -- 1000 msgs over one second
					n += 1
				end
			end
			assert(n <= 2 + 10 + 1, `1 second flood accepted {n}`)
		end,
	},
}
