--!strict
-- Where new followers come from (issue #68). Pure. Turns a server Event into a world-space SOURCE
-- hint for the FollowerFlow: the converted spectator group for a filled cluster, the gate panel for
-- a gate, the obstacle's side for a loss. Anything else (or a malformed payload) gives no hint and
-- the flow falls back to the lead's side. World coordinates (left negative); the client mirrors
-- with ViewMap.x when it draws. Display only: nothing here changes any total.
local Config = require("./Config")
local Level = require("./Level")
local ViewMap = require("./ViewMap")

export type Hint = { kind: string, x: number, z: number, side: string? }

local FollowerSource = {}

local function sideOf(v: any): string?
	if v == "left" or v == "right" then
		return v
	end
	return nil
end

-- `t` is the run time of the latest State (where a filled cluster stood when it converted).
function FollowerSource.fromEvent(layout: Level.Layout, payload: any, t: number): Hint?
	if type(payload) ~= "table" or type(payload.id) ~= "number" then
		return nil
	end
	local id = payload.id
	if payload.kind == "gate" then
		local side = sideOf(payload.side)
		if side == nil then
			return nil
		end
		for _, g in layout.gates do
			if g.id == id then
				return {
					kind = "gate",
					x = ViewMap.gateWorldX(side, layout.halfWidth),
					z = g.z,
					side = side,
				}
			end
		end
	elseif payload.kind == "cluster" then
		local hits = payload.hits
		if type(hits) ~= "number" or type(t) ~= "number" or t ~= t or t < 0 then
			return nil
		end
		for _, c in layout.clusters do
			if c.id == id then
				if hits < Config.clusterTypes[c.type].hits then
					return nil -- a shot that did not convert the group
				end
				local at = Level.clusterPosition(layout, id, t)
				return { kind = "cluster", x = at.x, z = at.z, side = sideOf(Level.sideOf(at.x)) }
			end
		end
	elseif payload.kind == "obstacle" then
		for _, o in layout.obstacles do
			if o.id == id then
				local x = if o.side == "left" then -layout.halfWidth else layout.halfWidth
				return { kind = "obstacle", x = x, z = o.z, side = o.side }
			end
		end
	end
	return nil
end

return FollowerSource
