--!strict
-- Active play has no screen-text overlay; ending/world presentation remains separate.
local fs = require("@lune/fs")
local ScreenLayout = require("../src/shared/ScreenLayout")
local RunView = require("../src/shared/RunView")
local RunFlow = require("../src/shared/RunFlow")
local Results = require("../src/shared/Results")

return {
	{
		name = "issue 160: every supported phone aspect leaves the whole active-play safe area free of HUD text",
		run = function()
			for _, aspect in ScreenLayout.ASPECTS do
				local safe = ScreenLayout.safeRect(aspect)
				assert(safe.w > 0 and safe.h > 0, aspect.name)
				for _, element in ScreenLayout.ELEMENTS do
					assert(
						not element.phases.run,
						`{aspect.name}: {element.name} still overlays active play`
					)
				end
			end
		end,
	},
	{
		name = "issue 160: no active-play count bindings survive; final score and ending flow still work",
		run = function()
			for _, total in { 0, 10, 49, 50, 120, 10000 } do
				local state = { total = total, over = false, best = 0 }
				local flow = RunFlow.new()
				RunFlow.step(flow, state, 0)
				local view = RunView.hud(state :: any) :: any
				assert(
					view.counter == nil and view.detail == nil,
					"obsolete gameplay count bindings remain"
				)
				assert(
					not view.showEnd and RunFlow.banner(flow) == nil,
					"running has no end overlay"
				)
				local final = {
					total = total,
					score = total,
					over = true,
					outcome = "completed",
					best = total,
				}
				RunFlow.step(flow, final, 0)
				if total >= 50 then
					assert(RunFlow.banner(flow) ~= nil, "preserve ending-only celebration")
				end
				RunFlow.step(flow, final, 100)
				local result = Results.apply(RunView.hud(final :: any), final, flow)
				assert(
					result.showEnd and result.score == tostring(total),
					"exact final score survives"
				)
			end
		end,
	},
	{
		name = "issue 160: an overwhelmed parade retains defeat feedback and a zero final result",
		run = function()
			local state = { total = 0, score = 0, over = true, outcome = "defeated", best = 100 }
			local flow = RunFlow.new()
			RunFlow.step(flow, state, 0)
			assert(flow.phase == "breakup" and RunFlow.banner(flow) ~= nil, "defeat beat stays")
			assert(
				not Results.apply(RunView.hud(state :: any), state, flow).showEnd,
				"wait for breakup"
			)
			RunFlow.step(flow, state, 100)
			local result = Results.apply(RunView.hud(state :: any), state, flow)
			assert(
				result.showEnd and result.score == "0",
				"defeat ends with the authoritative zero score"
			)
		end,
	},
	{
		name = "issue 160: Roblox presentation no longer builds or updates removed text overlays",
		run = function()
			local hud = fs.readFile("src/client/Hud.luau")
			for _, name in
				{ '"Counter"', '"Detail"', '"Hint"', "view.counter", "view.detail", "hintVisible" }
			do
				assert(not string.find(hud, name, 1, true), `Hud still binds {name}`)
			end
			local runHud = fs.readFile("src/client/RunHud.luau")
			assert(
				not string.find(runHud, "SectionMeter", 1, true),
				"run HUD still builds section meter"
			)
			local sections = fs.readFile("src/client/SectionsView.luau")
			assert(
				not string.find(sections, 'Instance.new("ScreenGui")', 1, true),
				"sections still build a screen toast"
			)
			assert(
				string.find(sections, 'Instance.new("BillboardGui")', 1, true),
				"world stack badges stay"
			)
			local main = fs.readFile("src/client/Main.client.luau")
			assert(
				not string.find(main, "hud:pop()", 1, true),
				"removed counter still has event bindings"
			)
		end,
	},
}
