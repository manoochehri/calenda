--!strict
-- Pure timing for the card between two server-authoritative levels (issue #129).
-- The client owns this presentation clock; the server remains the source of the next level.
local LevelInterstitial = {}

LevelInterstitial.DURATION = 3

export type Flow = {
	startedAt: number,
	active: boolean,
	completed: boolean,
}

export type Frame = {
	active: boolean,
	advance: boolean,
	elapsed: number,
	progress: number,
}

function LevelInterstitial.new(startedAt: number, _level: number): Flow
	assert(type(startedAt) == "number" and startedAt == startedAt, "startedAt must be finite")
	return { startedAt = startedAt, active = true, completed = false }
end

function LevelInterstitial.step(flow: Flow, now: number, skip: boolean): Frame
	assert(type(now) == "number" and now == now, "now must be finite")
	local elapsed = math.clamp(now - flow.startedAt, 0, LevelInterstitial.DURATION)
	if flow.active and (skip or elapsed >= LevelInterstitial.DURATION) then
		flow.active = false
		flow.completed = true
		return { active = false, advance = true, elapsed = elapsed, progress = 1 }
	end
	return {
		active = flow.active,
		advance = false,
		elapsed = elapsed,
		progress = elapsed / LevelInterstitial.DURATION,
	}
end

return LevelInterstitial
