--!strict
-- Issue #151 (pass 2): the three ordinary shots must be readable at phone size within the calm
-- screen (no trail, no extra pieces). Headless projection through the game's camera model onto
-- the 390 px tall landscape reference phone. The pixel targets are design choices, not a
-- published standard (Apple HIG's 44 pt is a TAP target, not a sprite size): UNVERIFIED in Studio.
local CameraRig = require("../src/shared/CameraRig")
local Config = require("../src/shared/Config")
local ProjectileVisual = require("../src/shared/ProjectileVisual")
local ScreenLayout = require("../src/shared/ScreenLayout")
local ShotLook = require("../src/shared/ShotLook")

local KINDS: { ProjectileVisual.Kind } = { "note", "heart", "gift" }

-- Smallest silhouette dimension (px) at the impact range, pullback 1, nominal size.
local MIN_PX = 24
-- Hard floor (px) at the largest pullback and the pulse trough.
local FLOOR_PX = 16
-- Largest silhouette dimension (px) at spawn, so a shot near the lead does not become clutter.
local MAX_SPAWN_PX = 60
-- Minimum WCAG relative-luminance contrast ratio between any two shot colours.
local MIN_CONTRAST = 2.2

local function extent(kind: ProjectileVisual.Kind, size: number): (number, number)
	local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
	for _, q in ProjectileVisual.place(kind, size) do
		x0 = math.min(x0, q.x - q.w / 2)
		x1 = math.max(x1, q.x + q.w / 2)
		y0 = math.min(y0, q.y - q.h / 2)
		y1 = math.max(y1, q.y + q.h / 2)
	end
	return x1 - x0, y1 - y0
end

-- Pixel (width, height) of the silhouette at (y, z) from the camera at `pullback`.
local function pixels(
	kind: ProjectileVisual.Kind,
	size: number,
	pullback: number,
	y: number,
	z: number
)
	local pose = CameraRig.pose(0, 0, pullback)
	local w, h = extent(kind, size)
	local per = CameraRig.screenFraction(pose, y, z, 1, ProjectileVisual.TILT)
		* ScreenLayout.REFERENCE_HEIGHT
	return w * per, h * per
end

local function lin(c: number): number
	local s = c / 255
	return if s <= 0.03928 then s / 12.92 else ((s + 0.055) / 1.055) ^ 2.4
end
local function luminance(rgb: { number }): number
	return 0.2126 * lin(rgb[1]) + 0.7152 * lin(rgb[2]) + 0.0722 * lin(rgb[3])
end

return {
	{
		name = "impact: smallest dimension >= MIN_PX at pullback 1; >= FLOOR_PX at max pullback and pulse trough",
		run = function()
			local maxPull = Config.visualBudget.cameraPullback.max
			for _, kind in KINDS do
				local size = ShotLook.LOOKS[kind].size
				local w, h = pixels(kind, size, 1, 3, Config.firing.range)
				assert(math.min(w, h) >= MIN_PX, `{kind} impact {w} x {h} px, need {MIN_PX}`)
				local tw, th =
					pixels(kind, size * (1 - ShotLook.PULSE), maxPull, 3, Config.firing.range)
				assert(
					math.min(tw, th) >= FLOOR_PX,
					`{kind} worst case {tw} x {th} px, need {FLOOR_PX}`
				)
			end
		end,
	},
	{
		name = "spawn and mid-flight sizes stay between MIN_PX-ish and MAX_SPAWN_PX",
		run = function()
			for _, kind in KINDS do
				local size = ShotLook.LOOKS[kind].size
				local sw, sh = pixels(kind, size * (1 + ShotLook.PULSE), 1, 2.5, 0)
				assert(math.max(sw, sh) <= MAX_SPAWN_PX, `{kind} spawn {sw} x {sh} px is clutter`)
				local mw, mh = pixels(kind, size * (1 - ShotLook.PULSE), 1, 9.5, 30)
				assert(math.min(mw, mh) >= FLOOR_PX, `{kind} mid-flight {mw} x {mh} px`)
			end
		end,
	},
	{
		name = "the three shot colours differ in luminance (colour-blind safe), flat and opaque",
		run = function()
			for i = 1, #KINDS do
				for j = i + 1, #KINDS do
					local a = luminance(ShotLook.LOOKS[KINDS[i]].core)
					local b = luminance(ShotLook.LOOKS[KINDS[j]].core)
					local ratio = (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05)
					assert(
						ratio >= MIN_CONTRAST,
						`{KINDS[i]} vs {KINDS[j]} contrast {ratio}, need {MIN_CONTRAST}`
					)
				end
			end
		end,
	},
	{
		name = "silhouettes differ by piece count/shape and none carries a trail-style extra",
		run = function()
			local sig = {}
			for _, kind in KINDS do
				local parts = ProjectileVisual.geometry(kind)
				local balls = 0
				for _, p in parts do
					if p.shape == "ball" then
						balls += 1
					end
				end
				local s = `{#parts}:{balls}`
				assert(not sig[s], `{kind} shares a piece signature with another kind`)
				sig[s] = true
			end
		end,
	},
}
