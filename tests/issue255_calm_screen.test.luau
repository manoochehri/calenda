--!strict
-- Issue #255 (calm screen). Trails, the gate strip, hit shake, dust/chevron emitters, reward floaters
-- and the lead ring are off by default, each behind one Config.debug flag that brings only that effect
-- back. Shot shape pieces are NOT decoration (#151) and always stay. Cases 1-3 and 5 check pure
-- builders/data only; case 4 is a source grep (the client sites call the builders, the Hud hit handler
-- is a no-op). The on-device look is UNVERIFIED.
local Config = require("../src/shared/Config")
local DebugSwitches = require("../src/shared/DebugSwitches")
local ProjectileVisual = require("../src/shared/ProjectileVisual")
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
			eq((Config.debug :: any).noShotExtras, nil, "no switch removes shot shape pieces")
		end,
	},
	{
		name = "issue 255: by default no Trail, emitters, gate strip or ring is built",
		run = function()
			local d = flags()
			eq(DebugSwitches.shotTrailBuilt(d), false, "trail built")
			eq(DebugSwitches.dustBuilt(d), false, "dust emitters built")
			eq(DebugSwitches.leadRingBuilt(d), false, "lead ring built")
			eq(DebugSwitches.gateStripBuilt(d), false, "gate strip built")
			eq(DebugSwitches.rewardFloaters(d), false, "floaters")
			local x, y = DebugSwitches.hitShake(d, 0.7, -0.3)
			eq(x + y, 0, "shake")
		end,
	},
	{
		name = "issue 255: one flip brings back exactly one effect",
		run = function()
			eq(DebugSwitches.shotTrailBuilt(flags({ noTrails = false })), true, "trail back")
			eq(DebugSwitches.dustBuilt(flags({ noDust = false })), true, "dust back")
			eq(DebugSwitches.leadRingBuilt(flags({ noLeadRing = false })), true, "ring back")
			eq(DebugSwitches.gateStripBuilt(flags({ noGateStrip = false })), true, "strip back")
			eq(DebugSwitches.rewardFloaters(flags({ noRewardFloaters = false })), true, "floaters")
			local d = flags({ noLeadRing = false })
			eq(DebugSwitches.shotTrailBuilt(d), false, "trail still off")
			eq(DebugSwitches.dustBuilt(d), false, "dust still off")
		end,
	},
	{
		name = "issue 255 (source grep): client sites ask the builders; Hud hit handler draws nothing",
		run = function()
			assert(has("src/client/ClusterView.luau", "DebugSwitches.shotTrailBuilt"), "trail site")
			assert(has("src/client/ClusterView.luau", "DebugSwitches.dustBuilt"), "chevron site")
			assert(has("src/client/ClusterView.luau", "DebugSwitches.rewardFloaters"), "floaters")
			assert(has("src/client/MobView.luau", "DebugSwitches.dustBuilt"), "mob dust site")
			assert(has("src/client/GateView.luau", "DebugSwitches.gateStripBuilt"), "strip site")
			assert(has("src/client/CrowdView.luau", "DebugSwitches.leadRingBuilt"), "ring site")
			assert(
				has("src/client/Hud.luau", "function hud.applyHit(_, _: HitFeedback.Sample) end"),
				"hud flash"
			)
			assert(
				not has("src/client/ClusterView.luau", "noShotExtras"),
				"shot pieces always built"
			)
		end,
	},
	{
		name = "issue 255: note, heart and gift stay distinguishable under the calm defaults",
		run = function()
			local function sig(kind: any): string
				local out = {}
				for _, p in ProjectileVisual.geometry(kind) do
					table.insert(
						out,
						`{p.shape}:{p.w}x{p.h}@{p.x},{p.y}r{p.roll}{if p.ribbon then "R" else ""}`
					)
				end
				return table.concat(out, "|")
			end
			local note, heart, gift = sig("note"), sig("heart"), sig("gift")
			assert(note ~= heart and note ~= gift and heart ~= gift, "silhouettes collide")
			eq(#ProjectileVisual.geometry("note"), 3, "note pieces")
			eq(#ProjectileVisual.geometry("heart"), 3, "heart pieces")
			eq(#ProjectileVisual.geometry("gift"), 4, "gift pieces")
			-- the gift alone has ribbons; the heart alone has a 45-degree piece; the note has neither
			local function any(kind: any, f: (any) -> boolean): boolean
				for _, p in ProjectileVisual.geometry(kind) do
					if f(p) then
						return true
					end
				end
				return false
			end
			assert(
				any("gift", function(p)
					return p.ribbon
				end),
				"gift ribbons"
			)
			assert(not any("heart", function(p)
				return p.ribbon
			end), "heart no ribbon")
			assert(not any("note", function(p)
				return p.ribbon or p.roll ~= 0
			end), "note plain")
			assert(
				any("heart", function(p)
					return p.roll ~= 0
				end),
				"heart diamond"
			)
		end,
	},
}
