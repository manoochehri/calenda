--!strict
-- A tall humanlike puppet (or a small entourage copy) built from primitive Parts (issue #14, spec s7).
-- No assets, no invented IDs. Pose numbers come from the pure PuppetPose; this module only moves
-- Parts. IN-ENGINE BEHAVIOUR IS UNVERIFIED (see the PR checklist).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PuppetPose = require(Shared:WaitForChild("PuppetPose"))

export type Figure = {
	model: Model,
	-- root: world CFrame of the feet; scale: 1 = full height; intensity: bigger bounce.
	setPose: (
		self: Figure,
		root: CFrame,
		pose: PuppetPose.Pose,
		scale: number,
		intensity: number
	) -> (),
	badgeAnchor: Part,
	destroy: (self: Figure) -> (),
}

export type Palette = { cloth: Color3, skirt: Color3, skin: Color3, hat: Color3 }

local PuppetFigure = {}

PuppetFigure.HEIGHT = 11 -- [default] studs at scale 1; about 5x a follower

PuppetFigure.PALETTES = {
	{
		cloth = Color3.fromRGB(235, 60, 110),
		skirt = Color3.fromRGB(255, 200, 40),
		skin = Color3.fromRGB(255, 214, 170),
		hat = Color3.fromRGB(60, 190, 120),
	},
	{
		cloth = Color3.fromRGB(40, 170, 235),
		skirt = Color3.fromRGB(255, 120, 40),
		skin = Color3.fromRGB(235, 180, 140),
		hat = Color3.fromRGB(235, 60, 110),
	},
	{
		cloth = Color3.fromRGB(150, 80, 230),
		skirt = Color3.fromRGB(70, 220, 160),
		skin = Color3.fromRGB(250, 205, 160),
		hat = Color3.fromRGB(255, 200, 40),
	},
	{
		cloth = Color3.fromRGB(255, 140, 30),
		skirt = Color3.fromRGB(60, 120, 235),
		skin = Color3.fromRGB(225, 170, 125),
		hat = Color3.fromRGB(235, 60, 110),
	},
	{
		cloth = Color3.fromRGB(60, 200, 110),
		skirt = Color3.fromRGB(235, 60, 110),
		skin = Color3.fromRGB(255, 220, 180),
		hat = Color3.fromRGB(40, 170, 235),
	},
	{
		cloth = Color3.fromRGB(255, 205, 40),
		skirt = Color3.fromRGB(150, 80, 230),
		skin = Color3.fromRGB(240, 190, 150),
		hat = Color3.fromRGB(255, 140, 30),
	},
} :: { Palette }

type PartSpec = {
	part: Part,
	size: Vector3, -- at scale 1
	offset: Vector3, -- relative to the body root, at scale 1
}

local function newPart(
	parent: Instance,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	color: Color3
): Part
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
	return p
end

function PuppetFigure.new(parent: Instance, palette: Palette): Figure
	local model = Instance.new("Model")
	model.Name = "Puppet"
	model.Parent = parent

	local function spec(
		name: string,
		shape: Enum.PartType,
		size: Vector3,
		offset: Vector3,
		color: Color3
	): PartSpec
		return { part = newPart(model, name, shape, size, color), size = size, offset = offset }
	end

	-- Offsets are from the feet. The torso is the badge anchor (the xN badge floats above the hat).
	local legs = {
		spec(
			"LegL",
			Enum.PartType.Block,
			Vector3.new(1.1, 3.4, 1.1),
			Vector3.new(-0.8, 1.7, 0),
			palette.cloth
		),
		spec(
			"LegR",
			Enum.PartType.Block,
			Vector3.new(1.1, 3.4, 1.1),
			Vector3.new(0.8, 1.7, 0),
			palette.cloth
		),
	}
	local skirt = spec(
		"Skirt",
		Enum.PartType.Block,
		Vector3.new(4.2, 2.6, 3.2),
		Vector3.new(0, 4.5, 0),
		palette.skirt
	)
	local torso = spec(
		"Torso",
		Enum.PartType.Block,
		Vector3.new(3, 3.4, 2),
		Vector3.new(0, 7.4, 0),
		palette.cloth
	)
	local head = spec(
		"Head",
		Enum.PartType.Ball,
		Vector3.new(2.6, 2.6, 2.6),
		Vector3.new(0, 10, 0),
		palette.skin
	)
	local hat = spec(
		"Hat",
		Enum.PartType.Block,
		Vector3.new(2.2, 1.2, 2.2),
		Vector3.new(0, 11.7, 0),
		palette.hat
	)
	local body: { PartSpec } = { legs[1], legs[2], skirt, torso, head, hat }

	local armSize = Vector3.new(0.9, 3.6, 0.9)
	local armL = spec("ArmL", Enum.PartType.Block, armSize, Vector3.zero, palette.skin)
	local armR = spec("ArmR", Enum.PartType.Block, armSize, Vector3.zero, palette.skin)
	local SHOULDER_Y = 8.8
	local SHOULDER_X = 1.9

	local anchor = torso.part
	local figure = {} :: Figure
	figure.model = model
	figure.badgeAnchor = hat.part

	local lastScale = -1

	function figure.setPose(
		_,
		root: CFrame,
		pose: PuppetPose.Pose,
		scale: number,
		intensity: number
	)
		local s = math.max(scale, 0.001)
		local lean = CFrame.Angles(0, 0, pose.sway) -- whole body sways at the feet
		local base = root * lean
		if s ~= lastScale then
			lastScale = s
			for _, ps in body do
				ps.part.Size = ps.size * s
			end
			armL.part.Size = armSize * s
			armR.part.Size = armSize * s
		end
		for _, ps in body do
			local bob = Vector3.zero
			local rot = CFrame.identity
			if ps == head or ps == hat then
				bob = Vector3.new(0, pose.headBob * intensity * s, 0)
				rot = CFrame.Angles(0, 0, pose.headTilt)
			end
			ps.part.CFrame = base * CFrame.new(ps.offset * s + bob) * rot
		end
		-- Loose arms: swing sideways; on the beat they come forward and together to clap.
		local clap = pose.clap
		for _, side in { { armL, -1, pose.armLeft }, { armR, 1, pose.armRight } } do
			local a = side[1] :: PartSpec
			local sign = side[2] :: number
			local swing = side[3] :: number
			local shoulder = Vector3.new(sign * SHOULDER_X, SHOULDER_Y, 0) * s
			local rotation = CFrame.Angles(-clap * 1.5, 0, sign * (swing * (1 - clap) - clap * 0.6))
			a.part.CFrame = base * CFrame.new(shoulder) * rotation * CFrame.new(0, -1.8 * s, 0)
		end
	end

	function figure.destroy(_)
		model:Destroy()
	end

	-- keep `anchor` referenced for future badge attachment without an unused-variable lint.
	model.PrimaryPart = anchor
	return figure
end

return PuppetFigure
