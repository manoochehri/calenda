--!strict
-- Production gameplay hooks connecting target selection to RunState and the parade size (ADR 0006).
-- Pure: the server supplies the RunState and replicates the emitted events.
local Config = require("./Config")
local ClusterFeed = require("./ClusterFeed")
local CrowdMath = require("./CrowdMath")
local LaneGeometry = require("./LaneGeometry")
local Level = require("./Level")
local Targeting = require("./Targeting")

local RunHooks = {}

-- `layout` is the first level; each tick follows the level the run is on (ctx.layout, issue #128),
-- and targeting is rebuilt when the level changes so it never reads another level's clusters.
function RunHooks.new(layout: Level.Layout, config: any?): any
	local cfg = config or Config
	local targeting: Targeting.Session? = nil
	local targetingLayout: Level.Layout? = nil
	local hooks: any = {}

	local function session(ctx: any): Targeting.Session
		local current: Level.Layout = ctx.layout or layout
		if targeting == nil or targetingLayout ~= current then
			targetingLayout = current
			targeting = Targeting.new({
				layout = current,
				runState = ctx.state,
				runIdPrefix = "c",
				config = cfg,
			})
		end
		return targeting :: Targeting.Session
	end

	hooks.shots = function(ctx: any)
		local step = session(ctx):advance(
			ctx.t1,
			CrowdMath.sectionCount(ctx.state:total()),
			LaneGeometry.laneOf(ctx.x), -- start-of-tick lane (Amendment 9 same-tick order); nil engages nothing
			ctx.t0,
			if ctx.routeT1 ~= nil
				then {
					delay = ctx.delay,
					routeT1 = ctx.routeT1,
					leadZ0 = ctx.z0,
					leadZ1 = ctx.z1,
				}
				else nil,
			ctx.state:total() -- recruits: speed, rate and shots in flight follow it (issue #234)
		)
		ctx.passedClusters = step.passed
		-- Landed gift shots can block a tomato (issue #96). Misses and notes never do.
		if ctx.giftTimes ~= nil then
			for _, shot in step.shots do
				if not shot.miss and shot.kind == "gift" then
					table.insert(ctx.giftTimes, shot.time)
				end
			end
		end
		-- One display-only event per landed shot; the server sends it to the owning player only.
		for _, shot in step.shots do
			local payload = ClusterFeed.encode(shot)
			if payload ~= nil then
				ctx.emit(payload)
			end
		end
	end

	hooks.attacks = function(ctx: any)
		-- Lane-bounded contact (ADR 0010, Amendment 9): a passed mob attacks only when its authored lane
		-- is the lead's lane at the crossing (the lead's updated x). An off-lane mob is consumed with no
		-- reward and no loss. attackClusters returns one result per id, in the order given, so
		-- results[i] belongs to attacking[i]; passes come in id order, which is the attack order.
		local lead = LaneGeometry.laneOf(ctx.x)
		local laneById: { [number]: string } = {}
		for _, c in ctx.layout.clusters do
			laneById[c.id] = c.lane
		end
		local ids: { string } = {}
		local attacking: { number } = {}
		for _, id in ctx.passedClusters do
			if lead ~= nil and laneById[id] == lead then
				table.insert(ids, `c{id}`)
				table.insert(attacking, id)
			else
				ctx.state:passCluster(`c{id}`)
			end
		end
		local results = ctx.state:attackClusters(ids)
		for i, result in results do
			if result.ok then
				ctx.emit({
					kind = "attack",
					id = attacking[i],
					before = result.before,
					after = result.after,
				})
			end
		end
	end

	hooks.endCheck = function(ctx: any): boolean
		return ctx.state:outcome() == "defeated"
	end

	hooks.reset = function()
		targeting = nil
	end

	return hooks
end

return RunHooks
