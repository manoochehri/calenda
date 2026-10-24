--!strict
-- Turns a stream of crowd totals into at most one running section animation (issue #14).
-- Pure state machine, driven by the client with the replicated total and frame time.
-- Merging keeps "one combined celebration": a second threshold crossed inside the window joins the
-- running celebration (new indicator, window restarts) instead of starting another.
local SectionEvents = require("./SectionEvents")

export type Active = { plan: SectionEvents.Plan, elapsed: number, progress: number }
export type Director = {
	observe: (self: Director, total: number) -> SectionEvents.Plan?,
	step: (self: Director, dt: number) -> (),
	active: (self: Director) -> Active?,
	reset: (self: Director, total: number) -> (),
	shownTotal: (self: Director) -> number,
}

local SectionDirector = {}

function SectionDirector.new(initialTotal: number): Director
	local shown = initialTotal
	local plan: SectionEvents.Plan? = nil
	local elapsed = 0
	local director = {} :: Director

	function director.observe(_, total: number): SectionEvents.Plan?
		if total == shown then
			return nil
		end
		local previous = shown
		shown = total
		local fresh = SectionEvents.plan(previous, total)
		if fresh.kind == "none" then
			return nil
		end
		local running = plan
		if running ~= nil and running.kind == fresh.kind then
			fresh = SectionEvents.plan(running.from, total) -- one combined event
		end
		plan = fresh
		elapsed = 0
		return fresh
	end

	function director.step(_, dt: number)
		local running = plan
		if running == nil then
			return
		end
		elapsed += math.max(0, dt)
		if elapsed >= running.duration then
			plan = nil
			elapsed = 0
		end
	end

	function director.active(_): Active?
		local running = plan
		if running == nil then
			return nil
		end
		return {
			plan = running,
			elapsed = elapsed,
			progress = math.clamp(elapsed / running.duration, 0, 1),
		}
	end

	function director.reset(_, total: number)
		shown = total
		plan = nil
		elapsed = 0
	end

	function director.shownTotal(_): number
		return shown
	end

	return director
end

return SectionDirector
