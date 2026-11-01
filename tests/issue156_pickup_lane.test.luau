--!strict
-- Issue #156 (ADR 0014 / Amendment 15): +1 pickups live only in their layout's pickup lane, authored
-- in strips of six 3.4 travel-seconds apart starting at travel-seconds 8, 40 and 68. Lane roles are
-- authored per layout as laneRoles = { pickup, horde, recruit }. Gate times are NOT touched here.
local Config = require("../src/shared/Config")
local LayoutValidator = require("../src/shared/LayoutValidator")

local function eq(actual: any, expected: any, label: string)
	assert(actual == expected, `{label}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function layouts(): { any }
	local Layouts = require("../src/shared/Layouts")
	local DebugLayout = require("../src/shared/DebugLayout")
	local out: { any } = { DebugLayout }
	for _, l in Layouts.all do
		table.insert(out, l)
	end
	return out
end

local function clone(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, c in v do
		out[k] = clone(c)
	end
	return out
end

return {
	{
		name = "every authored layout carries laneRoles: pickup opposite the horde side, recruit center",
		run = function()
			for _, l in layouts() do
				local roles = l.laneRoles
				assert(roles ~= nil, `{l.name} has laneRoles`)
				eq(roles.recruit, "center", `{l.name} recruit lane`)
				eq(roles.horde ~= roles.pickup, true, `{l.name} horde and pickup differ`)
				for _, c in l.clusters do
					eq(c.lane, roles.horde, `{l.name} cluster {c.id} is in the horde lane`)
				end
			end
		end,
	},
	{
		name = "strips: three of six pickups, 3.4 travel-seconds apart, starting at 8, 40, 68 s, pickup lane only",
		run = function()
			for _, l in layouts() do
				local ps = l.pickups
				assert(ps ~= nil, `{l.name} has pickups`)
				eq(#ps, 18, `{l.name} pickup count`)
				for strip, start in { 8, 40, 68 } do
					for i = 0, 5 do
						local p = ps[(strip - 1) * 6 + i + 1]
						local want = (start + i * 3.4) * Config.speed
						assert(
							math.abs(p.z - want) < 1e-9,
							`{l.name} strip {strip} pickup {i} z {p.z} ~= {want}`
						)
						eq(p.lane, l.laneRoles.pickup, `{l.name} pickup {p.id} lane`)
					end
				end
			end
		end,
	},
	{
		name = "no obstacle sits in the pickup lane within 2 travel-seconds of a pickup",
		run = function()
			for _, l in layouts() do
				for _, p in l.pickups do
					for _, o in l.obstacles do
						if o.side == p.lane then
							assert(
								math.abs(o.z - p.z) > 2 * Config.speed,
								`{l.name}: obstacle {o.id} collides with pickup {p.id}`
							)
						end
					end
				end
			end
		end,
	},
	{
		name = "LayoutValidator accepts the authored layouts",
		run = function()
			for _, l in layouts() do
				local ok, why = LayoutValidator.validate(l)
				assert(ok, `{l.name}: {tostring(why)}`)
			end
		end,
	},
	{
		name = "LayoutValidator rejects a pickup outside the pickup lane, bad laneRoles, and pickups without laneRoles",
		run = function()
			local base = layouts()[1]
			local bad1 = clone(base)
			bad1.pickups[1].lane = bad1.laneRoles.horde
			eq((LayoutValidator.validate(bad1)), false, "pickup in the horde lane")
			local bad2 = clone(base)
			bad2.laneRoles = { pickup = "left", horde = "left", recruit = "center" }
			eq((LayoutValidator.validate(bad2)), false, "roles are not a permutation")
			local bad3 = clone(base)
			bad3.laneRoles = nil
			eq((LayoutValidator.validate(bad3)), false, "pickups need laneRoles")
			local bad4 = clone(base)
			bad4.clusters[1].lane = bad4.laneRoles.pickup
			bad4.clusters[1].spawn.x = if bad4.clusters[1].lane == "left" then -10 else 10
			eq((LayoutValidator.validate(bad4)), false, "cluster outside the horde lane")
		end,
	},
	{
		name = "encounter spans of a strip touch but never overlap, so at most one encounter is active",
		run = function()
			local Encounters = require("../src/shared/Encounters")
			for _, l in layouts() do
				local ok, why = Encounters.validateSpans(l)
				assert(ok, `{l.name}: {tostring(why)}`)
			end
			-- two pickups 10.8 studs apart: the second span starts at the first one's plane
			local lay = {
				pickups = {
					{ id = 1, z = 100, lane = "left" },
					{ id = 2, z = 110.8, lane = "left" },
				},
			}
			local e = Encounters.current(lay, 95, {})
			assert(e ~= nil and e.id == "p1", "first pickup is the encounter")
			local e2 = Encounters.current(lay, 105, { [1] = "collected" })
			assert(
				e2 ~= nil and e2.id == "p2" and e2.active,
				"second becomes active after the first is resolved"
			)
			local e3 = Encounters.current(lay, 103, { [1] = "collected" })
			assert(e3 ~= nil and e3.id == "p2", "next pickup after resolving the first")
		end,
	},
	{
		name = "played level: lead steering through the pickup lane collects each strip once, a horde-lane lead collects none",
		run = function()
			local BotHarness = require("./helpers/BotHarness")
			local DebugLayout = require("../src/shared/DebugLayout")
			local function collected(x: number): number
				local policy = {
					name = `x{x}`,
					period = 0.5,
					decide = function()
						return x
					end,
				}
				local r = BotHarness.play(DebugLayout, policy, { maxSeconds = 90 })
				local n = 0
				for _, e in r.events do
					if e.kind == "pickup" then
						n += 1
					end
				end
				return n
			end
			local px = if DebugLayout.laneRoles.pickup == "left" then -10 else 10
			eq(collected(px), 18, "pickup-lane lead collects all 18 once")
			eq(collected(0), 0, "center lead collects none")
		end,
	},
}
