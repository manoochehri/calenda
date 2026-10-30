--!strict
-- Issue #203: pure maths behind the marching avatar slot (viewport framing and the march).
local okA, AvatarSlot = pcall(require, "../src/shared/AvatarSlot")

return {
	{
		name = "camera distance frames the whole avatar with margin for any slot aspect",
		run = function()
			assert(okA, `AvatarSlot module missing: {tostring(AvatarSlot)}`)
			for _, aspect in { 0.5, 0.75, 1, 1.5 } do
				local d = AvatarSlot.cameraDistance(6, AvatarSlot.FOV, aspect)
				local halfV = math.tan(math.rad(AvatarSlot.FOV / 2)) * d
				local halfH = halfV * aspect
				assert(halfV >= 6 / 2, `aspect {aspect}: height not framed`)
				assert(halfH >= AvatarSlot.WIDTH_STUDS / 2, `aspect {aspect}: width not framed`)
			end
		end,
	},
	{
		name = "the march is a bounded in-place bob and sway, periodic, with no translation",
		run = function()
			assert(okA, `AvatarSlot module missing: {tostring(AvatarSlot)}`)
			local lo, hi = math.huge, -math.huge
			for i = 0, 200 do
				local m = AvatarSlot.march(i * 0.02)
				lo, hi = math.min(lo, m.lift), math.max(hi, m.lift)
				assert(math.abs(m.roll) <= math.rad(8), "sway is small")
			end
			assert(lo >= 0 and hi <= 1, "lift stays under one stud")
			assert(hi > 0.05, "the bob is visible")
			local a, b = AvatarSlot.march(0.3), AvatarSlot.march(0.3 + AvatarSlot.PERIOD)
			assert(math.abs(a.lift - b.lift) < 1e-9, "loops every PERIOD")
		end,
	},
}
