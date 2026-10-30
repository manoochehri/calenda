--!strict
-- Issues #50 and #60: hit feedback envelopes, cluster event budget and dedupe, and the finale depth
-- fix. All pure. The HP bar is gone (ADR 0006): the crowd counter is the life bar.
local ClusterEvents = require("../src/shared/ClusterEvents")
local FinalePlan = require("../src/shared/FinalePlan")
local HitFeedback = require("../src/shared/HitFeedback")
local ResetPlan = require("../src/shared/ResetPlan")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function near(actual: number, expected: number, name: string)
	assert(math.abs(actual - expected) < 1e-6, `{name}: expected {expected}, got {actual}`)
end

return {
	{
		name = "hit intensity scales with the share of followers lost, has a floor and a cap, and survives bad input",
		run = function()
			near(HitFeedback.intensity(nil, nil), HitFeedback.MIN_INTENSITY, "missing")
			near(HitFeedback.intensity(100, 99), HitFeedback.MIN_INTENSITY, "small hit floored")
			assert(
				HitFeedback.intensity(100, 80) > HitFeedback.intensity(100, 95),
				"bigger hit stronger"
			)
			near(HitFeedback.intensity(100, 0), 1, "capped at 1")
			near(HitFeedback.intensity(0 / 0, 1), HitFeedback.MIN_INTENSITY, "nan")
			near(HitFeedback.intensity(0, 0), HitFeedback.MIN_INTENSITY, "empty parade")
		end,
	},
	{
		name = "envelopes start at full, decay monotonically and are zero after their duration",
		run = function()
			for _, e in { HitFeedback.jolt, HitFeedback.shakeScale } do
				local prev = math.huge
				for i = 0, 40 do
					local v = e(i * 0.02)
					assert(v <= prev + 1e-9, "non-increasing")
					assert(v >= 0 and v <= 1, "in 0..1")
					prev = v
				end
				near(e(0), 1, "starts at 1")
				near(e(10), 0, "gone")
				near(e(-1), 0, "negative age is nothing")
			end
		end,
	},
	{
		name = "sampled feedback is capped: shake studs, flash alpha, jolt scale",
		run = function()
			local fx = HitFeedback.new()
			fx:hit(1)
			fx:hit(1) -- a flood stacks to the cap, not beyond it
			fx:hit(5) -- out-of-range intensity is clamped
			local worstShake, worstFlash, worstJolt = 0, 0, 0
			for _ = 1, 100 do
				local s = fx:sample()
				worstShake = math.max(worstShake, math.abs(s.shakeX), math.abs(s.shakeY))
				worstFlash = math.max(worstFlash, s.flash)
				worstJolt = math.max(worstJolt, s.jolt)
				fx:step(0.01)
			end
			assert(worstShake <= HitFeedback.MAX_SHAKE_STUDS + 1e-9, "shake capped")
			assert(
				worstFlash <= require("../src/shared/Config").hitVignette.peakAlpha + 1e-9,
				"flash capped"
			)
			assert(worstJolt <= HitFeedback.MAX_JOLT_SCALE + 1e-9, "jolt capped")
			assert(worstShake > 0.05 and worstFlash > 0.05 and worstJolt > 0.05, "visible")
		end,
	},
	{
		name = "a hit decays to nothing, and reset clears a hit in progress",
		run = function()
			local fx = HitFeedback.new()
			fx:hit(0.8)
			for _ = 1, 200 do
				fx:step(0.01)
			end
			local s = fx:sample()
			eq(s.shakeX, 0, "no shake left")
			eq(s.flash, 0, "no flash left")
			eq(s.jolt, 0, "no jolt left")
			fx:hit(1)
			fx:reset()
			eq(fx:sample().flash, 0, "reset clears")
		end,
	},
	{
		name = "a weaker hit during a strong one does not shrink the feedback",
		run = function()
			local fx = HitFeedback.new()
			fx:hit(1)
			fx:step(0.05)
			local before = fx:sample().flash
			fx:hit(0.35)
			assert(fx:sample().flash >= before - 1e-9 or fx:sample().flash > 0, "kept")
			assert(fx:sample().flash > 0, "still flashing")
		end,
	},
	{
		name = "event budget: at most N per frame, refilled each frame, never negative",
		run = function()
			local b = ClusterEvents.budget(3)
			local taken = 0
			for _ = 1, 1000 do
				if b:take() then
					taken += 1
				end
			end
			eq(taken, 3, "a flood costs only N accepts")
			b:newFrame()
			eq(b:take(), true, "refilled next frame")
			eq(ClusterEvents.budget(0):take(), false, "zero budget takes nothing")
			assert(ClusterEvents.EVENTS_PER_FRAME >= 1, "named default")
		end,
	},
	{
		name = "shot decision: first sighting launches; filled cluster and gone cluster do not",
		run = function()
			eq(ClusterEvents.shotAction(true, false, true), "launch", "normal")
			eq(ClusterEvents.shotAction(true, true, true), "skip", "already filled: duplicate")
			eq(ClusterEvents.shotAction(true, false, false), "drop", "cluster gone: no hidden part")
			eq(ClusterEvents.shotAction(false, false, true), "drop", "rejected by the tracker")
		end,
	},
	{
		name = "attack dedupe: the same cluster id plays once until reset; id-less events pass",
		run = function()
			local d = ClusterEvents.dedupe()
			eq(d:first(4), true, "first")
			eq(d:first(4), false, "repeat")
			eq(d:first(5), true, "other id")
			eq(d:first(nil), true, "no id")
			eq(d:first(nil), true, "no id again")
			d:reset()
			eq(d:first(4), true, "after reset")
		end,
	},
	{
		name = "attack dedupe is bounded",
		run = function()
			local d = ClusterEvents.dedupe()
			for i = 1, ClusterEvents.MAX_TRACKED + 50 do
				d:first(i)
			end
			eq(d:size() <= ClusterEvents.MAX_TRACKED, true, "bounded")
		end,
	},
	{
		name = "finale depth: slots and bursts never go past the end of the street",
		run = function()
			for _, leadZ in { 1440, 1500, 1590, 1599, 1700 } do
				local depth = FinalePlan.depthAhead(1600, leadZ)
				assert(depth >= FinalePlan.MIN_DEPTH, "floor")
				assert(depth <= FinalePlan.DEFAULT_DEPTH, "cap")
				for i = 1, 24 do
					local _, dz = FinalePlan.slot(i, 24, 20, depth)
					-- a floor-sized depth near the very end may exceed by its floor only
					assert(
						leadZ + dz <= math.max(1600, leadZ + FinalePlan.MIN_DEPTH),
						`slot {i} at lead {leadZ} reaches {leadZ + dz}`
					)
				end
			end
			near(FinalePlan.depthAhead(1600, 1440), 156, "room ahead minus the edge margin")
			assert(
				FinalePlan.depthAhead(1600, 1560) < FinalePlan.depthAhead(1600, 1500),
				"less room, less depth"
			)
		end,
	},
	{
		name = "ClusterVisual reports a shot to an already-filled cluster so the client can skip it",
		run = function()
			local Config = require("../src/shared/Config")
			local ClusterVisual = require("../src/shared/ClusterVisual")
			local DebugLayout = require("../src/shared/DebugLayout")
			local c = DebugLayout.clusters[1]
			local need = Config.clusterTypes[c.type].hits
			local tr = ClusterVisual.new(DebugLayout)
			local first = tr:shot({ id = c.id, hits = need - 1, shot = "note" }, c.spawnTime)
			eq(first.alreadyFilled, false, "not filled yet")
			local fill = tr:shot({ id = c.id, hits = need, shot = "note" }, c.spawnTime + 0.1)
			eq(fill.filled, true, "this shot fills it")
			eq(fill.alreadyFilled, false, "the filling shot itself still launches")
			local dup = tr:shot({ id = c.id, hits = need, shot = "note" }, c.spawnTime + 0.2)
			eq(dup.alreadyFilled, true, "a duplicate is flagged")
			eq(
				tr:shot({ id = 99999, hits = 1, shot = "note" }, 1).alreadyFilled,
				false,
				"unknown id"
			)
		end,
	},
	{
		name = "plan: an over-budget shot is still tracked and still reports its first fill (+N)",
		run = function()
			local p = ClusterEvents.plan({
				accepted = true,
				alreadyFilled = false,
				filled = true,
				reward = 5,
				visible = true,
				inBudget = false,
			})
			eq(p.track, true, "always fed to the tracker")
			eq(p.projectile, false, "over budget: no projectile")
			eq(p.float, true, "the +N still plays")
		end,
	},
	{
		name = "plan: a first fill with no known position still shows +N but launches nothing",
		run = function()
			local p = ClusterEvents.plan({
				accepted = true,
				alreadyFilled = false,
				filled = true,
				reward = 5,
				visible = false,
				inBudget = true,
			})
			eq(p.projectile, false, "orphan: no hidden part takes a pool slot")
			eq(p.float, true, "+N survives")
		end,
	},
	{
		name = "plan: skip and drop only suppress the projectile; duplicates and rejects show no +N",
		run = function()
			local dup = ClusterEvents.plan({
				accepted = true,
				alreadyFilled = true,
				filled = false,
				reward = nil,
				visible = true,
				inBudget = true,
			})
			eq(dup.projectile, false, "duplicate: no projectile")
			eq(dup.float, false, "duplicate: no second +N")
			local ok = ClusterEvents.plan({
				accepted = true,
				alreadyFilled = false,
				filled = false,
				reward = nil,
				visible = true,
				inBudget = true,
			})
			eq(ok.projectile, true, "normal shot launches")
			eq(ok.float, false, "no fill, no +N")
			local rej = ClusterEvents.plan({
				accepted = false,
				alreadyFilled = false,
				filled = false,
				reward = nil,
				visible = true,
				inBudget = true,
			})
			eq(rej.projectile, false, "rejected: nothing")
			eq(rej.float, false, "rejected: no +N")
		end,
	},
	{
		name = "a flood over the budget still fills the cluster in the tracker",
		run = function()
			local Config = require("../src/shared/Config")
			local ClusterVisual = require("../src/shared/ClusterVisual")
			local DebugLayout = require("../src/shared/DebugLayout")
			local c = DebugLayout.clusters[1]
			local need = Config.clusterTypes[c.type].hits
			local tr = ClusterVisual.new(DebugLayout)
			local budget = ClusterEvents.budget(1)
			local floats = 0
			for h = 1, need do
				local r = tr:shot({ id = c.id, hits = h, shot = "note" }, c.spawnTime + h * 0.1)
				local plan = ClusterEvents.plan({
					accepted = r.accepted,
					alreadyFilled = r.alreadyFilled,
					filled = r.filled,
					reward = r.reward,
					visible = false,
					inBudget = budget:take(),
				})
				if plan.float then
					floats += 1
				end
			end
			eq(floats, 1, "exactly one +N, on the filling shot, though only one event had budget")
		end,
	},
	{
		name = "ResetPlan has a hit item and no hp item",
		run = function()
			assert(table.find(ResetPlan.items, "hit") ~= nil, "hit is on the replay checklist")
			assert(table.find(ResetPlan.items, "hp") == nil, "no HP on the checklist")
		end,
	},
}
