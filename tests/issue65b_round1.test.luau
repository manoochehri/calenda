--!strict
-- Issue #65 round 1: rank-based admission (no pop, no orphan tags), lateral fit, quality override,
-- honest emitter/burst numbers, and the chevron's vertex positions.
local Emergence = require("../src/shared/Emergence")
local MobLod = require("../src/shared/MobLod")
local QualityConfig = require("../src/shared/QualityConfig")

local function near(a: number, b: number, name: string)
	assert(math.abs(a - b) < 1e-6, `{name}: expected {b}, got {a}`)
end

-- Corners of a bar (length L along its axis, width W) centred at (cx, cz) with yaw theta, the way
-- Roblox's CFrame.Angles(0, theta, 0) turns it: the +X axis goes to (cos, -sin) in (x, z).
local function corners(bar: Emergence.Bar): { { number } }
	local c, s = math.cos(bar.yaw), math.sin(bar.yaw)
	local ax, az = c, -s
	local bx, bz = s, c -- the +Z axis goes to (sin, cos)
	local out = {}
	for _, u in { -1, 1 } do
		for _, v in { -1, 1 } do
			table.insert(out, {
				bar.x + ax * u * bar.length / 2 + bx * v * bar.width / 2,
				bar.z + az * u * bar.length / 2 + bz * v * bar.width / 2,
			})
		end
	end
	return out
end

-- Separating-axis overlap test for two rectangles given by their corners (order irrelevant).
local function overlap(a: { { number } }, b: { { number } }): boolean
	for _, poly in { a, b } do
		for _, axis in { { poly[1], poly[2] }, { poly[1], poly[3] } } do
			local nx, nz = axis[2][1] - axis[1][1], axis[2][2] - axis[1][2]
			local function range(p: { { number } }): (number, number)
				local lo, hi = math.huge, -math.huge
				for _, q in p do
					local d = q[1] * nx + q[2] * nz
					lo, hi = math.min(lo, d), math.max(hi, d)
				end
				return lo, hi
			end
			local alo, ahi = range(a)
			local blo, bhi = range(b)
			if ahi < blo - 1e-9 or bhi < alo - 1e-9 then
				return false
			end
		end
	end
	return true
end

return {
	{
		name = "admission: never more than maxMobs drawn, nobody pops (fade steps are bounded), 23 mobs at every quality",
		run = function()
			for _, q in QualityConfig.NAMES do
				local cap = QualityConfig.get(q).maxMobs
				local adm = MobLod.admission(cap)
				local prev: { [number]: number } = {}
				local dt = 1 / 30
				for frame = 0, 600 do
					-- 23 mobs alive; every 0.5 s the nearest one leaves and a new one joins at the back
					local first = frame // 15
					local ids = {}
					for i = 0, 22 do
						table.insert(ids, first + i + 1)
					end
					local fades = adm:step(ids, dt)
					local drawn = 0
					for id, f in fades do
						assert(f >= 0 and f <= 1, "fade within 0..1")
						if f > 0 then
							drawn += 1
						end
						local before = prev[id]
						local step = if before == nil then f else math.abs(f - before)
						assert(
							step <= MobLod.ADMIT_RATE * dt + 1e-9,
							`{q}: mob {id} fade jumped {step} at frame {frame}`
						)
					end
					assert(drawn <= cap, `{q}: {drawn} mobs drawn, cap {cap}`)
					assert(adm:count() <= cap, "state never exceeds the cap")
					prev = table.clone(fades)
				end
			end
		end,
	},
	{
		name = "admission: nearest mobs are admitted; a farther one waits until a nearer one's slot frees, fading in from 0",
		run = function()
			local adm = MobLod.admission(2)
			local f = adm:step({ 1, 2, 3 }, 0.1)
			assert(f[3] == nil, "the third waits")
			assert(f[1] ~= nil and f[2] ~= nil, "two admitted")
			for _ = 1, 40 do
				f = adm:step({ 1, 2, 3 }, 0.1)
			end
			near(f[1], 1, "nearest full")
			-- mob 0 appears nearer than everyone: the farthest occupant (2) fades out, then 0 fades in
			local sawBoth = false
			for _ = 1, 60 do
				f = adm:step({ 0, 1, 2, 3 }, 0.1)
				assert(adm:count() <= 2, "cap holds during the swap")
				if f[2] ~= nil and f[0] ~= nil then
					sawBoth = true
				end
			end
			near(f[0] or 0, 1, "mob 0 admitted")
			near(f[1] or 0, 1, "mob 1 stays")
			assert(f[2] == nil, "mob 2 faded out and left")
			assert(not sawBoth, "a newcomer waits for the slot instead of exceeding the cap")
			-- a mob that disappears is dropped at once
			f = adm:step({ 0 }, 0.1)
			assert(f[1] == nil, "gone mob dropped")
		end,
	},
	{
		name = "lateral fit: a mob at the sidewalk never reaches |x| 21.5 at any quality, reward or side",
		run = function()
			for _, q in QualityConfig.NAMES do
				for _, reward in { 1, 5, 15, 100, 1e9 } do
					for _, cx in { -20, -16, -5, 0, 5, 16, 20 } do
						local size = MobLod.mobSize(reward, q)
						local w = MobLod.footprint(size)
						local x = MobLod.lateralFit(cx, w)
						local edge = math.abs(x) + w / 2 + MobLod.FIGURE_HALF
						assert(
							edge <= MobLod.STREET_LIMIT_X + 1e-9,
							`{q} reward {reward} centre {cx}: edge {edge}`
						)
						assert(
							math.abs(x) <= math.abs(cx) + 1e-9,
							"only ever shifted toward the lane"
						)
					end
				end
			end
			near(MobLod.lateralFit(0, 8), 0, "a centred mob is left alone")
			near(MobLod.lateralFit(16, 6), 16, "a small mob at 16 does not move")
			print(`mob lateral limit: edge <= {MobLod.STREET_LIMIT_X} studs (facades start at 28)`)
		end,
	},
	{
		name = "quality override: attribute beats Config.debug.quality beats the touch default; garbage is ignored",
		run = function()
			assert(QualityConfig.pick("low", "high", false) == "low", "attribute wins")
			assert(QualityConfig.pick(nil, "high", true) == "high", "config next")
			assert(QualityConfig.pick("bogus", nil, true) == QualityConfig.TOUCH_DEFAULT, "garbage")
			assert(
				QualityConfig.pick(7, "nope", false) == QualityConfig.DESKTOP_DEFAULT,
				"garbage 2"
			)
			assert(QualityConfig.pick(nil, nil, false) == "high", "desktop default")
		end,
	},
	{
		name = "caps are stated honestly: emitters include the chevrons, bursts are counted",
		run = function()
			assert(QualityConfig.CHEVRONS == 6, "chevrons")
			assert(QualityConfig.maxEmitters("high") == 34, "high emitters")
			assert(QualityConfig.maxEmitters("medium") == 27, "medium emitters")
			assert(QualityConfig.maxEmitters("low") == 21, "low emitters")
			assert(QualityConfig.maxBurst("high") == 960, "high burst")
			assert(QualityConfig.maxBurst("medium") == 360, "medium burst")
			assert(QualityConfig.maxBurst("low") == 108, "low burst")
		end,
	},
	{
		name = "chevron: a 'v' pointing down the lane (apex at the lowest z), arms reach back toward the camera, bars do not overlap",
		run = function()
			for _, x in { -16, 0, 16 } do
				local bars = Emergence.chevronBars(x, 100)
				assert(#bars == 2, "two bars")
				local lowest, highest = math.huge, -math.huge
				local lowestX = 0
				for _, b in bars do
					for _, c in corners(b) do
						if c[2] < lowest then
							lowest, lowestX = c[2], c[1]
						end
						highest = math.max(highest, c[2])
					end
				end
				-- the lowest-z vertex sits at the middle (the apex), the highest at the outer ends
				assert(math.abs(lowestX - x) < 2, `apex x {lowestX} near the centre {x}`)
				for _, b in bars do
					local cs = corners(b)
					local far = cs[1]
					for _, c in cs do
						if math.abs(c[1] - x) > math.abs(far[1] - x) then
							far = c
						end
					end
					assert(
						far[2] > lowest + 1,
						"the outer end is farther along +z (toward the camera) than the apex"
					)
				end
				assert(highest - lowest > 3, "arms have real depth")
				assert(
					not overlap(corners(bars[1]), corners(bars[2])),
					"bars must not overlap coplanar"
				)
				-- mirror symmetry about the chevron's centre
				near(bars[1].x - x, -(bars[2].x - x), "symmetric x")
				near(bars[1].z, bars[2].z, "symmetric z")
			end
		end,
	},
	{
		name = "perturbation family (50 layouts, spawn time +-0.75 s, z +-8): no cluster spawns inside the visible depth; the 30-stud margin is NOT kept (reported)",
		run = function()
			local BotHarness = require("./helpers/BotHarness")
			local DebugLayout = require("../src/shared/DebugLayout")
			local _, hi = Emergence.depthRange()
			local need = Emergence.requiredSpawnOffset()
			local insideMargin, insideView, layoutsFailing, total = 0, 0, 0, 0
			local worst = math.huge
			for seed = 1, 50 do
				local l = BotHarness.perturb(DebugLayout, seed)
				if #Emergence.check(l) > 0 then
					layoutsFailing += 1
				end
				for _, c in l.clusters do
					total += 1
					local off = Emergence.spawnOffset(l, c)
					worst = math.min(worst, off - need)
					if off < need then
						insideMargin += 1
					end
					if off < hi then
						insideView += 1
					end
				end
			end
			print(
				`family: {layoutsFailing}/50 layouts fail Emergence.check; {insideMargin}/{total} clusters spawn inside depth+margin (worst {worst} studs); {insideView} inside the visible depth`
			)
			assert(insideView == 0, `{insideView} family clusters would pop inside the view`)
			assert(#Emergence.check(DebugLayout) == 0, "the fixed layout itself keeps every rule")
		end,
	},
}
