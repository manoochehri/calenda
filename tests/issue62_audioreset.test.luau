--!strict
local ResetPlan = require("../src/shared/ResetPlan")

return {
	{
		name = "ResetPlan has an audio item that runs its handler (replay resets intensity)",
		run = function()
			assert(table.find(ResetPlan.items, "audio") ~= nil, "audio is on the replay checklist")
			local ran = 0
			local handlers: { [string]: () -> () } = {}
			for _, item in ResetPlan.items do
				handlers[item] = function() end
			end
			handlers.audio = function()
				ran += 1
			end
			ResetPlan.apply(handlers, function(msg)
				error(msg)
			end)
			assert(ran == 1, "audio handler ran once")
		end,
	},
	{
		name = "a missing audio handler is reported, not thrown",
		run = function()
			local msgs: { string } = {}
			ResetPlan.apply({}, function(m)
				table.insert(msgs, m)
			end)
			local found = false
			for _, m in msgs do
				if string.find(m, '"audio"') then
					found = true
				end
			end
			assert(found, "reported")
		end,
	},
}
