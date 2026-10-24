--!strict
-- Client-only presentation for the fixed debug layout (issue #11).
-- Gameplay stays server-owned; this script only draws the authored course. The standing gate
-- portals and their labels live in GateView (issue #70).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local DebugLayout = require(Shared:WaitForChild("DebugLayout"))
local LevelTheme = require(Shared:WaitForChild("LevelTheme"))
local ViewMap = require(Shared:WaitForChild("ViewMap"))
local GateView = require(script.Parent:WaitForChild("GateView"))

local WORLD_NAME = "CalendaWorld"
local ROAD_HALF_WIDTH = DebugLayout.halfWidth - 6
local SIDEWALK_WIDTH = 6

local function makePart(
	parent: Instance,
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3,
	material: Enum.Material,
	canCollide: boolean?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = canCollide == true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function addTextLabel(
	parent: Instance,
	name: string,
	position: UDim2,
	size: UDim2,
	text: string,
	font: Enum.Font
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = position
	label.Size = size
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeColor3 = Color3.fromRGB(24, 22, 30)
	label.TextStrokeTransparency = 0.1
	label.TextScaled = true
	label.TextWrapped = true
	label.Font = font
	label.Parent = parent
	return label
end

local function addSurfaceText(
	part: Part,
	face: Enum.NormalId,
	text: string,
	canvas: Vector2
): TextLabel
	local surface = Instance.new("SurfaceGui")
	surface.Name = "ReadableText"
	surface.Face = face
	surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	surface.CanvasSize = canvas
	surface.AlwaysOnTop = true
	surface.LightInfluence = 0
	surface.Parent = part
	return addTextLabel(
		surface,
		"Label",
		UDim2.fromScale(0, 0),
		UDim2.fromScale(1, 1),
		text,
		Enum.Font.GothamBlack
	)
end

local function addGround(
	parent: Instance,
	name: string,
	x: number,
	z0: number,
	z1: number,
	width: number,
	color: Color3
)
	makePart(
		parent,
		name,
		Vector3.new(width, 1, z1 - z0),
		Vector3.new(ViewMap.x(x), -0.5, (z0 + z1) / 2),
		color,
		Enum.Material.Concrete,
		true
	)
end

local function addCone(parent: Instance, name: string, x: number, z: number)
	local function cylinder(
		layer: string,
		y: number,
		height: number,
		diameter: number,
		color: Color3
	)
		local part = Instance.new("Part")
		part.Name = `{name}{layer}`
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(height, diameter, diameter)
		part.CFrame = CFrame.new(ViewMap.x(x), y, z) * CFrame.Angles(0, 0, math.pi / 2)
		part.Color = color
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = true
		part.CanCollide = false
		part.Parent = parent
	end

	-- Three shrinking primitive cylinders read as a friendly striped traffic cone.
	cylinder("Base", 0.12, 0.2, 0.9, Color3.fromRGB(245, 111, 38))
	cylinder("Body", 0.4, 0.36, 0.56, Color3.fromRGB(255, 130, 45))
	cylinder("Stripe", 0.43, 0.08, 0.6, Color3.fromRGB(255, 245, 225))
	cylinder("Tip", 0.68, 0.2, 0.28, Color3.fromRGB(255, 130, 45))
end

local function addObstacle(parent: Instance, obstacleId: number, side: "left" | "right", z: number)
	local signX = if side == "left"
		then -DebugLayout.halfWidth * 0.85
		else DebugLayout.halfWidth * 0.85
	local board = makePart(
		parent,
		`Obstacle{obstacleId}Sign`,
		Vector3.new(5, 2.6, 0.3),
		Vector3.new(ViewMap.x(signX), 2.7, z - 4),
		Color3.fromRGB(191, 47, 57),
		Enum.Material.SmoothPlastic
	)
	addSurfaceText(
		board,
		Enum.NormalId.Front,
		`-{Config.obstacleLoss}\nCALLE CERRADA`,
		Vector2.new(600, 300)
	)

	local startX = if side == "left" then -DebugLayout.halfWidth + 2 else 2
	local endX = if side == "left" then -2 else DebugLayout.halfWidth - 2
	for index = 0, 4 do
		local x = startX + (endX - startX) * index / 4
		addCone(parent, `Obstacle{obstacleId}Cone{index + 1}`, x, z)
	end
end

local function buildWorld()
	local oldWorld = Workspace:FindFirstChild(WORLD_NAME)
	if oldWorld then
		oldWorld:Destroy()
	end

	local world = Instance.new("Model")
	world.Name = WORLD_NAME
	world.Parent = Workspace

	-- Colors come from the level theme (issue #54); OaxacaStreet lays the flagstone courses and
	-- the curb stripe over the road.
	local palette = LevelTheme.level1.palette
	local function toColor(c: LevelTheme.Rgb): Color3
		return Color3.fromRGB(c.r, c.g, c.b)
	end
	local roadColor = toColor(palette.road)
	local sidewalkColor = toColor(palette.sidewalk)
	local plazaColor = toColor(palette.plazaPaving)
	local streetEnd = DebugLayout.plazaStart
	local sidewalkCenter = ROAD_HALF_WIDTH + SIDEWALK_WIDTH / 2

	addGround(world, "Street", 0, 0, streetEnd, ROAD_HALF_WIDTH * 2, roadColor)
	addGround(world, "LeftSidewalk", -sidewalkCenter, 0, streetEnd, SIDEWALK_WIDTH, sidewalkColor)
	addGround(world, "RightSidewalk", sidewalkCenter, 0, streetEnd, SIDEWALK_WIDTH, sidewalkColor)
	addGround(
		world,
		"Plaza",
		0,
		streetEnd,
		DebugLayout.streetLength,
		DebugLayout.halfWidth * 2,
		plazaColor
	)

	-- Dashed road centerline keeps the forward route readable without competing with gate text.
	for z = 48, streetEnd - 48, 96 do
		makePart(
			world,
			`RoadMark{z}`,
			Vector3.new(0.45, 0.03, 24),
			Vector3.new(0, 0.02, z),
			Color3.fromRGB(225, 215, 185),
			Enum.Material.SmoothPlastic
		)
	end

	-- Standing gate portals (issue #70): drawn, animated and fed by the server Event in GateView.
	GateView.new(world, DebugLayout)

	for _, obstacle in DebugLayout.obstacles do
		addObstacle(world, obstacle.id, obstacle.side, obstacle.z)
	end
end

buildWorld()
