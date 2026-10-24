--!strict
-- A dancer section (issue #20, spec s7) from primitive Parts: a lead dancer and a small chorus in a V,
-- each with a swirling petal skirt, a flower crown, a flower basket and alternating coordinated steps.
-- A gift toss raises the basket arm and pops the basket up. All numbers come from the pure
-- DancerPose; this module only moves Parts. IN-ENGINE BEHAVIOUR IS UNVERIFIED (see the PR checklist).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DancerPose = require(Shared:WaitForChild("DancerPose"))
local SectionScale = require(Shared:WaitForChild("SectionScale"))

local FigureParts = require(script.Parent:WaitForChild("FigureParts"))
local SectionFigure = require(script.Parent:WaitForChild("SectionFigure"))

local PETALS = 6 -- [default] skirt petals; two alternating colors so the swirl reads
local SKIN = Color3.fromRGB(240, 190, 150)
local HAIR = Color3.fromRGB(50, 30, 30)
local BASKET = Color3.fromRGB(170, 110, 50)
local FLOWERS = {
	Color3.fromRGB(255, 90, 150),
	Color3.fromRGB(255, 225, 60),
	Color3.fromRGB(255, 255, 255),
}
type Palette = { skirtA: Color3, skirtB: Color3, top: Color3 }
local PALETTES: { Palette } = {
	{
		skirtA = Color3.fromRGB(235, 60, 110),
		skirtB = Color3.fromRGB(255, 200, 40),
		top = Color3.fromRGB(255, 255, 255),
	},
	{
		skirtA = Color3.fromRGB(40, 170, 235),
		skirtB = Color3.fromRGB(255, 120, 40),
		top = Color3.fromRGB(255, 240, 200),
	},
	{
		skirtA = Color3.fromRGB(150, 80, 230),
		skirtB = Color3.fromRGB(70, 220, 160),
		top = Color3.fromRGB(255, 255, 255),
	},
}

type Dancer = {
	legL: FigureParts.Piece,
	legR: FigureParts.Piece,
	petals: { FigureParts.Piece },
	torso: FigureParts.Piece,
	head: FigureParts.Piece,
	hair: FigureParts.Piece,
	flower: FigureParts.Piece,
	armL: FigureParts.Piece,
	armR: FigureParts.Piece,
	basket: FigureParts.Piece,
	blooms: { FigureParts.Piece },
}

local function newDancer(parent: Instance, palette: Palette): Dancer
	local block, ball = Enum.PartType.Block, Enum.PartType.Ball
	local petals = {}
	for i = 1, PETALS do
		table.insert(
			petals,
			FigureParts.add(
				parent,
				"Petal",
				block,
				Vector3.new(1.7, 0.35, 1.5),
				if i % 2 == 0 then palette.skirtA else palette.skirtB
			)
		)
	end
	local blooms = {}
	for i, c in FLOWERS do
		blooms[i] = FigureParts.add(parent, "Bloom", ball, Vector3.one * 0.7, c)
	end
	return {
		legL = FigureParts.add(parent, "LegL", block, Vector3.new(0.8, 2.6, 0.8), SKIN),
		legR = FigureParts.add(parent, "LegR", block, Vector3.new(0.8, 2.6, 0.8), SKIN),
		petals = petals,
		torso = FigureParts.add(parent, "Top", block, Vector3.new(1.6, 2, 1.1), palette.top),
		head = FigureParts.add(parent, "Head", ball, Vector3.one * 1.6, SKIN),
		hair = FigureParts.add(parent, "Hair", block, Vector3.new(1.7, 0.8, 1.7), HAIR),
		flower = FigureParts.add(parent, "Crown", ball, Vector3.one * 1.1, FLOWERS[1]),
		armL = FigureParts.add(parent, "ArmL", block, Vector3.new(0.6, 2.2, 0.6), SKIN),
		armR = FigureParts.add(parent, "ArmR", block, Vector3.new(0.6, 2.2, 0.6), SKIN),
		basket = FigureParts.add(parent, "Basket", block, Vector3.new(1.5, 0.9, 1.1), BASKET),
		blooms = blooms,
	}
end

local DancerFigure = {}

function DancerFigure.new(parent: Instance, index: number, entourage: number): SectionFigure.Visual
	local model = Instance.new("Model")
	model.Name = "Dancers"
	model.Parent = parent
	local slots = DancerPose.formation(entourage + 1)
	local dancers: { Dancer } = {}
	for i = 1, #slots do
		table.insert(dancers, newDancer(model, PALETTES[(index + i - 2) % #PALETTES + 1]))
	end
	local tossedAt = -math.huge

	local visual = {} :: SectionFigure.Visual
	visual.badgeAnchor = dancers[1].flower.part

	function visual.setPose(
		_,
		ground: CFrame,
		time: number,
		phase: number,
		scale: number,
		intensity: number
	)
		local toss = DancerPose.toss(time - tossedAt)
		for i, d in dancers do
			local slot = slots[i]
			local s = math.max(scale, 0.001) * slot.scale
			-- Steps and hops depend only on time (the group moves as one); the skirt swirl is offset.
			local pose = DancerPose.pose(time, phase + (i - 1) * 0.12)
			local hop = pose.hop * math.min(intensity, 1.5)
			local frame = ground
				* CFrame.new(
					slot.dx * scale * SectionScale.DANCER_SPREAD,
					0,
					slot.dz * scale * SectionScale.DANCER_SPREAD
				)
				* CFrame.Angles(0, 0, pose.sway)
			FigureParts.place(d.legL, frame, CFrame.new(-0.6, 1.3 + pose.footL + hop, 0), s)
			FigureParts.place(d.legR, frame, CFrame.new(0.6, 1.3 + pose.footR + hop, 0), s)
			-- The skirt: petals around the waist, turned by the swirl and opened by the flare.
			local waist = CFrame.new(0, 3.3 + hop, 0) * CFrame.Angles(0, pose.swirl, 0)
			local radius = 0.5 + 1.2 * pose.flare
			local droop = 0.25 + 0.3 * pose.flare
			for p, petal in d.petals do
				local a = (p - 1) / #d.petals * math.pi * 2
				FigureParts.place(
					petal,
					frame,
					waist
						* CFrame.Angles(0, a, 0)
						* CFrame.new(0, 0, radius)
						* CFrame.Angles(droop, 0, 0),
					s
				)
			end
			FigureParts.place(d.torso, frame, CFrame.new(0, 4.6 + hop, 0), s)
			FigureParts.place(d.head, frame, CFrame.new(0, 6.2 + hop, 0), s)
			FigureParts.place(d.hair, frame, CFrame.new(0, 6.95 + hop, -0.05), s)
			FigureParts.place(d.flower, frame, CFrame.new(0.3, 7.5 + hop, 0), s)
			-- Free arm swings; the basket arm raises on a toss (only the lead's throw is exaggerated).
			local left = CFrame.new(-1.1, 5.5 + hop, 0)
				* CFrame.Angles(pose.armSwing, 0, -0.25)
				* CFrame.new(0, -1.1, 0)
			FigureParts.place(d.armL, frame, left, s)
			local raise = toss.raise * 2.2
			local right = CFrame.new(1.1, 5.5 + hop, 0)
				* CFrame.Angles(-raise - pose.armSwing * 0.2, 0, 0.25)
			FigureParts.place(d.armR, frame, right * CFrame.new(0, -1.1, 0), s)
			local basket = right * CFrame.new(0, -2.4 + toss.lift * 0.4, 0)
			FigureParts.place(d.basket, frame, basket, s)
			local spots = {
				Vector3.new(-0.4, 0.65, 0),
				Vector3.new(0.4, 0.65, 0),
				Vector3.new(0, 0.85, 0.2),
			}
			for b, bloom in d.blooms do
				FigureParts.place(bloom, frame, basket * CFrame.new(spots[b]), s)
			end
		end
	end

	function visual.toss(_, time: number)
		tossedAt = time
	end

	function visual.destroy(_)
		model:Destroy()
	end

	return visual
end

return DancerFigure
