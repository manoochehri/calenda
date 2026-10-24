--!strict
-- A tiny object pool (issue #13): items are created on demand, then shown or hidden, never
-- destroyed, so a changing follower count costs no allocation after warm-up. Generic and free of
-- Roblox APIs; the client supplies create/show/hide for its avatar models.
export type Pool<T> = {
	setCount: (self: Pool<T>, n: number) -> { T },
	size: (self: Pool<T>) -> number,
}

local Pool = {}

function Pool.new<T>(create: () -> T, show: (T) -> (), hide: (T) -> ()): Pool<T>
	local all: { T } = {} -- every item ever created
	local activeCount = 0
	local pool = {} :: Pool<T>

	-- Makes exactly `n` items active and returns them (the first n of the pool, in a stable order).
	function pool.setCount(_, n: number): { T }
		if type(n) ~= "number" or n ~= math.floor(n) or n < 0 then
			error(`count must be a non-negative integer, got {tostring(n)}`, 2)
		end
		while #all < n do
			local item = create()
			hide(item)
			table.insert(all, item)
		end
		for i = activeCount + 1, n do
			show(all[i])
		end
		for i = n + 1, activeCount do
			hide(all[i])
		end
		activeCount = n
		return table.move(all, 1, n, 1, {})
	end

	function pool.size(_): number
		return #all
	end

	return pool
end

return Pool
