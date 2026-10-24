--!strict
-- Pure effect timing for the gate portals (issue #70): the pass-through reaction (chosen portal
-- flashes and bursts, the other dims, a ground ring), the approach pulse of the next row, and the
-- see-through fade that keeps a banner from hiding the lead just after it. Time is passed in.
-- The client (GateView) only applies these numbers. IN-ENGINE LOOK IS UNVERIFIED.
export type Plan = {
	gateId: number,
	chosen: "left" | "right",
	dimmed: "left" | "right",
	confetti: number,
}

local PortalFx = {}

PortalFx.DURATION = 1.1 -- [default] seconds for the flash and the ring
PortalFx.CONFETTI = 24 -- [default] pieces per pass; GateView has its own Bits pool (cap 90) and section bursts share the screen
PortalFx.DIM_MAX = 0.6 -- [default] extra banner transparency of the portal not taken
PortalFx.DIM_SECONDS = 0.3 -- [default] time to reach DIM_MAX
PortalFx.PULSE_FAR = 110 -- [default] studs ahead at which the next row starts to pulse
PortalFx.PULSE_NEAR = 30 -- [default] studs ahead at which the pulse is strongest (GATE_NEAR)
PortalFx.PULSE_SCALE = 0.05 -- [default] banner scale change at full pulse: subtle
PortalFx.FADE_MAX = 0.8 -- [default] banner transparency while it would hide the lead
-- The lead is `dz` studs past the portal plane. Keep the banner faded until the deepest drawn
-- follower or section has cleared, then ease it back in over the final 2.5 studs. (Issue #82: the leaning banner hides the lead out to
-- 15 studs past the plane, so the lead-only hold is 15.5.)
local FADE_IN_FROM, FADE_IN_TO, FADE_OUT_FROM, FADE_OUT_TO = -0.5, 0.5, 15.5, 18

local function smooth(x: number): number
	local t = math.clamp(x, 0, 1)
	return t * t * (3 - 2 * t)
end

function PortalFx.new()
	local seen: { [number]: boolean } = {}
	local self = {}

	-- A server Event payload -> a plan, once per gate id per run. Anything else -> nil.
	function self.handle(_, payload: any): Plan?
		if type(payload) ~= "table" or payload.kind ~= "gate" then
			return nil
		end
		local id, side = payload.id, payload.side
		if type(id) ~= "number" or (side ~= "left" and side ~= "right") then
			return nil
		end
		if seen[id] then
			return nil
		end
		seen[id] = true
		return {
			gateId = id,
			chosen = side,
			dimmed = if side == "left" then "right" else "left",
			confetti = PortalFx.CONFETTI,
		}
	end

	function self.reset(_)
		table.clear(seen)
	end

	return self
end

-- f = seconds since the pass / DURATION, 0..1.
function PortalFx.flash(f: number): number
	local r = 1 - math.clamp(f, 0, 1)
	return r * r
end

-- Extra banner transparency of the portal not taken, `seconds` after the pass.
function PortalFx.dim(seconds: number): number
	return PortalFx.DIM_MAX * smooth(seconds / PortalFx.DIM_SECONDS)
end

function PortalFx.ringRadius(f: number, maxRadius: number): number
	local e = 1 - (1 - math.clamp(f, 0, 1)) ^ 2
	return maxRadius * (0.15 + 0.85 * e)
end

-- 0.. opaque start; 1 at f = 1 means fully transparent for the ring; returned as "alpha" (1 = visible).
function PortalFx.ringAlpha(f: number): number
	return (1 - math.clamp(f, 0, 1)) * 0.8
end

-- Approach pulse: glow 0..1 for a row `dist` studs ahead. Calm beyond PULSE_FAR and once passed;
-- the strength and the speed grow towards PULSE_NEAR.
function PortalFx.pulse(dist: number, clock: number): number
	if dist <= 0 or dist >= PortalFx.PULSE_FAR then
		return 0
	end
	local env = smooth((PortalFx.PULSE_FAR - dist) / (PortalFx.PULSE_FAR - PortalFx.PULSE_NEAR))
	local hz = 0.8 + 1.7 * env
	return env * (0.5 + 0.5 * math.sin(2 * math.pi * hz * clock))
end

function PortalFx.scale(glow: number): number
	return 1 + PortalFx.PULSE_SCALE * glow
end

-- Id of the first gate row still ahead of the lead (the only one that pulses).
function PortalFx.nextRowId(gates: { { id: number, z: number } }, leadZ: number): number?
	for _, g in gates do
		if g.z > leadZ then
			return g.id
		end
	end
	return nil
end

-- Banner/text transparency while the lead is `dz` studs past the portal plane. `tailDepth` is the
-- deepest drawn parade slot behind the lead, so the banner remains faded until that slot clears.
function PortalFx.fade(dz: number, tailDepth: number?): number
	local tail = math.max(0, tailDepth or 0)
	local up = smooth((dz - FADE_IN_FROM) / (FADE_IN_TO - FADE_IN_FROM))
	local down = 1 - smooth((dz - tail - FADE_OUT_FROM) / (FADE_OUT_TO - FADE_OUT_FROM))
	return PortalFx.FADE_MAX * math.min(up, down)
end

return PortalFx
