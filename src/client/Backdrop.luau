--!strict
-- A warm, contrasting backdrop, a restrained run of painted facades and papel picado, and a short
-- road run-in behind the start so the high camera never looks at empty space. The street itself is
-- drawn by WorldBuilder.client. IN-ENGINE BEHAVIOUR IS UNVERIFIED (see the PR checklist).
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DebugLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DebugLayout"))
local StreetTheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StreetTheme"))

local GROUND_COLOR = Color3.fromRGB(
	StreetTheme.palette.ground[1],
	StreetTheme.palette.ground[2],
	StreetTheme.palette.ground[3]
)
local ROAD_COLOR = Color3.fromRGB(
	StreetTheme.palette.road[1],
	StreetTheme.palette.road[2],
	StreetTheme.palette.road[3]
) -- same as WorldBuilder's street
local RUN_IN = 80 -- [default] studs of road behind the start line

local Backdrop = {}

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

local function themeColor(rgb: StreetTheme.RGB): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function decoration(
	parent: Instance,
	name: string,
	size: Vector3,
	position: Vector3,
	partColor: Color3
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Position = position
	p.Color = partColor
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function addFacades(parent: Instance)
	-- A small number of chunky painted fronts give the street a place identity without
	-- filling the frame with fine detail or adding collisions.
	local rows = { 220, 548, 876, 1204 }
	for row, z in rows do
		local height = 13 + (row % 3) * 1.5
		for _, side in { -1, 1 } do
			local centerX = side * (DebugLayout.halfWidth + 5.5)
			local insideX = centerX - side * 1.06
			local facadeColor = themeColor(
				StreetTheme.palette.facades[(row + side + 10) % #StreetTheme.palette.facades + 1]
			)
			decoration(
				parent,
				`Facade{row}{side}`,
				Vector3.new(2, height, 48),
				Vector3.new(centerX, height / 2, z),
				facadeColor
			)
			for windowIndex, dz in { -10, 10 } do
				decoration(
					parent,
					`Window{row}{side}{windowIndex}`,
					Vector3.new(0.12, 2.1, 3.2),
					Vector3.new(insideX, height * 0.64, z + dz),
					themeColor(StreetTheme.palette.window)
				)
			end
			decoration(
				parent,
				`Door{row}{side}`,
				Vector3.new(0.12, 4.2, 3.6),
				Vector3.new(insideX, 2.1, z),
				themeColor(StreetTheme.palette.window)
			)
		end
	end
end

local function addPapelPicado(parent: Instance)
	-- Six light overhead strings echo the colorful street references. Each string and its five
	-- broad paper panels are static, non-colliding primitives; there are no per-frame effects.
	local rows = { 96, 256, 416, 624, 832, 1040 }
	for rowIndex, z in rows do
		local cord = decoration(
			parent,
			`PapelPicadoCord{rowIndex}`,
			Vector3.new(24, 0.12, 0.12),
			Vector3.new(0, 27, z),
			themeColor(StreetTheme.palette.ink)
		)
		cord.Material = Enum.Material.SmoothPlastic
		for flagIndex = -2, 2 do
			local paletteIndex = (rowIndex + flagIndex + #StreetTheme.palette.bunting)
					% #StreetTheme.palette.bunting
				+ 1
			decoration(
				parent,
				`PapelPicado{rowIndex}Flag{flagIndex + 3}`,
				Vector3.new(4.2, 1.8, 0.12),
				Vector3.new(flagIndex * 4.8, 25.9, z),
				themeColor(StreetTheme.palette.bunting[paletteIndex])
			)
		end
	end
end

function Backdrop.build()
	local folder = Instance.new("Folder")
	folder.Name = "CalendaBackdrop"
	folder.Parent = Workspace

	local length = DebugLayout.streetLength
	-- Top of the plate is just below the street slabs (their bottom is y = -1).
	slab(
		folder,
		"Ground",
		Vector3.new(3000, 1, length + 3000),
		Vector3.new(0, -1.6, length / 2),
		GROUND_COLOR
	)
	slab(
		folder,
		"RunIn",
		Vector3.new((DebugLayout.halfWidth - 6) * 2, 1, RUN_IN),
		Vector3.new(0, -0.5, -RUN_IN / 2),
		ROAD_COLOR
	)
	addFacades(folder)
	addPapelPicado(folder)

	Lighting.ClockTime = 15
	Lighting.Ambient = Color3.fromRGB(195, 160, 125)
	Lighting.OutdoorAmbient = Color3.fromRGB(215, 181, 143)
	Lighting.FogColor = GROUND_COLOR
	Lighting.FogStart = 300
	Lighting.FogEnd = 900
end

return Backdrop
