--!strict
-- Issue #178: the crowd's feel layer. Per-follower breathing variation (no lockstep), a short
-- join bounce and squash, a cheer on gain and a short flinch on loss. All of it is display only:
-- the server still owns crowdTotal and the 10% loss rule. Every tunable is in CrowdFeelConfig.
local CrowdFeel = require("../src/shared/CrowdFeel")
local CrowdFeelConfig = require("../src/shared/CrowdFeelConfig")
local FollowerLook = require("../src/shared/FollowerLook")
local Config = require("../src/shared/Config")

local C = CrowdFeelConfig
local EPS = 1e-9

local function near(actual: number, expected: number, name: string)
	assert(math.abs(actual - expected) < EPS, `{name}: expected {expected}, got {actual}`)
end

local function assertFinite(v: number, name: string)
	assert(v == v and v ~= math.huge and v ~= -math.huge, `{name} must be finite, got {v}`)
end

-- Counts how many times a sampled curve changes direction (ignoring flat runs).
local function turns(samples: { number }): number
	local count, last = 0, 0
	for i = 2, #samples do
		local d = samples[i] - samples[i - 1]
		if math.abs(d) > 1e-12 then
			local sign = if d > 0 then 1 else -1
			if last ~= 0 and sign ~= last then
				count += 1
			end
			last = sign
		end
	end
	return count
end

return {
	{
		name = "breath phase is deterministic, bounded and varies across followers",
		run = function()
			local seen: { [string]: boolean } = {}
			local distinct = 0
			for id = 1, 200 do
				local p = CrowdFeel.breathPhase(id)
				assertFinite(p, "breath phase")
				assert(p >= 0 and p <= C.BREATH_SPREAD_BEATS, `phase {p} outside [0, spread]`)
				assert(CrowdFeel.breathPhase(id) == p, "same id must give the same phase")
				local key = string.format("%.4f", p)
				if not seen[key] then
					seen[key] = true
					distinct += 1
				end
			end
			assert(distinct >= 20, `expected varied phases, got {distinct} distinct of 200`)
		end,
	},
	{
		name = "breath stays in its band and two followers do not pulse in lockstep",
		run = function()
			local lo, hi = 1 - FollowerLook.BREATH, 1 + FollowerLook.BREATH
			local differs = false
			for i = 0, 99 do
				local t = i * 0.037
				local a = FollowerLook.breath(t, CrowdFeel.breathPhase(1))
				local b = FollowerLook.breath(t, CrowdFeel.breathPhase(7))
				assert(a >= lo - EPS and a <= hi + EPS, `breath {a} outside [{lo}, {hi}]`)
				assert(b >= lo - EPS and b <= hi + EPS, `breath {b} outside [{lo}, {hi}]`)
				if math.abs(a - b) > 1e-6 then
					differs = true
				end
			end
			assert(differs, "two followers with different phases must not breathe identically")
		end,
	},
	{
		name = "join bounce is capped and returns to rest",
		run = function()
			for i = 0, 100 do
				local age = i * (2 * C.JOIN_SECONDS) / 100
				local hop, squash = CrowdFeel.join(age)
				assertFinite(hop, "join hop")
				assertFinite(squash, "join squash")
				assert(math.abs(hop) <= C.JOIN_HOP + EPS, `join hop {hop} exceeds JOIN_HOP`)
				assert(
					squash >= -EPS and squash <= C.MAX_SQUASH + EPS,
					`squash {squash} out of range`
				)
			end
			local h0, s0 = CrowdFeel.join(0)
			assert(s0 > 0, "a join squashes on the first frame")
			near(h0, 0, "a join starts on the ground")
			local hEnd, sEnd = CrowdFeel.join(C.JOIN_SECONDS)
			near(hEnd, 0, "join hop at rest")
			near(sEnd, 0, "join squash at rest")
			local hLate, sLate = CrowdFeel.join(C.JOIN_SECONDS * 10)
			near(hLate, 0, "late join hop")
			near(sLate, 0, "late join squash")
			local hNeg, sNeg = CrowdFeel.join(-1)
			near(hNeg, 0, "negative age hop")
			near(sNeg, 0, "negative age squash")
			local hNan, sNan = CrowdFeel.join(0 / 0)
			near(hNan, 0, "NaN age hop")
			near(sNan, 0, "NaN age squash")
		end,
	},
	{
		name = "join bounce hops once and does not strobe",
		run = function()
			local samples = {}
			for i = 0, 200 do
				local hop = CrowdFeel.join(i * C.JOIN_SECONDS / 200)
				table.insert(samples, hop)
			end
			assert(turns(samples) <= 2, `join hop changed direction {turns(samples)} times`)
		end,
	},
	{
		name = "cheer on gain and flinch on loss are short, capped and return to rest",
		run = function()
			for i = 0, 100 do
				local hop = CrowdFeel.cheer(i * C.CHEER_SECONDS / 100)
				assert(math.abs(hop) <= C.CHEER_HOP + EPS, `cheer hop {hop} exceeds CHEER_HOP`)
				local fh, fs = CrowdFeel.flinch(i * C.FLINCH_SECONDS / 100)
				assert(math.abs(fh) <= C.FLINCH_DIP + EPS, `flinch dip {fh} exceeds FLINCH_DIP`)
				assert(
					fs >= -EPS and fs <= C.FLINCH_SQUASH + EPS,
					`flinch squash {fs} out of range`
				)
			end
			near(CrowdFeel.cheer(C.CHEER_SECONDS), 0, "cheer at rest")
			near(CrowdFeel.cheer(-1), 0, "cheer before the gain")
			local h, s = CrowdFeel.flinch(C.FLINCH_SECONDS)
			near(h, 0, "flinch at rest")
			near(s, 0, "flinch squash at rest")
			local dip = CrowdFeel.flinch(C.FLINCH_SECONDS * 0.5)
			assert(dip < 0, "a loss pushes followers down visibly")
		end,
	},
	{
		name = "combined offset is clamped and at rest when nothing has happened",
		run = function()
			local hop, sy, sxz = CrowdFeel.combine(math.huge, math.huge, math.huge)
			near(hop, 0, "rest hop")
			near(sy, 1, "rest squash Y")
			near(sxz, 1, "rest squash XZ")
			for i = 0, 40 do
				local t = i * 0.02
				local h, y, xz = CrowdFeel.combine(t, t, t)
				assert(h >= C.MIN_HOP - EPS and h <= C.MAX_HOP + EPS, `hop {h} outside clamp`)
				assert(y >= 1 - C.MAX_SQUASH - EPS and y <= 1 + EPS, `squash Y {y} outside clamp`)
				assert(xz >= 1 - EPS and xz <= 1 / math.sqrt(1 - C.MAX_SQUASH) + EPS, `xz {xz}`)
			end
		end,
	},
	{
		name = "tunables are sane and every peak fits inside its clamp",
		run = function()
			for _, key in
				{ "BREATH_SPREAD_BEATS", "JOIN_SECONDS", "CHEER_SECONDS", "FLINCH_SECONDS" }
			do
				assert(C[key] > 0, `{key} must be positive`)
			end
			assert(C.JOIN_HOP <= C.MAX_HOP, "a join bounce fits inside MAX_HOP")
			assert(C.CHEER_HOP <= C.MAX_HOP, "a cheer fits inside MAX_HOP")
			assert(C.FLINCH_DIP <= -C.MIN_HOP, "a flinch fits inside MIN_HOP")
			assert(C.JOIN_SQUASH <= C.MAX_SQUASH and C.FLINCH_SQUASH <= C.MAX_SQUASH, "squash caps")
			assert(C.BREATH_SPREAD_BEATS <= 1, "breath spread is at most one beat")
			assert(C.JOIN_SECONDS < 1 and C.CHEER_SECONDS < 1.5, "feedback is short")
			assert(Config.music.bpm > 0, "beat clock available")
		end,
	},
}
