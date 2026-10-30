--!strict
-- The replay checklist (spec s9 and s12, issue #16): every piece of client run state that must be
-- cleared when a new run starts. Pure: `apply` calls one handler per item, in order, and warns
-- (never throws) on a missing, unknown or failing handler, so adding state to the client without
-- adding it here (or the reverse) is loud in the log but cannot freeze the client.
local ResetPlan = {}

ResetPlan.items = table.freeze({
	"input", -- the steering controller and its remembered target
	"counters", -- the cached state, HUD counters and arrival clock
	"camera", -- drawn x and the camera pullback
	"sections", -- section puppets, ghosts, indicator and the director's previous total
	"clusters", -- spectator groups, projectile flights and floats (issue #12)
	"obstacles", -- obstacle feedback in flight (issue #15)
	"music", -- layered stems: stop, rewind, forget the crossfade schedule (issue #21)
	"audio", -- audio intensity, music duck and peak, sound effect cooldowns and voices (issue #62)
	"bits", -- confetti and other pooled pieces still in the air
	"finale", -- plaza dancers, gifts and the finale banner
	"hit", -- any hit wobble or screen shake still in progress (issue #50, ADR 0006)
	"breakup", -- tumbling lead, flying hats and instruments, wandering followers
	"results", -- the results panel and the new-best flag
	"flow", -- RunFlow back to its first phase
})

-- Never throws: a missing, unknown or failing handler is reported through `warn` and the rest
-- still run, so a mistake here can never abort the State handler before it stores the new State.
function ResetPlan.apply(handlers: { [string]: () -> () }, warn: ((string) -> ())?)
	local report = warn or print
	for name in handlers do
		if table.find(ResetPlan.items, name) == nil then
			report(`ResetPlan: unknown reset handler "{name}" ignored`)
		end
	end
	for _, item in ResetPlan.items do
		local handler = handlers[item]
		if type(handler) ~= "function" then
			report(`ResetPlan: no reset handler for "{item}"`)
		else
			local ok, err = pcall(handler)
			if not ok then
				report(`ResetPlan: handler "{item}" failed: {err}`)
			end
		end
	end
end

return ResetPlan
