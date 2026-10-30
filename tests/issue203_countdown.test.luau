--!strict
-- Issue #203: the Spanish count-in "tres, dos, uno" as pure data. It is shown after the intro
-- camera move and before the client's single Start request. No flashing (#85, #171): numerals
-- change scale and opacity along eased ramps of at least 0.25 s.
local okC, Countdown = pcall(require, "../src/shared/Countdown")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

return {
	{
		name = "the words are tres, dos, uno in that order",
		run = function()
			assert(okC, `Countdown module missing: {tostring(Countdown)}`)
			eq(table.concat(Countdown.WORDS, ","), "tres,dos,uno", "words")
		end,
	},
	{
		name = "the word shown follows elapsed time: tres, dos, uno, then nothing",
		run = function()
			assert(okC, `Countdown module missing: {tostring(Countdown)}`)
			local s = Countdown.STEP
			eq(Countdown.wordAt(0), "tres", "t=0")
			eq(Countdown.wordAt(s * 0.99), "tres", "end of first step")
			eq(Countdown.wordAt(s), "dos", "second step")
			eq(Countdown.wordAt(s * 2), "uno", "third step")
			eq(Countdown.wordAt(s * 2.99), "uno", "end of third step")
			eq(Countdown.wordAt(s * 3), nil, "after uno")
			eq(Countdown.wordAt(-1), nil, "before the start")
		end,
	},
	{
		name = "total duration is the words times the step, and each step is readable (>= 0.6 s)",
		run = function()
			assert(okC, `Countdown module missing: {tostring(Countdown)}`)
			eq(Countdown.DURATION, Countdown.STEP * 3, "duration")
			assert(Countdown.STEP >= 0.6, "readable step")
		end,
	},
	{
		name = "numerals ramp opacity and scale over at least 0.25 s, never a hard pop",
		run = function()
			assert(okC, `Countdown module missing: {tostring(Countdown)}`)
			assert(Countdown.FADE >= 0.25, `fade {Countdown.FADE} s is under 0.25 s`)
			assert(Countdown.FADE * 2 <= Countdown.STEP, "fade in and out fit in one step")
			local first = Countdown.visual(0)
			eq(first.opacity, 0, "starts invisible")
			local last = Countdown.visual(Countdown.STEP - 1e-6)
			assert(last.opacity < 0.01, "ends invisible")
			-- No frame changes opacity faster than a 0.25 s full ramp allows (x2 for easing slope).
			local dt = 1 / 60
			local prev = Countdown.visual(0)
			for i = 1, math.floor(Countdown.DURATION / dt) do
				local v = Countdown.visual(i * dt)
				assert(
					math.abs(v.opacity - prev.opacity) <= dt / 0.25 * 2 + 1e-9,
					`opacity jumps at {i * dt}`
				)
				assert(v.opacity >= 0 and v.opacity <= 1, "opacity in range")
				assert(v.scale > 0.5 and v.scale < 2, "scale stays modest")
				prev = v
			end
			local mid = Countdown.visual(Countdown.STEP / 2)
			eq(mid.opacity, 1, "fully visible mid-step")
			eq(mid.scale, 1, "settled scale mid-step")
		end,
	},
}
