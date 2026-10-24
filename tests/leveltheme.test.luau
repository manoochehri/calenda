--!strict
-- LevelTheme (issue #54 phase 1): data-driven theme, contrast checks, budgets, heights vs CameraRig.
local CameraRig = require("../src/shared/CameraRig")
local DebugLayout = require("../src/shared/DebugLayout")
local LevelTheme = require("../src/shared/LevelTheme")

local theme = LevelTheme.level1
local function near(a: number, b: number, eps: number, name: string)
	assert(math.abs(a - b) <= eps, `{name}: expected {b}, got {a}`)
end

return {
	{
		name = "luminance and contrast follow WCAG: white 1, black 0, white/black 21, symmetric",
		run = function()
			local white, black = LevelTheme.rgb(255, 255, 255), LevelTheme.rgb(0, 0, 0)
			near(LevelTheme.luminance(white), 1, 1e-9, "white")
			near(LevelTheme.luminance(black), 0, 1e-9, "black")
			near(LevelTheme.contrast(white, black), 21, 1e-9, "white/black")
			near(LevelTheme.contrast(black, white), 21, 1e-9, "symmetric")
			near(LevelTheme.contrast(white, white), 1, 1e-9, "same")
		end,
	},
	{
		name = "gameplay colors stay readable on the road (followers, lead, gates, ring)",
		run = function()
			local g = theme.gameplay
			for name, c in
				{
					follower = g.follower,
					multiplier = g.multiplierBanner,
					spectator = g.spectator,
				}
			do
				local ratio = LevelTheme.contrast(theme.palette.road, c)
				assert(ratio >= 2.2, `{name} vs road {ratio}`)
			end
			assert(LevelTheme.contrast(theme.palette.road, g.adderBanner) >= 1.8, "adder vs road")
			assert(LevelTheme.contrast(theme.palette.road, g.lead) >= 4, "lead vs road")
			assert(LevelTheme.contrast(theme.palette.road, g.ring) >= 4, "ring vs road")
		end,
	},
	{
		name = "gates differ by luminance as well as hue (not a color-only distinction)",
		run = function()
			local g = theme.gameplay
			assert(
				LevelTheme.contrast(g.adderBanner, g.multiplierBanner) >= 1.5,
				"adder vs multiplier"
			)
			assert(LevelTheme.contrast(g.follower, g.lead) >= 3, "follower vs lead")
		end,
	},
	{
		name = "road, sidewalk, curb stripe and facades keep clear value steps",
		run = function()
			local p = theme.palette
			assert(LevelTheme.contrast(p.road, p.sidewalk) >= 3, "road vs sidewalk")
			assert(LevelTheme.contrast(p.road, p.curb) >= 4, "road vs curb")
			local alt = LevelTheme.contrast(p.road, p.roadAlt)
			assert(alt >= 1.15 and alt <= 1.5, `road courses subtle but visible: {alt}`)
			for _, style in theme.facades do
				assert(LevelTheme.contrast(p.road, style.wall) >= 2.2, `{style.name} wall vs road`)
				assert(LevelTheme.contrast(style.wall, style.trim) >= 1.15, `{style.name} trim`)
			end
		end,
	},
	{
		name = "report lists every checked pair and all pass",
		run = function()
			local report = LevelTheme.contrastReport(theme)
			assert(#report >= 40, "enough pairs")
			for _, row in report do
				assert(row.ok, `{row.name}: {row.ratio} < {row.min}`)
			end
		end,
	},
	{
		name = "the pairs that were too low before are now above their floors (sidewalk/ground, lead, ring, follower, facade/plaza)",
		run = function()
			local want = {
				["sidewalk vs ground"] = 1.3,
				["sidewalk vs lead"] = 1.25,
				["sidewalk vs ring"] = 1.2,
				["sidewalk vs follower"] = 1.8,
				["sidewalk vs spectator"] = 1.4,
				["plaza vs ochre wall"] = 1.25,
				["plaza vs terracotta wall"] = 1.25,
				["plaza vs pink wall"] = 1.25,
				["plaza vs lavender wall"] = 1.25,
			}
			local seen = 0
			for _, row in LevelTheme.contrastReport(theme) do
				local floor = want[row.name]
				if floor then
					seen += 1
					assert(row.ratio >= floor, `{row.name} {row.ratio}`)
				end
			end
			assert(seen == 9, `all pairs reported: {seen}`)
		end,
	},
	{
		name = "budgets are bounded and sum under 600 parts",
		run = function()
			local b = theme.budgets
			assert(b.maxFacadeParts > 0 and b.maxFlagStrips > 0 and b.maxLamps > 0, "positive")
			local componentCaps = b.maxFacadeParts
				+ b.maxFlagStrips
				+ b.maxLamps * 2
				+ b.maxPlazaParts
				+ b.maxGroundParts
			assert(
				LevelTheme.maxTotalParts(theme) >= componentCaps + 7,
				"includes Rey's seven Parts"
			)
			assert(
				LevelTheme.maxTotalParts(theme) <= 600,
				`total {LevelTheme.maxTotalParts(theme)}`
			)
			assert(b.maxLights <= 16, "lights sparse")
			assert(b.maxFlagCells <= 2000, "flag cells bounded")
		end,
	},
	{
		name = "facade heights sit below the camera and outside the corridor (CameraRig)",
		run = function()
			local top = LevelTheme.facadeTopMax(theme)
			assert(top <= CameraRig.HEIGHT - 2 * CameraRig.CLEARANCE, `top {top} too tall`)
			assert(theme.heights.facadeMin >= 10, "two-storey look")
			assert(
				theme.layout.facadeInset >= DebugLayout.halfWidth + 6,
				"inset beyond the corridor"
			)
			-- flags hang above the tallest prop and outside the corridor
			for _, lane in theme.layout.flagLanes do
				assert(
					lane.y - theme.layout.flagHeight / 2 > LevelTheme.PROP_TOP,
					"flags above props"
				)
				assert(lane.x >= DebugLayout.halfWidth + 2, "flag lane outside corridor")
				assert(lane.x < theme.layout.facadeInset, "flag lane inside the facades")
			end
			assert(theme.layout.lampX >= DebugLayout.halfWidth + 1, "lamps outside corridor")
			local problems = LevelTheme.validate(theme, DebugLayout.halfWidth)
			assert(#problems == 0, table.concat(problems, "; "))
		end,
	},
	{
		name = "validate catches a facade pulled into the play corridor",
		run = function()
			local bad = table.clone(theme)
			bad.layout = table.clone(theme.layout)
			bad.layout.facadeInset = 12
			assert(#LevelTheme.validate(bad, DebugLayout.halfWidth) > 0, "must complain")
		end,
	},
	{
		name = "lighting values are in range",
		run = function()
			local l = theme.lighting
			assert(l.clockTime >= 10 and l.clockTime <= 16, "daylight")
			assert(l.brightness > 0 and l.shadowSoftness >= 0 and l.shadowSoftness <= 1, "ranges")
		end,
	},
}
