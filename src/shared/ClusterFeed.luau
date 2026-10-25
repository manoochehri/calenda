--!strict
-- The server -> client "cluster" Event (issue #12): one per landed shot, display-only. It carries
-- the cluster's hit count AFTER the shot and the visual shot kind; everything else the client
-- needs (needed hits, reward, position over time) comes from Config and Level, which it already
-- has. The client never sends anything back. `decode` treats the payload as untrusted-shaped data.
--
-- Wire shapes (both display-only, owner-only, validated on encode AND decode):
--   hit:  { kind = "cluster", id = <layout cluster id>, hits = <int>, shot = "note" | "gift" }
--   miss: { kind = "miss", shot = "note" | "gift", n = <shot number, int 1..MAX_SHOT_NUMBER> }
--   rey:  { kind = "rey", shot = "note" | "gift", n = <shot number>, bonus = <boolean> }
-- A Rey shot (ADR 0006, #93) hit Rey, not a cluster: no id, no meter. `bonus` is true only on the
-- run's first Rey hit, the one that paid Config.rey.bonus; the client shows the "+N" on that one.
-- A miss (ADR 0004, Amendment 2) is a continuous-fire shot with no eligible target. It carries no
-- id, position, hit or reward: the client draws it straight ahead and nothing can credit from it.
-- `n` only varies the look (note / heart / snack) and orders nothing.
-- The server side is in RunHooks.shots: each Targeting shot is encoded (and validated) and emitted
-- to the owning player only.
export type Shot = { id: number, hits: number, shot: "note" | "gift" }
export type Payload = { kind: string, id: number, hits: number, shot: string }
export type Miss = { shot: "note" | "gift", n: number }
export type MissPayload = { kind: string, shot: string, n: number }
export type ReyShot = { shot: "note" | "gift", n: number, bonus: boolean }
export type ReyPayload = { kind: string, shot: string, n: number, bonus: boolean }

local ClusterFeed = {}

ClusterFeed.MAX_HITS = 1000 -- [default] sanity bound on a replicated hit count
ClusterFeed.MAX_SHOT_NUMBER = 1000000 -- [default] sanity bound on a replicated miss shot number

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

-- Returns the validated miss or nil for anything that is not exactly this shape. Extra fields
-- (an id, a position, hits) make no difference to what is read.
function ClusterFeed.decodeMiss(payload: any): Miss?
	if type(payload) ~= "table" or payload.kind ~= "miss" then
		return nil
	end
	local shot, n = payload.shot, payload.n
	if not isWholeNumber(n, 1, ClusterFeed.MAX_SHOT_NUMBER) then
		return nil
	end
	if shot ~= "note" and shot ~= "gift" then
		return nil
	end
	return { shot = shot, n = n }
end

-- Server side: a Targeting miss (fields kind, number) becomes the miss wire payload; nil if bad.
function ClusterFeed.encodeMiss(s: { kind: string, number: number? }): MissPayload?
	if type(s) ~= "table" then
		return nil
	end
	local kind, n = s.kind, s.number :: any
	if not isWholeNumber(n, 1, ClusterFeed.MAX_SHOT_NUMBER) then
		return nil
	end
	if kind ~= "note" and kind ~= "gift" then
		return nil
	end
	return { kind = "miss", shot = kind, n = n }
end

-- Returns the validated Rey shot or nil for anything that is not exactly this shape.
function ClusterFeed.decodeRey(payload: any): ReyShot?
	if type(payload) ~= "table" or payload.kind ~= "rey" then
		return nil
	end
	local shot, n, bonus = payload.shot, payload.n, payload.bonus
	if not isWholeNumber(n, 1, ClusterFeed.MAX_SHOT_NUMBER) then
		return nil
	end
	if shot ~= "note" and shot ~= "gift" then
		return nil
	end
	if type(bonus) ~= "boolean" then
		return nil
	end
	return { shot = shot, n = n, bonus = bonus }
end

-- Server side: a Targeting Rey shot (rey, number, kind, credit) becomes the Rey wire payload.
function ClusterFeed.encodeRey(s: { number: number?, kind: string, credit: any? }): ReyPayload?
	if type(s) ~= "table" then
		return nil
	end
	local n, kind = s.number :: any, s.kind
	if not isWholeNumber(n, 1, ClusterFeed.MAX_SHOT_NUMBER) then
		return nil
	end
	if kind ~= "note" and kind ~= "gift" then
		return nil
	end
	return { kind = "rey", shot = kind, n = n, bonus = s.credit ~= nil }
end

-- Server side: a Targeting.Shot (fields targetId, hits, kind) becomes the wire payload. Validated
-- like decode: returns nil for anything out of shape (unknown kind, bad id, hits outside 0..MAX_HITS)
-- so the server never replicates a value the client would drop.
function ClusterFeed.encode(s: {
	targetId: number?,
	hits: number,
	kind: string,
	miss: boolean?,
	rey: boolean?,
	number: number?,
	credit: any?,
}): (Payload | MissPayload | ReyPayload)?
	if type(s) ~= "table" then
		return nil
	end
	if s.miss == true then
		return ClusterFeed.encodeMiss(s)
	end
	if s.rey == true then
		return ClusterFeed.encodeRey(s)
	end
	local id, hits, kind = s.targetId :: any, s.hits, s.kind
	if not isWholeNumber(id, 1, 1e9) or not isWholeNumber(hits, 0, ClusterFeed.MAX_HITS) then
		return nil
	end
	if kind ~= "note" and kind ~= "gift" then
		return nil
	end
	return { kind = "cluster", id = id, hits = hits, shot = kind }
end

return ClusterFeed
