--!strict
-- Issue #203: Jugar -> intro camera move -> tres, dos, uno -> the client's one Start request.
-- Start is never due before the camera move ends plus the countdown, and fires exactly once.
local okS, StartSequence = pcall(require, "../src/shared/StartSequence")
local okC, Countdown = pcall(require, "../src/shared/Countdown")
local IntroCamera = require("../src/shared/IntroCamera")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function need()
	assert(okS, `StartSequence module missing: {tostring(StartSequence)}`)
	assert(okC, `Countdown module missing: {tostring(Countdown)}`)
end

return {
	{
		name = "no word during the camera move; tres, dos, uno in order after it; then Start once",
		run = function()
			need()
			local seq = StartSequence.begin(0)
			local d = IntroCamera.DURATION
			local words: { string } = {}
			local starts = 0
			local dt = 1 / 30
			for i = 0, math.floor((d + Countdown.DURATION + 2) / dt) do
				local now = i * dt
				local f = StartSequence.step(seq, now, 0, 0, true)
				if now < d - 1e-9 then
					eq(f.word, nil, `no word at {now} during the camera move`)
				end
				if f.word and words[#words] ~= f.word then
					table.insert(words, f.word)
				end
				if f.startDue then
					starts += 1
					assert(now >= d + Countdown.DURATION - 1e-9, `Start at {now}, too early`)
				end
			end
			eq(table.concat(words, ","), "tres,dos,uno", "words in order")
			eq(starts, 1, "Start due exactly once")
		end,
	},
	{
		name = "Start is due only after camera end plus a full countdown, never before",
		run = function()
			need()
			local seq = StartSequence.begin(10)
			local d = IntroCamera.DURATION
			local floor = d + Countdown.DURATION
			local dt = 1 / 30
			local firstDue: number? = nil
			for i = 0, math.floor((floor + 3) / dt) do
				local t = i * dt
				local f = StartSequence.step(seq, 10 + t, 0, 0, true)
				if f.startDue then
					assert(firstDue == nil, "due twice")
					firstDue = t
				end
			end
			assert(firstDue ~= nil, "Start never became due")
			assert(
				(firstDue :: number) >= floor - 1e-6,
				`Start due at {firstDue}, before camera end + countdown {floor}`
			)
			assert((firstDue :: number) <= floor + 2 * dt, `Start late: {firstDue} vs {floor}`)
		end,
	},
	{
		name = "a late frame cannot skip the countdown: Start still waits for a full one",
		run = function()
			need()
			local seq = StartSequence.begin(0)
			StartSequence.step(seq, 0, 0, 0, true)
			-- one huge frame past camera end and past the whole countdown
			local f = StartSequence.step(seq, 1000, 0, 0, true)
			eq(f.startDue, false, "the countdown has not been shown yet")
			eq(f.word, "tres", "countdown begins from tres")
			local g = StartSequence.step(seq, 1000 + Countdown.DURATION, 0, 0, true)
			eq(g.startDue, true, "due once a full countdown has elapsed")
		end,
	},
	{
		name = "a missing avatar delays the whole sequence, never Start",
		run = function()
			need()
			local seq = StartSequence.begin(0)
			local floor = IntroCamera.AVATAR_WAIT + IntroCamera.DURATION + Countdown.DURATION
			local dt = 1 / 30
			local firstDue: number? = nil
			for i = 0, math.floor((floor + 3) / dt) do
				local t = i * dt
				local f = StartSequence.step(seq, t, 0, 0, false)
				if t < IntroCamera.AVATAR_WAIT - 1e-9 then
					eq(f.word, nil, "no word while waiting for the avatar")
				end
				if f.startDue and firstDue == nil then
					firstDue = t
				end
			end
			assert(firstDue ~= nil, "Start never became due")
			assert((firstDue :: number) >= floor - 1e-6, `Start at {firstDue} before {floor}`)
		end,
	},
	{
		name = "the pose during the countdown holds the settled game camera",
		run = function()
			need()
			local seq = StartSequence.begin(0)
			StartSequence.step(seq, 0, 0, 0, true)
			local f = StartSequence.step(seq, IntroCamera.DURATION + 0.5, 0, 0, true)
			local game = IntroCamera.pose(0, 0, 1)
			eq(f.pose.pz, game.pz, "pz")
			eq(f.pose.py, game.py, "py")
		end,
	},
}
