--!strict
-- Issue #171: one-flip Studio A/B switches for the still-unresolved road flash candidates
-- (shot trails, hit camera shake, translucent strips/ring, dust particles). All default false =
-- normal game. DebugSwitches is the pure decision; the client sites must call it.
local Config = require("../src/shared/Config")
local DebugSwitches = require("../src/shared/DebugSwitches")
local fs = require("@lune/fs")

local function eq(a: any, b: any, msg: string)
	assert(a == b, `{msg}: expected {tostring(b)}, got {tostring(a)}`)
end

local FLAGS = { "noTrails", "noHitShake", "noTransparentStrips", "noDust" }

local function with(flag: string): any
	local d: any =
		{ noTrails = false, noHitShake = false, noTransparentStrips = false, noDust = false }
	d[flag] = true
	return d
end
local OFF: any =
	{ noTrails = false, noHitShake = false, noTransparentStrips = false, noDust = false }

local function has(path: string, needle: string): boolean
	return string.find(fs.readFile(path), needle, 1, true) ~= nil
end

return {
	{
		name = "issue 171: the A/B switches default to false and validate as booleans",
		run = function()
			for _, f in FLAGS do
				eq((Config.debug :: any)[f], false, `{f} default`)
				local copy: any = table.clone(Config)
				copy.debug = table.clone(Config.debug)
				copy.debug[f] = 1
				local ok = Config.validate(copy)
				eq(ok, false, `{f} must be validated as boolean`)
			end
		end,
	},
	{
		name = "issue 171: with every switch off the helpers change nothing",
		run = function()
			eq(DebugSwitches.trailEnabled(OFF, true), true, "trail on")
			eq(DebugSwitches.trailEnabled(OFF, false), false, "trail stays off")
			local x, y = DebugSwitches.hitShake(OFF, 0.7, -0.3)
			eq(x, 0.7, "shake x")
			eq(y, -0.3, "shake y")
			eq(DebugSwitches.stripTransparency(OFF, 0.25), 0.25, "strip")
			eq(DebugSwitches.dustRate(OFF, 12), 12, "dust rate")
			eq(DebugSwitches.allowDustPuff(OFF), true, "dust puff")
		end,
	},
	{
		name = "issue 171: each switch removes only its own candidate",
		run = function()
			eq(DebugSwitches.trailEnabled(with("noTrails"), true), false, "noTrails")
			local x, y = DebugSwitches.hitShake(with("noHitShake"), 0.7, -0.3)
			eq(x + y, 0, "noHitShake")
			eq(DebugSwitches.stripTransparency(with("noTransparentStrips"), 0.25), 0, "opaque")
			eq(
				DebugSwitches.stripTransparency(with("noTransparentStrips"), 1),
				1,
				"hidden stays hidden"
			)
			eq(DebugSwitches.dustRate(with("noDust"), 12), 0, "noDust rate")
			eq(DebugSwitches.allowDustPuff(with("noDust")), false, "noDust puff")
			-- an unrelated switch leaves the others alone
			eq(DebugSwitches.trailEnabled(with("noHitShake"), true), true, "trail untouched")
		end,
	},
	{
		name = "issue 171: the client applies each switch at its site",
		run = function()
			assert(has("src/client/ClusterView.luau", "DebugSwitches.trailEnabled"), "trail site")
			assert(
				has("src/client/ClusterView.luau", "DebugSwitches.dustRate"),
				"chevron dust site"
			)
			assert(has("src/client/MobView.luau", "DebugSwitches.dustRate"), "mob dust site")
			assert(has("src/client/MobView.luau", "DebugSwitches.allowDustPuff"), "mob puff site")
			assert(has("src/client/Main.client.luau", "DebugSwitches.hitShake"), "shake site")
			assert(has("src/client/GateView.luau", "DebugSwitches.stripTransparency"), "strip site")
			assert(has("src/client/CrowdView.luau", "DebugSwitches.stripTransparency"), "ring site")
		end,
	},
}
