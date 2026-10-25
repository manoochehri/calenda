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

-- Emitters one level can create: a swarm emitter per mob plus its dust emitters.
function QualityConfig.maxEmitters(name: any): number
	local l = QualityConfig.get(name)
	return l.maxMobs + l.maxDust
end

return QualityConfig
