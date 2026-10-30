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
local LayerHeights = require(Shared:WaitForChild("LayerHeights"))
local LevelTheme = require(Shared:WaitForChild("LevelTheme"))
local StreetSurface = require(Shared:WaitForChild("StreetSurface"))
local OaxacaStreet = require(script.Parent:WaitForChild("OaxacaStreet"))

local FOLDER_NAME = "CalendaBackdrop"
local RUN_IN = 80 -- [default] studs of road behind the start line
local SCENERY_ROWS = 9
local HILL_ROWS = 5

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

local function sceneryPart(
	parent: Instance,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	position: Vector3,
	color: Color3
)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Position = position
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Parent = parent
end

-- Low-detail hills and tree silhouettes fill the large ground plate beyond the street walls.
-- The fixed row pattern is reset-safe, symmetrical, and adds 64 non-interactive parts total.
local function buildScenery(parent: Instance, length: number)
	local earth = LayerHeights.EARTH
	local trees = {
		Color3.fromRGB(91, 119, 96),
		Color3.fromRGB(103, 127, 102),
		Color3.fromRGB(111, 130, 105),
	}
	local trunks = Color3.fromRGB(112, 92, 69)
	local hills = {
		Color3.fromRGB(139, 143, 122),
		Color3.fromRGB(151, 148, 125),
	}

	for row = 0, SCENERY_ROWS - 1 do
		local z = -80 + row * (length + 160) / (SCENERY_ROWS - 1)
		local scale = 0.68 + (row % 4) * 0.08
		local x = 74 + (row % 3) * 12
		local trunkHeight = 5 * scale
		for _, side in { -1, 1 } do
			local centerX = side * x
			sceneryPart(
				parent,
				`TreeTrunk{row}_{side}`,
				Enum.PartType.Block,
				Vector3.new(1.1 * scale, trunkHeight, 1.1 * scale),
				Vector3.new(centerX, earth + trunkHeight / 2, z),
				trunks
			)
			sceneryPart(
				parent,
				`TreeCrownLower{row}_{side}`,
				Enum.PartType.Ball,
				Vector3.new(9 * scale, 8 * scale, 9 * scale),
				Vector3.new(centerX, earth + trunkHeight + 2.7 * scale, z),
				trees[row % #trees + 1]
			)
			sceneryPart(
				parent,
				`TreeCrownUpper{row}_{side}`,
				Enum.PartType.Ball,
				Vector3.new(6.5 * scale, 7 * scale, 6.5 * scale),
				Vector3.new(centerX, earth + trunkHeight + 7.6 * scale, z),
				trees[(row + 1) % #trees + 1]
			)
		end
	end

	for row = 0, HILL_ROWS - 1 do
		local z = -150 + row * (length + 300) / (HILL_ROWS - 1)
		for _, side in { -1, 1 } do
			sceneryPart(
				parent,
				`Hillside{row}_{side}`,
				Enum.PartType.Ball,
				Vector3.new(340, 42, 560),
				Vector3.new(side * 230, earth + 9, z),
				hills[row % #hills + 1]
			)
		end
	end
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
	-- The plate covers every ground point the high camera can see (StreetSurface, issue #54).
	local plate = StreetSurface.groundPlate(length)
	slab(
		folder,
		"Ground",
		Vector3.new(plate.x1 - plate.x0, 1, plate.z1 - plate.z0),
		Vector3.new((plate.x0 + plate.x1) / 2, LayerHeights.EARTH - 0.5, (plate.z0 + plate.z1) / 2),
		toColor(palette.ground)
	)
	slab(
		folder,
		"RunIn",
		Vector3.new(StreetSurface.roadHalfWidth(DebugLayout.halfWidth) * 2, 1, RUN_IN),
		Vector3.new(0, LayerHeights.ROAD_BASE - 0.5, -RUN_IN / 2),
		toColor(palette.road)
	)
	buildScenery(folder, length)

	OaxacaStreet.applyTheme(Lighting)
	Lighting.FogColor = toColor(LevelTheme.level1.lighting.atmosphere.color)
	Lighting.FogStart = 500
	Lighting.FogEnd = 2200

	-- Several frames, off the caller's thread: Main keeps starting while the street appears.
	task.spawn(OaxacaStreet.build, Workspace, onProgress)
end

return Backdrop
