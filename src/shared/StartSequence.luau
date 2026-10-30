--!strict
-- Issue #203: Jugar -> intro camera move (IntroCamera, #177) -> "tres, dos, uno" (Countdown) ->
-- the client's one payload-free Start request. This is the single place that decides when Start is
-- due, so it can never fire before the camera move ends plus the countdown. Client presentation
-- only: the server still starts the run on that request and owns all authority.
local Countdown = require("./Countdown")
local IntroCamera = require("./IntroCamera")

local StartSequence = {}

local TIME_EPS = 1e-9 -- float slack when comparing two os.clock() differences

export type Sequence = { intro: IntroCamera.Intro, countdownAt: number?, startSent: boolean }
export type Frame = {
	pose: IntroCamera.Pose, -- the camera for this frame
	word: string?, -- the numeral word to show, nil outside the countdown
	look: Countdown.Look?, -- its scale and opacity, nil outside the countdown
	startDue: boolean, -- true on exactly one frame: send Start now
}

function StartSequence.begin(now: number): Sequence
	return { intro = IntroCamera.begin(now), countdownAt = nil, startSent = false }
end

-- One frame. The countdown begins on the frame the camera move reports it has settled, and Start
-- is due Countdown.DURATION later, so a long frame cannot skip any of it.
function StartSequence.step(
	seq: Sequence,
	now: number,
	leadX: number,
	leadZ: number,
	avatarReady: boolean
): Frame
	local pose, moveDone = IntroCamera.step(seq.intro, now, leadX, leadZ, avatarReady)
	if moveDone and seq.countdownAt == nil then
		seq.countdownAt = now
	end
	local started = seq.countdownAt
	if started == nil then
		return { pose = pose, word = nil, look = nil, startDue = false }
	end
	local elapsed = now - started
	local startDue = false
	if elapsed >= Countdown.DURATION - TIME_EPS and not seq.startSent then
		seq.startSent = true
		startDue = true
	end
	local word = Countdown.wordAt(elapsed)
	return {
		pose = pose,
		word = word,
		look = if word then Countdown.visual(elapsed) else nil,
		startDue = startDue,
	}
end

return StartSequence
