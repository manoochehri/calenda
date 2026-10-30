--!strict
-- Issue #193: the visible lanes on the street (owner report: "there's no lanes like in mob
-- control"). Draws what LaneMarkings describes: two solid divider lines, a row of forward arrows
-- on each lane centre, and a two-bar bracket under the lead that snaps to the lead's lane. Flat
-- Parts, CastShadow = false (issue #171), each at a named LayerHeights layer so none sits coplanar
-- with the road (issue #85); an arrow's Parts never overlap each other (LaneMarkings.arrowParts).
-- Everything is static colour: nothing here pulses or changes brightness (issues #85, #171); the
-- bracket only moves when the lead changes lane or moves along the street.
-- IN-ENGINE LOOK IS UNVERIFIED (see the PR checklist). Presentation only: no authority.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LaneMarkings = require(Shared:WaitForChild("LaneMarkings"))
local ViewMap = require(Shared:WaitForChild("ViewMap"))

local LaneView = {}
LaneView.__index = LaneView

local LINE_COLOR = Color3.fromRGB(240, 236, 220) -- pale paint, readable on the road
local LEAD_COLOR = Color3.fromRGB(255, 196, 40) -- the lead's bracket: bright, but fixed
local MARK_THICKNESS = 0.2 -- [default] studs; the Part sits with its top at the named layer

local function flat(parent: Instance, name: string, sx: number, sz: number, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(sx, MARK_THICKNESS, sz)
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false -- issue #171
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function place(p: Part, x: number, z: number, top: number, yawDegrees: number)
	p.CFrame = CFrame.new(ViewMap.x(x), top - MARK_THICKNESS / 2, z)
		* CFrame.Angles(0, math.rad(yawDegrees), 0)
end

-- A forward arrow, one Part per LaneMarkings.arrowParts entry (no two overlap).
local function buildArrow(parent: Instance, s: LaneMarkings.Spec)
	for _, part in LaneMarkings.arrowParts(s) do
		local p = flat(parent, part.name, part.sx, part.sz, LINE_COLOR)
		-- Mirror-safe: the barb leans outward on screen whichever way ViewMap flips x.
		place(p, part.x, part.z, part.top, -45 * ViewMap.x(part.side))
	end
end

export type LaneView = typeof(setmetatable(
	{} :: { model: Model, bars: { Part }, lastCentre: number?, lastZ: number? },
	LaneView
))

function LaneView.new(layout: LaneMarkings.LayoutInfo): LaneView
	local model = Instance.new("Model")
	model.Name = "LaneMarkings"
	for _, s in LaneMarkings.specs(layout) do
		if s.kind == "divider" then
			place(flat(model, s.name, s.sx, s.sz, LINE_COLOR), s.x, s.z, s.top, 0)
		else
			buildArrow(model, s)
		end
	end
	local bars: { Part } = {}
	for i = 1, 2 do
		-- Size is fixed for the bracket's life: only the bar's position ever changes.
		local bar = flat(model, `LeadLaneBar{i}`, 1, LaneMarkings.BRACKET_BAR_DEPTH, LEAD_COLOR)
		bar.Size =
			Vector3.new(LaneMarkings.bracketWidth(), MARK_THICKNESS, LaneMarkings.BRACKET_BAR_DEPTH)
		table.insert(bars, bar)
	end
	model.Parent = Workspace
	local self = setmetatable({ model = model, bars = bars }, LaneView)
	self:update(0, 0)
	return self
end

-- Move the lead bracket to the lead's lane and street position. Called every frame; it returns
-- before allocating or writing when neither the lane centre nor z changed (the Hud guard rule,
-- issue #196), and writes only the CFrame that changed.
function LaneView.update(self: LaneView, x: number, z: number)
	local centre = LaneMarkings.leadCentre(x)
	local centreSame = centre == self.lastCentre
	local zSame = z == self.lastZ
	if centreSame and zSame then
		return
	end
	self.lastCentre = centre
	self.lastZ = z
	local h = LaneMarkings.BRACKET_HALF_LENGTH
	local top = LaneMarkings.BRACKET_TOP
	place(self.bars[1], centre, z + h, top, 0)
	place(self.bars[2], centre, z - h, top, 0)
end

function LaneView.destroy(self: LaneView)
	self.model:Destroy()
end

return LaneView
