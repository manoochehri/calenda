--!strict
local Formation = require("../src/shared/Formation")
local ParadeTail = require("../src/shared/ParadeTail")

return {
	{
		name = "parade tail is the deepest drawn loose follower or section representative",
		run = function()
			for _, total in { 0, 24, 49, 50, 300, 10000 } do
				local formation = Formation.forTotal(total)
				local expected = 0
				for _, slot in formation.slots do
					expected = math.max(expected, -slot.dz)
				end
				for _, slot in formation.sections do
					expected = math.max(expected, -slot.dz)
				end
				assert(
					ParadeTail.depth(total) == expected,
					`total {total}: expected tail {expected}, got {ParadeTail.depth(total)}`
				)
			end
		end,
	},
	{
		name = "bad crowd totals are rejected",
		run = function()
			assert(not pcall(ParadeTail.depth, -1), "negative total accepted")
			assert(not pcall(ParadeTail.depth, 1.5), "fractional total accepted")
		end,
	},
}
