--!strict
-- Issue #65, owner direction 2026-10-25: "I can hardly see anything, the people are in grouped
-- bunches ... we want random individuals coming at the player." Spectators are INDIVIDUAL
-- figures spread across the lane, never grouped bunches above a set size, every figure
-- individually visible, within the on-screen budget. Pure: SpectatorScatter and its Config.
-- Required lazily so every case fails by name until the module exists (fail-first).
local CameraRig = require("../src/shared/CameraRig")
local Config = require("../src/shared/Config")
local Emergence = require("../src/shared/Emergence")
local MobLod = require("../src/shared/MobLod")
local QualityConfig = require("../src/shared/QualityConfig")

local function scatter()
	return require("../src/shared/SpectatorScatter")
end

local function params()
	return Config.spectators.scatter
end

local function dist(a: { dx: number, dz: number }, b: { dx: number, dz: number }): number
	local x, z = a.dx - b.dx, a.dz - b.dz
	return math.sqrt(x * x + z * z)
end

return {
	{
		name = "scatter config: every tunable lives in Config.spectators.scatter and validates",
		run = function()
			local p = params()
			assert(p ~= nil, "Config.spectators.scatter exists")
			for _, key in
				{
					"perReward",
					"spreadHalfWidth",
					"colSpacing",
					"rowSpacing",
					"jitter",
					"minSeparation",
					"bunchRadius",
					"maxBunch",
					"minScreenFraction",
					"maxScale",
				}
			do
				local v = (p :: any)[key]
				assert(
					type(v) == "number" and v > 0 and v < math.huge,
					`scatter.{key} must be a positive number`
				)
			end
			assert(p.jitter < 0.5, "scatter.jitter stays inside half a cell")
			assert(
				p.maxBunch >= 1 and p.maxBunch == math.floor(p.maxBunch),
				"scatter.maxBunch is a whole count"
			)
			local ok, why = Config.validate(Config)
			assert(ok, `Config.validate: {why}`)
		end,
	},
	{
		name = "place: every individual gets its own spot: no two closer than minSeparation",
		run = function()
			local p = params()
			for _, n in { 1, 2, 7, 13, 24, 40 } do
				for seed = 1, 5 do
					local offs = scatter().place(n, seed, p)
					assert(#offs == n, `place({n}) returned {#offs}`)
					for i = 1, n do
						for j = i + 1, n do
							local d = dist(offs[i], offs[j])
							assert(
								d >= p.minSeparation,
								`n={n} seed={seed}: {i} and {j} are {d} apart, minSeparation {p.minSeparation}`
							)
						end
					end
				end
			end
		end,
	},
	{
		name = "no grouped bunches: no individual has more than maxBunch-1 neighbours within bunchRadius",
		run = function()
			local p = params()
			local worst = 0
			for _, n in { 7, 13, 24, 40 } do
				for seed = 1, 10 do
					local offs = scatter().place(n, seed, p)
					for i = 1, n do
						local near = 0
						for j = 1, n do
							if j ~= i and dist(offs[i], offs[j]) <= p.bunchRadius then
								near += 1
							end
						end
						worst = math.max(worst, near + 1)
						assert(
							near + 1 <= p.maxBunch,
							`n={n} seed={seed}: individual {i} sits in a bunch of {near + 1} (maxBunch {p.maxBunch})`
						)
					end
				end
			end
			print(
				`bunch: largest group within bunchRadius {p.bunchRadius} studs = {worst} (maxBunch {p.maxBunch})`
			)
		end,
	},
	{
		name = "spread across the lane: lateral offsets fill most of the lane and stay inside the street",
		run = function()
			local p = params()
			for _, n in { 8, 16, 24 } do
				local offs = scatter().place(n, 3, p)
				local lo, hi = math.huge, -math.huge
				for _, o in offs do
					assert(
						math.abs(o.dx) <= p.spreadHalfWidth + 1e-6,
						`dx {o.dx} outside spreadHalfWidth {p.spreadHalfWidth}`
					)
					lo, hi = math.min(lo, o.dx), math.max(hi, o.dx)
				end
				local span = hi - lo
				assert(
					span >= 0.6 * 2 * p.spreadHalfWidth,
					`n={n}: lateral span {span} is under 60% of the lane {2 * p.spreadHalfWidth}`
				)
				assert(
					p.spreadHalfWidth + MobLod.FIGURE_HALF <= MobLod.STREET_LIMIT_X,
					"spreadHalfWidth plus a figure stays inside STREET_LIMIT_X"
				)
			end
		end,
	},
	{
		name = "random individuals, not a stamped pattern: offsets differ by seed and by individual",
		run = function()
			local p = params()
			local a = scatter().place(24, 1, p)
			local b = scatter().place(24, 2, p)
			local same = true
			for i = 1, 24 do
				if math.abs(a[i].dx - b[i].dx) > 1e-6 or math.abs(a[i].dz - b[i].dz) > 1e-6 then
					same = false
				end
			end
			assert(not same, "two seeds give the same layout")
			local distinct: { [string]: boolean } = {}
			for _, o in a do
				distinct[string.format("%.2f", o.dx)] = true
			end
			local count = 0
			for _ in distinct do
				count += 1
			end
			assert(count >= 20, `only {count} distinct lateral positions out of 24 individuals`)
			-- reproducible from the seed
			local again = scatter().place(24, 1, p)
			for i = 1, 24 do
				assert(a[i].dx == again[i].dx and a[i].dz == again[i].dz, "same seed, same layout")
			end
		end,
	},
	{
		name = "individuals per cluster: grows with reward, never above the per-mob figure cap, any quality",
		run = function()
			local p = params()
			for _, name in QualityConfig.NAMES do
				local cap = QualityConfig.get(name).maxFiguresPerMob
				local last = -1
				for reward = 0, 60 do
					local n = scatter().individuals(reward, name, p)
					assert(
						n >= 0 and n <= cap,
						`{name} reward {reward}: {n} individuals, cap {cap}`
					)
					assert(n >= last, `{name} reward {reward}: count fell from {last} to {n}`)
					last = n
				end
				assert(
					scatter().individuals(5, name, p) >= 1,
					`{name}: a small cluster still has spectators`
				)
			end
		end,
	},
	{
		name = "on-screen budget: allocation never exceeds maxFigures or maxMobs, nearest mobs first, any quality",
		run = function()
			for _, name in QualityConfig.NAMES do
				local level = QualityConfig.get(name)
				local mobs = {}
				for _ = 1, 23 do
					table.insert(mobs, { count = level.maxFiguresPerMob, fade = 1 })
				end
				local shown = scatter().allocate(mobs, name)
				local total = 0
				for i, s in shown do
					assert(s <= level.maxFiguresPerMob, `{name}: mob {i} shows {s}`)
					if i > level.maxMobs then
						assert(s == 0, `{name}: mob {i} past maxMobs is drawn`)
					end
					total += s
				end
				assert(
					total <= level.maxFigures,
					`{name}: {total} figures on screen, budget {level.maxFigures}`
				)
				assert(
					shown[1] == level.maxFiguresPerMob,
					`{name}: the nearest mob gets its full group first`
				)
			end
		end,
	},
	{
		name = "emergence without pops: a mob still fading in shows fewer individuals; each rises out of the road one at a time",
		run = function()
			local name = QualityConfig.DEFAULT
			local full = scatter().allocate({ { count = 20, fade = 1 } }, name)[1]
			local half = scatter().allocate({ { count = 20, fade = 0.5 } }, name)[1]
			local none = scatter().allocate({ { count = 20, fade = 0 } }, name)[1]
			assert(
				none == 0 and half < full and half > 0,
				`fade 0/0.5/1 shows {none}/{half}/{full}`
			)
			for k = 1, 20 do
				local last = -1
				for step = 0, 40 do
					local r = scatter().risen(k, 20, step / 40)
					assert(r >= 0 and r <= 1, `risen out of 0..1: {r}`)
					assert(r >= last - 1e-9, `risen fell for individual {k}`)
					last = r
				end
				assert(
					scatter().risen(k, 20, 0) == 0 and scatter().risen(k, 20, 1) == 1,
					"risen runs 0 to 1"
				)
			end
		end,
	},
	{
		name = "every figure individually visible: at the visible depth a figure reads at minScreenFraction, scaled up to maxScale at most, and never scaled when it already reads",
		run = function()
			local p = params()
			for _, pullback in { 1, 1.4 } do
				local depth = Emergence.visibleDepthAhead(pullback)
				local pose = CameraRig.pose(0, 0, pullback)
				-- the farthest visible individual is the one that must still read on a phone
				local frac = CameraRig.screenFraction(pose, 1.1, depth - 2, 2.2)
				local s = scatter().legibleScale(frac, p)
				assert(
					s <= p.maxScale + 1e-9,
					`pullback {pullback}: scale {s} above maxScale {p.maxScale}`
				)
				assert(
					frac * s >= p.minScreenFraction,
					`pullback {pullback}: a figure at the visible depth reads at {frac * s} of the screen height (scale {s}), minScreenFraction {p.minScreenFraction}`
				)
				local near = CameraRig.screenFraction(pose, 1.1, 10, 2.2)
				assert(
					scatter().legibleScale(near, p) == 1,
					"a figure that already reads is not scaled"
				)
			end
		end,
	},
}
