--!strict
-- Hit feedback envelopes (issue #50): the wobble on the crowd counter and a short decaying screen shake,
-- driven by one tiny state that an "attack" Event restarts. Pure and capped:
-- no matter how many attacks arrive, nothing exceeds the MAX_* values. Hits are playful but
-- impactful (Amendment 1): quick and bouncy, never lingering.
local HitFeedback = {}

HitFeedback.JOLT_SECONDS = 0.4 -- [default]
HitFeedback.SHAKE_SECONDS = 0.45 -- [default]
HitFeedback.MAX_JOLT_SCALE = 0.3 -- [default] extra bar scale at the peak
HitFeedback.MAX_SHAKE_STUDS = 1.2 -- [default] camera offset at the peak
HitFeedback.SHAKE_HZ = 22 -- [default]
HitFeedback.MIN_INTENSITY = 0.35 -- [default] even a small hit is visible
HitFeedback.INTENSITY_GAIN = 6 -- [default] share of the crowd lost -> intensity

local function decay(age: number, seconds: number): number
	if age < 0 or age >= seconds then
		return 0
	end
	local k = 1 - age / seconds
	return k * k
end

function HitFeedback.jolt(age: number): number
	return decay(age, HitFeedback.JOLT_SECONDS)
end

function HitFeedback.shakeScale(age: number): number
	return decay(age, HitFeedback.SHAKE_SECONDS)
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- 0..1 from the followers a hit took (ADR 0006: the crowd total is the life bar); missing or odd
-- numbers give the floor.
function HitFeedback.intensity(before: any, after: any): number
	if not (finite(before) and finite(after)) or before <= 0 then
		return HitFeedback.MIN_INTENSITY
	end
	local share = math.max(0, before - after) / before
	return math.clamp(share * HitFeedback.INTENSITY_GAIN, HitFeedback.MIN_INTENSITY, 1)
end

export type Sample = {
	jolt: number, -- extra scale, 0..MAX_JOLT_SCALE
	shakeX: number, -- studs, camera space
	shakeY: number,
	flash: number, -- retained for the shared sample shape; always zero
}
export type Tracker = {
	hit: (self: Tracker, intensity: number) -> (),
	step: (self: Tracker, dt: number) -> (),
	sample: (self: Tracker) -> Sample,
	reset: (self: Tracker) -> (),
}

function HitFeedback.new(): Tracker
	local age = math.huge
	local strength = 0
	local self = {} :: Tracker

	function self.hit(_, intensity: number)
		local i = if finite(intensity) then math.clamp(intensity, 0, 1) else 0
		-- A new hit restarts the clock but never weakens what is still playing.
		local remaining = strength * HitFeedback.shakeScale(age)
		strength = math.max(i, remaining)
		age = 0
	end

	function self.step(_, dt: number)
		if finite(dt) and dt > 0 then
			age += dt
		end
	end

	function self.sample(_): Sample
		local s = strength
		local shake = HitFeedback.shakeScale(age) * s * HitFeedback.MAX_SHAKE_STUDS
		local wave = age * HitFeedback.SHAKE_HZ * math.pi * 2
		return {
			jolt = HitFeedback.jolt(age) * s * HitFeedback.MAX_JOLT_SCALE,
			shakeX = if shake == 0 then 0 else shake * math.sin(wave),
			shakeY = if shake == 0 then 0 else shake * math.cos(wave * 0.8),
			flash = 0,
		}
	end

	function self.reset(_)
		age, strength = math.huge, 0
	end

	return self
end

return HitFeedback
