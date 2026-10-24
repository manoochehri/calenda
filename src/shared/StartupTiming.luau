--!strict
-- Pure recorder for opt-in startup measurements. Callers supply the clock and output sink so
-- this stays testable under Lune and cannot depend on Roblox Instances.
export type Recorder = {
	enabled: boolean,
	begin: (self: Recorder) -> number,
	span: (self: Recorder, label: string, startedAt: number) -> (),
	lap: (self: Recorder, label: string, startedAt: number) -> number,
	setStartAt: (self: Recorder, at: number) -> (),
	mark: (self: Recorder, label: string, at: number?) -> (),
	recordDuration: (self: Recorder, label: string, startedAt: number, endedAt: number) -> (),
	measure: <T>(self: Recorder, label: string, action: () -> T) -> T,
	has: (self: Recorder, label: string) -> boolean,
	finish: (self: Recorder, incomplete: string?) -> boolean,
}

type Entry = { label: string, at: number, duration: number? }

local StartupTiming = {}

-- Shared recorder for the disabled case: every method returns immediately, nothing reads the
-- clock, allocates, formats or prints. (Callers still must not build labels when disabled.)
local DISABLED: Recorder = {
	enabled = false,
	begin = function(_)
		return 0
	end,
	span = function(_, _label, _startedAt) end,
	lap = function(_, _label, _startedAt)
		return 0
	end,
	setStartAt = function(_, _at) end,
	mark = function(_, _label, _at) end,
	recordDuration = function(_, _label, _beganAt, _endedAt) end,
	measure = function<T>(_, _label: string, action: () -> T): T
		return action()
	end,
	has = function(_, _label)
		return false
	end,
	finish = function(_, _incomplete)
		return false
	end,
}

function StartupTiming.new(
	enabled: boolean,
	startedAt: number,
	clock: () -> number,
	emit: (string) -> ()
): Recorder
	if not enabled then
		return DISABLED
	end
	local startAt = startedAt
	local labels: { [string]: boolean } = {}
	local entries: { Entry } = {}
	local finished = false
	local recorder = {} :: Recorder
	recorder.enabled = true

	function recorder.setStartAt(_, at: number)
		if enabled and not finished and at < startAt then
			startAt = at
		end
	end

	function recorder.mark(_, label: string, at: number?)
		if not enabled or finished then
			return
		end
		labels[label] = true
		table.insert(entries, { label = label, at = at or clock(), duration = nil })
	end

	function recorder.recordDuration(_, label: string, beganAt: number, endedAt: number)
		if not enabled or finished then
			return
		end
		labels[label] = true
		table.insert(entries, {
			label = label,
			at = endedAt,
			duration = math.max(0, endedAt - beganAt),
		})
	end

	function recorder.measure<T>(_, label: string, action: () -> T): T
		if not enabled or finished then
			return action()
		end
		local beganAt = clock()
		local result = action()
		recorder.recordDuration(recorder, label, beganAt, clock())
		return result
	end

	function recorder.begin(_): number
		return clock()
	end

	function recorder.span(_, label: string, beganAt: number)
		recorder.recordDuration(recorder, label, beganAt, clock())
	end

	-- Records a span and returns its end time, so consecutive steps need one call each.
	function recorder.lap(_, label: string, beganAt: number): number
		local endedAt = clock()
		recorder.recordDuration(recorder, label, beganAt, endedAt)
		return endedAt
	end

	function recorder.has(_, label: string): boolean
		return labels[label] == true
	end

	function recorder.finish(_, incomplete: string?): boolean
		if not enabled or finished then
			return false
		end
		finished = true
		table.sort(entries, function(a, b)
			return a.at < b.at
		end)
		local fields = { "[startup]" }
		for _, entry in entries do
			local elapsed = math.max(0, entry.at - startAt)
			local field = string.format("+%.3fs %s", elapsed, entry.label)
			if entry.duration ~= nil then
				field ..= string.format(" (%.3fs)", entry.duration)
			end
			table.insert(fields, field)
		end
		if incomplete ~= nil then
			table.insert(fields, `INCOMPLETE: {incomplete}`)
		end
		emit(table.concat(fields, " | "))
		return true
	end

	return recorder
end

return StartupTiming
