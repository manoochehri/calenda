--!strict
-- Pure input -> steering intent mapping (issue #10, spec s3). The client turns keys and touch drags
-- into ONE number: the lateral position it would like the lead to stand at (studs, negative =
-- left). The server clamps it, rate limits it and moves the lead (Steering, RunDriver); the client
-- never sends anything else. No Roblox APIs here.
-- Values marked [default] are tuning defaults; spec s3 gives no numbers.
local InputIntent = {}

InputIntent.KEY_SPEED = 20 -- [default] studs/second the keyboard intent slides (server max is 24)
InputIntent.DRAG_SPAN = 0.6 -- [default] a drag of this fraction of the screen width crosses the street
InputIntent.SEND_HZ = 15 -- [default] steer messages per second; below Steering.MESSAGES_PER_SECOND
InputIntent.MIN_CHANGE = 0.05 -- [default] studs; smaller changes are not worth a message
InputIntent.HINT_SECONDS = 10 -- [spec s9] 'Arrastra para moverte' during the first seconds

local function isFinite(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function clamp(x: number, bound: number): number
	return math.clamp(x, -bound, bound)
end

-- -1 for left (A / left arrow), +1 for right (D / right arrow), 0 for none or both.
function InputIntent.keyAxis(left: boolean, right: boolean): number
	if left == right then
		return 0
	end
	return if left then -1 else 1
end

-- Slides the intent while a key is held. `bound` is the furthest |x| the lead may stand at.
function InputIntent.stepKeys(x: number, axis: number, dt: number, bound: number): number
	if axis == 0 or not isFinite(dt) then
		return clamp(x, bound)
	end
	return clamp(x + axis * InputIntent.KEY_SPEED * dt, bound)
end

-- A touch drag of `dxPixels` starting from the intent `originX`. DRAG_SPAN of the screen width
-- moves the intent across the whole street (2 * bound), so one thumb swipe reaches either kerb.
function InputIntent.dragToX(
	originX: number,
	dxPixels: number,
	screenWidth: number,
	bound: number
): number
	if not isFinite(dxPixels) or not isFinite(screenWidth) or screenWidth <= 0 then
		return clamp(originX, bound)
	end
	local studsPerPixel = (2 * bound) / (InputIntent.DRAG_SPAN * screenWidth)
	return clamp(originX + dxPixels * studsPerPixel, bound)
end

-- Stateless send policy: send when the intent moved enough and the last send is old enough.
-- A change held back by the rate limit is still a change on the next frame, so nothing is lost.
function InputIntent.shouldSend(lastX: number?, lastAt: number, x: number, now: number): boolean
	if lastX == nil then
		return true
	end
	if math.abs(x - lastX) < InputIntent.MIN_CHANGE then
		return false
	end
	return now - lastAt >= 1 / InputIntent.SEND_HZ
end

-- Spec s9: shown in the first seconds, gone once the player steers or the run ends.
function InputIntent.hintVisible(runTime: number, hasSteered: boolean, over: boolean): boolean
	return not hasSteered and not over and runTime < InputIntent.HINT_SECONDS
end

return InputIntent
