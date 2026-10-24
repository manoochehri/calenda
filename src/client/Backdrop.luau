--!strict
-- The earth plate under and around the street (Mob Control framing note on issue #10: the lane and
-- the numbers must stand out), a short run-in of road behind the start so the high camera never
-- looks at empty space, the Level 1 Oaxacan lighting, and the Oaxacan street dressing (issue #54,
-- OaxacaStreet: facades, papel picado, farol lamps, zocalo), built over several frames. The street
-- itself is drawn by WorldBuilder.client. build() is reset-safe: calling it again replaces
-- everything. IN-ENGINE BEHAVIOUR IS UNVERIFIED (see the PR checklist).
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DebugLayout = require(Shared:WaitForChild("DebugLayout"))
local LevelTheme = require(Shared:WaitForChild("LevelTheme"))
local OaxacaStreet = require(script.Parent:WaitForChild("OaxacaStreet"))

local FOLDER_NAME = "CalendaBackdrop"
local RUN_IN = 80 -- [default] studs of road behind the start line

local Backdrop = {}

local function toColor(c: LevelTheme.Rgb): Color3
	return Color3.fromRGB(c.r, c.g, c.b)
end

local function slab(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Position = position
	p.Color = color
	p.Material = Enum.Material.Concrete
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Parent = parent
end

-- `onProgress(fraction)` reports the street dressing (0..1) for the loading screen (#72).
function Backdrop.build(onProgress: ((number) -> ())?)
	local old = Workspace:FindFirstChild(FOLDER_NAME)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = Workspace

	local palette = LevelTheme.level1.palette
	local length = DebugLayout.streetLength
	-- Top of the plate is just below the street slabs (their bottom is y = -1).
	slab(
		folder,
		"Ground",
		Vector3.new(3000, 1, length + 3000),
		Vector3.new(0, -1.6, length / 2),
		toColor(palette.ground)
	)
	slab(
		folder,
		"RunIn",
		Vector3.new((DebugLayout.halfWidth - 6) * 2, 1, RUN_IN),
		Vector3.new(0, -0.5, -RUN_IN / 2),
		toColor(palette.road)
	)

	OaxacaStreet.applyTheme(Lighting)
	Lighting.FogColor = toColor(LevelTheme.level1.lighting.atmosphere.color)
	Lighting.FogStart = 500
	Lighting.FogEnd = 2200

	-- Several frames, off the caller's thread: Main keeps starting while the street appears.
	task.spawn(OaxacaStreet.build, Workspace, onProgress)
end

return Backdrop
