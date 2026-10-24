--!strict
local StreetTheme = require("../src/shared/StreetTheme")
local HudLayout = require("../src/shared/HudLayout")

local function above(left: HudLayout.Region, right: HudLayout.Region, name: string)
	assert(left.top + left.height <= right.top, `{name}: regions overlap vertically`)
end

return {
	{
		name = "street values are warm and separate the road, sidewalk, ground, and plaza",
		run = function()
			local p = StreetTheme.palette
			assert(p.road[1] > p.road[2] and p.road[2] >= p.road[3], "road is warm, not blue-gray")
			assert(StreetTheme.contrastRatio(p.road, p.sidewalk) >= 4.5, "road/sidewalk contrast")
			assert(StreetTheme.contrastRatio(p.road, p.ground) >= 4.5, "road/ground contrast")
			assert(StreetTheme.contrastRatio(p.road, p.plaza) >= 2.0, "plaza reads apart from road")
			assert(
				StreetTheme.contrastRatio(p.road, p.follower) >= 2.0,
				"followers separate from road"
			)
		end,
	},
	{
		name = "the palette includes visible festive accents and a high-contrast lead marker",
		run = function()
			local p = StreetTheme.palette
			assert(#p.bunting >= 4, "multiple flag colors")
			assert(
				StreetTheme.contrastRatio(p.road, p.leadRing) >= 3.0,
				"lead ring is easy to find"
			)
			assert(
				StreetTheme.contrastRatio(p.ground, p.facade) >= 1.2,
				"facades separate from ground"
			)
		end,
	},
	{
		name = "the top HUD cluster stays compact and its rows do not overlap",
		run = function()
			local h = HudLayout
			above(h.caption, h.counter, "caption/counter")
			above(h.counter, h.detail, "counter/detail")
			above(h.detail, h.meter, "detail/meter")
			assert(h.counter.width <= 0.5, "counter leaves the street visible")
			assert(
				h.hp.centerX + h.hp.width / 2 <= h.counter.centerX - h.counter.width / 2,
				"HP bar stays clear of the centered counter"
			)
			assert(h.meter.width <= 0.4, "meter is narrower than the old banner")
			assert(h.meter.top + h.meter.height <= 0.24, "top HUD ends before the first road view")
			assert(h.hint.top >= 0.82, "steering hint stays near the bottom")
		end,
	},
}
