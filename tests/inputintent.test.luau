--!strict
local InputIntent = require("../src/shared/InputIntent")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function near(actual: number, expected: number, name: string)
	assert(math.abs(actual - expected) < 1e-6, `{name}: expected {expected}, got {actual}`)
end

return {
	{
		name = "keyAxis: A/left = -1, D/right = +1, both or neither = 0",
		run = function()
			eq(InputIntent.keyAxis(false, false), 0, "none")
			eq(InputIntent.keyAxis(true, false), -1, "left")
			eq(InputIntent.keyAxis(false, true), 1, "right")
			eq(InputIntent.keyAxis(true, true), 0, "both")
		end,
	},
	{
		name = "stepKeys moves at KEY_SPEED, stays within the bound, ignores a zero axis",
		run = function()
			near(InputIntent.stepKeys(0, 1, 0.5, 18.5), InputIntent.KEY_SPEED * 0.5, "right")
			near(InputIntent.stepKeys(0, -1, 0.5, 18.5), -InputIntent.KEY_SPEED * 0.5, "left")
			eq(InputIntent.stepKeys(18, 1, 1, 18.5), 18.5, "clamped right")
			eq(InputIntent.stepKeys(-18, -1, 1, 18.5), -18.5, "clamped left")
			eq(InputIntent.stepKeys(4, 0, 1, 18.5), 4, "no axis")
		end,
	},
	{
		name = "dragToX: a drag of DRAG_SPAN of the screen width crosses the whole street",
		run = function()
			local w = 1000
			local full = InputIntent.DRAG_SPAN * w
			near(InputIntent.dragToX(-20, full, w, 20), 20, "left edge to right edge")
			near(InputIntent.dragToX(0, full / 4, w, 20), 10, "quarter span")
			near(InputIntent.dragToX(5, -full / 4, w, 20), -5, "leftwards from 5")
			eq(InputIntent.dragToX(0, 10 * w, w, 18.5), 18.5, "clamped right")
			eq(InputIntent.dragToX(0, -10 * w, w, 18.5), -18.5, "clamped left")
			eq(InputIntent.dragToX(3, 0, w, 18.5), 3, "no movement")
		end,
	},
	{
		name = "dragToX is safe on a zero width or non-finite input",
		run = function()
			eq(InputIntent.dragToX(3, 50, 0, 18.5), 3, "zero width keeps the origin")
			eq(InputIntent.dragToX(3, 0 / 0, 1000, 18.5), 3, "nan drag keeps the origin")
			eq(InputIntent.dragToX(100, 0, 1000, 18.5), 18.5, "origin outside the bound is clamped")
		end,
	},
	{
		name = "shouldSend: first intent sends; tiny changes and too-frequent sends do not",
		run = function()
			local gap = 1 / InputIntent.SEND_HZ
			eq(InputIntent.shouldSend(nil, 0, 3, 0), true, "first")
			eq(InputIntent.shouldSend(3, 0, 3, 5), false, "unchanged")
			eq(InputIntent.shouldSend(3, 0, 3.01, 5), false, "below the change threshold")
			eq(InputIntent.shouldSend(3, 0, 6, gap / 2), false, "too soon")
			eq(InputIntent.shouldSend(3, 0, 6, gap), true, "changed and spaced")
		end,
	},
	{
		name = "send rate stays under the server's sustained steer limit",
		run = function()
			local Steering = require("../src/shared/Steering")
			assert(
				InputIntent.SEND_HZ < Steering.MESSAGES_PER_SECOND,
				"client sends slower than server accepts"
			)
		end,
	},
}
