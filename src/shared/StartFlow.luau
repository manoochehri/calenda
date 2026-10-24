--!strict
-- Pure loading/title/play/results transitions. The server's ready State is necessary but not
-- sufficient for Play: local world construction and client listeners must also be ready.
local StartFlow = {}

export type Phase = "loading" | "title" | "playing" | "results"
export type Flow = { phase: Phase, progress: number, serverReady: boolean }

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function unlockTitle(flow: Flow)
	if flow.phase == "loading" and flow.progress >= 1 and flow.serverReady then
		flow.phase = "title"
	end
end

function StartFlow.new(): Flow
	return { phase = "loading", progress = 0, serverReady = false }
end

function StartFlow.progress(flow: Flow, value: any)
	if flow.phase ~= "loading" or not finite(value) then
		return
	end
	flow.progress = math.max(flow.progress, math.clamp(value :: number, 0, 1))
	unlockTitle(flow)
end

function StartFlow.serverPhase(flow: Flow, phase: any)
	if phase == "ready" then
		flow.serverReady = true
		unlockTitle(flow)
	elseif phase == "running" then
		flow.serverReady = false
		if flow.phase ~= "results" then
			flow.phase = "playing"
		end
	elseif phase == "over" then
		flow.serverReady = false
		flow.phase = "results"
	end
end

function StartFlow.play(flow: Flow): boolean
	if flow.phase ~= "title" then
		return false
	end
	flow.phase = "playing"
	flow.serverReady = false
	return true
end

function StartFlow.replay(flow: Flow): boolean
	if flow.phase ~= "results" then
		return false
	end
	flow.phase = "playing"
	return true
end

return StartFlow
