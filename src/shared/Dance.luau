--!strict
-- Shared pure timing, move catalogue and parade-size dance scaling (issue #75).
local AudioIntensity = require("./AudioIntensity")
local Config = require("./Config")
local DanceConfig = require("./DanceConfig")
local FollowerSlots = require("./FollowerSlots")

export type Beat = { index: number, phase: number }
export type Cycle = { beat: number, bar: number, beatInBar: number, section: string }

local Dance = {}
local TAU = 2 * math.pi

local function positiveBpm(bpm: number): number
	return if type(bpm) == "number" and bpm > 0 and bpm < math.huge then bpm else Config.music.bpm
end

function Dance.beatAt(time: number, bpm: number?): Beat
	local safeTime = if type(time) == "number" and time == time then math.max(0, time) else 0
	local beats = safeTime * positiveBpm(bpm or Config.music.bpm) / 60
	local index = math.floor(beats)
	return { index = index, phase = beats - index }
end

function Dance.cycleAt(time: number, bpm: number?): Cycle
	local beat = Dance.beatAt(time, bpm)
	local cycleBeat = beat.index % DanceConfig.cycleBeats
	local beatInBar = cycleBeat % Config.music.beatsPerBar + 1
	local bar = cycleBeat // Config.music.beatsPerBar + 1
	return {
		beat = cycleBeat + 1,
		bar = bar,
		beatInBar = beatInBar,
		section = if bar >= DanceConfig.chorusStartsAtBar then "chorus" else "verse",
	}
end

function Dance.variant(id: number): string
	local index = math.floor(FollowerSlots.unit(id, 7501) * #DanceConfig.moves) + 1
	return DanceConfig.moves[index]
end

function Dance.intensity(total: number, sections: number): (number, number, number)
	local value = AudioIntensity.target(total, sections)
	local amplitude = 1 + (DanceConfig.maxAmplitude - 1) * value
	local tempo = if value >= DanceConfig.doubleTempoAt then 2 else 1
	return amplitude, tempo, value
end

-- A compact shared pose record for the loose-follower catalogue. All rotations remain inside
-- DanceConfig limits, including the high-intensity parade state.
function Dance.pose(move: string, beat: number, amplitude: number): (number, number, number, number)
	local amp = math.clamp(amplitude, 0, DanceConfig.maxAmplitude)
	local wave = math.sin(TAU * beat / 4)
	local downbeat = math.cos(TAU * beat)
	local hop = 0
	local sway = 0
	local arm = 0
	local spin = 0
	if move == "bounceSway" then
		hop = math.abs(wave) * DanceConfig.maxHopStuds
		sway = wave * DanceConfig.maxSwayRadians
		arm = wave * DanceConfig.maxArmRadians * 0.45
	elseif move == "sideStep" then
		hop = math.max(0, wave) * DanceConfig.maxHopStuds * 0.6
		sway = wave * DanceConfig.maxSwayRadians
		arm = -wave * DanceConfig.maxArmRadians * 0.7
	elseif move == "spinTwirl" then
		hop = math.abs(wave) * DanceConfig.maxHopStuds * 0.7
		spin = DanceConfig.maxSpinRadians * math.sin(math.pi * beat / 4)
		sway = wave * DanceConfig.maxSwayRadians * 0.5
	elseif move == "armsUp" then
		hop = math.max(0, downbeat) * DanceConfig.maxHopStuds
		arm = DanceConfig.maxArmRadians * (0.55 + 0.45 * downbeat)
		sway = wave * DanceConfig.maxSwayRadians * 0.4
	elseif move == "clap" then
		arm = DanceConfig.maxArmRadians * (0.4 + 0.4 * math.max(0, downbeat))
		hop = math.max(0, downbeat) * DanceConfig.maxHopStuds * 0.35
		sway = wave * DanceConfig.maxSwayRadians * 0.55
	elseif move == "finale" then
		-- The plaza finale is a sustained full-out party. Each bar's first beat lands a
		-- synchronized jump and arm lift; the body turns and sways between those downbeats.
		local barPulse = math.cos(TAU * beat / Config.music.beatsPerBar)
		hop = DanceConfig.maxHopStuds * (0.65 + 0.35 * math.max(0, barPulse))
		arm = DanceConfig.maxArmRadians * (0.7 + 0.3 * math.max(0, barPulse))
		sway = wave * DanceConfig.maxSwayRadians
		spin = DanceConfig.maxSpinRadians * math.sin(TAU * beat / 8)
	else -- march, and safe fallback for a malformed move key
		hop = math.abs(wave) * DanceConfig.maxHopStuds * 0.5
		arm = wave * DanceConfig.maxArmRadians * 0.3
	end
	return math.clamp(hop * amp, 0, DanceConfig.maxHopStuds * DanceConfig.maxAmplitude),
		math.clamp(sway * amp, -DanceConfig.maxJointRadians, DanceConfig.maxJointRadians),
		math.clamp(arm * amp, -DanceConfig.maxJointRadians, DanceConfig.maxJointRadians),
		math.clamp(spin * amp, -DanceConfig.maxJointRadians, DanceConfig.maxJointRadians)
end

-- Distance LOD keeps only a single step wave and disables arm/spin details for a far figure.
function Dance.lowDetailPose(beat: number): (number, number, number, number)
	local step = math.sin(math.pi * beat / 2)
	return math.abs(step) * DanceConfig.maxHopStuds * DanceConfig.farAmplitude,
		step * DanceConfig.maxSwayRadians * DanceConfig.farAmplitude,
		0,
		0
end

-- Small event accent shared by the parade. `age` is local elapsed seconds; unknown events are inert.
-- Returns hop, roll and turn values without allocating per-frame records.
function Dance.reaction(kind: string, age: number): (number, number, number)
	if type(age) ~= "number" or age < 0 or age >= 1.2 then
		return 0, 0, 0
	end
	local fade = 1 - age / 1.2
	if kind == "gate" then
		return DanceConfig.maxHopStuds * fade, 0, 0
	elseif kind == "conversion" then
		return DanceConfig.maxHopStuds * 1.1 * fade, 0, DanceConfig.maxSpinRadians * 0.5 * fade
	elseif kind == "attack" then
		return -DanceConfig.maxHopStuds * 0.45 * fade, DanceConfig.maxSwayRadians * fade, 0
	elseif kind == "complete" then
		return DanceConfig.maxHopStuds * 1.1 * fade, 0, DanceConfig.maxSpinRadians * fade
	elseif kind == "defeated" then
		return -DanceConfig.maxHopStuds * 0.65 * fade, -DanceConfig.maxSwayRadians * fade, 0
	end
	return 0, 0, 0
end

return Dance
