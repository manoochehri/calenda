--!strict
-- Issue #211: the start screen shows no PROTOTIPO label and no avatar box. The street sits behind
-- the title, the lead avatar stands still at its start, and Jugar runs a camera move that orbits
-- the player, zooms out, then glides behind them into the gameplay pose. The countdown waits for it.
local fs = require("@lune/fs")
local CameraRig = require("../src/shared/CameraRig")
local IntroCamera = require("../src/shared/IntroCamera")
local LeadPose = require("../src/shared/LeadPose")
local TitleLayout = require("../src/shared/TitleLayout")

local EPS = 1e-6

local function near(actual: number, expected: number, name: string)
	assert(math.abs(actual - expected) < EPS, `{name}: expected {expected}, got {actual}`)
end

local function distance(p: IntroCamera.Pose): number
	local dx, dy, dz = p.px - p.lx, p.py - p.ly, p.pz - p.lz
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local LEAD_X, LEAD_Z = 0, 0

return {
	{
		name = "the title layout has no PROTOTIPO footer and no avatar box element",
		run = function()
			assert(TitleLayout.element("Version") == nil, "Version (PROTOTIPO) element remains")
			assert(TitleLayout.element("AvatarSlot") == nil, "AvatarSlot box element remains")
		end,
	},
	{
		name = "no PROTOTIPO text in the player-facing start screen code",
		run = function()
			for _, path in { "src/client/StartupScreen.luau", "src/shared/TitleLayout.luau" } do
				local source = fs.readFile(path)
				assert(
					string.find(source, "PROTOTIPO", 1, true) == nil,
					`{path} still shows PROTOTIPO`
				)
			end
		end,
	},
	{
		name = "the title pose is a three-quarter view of the lead, not a close-up or head-on",
		run = function()
			local p = IntroCamera.titlePose(LEAD_X, LEAD_Z)
			near(p.lz, LEAD_Z, "looks at the avatar")
			assert(p.pz - LEAD_Z > 4, "camera stands clear of the avatar")
			assert(p.pz - LEAD_Z < 20, "camera is close enough to frame the avatar")
			assert(p.px ~= LEAD_X, "camera is off-axis for a three-quarter view")
		end,
	},
	{
		name = "the move starts exactly on the title pose (no snap from the title)",
		run = function()
			local start = IntroCamera.pose(LEAD_X, LEAD_Z, 0)
			local title = IntroCamera.titlePose(LEAD_X, LEAD_Z)
			near(start.px, title.px, "px")
			near(start.py, title.py, "py")
			near(start.pz, title.pz, "pz")
			near(start.lx, title.lx, "lx")
			near(start.ly, title.ly, "ly")
			near(start.lz, title.lz, "lz")
		end,
	},
	{
		name = "the move ends exactly on the normal game camera (seamless hand-off)",
		run = function()
			local end_ = IntroCamera.pose(LEAD_X, LEAD_Z, 1)
			local game = CameraRig.pose(LEAD_X, LEAD_Z, 1)
			near(end_.px, game.px, "px")
			near(end_.py, game.py, "py")
			near(end_.pz, game.pz, "pz")
			near(end_.lx, game.lx, "lx")
			near(end_.ly, game.ly, "ly")
			near(end_.lz, game.lz, "lz")
		end,
	},
	{
		name = "the move orbits and zooms out mid-way (the street shows) before settling behind",
		run = function()
			local start = distance(IntroCamera.pose(LEAD_X, LEAD_Z, 0))
			local middle = distance(IntroCamera.pose(LEAD_X, LEAD_Z, 0.5))
			assert(middle > start, "zooms out from the title view")
		end,
	},
	{
		name = "the move takes no sudden jump between frames",
		run = function()
			local prev = IntroCamera.pose(LEAD_X, LEAD_Z, 0)
			for i = 1, 100 do
				local p = IntroCamera.pose(LEAD_X, LEAD_Z, i / 100)
				local step =
					math.sqrt((p.px - prev.px) ^ 2 + (p.py - prev.py) ^ 2 + (p.pz - prev.pz) ^ 2)
				assert(step < 2, `jump of {step} studs at step {i}`)
				prev = p
			end
		end,
	},
	{
		name = "the lead stands still at its start in the title (no bob, no march)",
		run = function()
			local standing = 2.5
			local pose = LeadPose.still(0, 0, standing)
			near(pose.y, standing, "still height")
			near(pose.x, 0, "still x")
			near(pose.z, 0, "still z")
		end,
	},
}
