--!strict
local CameraRig = require("../src/shared/CameraRig")
local Config = require("../src/shared/Config")
local FollowerSlots = require("../src/shared/FollowerSlots")
local ScreenProject = require("../src/shared/ScreenProject")
local SectionScale = require("../src/shared/SectionScale")
local ViewMap = require("../src/shared/ViewMap")

local MARGIN = 0.04
local ASPECTS = { 16 / 9, 4 / 3 } -- landscape and tablet; portrait phones are on the Studio checklist
local PULLBACKS = { 1, 1.1, 1.2, 1.3, 1.4 }
local TYPES = { "puppet", "globo", "dancers" }

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

-- Projects a world offset (lead at leadX, leadZ) at height y through the real camera pose.
local function shot(
	leadX: number,
	dx: number,
	dz: number,
	y: number,
	pullback: number,
	aspect: number
)
	local leadZ = 400
	local pose = CameraRig.pose(ViewMap.x(leadX), leadZ, pullback)
	return ScreenProject.project(pose, aspect, ViewMap.x(leadX + dx), y, leadZ + dz)
end

return {
	{
		name = "ScreenProject: the look-at point is the screen centre and a point behind the camera is off",
		run = function()
			local pose = CameraRig.pose(0, 100, 1)
			local c = ScreenProject.project(pose, 16 / 9, pose.lx, pose.ly, pose.lz)
			assert(math.abs(c.x) < 1e-6 and math.abs(c.y) < 1e-6, "centre")
			local behind = ScreenProject.project(pose, 16 / 9, 0, 1, pose.pz - 10)
			assert(not ScreenProject.onScreen(behind, 0), "behind the camera")
			local right = ScreenProject.project(pose, 16 / 9, 5, 0, pose.lz)
			assert(
				right.x < 0,
				"world +x is screen-left in this pose: why ViewMap.x mirrors every client x"
			)
		end,
	},
	{
		name = "every section figure is fully on screen (base and top) at pullback 1.0 to 1.4",
		run = function()
			for _, aspect in ASPECTS do
				for _, pullback in PULLBACKS do
					for i = 1, Config.visualBudget.sectionRepresentatives do
						local base = FollowerSlots.base(i)
						local t = TYPES[(i - 1) % 3 + 1]
						local top = SectionScale.heightOf(t, i)
						for _, leadX in { -8, 0, 8 } do
							for _, y in { 0, top } do
								local ndc = shot(leadX, base.dx, base.dz, y, pullback, aspect)
								assert(
									ScreenProject.onScreen(ndc, MARGIN),
									`section {i} ({t}) y={y} off screen at pullback {pullback} aspect {aspect} leadX {leadX}: x={ndc.x} y={ndc.y}`
								)
							end
						end
					end
				end
			end
		end,
	},
	{
		name = "every loose follower slot is on screen (feet and head) at pullback 1.0 to 1.4",
		run = function()
			for _, aspect in ASPECTS do
				for _, pullback in PULLBACKS do
					for k = 1, FollowerSlots.capacity() do
						local s = FollowerSlots.slot(k)
						for _, y in { 0, 3 } do
							local ndc = shot(0, s.dx, s.dz, y, pullback, aspect)
							assert(
								ScreenProject.onScreen(ndc, MARGIN),
								`slot {k} y={y} off screen at pullback {pullback} aspect {aspect}: x={ndc.x} y={ndc.y}`
							)
						end
					end
				end
			end
		end,
	},
	{
		name = "puppets and globos tower over the crowd; the camera clears the tallest figure",
		run = function()
			for i = 1, 6 do
				for _, t in { "puppet", "globo" } do
					assert(
						SectionScale.heightOf(t, i) >= 15,
						`{t} {i} must stand 15+ studs over 2-stud followers`
					)
				end
			end
			assert(
				SectionScale.heightOf("puppet", 1) / 11 >= 1.5,
				"puppet at least 1.5x its old height"
			)
			assert(
				SectionScale.tallest() <= CameraRig.TALLEST_PROP,
				`TALLEST_PROP {CameraRig.TALLEST_PROP} must cover {SectionScale.tallest()}`
			)
		end,
	},
	{
		name = "tall figures never hide the next gate row or the lead (camera rule, every base)",
		run = function()
			local tallest = SectionScale.tallest()
			for _, pullback in PULLBACKS do
				local pose = CameraRig.pose(0, 0, pullback, tallest)
				assert(
					CameraRig.gateClearance(pose, 0, CameraRig.PROP_FRONT, tallest)
						>= CameraRig.CLEARANCE - 1e-9,
					`gate row hidden at pullback {pullback}`
				)
				for i = 1, 6 do
					local b = FollowerSlots.base(i)
					assert(
						CameraRig.leadClearance(pose, 0, b.dz, tallest) >= 0,
						`lead hidden by base {i}`
					)
					assert(
						CameraRig.gateClearance(pose, 0, b.dz, tallest) >= CameraRig.CLEARANCE,
						`gate hidden by base {i}`
					)
				end
				assert(CameraRig.leadInFrame(pose, 0), "lead in frame")
			end
		end,
	},
	{
		name = "figure sizes vary per index, stably, within the variation band",
		run = function()
			local seen = {}
			for i = 1, 6 do
				local a, b = SectionScale.scaleOf("puppet", i), SectionScale.scaleOf("puppet", i)
				eq(a, b, "stable")
				local k = SectionScale.TYPE_SCALE.puppet
				assert(
					a >= k * (1 - SectionScale.VARIATION) - 1e-9
						and a <= k * (1 + SectionScale.VARIATION) + 1e-9,
					"band"
				)
				seen[string.format("%.4f", a)] = true
			end
			local n = 0
			for _ in seen do
				n += 1
			end
			assert(n >= 4, "sizes differ between figures")
			assert(not pcall(SectionScale.scaleOf, "tuba", 1), "unknown type")
		end,
	},
}
