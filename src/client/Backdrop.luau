--!strict
-- A plain, low-contrast warm backdrop under and around the street (Mob Control framing note on
-- issue #10: the lane and the numbers must stand out), a short run-in of road behind the start so
-- the high camera never looks at empty space, and warm lighting. The street itself is drawn by
-- WorldBuilder.client. IN-ENGINE BEHAVIOUR IS UNVERIFIED (see the PR checklist).
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DebugLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DebugLayout"))

local GROUND_COLOR = Color3.fromRGB(226, 206, 176)
local ROAD_COLOR = Color3.fromRGB(57, 61, 72) -- same as WorldBuilder's street
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

	Lighting.ClockTime = 15
	Lighting.Ambient = Color3.fromRGB(170, 150, 130)
	Lighting.OutdoorAmbient = Color3.fromRGB(190, 170, 150)
	Lighting.FogColor = GROUND_COLOR
	Lighting.FogStart = 300
	Lighting.FogEnd = 900
end

return Backdrop
