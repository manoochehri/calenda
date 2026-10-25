--!strict
-- Level data types and the pure geometry/time helpers on them (issue #7, spec s9 + Amendment 1).
-- No Roblox APIs. Coordinates: z is distance along the street (the lead starts at z = 0 and moves
-- toward +z at Config.speed), x is lateral (negative = left, positive = right). The lead's forward
-- position at run time t is leadZ(t); a cluster has reached the parade when its z <= leadZ(t).
local Config = require("./Config")

export type Point = { x: number, z: number }
export type Op = { kind: "add" | "multiply", value: number }
-- A gate pair: both gates sit at the same z; the lead picks `left` or `right` (spec s6).
export type Gate = { id: number, z: number, left: Op, right: Op }
-- A closed streetwork lane on one side; one hit removes Config.obstacleLoss once (spec s9).
export type Obstacle = { id: number, z: number, side: "left" | "right" }
-- A spectator cluster. It waits at `spawn` until `spawnTime`, then walks along `path` at
-- Config.spectators.approachSpeed, then continues straight toward the parade (-z).
export type Cluster = {
	id: number,
	wave: number,
	type: string, -- key of Config.clusterTypes
	spawnTime: number,
	spawn: Point,
	path: { Point },
}
-- Level hazard set (issue #96): which hazard kinds this level uses and when they can land.
export type HazardSet = {
	kinds: { string },
	firstAt: number,
	lastAt: number,
	minGap: number,
	maxGap: number,
}
export type Layout = {
	name: string,
	seed: number, -- recorded seed; the fixed debug layout uses no randomness
	startPlazaEnd: number?, -- route begins in a distinct plaza before the continuous street
	streetLength: number,
	plazaStart: number, -- z where the plaza begins; reaching it ends the run
	halfWidth: number, -- walkable half width including sidewalks
	maxTotal: number, -- authored bound on the best-route final crowd total
	intendedRecruitTotal: number, -- followers the authored waves are meant to give at the base fire rate
	gates: { Gate },
	clusters: { Cluster },
	obstacles: { Obstacle },
	hazardSet: HazardSet?, -- nil: the level has no hazards (issue #96)
}
export type Side = "left" | "right" | "center"

-- The subset of Config these helpers read; tests may pass a modified copy.
type TimingConfig = {
	speed: number,
	spectators: { approachSpeed: number, centerTolerance: number },
}

local Level = {}

function Level.leadZ(t: number, config: TimingConfig?): number
	local cfg = config or Config
	return cfg.speed * t
end

function Level.timeAtZ(z: number, config: TimingConfig?): number
	local cfg = config or Config
	return z / cfg.speed
end

function Level.sideOf(x: number, config: TimingConfig?): Side
	local tol = (config or Config).spectators.centerTolerance
	if x < -tol then
		return "left"
	elseif x > tol then
		return "right"
	end
	return "center"
end

function Level.findCluster(layout: Layout, id: number): Cluster
	for _, c in layout.clusters do
		if c.id == id then
			return c
		end
	end
	error(`unknown cluster id {id}`, 3)
end

-- Position of cluster `id` at run time `t` (seconds). Pure function of (layout, id, t, approachSpeed).
function Level.clusterPosition(layout: Layout, id: number, t: number, config: TimingConfig?): Point
	if type(t) ~= "number" or t < 0 or t ~= t then
		error(`t must be a non-negative number, got {t}`, 2)
	end
	local cluster = Level.findCluster(layout, id)
	local speed = (config or Config).spectators.approachSpeed
	local remaining = math.max(0, t - cluster.spawnTime) * speed
	local from = cluster.spawn
	for _, to in cluster.path do
		local dx, dz = to.x - from.x, to.z - from.z
		local len = math.sqrt(dx * dx + dz * dz)
		if remaining <= len then
			local f = if len == 0 then 0 else remaining / len
			return { x = from.x + dx * f, z = from.z + dz * f }
		end
		remaining -= len
		from = to
	end
	return { x = from.x, z = from.z - remaining }
end

return Level
