--!strict
-- Issue #254: the one place a Studio debug switch is declared. A switch is ONE ROW below; nothing
-- else needs editing. Config.debug takes its defaults from here, Config.validate checks every row,
-- and the registry test (tests/debugregistry.test.luau) iterates the rows, so a new row is
-- defaulted, validated and tested without touching any of them.
--
--   boolean row: { name, describe, group, default? }        default false (= normal game)
--   enum row:    { name, kind = "enum", values, describe }  default nil (= automatic)
--
-- Read a switch at its one call site as `Config.debug.<name>`. If the decision is worth a pure,
-- testable function, put it in DebugSwitches / MotionSwitches (they take Config.debug); that is
-- optional and is not part of adding a switch.
--
-- To flip a switch for a Studio A/B run, set that row's `default = true` locally (this replaces
-- editing a literal in Config.luau) and put it back before committing: the registry test fails on a
-- committed row that is not off.
-- Every boolean switch defaults to false and a default must never change behaviour: with every
-- row at its default the game is the normal game. Only the human flips a switch, in Studio.
local DebugRegistry = {}

export type Row = {
	name: string,
	describe: string,
	group: string,
	default: boolean?, -- boolean rows: local A/B flip only; the committed value is always false/absent
	kind: ("boolean" | "enum")?,
	values: { string }?, -- enum rows: the allowed values; the default is nil
}

-- The flags table the game carries as Config.debug: every boolean row is a boolean, an enum row is
-- a string or nil. Kept as a map so the registry, not a type declaration, is the list of switches.
export type Flags = { [string]: any }

DebugRegistry.rows = table.freeze({
	{
		name = "startupTiming",
		group = "startup",
		describe = "opt-in local startup trace; no Output logging unless enabled",
	},
	-- Issue #85 A/B switches for Studio:
	{
		name = "freezeCamera",
		group = "issue85",
		describe = "hold the camera at its first pose: does the flicker survive a still camera?",
	},
	{
		name = "noShadows",
		group = "issue85",
		describe = "Lighting.GlobalShadows = false: is it shadow flicker?",
	},
	{
		name = "rawExtrapolation",
		group = "issue85",
		describe = "the pre-#85 snap-to-State lead path instead of ServerClock",
	},
	{
		name = "quality",
		group = "issue65",
		kind = "enum",
		values = { "low", "medium", "high" },
		describe = "nil = automatic (medium on touch, high otherwise); or force the mob quality",
	},
	-- Issue #171 A/B switches (flip one, replay the same route):
	{ name = "noTrails", group = "issue171", describe = "shot Trails (Neon streaks) off" },
	{ name = "noHitShake", group = "issue171", describe = "hit camera shake off" },
	{
		name = "noTransparentStrips",
		group = "issue171",
		describe = "GateView crossing strip and LeadRing drawn opaque",
	},
	{ name = "noDust", group = "issue171", describe = "chevron and mob dust ParticleEmitters off" },
	-- Issue #222: lane-label plates
	{
		name = "legacyLaneLabelPlates",
		group = "issue222",
		describe = "true brings back the dark rectangles behind lane labels",
	},
	-- Issue #240 A/B switches for horde and parade motion:
	{
		name = "noMobStride",
		group = "issue240",
		describe = "horde: no hop, no arm pump (lean and advance remain)",
	},
	{
		name = "calmMobStride",
		group = "issue240",
		describe = "horde: hop at 30%, no arm pump (the recommended readable look)",
	},
	{ name = "noBreath", group = "issue240", describe = "parade: per-beat size pulse off" },
	{
		name = "noCrowdFeel",
		group = "issue240",
		describe = "parade: join bounce, cheer hop, flinch dip off",
	},
	{
		name = "noFollowerDance",
		group = "issue240",
		describe = "parade: beat-synced dance hop/sway/spin off",
	},
	{
		name = "noFollowerMarch",
		group = "issue240",
		describe = "parade and runners/leavers: march hop and squash/stretch off (runners lose their hop too)",
	},
	-- Issue #256 / #147: diagnostics
	{
		name = "perfOverlay",
		group = "issue256",
		describe = "on-screen Parts / emitters / trails / dt p50,p95",
	},
} :: { Row })

local function isEnum(row: Row): boolean
	return row.kind == "enum"
end

-- A fresh, unfrozen Config.debug table: every boolean false, every enum nil.
function DebugRegistry.defaults(): Flags
	local flags: Flags = {}
	for _, row in DebugRegistry.rows do
		if not isEnum(row) then
			flags[row.name] = row.default == true
		end
	end
	return flags
end

-- The names of every row, in declaration order.
function DebugRegistry.names(): { string }
	local out = {}
	for _, row in DebugRegistry.rows do
		table.insert(out, row.name)
	end
	return out
end

function DebugRegistry.has(name: string): boolean
	for _, row in DebugRegistry.rows do
		if row.name == name then
			return true
		end
	end
	return false
end

-- (ok, message). Every boolean row must be a boolean, every enum row nil or one of its values.
function DebugRegistry.validate(debugFlags: any): (boolean, string?)
	if type(debugFlags) ~= "table" then
		return false, "debug must be a table"
	end
	for _, row in DebugRegistry.rows do
		local v = debugFlags[row.name]
		if isEnum(row) then
			local allowed = row.values :: { string }
			if v ~= nil and table.find(allowed, v) == nil then
				return false, `debug.{row.name} must be nil, "{table.concat(allowed, '", "')}"`
			end
		elseif type(v) ~= "boolean" then
			return false, `debug.{row.name} must be a boolean`
		end
	end
	return true, nil
end

return DebugRegistry
