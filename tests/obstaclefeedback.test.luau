--!strict
local DebugLayout = require("../src/shared/DebugLayout")
local ObstacleFeedback = require("../src/shared/ObstacleFeedback")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local obstacle = DebugLayout.obstacles[1]

local function event(id: number, before: number?, after: number?): any
	return { kind = "obstacle", id = id, before = before, after = after }
end

return {
	{
		name = "the first obstacle event plays: puffs at the obstacle, peelers to its sidewalk",
		run = function()
			local fb = ObstacleFeedback.new(DebugLayout)
			local plan = fb:handle(event(obstacle.id, 60, 50))
			assert(plan ~= nil, "plays")
			eq(plan.id, obstacle.id, "id")
			eq(plan.z, obstacle.z, "z")
			eq(plan.side, obstacle.side, "side")
			eq(plan.puffs, ObstacleFeedback.PUFFS, "puffs")
			eq(plan.peelers, ObstacleFeedback.PEEL_MAX, "peelers capped")
			assert(#plan.sidewalkX == plan.peelers, "one sidewalk spot per peeler")
			for _, x in plan.sidewalkX do
				eq(x > 0, obstacle.side == "right", "on the obstacle's side")
				assert(math.abs(x) > DebugLayout.halfWidth - 6, "on the sidewalk, off the road")
			end
		end,
	},
	{
		name = "a second event for the same obstacle plays nothing",
		run = function()
			local fb = ObstacleFeedback.new(DebugLayout)
			assert(fb:handle(event(obstacle.id, 60, 50)) ~= nil, "first plays")
			eq(fb:handle(event(obstacle.id, 50, 40)), nil, "second is ignored")
			eq(fb:handle(event(obstacle.id, 60, 50)), nil, "third is ignored")
		end,
	},
	{
		name = "a new run (reset) lets the obstacle play again",
		run = function()
			local fb = ObstacleFeedback.new(DebugLayout)
			assert(fb:handle(event(obstacle.id, 60, 50)) ~= nil, "first")
			fb:reset()
			assert(fb:handle(event(obstacle.id, 60, 50)) ~= nil, "after replay")
		end,
	},
	{
		name = "few followers means few peelers; none means none (no injury, no crash)",
		run = function()
			local fb = ObstacleFeedback.new(DebugLayout)
			local plan = fb:handle(event(obstacle.id, 2, 0))
			assert(plan ~= nil, "plays")
			eq(plan.peelers, 2, "two followers, two peelers")
			fb:reset()
			local none = fb:handle(event(obstacle.id, 0, 0))
			assert(none ~= nil, "plays")
			eq(none.peelers, 0, "no followers, no peelers")
			eq(none.puffs, ObstacleFeedback.PUFFS, "dust still bursts")
		end,
	},
	{
		name = "unknown ids, wrong kinds and junk are ignored and do not consume a dedupe slot",
		run = function()
			local fb = ObstacleFeedback.new(DebugLayout)
			local junk: { any } = {
				"x",
				{},
				{ kind = "gate", id = obstacle.id },
				{ kind = "obstacle", id = 9999 },
				{ kind = "obstacle", id = 0 / 0 },
				{ kind = "obstacle" },
			}
			for i, p in junk do
				eq(fb:handle(p), nil, `junk {i}`)
			end
			assert(fb:handle(event(obstacle.id, 60, 50)) ~= nil, "real one still plays")
		end,
	},
}
