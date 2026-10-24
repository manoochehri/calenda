--!strict
-- Layered music logic (spec s10). Pure: no Roblox APIs, no Sound instances. A client wires the
-- results to SoundService later. Stem SoundIds are Config placeholders; empty means silent.
local Config = require("./Config")

export type Fade = {
	layer: string,
	action: "in" | "out",
	startTime: number,
	duration: number,
}
export type Plan = {
	boundary: number, -- first musical (bar) boundary at or after `now`
	fades: { Fade },
	peakSources: number, -- most stems audible at once while the plan runs
}
-- Only the fields this module reads, so tests can pass a small override.
export type Cfg = {
	musicLayerSections: { number },
	music: Config.MusicConfig,
}

-- Spec s10 layer order; index i pairs with musicLayerSections[i] and music.stemSoundIds[i].
local LAYER_NAMES: { string } = { "percussion", "brass", "ensemble", "crowd" }
-- Spec s10: never more than 4 simultaneous sources, whatever the config says.
local HARD_MAX_SOURCES = 4
local EPSILON = 1e-9

local function sourceCap(cfg: Cfg): number
	return math.min(cfg.music.maxSources, HARD_MAX_SOURCES)
end

local function layerIndex(name: string): number
	for i, n in LAYER_NAMES do
		if n == name then
			return i
		end
	end
	return 0
end

local function activeLayers(sectionCount: number, cfg: Cfg?): { string }
	local c: Cfg = cfg or (Config :: any)
	if
		type(sectionCount) ~= "number"
		or sectionCount < 0
		or sectionCount ~= math.floor(sectionCount)
	then
		error(`sectionCount must be a non-negative integer, got {sectionCount}`, 2)
	end
	local cap = sourceCap(c)
	local out = {}
	for i, threshold in c.musicLayerSections do
		if i > #LAYER_NAMES or #out >= cap then
			break
		end
		if sectionCount >= threshold then
			table.insert(out, LAYER_NAMES[i])
		end
	end
	return out
end

-- Active layers that actually have a stem id. Empty ids (the default) give an empty list: silent.
local function filterAudible(layers: { string }, c: Cfg): { string }
	local out = {}
	for _, name in layers do
		local id = c.music.stemSoundIds[layerIndex(name)]
		if id ~= nil and id ~= "" then
			table.insert(out, name)
		end
	end
	return out
end

local function audibleLayers(sectionCount: number, cfg: Cfg?): { string }
	local c: Cfg = cfg or (Config :: any)
	return filterAudible(activeLayers(sectionCount, c), c)
end

local function contains(list: { string }, name: string): boolean
	return table.find(list, name) ~= nil
end

-- Schedules layer changes on the next bar boundary. Time 0 is the start of the loop. Layers that
-- stay on are untouched. If fading in while the outgoing stems are still sounding would pass the
-- source cap, the fade-ins wait until the fade-outs finish.
local function planCrossfade(now: number, current: { string }, target: { string }, cfg: Cfg?): Plan
	local c: Cfg = cfg or (Config :: any)
	if type(now) ~= "number" or now ~= now or now < 0 or now == math.huge then
		error(`now must be a finite non-negative number, got {now}`, 2)
	end
	local cap = sourceCap(c)
	local cur = filterAudible(current, c)
	local tgtFull = filterAudible(target, c)
	local tgt = {}
	for i = 1, math.min(#tgtFull, cap) do
		tgt[i] = tgtFull[i]
	end

	local barSeconds = 60 / c.music.bpm * c.music.beatsPerBar
	local boundary = math.ceil(now / barSeconds - EPSILON) * barSeconds
	local fadeSeconds = c.music.fadeBars * barSeconds

	local outs: { string } = {}
	local ins: { string } = {}
	for _, name in cur do
		if not contains(tgt, name) then
			table.insert(outs, name)
		end
	end
	for _, name in tgt do
		if not contains(cur, name) then
			table.insert(ins, name)
		end
	end

	local union = #cur + #ins
	local sequential = union > cap
	local inStart = boundary
	if sequential and #outs > 0 then
		inStart = boundary + fadeSeconds
	end

	local fades: { Fade } = {}
	for _, name in outs do
		table.insert(
			fades,
			{ layer = name, action = "out", startTime = boundary, duration = fadeSeconds }
		)
	end
	for _, name in ins do
		table.insert(
			fades,
			{ layer = name, action = "in", startTime = inStart, duration = fadeSeconds }
		)
	end

	local peak = if sequential then math.max(#cur, #tgt) else union
	return { boundary = boundary, fades = fades, peakSources = math.min(peak, cap) }
end

return {
	activeLayers = activeLayers,
	audibleLayers = audibleLayers,
	planCrossfade = planCrossfade,
	maxSources = function(cfg: Cfg?): number
		return sourceCap(cfg or (Config :: any))
	end,
}
