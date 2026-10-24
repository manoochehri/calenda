--!strict
-- A globo / marmota (issue #19, spec s7) from primitive Parts: a large decorated sphere on a visible
-- pole that rotates and tilts, with small carriers around the pole base. The sphere carries a belt,
-- a tilted belt and dots so its rotation reads from the high camera. All numbers come from the pure
-- GloboPose; this module only moves Parts. IN-ENGINE BEHAVIOUR IS UNVERIFIED (see the PR checklist).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GloboPose = require(Shared:WaitForChild("GloboPose"))
local DanceConfig = require(Shared:WaitForChild("DanceConfig"))
local PuppetPose = require(Shared:WaitForChild("PuppetPose"))
local SectionScale = require(Shared:WaitForChild("SectionScale"))

local FigureParts = require(script.Parent:WaitForChild("FigureParts"))
local PuppetFigure = require(script.Parent:WaitForChild("PuppetFigure"))
local SectionFigure = require(script.Parent:WaitForChild("SectionFigure"))

local SPHERE_DIAMETER = 7.5 -- [default] studs at scale 1; a puppet is 11 tall
local SPHERE_Y = 11.5 -- [default] sphere center above the feet
local POLE_LENGTH = 9.4 -- [default]
local CARRIER_SCALE = DanceConfig.globoCarrierScale
local DOT_COUNT = 12 -- [default]
local GOLDEN_ANGLE = 2.399963229728653

type Look = { sphere: Color3, belt: Color3, belt2: Color3, dots: { Color3 } }
local LOOKS: { Look } = {
	{
		sphere = Color3.fromRGB(235, 60, 110),
		belt = Color3.fromRGB(255, 215, 40),
		belt2 = Color3.fromRGB(40, 190, 235),
		dots = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 215, 40) },
	},
	{
		sphere = Color3.fromRGB(40, 170, 235),
		belt = Color3.fromRGB(255, 120, 40),
		belt2 = Color3.fromRGB(255, 255, 255),
		dots = { Color3.fromRGB(255, 215, 40), Color3.fromRGB(235, 60, 110) },
	},
	{
		sphere = Color3.fromRGB(110, 220, 120),
		belt = Color3.fromRGB(235, 60, 110),
		belt2 = Color3.fromRGB(255, 215, 40),
		dots = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 80, 230) },
	},
}
local POLE_COLOR = Color3.fromRGB(130, 80, 40)
local KNOB_COLOR = Color3.fromRGB(255, 215, 40)

local GloboFigure = {}

function GloboFigure.new(parent: Instance, index: number, carriers: number): SectionFigure.Visual
	local look = LOOKS[(index - 1) % #LOOKS + 1]
	local model = Instance.new("Model")
	model.Name = "Globo"
	model.Parent = parent

	local pole = FigureParts.add(
		model,
		"Pole",
		Enum.PartType.Block,
		Vector3.new(0.7, POLE_LENGTH, 0.7),
		POLE_COLOR
	)
	local sphere = FigureParts.add(
		model,
		"Sphere",
		Enum.PartType.Ball,
		Vector3.one * SPHERE_DIAMETER,
		look.sphere
	)
	local topKnob =
		FigureParts.add(model, "Knob", Enum.PartType.Ball, Vector3.one * 1.6, KNOB_COLOR)
	-- Cylinders run along X; turn them so the belt is a flat disc around the sphere's middle.
	local belt = FigureParts.add(
		model,
		"Belt",
		Enum.PartType.Cylinder,
		Vector3.new(1.1, SPHERE_DIAMETER + 0.2, SPHERE_DIAMETER + 0.2),
		look.belt
	)
	local belt2 = FigureParts.add(
		model,
		"Belt2",
		Enum.PartType.Cylinder,
		Vector3.new(0.8, SPHERE_DIAMETER + 0.15, SPHERE_DIAMETER + 0.15),
		look.belt2
	)
	local dots: { { piece: FigureParts.Piece, dir: Vector3 } } = {}
	for i = 1, DOT_COUNT do
		local y = 1 - (i - 0.5) / DOT_COUNT * 2 -- spread from the top to the bottom
		local r = math.sqrt(math.max(0, 1 - y * y))
		local a = i * GOLDEN_ANGLE
		table.insert(dots, {
			piece = FigureParts.add(
				model,
				"Dot",
				Enum.PartType.Ball,
				Vector3.one * 0.95,
				look.dots[i % #look.dots + 1]
			),
			dir = Vector3.new(math.cos(a) * r, y, math.sin(a) * r),
		})
	end
	local people: { PuppetFigure.Figure } = {}
	local palettes = PuppetFigure.PALETTES
	for i = 1, carriers do
		table.insert(people, PuppetFigure.new(model, palettes[(index + i) % #palettes + 1]))
	end
	local offsets = GloboPose.carrierOffsets(carriers)
	local poseBuffer: GloboPose.Pose = { spin = 0, tiltX = 0, tiltZ = 0, lift = 0, carrierStep = 0 }
	local carrierPose: PuppetPose.Pose = {
		headBob = 0,
		headTilt = 0,
		armLeft = 0,
		armRight = 0,
		clap = 0,
		sway = 0,
		bow = 0,
	}

	local center = Vector3.zero
	local visual = {} :: SectionFigure.Visual
	visual.badgeAnchor = topKnob.part

	local beltTilt = CFrame.Angles(0, 0, math.pi / 2)
	local belt2Tilt = CFrame.Angles(0.95, 0, 0) * beltTilt

	function visual.setPose(
		_,
		ground: CFrame,
		time: number,
		phase: number,
		scale: number,
		intensity: number
	)
		local s = math.max(scale, 0.001)
		GloboPose.into(poseBuffer, time, phase)
		local pose = poseBuffer
		-- The whole pole leans about its base; the sphere pops up on the beat and turns on the pole.
		local poleFrame = ground
			* CFrame.Angles(
				math.clamp(pose.tiltX * intensity, -GloboPose.MAX_TILT, GloboPose.MAX_TILT),
				0,
				math.clamp(pose.tiltZ * intensity, -GloboPose.MAX_TILT, GloboPose.MAX_TILT)
			)
		FigureParts.place(pole, poleFrame, CFrame.new(0, POLE_LENGTH / 2, 0), s)
		local lift = pose.lift * math.min(intensity, PuppetPose.MAX_INTENSITY)
		local sphereFrame = poleFrame
			* CFrame.new(0, (SPHERE_Y + lift) * s, 0)
			* CFrame.Angles(0, pose.spin * math.min(intensity, DanceConfig.maxAmplitude), 0)
		FigureParts.place(sphere, sphereFrame, CFrame.identity, s)
		FigureParts.place(belt, sphereFrame, beltTilt, s)
		FigureParts.place(belt2, sphereFrame, belt2Tilt, s)
		FigureParts.place(topKnob, sphereFrame, CFrame.new(0, SPHERE_DIAMETER / 2 + 0.6, 0), s)
		for _, d in dots do
			FigureParts.place(d.piece, sphereFrame, CFrame.new(d.dir * (SPHERE_DIAMETER / 2)), s)
		end
		center = sphereFrame.Position
		for i, person in people do
			local o = offsets[i]
			local bob = pose.carrierStep * DanceConfig.globoCarrierStepStuds * s * intensity
			PuppetPose.into(carrierPose, time, phase + i * 0.31)
			person:setPose(
				ground
					* CFrame.new(
						o.dx * s * SectionScale.GLOBO_CARRIER_FACTOR,
						bob,
						o.dz * s * SectionScale.GLOBO_CARRIER_FACTOR
					),
				carrierPose,
				s * CARRIER_SCALE,
				intensity
			)
		end
	end

	function visual.ringOrigin(_): Vector3
		return center
	end

	function visual.destroy(_)
		for _, person in people do
			person:destroy()
		end
		model:Destroy()
	end

	return visual
end

return GloboFigure
