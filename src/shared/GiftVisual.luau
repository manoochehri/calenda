--!strict
-- Pure look of the gift shot (issue #20, spec s4): a wrapped treat that is plainly neither a note
-- nor a spectator, and the spectators' catch celebration. Visual only: a gift is exactly one hit on
-- the server, and nothing here is a reward. Colors are 0..255 triples (the client makes Color3s).
-- Placeholder treats only; specific foods await local reference review (spec s4).
local Config = require("./Config")
local GiftVisual = {}

GiftVisual.NOTE_RGB = table.freeze({ 255, 235, 60 })
GiftVisual.SPECTATOR_RGB = table.freeze({ 255, 120, 40 })
-- Wrapper colorways, all far from the note yellow and the spectator orange so a gift reads at once.
GiftVisual.WRAPPERS = table.freeze({
	table.freeze({ 200, 30, 200 }), -- magenta
	table.freeze({ 40, 200, 230 }), -- cyan
	table.freeze({ 130, 70, 235 }), -- violet
})
GiftVisual.NOTE_SIZE = 0.9 -- [default] studs, matches the note ball
GiftVisual.TREAT_LENGTH = 1.9 -- [default] studs: the wrapped body, twisted ends included
GiftVisual.TREAT_THICK = 1.1 -- [default]
GiftVisual.CATCH_SECONDS = 0.55 -- [default] one spectator's celebratory hop
GiftVisual.STAGGER_SECONDS = 0.05 -- [default] delay between neighbors, so the group ripples
GiftVisual.CATCH_HOP = 1.6 -- [default] studs

export type Look = { wrapper: number, spin: number }
export type Catch = { hop: number, glow: number }

-- Colorway and tumble direction of the gift that made the meter `hits`.
function GiftVisual.look(hits: number): Look
	return {
		wrapper = hits % #GiftVisual.WRAPPERS + 1,
		spin = if hits % 2 == 0 then 9 else -9,
	}
end

-- The gift's flight path (ADR 0006, #93): a high arc that rises to `giftArc.height` at the middle
-- and comes back down, with `giftArc.loops` whole loops swinging sideways by `giftArc.loopRadius`.
-- Returns the offsets (studs) to add to the straight line from launch to target at progress f.
-- Both offsets are 0 at f = 0 and f = 1, so the gift still lands exactly on its target.
function GiftVisual.arc(f: number, config: any?): { dx: number, dy: number }
	local cfg = (config or Config).giftArc
	local k = math.clamp(f, 0, 1)
	return {
		dx = cfg.loopRadius * math.sin(2 * math.pi * cfg.loops * k),
		dy = cfg.height * 4 * k * (1 - k),
	}
end

-- A gift's flight time over a distance that a note covers in `noteSeconds` (ADR 0006, #93).
function GiftVisual.flightSeconds(noteSeconds: number, config: any?): number
	return noteSeconds * (config or Config).giftArc.slowdown
end

-- Tumble angle at flight progress 0..1: two whole turns on the way.
function GiftVisual.tumble(f: number): number
	return math.clamp(f, 0, 1) * 4 * math.pi
end

-- Spectator `member` (1-based) catching the gift, `age` seconds after it landed.
function GiftVisual.catch(age: number, member: number): Catch
	local a = age - (member - 1) * GiftVisual.STAGGER_SECONDS
	if a < 0 or a >= GiftVisual.CATCH_SECONDS then
		return { hop = 0, glow = 0 }
	end
	local s = math.sin(math.pi * a / GiftVisual.CATCH_SECONDS)
	return { hop = GiftVisual.CATCH_HOP * s, glow = s }
end

return GiftVisual
