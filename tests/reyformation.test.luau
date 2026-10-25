--!strict
local CameraRig = require("../src/shared/CameraRig")
local DebugLayout = require("../src/shared/DebugLayout")
local ReyFormation = require("../src/shared/ReyFormation")
local ScreenProject = require("../src/shared/ScreenProject")

type Box = { cx: number, cy: number, cz: number, sx: number, sy: number, sz: number }

local function hits(a: { number }, b: { number }, box: Box): boolean
	local lo = { box.cx - box.sx / 2, box.cy - box.sy / 2, box.cz - box.sz / 2 }
	local hi = { box.cx + box.sx / 2, box.cy + box.sy / 2, box.cz + box.sz / 2 }
	local t0, t1 = 0, 1
	for i = 1, 3 do
		local d = b[i] - a[i]
		if math.abs(d) < 1e-12 then
			if a[i] < lo[i] or a[i] > hi[i] then
				return false
			end
		else
			local ta, tb = (lo[i] - a[i]) / d, (hi[i] - a[i]) / d
			if ta > tb then
				ta, tb = tb, ta
			end
			t0, t1 = math.max(t0, ta), math.min(t1, tb)
			if t0 > t1 then
				return false
			end
		end
	end
	return true
end

local function boxAt(x: number, z: number): Box
	return {
		cx = x,
		cy = ReyFormation.CENTER_Y,
		cz = z + ReyFormation.CENTER_Z,
		sx = 2 * ReyFormation.HALF_WIDTH,
		sy = ReyFormation.HEIGHT,
		sz = 2 * ReyFormation.HALF_DEPTH,
	}
end

return {
	{
		name = "Rey stays in the outer parade lane, follows steering, and is deterministic",
		run = function()
			local edge = DebugLayout.halfWidth - 6 - ReyFormation.HALF_WIDTH - 0.2
			for seed = 1, 64 do
				for _, leadX in { -14, -7, 0, 7, 14 } do
					local pose = ReyFormation.pose(leadX, 50, seed, DebugLayout.halfWidth - 6)
					local again = ReyFormation.pose(leadX, 50, seed, DebugLayout.halfWidth - 6)
					assert(
						pose.x == again.x and pose.z == again.z and pose.bob == again.bob,
						"same inputs give the same march pose"
					)
					assert(pose.bob >= 0 and pose.bob <= 0.25, "march bob stays subtle")
					assert(
						pose.z == 50 - ReyFormation.BEHIND,
						"Rey moves with the lead through the parade"
					)
					assert(
						math.abs(pose.x) <= edge,
						`seed {seed}: full body stays inside road edge`
					)
					assert(
						math.abs(pose.x) + ReyFormation.HALF_WIDTH <= 13.2 + 1e-6,
						`seed {seed}: full silhouette stays inside the curb stripe at its widest steering position`
					)
					assert(
						pose.side == (if seed % 2 == 0 then 1 else -1),
						"seed chooses a stable parade side"
					)
					assert(pose.x * pose.side > 0, "Rey stays in her outer lane as the lead steers")
				end
			end
			assert(
				ReyFormation.pose(0, 0, 1, DebugLayout.halfWidth - 6).bob == 0,
				"bob starts at baseline"
			)
			assert(
				ReyFormation.pose(0, 2, 1, DebugLayout.halfWidth - 6).bob > 0,
				"bob follows the deterministic parade phase"
			)
			assert(
				9.9 + 0.79 * (ReyFormation.SCALE + 0.1) > 13.2,
				"the next larger model would cross the curb at full steering"
			)
		end,
	},
	{
		name = "largest Rey silhouette stays visible from Jugar through the plaza",
		run = function()
			assert(
				(ReyFormation.BODY_CENTER_Y - ReyFormation.BODY_HALF_HEIGHT) * ReyFormation.SCALE
					> 0,
				"Rey's body is raised fully above the road"
			)
			for seed = 1, 64 do
				local checkedStart, checkedPlaza = false, false
				for _, leadX in { -14, -7, 0, 7, 14 } do
					for _, leadZ in { 0, 72, 700, DebugLayout.plazaStart } do
						for _, pullback in { 1, 1.2, 1.4 } do
							local rey =
								ReyFormation.pose(leadX, leadZ, seed, DebugLayout.halfWidth - 6)
							local bounds = boxAt(rey.x, rey.z)
							assert(bounds.cy - bounds.sy / 2 > 0, "feet stay above the road")
							assert(
								bounds.cy + bounds.sy / 2 < 9,
								"silhouette stays below the lead and gate sightline band"
							)
							local camera = CameraRig.pose(leadX, leadZ, pullback)
							local center =
								ScreenProject.project(camera, 16 / 9, rey.x, bounds.cy, bounds.cz)
							local top = ScreenProject.project(
								camera,
								16 / 9,
								rey.x,
								bounds.cy + bounds.sy / 2,
								bounds.cz
							)
							local bottom = ScreenProject.project(
								camera,
								16 / 9,
								rey.x,
								bounds.cy - bounds.sy / 2,
								bounds.cz
							)
							local left = ScreenProject.project(
								camera,
								16 / 9,
								rey.x - ReyFormation.HALF_WIDTH,
								bounds.cy,
								bounds.cz
							)
							local right = ScreenProject.project(
								camera,
								16 / 9,
								rey.x + ReyFormation.HALF_WIDTH,
								bounds.cy,
								bounds.cz
							)
							assert(
								ScreenProject.onScreen(center, 0.05)
									and ScreenProject.onScreen(left, 0.02)
									and ScreenProject.onScreen(right, 0.02)
									and math.abs(top.y - bottom.y) >= 0.07
									and center.y > -0.55
									and bottom.y > -0.62,
								`seed {seed}: full Rey silhouette clears frame and HUD at x={leadX}, z={leadZ}, pullback={pullback}; ndc=({center.x},{center.y}), height={math.abs(
									top.y - bottom.y
								)}`
							)
							local cam = { camera.px, camera.py, camera.pz }
							local leadTarget = { leadX, CameraRig.LEAD_TOP, leadZ }
							assert(
								not hits(cam, leadTarget, bounds),
								`seed {seed}: Rey does not hide the lead x={leadX}, z={leadZ}, pullback={pullback}`
							)
							for _, gateX in { -10, 10 } do
								local gateTarget = { gateX, 0, leadZ + CameraRig.GATE_NEAR }
								assert(
									not hits(cam, gateTarget, bounds),
									`seed {seed}: Rey does not hide gate at x={gateX}`
								)
							end
							if leadZ == 0 then
								checkedStart = true
							elseif leadZ == DebugLayout.plazaStart then
								checkedPlaza = true
							end
						end
					end
				end
				assert(
					checkedStart and checkedPlaza,
					`seed {seed}: tested the run start and plaza finale`
				)
			end
		end,
	},
}
