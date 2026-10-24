--!strict
-- What SectionsView draws for one representative, whatever its type (issues #14, #19, #20): a
-- Visual is posed each frame and destroyed when it goes. Globo and dancers have their own files;
-- the puppet with its small entourage is wrapped here. IN-ENGINE BEHAVIOUR IS UNVERIFIED.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PuppetPose = require(Shared:WaitForChild("PuppetPose"))
local SectionScale = require(Shared:WaitForChild("SectionScale"))

local PuppetFigure = require(script.Parent:WaitForChild("PuppetFigure"))

export type Visual = {
	-- ground: world CFrame of the feet; time: os.clock(); phase: per-representative offset;
	-- scale: rise 0..1 (a little over 1 at the pop); intensity: the capped liveliness (spec s8).
	setPose: (
		self: Visual,
		ground: CFrame,
		time: number,
		phase: number,
		scale: number,
		intensity: number
	) -> (),
	badgeAnchor: Part, -- the xN badge floats above this
	destroy: (self: Visual) -> (),
	-- Globo only: where a decorative ring is born, as of the last pose.
	ringOrigin: ((self: Visual) -> Vector3)?,
	-- Dancers only: throw a gift now (`time` is os.clock()).
	toss: ((self: Visual, time: number) -> ())?,
}
-- Creates a representative's visual. `entourage` comes from the type's SectionTypes descriptor.
export type Builder = (parent: Instance, index: number, entourage: number) -> Visual

local SectionFigure = {}

function SectionFigure.puppet(parent: Instance, index: number, entourage: number): Visual
	local palettes = PuppetFigure.PALETTES
	local figures = { PuppetFigure.new(parent, palettes[(index - 1) % #palettes + 1]) }
	local scales = { 1 }
	for i = 1, entourage do
		table.insert(figures, PuppetFigure.new(parent, palettes[(index + i - 1) % #palettes + 1]))
		table.insert(scales, SectionScale.PUPPET_ENTOURAGE_SCALE)
	end
	local visual = {} :: Visual
	visual.badgeAnchor = figures[1].badgeAnchor
	local poseBuffer: PuppetPose.Pose = {
		headBob = 0,
		headTilt = 0,
		armLeft = 0,
		armRight = 0,
		clap = 0,
		sway = 0,
		bow = 0,
	}

	function visual.setPose(
		_,
		ground: CFrame,
		time: number,
		phase: number,
		scale: number,
		intensity: number
	)
		for i, figure in figures do
			local offset = Vector3.zero
			if i > 1 then
				local a = (i - 2) / math.max(1, #figures - 1) * math.pi * 2 + math.pi / 2
				offset = Vector3.new(math.cos(a), 0, math.sin(a)) * SectionScale.ENTOURAGE_RADIUS
			end
			PuppetPose.into(poseBuffer, time, phase + (i - 1) * 0.25)
			figure:setPose(ground * CFrame.new(offset), poseBuffer, scale * scales[i], intensity)
		end
	end

	function visual.destroy(_)
		for _, f in figures do
			f:destroy()
		end
	end

	return visual
end

return SectionFigure
