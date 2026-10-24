--!strict
-- Tiny helper for figures built from primitive Parts (issues #19, #20): a Piece remembers its
-- size at scale 1 and is placed by a frame plus a local CFrame, both scaled together so a figure
-- can rise from nothing. No assets, no invented IDs. IN-ENGINE BEHAVIOUR IS UNVERIFIED.
export type Piece = { part: Part, size: Vector3, lastScale: number, lastHorizontalScale: number }

local FigureParts = {}

function FigureParts.add(
	parent: Instance,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	color: Color3
): Piece
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Parent = parent
	return { part = p, size = size, lastScale = 1, lastHorizontalScale = 1 }
end

-- `localCF` is the piece's CFrame in `frame`'s space at scale 1; its position scales, its
-- rotation does not.
function FigureParts.place(
	piece: Piece,
	frame: CFrame,
	localCF: CFrame,
	scale: number,
	horizontalScale: number?
)
	local s = math.max(scale, 0.001)
	local h = math.max(horizontalScale or 1, 0.001)
	if piece.lastScale ~= s or piece.lastHorizontalScale ~= h then
		piece.lastScale = s
		piece.lastHorizontalScale = h
		piece.part.Size = Vector3.new(piece.size.X * s * h, piece.size.Y * s, piece.size.Z * s * h)
	end
	local p = localCF.Position
	local offset = Vector3.new(p.X * s * h, p.Y * s, p.Z * s * h)
	piece.part.CFrame = frame * (CFrame.new(offset) * (localCF - p))
end

return FigureParts
