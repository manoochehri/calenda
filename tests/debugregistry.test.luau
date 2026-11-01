--!strict
-- Issue #254: the debug-switch registry. A switch is one row in src/shared/DebugRegistry.luau; these
-- tests iterate the rows, so a new row is covered (defaulted, validated, read at a registered name)
-- without adding or editing anything here.
local Config = require("../src/shared/Config")
local DebugRegistry = require("../src/shared/DebugRegistry")
local fs = require("@lune/fs")

-- The switches that existed before the registry (#85, #171, #240, startup trace, quality). Pinned so the
-- migration cannot silently drop one; a NEW switch does not need to be listed here.
local MIGRATED = {
	"startupTiming",
	"freezeCamera",
	"noShadows",
	"rawExtrapolation",
	"quality",
	"noTrails",
	"noHitShake",
	"noTransparentStrips",
	"noDust",
	"noMobStride",
	"calmMobStride",
	"noBreath",
	"noCrowdFeel",
	"noFollowerDance",
	"noFollowerMarch",
	"legacyLaneLabelPlates",
	"perfOverlay",
	"noGateStrip",
	"noRewardFloaters",
	"noLeadRing",
}

local function sourceFiles(dir: string, out: { string }): { string }
	for _, entry in fs.readDir(dir) do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			sourceFiles(path, out)
		elseif string.match(entry, "%.luau$") then
			table.insert(out, path)
		end
	end
	return out
end

return {
	{
		name = "issue 254: rows are unique, described and grouped",
		run = function()
			local seen: { [string]: boolean } = {}
			for _, row in DebugRegistry.rows do
				assert(not seen[row.name], `duplicate switch {row.name}`)
				seen[row.name] = true
				assert(string.match(row.name, "^[%a][%w]*$") ~= nil, `bad switch name {row.name}`)
				assert(#row.describe > 0, `{row.name} has no description`)
				assert(#row.group > 0, `{row.name} has no group`)
				if row.kind == "enum" then
					assert(row.values ~= nil and #row.values > 0, `{row.name} enum has no values`)
				end
			end
		end,
	},
	{
		name = "issue 254: every pre-registry switch is still a row",
		run = function()
			for _, name in MIGRATED do
				assert(DebugRegistry.has(name), `switch {name} lost in the migration`)
			end
		end,
	},
	{
		name = "issue 254: Config.debug is exactly the registry and every shipped default is pinned",
		run = function()
			-- The shipped (committed) defaults. The issue #255 calm-screen switches are true; every
			-- other switch is false/nil. Changing a default means changing this table in the same PR.
			local TRUE_BY_DEFAULT = {
				noTrails = true,
				noHitShake = true,
				noDust = true,
				noGateStrip = true,
				noRewardFloaters = true,
				noLeadRing = true,
			}
			for _, row in DebugRegistry.rows do
				local v = (Config.debug :: any)[row.name]
				if row.kind == "enum" then
					assert(v == nil, `{row.name} must default to nil (automatic)`)
				else
					assert(
						v == (TRUE_BY_DEFAULT[row.name] == true),
						`{row.name} default is {tostring(v)}, pinned {tostring(
							TRUE_BY_DEFAULT[row.name] == true
						)}`
					)
				end
			end
			for name in Config.debug :: any do
				assert(DebugRegistry.has(name), `Config.debug.{name} is not a registry row`)
			end
		end,
	},
	{
		name = "issue 254: Config.validate rejects a wrong-typed value for every row",
		run = function()
			for _, row in DebugRegistry.rows do
				local copy: any = table.clone(Config)
				copy.debug = table.clone(Config.debug)
				copy.debug[row.name] = if row.kind == "enum" then "ultra" else 1
				local ok, err = Config.validate(copy)
				assert(ok == false, `{row.name} accepted a wrong-typed value`)
				assert(string.find(err or "", row.name, 1, true), `message names the switch: {err}`)
			end
			local good: any = table.clone(Config)
			good.debug = DebugRegistry.defaults()
			assert(Config.validate(good), "registry defaults validate")
			good.debug.quality = "low"
			assert(Config.validate(good), "a valid enum value validates")
		end,
	},
	{
		name = "issue 254: a missing row value fails validation, so a typo cannot silently disable a switch",
		run = function()
			local copy: any = table.clone(Config)
			copy.debug = {}
			assert(Config.validate(copy) == false, "empty debug table must not validate")
		end,
	},
	{
		name = "issue 254: every Config.debug.<name> read in src/ names a registered switch",
		run = function()
			local unknown = {}
			for _, path in sourceFiles("src", {}) do
				local text = fs.readFile(path)
				for name in string.gmatch(text, "Config%.debug%.([%a_][%w_]*)") do
					if not DebugRegistry.has(name) then
						table.insert(unknown, `{path}: Config.debug.{name}`)
					end
				end
			end
			assert(#unknown == 0, `unregistered switches read: {table.concat(unknown, "; ")}`)
		end,
	},
}
