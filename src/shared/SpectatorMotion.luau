--!strict
-- Per-person spectator trajectories (issue #65). Pure and display-only: each figure gets a
-- deterministic spawn delay, front/back and lateral offset, turn, and approach speed from the
-- layout seed, cluster id, and figure index. The server still owns one cluster hit/reward; this
-- module never changes gameplay.
local MobCharge = require("./MobCharge")
local MobLod = require("./MobLod")
local SpectatorScatter = require("./SpectatorScatter")

local SpectatorMotion = {}

export type Path = {
	x: number,
	z: number,
	targetX: number,
	startDelay: number,
	speed: number,
	turnDelay: number,
	turnSeconds: number,
	phase: number,
	sway: number,
	arrivalAge: number,
	arrivalAhead: number,
}

export type Position = { x: number, z: number, started: boolean, arrived: boolean }

local function noise(seed: number, clusterId: number, person: number, salt: number): number
	local value = math.sin(seed * 12.9898 + clusterId * 78.233 + person * 37.719 + salt * 19.913)
		* 43758.5453
	return value - math.floor(value)
end

local function smooth(x: number): number
	local t = math.clamp(x, 0, 1)
	return t * t * (3 - 2 * t)
end

function SpectatorMotion.plan(
	seed: number,
	clusterId: number,
	person: number,
	originX: number,
	originZ: number,
	originLeadZ: number,
	leadSpeed: number,
	approachSpeed: number,
	offset: SpectatorScatter.Offset,
	p: any
): Path
	local startX = MobLod.lateralFit(originX + offset.dx, p.armsWidth)
	local startZ = originZ
		+ offset.dz
		+ (noise(seed, clusterId, person, 1) * 2 - 1) * p.longitudinalJitter
	local startDelay = noise(seed, clusterId, person, 2) * p.startDelayMax
	local speedScale = 1
		- p.approachSpeedSpread
		+ noise(seed, clusterId, person, 3) * 2 * p.approachSpeedSpread
	local speed = approachSpeed * speedScale
	local targetX = MobLod.lateralFit(
		startX + (noise(seed, clusterId, person, 4) * 2 - 1) * p.lateralWander,
		p.armsWidth
	)
	local turnDelay = noise(seed, clusterId, person, 5) * p.turnDelayMax
	local turnSeconds = p.turnSeconds * (0.6 + noise(seed, clusterId, person, 6) * 0.8)
	local arrivalAhead = MobCharge.SLAM_GAP
		+ (noise(seed, clusterId, person, 7) * 2 - 1) * p.arrivalSpread
	local gapAtStart = startZ - (originLeadZ + leadSpeed * startDelay + arrivalAhead)
	local arrivalAge = startDelay + math.max(0, gapAtStart) / (leadSpeed + speed)
	return {
		x = startX,
		z = startZ,
		targetX = targetX,
		startDelay = startDelay,
		speed = speed,
		turnDelay = turnDelay,
		turnSeconds = turnSeconds,
		phase = noise(seed, clusterId, person, 8) * math.pi * 2,
		sway = (noise(seed, clusterId, person, 9) * 2 - 1) * p.lateralWander * 0.08,
		arrivalAge = arrivalAge,
		arrivalAhead = arrivalAhead,
	}
end

function SpectatorMotion.position(path: Path, spawnAge: number, leadZ: number): Position
	local started = spawnAge >= path.startDelay
	local age = math.max(0, spawnAge - path.startDelay)
	local turn = smooth((age - path.turnDelay) / path.turnSeconds)
	local x = path.x + (path.targetX - path.x) * turn + math.sin(age * 2.1 + path.phase) * path.sway
	local z = path.z - path.speed * age
	local arrived = spawnAge >= path.arrivalAge
	if arrived then
		z = leadZ + path.arrivalAhead
	end
	return { x = x, z = z, started = started, arrived = arrived }
end

function SpectatorMotion.latestArrivalAge(
	seed: number,
	clusterId: number,
	count: number,
	originX: number,
	originZ: number,
	originLeadZ: number,
	leadSpeed: number,
	approachSpeed: number,
	p: any
): number
	local offsets = SpectatorScatter.place(count, seed + clusterId * 1009, p)
	local latest = 0
	for i = 1, count do
		local path = SpectatorMotion.plan(
			seed,
			clusterId,
			i,
			originX,
			originZ,
			originLeadZ,
			leadSpeed,
			approachSpeed,
			offsets[i],
			p
		)
		latest = math.max(latest, path.arrivalAge)
	end
	return latest
end

return SpectatorMotion
