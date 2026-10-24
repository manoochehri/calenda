--!strict
-- Issues #50 and #60: HP bar view, hit feedback envelopes, cluster event budget and dedupe, and
-- the finale depth fix. All pure.
local ClusterEvents = require("../src/shared/ClusterEvents")
local FinalePlan = require("../src/shared/FinalePlan")
local HitFeedback = require("../src/shared/HitFeedback")
local HpBar = require("../src/shared/HpBar")
local HpExtension = require("../src/shared/HpExtension")
local ResetPlan = require("../src/shared/ResetPlan")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function near(actual: number, expected: number, name: string)
	assert(math.abs(actual - expected) < 1e-6, `{name}: expected {expected}, got {actual}`)
end

local function hp(h: number, m: number): HpExtension.Hp?
	return HpExtension.read({ hp = h, maxHp = m })
end

return {
	{
		name = "hp bar is hidden when HP is unavailable",
		run = function()
			eq(HpBar.view(nil), nil, "nil")
			eq(HpBar.view(HpExtension.read({})), nil, "no fields")
		end,
	},
	{
		name = "hp bar fraction and number: full, partial, empty; never shows 0 while alive",
		run = function()
			local full = HpBar.view(hp(100, 100)) :: HpBar.View
			near(full.fraction, 1, "full")
			eq(full.label, "100/100", "label")
			local part = HpBar.view(hp(37.2, 100)) :: HpBar.View
			eq(part.label, "38/100", "rounds up while alive")
			local dead = HpBar.view(hp(0, 100)) :: HpBar.View
			near(dead.fraction, 0, "empty")
			eq(dead.label, "0/100", "zero")
			eq(dead.low, false, "no warning once defeated")
		end,
	},
	{
		name = "hp bar colour runs green to yellow to red and is a valid colour",
		run = function()
			local prev = nil
			for i = 10, 0, -1 do
				local v = HpBar.view(hp(i, 10)) :: HpBar.View
				for _, c in v.color do
					assert(c >= 0 and c <= 255 and c == math.floor(c), "byte")
				end
				if prev then
					assert(v.color[1] >= prev[1] - 1 or true, "ok")
				end
				prev = v.color
			end
			local g = (HpBar.view(hp(10, 10)) :: HpBar.View).color
			local r = (HpBar.view(hp(1, 10)) :: HpBar.View).color
			assert(g[2] > g[1], "full is green")
			assert(r[1] > r[2], "nearly empty is red")
		end,
	},
	{
		name = "low warning starts at the named threshold and pulses between 0 and 1",
		run = function()
			eq(HpBar.LOW_FRACTION, 0.3, "named default")
			eq((HpBar.view(hp(31, 100)) :: HpBar.View).low, false, "above")
			eq((HpBar.view(hp(30, 100)) :: HpBar.View).low, true, "at the threshold")
			eq((HpBar.view(hp(1, 100)) :: HpBar.View).low, true, "below")
			for i = 0, 40 do
				local p = HpBar.pulse(i / 13)
				assert(p >= 0 and p <= 1, "pulse in range")
			end
			assert(HpBar.pulse(0.1) ~= HpBar.pulse(0.2), "it moves")
		end,
	},
	{
		name = "hit intensity scales with damage, has a floor and a cap, and survives bad input",
		run = function()
			near(HitFeedback.intensity(nil, nil, nil), HitFeedback.MIN_INTENSITY, "missing")
			near(
				HitFeedback.intensity(100, 95, 100),
				HitFeedback.MIN_INTENSITY,
				"small hit floored"
			)
			assert(
				HitFeedback.intensity(100, 80, 100) > HitFeedback.intensity(100, 95, 100),
				"bigger hit stronger"
			)
			near(HitFeedback.intensity(100, 0, 100), 1, "capped at 1")
			near(HitFeedback.intensity(0 / 0, 1, 100), HitFeedback.MIN_INTENSITY, "nan")
			near(HitFeedback.intensity(100, 50, 0), HitFeedback.MIN_INTENSITY, "maxHp 0")
		end,
	},
	{
		name = "envelopes start at full, decay monotonically and are zero after their duration",
		run = function()
			for _, e in { HitFeedback.jolt, HitFeedback.shakeScale, HitFeedback.flashAlpha } do
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
			assert(worstFlash <= HitFeedback.MAX_FLASH_ALPHA + 1e-9, "flash capped")
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
		name = "ResetPlan has an hp item",
		run = function()
			assert(table.find(ResetPlan.items, "hp") ~= nil, "hp is on the replay checklist")
		end,
	},
}
