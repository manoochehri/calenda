--!strict
local RunView = require("../src/shared/RunView")
local Strings = require("../src/shared/Strings")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function state(over: { [string]: any }?): any
	local s: { [string]: any } = { t = 4, z = 64, x = 2, total = 10, best = 0, over = false }
	for k, v in over or {} do
		s[k] = v
	end
	return s
end

return {
	{
		name = "the Spanish strings are the spec's",
		run = function()
			eq(Strings.hint, "Arrastra para moverte", "hint")
			eq(Strings.replay, "¡Otra calenda!", "replay")
			eq(Strings.defeated, "¡Se acabó la fiesta!", "defeated")
		end,
	},
	{
		name = "hud: exact total, loose count and sections for 10, 120 and 10,000",
		run = function()
			local a = RunView.hud(state({ total = 10 }))
			eq(a.counter, "10", "counter at 10")
			eq(a.detail, "Sueltos 10 · Secciones 0", "detail at 10")
			local b = RunView.hud(state({ total = 120 }))
			eq(b.counter, "120", "counter at 120")
			eq(b.detail, "Sueltos 20 · Secciones 2", "detail at 120")
			local c = RunView.hud(state({ total = 10000 }))
			eq(c.counter, "10000", "counter at 10,000 is exact")
			eq(c.detail, "Sueltos 0 · Secciones 200", "detail at 10,000")
		end,
	},
	{
		name = "hud: the end of the run comes from state.over and outcome alone",
		run = function()
			eq(RunView.hud(state()).showEnd, false, "running")
			local done =
				RunView.hud(state({ over = true, outcome = "completed", score = 95, best = 95 }))
			eq(done.showEnd, true, "completed shows the end")
			eq(done.endTitle, Strings.completed, "completed title")
			eq(done.score, "Puntos: 95", "score")
			eq(done.best, "Mejor: 95", "best")
			local lost = RunView.hud(state({ over = true, outcome = "defeated", score = 30 }))
			eq(lost.endTitle, Strings.defeated, "defeated title")
			local odd = RunView.hud(state({ over = true, outcome = "mystery", total = 7 }))
			eq(odd.showEnd, true, "unknown outcome still ends")
			eq(odd.score, "Puntos: 7", "falls back to the total when there is no score")
		end,
	},
	{
		name = "hud tolerates a broken total instead of erroring every frame",
		run = function()
			eq(RunView.hud(state({ total = -3 })).counter, "0", "negative")
			eq(RunView.hud(state({ total = 12.7 })).counter, "12", "fractional")
		end,
	},
	{
		name = "leadPosition extrapolates z and t between states, but not once over",
		run = function()
			local x, z, t = RunView.leadPosition(state({ z = 64, t = 4 }), 0.05, 16, 1440)
			eq(x, 2, "x")
			assert(math.abs(z - 64.8) < 1e-9, `z {z}`)
			assert(math.abs(t - 4.05) < 1e-9, `t {t}`)
			local _, zOver, tOver =
				RunView.leadPosition(state({ z = 1440, t = 90, over = true }), 5, 16, 1440)
			eq(zOver, 1440, "frozen z")
			eq(tOver, 90, "frozen t")
			local _, zCap = RunView.leadPosition(state({ z = 1439, t = 89.9 }), 1, 16, 1440)
			eq(zCap, 1440, "never past the plaza")
			local _, zLate = RunView.leadPosition(state(), 99, 16, 1440)
			assert(
				zLate <= 64 + 16 * RunView.MAX_EXTRAPOLATION + 1e-9,
				"stale state is not extrapolated for long"
			)
		end,
	},
	{
		name = "isNewRun: time going backwards means a replay reset",
		run = function()
			eq(RunView.isNewRun(nil, 0), true, "first state")
			eq(RunView.isNewRun(30, 0.1), true, "replay")
			eq(RunView.isNewRun(30, 30.1), false, "normal")
			eq(RunView.isNewRun(30, 30), false, "same")
		end,
	},
}
