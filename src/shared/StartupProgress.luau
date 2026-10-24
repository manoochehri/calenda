--!strict
-- Progress is the fraction of explicitly registered startup tasks completed. A task may report
-- incremental progress from actual work (for example, built street batches); time never advances it.
local StartupProgress = {}

export type Progress = {
	total: number,
	values: { [string]: number },
}

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function StartupProgress.new(tasks: { string }): Progress
	assert(type(tasks) == "table" and #tasks > 0, "at least one startup task is required")
	local values: { [string]: number } = {}
	for _, task in tasks do
		assert(
			type(task) == "string" and task ~= "",
			"startup task names must be non-empty strings"
		)
		assert(values[task] == nil, `duplicate startup task: {task}`)
		values[task] = 0
	end
	return { total = #tasks, values = values }
end

function StartupProgress.report(progress: Progress, task: string, fraction: any): boolean
	if progress.values[task] == nil or not finite(fraction) then
		return false
	end
	local current = progress.values[task]
	progress.values[task] = math.max(current, math.clamp(fraction :: number, 0, 1))
	return true
end

function StartupProgress.fraction(progress: Progress): number
	local completed = 0
	for _, value in progress.values do
		completed += value
	end
	return completed / progress.total
end

return StartupProgress
