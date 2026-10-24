--!strict
-- Pure recorder for opt-in startup measurements. Callers supply the clock and output sink so
-- this stays testable under Lune and cannot depend on Roblox Instances.
export type Recorder = {
	setStartAt: (self: Recorder, at: number) -> (),
	mark: (self: Recorder, label: string, at: number?) -> (),
	recordDuration: (self: Recorder, label: string, startedAt: number, endedAt: number) -> (),
	measure: <T>(self: Recorder, label: string, action: () -> T) -> T,
	has: (self: Recorder, label: string) -> boolean,
	finish: (self: Recorder) -> boolean,
}

type Entry = { label: string, at: number, duration: number? }

local StartupTiming = {}

function StartupTiming.new(
	enabled: boolean,
	startedAt: number,
	clock: () -> number,
	emit: (string) -> ()
): Recorder
	local startAt = startedAt
	local entries: { Entry } = {}
	local finished = false
	local recorder = {} :: Recorder

	function recorder.setStartAt(_, at: number)
		if enabled and not finished and at < startAt then
			startAt = at
		end
	end

	function recorder.mark(_, label: string, at: number?)
		if not enabled or finished then
			return
		end
		table.insert(entries, { label = label, at = at or clock(), duration = nil })
	end

	function recorder.recordDuration(_, label: string, beganAt: number, endedAt: number)
		if not enabled or finished then
			return
		end
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

	function recorder.has(_, label: string): boolean
		if not enabled then
			return false
		end
		for _, entry in entries do
			if entry.label == label then
				return true
			end
		end
		return false
	end

	function recorder.finish(_): boolean
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
		emit(table.concat(fields, " | "))
		return true
	end

	return recorder
end

return StartupTiming
