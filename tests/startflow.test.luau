--!strict
local progressOk, StartupProgress = pcall(require, "../src/shared/StartupProgress")
local flowOk, StartFlow = pcall(require, "../src/shared/StartFlow")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

return {
	{
		name = "startup progress is based on registered work and reaches 1 only when every task finishes",
		run = function()
			assert(progressOk, `StartupProgress module missing: {tostring(StartupProgress)}`)
			local p = StartupProgress.new({ "client", "street", "world", "server" })
			eq(StartupProgress.fraction(p), 0, "starts at zero")
			StartupProgress.report(p, "client", 1)
			StartupProgress.report(p, "street", 0.5)
			eq(StartupProgress.fraction(p), 0.375, "completed task fractions")
			StartupProgress.report(p, "street", 1)
			StartupProgress.report(p, "world", 1)
			eq(StartupProgress.fraction(p), 0.75, "server task still pending")
			StartupProgress.report(p, "server", 1)
			eq(StartupProgress.fraction(p), 1, "all tasks complete")
		end,
	},
	{
		name = "startup progress clamps, rejects bad reports, and never moves backward",
		run = function()
			assert(progressOk, `StartupProgress module missing: {tostring(StartupProgress)}`)
			local p = StartupProgress.new({ "street" })
			StartupProgress.report(p, "street", 0.4)
			StartupProgress.report(p, "street", 0.2)
			StartupProgress.report(p, "missing", 1)
			StartupProgress.report(p, "street", 0 / 0)
			eq(StartupProgress.fraction(p), 0.4, "progress stays at the last valid report")
			StartupProgress.report(p, "street", 2)
			eq(StartupProgress.fraction(p), 1, "progress is bounded")
		end,
	},
	{
		name = "the title waits for both real loading completion and the server ready State",
		run = function()
			assert(flowOk, `StartFlow module missing: {tostring(StartFlow)}`)
			local f = StartFlow.new()
			StartFlow.serverPhase(f, "ready")
			eq(f.phase, "loading", "server ready before local loading")
			StartFlow.progress(f, 1)
			eq(f.phase, "title", "title after both gates")
		end,
	},
	{
		name = "Play is accepted once and the state flow keeps results and replay distinct",
		run = function()
			assert(flowOk, `StartFlow module missing: {tostring(StartFlow)}`)
			local f = StartFlow.new()
			StartFlow.progress(f, 1)
			StartFlow.serverPhase(f, "ready")
			eq(StartFlow.play(f), true, "first Play")
			eq(StartFlow.play(f), false, "duplicate Play")
			StartFlow.serverPhase(f, "over")
			eq(f.phase, "results", "finished run")
			eq(StartFlow.replay(f), true, "Replay remains available")
			eq(f.phase, "playing", "replay enters play")
		end,
	},
	{
		name = "music updates in the server ready window after local Play, but not on the title",
		run = function()
			assert(flowOk, `StartFlow module missing: {tostring(StartFlow)}`)
			local f = StartFlow.new()
			StartFlow.progress(f, 1)
			StartFlow.serverPhase(f, "ready")
			eq(StartFlow.shouldUpdateMusic(f), false, "title stays silent")
			StartFlow.play(f)
			eq(f.phase, "playing", "local Play accepted")
			eq(
				StartFlow.shouldUpdateMusic(f),
				true,
				"ready State can update music during the opening move"
			)
			StartFlow.serverPhase(f, "ready")
			eq(
				StartFlow.shouldUpdateMusic(f),
				true,
				"server ready State after Jugar keeps music updating"
			)
			StartFlow.serverPhase(f, "over")
			eq(StartFlow.shouldUpdateMusic(f), false, "results are not the ready window")
		end,
	},
	{
		name = "invalid server phases cannot unlock Play",
		run = function()
			assert(flowOk, `StartFlow module missing: {tostring(StartFlow)}`)
			local f = StartFlow.new()
			StartFlow.progress(f, 1)
			StartFlow.serverPhase(f, "fake")
			eq(f.phase, "loading", "bad phase ignored")
			eq(StartFlow.play(f), false, "Play remains locked")
		end,
	},
}
