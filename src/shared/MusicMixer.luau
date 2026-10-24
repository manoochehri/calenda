--!strict
-- Pure layered-music mixer (spec s10, issue #21). Turns the section count and a local clock into a
-- gain per stem layer; a client only copies the numbers onto Sound.Volume. No Roblox APIs, no
-- Sound instances. Which layers are on and when fades start comes from MusicLayers (bar
-- boundaries, source cap, silence without stem ids); this module owns the per-layer ramp state so
-- a change in the middle of a fade continues from the current level instead of jumping.
-- Time is seconds on a local clock whose 0 is the moment the stems were started together.
local Config = require("./Config")
local MusicLayers = require("./MusicLayers")

export type Ramp = { from: number, to: number, start: number, duration: number }
export type Mixer = {
	cfg: MusicLayers.Cfg,
	sections: number?, -- last section count scheduled; nil until set
	target: { string }, -- audible layers the schedule is heading to
	ramps: { [string]: Ramp },
}

local MusicMixer = {}

MusicMixer.LAYER_VOLUME = 0.5 -- [default] Sound.Volume of one layer at full gain (controlled ceiling)
MusicMixer.PEAK_BOOST = 0.3 -- [default] up to +30% at the finale's music peak

local LAYER_NAMES: { string } = { "percussion", "brass", "ensemble", "crowd" }

function MusicMixer.new(cfg: MusicLayers.Cfg?): Mixer
	return {
		cfg = cfg or (Config :: any),
		sections = nil,
		target = {},
		ramps = {},
	}
end

local function rampGain(r: Ramp, t: number): number
	if t <= r.start then
		return r.from
	end
	if t >= r.start + r.duration then
		return r.to
	end
	return r.from + (r.to - r.from) * ((t - r.start) / r.duration)
end

-- Layers that get a Sound: those with a stem id, at most MusicLayers.maxSources (4).
function MusicMixer.soundLayers(m: Mixer): { string }
	local out = {}
	local cap = MusicLayers.maxSources(m.cfg)
	for i, name in LAYER_NAMES do
		local id = m.cfg.music.stemSoundIds[i]
		if id ~= nil and id ~= "" and #out < cap then
			table.insert(out, name)
		end
	end
	return out
end

-- Schedules the layers for `sectionCount`, starting at the next bar boundary after `now`.
function MusicMixer.setSections(m: Mixer, sectionCount: number, now: number)
	if m.sections == sectionCount then
		return
	end
	m.sections = sectionCount
	local goal = MusicLayers.audibleLayers(sectionCount, m.cfg)
	local plan = MusicLayers.planCrossfade(now, m.target, goal, m.cfg)
	m.target = goal
	for _, f in plan.fades do
		local old = m.ramps[f.layer]
		-- Start from wherever the layer will be at the fade's start (continues a fade in progress).
		local from = if old then rampGain(old, f.startTime) else 0
		m.ramps[f.layer] = {
			from = from,
			to = if f.action == "in" then 1 else 0,
			start = f.startTime,
			duration = f.duration,
		}
	end
end

-- Gain 0..1 per layer name at local time `t`.
function MusicMixer.gains(m: Mixer, t: number): { [string]: number }
	local out: { [string]: number } = {}
	for _, name in LAYER_NAMES do
		local r = m.ramps[name]
		out[name] = if r then math.clamp(rampGain(r, t), 0, 1) else 0
	end
	return out
end

-- Silence everything and forget the schedule (replay). The next setSections schedules afresh.
function MusicMixer.reset(m: Mixer)
	m.sections = nil
	m.target = {}
	m.ramps = {}
end

-- Sound.Volume for a layer gain, with the finale "music peak" intensity (0..1) lifting it slightly.
function MusicMixer.volume(gain: number, peakIntensity: number): number
	local g = math.clamp(gain, 0, 1)
	local p = math.clamp(peakIntensity, 0, 1)
	return MusicMixer.LAYER_VOLUME * g * (1 + MusicMixer.PEAK_BOOST * p)
end

-- FinalePlan.at(t).musicIntensity runs 0.5 -> 1 across the finale; the lift starts from nothing
-- (0 at 0.5 or below, 1 at the top) so the peak does not jump the volume when the finale begins.
function MusicMixer.peakAmount(musicIntensity: number): number
	return math.clamp((musicIntensity - 0.5) / 0.5, 0, 1)
end

return MusicMixer
