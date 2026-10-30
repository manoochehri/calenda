--!strict
-- Crowd feel layer (issue #178). Pure: numbers in, numbers out, no Roblox APIs. Everything here
-- is display only. The server still decides every hit, credit, crowd total and the 10% loss rule;
-- the client only turns the server's total changes into a cheer or a flinch. Tunables live in
-- CrowdFeelConfig. Every envelope below is a single bump that starts and ends at rest, so nothing
-- flashes or repeats: a join hops once, a cheer hops once, a flinch dips once.
local FollowerSlots = require("./FollowerSlots")
local CrowdFeelConfig = require("./CrowdFeelConfig")

local C = CrowdFeelConfig
local CrowdFeel = {}

local function finite(x: number): boolean
	return x == x and x ~= math.huge and x ~= -math.huge
end

-- A seeded per-follower offset in beats, in [0, BREATH_SPREAD_BEATS]. The same follower always
-- breathes at the same offset, so the crowd reads as individuals rather than one pulse.
function CrowdFeel.breathPhase(id: number): number
	return FollowerSlots.unit(id, 71) * C.BREATH_SPREAD_BEATS
end

-- A follower who has just joined: one hop up and a squash on the landing frame (squash shrinks
-- height, so it is returned as a positive share). Returns (hop studs, squash share).
function CrowdFeel.join(age: number): (number, number)
	if not finite(age) or age < 0 or age >= C.JOIN_SECONDS then
		return 0, 0
	end
	local k = age / C.JOIN_SECONDS
	return C.JOIN_HOP * math.sin(math.pi * k), C.JOIN_SQUASH * (1 - k) * (1 - k)
end

-- The parade cheers on a gain: one hop, returning to the ground.
function CrowdFeel.cheer(age: number): number
	if not finite(age) or age < 0 or age >= C.CHEER_SECONDS then
		return 0
	end
	return C.CHEER_HOP * math.sin(math.pi * age / C.CHEER_SECONDS)
end

-- The parade flinches on a loss: a short dip with a squash, returning to rest.
-- Returns (hop studs, squash share).
function CrowdFeel.flinch(age: number): (number, number)
	if not finite(age) or age < 0 or age >= C.FLINCH_SECONDS then
		return 0, 0
	end
	local s = math.sin(math.pi * age / C.FLINCH_SECONDS)
	return -C.FLINCH_DIP * s, C.FLINCH_SQUASH * s
end

-- The clock time a cheer or flinch bump starts at. A total change while that bump is still running
-- keeps its start, so rapid conversions never snap it back to rest and rise again (issue #178).
-- Once the bump has ended, a new change starts a new one.
function CrowdFeel.startBump(startAt: number, now: number, seconds: number): number
	if finite(startAt) and now >= startAt and now - startAt < seconds then
		return startAt
	end
	return now
end

local function clamp(x: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, x))
end

-- Every active feel term summed and clamped. Returns (hop studs, scaleY, scaleXZ) where the
-- XZ scale keeps the volume roughly constant (scaleXZ = 1 / sqrt(scaleY)).
function CrowdFeel.combine(
	joinAge: number,
	cheerAge: number,
	flinchAge: number
): (number, number, number)
	local jh, js = CrowdFeel.join(joinAge)
	local fh, fs = CrowdFeel.flinch(flinchAge)
	local hop = clamp(jh + CrowdFeel.cheer(cheerAge) + fh, C.MIN_HOP, C.MAX_HOP)
	local squash = clamp(js + fs, 0, C.MAX_SQUASH)
	local sy = 1 - squash
	return hop, sy, 1 / math.sqrt(sy)
end

return CrowdFeel
