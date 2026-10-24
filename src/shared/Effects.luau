--!strict
-- A bounded set of timed visual effects (issues #12, #15): projectiles, dust chunks, floating
-- numbers, runners. `start` is refused (the effect is simply not shown) once `capacity` effects
-- are live, so the pools behind them can never grow with how fast the server sends events.
-- Pure: time is passed in. The client sizes its Pool to `count` each frame.
export type Active<T> = { data: T, f: number }
export type Effects<T> = {
	start: (self: Effects<T>, now: number, duration: number, data: T) -> boolean,
	active: (self: Effects<T>, now: number) -> { Active<T> },
	count: (self: Effects<T>, now: number) -> number,
	capacity: (self: Effects<T>) -> number,
	clear: (self: Effects<T>) -> (),
}

local Effects = {}

function Effects.new<T>(capacity: number): Effects<T>
	if type(capacity) ~= "number" or capacity ~= math.floor(capacity) or capacity < 1 then
		error(`capacity must be a positive integer, got {tostring(capacity)}`, 2)
	end
	local live: { { data: T, start: number, duration: number } } = {}
	local self = {} :: Effects<T>

	local function prune(now: number)
		local kept = {}
		for _, e in live do
			if now < e.start + e.duration then
				table.insert(kept, e)
			end
		end
		live = kept
	end

	function self.start(_, now: number, duration: number, data: T): boolean
		if type(duration) ~= "number" or duration <= 0 then
			error(`duration must be positive, got {tostring(duration)}`, 2)
		end
		prune(now)
		if #live >= capacity then
			return false
		end
		table.insert(live, { data = data, start = now, duration = duration })
		return true
	end

	function self.active(_, now: number): { Active<T> }
		prune(now)
		local out: { Active<T> } = {}
		for _, e in live do
			table.insert(out, { data = e.data, f = math.clamp((now - e.start) / e.duration, 0, 1) })
		end
		return out
	end

	function self.count(_, now: number): number
		prune(now)
		return #live
	end

	function self.capacity(_): number
		return capacity
	end

	function self.clear(_)
		live = {}
	end

	return self
end

return Effects
