--!strict
-- The local count-in. The client owns presentation; Start is sent only after the final cue.
local StartCountdown = {}

local CUES = { "¡Tres!", "¡Dos!", "¡Uno!", "¡Vamos!" }
export type Countdown = { index: number }

function StartCountdown.new(): Countdown
	return { index = 0 }
end

function StartCountdown.cue(countdown: Countdown): string?
	return CUES[countdown.index + 1]
end

function StartCountdown.advance(countdown: Countdown): string?
	if countdown.index >= #CUES then
		return nil
	end
	countdown.index += 1
	return CUES[countdown.index]
end

function StartCountdown.shouldStart(countdown: Countdown): boolean
	return countdown.index == #CUES
end

StartCountdown.DURATION = 0.85

return StartCountdown
