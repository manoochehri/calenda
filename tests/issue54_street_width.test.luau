--!strict
-- Issue #54 (Amendment 9 width paragraph): the road surface is 30 studs wide, each edge one stud
-- further out than the old 28, inside the unchanged 40-stud street/sidewalk corridor. The earth
-- plate must cover every ground point the high camera can see, so no empty or checker ground shows
-- beyond the buildings. Pure: the width and the coverage bound come from StreetSurface.
local CameraRig = require("../src/shared/CameraRig")
local DebugLayout = require("../src/shared/DebugLayout")
local LevelTheme = require("../src/shared/LevelTheme")
local StreetSurface = require("../src/shared/StreetSurface")

local function near(a: number, b: number, eps: number, name: string)
	assert(math.abs(a - b) <= eps, `{name}: expected {b}, got {a}`)
end

return {
	{
		name = "the road surface is 30 studs wide: half width 15, one stud out per edge from 14",
		run = function()
			near(StreetSurface.roadHalfWidth(DebugLayout.halfWidth), 15, 1e-9, "road half width")
			near(StreetSurface.roadHalfWidth(20), 15, 1e-9, "road half width at corridor 20")
			near(StreetSurface.roadHalfWidth(20) * 2, 30, 1e-9, "road surface width")
		end,
	},
	{
		name = "the sidewalks take the rest of the unchanged 40-stud corridor",
		run = function()
			near(StreetSurface.sidewalkWidth(DebugLayout.halfWidth), 5, 1e-9, "sidewalk width")
			near(
				StreetSurface.roadHalfWidth(DebugLayout.halfWidth)
					+ StreetSurface.sidewalkWidth(DebugLayout.halfWidth),
				DebugLayout.halfWidth,
				1e-9,
				"road plus sidewalk reaches the corridor edge"
			)
			near(DebugLayout.halfWidth, 20, 1e-9, "corridor unchanged")
		end,
	},
	{
		name = "the yellow curb stripe sits just inside the new road edge (level theme matches)",
		run = function()
			local roadHalf = StreetSurface.roadHalfWidth(DebugLayout.halfWidth)
			near(LevelTheme.level1.layout.curbX, roadHalf - 0.4, 1e-9, "curbX")
			assert(LevelTheme.level1.layout.curbX < roadHalf, "curb inside the road edge")
		end,
	},
	{
		name = "the earth plate covers every visible ground point of the high camera (no empty ground)",
		run = function()
			local length = DebugLayout.streetLength
			local plate = StreetSurface.groundPlate(length)
			local aspects = { 0.46, 1.0, 2.2 }
			for _, leadZ in { 0, length / 2, length } do
				for _, leadX in { -15, 0, 15 } do
					for _, pullback in { 1, 1.2, 1.4 } do
						local pose = CameraRig.pose(leadX, leadZ, pullback)
						local far = StreetSurface.farVisibleGroundZ(pose)
						local nearZ = StreetSurface.nearVisibleGroundZ(pose)
						assert(far <= plate.z1, `far ground {far} past plate {plate.z1}`)
						assert(nearZ >= plate.z0, `near ground {nearZ} before plate {plate.z0}`)
						for _, aspect in aspects do
							local reach = math.abs(pose.px)
								+ CameraRig.visibleHalfWidth(pose, far, aspect)
							assert(reach <= plate.x1, `side reach {reach} past plate {plate.x1}`)
						end
					end
				end
			end
		end,
	},
}
