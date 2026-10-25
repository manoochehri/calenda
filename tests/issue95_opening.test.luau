--!strict
local Countdown = require("../src/shared/StartCountdown")
local DebugLayout = require("../src/shared/DebugLayout")

local function eq(actual: any, expected: any, label: string)
	assert(actual == expected, `{label}: expected {tostring(expected)}, got {tostring(actual)}`)
end

return {
	{
		name = "count-in cues are Spanish, ordered, and Start is withheld until Vamos",
		run = function()
			local countdown = Countdown.new()
			eq(Countdown.cue(countdown), "¡Tres!", "first cue")
			eq(Countdown.advance(countdown), "¡Dos!", "second cue")
			eq(Countdown.advance(countdown), "¡Uno!", "third cue")
			eq(Countdown.advance(countdown), "¡Vamos!", "go cue")
			eq(Countdown.advance(countdown), nil, "only one start cue")
			eq(Countdown.shouldStart(countdown), true, "start after go")
		end,
	},
	{
		name = "the route walks from a starting plaza into the street and reaches the separate finale plaza after a 90 second street",
		run = function()
			assert(DebugLayout.startPlazaEnd > 0, "starting plaza must be part of the authored route")
			assert(DebugLayout.startPlazaEnd < DebugLayout.plazaStart, "street follows starting plaza")
			assert(DebugLayout.plazaStart < DebugLayout.streetLength, "ending plaza remains distinct")
			eq((DebugLayout.plazaStart - DebugLayout.startPlazaEnd) / require("../src/shared/Config").speed, 90, "street duration")
		end,
	},
}
