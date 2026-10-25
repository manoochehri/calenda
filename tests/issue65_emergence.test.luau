--!strict
-- Issue #65, tension from the top: waves emerge from beyond the camera's view, are seen for at
-- least 3 s, nothing is in view during the calm opening, and nothing pops.
local CameraRig = require("../src/shared/CameraRig")
local Config = require("../src/shared/Config")
local DebugLayout = require("../src/shared/DebugLayout")
local Emergence = require("../src/shared/Emergence")
local LayoutValidator = require("../src/shared/LayoutValidator")
local Level = require("../src/shared/Level")

local function near(a: number, b: number, name: string)
	assert(math.abs(a - b) < 1e-6, `{name}: expected {b}, got {a}`)
end

-- A one-cluster layout whose cluster spawns `offset` studs ahead of the lead at `spawnTime`.
local function oneWave(spawnTime: number, offset: number): Level.Layout
	local base = table.clone(DebugLayout :: any)
	base.clusters = {
		{
			id = 1,
			wave = 1,
			type = "small",
			spawnTime = spawnTime,
			spawn = { x = -16, z = Config.speed * spawnTime + offset },
			path = {},
		},
	}
	return base
end

return {
	{
		name = "visible depth comes from the camera pose and is the same for 16:9, 4:3 and 19.5:9 (vertical FOV)",
		run = function()
			local lo, hi = Emergence.depthRange()
			assert(lo > 100 and lo < hi and hi < 400, `depth range {lo}..{hi}`)
			-- the top edge ray at pullback 1, checked by hand against the pose
			local pose = CameraRig.pose(0, 0, 1)
			local ray = math.rad(CameraRig.pitchDegrees(pose) - CameraRig.FIELD_OF_VIEW / 2)
			near(Emergence.visibleDepthAhead(1), pose.pz + pose.py / math.tan(ray), "hand check")
			-- the depth is independent of aspect; only the width at that depth changes, and every
			-- target aspect still shows the sidewalks (|x| = halfWidth) at the far edge
			for _, aspect in Emergence.ASPECTS do
				for _, pull in { 1.0, 1.4 } do
					local w = Emergence.halfWidthAt(pull, Emergence.visibleDepthAhead(pull), aspect)
					assert(w > DebugLayout.halfWidth * 3, `aspect {aspect}: half width {w}`)
				end
			end
			local narrow = Emergence.halfWidthAt(1, hi, 4 / 3)
			local wide = Emergence.halfWidthAt(1, hi, 19.5 / 9)
			assert(wide > narrow, "wider screens see more width, same depth")
		end,
	},
	{
		name = "required spawn offset exceeds the deepest visible depth by the margin",
		run = function()
			local _, hi = Emergence.depthRange()
			near(Emergence.requiredSpawnOffset(), hi + Emergence.SPAWN_MARGIN, "offset")
			assert(Emergence.requiredSpawnOffset() > 150, "far beyond the old 15-40 stud pop-in")
		end,
	},
	{
		name = "spawn rule: the pre-#65 debug layout offsets (15-40 studs) are rejected, the real layout passes",
		run = function()
			local errs = Emergence.check(oneWave(1, 30))
			assert(#errs >= 2, "pop-in and approach time rejected")
			assert(string.find(errs[1], "visible depth", 1, true), errs[1])
			local ok = oneWave(1, Emergence.requiredSpawnOffset() + 40)
			-- calm opening too: first in view must be at or after 5 s
			ok.clusters[1].spawnTime = 1
			ok.clusters[1].spawn = { x = -16, z = Config.speed * 1 + 400 }
			assert(#Emergence.check(ok) == 0, table.concat(Emergence.check(ok), "|"))
			assert(
				#Emergence.check(DebugLayout) == 0,
				table.concat(Emergence.check(DebugLayout), "|")
			)
		end,
	},
	{
		name = "every DebugLayout cluster spawns beyond the camera's reach at max pullback + margin",
		run = function()
			local need = Emergence.requiredSpawnOffset()
			for _, c in DebugLayout.clusters do
				assert(c.spawnTime >= 0, `cluster {c.id} spawns before the run`)
				local off = Emergence.spawnOffset(DebugLayout, c)
				assert(off >= need, `cluster {c.id} spawns {off} ahead, needs {need}`)
			end
		end,
	},
	{
		name = "approach time: at least 3 s in view at the closing speed, for every cluster and the worst camera",
		run = function()
			local lo = Emergence.depthRange()
			local closing = Config.speed + Config.spectators.approachSpeed
			assert(lo / closing >= Emergence.MIN_APPROACH_SECONDS, "closed form")
			local worst = math.huge
			for _, c in DebugLayout.clusters do
				worst = math.min(worst, Emergence.approachSeconds(DebugLayout, c, lo))
			end
			assert(worst >= Emergence.MIN_APPROACH_SECONDS, `shortest approach {worst} s`)
			print(
				`shortest visible approach {worst} s over {#DebugLayout.clusters} clusters (min {Emergence.MIN_APPROACH_SECONDS})`
			)
			-- a cluster that starts in view has zero visible approach
			near(
				Emergence.approachSeconds(oneWave(1, 30), oneWave(1, 30).clusters[1], lo),
				0,
				"pop"
			)
		end,
	},
	{
		name = "calm opening: nothing in view before CALM_OPENING_SECONDS in DebugLayout; a wave at 2 s is rejected",
		run = function()
			local lo = Emergence.depthRange()
			local first = Emergence.firstVisibleTime(DebugLayout, lo)
			assert(first >= Emergence.CALM_OPENING_SECONDS, `first wave in view at {first} s`)
			assert(first < 8, `the calm opening is not longer than 8 s, got {first}`)
			print(
				`first wave in view at {first} s (calm opening {Emergence.CALM_OPENING_SECONDS} s)`
			)
			local early = oneWave(0, Emergence.requiredSpawnOffset() + 10)
			local errs = Emergence.check(early)
			local found = false
			for _, e in errs do
				if string.find(e, "calm opening", 1, true) then
					found = true
				end
			end
			assert(found, "an early wave must break the calm opening rule")
		end,
	},
	{
		name = "LayoutValidator applies the emergence rules",
		run = function()
			assert(
				LayoutValidator.check(DebugLayout).ok,
				table.concat(LayoutValidator.check(DebugLayout).errors, "|")
			)
			local bad = table.clone(DebugLayout :: any)
			bad.clusters = table.clone(DebugLayout.clusters :: any)
			local c = table.clone(bad.clusters[1])
			c.spawnTime, c.spawn = 1, { x = c.spawn.x, z = Config.speed + 30 }
			bad.clusters[1] = c
			local r = LayoutValidator.check(bad)
			assert(not r.ok, "pop-in layout must fail")
			local mentioned = false
			for _, e in r.errors do
				if string.find(e, "visible depth", 1, true) then
					mentioned = true
				end
			end
			assert(mentioned, table.concat(r.errors, "|"))
		end,
	},
	{
		name = "fade curve: 0 at the top edge, 1 inside the band, monotone, never a step (no pop)",
		run = function()
			local depth = 150
			near(Emergence.fade(depth + 50, depth), 0, "beyond")
			near(Emergence.fade(depth, depth), 0, "at the edge")
			near(Emergence.fade(depth - Emergence.FADE_BAND, depth), 1, "inside")
			near(Emergence.fade(0, depth), 1, "near")
			local prev = 0
			local biggestStep = 0
			for ahead = depth, 0, -0.5 do
				local f = Emergence.fade(ahead, depth)
				assert(f >= prev - 1e-12, "monotone as it approaches")
				biggestStep = math.max(biggestStep, f - prev)
				prev = f
			end
			assert(biggestStep < 0.05, `largest fade step per half stud {biggestStep}`)
			near(Emergence.scaleIn(depth, depth), Emergence.SCALE_FROM, "scale starts small")
			near(Emergence.scaleIn(0, depth), 1, "scale ends full")
			-- every DebugLayout cluster is fully faded out at its spawn point (nothing can pop)
			local _, hi = Emergence.depthRange()
			for _, c in DebugLayout.clusters do
				near(
					Emergence.fade(Emergence.spawnOffset(DebugLayout, c), hi),
					0,
					`spawn fade {c.id}`
				)
			end
		end,
	},
	{
		name = "telegraph, threat and pulse curves are bounded and rise as the wave closes in",
		run = function()
			local depth = 150
			near(Emergence.telegraph(depth + 200, depth), 0, "no chevron far beyond the spawn")
			assert(Emergence.telegraph(depth, depth) > 0.99, "chevron at the top edge")
			near(
				Emergence.telegraph(depth * 0.3, depth),
				0,
				"chevron gone once the mob can be read"
			)
			near(Emergence.threat(Emergence.THREAT_FAR + 10), 0, "no threat far away")
			near(Emergence.threat(Emergence.THREAT_NEAR - 5), 1, "full threat at the lead")
			local prev = 0
			for ahead = Emergence.THREAT_FAR, 0, -1 do
				local t = Emergence.threat(ahead)
				assert(t >= prev - 1e-12 and t <= 1, "threat monotone and bounded")
				prev = t
			end
			assert(Emergence.pulseRate(1) > Emergence.pulseRate(0), "faster pulse when close")
			for phase = 0, 3, 0.1 do
				local p = Emergence.pulse(0.7, phase)
				assert(p >= 0 and p <= 0.7 + 1e-9, "pulse stays within the threat")
			end
			near(Emergence.pulse(0, 0.3), 0, "no pulse without threat")
		end,
	},
	{
		name = "DebugLayout never needs more mobs on screen than the pools hold (visible cluster cap and quality mob caps)",
		run = function()
			local lo, hi = Emergence.depthRange()
			local worst, worstSeen = 0, 0
			for k = 0, 90 * 30 do
				local t = k / 30
				local n = 0
				for _, c in DebugLayout.clusters do
					if t >= c.spawnTime then
						local ahead = Level.clusterPosition(DebugLayout, c.id, t).z - Level.leadZ(t)
						if ahead > 0 and ahead <= hi + Emergence.SPAWN_MARGIN then
							n += 1
						end
					end
				end
				worst = math.max(worst, n)
				local seen = 0
				for _, c in DebugLayout.clusters do
					if t >= c.spawnTime then
						local ahead = Level.clusterPosition(DebugLayout, c.id, t).z - Level.leadZ(t)
						if ahead > 0 and ahead <= lo then
							seen += 1
						end
					end
				end
				worstSeen = math.max(worstSeen, seen)
			end
			print(
				`most mobs at once: {worst} in the draw band, {worstSeen} inside the top edge at the closest camera`
			)
			assert(
				worst <= require("../src/shared/ClusterVisual").MAX_VISIBLE_CLUSTERS,
				"cluster cap"
			)
			assert(
				worstSeen <= require("../src/shared/QualityConfig").get("low").maxMobs,
				"even low quality draws every mob inside the top edge"
			)
		end,
	},
}
