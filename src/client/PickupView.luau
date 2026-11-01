--!strict
-- Optional +1 pickups in the world (issue #156, ADR 0014). Each authored pickup is a small gold
-- recruit marker (a round head on a block, with a flat gold disc under it) standing in its pickup
-- lane at its distance plane. Presentation only: the server awards the +1 (Crossing.pickupsAwarded);
-- this view hides a marker once the lead's z has passed its plane, collected or not, and writes
-- nothing on a frame where nothing changed. Positions come from the authored layout and
-- LaneGeometry; ViewMap mirrors x. IN-ENGINE APPEARANCE IS UNVERIFIED.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LaneGeometry = require(Shared:WaitForChild("LaneGeometry"))
local LayerHeights = require(Shared:WaitForChild("LayerHeights"))
local ViewMap = require(Shared:WaitForChild("ViewMap"))

local GOLD = Color3.fromRGB(245, 190, 40)
local BODY = Color3.fromRGB(45, 120, 235)

export type PickupView = {
	update: (self: PickupView, leadZ: number) -> (),
}

local PickupView = {}

local function part(
	parent: Instance,
	shape: Enum.PartType,
	size: Vector3,
	color: Color3,
	pos: Vector3
): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Position = pos
	p.Parent = parent
	return p
end

function PickupView.new(layout: any): PickupView
	local folder = Instance.new("Folder")
	folder.Name = "CalendaPickups"
	folder.Parent = Workspace
	type Marker = { z: number, parts: { Part }, shown: boolean }
	local markers: { Marker } = {}
	for _, p in layout.pickups or {} do
		local x = ViewMap.x(LaneGeometry.centerOf(p.lane))
		local parts = {
			part(
				folder,
				Enum.PartType.Cylinder,
				Vector3.new(0.2, 4, 4),
				GOLD,
				Vector3.new(x, LayerHeights.DECAL, p.z)
			),
			part(
				folder,
				Enum.PartType.Block,
				Vector3.new(1.4, 2, 1.4),
				BODY,
				Vector3.new(x, 1.4, p.z)
			),
			part(
				folder,
				Enum.PartType.Ball,
				Vector3.new(1.3, 1.3, 1.3),
				GOLD,
				Vector3.new(x, 2.9, p.z)
			),
		}
		parts[1].Orientation = Vector3.new(0, 0, 90) -- the cylinder's axis points up: a flat disc
		table.insert(markers, { z = p.z, parts = parts, shown = true })
	end
	local view = {} :: PickupView
	function view.update(_, leadZ: number)
		for _, m in markers do
			local want = m.z > leadZ
			if want ~= m.shown then
				m.shown = want
				for _, pt in m.parts do
					pt.Parent = if want then folder else nil
				end
			end
		end
	end
	return view
end

return PickupView
