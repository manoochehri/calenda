--!strict
-- Issue #65, mobs: quality levels, charge motion and palettes. All pure.
local MobCharge = require("../src/shared/MobCharge")
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
					"maxMobs",
					"maxFigures",
					"maxFiguresPerMob",
					"maxDust",
					"maxStream",
					"puff",
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
							`{n}: mobs<={q.maxMobs} figures<={q.maxFigures} (<={q.maxFiguresPerMob}/mob) emitters<={QualityConfig.maxEmitters(
								n
							)} stream<={q.maxStream}`
						)
					end
					return rows
				end)(),
				" | "
			))
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
