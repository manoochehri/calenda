--!strict
-- The ONE pure quality config (issue #65), shared with the future JuiceConfig (#63): a global
-- level (high / medium / low) and the hard caps that go with it. Presentation only: nothing here
-- touches gameplay. #63 adds its own per-level fields to `levels` rather than a second table.
-- Numbers are [default] tuning values; all counts are HARD caps the client never exceeds.
--
-- mobScale       multiplies the mob size derived from a cluster's reward.
-- maxMobSize     most spectators one mob represents (figures + particles).
-- maxMobs        mobs drawn at once (nearest first); the rest are not drawn.
-- maxFigures     real figures on screen across ALL mobs (each is body + head + arms = 3 Parts).
-- maxFiguresPerMob  figures in one mob's wedge.
-- maxDots        particles alive per mob (rate x lifetime); maxTotalDots across all mobs.
-- maxDust        mobs that also carry a dust emitter (stride dust, puffs).
-- maxStream      converted spectators running into the parade at once.
-- puff           particles in one dissolve / impact puff.
-- Emitters in total = maxMobs + maxDust + CHEVRONS (34 / 27 / 21). Steady particles are bounded
-- by maxTotalDots; slam puffs are transient Emit() bursts on top, bounded by maxBurst
-- (maxDust x 3 x puff = 960 / 360 / 108). Override at run time: player attribute CalendaQuality,
-- or Config.debug.quality (see QualityConfig.pick).
local QualityConfig = {}

export type Level = {
	mobScale: number,
	maxMobSize: number,
	maxMobs: number,
	maxFigures: number,
	maxFiguresPerMob: number,
	maxDots: number,
	maxTotalDots: number,
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
		mobScale = 1.5,
		maxMobSize = 2000,
		maxMobs = 20,
		maxFigures = 300,
		maxFiguresPerMob = 90,
		maxDots = 1500,
		maxTotalDots = 6000,
		maxDust = 8,
		maxStream = 24,
		puff = 40,
	}),
	medium = table.freeze({
		mobScale = 1.0,
		maxMobSize = 1200,
		maxMobs = 16,
		maxFigures = 200,
		maxFiguresPerMob = 60,
		maxDots = 900,
		maxTotalDots = 3500,
		maxDust = 5,
		maxStream = 16,
		puff = 24,
	}),
	low = table.freeze({
		mobScale = 0.5,
		maxMobSize = 600,
		maxMobs = 12,
		maxFigures = 100,
		maxFiguresPerMob = 30,
		maxDots = 400,
		maxTotalDots = 1500,
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
QualityConfig.BURSTS_PER_MOB = 3 -- one dust puff plus two swarm puffs when a mob slams

function QualityConfig.isValid(name: any): boolean
	return type(name) == "string" and QualityConfig.levels[name] ~= nil
end

-- Emitters one level can create: a swarm emitter per mob, the dust emitters, the chevron dust.
function QualityConfig.maxEmitters(name: any): number
	local l = QualityConfig.get(name)
	return l.maxMobs + l.maxDust + QualityConfig.CHEVRONS
end

-- Most particles one frame's Emit() bursts can add on top of the steady swarm (a slam puff only
-- plays on a mob that has a dust emitter, so at most maxDust mobs burst at once). Transient.
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
