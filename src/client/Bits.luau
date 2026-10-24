--!strict
-- A small pooled burst system for confetti, dust and dispersing dancers (issue #14). Plain Parts
-- with hand-rolled ballistics: no assets, a hard cap so a huge parade never adds draw cost.
-- IN-ENGINE BEHAVIOUR IS UNVERIFIED (see the PR checklist).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LayerHeights = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LayerHeights"))

local Bits = {}

Bits.MAX = 90 -- [default] pieces alive at once; the oldest is recycled first
local GRAVITY = 40 -- [default] studs/second^2

export type Kind = "confetti" | "dust" | "dancer" | "prop"
type Bit = {
	part: Part,
	vx: number,
	vy: number,
	vz: number,
	life: number,
	total: number,
	spin: number,
}

export type Bits = {
	burst: (
		self: Bits,
		kind: Kind,
		center: Vector3,
		count: number,
		spread: number,
		colors: { Color3 }
	) -> (),
	update: (self: Bits, dt: number) -> (),
	clear: (self: Bits) -> (),
}

function Bits.new(parent: Instance): Bits
	local all: { Bit } = {}
	local nextIndex = 1
	local bits = {} :: Bits

	local function take(): Bit
		if #all < Bits.MAX then
			local p = Instance.new("Part")
			p.Name = "Bit"
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CastShadow = false
			p.Material = Enum.Material.SmoothPlastic
			local bit: Bit =
				{ part = p, vx = 0, vy = 0, vz = 0, life = 0, total = 1, spin = 0, drag = 0 }
			table.insert(all, bit)
			return bit
		end
		local bit = all[nextIndex]
		nextIndex = nextIndex % #all + 1
		return bit
	end

	function bits.burst(
		_,
		kind: Kind,
		center: Vector3,
		count: number,
		spread: number,
		colors: { Color3 }
	)
		for i = 1, count do
			local b = take()
			local a = math.random() * math.pi * 2
			local r = math.random() * spread
			local p = b.part
			if kind == "confetti" then
				p.Shape = Enum.PartType.Block
				p.Size = Vector3.new(0.5, 0.08, 0.8)
				p.Material = Enum.Material.SmoothPlastic
				p.Transparency = 0
				b.vx, b.vy, b.vz =
					math.cos(a) * r * 1.5, 22 + math.random() * 14, math.sin(a) * r * 1.5
				b.total = 0.9 + math.random() * 0.4
			elseif kind == "dust" then
				p.Shape = Enum.PartType.Ball
				p.Size = Vector3.one * (1.2 + math.random() * 1.2)
				p.Transparency = 0.35
				b.vx, b.vy, b.vz =
					math.cos(a) * r * 2.5, 2 + math.random() * 4, math.sin(a) * r * 2.5
				b.total = 0.45 + math.random() * 0.2
			elseif kind == "prop" then -- a flying hat or instrument piece (issue #50): tumbles, no gore
				p.Shape = Enum.PartType.Block
				p.Size = Vector3.new(1.3, 0.7 + math.random() * 0.8, 1.3)
				p.Transparency = 0
				b.vx, b.vy, b.vz = math.cos(a) * r * 3, 18 + math.random() * 8, math.sin(a) * r * 3
				b.total = 0.9 + math.random() * 0.3
			else -- dancer: a small colored figure-ball hopping away
				p.Shape = Enum.PartType.Ball
				p.Size = Vector3.one * 1.4
				p.Transparency = 0
				b.vx, b.vy, b.vz = math.cos(a) * r * 2, 14 + math.random() * 6, math.sin(a) * r * 2
				b.total = 0.8
			end
			b.drag = if kind == "confetti" then 0.4 else 0
			p.Color = colors[(i - 1) % #colors + 1]
			p.Position = center + Vector3.new(math.cos(a) * r * 0.3, 0, math.sin(a) * r * 0.3)
			b.life = b.total
			b.spin = (math.random() - 0.5) * 20
			p.Parent = parent
		end
	end

	function bits.update(_, dt: number)
		for _, b in all do
			if b.life > 0 then
				b.life -= dt
				local p = b.part
				if b.life <= 0 then
					p.Parent = nil
				else
					b.vy -= GRAVITY * (1 - b.drag) * dt
					local pos = p.Position + Vector3.new(b.vx, b.vy, b.vz) * dt
					if pos.Y < LayerHeights.DEBRIS then
						-- landed debris rests on its own layer, clear of the rings (issue #85 audit)
						pos = Vector3.new(pos.X, LayerHeights.DEBRIS, pos.Z)
						b.vy, b.vx, b.vz = 0, b.vx * 0.9, b.vz * 0.9
					end
					p.CFrame = CFrame.new(pos)
						* CFrame.Angles(b.life * b.spin, b.life * b.spin * 0.5, 0)
					if b.life < b.total * 0.3 and p.Shape == Enum.PartType.Ball then
						p.Transparency = math.max(p.Transparency, 1 - b.life / (b.total * 0.3))
					end
				end
			end
		end
	end

	function bits.clear(_)
		for _, b in all do
			b.life = 0
			b.part.Parent = nil
		end
	end

	return bits
end

return Bits
