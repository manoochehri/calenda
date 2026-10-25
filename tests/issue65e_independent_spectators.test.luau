--!strict
-- Owner direction on issue #65: figures must be readable people and move independently. Require
-- the new module lazily so the baseline can run against unchanged source and fail by name.
local CameraRig = require("../src/shared/CameraRig")
local Config = require("../src/shared/Config")
local Emergence = require("../src/shared/Emergence")
local Scatter = require("../src/shared/SpectatorScatter")
local QualityConfig = require("../src/shared/QualityConfig")

local motionOk, Motion = pcall(function()
	return require("../src/shared/SpectatorMotion")
end)

local function params()
	return Config.spectators.scatter
end

local function plans(seed: number, clusterId: number, count: number)
	local p = params()
	local offsets = Scatter.place(count, seed + clusterId * 1009, p)
	local out = {}
	for i = 1, count do
		out[i] = Motion.plan(
			seed,
			clusterId,
			i,
			0,
			1500,
			0,
			Config.speed,
			Config.spectators.approachSpeed,
			offsets[i],
			p
		)
	end
	return out
end

return {
	{
		name = "human silhouette: a distinct body and head project large enough to read from the gameplay camera",
		run = function()
			local p = params()
			assert(motionOk, "SpectatorMotion exists")
			assert(p.bodyHeight >= 1.8, `body height {p.bodyHeight} is too small to read`)
			assert(
				p.headDiameter >= 1.0,
				`head diameter {p.headDiameter} is too small to distinguish`
			)
			assert(
				p.headDiameter >= p.bodyHeight * 0.5,
				"head remains a visible part of the human silhouette"
			)
			assert(
				p.minScreenFraction >= 0.02,
				"each person fills at least 2% of screen height at the visible edge"
			)
			local figureHeight = p.bodyHeight + p.headDiameter
			for _, pullback in { 1, 1.4 } do
				local depth = Emergence.visibleDepthAhead(pullback)
				local pose = CameraRig.pose(0, 0, pullback)
				local fraction =
					CameraRig.screenFraction(pose, figureHeight / 2, depth - 2, figureHeight)
				local scale = Scatter.legibleScale(fraction, p)
				assert(
					scale <= p.maxScale,
					`pullback {pullback}: figure scale {scale} exceeds cap {p.maxScale}`
				)
				assert(
					fraction * scale >= p.minScreenFraction,
					`pullback {pullback}: person is only {fraction * scale} of screen height`
				)
			end
		end,
	},
	{
		name = "each person has a deterministic but independent seeded path, offset, turn, and approach",
		run = function()
			assert(motionOk, "SpectatorMotion exists")
			local a = plans(431, 9, 24)
			local again = plans(431, 9, 24)
			local other = plans(432, 9, 24)
			for i = 1, #a do
				assert(
					a[i].x == again[i].x and a[i].z == again[i].z,
					`person {i}: seed is reproducible`
				)
				assert(
					a[i].startDelay == again[i].startDelay
						and a[i].speed == again[i].speed
						and a[i].arrivalAge == again[i].arrivalAge,
					`person {i}: path schedule is reproducible`
				)
			end
			assert(
				a[1].x ~= other[1].x or a[1].z ~= other[1].z,
				"different layout seeds give different people"
			)
			local minArrival, maxArrival = math.huge, -math.huge
			local minStep, maxStep = math.huge, -math.huge
			local minSideShift, maxSideShift = math.huge, -math.huge
			for i = 1, #a do
				minArrival = math.min(minArrival, a[i].arrivalAge)
				maxArrival = math.max(maxArrival, a[i].arrivalAge)
				local before = Motion.position(a[i], 3, Config.speed * 3)
				local after = Motion.position(a[i], 4, Config.speed * 4)
				local forward = before.z - after.z
				minStep, maxStep = math.min(minStep, forward), math.max(maxStep, forward)
				local sideShift = after.x - a[i].x
				minSideShift, maxSideShift =
					math.min(minSideShift, sideShift), math.max(maxSideShift, sideShift)
				assert(
					before.x ~= a[i].x or before.z ~= a[i].z,
					`person {i}: advances from their own origin`
				)
			end
			assert(
				maxArrival - minArrival >= 0.5,
				`arrival timing range is only {maxArrival - minArrival}s`
			)
			assert(
				maxStep - minStep >= 0.5,
				`one-second approach distances differ by only {maxStep - minStep} studs`
			)
			assert(
				maxSideShift - minSideShift >= 0.25,
				`lateral trajectories differ by only {maxSideShift - minSideShift} studs`
			)
		end,
	},
	{
		name = "per-person animation budget stays within the existing quality caps",
		run = function()
			for _, quality in QualityConfig.NAMES do
				local level = QualityConfig.get(quality)
				assert(level.maxFigures <= 300, `{quality}: figure cap grew to {level.maxFigures}`)
				assert(
					level.maxFiguresPerMob <= 90,
					`{quality}: per-mob figure cap grew to {level.maxFiguresPerMob}`
				)
			end
		end,
	},
}
