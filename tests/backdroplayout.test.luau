-- Issue #54: the camera should see a town backdrop beside the street, not a wide empty-earth band.
local BackdropLayout = require("../src/shared/BackdropLayout")
local DebugLayout = require("../src/shared/DebugLayout")
local LevelTheme = require("../src/shared/LevelTheme")

local theme = LevelTheme.level1
local layout = BackdropLayout.generate(DebugLayout.streetLength, theme)

return {
	{
		name = "the town backdrop fills both visible side bands along the whole route",
		run = function()
			assert(
				#layout <= BackdropLayout.MAX_BUILDINGS,
				`backdrop count {#layout} exceeds bound`
			)
			for _, side in { -1, 1 } do
				local nearZ = 0
				local found = false
				for _, building in layout do
					if building.side == side and building.row == 1 then
						assert(
							building.x * side >= BackdropLayout.NEAR_MIN_X,
							"town begins beyond the blank band"
						)
						assert(
							building.x * side <= BackdropLayout.NEAR_MAX_X,
							"town backdrop stays in its designed band"
						)
						if found then
							assert(
								building.z0 <= nearZ + BackdropLayout.MAX_GAP,
								"gap in the nearer town row"
							)
						end
						found = true
						nearZ = building.z1
					end
				end
				assert(nearZ >= DebugLayout.streetLength, `side {side} town ends before route end`)
			end
		end,
	},
	{
		name = "backdrop buildings stay outside gameplay and use the existing Oaxaca palette",
		run = function()
			for _, building in layout do
				assert(
					math.abs(building.x) - building.depth / 2 > DebugLayout.halfWidth,
					"town enters play corridor"
				)
				assert(
					building.height <= BackdropLayout.MAX_HEIGHT,
					"town exceeds the low backdrop silhouette"
				)
				local found = false
				for _, facade in theme.facades do
					if
						building.color.r == facade.wall.r
						and building.color.g == facade.wall.g
						and building.color.b == facade.wall.b
					then
						found = true
					end
				end
				assert(found, "backdrop color comes from the level facade palette")
			end
		end,
	},
}
