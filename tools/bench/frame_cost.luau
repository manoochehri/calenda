--!nocheck
local fs = require("@lune/fs")
local process = require("@lune/process")

-- Roblox stubs: enough for MobView.update to run headless. Engine costs are NOT modelled.
local V3 = {}
V3.__index = V3
V3.__mul = function(a, b)
	if type(b) == "number" then
		return setmetatable({ X = a.X * b, Y = a.Y * b, Z = a.Z * b }, V3)
	end
	return setmetatable({ X = a.X * b.X, Y = a.Y * b.Y, Z = a.Z * b.Z }, V3)
end
Vector3 = {
	new = function(x, y, z)
		return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3)
	end,
}
Color3 = {
	fromRGB = function(r, g, b)
		return { r = r, g = g, b = b }
	end,
	new = function(r, g, b)
		return { r = r, g = g, b = b }
	end,
}
local CF = {}
CF.__index = CF
CF.__mul = function(a, b)
	return setmetatable({ a = a, b = b }, CF)
end
CFrame = {
	new = function(x, y, z)
		return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, CF)
	end,
	Angles = function(a, b, c)
		return setmetatable({ ax = a, ay = b, az = c }, CF)
	end,
}
Enum = setmetatable({}, {
	__index = function()
		return setmetatable({}, {
			__index = function(_, k)
				return k
			end,
		})
	end,
})
Instance = {
	new = function()
		return setmetatable({}, {
			__index = function()
				return function() end
			end,
		})
	end,
}
local anyNew = {
	new = function(...)
		return { ... }
	end,
}
NumberRange = anyNew
NumberSequence = anyNew
NumberSequenceKeypoint = anyNew
ColorSequence = anyNew
Vector2 = anyNew
local moved = { parts = 0, calls = 0 }
Workspace = {
	BulkMoveTo = function(_, parts, _cfs, _mode)
		moved.calls += 1
		moved.parts += #parts
	end,
}
game = {
	GetService = function(_, name)
		if name == "Workspace" then
			return Workspace
		end
		return {
			WaitForChild = function(self)
				return self
			end,
		}
	end,
}
ReplicatedStorage = {}

-- Usage (from the repo root): lune run tools/bench/frame_cost.luau <mode|views> [frames] [runs]
-- A copy of the real MobView with its Roblox-tree requires mapped to the real pure modules. The
-- copy is written next to this script and removed at the end; it is never committed.
local src = fs.readFile("src/client/MobView.luau")
src =
	string.gsub(src, 'require%(Shared:WaitForChild%("(%w+)"%)%)', 'require("../../src/shared/%1")')
local COPY = "tools/bench/_mobview_copy.luau"
fs.writeFile(COPY, src)
local MobView = require("./_mobview_copy")
local Config = require("../../src/shared/Config")
local ClusterVisual = require("../../src/shared/ClusterVisual")
local Layouts = require("../../src/shared/Layouts")
local Level = require("../../src/shared/Level")

local MODE = process.args[1] or "medium"
local FRAMES = tonumber(process.args[2]) or 600
local RUNS = tonumber(process.args[3]) or 5

local function mkMobs(n, phaseMix)
	local mobs = {}
	for i = 1, n do
		local phase = "walking"
		if phaseMix then
			phase = ({ "walking", "cheering", "slamming", "dispersing" })[(i % 4) + 1]
		end
		mobs[i] = {
			id = i,
			x = ((i % 5) - 2) * 6,
			z = 30 + i * 4,
			reward = Config.clusterTypes.large.reward,
			ahead = 30 + i * 4,
			fade = 1,
			phase = phase,
			phaseT = 0.3,
			age = 0.5,
			pulse = 0,
			dip = 0,
			hop = 0,
			glow = 0,
			spawnAge = 2,
			layoutSeed = 7,
			spawnX = 10,
			spawnZ = 130,
			spawnLeadZ = 0,
		}
	end
	return mobs
end

local function stats(times: { number }): string
	table.sort(times)
	local function pct(p)
		return times[math.max(1, math.floor(p * #times + 0.5))]
	end
	local sum = 0
	for _, t in times do
		sum += t
	end
	return string.format(
		"n=%d median=%.1f p90=%.1f p99=%.1f max=%.1f mean=%.1f (us)",
		#times,
		pct(0.5),
		pct(0.9),
		pct(0.99),
		times[#times],
		sum / #times
	)
end

if MODE == "views" then
	-- ClusterVisual.views (pure Lua) on every authored layout, walking clusters only (no hits).
	for _, layout in Layouts.all do
		local tr = ClusterVisual.new(layout)
		local times = {}
		local shown = 0
		local frames = 0
		local span = (layout.streetLength / Config.speed) + 40
		for run = 0, RUNS do
			for f = 0, FRAMES - 1 do
				local t = span * f / FRAMES
				local leadZ = Level.leadZ(t)
				local t0 = os.clock()
				local out = tr:views(t, 0, leadZ)
				local t1 = os.clock()
				if run > 0 then
					times[#times + 1] = (t1 - t0) * 1e6
					shown += #out
					frames += 1
				end
			end
		end
		print(
			`views layout={layout.name} clusters={#layout.clusters} avgViews={string.format(
				"%.1f",
				shown / frames
			)} | {stats(times)}`
		)
	end
else
	local cfgs = {
		medium = { 16, "medium", false },
		high = { 20, "high", false },
		low = { 12, "low", false },
		mixed = { 16, "medium", true },
	}
	local cfg = assert(cfgs[MODE], "mode must be views, low, medium, high or mixed")
	local view = MobView.new()
	view:setQuality(cfg[2])
	local mobs = mkMobs(cfg[1], cfg[3])

	local times = {}
	local figuresSeen, partsSeen = 0, 0
	-- run 0 is a warm-up (figure pool creation happens there) and is not recorded
	for run = 0, RUNS do
		view:clear()
		for f = 1, FRAMES do
			local leadZ = (f + run * FRAMES) * 0.05
			for _, m in mobs do
				m.ahead = m.z - leadZ
			end
			moved.calls, moved.parts = 0, 0
			local t0 = os.clock()
			view:update(mobs, leadZ, leadZ * 0.1, 1 / 60, 1)
			local t1 = os.clock()
			if run > 0 then
				times[#times + 1] = (t1 - t0) * 1e6
			end
			if f == FRAMES and run == RUNS then
				figuresSeen, partsSeen = view:counts().figures, moved.parts
			end
		end
	end
	print(
		`MobView.update mode={MODE} figures={figuresSeen} bulkMoveParts/frame={partsSeen} | {stats(
			times
		)}`
	)
end

fs.removeFile(COPY)
