--!nocheck
-- Issue #147 (choppy frame rate): headless counts of what CrowdView asks the engine to do per
-- frame. Counting stubs (tests/helpers/EngineCount), so these are request counts, not frame times:
-- engine and render cost stay UNVERIFIED until a device or Studio run.
local EngineCount = require("./helpers/EngineCount")

local MODS = {}
for _, n in
	{
		"LayerHeights",
		"DebugLayout",
		"DebugSwitches",
		"Effects",
		"Dance",
		"DanceConfig",
		"Config",
		"CrowdFeel",
		"CrowdFeelConfig",
		"FollowerFlow",
		"FollowerLook",
		"FollowerSource",
		"LeadPose",
		"Pool",
		"ViewMap",
	}
do
	MODS[n] = require(`../src/shared/{n}`)
end

local function run(frames: number, total: number)
	local c = EngineCount.new()
	local CrowdView = EngineCount.load("src/client/CrowdView.luau", MODS, c)
	local view = CrowdView.new()
	local dt = 1 / 60
	local peak = 0
	local sample =
		{ writesCFrame = 0, writesSize = 0, parents = 0, created = 0, bulk = 0, frames = 0 }
	for f = 1, frames do
		if f == 301 then
			c.resetFrame()
		end
		view:update(0, f * 0.5, total, dt, 0, 0, 0, true, 1)
		if f > 300 then
			sample.frames += 1
			sample.writesCFrame += c.writes.CFrame or 0
			sample.writesSize += c.writes.Size or 0
			sample.parents += c.parentChanges
			sample.created += c.created
			sample.bulk += c.bulkParts
			c.resetFrame()
		end
		peak = math.max(peak, c.liveParts)
	end
	return c, peak, sample
end

return {
	{
		name = "issue 147: CrowdView steady state creates no instances (n=300 frames, total 174)",
		run = function()
			local _, _, s = run(600, 174)
			assert(s.created == 0, `{s.created} Instance.new in {s.frames} steady frames`)
		end,
	},
	{
		name = "issue 147: a follower keeps only its visible topper as a live Part (<= 4 per avatar)",
		run = function()
			local _, peak = run(600, 174)
			print(`CrowdView live Parts at peak: {peak} (total 174, n=600 frames)`)
			-- 24 members + bounded runners/leavers drawn; every avatar is body, head, skirt, one topper.
			local FollowerSlots = require("../src/shared/FollowerSlots")
			assert(peak > 0, "nothing drawn")
			assert(
				peak <= 4 * (FollowerSlots.capacity() + 1) + 1,
				`{peak} live Parts exceeds 4 per drawn avatar`
			)
		end,
	},
	{
		name = "issue 147: follower CFrames are batched through BulkMoveTo, not written per Part",
		run = function()
			local _, _, s = run(600, 174)
			print(
				`CrowdView per steady frame (n={s.frames}): CFrame writes {s.writesCFrame / s.frames},`
					.. ` Size writes {s.writesSize / s.frames}, BulkMoveTo parts {s.bulk / s.frames}`
			)
			assert(s.writesCFrame == 0, `{s.writesCFrame} per-Part CFrame writes`)
			assert(s.bulk > 0, "no BulkMoveTo")
		end,
	},
	{
		-- Source-text checks (ClusterView, GateView and MobView need the whole engine tree to load).
		name = "issue 147: projectiles reparent only on change; gates and dust skip unchanged writes",
		run = function()
			local fs = require("@lune/fs")
			local cluster = fs.readFile("src/client/ClusterView.luau")
			assert(
				string.find(cluster, "if j > p.shown then", 1, true),
				"projectile reparents every frame"
			)
			assert(
				not string.find(cluster, "p.body.Parent = nil\n\t\t\tif gone", 1, true),
				"per-frame detach"
			)
			assert(
				string.find(cluster, "if p.glow ~= glowColor then", 1, true),
				"trail colour rebuilt every frame"
			)
			local gate = fs.readFile("src/client/GateView.luau")
			assert(
				not string.find(gate, "lastKey", 1, true),
				"GateView builds a key string per gate per frame"
			)
			local mob = fs.readFile("src/client/MobView.luau")
			assert(
				string.find(mob, "if d.sizeKey ~= depth then", 1, true),
				"dust Size written every frame"
			)
		end,
	},
}
