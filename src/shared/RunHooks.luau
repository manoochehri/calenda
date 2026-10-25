--!strict
-- Production gameplay hooks connecting target selection to RunState and parade HP.
-- Pure: the server supplies the RunState and replicates the emitted events.
local Config = require("./Config")
local ClusterFeed = require("./ClusterFeed")
local CrowdMath = require("./CrowdMath")
local Level = require("./Level")
local Targeting = require("./Targeting")

local RunHooks = {}

function RunHooks.new(layout: Level.Layout, config: any?): any
	local cfg = config or Config
	local targeting: Targeting.Session? = nil
	local hooks: any = {}

	local function session(ctx: any): Targeting.Session
		if targeting == nil then
			targeting = Targeting.new({
				layout = layout,
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
			Level.sideOf(ctx.x, cfg),
			ctx.t0
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
		-- attackClusters returns one result per id, in the order given, so results[i] belongs to
		-- passedClusters[i]; Targeting reports passed clusters in id order, which is the attack order.
		local ids: { string } = {}
		for _, id in ctx.passedClusters do
			table.insert(ids, `c{id}`)
		end
		local results = ctx.state:attackClusters(ids)
		for i, result in results do
			if result.ok then
				ctx.emit({
					kind = "attack",
					id = ctx.passedClusters[i],
					hpBefore = result.hpBefore,
					hpAfter = result.hpAfter,
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
