--!strict
-- Audio intensity (issue #62, owner: "as the parade gets bigger the sound should be bigger").
-- Pure: no Roblox APIs. One curve maps the crowd (followers and whole sections) to 0..1, and the
-- helpers below turn that single number into everything a client plays: music master gain,
-- four-stem weights, single-track SoundEffect settings, crowd ambience volume. Every output is
-- bounded, so a huge crowd cannot blow out the mix. Smoothing over time (slew) is here too so a
-- client can never click: it moves intensity and volumes by at most a rate per second.
-- Tunables are Config.audio (AudioTuning.luau); every function takes an optional override table.
local Config = require("./Config")

export type Cfg = { audio: { [string]: any }, sectionSize: number? }
export type Effects = {
	reverbDecay: number,
	reverbWet: number,
	reverbDry: number,
	chorusMix: number,
	chorusDepth: number,
	chorusRate: number,
	eqLow: number,
	eqMid: number,
	eqHigh: number,
	compThreshold: number,
	compMakeup: number,
	compAttack: number,
	compRelease: number,
}

local AudioIntensity = {}

local function conf(cfg: Cfg?): Cfg
	return cfg or (Config :: any)
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v
end

local function clamp01(v: number): number
	if v ~= v then
		return 0
	end
	return math.clamp(v, 0, 1)
end

local function lerp(range: { number }, t: number): number
	return range[1] + (range[2] - range[1]) * t
end

local function smoothstep(t: number): number
	local c = clamp01(t)
	return c * c * (3 - 2 * c)
end

-- ln(1 + x / ref) / ln(1 + full / ref), clamped to 0..1: 0 at x = 0, 1 at x = full and beyond.
local function logCurve(x: number, ref: number, full: number): number
	if not finite(x) or x <= 0 then
		return 0
	end
	if x >= full then
		return 1
	end
	return math.log(1 + x / ref) / math.log(1 + full / ref)
end

-- Crowd size -> 0..1. Logarithmic, so 10 -> 100 -> 1000 each sound like a step up and 10,000 is
-- the top. `sectionCount` adds a little (sectionWeight) so the milestone sections register; the
-- partial section is interpolated from `total`, so the curve has no jump when a section completes.
function AudioIntensity.target(total: number, sectionCount: number, cfg: Cfg?): number
	local c = conf(cfg)
	local a = c.audio
	local size = c.sectionSize or 50
	local t = if finite(total) then math.max(total, 0) else 0
	local s = if finite(sectionCount) then math.max(sectionCount, 0) else 0
	local part = clamp01((t - s * size) / size)
	local fromTotal = logCurve(total, a.refTotal, a.fullTotal)
	local fromSections = logCurve(s + part, 1, a.fullSections)
	if total == math.huge then
		fromSections = 1
	end
	local w = a.sectionWeight
	return clamp01((1 - w) * fromTotal + w * fromSections)
end

-- Moves `current` toward `target` by at most rise/fall per second. dt <= 0 holds the value.
function AudioIntensity.slew(
	current: number,
	target: number,
	dt: number,
	rise: number,
	fall: number
): number
	if not finite(dt) or dt <= 0 or not finite(target) then
		return current
	end
	if target > current then
		return math.min(target, current + rise * dt)
	end
	return math.max(target, current - fall * dt)
end

-- The finale's FinalePlan.at(t).musicIntensity overrides the crowd's intensity upward only.
function AudioIntensity.withPeak(base: number, peak: number?): number
	if peak == nil or not finite(peak) or peak <= 0 then
		return base
	end
	return math.max(base, clamp01(peak))
end

-- Music master gain (a multiplier on the music volume ceiling): a gentle swell, never above 1.
function AudioIntensity.masterGain(intensity: number, cfg: Cfg?): number
	local a = conf(cfg).audio
	return math.min(1, lerp({ a.masterMin, a.masterMax }, smoothstep(intensity)))
end

-- Four-stem mode: the level of stem `index` (1 percussion .. 4 crowd) once the section gate lets
-- it sound. Percussion is always full; the others start at layerFloor and grow to 1 as
-- intensity passes layerStart, over layerWidth.
function AudioIntensity.layerWeight(index: number, intensity: number, cfg: Cfg?): number
	local a = conf(cfg).audio
	local floor = a.layerFloor[index]
	if floor == nil then
		return 0
	end
	if index == 1 then
		return 1
	end
	local grow = smoothstep((clamp01(intensity) - a.layerStart[index]) / a.layerWidth)
	return floor + (1 - floor) * grow
end

-- Single-track mode: SoundEffect property values for an intensity, all inside the documented
-- ranges (docs/audio-setup.md lists them with sources). CompressorSoundEffect.Ratio is left alone:
-- its range is not documented (UNVERIFIED).
function AudioIntensity.effects(intensity: number, cfg: Cfg?): Effects
	local e = conf(cfg).audio.effects
	local t = smoothstep(intensity)
	return {
		reverbDecay = lerp(e.reverbDecay, t),
		reverbWet = lerp(e.reverbWet, t),
		reverbDry = e.reverbDry,
		chorusMix = lerp(e.chorusMix, t),
		chorusDepth = lerp(e.chorusDepth, t),
		chorusRate = e.chorusRate,
		eqLow = lerp(e.eqLow, t),
		eqMid = lerp(e.eqMid, t),
		eqHigh = lerp(e.eqHigh, t),
		compThreshold = lerp(e.compThreshold, t),
		compMakeup = lerp(e.compMakeup, t),
		compAttack = e.compAttack,
		compRelease = e.compRelease,
	}
end

-- Gain (<= 1) that takes back the loudness the single-track effects add (mid lift and makeup).
function AudioIntensity.compensation(e: Effects): number
	local boost = math.max(0, e.eqMid) + math.max(0, e.compMakeup)
	return math.min(1, 10 ^ (-boost / 20))
end

-- Crowd ambience volume: silent with no followers, rising on the same log curve to its ceiling.
function AudioIntensity.crowdLoopVolume(total: number, cfg: Cfg?): number
	local a = conf(cfg).audio
	return a.sfx.crowdLoopVolume * logCurve(total, a.refTotal, a.fullTotal)
end

return AudioIntensity
