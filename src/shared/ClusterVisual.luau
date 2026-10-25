--!strict
-- Visual state of the spectator MOBS (issues #12, #65, spec s4, Amendment 1). Pure: it turns the
-- layout (Level.clusterPosition over run time) plus the replicated per-shot hit counts and attack
-- Events into what to draw this frame. It never credits anything: the +N and the run into the
-- parade are visual only, and a repeated or late fill event plays nothing (the first fill wins).
--
-- Phases: "walking" (meter filling; an unconverted mob CHARGES straight at the parade and stops at
-- its front, SLAM_GAP studs ahead of the lead, until the server's attack Event arrives or
-- SLAM_FALLBACK passes), "slamming" (the hit: SLAM_SECONDS), "dispersing" (it scatters to the
-- sidewalks and dissolves, DISPERSE_SECONDS, then it is gone), "cheering" (filled: the mob
-- recolours to the party palette and streams into the parade for CHEER_SECONDS). There is no
-- veer-away any more (issue #65). `z` is the mob's FRONT; its body trails behind (+z).
local Config = require("./Config")
local FeedbackMath = require("./FeedbackMath")
local Emergence = require("./Emergence")
local Level = require("./Level")
local MobCharge = require("./MobCharge")

export type Runner = { x: number, z: number, y: number }
export type View = {
	id: number,
	phase: "walking" | "slamming" | "dispersing" | "cheering",
	kind: string, -- cluster type key (Config.clusterTypes)
	x: number,
	z: number, -- the mob's front
	ahead: number, -- z minus the lead's z (what the fade and the threat read)
	age: number, -- seconds since the phase began (cheering: since the fill; walking: 0)
	phaseT: number, -- 0..1 progress through slamming / dispersing / cheering
	spawnAge: number, -- seconds since the cluster spawned (telegraph)
	hits: number,
	needed: number,
	remaining: number, -- big numeral above the group
	fill: number, -- 0..1 meter bar
	reward: number, -- "+N" shown small beside the numeral
	runners: { Runner }, -- spectators running into the parade (cheering phase only)
}
export type ShotResult = {
	accepted: boolean,
	filled: boolean,
	alreadyFilled: boolean,
	reward: number?,
	x: number,
	z: number,
}
export type Tracker = {
	shot: (self: Tracker, s: { id: number, hits: number, shot: string }, t: number) -> ShotResult,
	attack: (self: Tracker, id: number, t: number) -> (), -- the server's attack Event: start the slam
	views: (self: Tracker, t: number, leadX: number, leadZ: number) -> { View },
	reset: (self: Tracker) -> (),
}

local ClusterVisual = {}

ClusterVisual.MAX_VISIBLE_CLUSTERS = 24 -- [default] bound on mobs drawn at once
ClusterVisual.RUNNERS = 6 -- [default] spectators per converted mob running into the parade
ClusterVisual.RUN_SECONDS = 0.9 -- [default]
ClusterVisual.CHEER_SECONDS = MobCharge.STREAM_SECONDS -- the converted mob streams in this long

function ClusterVisual.new(layout: Level.Layout, config: any?): Tracker
	local cfg = config or Config
	local byId: { [number]: Level.Cluster } = {}
	local order: { Level.Cluster } = {}
	for _, c in layout.clusters do
		byId[c.id] = c
		table.insert(order, c)
	end
	table.sort(order, function(a, b)
		return a.id < b.id
	end)

	local hits: { [number]: number } = {}
	local filledAt: { [number]: number } = {}
	local attackedAt: { [number]: number } = {} -- id -> run time of the server's attack Event
	local slamAt: { [number]: number } = {} -- id -> latched slam start (Event or fallback)
	local reachedAt: { [number]: number } = {} -- id -> run time the mob was first seen at the parade
	-- Beyond this (visible depth + spawn margin) a mob is not drawn at all.
	local _, deepest = Emergence.depthRange(cfg)
	local cullAhead = deepest + Emergence.SPAWN_MARGIN + 1
	local self = {} :: Tracker

	local function needed(c: Level.Cluster): number
		return cfg.clusterTypes[c.type].hits
	end

	function self.shot(_, s, t): ShotResult
		local c = byId[s.id]
		if c == nil or type(t) ~= "number" or t ~= t or t < 0 then
			return { accepted = false, filled = false, alreadyFilled = false, x = 0, z = 0 }
		end
		local need = needed(c)
		-- Replicated counts only ever raise the meter, so a late or duplicate event is harmless.
		hits[s.id] = math.min(need, math.max(hits[s.id] or 0, s.hits))
		local alreadyFilled = filledAt[s.id] ~= nil
		local firstFill = false
		if hits[s.id] >= need and filledAt[s.id] == nil then
			filledAt[s.id] = t
			firstFill = true
		end
		local at =
			Level.clusterPosition(layout, s.id, if filledAt[s.id] then filledAt[s.id] else t, cfg)
		return {
			accepted = true,
			filled = firstFill,
			alreadyFilled = alreadyFilled,
			reward = if firstFill then cfg.clusterTypes[c.type].reward else nil,
			x = at.x,
			z = at.z,
		}
	end

	function self.attack(_, id: number, t: number)
		if byId[id] == nil or type(t) ~= "number" or t ~= t then
			return
		end
		-- The slam start is LATCHED the first time it is used (an Event or the fallback). A later
		-- Event changes nothing: it never restarts a slam and never brings back a dispersed mob.
		if slamAt[id] ~= nil or attackedAt[id] ~= nil then
			return
		end
		local reach = reachedAt[id]
		if reach ~= nil and t >= reach + MobCharge.SLAM_FALLBACK then
			slamAt[id] = reach + MobCharge.SLAM_FALLBACK -- the fallback was already due
		else
			attackedAt[id] = t
		end
	end

	function self.views(_, t, leadX, leadZ): { View }
		local out: { View } = {}
		local cull = cullAhead
		for _, c in order do
			if t >= c.spawnTime and #out < ClusterVisual.MAX_VISIBLE_CLUSTERS then
				local need = needed(c)
				local h = hits[c.id] or 0
				local view: View = {
					id = c.id,
					phase = "walking",
					kind = c.type,
					x = 0,
					z = 0,
					ahead = 0,
					age = 0,
					phaseT = 0,
					spawnAge = t - c.spawnTime,
					hits = h,
					needed = need,
					remaining = math.max(0, need - h),
					fill = FeedbackMath.meterFraction(h, need),
					reward = cfg.clusterTypes[c.type].reward,
					runners = {},
				}
				local visible = true
				local tf = filledAt[c.id]
				if tf ~= nil then
					local p = Level.clusterPosition(layout, c.id, tf, cfg)
					view.phase, view.x, view.z = "cheering", p.x, p.z
					local since = t - tf
					view.age, view.phaseT =
						since, math.clamp(since / ClusterVisual.CHEER_SECONDS, 0, 1)
					if since > ClusterVisual.CHEER_SECONDS then
						visible = false
					elseif since < ClusterVisual.RUN_SECONDS then
						local f = since / ClusterVisual.RUN_SECONDS
						for i = 1, ClusterVisual.RUNNERS do
							local ox = (i - (ClusterVisual.RUNNERS + 1) / 2) * 1.6
							local rx, rz, ry =
								FeedbackMath.run(p.x + ox, p.z, leadX + ox * 0.5, leadZ, f)
							table.insert(view.runners, { x = rx, z = rz, y = ry })
						end
					end
				else
					local p = Level.clusterPosition(layout, c.id, t, cfg)
					view.x, view.z = p.x, p.z
					if p.z > leadZ then
						-- Charging: the front stops SLAM_GAP studs ahead of the lead and pushes in.
						view.z = math.max(p.z, leadZ + MobCharge.SLAM_GAP)
						if p.z - leadZ > cull then
							visible = false
						end
					else
						local reach = reachedAt[c.id]
						if reach == nil then
							reach = t
							reachedAt[c.id] = reach
						end
						local hitAt = slamAt[c.id] or attackedAt[c.id]
						if hitAt == nil and t >= reach + MobCharge.SLAM_FALLBACK then
							hitAt = reach + MobCharge.SLAM_FALLBACK
						end
						if hitAt ~= nil then
							slamAt[c.id] = hitAt -- latch
						end
						if hitAt == nil then
							view.z = leadZ + MobCharge.SLAM_GAP -- waiting for the Event
						else
							local age = t - hitAt
							view.x = Level.clusterPosition(layout, c.id, math.max(0, hitAt), cfg).x
							view.age = age
							if age < MobCharge.SLAM_SECONDS then
								view.phase = "slamming"
								view.phaseT = age / MobCharge.SLAM_SECONDS
								view.z = leadZ + MobCharge.SLAM_GAP
							elseif age < MobCharge.SLAM_SECONDS + MobCharge.DISPERSE_SECONDS then
								view.phase = "dispersing"
								view.phaseT = (age - MobCharge.SLAM_SECONDS)
									/ MobCharge.DISPERSE_SECONDS
								-- the scatter stays where the hit happened; the parade marches on
								view.z = Level.leadZ(hitAt + MobCharge.SLAM_SECONDS, cfg)
									+ MobCharge.SLAM_GAP
							else
								visible = false
							end
						end
					end
				end
				view.ahead = view.z - leadZ
				if visible then
					table.insert(out, view)
				end
			end
		end
		return out
	end

	function self.reset(_)
		hits = {}
		filledAt = {}
		attackedAt = {}
		slamAt = {}
		reachedAt = {}
	end

	return self
end

return ClusterVisual
