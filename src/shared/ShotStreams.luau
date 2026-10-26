--!strict
-- Issue #63: the visual distribution of musical shots into parallel streams. One stream per
-- logical parade section, capped at MAX_STREAMS; shot numbers cycle through the streams. Pure: no
-- Roblox APIs. Visual only: the stream count never changes the firing rate, the pool size, the
-- damage, the targets or the every-fourth-shot gift cadence; those stay in Config and the server.
local ShotLook = require("./ShotLook")

local ShotStreams = {}

ShotStreams.MAX_STREAMS = 5 -- [default] most parallel streams, however many sections there are
ShotStreams.SPACING = 1.6 -- [default] studs between neighbouring streams (game units)

local function checkInt(v: any, name: string)
	if type(v) ~= "number" or v ~= math.floor(v) or v < 0 then
		error(`{name} must be a non-negative integer, got {tostring(v)}`, 3)
	end
end

-- Streams for a logical section count: clamp(sections, 1, MAX_STREAMS), so 0 or 1 section is one
-- stream, two sections two, and so on up to the cap.
function ShotStreams.count(sections: number): number
	checkInt(sections, "sections")
	return math.clamp(sections, 1, ShotStreams.MAX_STREAMS)
end

-- The 0-based stream a shot number travels in, for `streams` streams.
function ShotStreams.lane(n: number, streams: number): number
	checkInt(n, "shot number")
	if type(streams) ~= "number" or streams ~= math.floor(streams) or streams < 1 then
		error(`streams must be a positive integer, got {tostring(streams)}`, 2)
	end
	return (n - 1) % streams
end

-- Lateral offset (game units, x) of a lane, centred on the lead so the streams are symmetric.
function ShotStreams.offset(lane: number, streams: number): number
	return (lane - (streams - 1) / 2) * ShotStreams.SPACING
end

-- Live shots the projectile pool must hold. Streams only redistribute the same firing schedule,
-- so this is the existing ShotLook sizing and does not depend on the stream count.
function ShotStreams.projectileCapacity(rate: number, maxAimedFlight: number): number
	return ShotLook.projectileCapacity(rate, maxAimedFlight)
end

return ShotStreams
