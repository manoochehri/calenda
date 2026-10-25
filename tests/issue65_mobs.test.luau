--!strict
-- Issue #65, mobs: size from reward and quality, LOD split, caps, wedge slots, particle rate,
-- charge motion and palettes. All pure.
local MobCharge = require("../src/shared/MobCharge")
local MobLod = require("../src/shared/MobLod")
local QualityConfig = require("../src/shared/QualityConfig")

local function near(a: number, b: number, name: string)
	assert(math.abs(a - b) < 1e-6, `{name}: expected {b}, got {a}`)
end

return {
	{
		name = "quality config: three levels, resolve falls back, caps shrink from high to low",
		run = function()
			assert(#QualityConfig.NAMES == 3, "#QualityConfig.NAMES == 3")
			assert(
				QualityConfig.resolve("bogus") == QualityConfig.DEFAULT,
				"QualityConfig.resolve('bogus') == QualityConfig.DEFAULT"
			)
			assert(
				QualityConfig.resolve(nil) == QualityConfig.DEFAULT,
				"QualityConfig.resolve(nil) == QualityConfig.DEFAULT"
			)
			assert(QualityConfig.resolve("low") == "low", "QualityConfig.resolve('low') == 'low'")
			assert(QualityConfig.defaultFor(true) == "medium", "phone-safe default")
			local h, m, l =
				QualityConfig.get("high"), QualityConfig.get("medium"), QualityConfig.get("low")
			for _, key in
				{
					"maxMobSize",
					"maxMobs",
					"maxFigures",
					"maxFiguresPerMob",
					"maxDots",
					"maxTotalDots",
					"maxDust",
					"maxStream",
					"puff",
					"mobScale",
				}
			do
				local k = key :: string
				assert(
					(h :: any)[k] > (m :: any)[k] and (m :: any)[k] > (l :: any)[k],
					`{k} must shrink high > medium > low`
				)
			end
			print("caps: " .. table.concat(
				(function()
					local rows = {}
					for _, n in QualityConfig.NAMES do
						local q = QualityConfig.get(n)
						table.insert(
							rows,
							`{n}: mobSize<={q.maxMobSize} mobs<={q.maxMobs} figures<={q.maxFigures} (<={q.maxFiguresPerMob}/mob, {q.maxFigures * 3} parts) dots<={q.maxDots}/mob, <={q.maxTotalDots} total, emitters<={QualityConfig.maxEmitters(
								n
							)}, stream<={q.maxStream}`
						)
					end
					return rows
				end)(),
				" | "
			))
		end,
	},
	{
		name = "mob size grows with reward and quality; never above the cap for ANY reward and quality",
		run = function()
			local small = MobLod.mobSize(5, "medium")
			local large = MobLod.mobSize(15, "medium")
			assert(small >= 100 and large > small, `hundreds of spectators: {small}, {large}`)
			assert(
				MobLod.mobSize(15, "high") > MobLod.mobSize(15, "medium"),
				"MobLod.mobSize(15, 'high') > MobLod.mobSize(15, 'medium')"
			)
			assert(
				MobLod.mobSize(15, "medium") > MobLod.mobSize(15, "low"),
				"MobLod.mobSize(15, 'medium') > MobLod.mobSize(15, 'low')"
			)
			for _, q in QualityConfig.NAMES do
				local cap = QualityConfig.get(q).maxMobSize
				local prev = 0
				for reward = 0, 20000 do
					local s = MobLod.mobSize(reward, q)
					assert(
						s <= cap and s >= MobLod.MIN_MOB or s == cap,
						`{q} reward {reward} size {s}`
					)
					assert(s >= prev, "monotone in reward")
					prev = s
				end
				assert(MobLod.mobSize(math.huge, q) <= cap, "infinite reward is capped")
				assert(MobLod.mobSize(0 / 0, q) >= 1, "NaN reward still gives a bounded mob")
				assert(MobLod.mobSize(-5, q) <= cap, "negative reward bounded")
			end
			assert(
				MobLod.mobSize(15, "high") >= 1000,
				"thousands at high quality for a large group"
			)
		end,
	},
	{
		name = "LOD split: figures + particles conserve the mob size until a cap bites; figures fall as the mob shrinks on screen",
		run = function()
			for _, q in QualityConfig.NAMES do
				local level = QualityConfig.get(q)
				local size = MobLod.mobSize(15, q)
				local prev = math.huge
				for i = 0, 20 do
					local w = i / 20
					local s = MobLod.split(size, 1 - w, q) -- w grows = farther
					assert(s.figures <= level.maxFiguresPerMob, "per-mob figure cap")
					assert(s.dots <= level.maxDots, "per-mob particle cap")
					assert(s.figures <= prev, "figures never increase as the mob gets farther")
					prev = s.figures
					if size - s.figures <= level.maxDots then
						assert(s.figures + s.dots == size, "density conserved")
					end
				end
				local nearSplit = MobLod.split(size, 1, q)
				local far = MobLod.split(size, 0, q)
				assert(
					nearSplit.figures == math.min(size, level.maxFiguresPerMob),
					"all figures near"
				)
				assert(far.figures == 0, "all particles far")
			end
			assert(
				MobLod.nearWeight(1) == 1 and MobLod.nearWeight(0) == 0,
				"MobLod.nearWeight(1) == 1 and MobLod.nearWeight(0) == 0"
			)
			assert(
				MobLod.nearWeight(MobLod.NEAR_FRACTION) == 1
					and MobLod.nearWeight(MobLod.FAR_FRACTION) == 0,
				"near/far fractions are the weight limits"
			)
			local prev = 0
			for f = 0, 0.04, 0.0005 do
				local w = MobLod.nearWeight(f)
				assert(w >= prev - 1e-12, "weight monotone in screen size")
				prev = w
			end
		end,
	},
	{
		name = "allocate: global caps are never exceeded, for any number of mobs, rewards and quality",
		run = function()
			for _, q in QualityConfig.NAMES do
				local level = QualityConfig.get(q)
				for _, count in { 1, 5, 12, 40, 200 } do
					for _, reward in { 5, 15, 50, 500, 1e9 } do
						for _, weight in { 0, 0.3, 1 } do
							local mobs = {}
							for i = 1, count do
								table.insert(mobs, {
									size = MobLod.mobSize(reward, q),
									nearWeight = weight,
									fade = if i % 3 == 0 then 0.5 else 1,
								})
							end
							local out = MobLod.allocate(mobs, q)
							local figures, dots, drawn = 0, 0, 0
							for i, o in out do
								figures += o.figures
								dots += o.dots
								if o.drawn then
									drawn += 1
								end
								assert(
									o.figures <= level.maxFiguresPerMob and o.dots <= level.maxDots,
									`per-mob cap {q} #{i}`
								)
								assert(
									o.rate <= level.maxDots / MobLod.LIFETIME + 1e-9,
									"rate bounded by the dot cap"
								)
								assert(o.rate >= 0, "o.rate >= 0")
							end
							assert(
								figures <= level.maxFigures,
								`{q}: {figures} figures > {level.maxFigures}`
							)
							assert(
								dots <= level.maxTotalDots,
								`{q}: {dots} dots > {level.maxTotalDots}`
							)
							assert(drawn <= level.maxMobs, `{q}: {drawn} mobs > {level.maxMobs}`)
							assert(
								MobLod.emitterCount(drawn, q) <= QualityConfig.maxEmitters(q),
								"emitter cap"
							)
						end
					end
				end
			end
		end,
	},
	{
		name = "allocate: nearest mobs get the budget first; a mob still fading in is scaled down, not popped",
		run = function()
			local mobs = {}
			for _ = 1, 8 do
				table.insert(mobs, { size = 900, nearWeight = 1, fade = 1 })
			end
			local out = MobLod.allocate(mobs, "low")
			assert(
				out[1].figures == 30 and out[2].figures == 30 and out[3].figures == 30,
				"nearest first"
			)
			assert(out[4].figures == 10, "the 100-figure budget runs out")
			assert(out[5].figures == 0, "out[5].figures == 0")
			local fading = MobLod.allocate({ { size = 900, nearWeight = 0, fade = 0.5 } }, "medium")
			local solid = MobLod.allocate({ { size = 900, nearWeight = 0, fade = 1 } }, "medium")
			assert(fading[1].dots == math.floor(solid[1].dots * 0.5), "half faded = half density")
			assert(
				MobLod.allocate({ { size = 900, nearWeight = 0, fade = 0 } }, "medium")[1].dots == 0,
				"a fully faded mob draws nothing"
			)
		end,
	},
	{
		name = "particle rate from size: Rate = dots / Lifetime (Number of particles = Rate * Lifetime)",
		run = function()
			near(MobLod.rate(700), 700 / MobLod.LIFETIME, "rate")
			near(MobLod.rate(0), 0, "no dots, no rate")
			assert(MobLod.rate(900) > MobLod.rate(300), "bigger mob, higher rate")
			for _, q in QualityConfig.NAMES do
				local level = QualityConfig.get(q)
				local o = MobLod.allocate({ { size = 1e9, nearWeight = 0, fade = 1 } }, q)[1]
				near(o.rate * MobLod.LIFETIME, level.maxDots, `{q} live particles at the cap`)
			end
		end,
	},
	{
		name = "footprint grows with size but stays within the street",
		run = function()
			local w1, d1 = MobLod.footprint(300)
			local w2 = MobLod.footprint(1200)
			assert(w2 > w1 and d1 > w1, "w2 > w1 and d1 > w1")
			assert(
				MobLod.footprint(1e9) <= MobLod.MAX_WIDTH,
				"MobLod.footprint(1e9) <= MobLod.MAX_WIDTH"
			)
		end,
	},
	{
		name = "wedge slots: apex at the front, rows widen, all distinct, inside the footprint, symmetric",
		run = function()
			local width, depth = 12, 12
			for _, n in { 1, 4, 9, 30, 60, 90 } do
				local seen: { [string]: boolean } = {}
				local sumX = 0
				for i = 1, n do
					local dx, dz = MobCharge.wedgeSlot(i, n, width, depth)
					assert(
						math.abs(dx) <= width / 2 + MobCharge.SPACING_MAX,
						`slot {i}/{n} dx {dx}`
					)
					assert(
						dz >= -MobCharge.SPACING_MAX and dz <= depth + MobCharge.SPACING_MAX,
						`slot {i}/{n} dz {dz}`
					)
					local key = string.format("%.3f,%.3f", dx, dz)
					assert(not seen[key], "distinct slots")
					seen[key] = true
					sumX += dx
				end
				if n >= 4 then
					assert(math.abs(sumX / n) < 0.4, `centered lateral mean for {n}: {sumX / n}`)
				end
			end
			-- slot 1 is the apex; deeper rows are wider
			local _, z1 = MobCharge.wedgeSlot(1, 30, width, depth)
			local lo, hi = math.huge, -math.huge
			for i = 2, 4 do
				local dx = MobCharge.wedgeSlot(i, 30, width, depth)
				lo, hi = math.min(lo, dx), math.max(hi, dx)
			end
			local _, z5 = MobCharge.wedgeSlot(5, 30, width, depth)
			assert(z5 > z1, "later rows are behind the front")
			local wideLo, wideHi = math.huge, -math.huge
			for i = 10, 16 do
				local dx = MobCharge.wedgeSlot(i, 30, width, depth)
				wideLo, wideHi = math.min(wideLo, dx), math.max(wideHi, dx)
			end
			assert(wideHi - wideLo > hi - lo, "the wedge widens toward the back")
		end,
	},
	{
		name = "charge motion: forward lean, raised pumping arms, hop; slam and dispersal envelopes are bounded",
		run = function()
			for i = 1, 50 do
				for c = 0, 3, 0.07 do
					local hop, lean, arm = MobCharge.stride(i, c)
					assert(
						hop >= 0 and hop <= MobCharge.STRIDE_HOP + 1e-9,
						"hop >= 0 and hop <= MobCharge.STRIDE_HOP + 1e-9"
					)
					assert(lean > 0.1, "leans forward")
					assert(
						arm >= MobCharge.ARM_UP - MobCharge.ARM_PUMP - 1e-9
							and arm > MobCharge.ARM_DOWN,
						"arms raised"
					)
				end
			end
			near(MobCharge.slam(-1), 0, "before")
			assert(
				MobCharge.slam(0) == 1 and MobCharge.slam(MobCharge.SLAM_SECONDS) == 0,
				"MobCharge.slam(0) == 1 and MobCharge.slam(MobCharge.SLAM_SECONDS) == 0"
			)
			assert(
				MobCharge.slamDepth(0) == 1
					and MobCharge.slamDepth(1) == 1 - MobCharge.SLAM_COMPRESS,
				"slam depth"
			)
			-- dispersal: heads for the sidewalk on its own side, hops, then sinks out of sight
			local x0, hop0, sink0 = MobCharge.disperse(-3, -16, 0)
			near(x0, -3, "starts in place")
			near(hop0, 0, "no hop yet")
			near(sink0, 0, "not sunk")
			local x1, _, sink1 = MobCharge.disperse(-3, -16, 1)
			near(x1, -MobCharge.SIDEWALK_X, "ends on the left sidewalk")
			near(sink1, MobCharge.SINK, "fully sunk")
			local xr = MobCharge.disperse(4, -16, 1)
			near(xr, MobCharge.SIDEWALK_X, "a figure right of centre goes right")
			for f = 0, 1, 0.02 do
				local _, hop, sink = MobCharge.disperse(2, 16, f)
				assert(
					hop >= 0
						and hop <= MobCharge.DISPERSE_HOP + 1e-9
						and sink >= 0
						and sink <= MobCharge.SINK + 1e-9,
					"dispersal hop and sink stay bounded"
				)
			end
		end,
	},
	{
		name = "converted mobs recolour to the party palette and thin out as they stream into the parade",
		run = function()
			near(MobCharge.partyMix(0), 0, "angry at the fill")
			near(MobCharge.partyMix(MobCharge.RECOLOUR_SECONDS), 1, "party after")
			local ar, ag, ab = MobCharge.colour(1, 0, 0, false)
			local pr, _, pb = MobCharge.colour(1, 1, 0, false)
			assert(ar > 150 and pb > 200 and ar > pr, "red-orange before, blue-ish after")
			near(ar, MobCharge.ANGRY[1][1], "angry r")
			near(pr, MobCharge.PARTY[1][1], "party r")
			-- the alert pulse brightens an angry mob but not a party one
			local hr = MobCharge.colour(1, 0, 1, false)
			assert(hr > ar - 1e-9, "hr > ar - 1e-9")
			local qr = MobCharge.colour(1, 1, 1, false)
			near(qr, pr, "party ignores the pulse")
			assert(ag >= 0 and ab >= 0, "ag >= 0 and ab >= 0")
			near(MobCharge.streamKeep(0), 1, "all standing at the fill")
			near(MobCharge.streamKeep(MobCharge.STREAM_SECONDS), 0, "all streamed in")
			local prev = 1
			for s = 0, MobCharge.STREAM_SECONDS, 0.05 do
				local k = MobCharge.streamKeep(s)
				assert(k <= prev + 1e-12 and k >= 0, "monotone")
				prev = k
			end
		end,
	},
}
