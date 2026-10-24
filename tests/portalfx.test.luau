--!strict
-- Issue #70: pass-through feedback, approach pulse and the lead-occlusion fade (all pure).
local CameraRig = require("../src/shared/CameraRig")
local PortalFx = require("../src/shared/PortalFx")
local PortalGeometry = require("../src/shared/PortalGeometry")

return {
	{
		name = "a gate event flashes the chosen portal and dims the other, once per gate",
		run = function()
			local fx = PortalFx.new()
			local plan =
				fx:handle({ kind = "gate", id = 3, side = "right", before = 10, after = 30 })
			assert(plan ~= nil, "plan")
			assert(plan.gateId == 3 and plan.chosen == "right" and plan.dimmed == "left", "sides")
			assert(plan.confetti > 0 and plan.confetti <= 90, "within the 90 piece Bits cap")
			assert(
				fx:handle({ kind = "gate", id = 3, side = "right" }) == nil,
				"duplicate plays nothing"
			)
			assert(fx:handle({ kind = "gate", id = 4, side = "left" }) ~= nil, "next gate plays")
			fx:reset()
			assert(
				fx:handle({ kind = "gate", id = 3, side = "left" }) ~= nil,
				"after reset it plays"
			)
		end,
	},
	{
		name = "malformed or other events play nothing",
		run = function()
			local fx = PortalFx.new()
			assert(fx:handle(nil) == nil and fx:handle("gate") == nil, "not tables")
			assert(fx:handle({ kind = "obstacle", id = 1 }) == nil, "other kind")
			assert(fx:handle({ kind = "gate", id = "x", side = "left" }) == nil, "bad id")
			assert(fx:handle({ kind = "gate", id = 1, side = "middle" }) == nil, "bad side")
			assert(fx:handle({ kind = "gate", side = "left" }) == nil, "missing id")
		end,
	},
	{
		name = "flash starts bright and fades out; dim eases in and holds; ring grows and fades",
		run = function()
			assert(PortalFx.flash(0) == 1 and PortalFx.flash(1) == 0, "flash ends")
			assert(PortalFx.flash(0.3) > PortalFx.flash(0.6), "flash decays")
			assert(PortalFx.dim(0) == 0, "dim starts at nothing")
			assert(
				PortalFx.dim(1) == PortalFx.DIM_MAX and PortalFx.dim(5) == PortalFx.DIM_MAX,
				"holds"
			)
			assert(PortalFx.dim(0.1) < PortalFx.dim(0.2), "eases in")
			assert(PortalFx.ringRadius(0, 10) < PortalFx.ringRadius(0.5, 10), "grows")
			assert(math.abs(PortalFx.ringRadius(1, 10) - 10) < 1e-9, "reaches the maximum")
			assert(
				PortalFx.ringAlpha(0) > PortalFx.ringAlpha(1) and PortalFx.ringAlpha(1) == 0,
				"fades"
			)
			assert(PortalFx.DURATION > 0, "duration")
		end,
	},
	{
		name = "pulse: none far away or once passed; subtle, stronger and quicker as the row nears",
		run = function()
			local function peak(dist: number): number
				local m = 0
				for i = 0, 200 do
					m = math.max(m, PortalFx.pulse(dist, i * 0.01))
				end
				return m
			end
			assert(peak(PortalFx.PULSE_FAR + 20) == 0, "far row is calm")
			assert(peak(-5) == 0 and peak(0) == 0, "passed row is calm")
			assert(
				peak(PortalFx.PULSE_NEAR) > peak((PortalFx.PULSE_FAR + PortalFx.PULSE_NEAR) / 2),
				"grows"
			)
			assert(peak(PortalFx.PULSE_NEAR) <= 1, "bounded")
			assert(PortalFx.PULSE_SCALE <= 0.06, "subtle: at most 6% size change")
			assert(
				PortalFx.scale(1) == 1 + PortalFx.PULSE_SCALE and PortalFx.scale(0) == 1,
				"scale"
			)
		end,
	},
	{
		name = "only the NEXT gate row pulses",
		run = function()
			local gates = { { id = 1, z = 100 }, { id = 2, z = 300 }, { id = 3, z = 500 } }
			assert(PortalFx.nextRowId(gates, 0) == 1, "before the first")
			assert(PortalFx.nextRowId(gates, 100) == 2, "at the plane it is passed")
			assert(PortalFx.nextRowId(gates, 250) == 2, "between")
			assert(PortalFx.nextRowId(gates, 600) == nil, "none left")
		end,
	},
	{
		name = "fade: opaque far from the lead, see-through while the banner would hide the lead",
		run = function()
			assert(PortalFx.fade(-30) == 0 and PortalFx.fade(40) == 0, "away from the lead")
			assert(PortalFx.fade(3) > 0.5, "just past the portal")
			assert(PortalFx.fade(3) <= PortalFx.FADE_MAX and PortalFx.FADE_MAX < 1, "bounded")
		end,
	},
	{
		name = "fade covers every distance where the banner blocks the camera's view of the lead",
		run = function()
			local seen = 0
			for _, pullback in { 1, 1.2, 1.4 } do
				local pose = CameraRig.pose(0, 0, pullback)
				for i = 0, 140 do
					local dz = i * 0.1 -- lead is dz studs past the portal plane
					if
						CameraRig.bannerHidesLead(
							pose,
							0,
							-dz,
							PortalGeometry.BANNER_BOTTOM,
							PortalGeometry.TOP
						)
					then
						seen += 1
						assert(
							PortalFx.fade(dz) >= 0.6,
							`hidden at dz {dz} (pullback {pullback}) but fade {PortalFx.fade(dz)}`
						)
					end
				end
			end
			assert(seen > 0, "the banner does hide the lead somewhere (the fade is needed)")
		end,
	},
}
