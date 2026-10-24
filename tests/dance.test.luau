--!strict
local Dance = require("../src/shared/Dance")
local DanceConfig = require("../src/shared/DanceConfig")
local PuppetPose = require("../src/shared/PuppetPose")

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
		name = "intensity curve is monotonic, bounded and doubles tempo only above its configured threshold",
		run = function()
			local previous = 0
			for total = 0, 10000, 25 do
				local amplitude, tempo = Dance.intensity(total, total // 50)
				expect(
					amplitude >= 1 and amplitude <= DanceConfig.maxAmplitude,
					"amplitude out of bounds"
				)
				expect(tempo >= 1 and tempo <= 2, "tempo multiplier out of bounds")
				expect(amplitude >= previous, "amplitude curve must be monotonic")
				previous = amplitude
			end
		end,
	},
	{
		name = "gate, celebration, attack and defeat reactions decay and unknown events are inert",
		run = function()
			local gateHop = Dance.reaction("gate", 0)
			local lateHop = Dance.reaction("gate", 0.6)
			local unknownHop, unknownRoll, unknownTurn = Dance.reaction("unrelated", 0)
			local endHop = Dance.reaction("gate", 2)
			expect(gateHop > lateHop and lateHop > 0, "reaction must decay")
			expect(
				unknownHop == 0 and unknownRoll == 0 and unknownTurn == 0,
				"unknown event must not react"
			)
			expect(endHop == 0, "expired reaction must be inert")
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
