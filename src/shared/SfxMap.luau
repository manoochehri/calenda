--!strict
-- Sound effect mapping (issue #62). Pure: event kind -> sound slot, how loud and how varied a
-- slot sounds at an intensity, a per-slot cooldown limiter and a bounded voice picker. The client
-- (SfxPlayer) owns the Sound instances; with empty Config.sfx ids nothing is created or played.
local Config = require("./Config")

export type Cfg = { sfx: { [string]: string }, audio: { [string]: any }, sectionSize: number? }
export type Limiter = { last: { [string]: number } }

local SfxMap = {}

SfxMap.SLOTS = table.freeze({
	"gatePop", -- a math gate is crossed
	"convert", -- spectators join the parade
	"sparkle", -- the +N counter pops
	"shotLaunch", -- a note, heart or snack leaves the lead
	"shotImpact", -- it lands on a spectator group
	"obstacleThud", -- the parade bumps an obstacle
	"attackBonk", -- an unconverted group reaches the parade
	"followerHit", -- the parade loses followers to a horde (ADR 0006)
	"sectionRise", -- a new section forms
	"finalePeak", -- the plaza finale
	"defeatBreakup", -- the party breaks up
	"replayClick", -- the replay button
})

local function conf(cfg: Cfg?): Cfg
	return cfg or (Config :: any)
end

local function clamp01(v: number): number
	if v ~= v then
		return 0
	end
	return math.clamp(v, 0, 1)
end

-- Slots for a server Event payload, or {} for anything unknown or malformed.
function SfxMap.forEvent(payload: any): { string }
	if type(payload) ~= "table" then
		return {}
	end
	local kind = payload.kind
	if kind == "gate" then
		return { "gatePop" }
	elseif kind == "obstacle" then
		return { "obstacleThud" }
	elseif kind == "cluster" then
		return { "shotLaunch", "shotImpact" }
	elseif kind == "attack" then
		return { "attackBonk", "followerHit" }
	elseif kind == "complete" then
		return { "finalePeak" }
	elseif kind == "defeated" then
		return { "defeatBreakup" }
	elseif kind == "replay" then
		return { "replayClick" }
	end
	return {}
end

-- Slots for the crowd total changing between frames: followers joined (a conversion or a gate),
-- plus the section rise when a whole-section boundary is crossed upward. Losses play nothing here.
function SfxMap.forTotalChange(prev: number, new: number, cfg: Cfg?): { string }
	local out = {}
	if type(prev) ~= "number" or type(new) ~= "number" or prev ~= prev or new ~= new then
		return out
	end
	if new <= prev then
		return out
	end
	table.insert(out, "convert")
	table.insert(out, "sparkle")
	local size = conf(cfg).sectionSize or 50
	if new // size > prev // size then
		table.insert(out, "sectionRise")
	end
	return out
end

-- True only when the slot is known and has a non-empty id: empty is silent.
function SfxMap.playable(slot: string, cfg: Cfg?): boolean
	if table.find(SfxMap.SLOTS, slot) == nil then
		return false
	end
	local id = conf(cfg).sfx[slot]
	return type(id) == "string" and id ~= ""
end

-- Sound.Volume for a slot at an intensity: the slot's base volume scaled up with the parade,
-- never above audio.sfx.maxVolume.
function SfxMap.volume(slot: string, intensity: number, cfg: Cfg?): number
	local s = conf(cfg).audio.sfx
	local base = s.volumes[slot]
	if base == nil then
		return 0
	end
	local scale = s.volumeMin + (s.volumeMax - s.volumeMin) * clamp01(intensity)
	return math.clamp(base * scale, 0, s.maxVolume)
end

-- Sound.PlaybackSpeed: 1 +/- a spread that grows with intensity. `roll` is a random 0..1.
function SfxMap.speed(intensity: number, roll: number, cfg: Cfg?): number
	local s = conf(cfg).audio.sfx
	local spread = s.pitchMin + (s.pitchMax - s.pitchMin) * clamp01(intensity)
	return math.clamp(1 + (clamp01(roll) * 2 - 1) * spread, 0.5, 2)
end

-- A Sound.SoundId from what the owner pasted: bare digits become rbxassetid://digits, anything
-- else (already a URI) is kept, empty or non-string is "" (silent).
function SfxMap.assetUri(id: any): string
	if type(id) ~= "string" then
		return ""
	end
	local trimmed = string.match(id, "^%s*(.-)%s*$") or ""
	if string.match(trimmed, "^%d+$") then
		return "rbxassetid://" .. trimmed
	end
	return trimmed
end

function SfxMap.limiter(): Limiter
	return { last = {} }
end

-- True (and remembers `now`) when the slot is off cooldown; false drops the request.
function SfxMap.admit(lim: Limiter, slot: string, now: number, cfg: Cfg?): boolean
	local cd = conf(cfg).audio.sfx.cooldowns[slot]
	if cd == nil then
		return false
	end
	local last = lim.last[slot]
	if last ~= nil and now - last < cd then
		return false
	end
	lim.last[slot] = now
	return true
end

-- Index of a free voice in 1..cap (busy[i] is the time it frees up), or nil when all are busy:
-- a sound is never stolen, so the number of playing Sounds can never pass `cap`.
function SfxMap.pick(busy: { number }, now: number, cap: number): number?
	for i = 1, cap do
		local until_ = busy[i]
		if until_ == nil or until_ <= now then
			return i
		end
	end
	return nil
end

return SfxMap
