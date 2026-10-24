--!strict
local FollowerSpring = require("../src/shared/FollowerSpring")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function simulate(dt: number, seconds: number, omega: number, zeta: number): (number, number)
	local pos, vel, peak = 0, 0, 0
	for _ = 1, math.floor(seconds / dt) do
		pos, vel = FollowerSpring.step(pos, vel, 10, 0, dt, omega, zeta)
		peak = math.max(peak, pos)
	end
	return pos, peak
end

return {
	{
		name = "settles on a fixed target",
		run = function()
			local pos = simulate(1 / 60, 3, 10, 0.7)
			assert(math.abs(pos - 10) < 0.01, `ended at {pos}`)
		end,
	},
	{
		name = "overshoot stays bounded for the follower damping range",
		run = function()
			for _, zeta in { 0.5, 0.7, 1, 2 } do
				local _, peak = simulate(1 / 60, 3, 12, zeta)
				assert(peak <= 10 * 1.2, `zeta {zeta} overshoot to {peak}`)
			end
		end,
	},
	{
		name = "stable at large and erratic dt: finite, never past the starting error",
		run = function()
			for _, dt in { 0.016, 0.1, 0.25, 0.5, 1, 10, 1000 } do
				local pos, vel = 0, 0
				for _ = 1, 20 do
					pos, vel = FollowerSpring.step(pos, vel, 10, 0, dt, 13, 0.5)
					assert(pos == pos and vel == vel, `NaN at dt {dt}`)
					assert(math.abs(pos) < 20 and math.abs(vel) < 200, `blew up at dt {dt}: {pos}`)
				end
			end
		end,
	},
	{
		name = "extreme omega is clamped rather than exploding",
		run = function()
			local pos, vel = FollowerSpring.step(0, 0, 10, 0, 0.1, 1e6, 0.5)
			assert(pos == pos and math.abs(pos) < 30 and math.abs(vel) < 2000, "finite")
		end,
	},
	{
		name = "feed-forward: a target moving at constant speed leaves no steady lag",
		run = function()
			local target, pos, vel = 0, 0, 16
			for _ = 1, 240 do
				target += 16 / 60
				pos, vel = FollowerSpring.step(pos, vel, target, 16, 1 / 60, 9, 0.7)
			end
			assert(math.abs(pos - target) < 0.01, `lag {target - pos}`)
		end,
	},
	{
		name = "different omegas lag differently after a sudden lateral shift (ripple)",
		run = function()
			local function after(omega: number): number
				local pos, vel = 0, 0
				for _ = 1, 6 do
					pos, vel = FollowerSpring.step(pos, vel, 10, 0, 1 / 60, omega, 0.7)
				end
				return pos
			end
			assert(after(13) > after(8) + 0.05, "stiffer follower is ahead")
		end,
	},
	{
		name = "zero or negative dt changes nothing",
		run = function()
			local p, v = FollowerSpring.step(3, 2, 10, 0, 0, 10, 0.7)
			eq(p, 3, "pos")
			eq(v, 2, "vel")
			p, v = FollowerSpring.step(3, 2, 10, 0, -1, 10, 0.7)
			eq(p, 3, "pos neg")
		end,
	},
}
