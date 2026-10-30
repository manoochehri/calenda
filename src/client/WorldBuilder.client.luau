--!strict
-- Client-only presentation for the fixed debug layout (issue #11).
-- Gameplay stays server-owned; this script only draws the authored course. The standing gate
-- portals and their labels live in GateView (issue #70). Startup timing (issue #73) is opt-in
-- and costs nothing when Config.debug.startupTiming is false.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StartupTrace = require(script.Parent:WaitForChild("StartupTrace"))
local trace = StartupTrace.trace
local TIMING = StartupTrace.enabled -- evaluated once; every mark below is skipped when false
if TIMING then
	trace:mark("WorldBuilder.client script start")
end
local timedRequire = StartupTrace.timedRequire

local Config = StartupTrace.Config
local DebugLayout = timedRequire("Shared", Shared, "DebugLayout")
local LayerHeights = timedRequire("Shared", Shared, "LayerHeights")
local StreetSurface = timedRequire("Shared", Shared, "StreetSurface")
local LevelTheme = timedRequire("Shared", Shared, "LevelTheme")
local ViewMap = timedRequire("Shared", Shared, "ViewMap")
local StrayBaseplate = timedRequire("Shared", Shared, "StrayBaseplate")
local GateView = timedRequire("Client", script.Parent, "GateView")

local WORLD_NAME = "CalendaWorld"
local ROAD_HALF_WIDTH = StreetSurface.roadHalfWidth(DebugLayout.halfWidth)
local SIDEWALK_WIDTH = StreetSurface.sidewalkWidth(DebugLayout.halfWidth)

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

-- Issue #171: flat ground-layer Parts do not cast shadows. A flat caster lies on the same plane as
-- the surface it shades, so the shadow map fights that surface and the road shimmers as the
-- camera moves. Every other flat ground part in the client opts out the same way.
local function addGround(
	parent: Instance,
	name: string,
	x: number,
	z0: number,
	z1: number,
	width: number,
	color: Color3,
	top: number? -- LayerHeights.GROUND unless given
)
	local part = makePart(
		parent,
		name,
		Vector3.new(width, 1, z1 - z0),
		Vector3.new(ViewMap.x(x), (top or LayerHeights.GROUND) - 0.5, (z0 + z1) / 2),
		color,
		Enum.Material.Concrete,
		true
	)
	part.CastShadow = false
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
	-- Flat cone feet sit on the DECAL layer (issue #85 z-fight audit); the cone stacks above it.
	local lift = LayerHeights.DECAL - 0.22
	cylinder("Base", 0.12 + lift, 0.2, 0.9, Color3.fromRGB(245, 111, 38))
	cylinder("Body", 0.4 + lift, 0.36, 0.56, Color3.fromRGB(255, 130, 45))
	cylinder("Stripe", 0.43 + lift, 0.08, 0.6, Color3.fromRGB(255, 245, 225))
	cylinder("Tip", 0.68 + lift, 0.2, 0.28, Color3.fromRGB(255, 130, 45))
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
	-- Issue #85: a template Baseplate at top 0 z-fights the street and ground (the checkerboard).
	for _, child in Workspace:GetChildren() do
		if StrayBaseplate.isStray(child.Name, child.ClassName) then
			child:Destroy()
		end
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
	local streetStart = DebugLayout.startPlazaEnd
	local sidewalkCenter = ROAD_HALF_WIDTH + SIDEWALK_WIDTH / 2

	-- The run begins in its own broad plaza. The route then narrows into the street and ends in
	-- the existing finale plaza; both transitions are crossed on foot at the same fixed pace.
	addGround(world, "StartingPlaza", 0, 0, streetStart, DebugLayout.halfWidth * 3, plazaColor)
	-- The road sits one kerb (0.2) below the sidewalks; OaxacaStreet lays flagstone courses on it.
	addGround(
		world,
		"Street",
		0,
		streetStart,
		streetEnd,
		ROAD_HALF_WIDTH * 2,
		roadColor,
		LayerHeights.ROAD_BASE
	)
	addGround(
		world,
		"LeftSidewalk",
		-sidewalkCenter,
		streetStart,
		streetEnd,
		SIDEWALK_WIDTH,
		sidewalkColor
	)
	addGround(
		world,
		"RightSidewalk",
		sidewalkCenter,
		streetStart,
		streetEnd,
		SIDEWALK_WIDTH,
		sidewalkColor
	)
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
		local mark = makePart(
			world,
			`RoadMark{z}`,
			Vector3.new(0.45, 0.2, 24),
			Vector3.new(0, LayerHeights.MARKING - 0.1, z),
			Color3.fromRGB(225, 215, 185),
			Enum.Material.SmoothPlastic
		)
		mark.CastShadow = false -- issue #171: a flat road marking casts no shadow
	end

	-- Standing gate portals (issue #70): drawn, animated and fed by the server Event in GateView.
	local gateStartedAt = trace:begin()
	GateView.new(world, DebugLayout)
	trace:span("GateView.new", gateStartedAt)

	for _, obstacle in DebugLayout.obstacles do
		addObstacle(world, obstacle.id, obstacle.side, obstacle.z)
	end
end

if TIMING then
	local builtAt = trace:begin()
	local ok, err = pcall(buildWorld)
	trace:span("WorldBuilder.buildWorld", builtAt)
	if ok then
		trace:mark("WorldBuilder built")
		StartupTrace.finishIfReady()
	else
		trace:mark("WorldBuilder FAILED")
		trace:finish("WorldBuilder error")
		error(err, 0)
	end
else
	buildWorld()
end
