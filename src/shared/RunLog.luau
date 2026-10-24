--!strict
-- Structured run log (spec s12 Record, issue #24). Pure: no Roblox APIs.
-- Captures seed, start, first recruitment, each gate choice with before/after totals,
-- first assembly time, obstacle loss, completion with final total, replay, and a flag
-- distinguishing automated QA from human playtest. Local only; no external services,
-- no player data beyond the run.
local RunState = require("./RunState")

local RunLog = {}

export type GateChoice = {
	id: string,
	side: string,
	before: number,
	after: number,
	time: number,
}

export type ObstacleLoss = {
	id: string,
	loss: number,
	before: number,
	after: number,
	time: number,
}

export type FirstRecruitment = {
	id: string,
	time: number,
	before: number,
	after: number,
}

export type Completion = {
	outcome: string,
	finalTotal: number,
	score: number,
	time: number,
}

export type ReplayEntry = {
	time: number,
	seed: number?,
}

export type LogEntry = {
	kind: string,
	time: number,
	[string]: any,
}

export type StructuredLog = {
	seed: number,
	start: number,
	automated: boolean,
	firstRecruitment: FirstRecruitment?,
	firstAssemblyTime: number?,
	gates: { GateChoice },
	obstacleLosses: { ObstacleLoss },
	completion: Completion?,
	replay: boolean,
	replays: { ReplayEntry },
	replayCount: number,
	entries: { LogEntry },
	events: { RunState.Event },
}

export type BuildOptions = {
	replays: { ReplayEntry }?,
	replayed: boolean?,
}

local storedLogs: { StructuredLog } = {}

function RunLog.fromEvents(events: { RunState.Event }, options: BuildOptions?): StructuredLog
	local seed = 0
	local start = 0
	local automated = false
	local firstRecruitment: FirstRecruitment? = nil
	local firstAssemblyTime: number? = nil
	local gates: { GateChoice } = {}
	local obstacleLosses: { ObstacleLoss } = {}
	local completion: Completion? = nil
	local entries: { LogEntry } = {}

	for _, e in events do
		if e.kind == "run_start" then
			seed = e.seed
			start = e.time
			automated = e.automated
			table.insert(entries, {
				kind = "start",
				time = e.time,
				seed = e.seed,
				automated = e.automated,
				before = e.before,
				after = e.after,
			})
		elseif e.kind == "gate" then
			local side = e.side or "left"
			local id = e.id or ""
			table.insert(gates, {
				id = id,
				side = side,
				before = e.before,
				after = e.after,
				time = e.time,
			})
			table.insert(entries, {
				kind = "gate",
				time = e.time,
				id = id,
				side = side,
				before = e.before,
				after = e.after,
			})
			if e.firstAssembly and firstAssemblyTime == nil then
				firstAssemblyTime = e.time
				table.insert(entries, {
					kind = "first_assembly",
					time = e.time,
					before = e.before,
					after = e.after,
				})
			end
		elseif e.kind == "cluster_credit" then
			local id = e.id or ""
			if e.firstRecruit and firstRecruitment == nil then
				firstRecruitment = {
					id = id,
					time = e.time,
					before = e.before,
					after = e.after,
				}
				table.insert(entries, {
					kind = "first_recruitment",
					time = e.time,
					id = id,
					before = e.before,
					after = e.after,
				})
			end
			table.insert(entries, {
				kind = "cluster_credit",
				time = e.time,
				id = id,
				before = e.before,
				after = e.after,
			})
			if e.firstAssembly and firstAssemblyTime == nil then
				firstAssemblyTime = e.time
				table.insert(entries, {
					kind = "first_assembly",
					time = e.time,
					before = e.before,
					after = e.after,
				})
			end
		elseif e.kind == "obstacle" then
			local id = e.id or ""
			local loss = e.before - e.after
			table.insert(obstacleLosses, {
				id = id,
				loss = loss,
				before = e.before,
				after = e.after,
				time = e.time,
			})
			table.insert(entries, {
				kind = "obstacle",
				time = e.time,
				id = id,
				loss = loss,
				before = e.before,
				after = e.after,
			})
		elseif e.kind == "complete" or e.kind == "defeated" then
			local outcome = if e.kind == "defeated" then "defeated" else "completed"
			completion = {
				outcome = outcome,
				finalTotal = e.after,
				score = e.score or e.after,
				time = e.time,
			}
			table.insert(entries, {
				kind = "complete",
				time = e.time,
				outcome = outcome,
				finalTotal = e.after,
				score = e.score or e.after,
			})
		end
	end

	local replaysCopy: { ReplayEntry } = {}
	if options and options.replays then
		for _, r in options.replays do
			table.insert(replaysCopy, { time = r.time, seed = r.seed })
			table.insert(entries, {
				kind = "replay",
				time = r.time,
				seed = r.seed,
			})
		end
	end

	local replayCount = #replaysCopy
	local isReplay = replayCount > 0 or (options ~= nil and options.replayed == true)

	return {
		seed = seed,
		start = start,
		automated = automated,
		firstRecruitment = firstRecruitment,
		firstAssemblyTime = firstAssemblyTime,
		gates = gates,
		obstacleLosses = obstacleLosses,
		completion = completion,
		replay = isReplay,
		replays = replaysCopy,
		replayCount = replayCount,
		entries = entries,
		events = events,
	}
end

function RunLog.format(log: StructuredLog): string
	local lines = {
		`[RunLog] seed: {log.seed} automated: {log.automated} start: {log.start}`,
	}
	if log.firstRecruitment then
		local r = log.firstRecruitment
		table.insert(
			lines,
			`  first_recruitment: id={r.id} time={r.time} ({r.before} -> {r.after})`
		)
	end
	if log.firstAssemblyTime then
		table.insert(lines, `  first_assembly_time: {log.firstAssemblyTime}`)
	end
	for _, g in log.gates do
		table.insert(lines, `  gate: {g.id} ({g.side}) {g.before} -> {g.after} at t={g.time}`)
	end
	for _, o in log.obstacleLosses do
		table.insert(lines, `  obstacle: {o.id} -{o.loss} ({o.before} -> {o.after}) at t={o.time}`)
	end
	if log.completion then
		local c = log.completion
		table.insert(
			lines,
			`  complete: {c.outcome} finalTotal={c.finalTotal} score={c.score} at t={c.time}`
		)
	end
	if log.replayCount > 0 then
		table.insert(lines, `  replays: {log.replayCount}`)
		for _, rep in log.replays do
			table.insert(lines, `    replay at t={rep.time}`)
		end
	end
	return table.concat(lines, "\n")
end

function RunLog.print(log: StructuredLog)
	print(RunLog.format(log))
end

function RunLog.store(log: StructuredLog)
	table.insert(storedLogs, log)
end

function RunLog.getStored(): { StructuredLog }
	return table.clone(storedLogs)
end

function RunLog.clearStored()
	storedLogs = {}
end

return RunLog
