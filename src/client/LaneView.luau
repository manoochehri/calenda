--!strict
-- Issue #193: the visible lanes on the street (owner report: "there's no lanes like in mob
-- control"). Draws what LaneMarkings describes: two solid divider lines, a row of forward arrows
-- on each lane centre, and a two-bar bracket under the lead that snaps to the lead's lane. Flat
-- Parts, CastShadow = false (issue #171), each at a named LayerHeights layer so none sits coplanar
-- with the road (issue #85). Everything is static colour: nothing here pulses or changes
-- brightness (issues #85, #171); the bracket only moves when the lead does.
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
local BARB_LENGTH = 3 -- [default] studs
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

-- A forward arrow: a shaft along the street and two barbs sweeping back from the tip.
local function buildArrow(parent: Instance, s: LaneMarkings.Spec)
	local len, half = s.sz, s.sz / 2
	local shaft = flat(parent, s.name, 0.6, len, LINE_COLOR)
	place(shaft, s.x, s.z, s.top, 0)
	for _, dx in { -1, 1 } do
		local barb = flat(parent, `{s.name}_Barb`, 0.6, BARB_LENGTH, LINE_COLOR)
		local viewSide = ViewMap.x(dx) -- mirror-safe: the barb leans outward on screen
		local c = BARB_LENGTH / 2 / math.sqrt(2)
		barb.CFrame = CFrame.new(
			ViewMap.x(s.x) + viewSide * c,
			s.top - MARK_THICKNESS / 2,
			s.z + half - c
		) * CFrame.Angles(0, math.rad(-45 * viewSide), 0)
	end
end

export type LaneView = typeof(setmetatable({} :: { model: Model, bars: { Part } }, LaneView))

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
		local bar = flat(model, `LeadLaneBar{i}`, 1, 1, LEAD_COLOR)
		table.insert(bars, bar)
	end
	model.Parent = Workspace
	local self = setmetatable({ model = model, bars = bars }, LaneView)
	self:update(0, 0)
	return self
end

-- Move the lead bracket to the lead's lane and street position. Called every frame; cheap.
function LaneView.update(self: LaneView, x: number, z: number)
	local specs = LaneMarkings.leadBracket(x, z)
	for i, bar in self.bars do
		local b = specs[i]
		bar.Size = Vector3.new(b.sx, MARK_THICKNESS, b.sz)
		place(bar, b.x, b.z, b.top, 0)
	end
end

function LaneView.destroy(self: LaneView)
	self.model:Destroy()
end

return LaneView
