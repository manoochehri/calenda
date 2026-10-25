--!strict
-- The ONE pure quality config (issue #65), shared with the future JuiceConfig (#63): a global
-- level (high / medium / low) and the hard caps that go with it. Presentation only: nothing here
-- touches gameplay. #63 adds its own per-level fields to `levels` rather than a second table.
-- Numbers are [default] tuning values; all counts are HARD caps the client never exceeds.
--
-- maxMobs        mobs drawn at once (nearest first); the rest are not drawn.
-- maxFigures     individual spectators on screen across ALL mobs (each is body + head + arms = 3 Parts).
-- maxFiguresPerMob  most individuals one mob shows (Config.spectators.scatter sets the count).
-- maxDust        mobs that also carry a dust emitter (stride dust, puffs).
-- maxStream      converted spectators running into the parade at once.
-- puff           particles in one dust puff (slam, dissolve).
-- Emitters in total = maxDust + CHEVRONS (14 / 11 / 8). Slam and dissolve puffs are transient
-- Emit() bursts bounded by maxBurst (maxDust x 2 x puff). Override at run time: player attribute
-- CalendaQuality, or Config.debug.quality (see QualityConfig.pick).
local QualityConfig = {}

export type Level = {
	maxMobs: number,
	maxFigures: number,
	maxFiguresPerMob: number,
	maxDust: number,
	maxStream: number,
	puff: number,
}

QualityConfig.NAMES = table.freeze({ "high", "medium", "low" })
QualityConfig.DEFAULT = "medium" -- [default] phone-safe: touch devices start here; desktop may use high
QualityConfig.TOUCH_DEFAULT = "medium"
QualityConfig.DESKTOP_DEFAULT = "high"

QualityConfig.levels = table.freeze({
	high = table.freeze({
		maxMobs = 20,
		maxFigures = 300,
		maxFiguresPerMob = 90,
		maxDust = 8,
		maxStream = 24,
		puff = 40,
	}),
	medium = table.freeze({
		maxMobs = 16,
		maxFigures = 200,
		maxFiguresPerMob = 60,
		maxDust = 5,
		maxStream = 16,
		puff = 24,
	}),
	low = table.freeze({
		maxMobs = 12,
		maxFigures = 100,
		maxFiguresPerMob = 30,
		maxDust = 3,
		maxStream = 8,
		puff = 12,
	}),
}) :: { [string]: Level }

-- A valid level name, whatever was asked for.
function QualityConfig.resolve(name: any): string
	if type(name) == "string" and QualityConfig.levels[name] ~= nil then
		return name
	end
	return QualityConfig.DEFAULT
end

function QualityConfig.get(name: any): Level
	return QualityConfig.levels[QualityConfig.resolve(name)]
end

function QualityConfig.defaultFor(touchEnabled: boolean): string
	return if touchEnabled then QualityConfig.TOUCH_DEFAULT else QualityConfig.DESKTOP_DEFAULT
end

QualityConfig.CHEVRONS = 6 -- [default] warning chevrons (each carries one small dust emitter)
QualityConfig.BURSTS_PER_MOB = 2 -- a slam puff and a dissolve puff per mob

function QualityConfig.isValid(name: any): boolean
	return type(name) == "string" and QualityConfig.levels[name] ~= nil
end

-- Emitters one level can create: the dust emitters and the chevron dust.
function QualityConfig.maxEmitters(name: any): number
	local l = QualityConfig.get(name)
	return l.maxDust + QualityConfig.CHEVRONS
end

-- Most particles one frame's Emit() bursts can add (a puff only plays on a mob that has a dust
-- emitter, so at most maxDust mobs burst at once). Transient.
function QualityConfig.maxBurst(name: any): number
	local l = QualityConfig.get(name)
	return l.maxDust * QualityConfig.BURSTS_PER_MOB * l.puff
end

-- The quality to use: the owner's override (a player attribute, set from the Studio Properties
-- panel or the Command Bar) beats Config.debug.quality, which beats the device default.
function QualityConfig.pick(attribute: any, configValue: any, touchEnabled: boolean): string
	if QualityConfig.isValid(attribute) then
		return attribute :: string
	end
	if QualityConfig.isValid(configValue) then
		return configValue :: string
	end
	return QualityConfig.defaultFor(touchEnabled)
end

return QualityConfig
