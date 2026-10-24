--!strict
-- The server -> client "cluster" Event (issue #12): one per landed shot, display-only. It carries
-- the cluster's hit count AFTER the shot and the visual shot kind; everything else the client
-- needs (needed hits, reward, position over time) comes from Config and Level, which it already
-- has. The client never sends anything back. `decode` treats the payload as untrusted-shaped data.
--
-- Wire shape: { kind = "cluster", id = <layout cluster id>, hits = <int>, shot = "note" | "gift" }
-- The server side is a one-liner in the shots hook: `for _, s in step.shots do
-- ctx.emit(ClusterFeed.encode(s)) end` (see the PR; RunHooks belongs to PR #43).
export type Shot = { id: number, hits: number, shot: "note" | "gift" }
export type Payload = { kind: string, id: number, hits: number, shot: string }

local ClusterFeed = {}

ClusterFeed.MAX_HITS = 1000 -- [default] sanity bound on a replicated hit count

local function isWholeNumber(v: any, min: number, max: number): boolean
	return type(v) == "number" and v == math.floor(v) and v >= min and v <= max
end

-- Returns the validated shot or nil for anything that is not exactly this shape.
function ClusterFeed.decode(payload: any): Shot?
	if type(payload) ~= "table" or payload.kind ~= "cluster" then
		return nil
	end
	local id, hits, shot = payload.id, payload.hits, payload.shot
	if not isWholeNumber(id, 1, 1e9) or not isWholeNumber(hits, 0, ClusterFeed.MAX_HITS) then
		return nil
	end
	if shot ~= "note" and shot ~= "gift" then
		return nil
	end
	return { id = id, hits = hits, shot = shot }
end

-- Server side: a Targeting.Shot (fields targetId, hits, kind) becomes the wire payload.
function ClusterFeed.encode(s: { targetId: number, hits: number, kind: string }): Payload
	return { kind = "cluster", id = s.targetId, hits = s.hits, shot = s.kind }
end

return ClusterFeed
