--!strict
-- Issue #171 (persistent road flashing after #85). The road is drawn by flat Parts in WorldBuilder
-- (StartingPlaza, Street, both sidewalks, Plaza, the centre-line dashes). Parts default to
-- CastShadow = true, so each flat road surface is also a shadow caster lying on the same plane it
-- is lit on: the shadow map then fights that surface (shadow acne), and the shimmer moves with the
-- camera. Every other ground-level flat Part in the client already opts out (Backdrop slabs,
-- OaxacaStreet ground and paving, Bits, ClusterView, SectionsView, FigureParts). The first two
-- cases pin the road's flat parts to the same rule (fail-first: they failed before the fix). The
-- third is a guard: OaxacaStreet.applyTheme sets GlobalShadows = true inside Backdrop.build, so the
-- noShadows A/B must stay applied after it or the toggle becomes a no-op. It passes on both sides.
local fs = require("@lune/fs")

local function source(path: string): string
	return fs.readFile(path)
end

-- The text from `startMarker` up to (not including) `endMarker`; fails loudly if either is absent.
local function section(text: string, startMarker: string, endMarker: string): string
	local a = string.find(text, startMarker, 1, true)
	assert(a ~= nil, `marker not found: {startMarker}`)
	local b = string.find(text, endMarker, a, true)
	assert(b ~= nil, `marker not found: {endMarker}`)
	return string.sub(text, a, b - 1)
end

return {
	{
		name = "issue 171: the road's flat ground parts do not cast shadows",
		run = function()
			local world = source("src/client/WorldBuilder.client.luau")
			local grounds = section(world, "local function addGround(", "local function addCone(")
			assert(
				string.find(grounds, "CastShadow = false", 1, true) ~= nil,
				"addGround (StartingPlaza, Street, sidewalks, Plaza) still casts shadows"
			)
		end,
	},
	{
		name = "issue 171: the centre-line dashes do not cast shadows",
		run = function()
			local world = source("src/client/WorldBuilder.client.luau")
			local dashes = section(world, "-- Dashed road centerline", "-- Standing gate portals")
			assert(
				string.find(dashes, "CastShadow = false", 1, true) ~= nil,
				"RoadMark dashes still cast shadows"
			)
		end,
	},
	{
		name = "issue 171: the noShadows A/B is applied after the Backdrop sets the street lighting",
		run = function()
			local main = source("src/client/Main.client.luau")
			local backdropAt = string.find(main, "Backdrop.build(", 1, true)
			local shadowsAt = string.find(main, "GlobalShadows = false", 1, true)
			assert(backdropAt ~= nil, "Main no longer calls Backdrop.build")
			assert(shadowsAt ~= nil, "Main no longer sets GlobalShadows for noShadows")
			assert(
				shadowsAt > backdropAt,
				"noShadows is set before Backdrop.build, which resets GlobalShadows = true"
			)
		end,
	},
}
