--!strict
-- The lead musician and the pooled follower avatars (issue #13), drawn from primitive Parts.
-- Where each avatar stands comes from the pure Formation module; how many are drawn comes from
-- the visual budget through VisualBudget. The exact count is shown by the HUD, not by this view.
-- IN-ENGINE BEHAVIOUR IS UNVERIFIED (see the PR checklist).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraRig = require(Shared:WaitForChild("CameraRig"))
local Formation = require(Shared:WaitForChild("Formation"))
local Pool = require(Shared:WaitForChild("Pool"))

-- Flat, saturated colors: the lead is the brightest thing on screen, followers share one color.
local LEAD_COLOR = Color3.fromRGB(255, 221, 0)
local LEAD_HEAD_COLOR = Color3.fromRGB(255, 240, 150)
local LEAD_HAT_COLOR = Color3.fromRGB(255, 110, 20)
local HORN_COLOR = Color3.fromRGB(235, 175, 40)
local RING_COLOR = Color3.fromRGB(80, 235, 255)
local FOLLOWER_COLOR = Color3.fromRGB(45, 120, 235)

local FOLLOW_RATE = 9 -- [default] how fast an avatar eases toward its slot
local BOB_HEIGHT = 0.25 -- [default] studs
local BOB_RATE = 9 -- [default] radians/second

type Avatar = { model: Model, x: number, z: number, fresh: boolean }

export type CrowdView = {
	update: (self: CrowdView, leadX: number, leadZ: number, total: number, dt: number) -> (),
}

local CrowdView = {}

local function part(
	parent: Instance,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	offset: Vector3,
	color: Color3
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Position = offset
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function buildLead(parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Lead"
	local body =
		part(model, "Body", Enum.PartType.Block, Vector3.new(2.6, 3, 2.2), Vector3.zero, LEAD_COLOR)
	part(
		model,
		"Head",
		Enum.PartType.Ball,
		Vector3.new(2.2, 2.2, 2.2),
		Vector3.new(0, 2.6, 0),
		LEAD_HEAD_COLOR
	)
	part(
		model,
		"Hat",
		Enum.PartType.Block,
		Vector3.new(1.8, 0.9, 1.8),
		Vector3.new(0, 4, 0),
		LEAD_HAT_COLOR
	)
	part(
		model,
		"Horn",
		Enum.PartType.Block,
		Vector3.new(0.7, 0.7, 2.2),
		Vector3.new(0, 0.5, 1.8),
		HORN_COLOR
	)
	model.PrimaryPart = body
	model.Parent = parent
	return model
end

local function buildFollower(parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Follower"
	local body = part(
		model,
		"Body",
		Enum.PartType.Block,
		Vector3.new(1.4, 2, 1.4),
		Vector3.zero,
		FOLLOWER_COLOR
	)
	part(
		model,
		"Head",
		Enum.PartType.Ball,
		Vector3.new(1.3, 1.3, 1.3),
		Vector3.new(0, 1.6, 0),
		FOLLOWER_COLOR
	)
	model.PrimaryPart = body
	model.Parent = parent
	return model
end

-- A neon ring on the ground under the lead: the steering anchor that never gets lost.
local function buildRing(parent: Instance): Part
	local ring = Instance.new("Part")
	ring.Name = "LeadRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, 8, 8) -- cylinder axis is X; rotated upright below
	ring.Color = RING_COLOR
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.2
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CastShadow = false
	ring.Parent = parent
	return ring
end

function CrowdView.new(): CrowdView
	local folder = Instance.new("Folder")
	folder.Name = "CalendaCrowd"
	folder.Parent = Workspace

	local lead = buildLead(folder) -- always present, even at zero followers (spec s3)
	local ring = buildRing(folder)

	local pool = Pool.new(function(): Avatar
		return { model = buildFollower(folder), x = 0, z = 0, fresh = true }
	end, function(avatar: Avatar)
		avatar.fresh = true -- snap to its slot the first frame it is shown
		avatar.model.Parent = folder
	end, function(avatar: Avatar)
		avatar.model.Parent = nil
	end)

	local cachedTotal = -1
	local layout: Formation.Layout = Formation.forTotal(0)
	local clock = 0

	local view = {} :: CrowdView

	function view.update(_, leadX: number, leadZ: number, total: number, dt: number)
		clock += dt
		if total ~= cachedTotal then
			cachedTotal = total
			layout = Formation.forTotal(total)
		end

		lead:PivotTo(
			CFrame.new(leadX, 1.5 + BOB_HEIGHT * math.abs(math.sin(clock * BOB_RATE)), leadZ)
		)
		ring.CFrame = CFrame.new(leadX, 0.12, leadZ) * CFrame.Angles(0, 0, math.pi / 2)

		local avatars = pool:setCount(#layout.slots)
		for i, avatar in avatars do
			local slot = layout.slots[i]
			local tx, tz = leadX + slot.dx, leadZ + slot.dz
			if avatar.fresh then
				avatar.x, avatar.z, avatar.fresh = tx, tz, false
			else
				avatar.x = CameraRig.smooth(avatar.x, tx, dt, FOLLOW_RATE)
				avatar.z = CameraRig.smooth(avatar.z, tz, dt, FOLLOW_RATE)
			end
			local bob = BOB_HEIGHT * math.abs(math.sin(clock * BOB_RATE + i))
			avatar.model:PivotTo(CFrame.new(avatar.x, 1 + bob, avatar.z))
		end
	end

	return view
end

return CrowdView
