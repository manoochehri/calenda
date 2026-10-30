--!strict
local Config = require("../src/shared/Config")
local FollowerLook = require("../src/shared/FollowerLook")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

return {
	{
		name = "a follower always looks the same, and followers differ",
		run = function()
			local a, b = FollowerLook.of(7), FollowerLook.of(7)
			eq(a.color, b.color, "color")
			eq(a.scale, b.scale, "scale")
			eq(a.topper, b.topper, "topper")
			local colors, scales, toppers = {}, {}, {}
			for id = 1, 120 do
				local l = FollowerLook.of(id)
				colors[table.concat(l.color, ",")] = true
				scales[string.format("%.3f", l.scale)] = true
				toppers[l.topper] = true
			end
			local nc, ns = 0, 0
			for _ in colors do
				nc += 1
			end
			for _ in scales do
				ns += 1
			end
			eq(nc, #FollowerLook.PALETTE, "every palette tone is used (a blue family, issue 206)")
			assert(ns >= 60, "sizes vary")
			assert(toppers.hat and toppers.flower and toppers.none, "hats, flowers and bare heads")
		end,
	},
	{
		name = "every knob stays inside its named range",
		run = function()
			for id = 1, 200 do
				local l = FollowerLook.of(id)
				assert(
					l.scale >= FollowerLook.SCALE_MIN and l.scale <= FollowerLook.SCALE_MAX,
					"scale"
				)
				assert(
					l.bounce >= FollowerLook.BOUNCE_MIN and l.bounce <= FollowerLook.BOUNCE_MAX,
					"bounce"
				)
				assert(
					l.tempo >= FollowerLook.TEMPO_MIN and l.tempo <= FollowerLook.TEMPO_MAX,
					"tempo"
				)
			end
		end,
	},
	{
		name = "bigger bounce than the old flat 0.25 studs, out of phase between followers",
		run = function()
			assert(FollowerLook.BOUNCE_MIN >= 0.5, "bigger bounce")
			local ys = {}
			for id = 1, 10 do
				ys[id] = FollowerLook.march(FollowerLook.of(id), 1.234).y
			end
			local lo, hi = math.huge, -math.huge
			for _, y in ys do
				lo, hi = math.min(lo, y), math.max(hi, y)
			end
			assert(hi - lo > 0.3, "followers are at different points of their step")
		end,
	},
	{
		name = "squash and stretch: squashed on the foot, stretched at the top, volume kept roughly",
		run = function()
			local look = FollowerLook.of(3)
			local lo, hi = math.huge, -math.huge
			for i = 0, 400 do
				local m = FollowerLook.march(look, i * 0.01)
				lo, hi = math.min(lo, m.squashY), math.max(hi, m.squashY)
				assert(math.abs(m.squashY * m.squashXZ * m.squashXZ - 1) < 1e-9, "volume")
			end
			assert(
				lo < 1 - FollowerLook.SQUASH * 0.9 and hi > 1 + FollowerLook.SQUASH * 0.9,
				"range"
			)
		end,
	},
	{
		name = "footfall fires once per step; dust is a small seeded share; breath pulses on the beat",
		run = function()
			local look = FollowerLook.of(5)
			local falls = 0
			for i = 1, 600 do
				if FollowerLook.footfall(look, (i - 1) / 60, i / 60) then
					falls += 1
				end
			end
			local expected = 10 * look.tempo * 0.5 / math.pi
			assert(
				math.abs(falls - expected) <= 1.5,
				`{falls} footfalls in 10 s, expected about {expected}`
			)
			local dust = 0
			for n = 1, 1000 do
				if FollowerLook.raisesDust(5, n) then
					dust += 1
				end
			end
			assert(dust > 60 and dust < 200, `dust share {dust}/1000`)
			local lo, hi = math.huge, -math.huge
			for i = 0, 400 do
				local b = FollowerLook.breath(i * 60 / Config.music.bpm / 100)
				lo, hi = math.min(lo, b), math.max(hi, b)
			end
			assert(
				hi <= 1 + FollowerLook.BREATH + 1e-9 and lo >= 1 - FollowerLook.BREATH - 1e-9,
				"bounded"
			)
			assert(hi - lo > FollowerLook.BREATH, "visible pulse")
			assert(FollowerLook.DUST_CAP <= 10, "dust is capped")
		end,
	},
	{
		name = "lean follows sideways speed, bounded, mirrored by sign",
		run = function()
			eq(FollowerLook.lean(0), 0, "still")
			assert(FollowerLook.lean(5) < 0 and FollowerLook.lean(-5) > 0, "opposite signs")
			eq(FollowerLook.lean(1e6), -FollowerLook.MAX_LEAN, "capped")
			eq(FollowerLook.lean(-1e6), FollowerLook.MAX_LEAN, "capped other way")
		end,
	},
}
