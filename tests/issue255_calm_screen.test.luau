--!strict
-- Issue #255 (calm screen). The essentials-only render: trails, extra shot parts, the translucent gate
-- strip, hit shake, dust/chevron emitters, reward floaters and the lead ring are off by default, each
-- behind one Config.debug flag that brings only that effect back. Headless: the pure builders decide
-- how many Instances are created, and the client sites must ask them. The on-device look is UNVERIFIED.
local Config = require("../src/shared/Config")
local DebugSwitches = require("../src/shared/DebugSwitches")
local fs = require("@lune/fs")

local function eq(a: any, b: any, msg: string)
	assert(a == b, `{msg}: expected {tostring(b)}, got {tostring(a)}`)
end
local function has(path: string, needle: string): boolean
	return string.find(fs.readFile(path), needle, 1, true) ~= nil
end

local CALM = {
	"noTrails",
	"noHitShake",
	"noDust",
	"noShotExtras",
	"noGateStrip",
	"noRewardFloaters",
	"noLeadRing",
}

local function flags(overrides: { [string]: boolean }?): any
	local d: any = table.clone(Config.debug)
	for k, v in overrides or {} do
		d[k] = v
	end
	return d
end

return {
	{
		name = "issue 255: every calm-screen switch defaults on and validates as a boolean",
		run = function()
			for _, f in CALM do
				eq((Config.debug :: any)[f], true, `{f} default`)
				local copy: any = table.clone(Config)
				copy.debug = table.clone(Config.debug)
				copy.debug[f] = "x"
				eq(Config.validate(copy), false, `{f} validated`)
			end
		end,
	},
	{
		name = "issue 255: by default a shot creates no Trail, no extra parts; chevrons/mobs no emitters; no ring",
		run = function()
			local d = flags()
			eq(DebugSwitches.shotTrailBuilt(d), false, "trail built")
			eq(DebugSwitches.shotExtraParts(d, 3), 0, "extra parts per shot")
			eq(DebugSwitches.dustBuilt(d), false, "dust emitters built")
			eq(DebugSwitches.leadRingBuilt(d), false, "lead ring built")
			eq(DebugSwitches.gateStripTransparency(d, 0.25), 1, "gate strip hidden")
			eq(DebugSwitches.rewardFloaters(d), false, "floaters")
			local x, y = DebugSwitches.hitShake(d, 0.7, -0.3)
			eq(x + y, 0, "shake")
		end,
	},
	{
		name = "issue 255: one flip brings back exactly one effect",
		run = function()
			eq(DebugSwitches.shotTrailBuilt(flags({ noTrails = false })), true, "trail back")
			eq(DebugSwitches.shotExtraParts(flags({ noShotExtras = false }), 3), 3, "extras back")
			eq(DebugSwitches.dustBuilt(flags({ noDust = false })), true, "dust back")
			eq(DebugSwitches.leadRingBuilt(flags({ noLeadRing = false })), true, "ring back")
			eq(
				DebugSwitches.gateStripTransparency(flags({ noGateStrip = false }), 0.25),
				0.25,
				"strip back"
			)
			eq(
				DebugSwitches.rewardFloaters(flags({ noRewardFloaters = false })),
				true,
				"floaters back"
			)
			-- and the others stay off
			local d = flags({ noLeadRing = false })
			eq(DebugSwitches.shotTrailBuilt(d), false, "trail still off")
			eq(DebugSwitches.dustBuilt(d), false, "dust still off")
		end,
	},
	{
		name = "issue 255: the client sites ask the builders; no full-screen flash exists",
		run = function()
			assert(has("src/client/ClusterView.luau", "DebugSwitches.shotTrailBuilt"), "trail site")
			assert(
				has("src/client/ClusterView.luau", "DebugSwitches.shotExtraParts"),
				"extras site"
			)
			assert(
				has("src/client/ClusterView.luau", "DebugSwitches.dustBuilt"),
				"chevron dust site"
			)
			assert(
				has("src/client/ClusterView.luau", "DebugSwitches.rewardFloaters"),
				"floater site"
			)
			assert(has("src/client/MobView.luau", "DebugSwitches.dustBuilt"), "mob dust site")
			assert(
				has("src/client/GateView.luau", "DebugSwitches.gateStripTransparency"),
				"strip site"
			)
			assert(has("src/client/CrowdView.luau", "DebugSwitches.leadRingBuilt"), "ring site")
			-- the screen flash stays gone: the HUD hit handler draws nothing
			assert(
				has("src/client/Hud.luau", "function hud.applyHit(_, _: HitFeedback.Sample) end"),
				"hud flash"
			)
		end,
	},
}
