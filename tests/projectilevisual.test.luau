--!strict
-- Issue #151: the look of each projectile. Regular shots alternate note and heart; every fourth
-- shot is a gift (the server's cadence, Targeting.shotKind, spec s4 / ADR 0004). Gifts fly a
-- high, slow, looping arc. Pure: the choice and the arc parameters, not the Parts.
local Config = require("../src/shared/Config")
local CrowdMath = require("../src/shared/CrowdMath")
local FeedbackMath = require("../src/shared/FeedbackMath")
local ProjectileVisual = require("../src/shared/ProjectileVisual")
local ShotLook = require("../src/shared/ShotLook")
local Targeting = require("../src/shared/Targeting")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

-- A section count with a dancer section present (the gift cadence needs one).
local function dancerSections(): number
	for n = 1, 6 do
		if CrowdMath.sectionType(n) == "dancers" then
			return n
		end
	end
	error("no dancer section in the first six sections")
end

return {
	{
		name = "visual per shot number: every giftEveryNthShot-th shot is a gift, the rest alternate note and heart",
		run = function()
			local sections = dancerSections()
			for n = 1, 2 * Config.giftEveryNthShot do
				local kind = Targeting.shotKind(n, sections)
				local visual = ProjectileVisual.kind(kind, n)
				if n % Config.giftEveryNthShot == 0 then
					eq(kind, "gift", `shot {n} is on the cadence`)
					eq(visual, "gift", `shot {n} looks like a gift`)
				else
					eq(kind, "note", `shot {n} is a regular shot`)
					assert(visual == "note" or visual == "heart", `shot {n} became {visual}`)
					eq(visual, if n % 2 == 1 then "heart" else "note", `shot {n} alternates`)
				end
			end
		end,
	},
	{
		name = "a gift is always a gift, whatever its index, never a heart or a note",
		run = function()
			for n = 1, 40 do
				eq(ProjectileVisual.kind("gift", n), "gift", `gift index {n}`)
			end
		end,
	},
	{
		name = "gift arc: slower and higher than a note at the same distance, and bounded",
		run = function()
			local d = 40
			assert(
				ProjectileVisual.flightSeconds("gift", d) > FeedbackMath.flightSeconds(d) * 1.4,
				"a gift takes clearly longer"
			)
			assert(
				ProjectileVisual.GIFT_APEX > FeedbackMath.ARC_HEIGHT * 1.5,
				"a gift arcs clearly higher"
			)
			assert(ProjectileVisual.longestFlight() <= 1.5, "a gift stays readable in time")
			eq(
				ProjectileVisual.flightSeconds("note", d),
				FeedbackMath.flightSeconds(d),
				"notes keep their flight"
			)
		end,
	},
	{
		name = "gift loop: starts and ends at zero, loops at least twice, never dips below the arc",
		run = function()
			local start = ProjectileVisual.giftLoop(0)
			local stop = ProjectileVisual.giftLoop(1)
			eq(start.dx + start.dy + start.dz, 0, "starts on the arc")
			assert(math.abs(stop.dx) < 1e-9 and math.abs(stop.dy) < 1e-9, "ends on the arc")
			eq(ProjectileVisual.GIFT_LOOPS >= 2, true, "at least two loops")
			local crossings, prev, peak = 0, nil, 0
			for i = 0, 400 do
				local p = ProjectileVisual.giftLoop(i / 400)
				assert(p.dy >= -1e-9, `loop dipped below the arc at {i}`)
				peak = math.max(peak, p.dy)
				if prev ~= nil and (prev > 0) ~= (p.dx > 0) and math.abs(p.dx) > 1e-9 then
					crossings += 1
				end
				prev = p.dx
			end
			assert(crossings >= 2 * ProjectileVisual.GIFT_LOOPS - 1, `only {crossings} crossings`)
			assert(peak > 0.5 * ProjectileVisual.GIFT_LOOP_RADIUS, "the loop is visible")
		end,
	},
	{
		name = "gift flight fits the pool: the capacity covers the longest gift flight",
		run = function()
			local cap =
				ShotLook.projectileCapacity(Config.firing.cap, ProjectileVisual.longestFlight())
			assert(
				cap >= math.ceil(Config.firing.cap * ProjectileVisual.longestFlight()),
				"covers rate x flight"
			)
			assert(cap <= ShotLook.PROJECTILE_HARD_CAP, "within the hard cap")
		end,
	},
}
