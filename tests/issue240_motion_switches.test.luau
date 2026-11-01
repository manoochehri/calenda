--!strict
-- Issue #240: one-flip Studio A/B switches per horde / parade motion family, so the owner can find
-- the motion that reads as strange by flipping one value. All default false = normal game.
-- MotionSwitches is the pure decision; the client sites must call it. Look is UNVERIFIED in engine.
local Config = require("../src/shared/Config")
local MotionSwitches = require("../src/shared/MotionSwitches")
local fs = require("@lune/fs")

local function eq(a: any, b: any, msg: string)
	assert(a == b, `{msg}: expected {tostring(b)}, got {tostring(a)}`)
end

local FLAGS = {
	"noMobStride",
	"calmMobStride",
	"noBreath",
	"noCrowdFeel",
	"noFollowerDance",
	"noFollowerMarch",
}

local function with(flag: string?): any
	local d: any = {}
	for _, f in FLAGS do
		d[f] = false
	end
	if flag ~= nil then
		d[flag] = true
	end
	return d
end

local function has(path: string, needle: string): boolean
	return string.find(fs.readFile(path), needle, 1, true) ~= nil
end

return {
	{
		name = "issue 240: the switches default to false and validate as booleans",
		run = function()
			for _, f in FLAGS do
				eq((Config.debug :: any)[f], false, `{f} default`)
				local copy: any = table.clone(Config)
				copy.debug = table.clone(Config.debug)
				copy.debug[f] = 1
				eq((Config.validate(copy)), false, `{f} must be validated as boolean`)
			end
		end,
	},
	{
		name = "issue 240: with every switch off the helpers change nothing",
		run = function()
			local off = with(nil)
			local h, l, a = MotionSwitches.mobStride(off, 0.4, 0.32, 2.8, 2.6)
			eq(h, 0.4, "stride hop")
			eq(l, 0.32, "stride lean")
			eq(a, 2.8, "stride arm")
			eq(MotionSwitches.breath(off, 1.04), 1.04, "breath")
			local fh, fy, fxz = MotionSwitches.crowdFeel(off, 0.5, 0.9, 1.05)
			eq(fh, 0.5, "feel hop")
			eq(fy, 0.9, "feel y")
			eq(fxz, 1.05, "feel xz")
			local dh, ds, dsp = MotionSwitches.dance(off, 0.3, 0.1, 0.2)
			eq(dh, 0.3, "dance hop")
			eq(ds, 0.1, "dance sway")
			eq(dsp, 0.2, "dance spin")
			local my, msy, mxz = MotionSwitches.march(off, 0.7, 1.1, 0.95)
			eq(my, 0.7, "march hop")
			eq(msy, 1.1, "march y")
			eq(mxz, 0.95, "march xz")
		end,
	},
	{
		name = "issue 240: noMobStride stops the hop and arm pump but keeps the forward lean",
		run = function()
			local h, l, a = MotionSwitches.mobStride(with("noMobStride"), 0.4, 0.32, 2.8, 2.6)
			eq(h, 0, "hop")
			eq(l, 0.32, "lean stays: it is the 'coming at you' cue")
			eq(a, 2.6, "arms held at rest height")
		end,
	},
	{
		name = "issue 240: calmMobStride keeps a small hop and drops the arm pump",
		run = function()
			local h, l, a = MotionSwitches.mobStride(with("calmMobStride"), 0.4, 0.32, 2.8, 2.6)
			assert(h > 0 and h < 0.4 * 0.5, "hop reduced but alive")
			eq(l, 0.32, "lean")
			eq(a, 2.6, "arm pump removed")
			-- noMobStride wins when both are set
			local h2 = MotionSwitches.mobStride(
				{ noMobStride = true, calmMobStride = true } :: any,
				0.4,
				0.32,
				2.8,
				2.6
			)
			eq(h2, 0, "noMobStride wins")
		end,
	},
	{
		name = "issue 240: each parade switch removes only its own family",
		run = function()
			eq(MotionSwitches.breath(with("noBreath"), 1.04), 1, "noBreath")
			local fh, fy, fxz = MotionSwitches.crowdFeel(with("noCrowdFeel"), 0.5, 0.9, 1.05)
			eq(fh, 0, "feel hop")
			eq(fy, 1, "feel y")
			eq(fxz, 1, "feel xz")
			local dh, ds, dsp = MotionSwitches.dance(with("noFollowerDance"), 0.3, 0.1, 0.2)
			eq(dh + ds + dsp, 0, "dance")
			local my, msy, mxz = MotionSwitches.march(with("noFollowerMarch"), 0.7, 1.1, 0.95)
			eq(my, 0, "march hop")
			eq(msy, 1, "march y")
			eq(mxz, 1, "march xz")
			-- an unrelated switch leaves the others alone
			eq(MotionSwitches.breath(with("noCrowdFeel"), 1.04), 1.04, "breath untouched")
		end,
	},
	{
		name = "issue 240: the client applies each switch at its site",
		run = function()
			for _, needle in { "MotionSwitches.mobStride" } do
				assert(has("src/client/MobView.luau", needle), needle)
			end
			for _, needle in
				{
					"MotionSwitches.breath",
					"MotionSwitches.crowdFeel",
					"MotionSwitches.dance",
					"MotionSwitches.march",
				}
			do
				assert(has("src/client/CrowdView.luau", needle), needle)
			end
		end,
	},
}
