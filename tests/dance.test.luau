--!strict
local Dance = require("../src/shared/Dance")
local DanceConfig = require("../src/shared/DanceConfig")
local PuppetPose = require("../src/shared/PuppetPose")
local DancerPose = require("../src/shared/DancerPose")
local GloboPose = require("../src/shared/GloboPose")

local function expect(ok: boolean, message: string)
	if not ok then
		error(message, 2)
	end
end

return {
	{
		name = "beat clock phase and four bar cycle are deterministic",
		run = function()
			local beat = Dance.beatAt(1, 120)
			expect(
				beat.index == 2 and math.abs(beat.phase) < 1e-9,
				"one second at 120 BPM is beat 2"
			)
			local cycle = Dance.cycleAt(8, 120)
			expect(cycle.bar == 1 and cycle.beatInBar == 1, "eight seconds starts bar 1")
			local afterCycle = Dance.cycleAt(16, 120)
			expect(
				afterCycle.bar == 1 and afterCycle.section == "verse",
				"16 seconds wraps the 4-bar cycle"
			)
		end,
	},
	{
		name = "follower variants are stable and pose offsets stay within configured joint bounds",
		run = function()
			local a = Dance.variant(431)
			local b = Dance.variant(431)
			expect(a == b, "same follower must always choose the same move")
			local seen = {}
			for id = 1, 100 do
				seen[Dance.variant(id)] = true
			end
			local variety = 0
			for _ in seen do
				variety += 1
			end
			expect(variety > 1, "different follower ids should select varied moves")
			for _, move in DanceConfig.moves do
				for i = 0, 15 do
					local _, sway, arm = Dance.pose(move, i, 1)
					expect(math.abs(arm) <= DanceConfig.maxJointRadians, "arm exceeded joint limit")
					expect(
						math.abs(sway) <= DanceConfig.maxJointRadians,
						"sway exceeded joint limit"
					)
				end
			end
		end,
	},
	{
		name = "presentation pose buffers can be reused without allocating a pose per frame",
		run = function()
			local puppet = {
				headBob = 0,
				headTilt = 0,
				armLeft = 0,
				armRight = 0,
				clap = 0,
				sway = 0,
				bow = 0,
			}
			local dancer =
				{ hop = 0, footL = 0, footR = 0, swirl = 0, flare = 0, sway = 0, armSwing = 0 }
			local globo = { spin = 0, tiltX = 0, tiltZ = 0, lift = 0, carrierStep = 0 }
			expect(
				PuppetPose.into(puppet, 1, 0) == puppet,
				"puppet buffer identity must be retained"
			)
			expect(
				DancerPose.into(dancer, 1, 0) == dancer,
				"dancer buffer identity must be retained"
			)
			expect(GloboPose.into(globo, 1, 0) == globo, "globo buffer identity must be retained")
		end,
	},
	{
		name = "intensity grows monotonically while dance pace stays fixed at every crowd size",
		run = function()
			local previous = 0
			for total = 0, 10000, 25 do
				local amplitude, tempo = Dance.intensity(total, total // 50)
				expect(
					amplitude >= 1 and amplitude <= DanceConfig.maxAmplitude,
					"amplitude out of bounds"
				)
				expect(tempo == 1, `tempo must stay constant at total {total}`)
				expect(amplitude >= previous, "amplitude curve must be monotonic")
				previous = amplitude
			end
		end,
	},
	{
		name = "crossing the former high-intensity threshold keeps the same dance pace without a phase jump",
		run = function()
			local bpm = 120
			local time = 5.123
			local dt = 1 / 60
			local below: number? = nil
			local above: number? = nil
			for total = 0, 10000 do
				local _, _, intensity = Dance.intensity(total, total // 50)
				if intensity < 0.72 then
					below = total
				elseif above == nil then
					above = total
					break
				end
			end
			expect(below ~= nil and above ~= nil, "the former intensity boundary must be exercised")
			local _, tempoBefore = Dance.intensity(below :: number, (below :: number) // 50)
			local _, tempoAfter = Dance.intensity(above :: number, (above :: number) // 50)
			expect(
				tempoBefore == 1 and tempoAfter == 1,
				"dance pace stays constant across the boundary"
			)
			local before = Dance.beatAt(time * tempoBefore, bpm)
			local after = Dance.beatAt((time + dt) * tempoAfter, bpm)
			local beforeBeats = before.index + before.phase
			local afterBeats = after.index + after.phase
			local expectedAdvance = dt * bpm / 60
			expect(
				math.abs((afterBeats - beforeBeats) - expectedAdvance) < 1e-6,
				`crossing the threshold must advance by {expectedAdvance} beat(s), got {afterBeats - beforeBeats}`
			)
		end,
	},
	{
		name = "gate, celebration, attack and defeat reactions decay and unknown events are inert",
		run = function()
			local gateHop = Dance.reaction("conversion", 0)
			local lateHop = Dance.reaction("conversion", 0.6)
			local unknownHop, unknownRoll, unknownTurn = Dance.reaction("unrelated", 0)
			local endHop = Dance.reaction("conversion", 2)
			expect(gateHop > lateHop and lateHop > 0, "reaction must decay")
			expect(
				unknownHop == 0 and unknownRoll == 0 and unknownTurn == 0,
				"unknown event must not react"
			)
			expect(endHop == 0, "expired reaction must be inert")
		end,
	},
	{
		name = "finale pose is full-out at each bar downbeat and stays within configured bounds",
		run = function()
			for _, beat in { 0, 4, 8, 12 } do
				local hop, sway, arm, spin = Dance.pose("finale", beat, DanceConfig.maxAmplitude)
				expect(hop >= DanceConfig.maxHopStuds, `finale hop is full at downbeat {beat}`)
				expect(
					arm >= DanceConfig.maxArmRadians * 0.6,
					`finale arms rise at downbeat {beat}`
				)
				expect(math.abs(sway) <= DanceConfig.maxJointRadians, "finale sway is bounded")
				expect(math.abs(spin) <= DanceConfig.maxJointRadians, "finale spin is bounded")
			end
		end,
	},
	{
		name = "section choreography adds a four bar puppet bow and chorus arm rise",
		run = function()
			local verse = PuppetPose.pose(1, 0)
			local chorus = PuppetPose.pose(4, 0) -- 8 beats at 120 BPM
			local downbeat = PuppetPose.pose(8, 0) -- 16 beats, start of the next four-bar phrase
			expect(verse.bow == 0, "verse should not bow mid-phrase")
			expect(chorus.armLeft > verse.armLeft, "chorus raises the puppet arms")
			expect(downbeat.bow > 0, "puppet bows on the phrase downbeat")
		end,
	},
}
