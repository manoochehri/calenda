--!strict
-- Reusable buffer for batching equivalent engine moves without allocating per frame.
-- The callback is injected so the movement policy is testable without Roblox.

export type MoveBatch = {
	push: (self: MoveBatch, item: any, frame: any) -> (),
	reset: (self: MoveBatch) -> (),
	flush: (self: MoveBatch) -> number,
}

local MoveBatch = {}

function MoveBatch.new(send: ({ any }, { any }) -> ()): MoveBatch
	local items: { any } = {}
	local frames: { any } = {}
	local count = 0
	local batch = {} :: MoveBatch

	function batch.push(_, item: any, frame: any)
		count += 1
		items[count] = item
		frames[count] = frame
	end

	function batch.reset(_)
		count = 0
	end

	function batch.flush(_): number
		if count == 0 then
			return 0
		end
		send(items, frames)
		local sent = count
		count = 0
		return sent
	end

	return batch
end

return MoveBatch
