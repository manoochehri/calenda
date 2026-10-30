--!strict
-- Issue #203: the Spanish count-in "tres, dos, uno" shown after the intro camera move (#177) and
-- before the client's single Start request. Pure timing and numeral look; the client draws it
-- (src/client/CountdownView). No flashing, strobe or brightness animation (#85, #171): a numeral
-- eases its opacity and scale in and out over FADE seconds (>= 0.25 s) and never pulses the screen.
-- Values marked [default] are tuning defaults; the feel is UNVERIFIED on device.
local Countdown = {}

Countdown.WORDS = table.freeze({ "tres", "dos", "uno" })
Countdown.STEP = 0.9 -- [default] seconds each word stays up
Countdown.FADE = 0.3 -- [default] seconds of each ease in and ease out; at least 0.25 s
Countdown.DURATION = Countdown.STEP * #Countdown.WORDS
Countdown.ENTER_SCALE = 1.35 -- [default] a numeral eases down from this size to 1

export type Look = { scale: number, opacity: number }

local function smoothstep(u: number): number
	local c = math.clamp(u, 0, 1)
	return c * c * (3 - 2 * c)
end

-- The word up `elapsed` seconds after the countdown began; nil before it and after "uno".
function Countdown.wordAt(elapsed: number): string?
	if elapsed < 0 or elapsed >= Countdown.DURATION then
		return nil
	end
	return Countdown.WORDS[math.floor(elapsed / Countdown.STEP) + 1]
end

-- The numeral's scale and opacity `elapsed` seconds after the countdown began. Opacity eases in
-- over FADE and out over the last FADE of each step; scale eases from ENTER_SCALE to 1 while it
-- fades in and holds at 1 after.
function Countdown.visual(elapsed: number): Look
	local local_ = elapsed % Countdown.STEP
	local fadeIn = smoothstep(local_ / Countdown.FADE)
	local fadeOut = smoothstep((Countdown.STEP - local_) / Countdown.FADE)
	return {
		scale = Countdown.ENTER_SCALE + (1 - Countdown.ENTER_SCALE) * fadeIn,
		opacity = math.min(fadeIn, fadeOut),
	}
end

return Countdown
