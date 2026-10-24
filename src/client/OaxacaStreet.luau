--!strict
-- Level 1 Oaxacan street builder (issue #54 phase 1). Turns StreetLayoutGen's pure output into
-- Parts and SurfaceGuis under ONE Model, a few items per frame, so the loading screen (#72) can
-- show progress. NOT wired into Main or WorldBuilder yet (phase 2, after #70 merges).
--
--   OaxacaStreet.build(parent, onProgress) -> Model   (yields; call from a task or Main's start)
--   OaxacaStreet.destroy()                            (cancels a build in flight and removes the model)
--   OaxacaStreet.applyTheme(Lighting)                 (Lighting properties + one Atmosphere)
--
-- Everything is Anchored, CanCollide false, CanQuery false, CanTouch false. Windows, doors, arches,
-- balcony railings and papel picado flags are Frames inside SurfaceGuis (a few GUIs, not a Part per
-- detail): flags are colored Frames on ~44 strip Parts, never one Part per flag. Buildings and
-- balconies have real depth, and Rey is a small primitive-Part chicken. Generator x is
-- WORLD x; ViewMap.x is applied here, to every Part position. Reset-safe: build() destroys the
-- previous model first, and a destroy() during a build stops it at the next batch.
-- IN-ENGINE BEHAVIOUR IS UNVERIFIED (see the PR checklist).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DebugLayout = require(Shared:WaitForChild("DebugLayout"))
local LevelTheme = require(Shared:WaitForChild("LevelTheme"))
local StreetLayoutGen = require(Shared:WaitForChild("StreetLayoutGen"))
local ViewMap = require(Shared:WaitForChild("ViewMap"))

local MODEL_NAME = "OaxacaStreet"
local ATMOSPHERE_NAME = "OaxacaAtmosphere"
local BATCH = 40 -- items per frame
local PPS = 12 -- SurfaceGui pixels per stud on facades
local SEED = 54
local GUI_MAX_DISTANCE = 400 -- studs; the camera sees about 300 ahead, details beyond are cut

local OaxacaStreet = {}

local model: Model? = nil
local token = 0 -- bumped by build/destroy; an older build stops when it sees a newer token

local function color(c: LevelTheme.Rgb): Color3
	return Color3.fromRGB(c.r, c.g, c.b)
end

local function material(name: string): Enum.Material
	local ok, value = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return if ok and value then value else Enum.Material.Concrete
end

local function newPart(
	parent: Instance,
	name: string,
	size: Vector3,
	worldX: number,
	y: number,
	z: number,
	c: Color3,
	mat: Enum.Material,
	castShadow: boolean
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = Vector3.new(ViewMap.x(worldX), y, z)
	part.Color = c
	part.Material = mat
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = castShadow
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function newFrame(
	parent: Instance,
	x: number,
	y: number,
	w: number,
	h: number,
	c: Color3,
	transparency: number?
): Frame
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.Position = UDim2.fromOffset(x, y)
	frame.Size = UDim2.fromOffset(w, h)
	frame.BackgroundColor3 = c
	frame.BackgroundTransparency = transparency or 0
	frame.Parent = parent
	return frame
end

local function stroke(frame: Frame, thickness: number, c: Color3)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = c
	s.Parent = frame
end

local function arch(frame: Frame)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0) -- pill: reads as an arched top at this size
	corner.Parent = frame
end

-- The face of a part that looks at the street centre (the camera is always inside the street).
local function innerFace(viewX: number): Enum.NormalId
	return if viewX < 0 then Enum.NormalId.Right else Enum.NormalId.Left
end

local function surfaceGui(part: Part, face: Enum.NormalId, canvas: Vector2): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Details"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = canvas
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.MaxDistance = GUI_MAX_DISTANCE -- documented SurfaceGui property; UNVERIFIED in engine
	gui.Parent = part
	return gui
end

local function buildFacade(theme: LevelTheme.Theme, root: Model, f: StreetLayoutGen.Facade)
	local wallMat = if f.stone
		then material(theme.materials.stone)
		else material(theme.materials.wall)
	local viewX = ViewMap.x(f.x)
	local toward = if viewX < 0 then 1 else -1
	local wall = newPart(
		root,
		`Facade{f.id}`,
		Vector3.new(f.depth, f.height, f.width),
		f.x,
		f.height / 2,
		f.z,
		color(f.wall),
		wallMat,
		true
	)
	local cornice = newPart(
		root,
		`Cornice{f.id}`,
		Vector3.new(f.depth + 2, theme.heights.roofExtra, f.width + 0.8),
		f.x,
		f.height + theme.heights.roofExtra / 2,
		f.z,
		color(f.trim),
		Enum.Material.Concrete,
		false -- cornices and balconies cast no shadows: about 560 casters is too heavy on a phone
	)
	-- A broad physical roof cap projects toward the street and beyond both side walls.
	cornice.Position += Vector3.new(toward, 0, 0)

	local gui = surfaceGui(wall, innerFace(viewX), Vector2.new(f.width * PPS, f.height * PPS))
	local trim, accent, glass = color(f.trim), color(f.accent), color(theme.palette.glass)
	local function top(
		y: number,
		h: number
	): number -- studs above ground -> pixel y of the top edge
		return (f.height - (y + h / 2)) * PPS
	end
	-- plinth and cornice band
	newFrame(gui, 0, (f.height - 0.8) * PPS, f.width * PPS, 0.8 * PPS, trim, 0)
	newFrame(gui, 0, 0, f.width * PPS, 0.6 * PPS, trim, 0)

	for _, w in f.windows do
		local frame = newFrame(
			gui,
			(w.u * f.width - w.w / 2) * PPS,
			top(w.y, w.h),
			w.w * PPS,
			w.h * PPS,
			glass,
			0
		)
		stroke(frame, if w.grille then 3 else 2, if w.grille then accent else trim)
		if w.arched then
			arch(frame)
		end
	end
	if f.door then
		local d = f.door
		local frame = newFrame(
			gui,
			(d.u * f.width - d.w / 2) * PPS,
			top(d.h / 2, d.h),
			d.w * PPS,
			d.h * PPS,
			accent,
			0
		)
		stroke(frame, 2, trim)
		if d.arched then
			arch(frame)
		end
	end
	for _, a in f.arches do
		local frame = newFrame(
			gui,
			(a.u * f.width - a.w / 2) * PPS,
			top(a.h / 2, a.h),
			a.w * PPS,
			a.h * PPS,
			glass,
			0
		)
		stroke(frame, 3, trim)
		arch(frame)
	end
	for i, b in f.balconies do
		local zOffset = (b.u - 0.5) * f.width
		newPart(
			root,
			`Balcony{f.id}_{i}`,
			Vector3.new(b.depth, 0.5, b.w),
			f.x + (if f.x < 0 then 1 else -1) * (f.depth / 2 + b.depth / 2),
			b.y,
			f.z + zOffset,
			accent,
			Enum.Material.Metal,
			false
		)
		-- Iron railing drawn on the wall above the slab.
		local rail = newFrame(
			gui,
			(b.u * f.width - b.w / 2) * PPS,
			top(b.y + 1.4, 2.4),
			b.w * PPS,
			2.4 * PPS,
			accent,
			1
		)
		stroke(rail, 2, accent)
	end
end

local function buildRey(root: Model, rey: StreetLayoutGen.Rey)
	local white = Color3.fromRGB(250, 242, 226)
	local ochre = Color3.fromRGB(232, 172, 58)
	local beak = Color3.fromRGB(244, 130, 40)
	local comb = Color3.fromRGB(204, 65, 56)
	local dark = Color3.fromRGB(30, 28, 30)
	local function ball(name: string, size: Vector3, x: number, y: number, z: number, c: Color3)
		local part = newPart(root, name, size, x, y, z, c, Enum.Material.SmoothPlastic, true)
		part.Shape = Enum.PartType.Ball
	end
	-- Seven inexpensive 3D Parts: body, head, beak, comb, two eyes and feet.
	ball("ReyBody", Vector3.new(1.5, 1.1, 1.65), rey.x, 0.68, rey.z, white)
	ball("ReyHead", Vector3.new(0.72, 0.72, 0.72), rey.x, 1.28, rey.z + 0.56, ochre)
	ball("ReyBeak", Vector3.new(0.36, 0.26, 0.42), rey.x, 1.2, rey.z + 0.92, beak)
	ball("ReyComb", Vector3.new(0.24, 0.34, 0.22), rey.x, 1.77, rey.z + 0.52, comb)
	ball("ReyLeftEye", Vector3.new(0.12, 0.12, 0.12), rey.x - 0.23, 1.34, rey.z + 0.82, dark)
	ball("ReyRightEye", Vector3.new(0.12, 0.12, 0.12), rey.x + 0.23, 1.34, rey.z + 0.82, dark)
	newPart(
		root,
		"ReyFeet",
		Vector3.new(1, 0.16, 0.22),
		rey.x,
		0.12,
		rey.z + 0.12,
		beak,
		Enum.Material.SmoothPlastic,
		true
	)
end

local function buildFlag(root: Model, s: StreetLayoutGen.FlagStrip)
	local part = newPart(
		root,
		`Flags{s.id}`,
		Vector3.new(0.2, s.height, s.z1 - s.z0),
		s.x,
		s.y,
		(s.z0 + s.z1) / 2,
		color(s.cord),
		Enum.Material.SmoothPlastic,
		false
	)
	part.Transparency = 1 -- the colored Frames are the flags
	local gui =
		surfaceGui(part, innerFace(ViewMap.x(s.x)), Vector2.new(s.canvasWidth, s.canvasHeight))
	local cell = StreetLayoutGen.FLAG_CELL_PX
	newFrame(gui, 0, 0, s.canvasWidth, 5, color(s.cord), 0) -- the cord
	for i, c in s.cells do
		newFrame(gui, (i - 1) * cell + cell * 0.1, 5, cell * 0.8, s.canvasHeight - 5, color(c), 0)
	end
end

local function buildLamp(theme: LevelTheme.Theme, root: Model, l: StreetLayoutGen.Lamp)
	local iron = color(theme.palette.iron)
	newPart(
		root,
		`LampPole{l.id}`,
		Vector3.new(0.6, l.height, 0.6),
		l.x,
		l.height / 2,
		l.z,
		iron,
		Enum.Material.Metal,
		false
	)
	local head = newPart(
		root,
		`LampHead{l.id}`,
		Vector3.new(1.6, 1.8, 1.6),
		l.x,
		l.height + 0.9,
		l.z,
		color(theme.palette.lampGlass),
		Enum.Material.Neon,
		false
	)
	if l.light then
		local light = Instance.new("PointLight")
		light.Color = color(theme.palette.lampLight)
		light.Brightness = 1.2
		light.Range = 24
		light.Shadows = false
		light.Parent = head
	end
end

local function buildPrim(root: Model, p: StreetLayoutGen.Prim, castShadow: boolean)
	local part = newPart(
		root,
		p.name,
		Vector3.new(p.sx, p.sy, p.sz),
		p.cx,
		p.cy,
		p.cz,
		color(p.color),
		material(p.material),
		castShadow
	)
	if p.shape == "ball" then
		part.Shape = Enum.PartType.Ball
	elseif p.shape == "cylinder" then
		part.Shape = Enum.PartType.Cylinder
		-- Roblox cylinders lie along x: size is (length, diameter, diameter), turned upright.
		part.Size = Vector3.new(p.sy, p.sx, p.sz)
		part.CFrame = CFrame.new(ViewMap.x(p.cx), p.cy, p.cz) * CFrame.Angles(0, 0, math.pi / 2)
	end
end

-- Build the street under `parent` (default Workspace). `onProgress(fraction)` is called after each
-- batch (0..1, ending at exactly 1) for the loading screen. Returns the Model, or nil when the
-- build was cancelled by destroy() or a newer build().
function OaxacaStreet.build(
	parent: Instance?,
	onProgress: ((number) -> ())?,
	theme: LevelTheme.Theme?,
	seed: number?
): Model?
	OaxacaStreet.destroy()
	token += 1
	local mine = token
	local useTheme = theme or LevelTheme.level1
	local result = StreetLayoutGen.generate({
		streetLength = DebugLayout.streetLength,
		plazaStart = DebugLayout.plazaStart,
		halfWidth = DebugLayout.halfWidth,
	}, useTheme, seed or SEED)
	local order = StreetLayoutGen.buildOrder(result)

	local root = Instance.new("Model")
	root.Name = MODEL_NAME
	root.Parent = parent or Workspace
	model = root

	for i, item in order do
		if item.kind == "facade" then
			buildFacade(useTheme, root, result.facades[item.index])
		elseif item.kind == "rey" then
			buildRey(root, result.rey)
		elseif item.kind == "flag" then
			buildFlag(root, result.flags[item.index])
		elseif item.kind == "lamp" then
			buildLamp(useTheme, root, result.lamps[item.index])
		elseif item.kind == "ground" then
			buildPrim(root, result.ground[item.index], false)
		else
			local p = result.plaza[item.index]
			buildPrim(root, p, p.group ~= "paving")
		end
		if i % BATCH == 0 or i == #order then
			if onProgress then
				onProgress(i / #order)
			end
			if i < #order then
				task.wait()
				if token ~= mine then
					return nil -- cancelled; destroy() already removed the model
				end
			end
		end
	end
	return root
end

function OaxacaStreet.destroy()
	token += 1
	if model then
		model:Destroy()
		model = nil
	end
	local stale = Workspace:FindFirstChild(MODEL_NAME)
	if stale then
		stale:Destroy()
	end
end

-- Lighting properties only (no Sky, no asset ids). Names checked against the Roblox Creator Docs
-- (Lighting and Atmosphere class pages, 2026-10-24): ClockTime, Brightness, Ambient, OutdoorAmbient,
-- ColorShift_Top, ColorShift_Bottom, EnvironmentDiffuseScale, EnvironmentSpecularScale,
-- GlobalShadows, ShadowSoftness, ExposureCompensation; Atmosphere Density, Offset, Color, Decay,
-- Glare, Haze. UNVERIFIED: that Atmosphere under Lighting renders as intended, and the look.
function OaxacaStreet.applyTheme(lighting: Lighting, theme: LevelTheme.Theme?)
	local t = (theme or LevelTheme.level1).lighting
	lighting.ClockTime = t.clockTime
	lighting.Brightness = t.brightness
	lighting.Ambient = color(t.ambient)
	lighting.OutdoorAmbient = color(t.outdoorAmbient)
	lighting.ColorShift_Top = color(t.colorShiftTop)
	lighting.ColorShift_Bottom = color(t.colorShiftBottom)
	lighting.EnvironmentDiffuseScale = t.environmentDiffuseScale
	lighting.EnvironmentSpecularScale = t.environmentSpecularScale
	lighting.GlobalShadows = true
	lighting.ShadowSoftness = t.shadowSoftness
	lighting.ExposureCompensation = t.exposureCompensation
	local existing = lighting:FindFirstChild(ATMOSPHERE_NAME)
	local a: Atmosphere
	if existing and existing:IsA("Atmosphere") then
		a = existing
	else
		a = Instance.new("Atmosphere")
		a.Name = ATMOSPHERE_NAME
		a.Parent = lighting
	end
	a.Density = t.atmosphere.density
	a.Offset = t.atmosphere.offset
	a.Color = color(t.atmosphere.color)
	a.Decay = color(t.atmosphere.decay)
	a.Glare = t.atmosphere.glare
	a.Haze = t.atmosphere.haze
end

return OaxacaStreet
