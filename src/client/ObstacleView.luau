--!strict
-- Obstacle feedback (issue #15): a dust and rubble puff where the lane closes, and a few
-- followers peel off to cheer from the sidewalk. No injury visuals. Whether and what to play
-- comes from the pure ObstacleFeedback (a repeated event for the same obstacle plays nothing)
-- and FeedbackMath; the new total reaches the HUD through State, unchanged.
-- IN-ENGINE BEHAVIOUR IS UNVERIFIED (see the PR checklist).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Effects = require(Shared:WaitForChild("Effects"))
local FeedbackMath = require(Shared:WaitForChild("FeedbackMath"))
local ObstacleFeedback = require(Shared:WaitForChild("ObstacleFeedback"))
local Pool = require(Shared:WaitForChild("Pool"))

local DUST_COLOR = Color3.fromRGB(205, 190, 165)
local RUBBLE_COLOR = Color3.fromRGB(150, 135, 120)
local FOLLOWER_COLOR = Color3.fromRGB(45, 120, 235)
local BURST_SECONDS = 0.9 -- [default]
local PEEL_SECONDS = 3.2 -- [default] run to the sidewalk, then cheer, then gone
local PEEL_RUN_SHARE = 0.25 -- [default] share of PEEL_SECONDS spent running
local CHUNK_CAPACITY = ObstacleFeedback.PUFFS * 2 -- [default] two overlapping bursts at most
local PEELER_CAPACITY = ObstacleFeedback.PEEL_MAX * 2

export type ObstacleView = {
	onObstacle: (self: ObstacleView, payload: any, leadX: number, leadZ: number) -> boolean,
	reset: (self: ObstacleView) -> (),
	update: (self: ObstacleView, dt: number) -> (),
}

local ObstacleView = {}

local function newPart(parent: Instance, shape: Enum.PartType, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
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

-- Returns true when the event played (first time for that obstacle this run).
function ObstacleView.new(layout: any): ObstacleView
	local folder = Instance.new("Folder")
	folder.Name = "CalendaObstacleFeedback"
	folder.Parent = Workspace

	local feedback = ObstacleFeedback.new(layout)

	type Chunk = { i: number, n: number, x: number, z: number }
	local chunks: Effects.Effects<Chunk> = Effects.new(CHUNK_CAPACITY)
	local chunkPool = Pool.new(function(): Part
		return newPart(folder, Enum.PartType.Block, Vector3.one, DUST_COLOR)
	end, function(p: Part)
		p.Parent = folder
	end, function(p: Part)
		p.Parent = nil
	end)

	type Peeler = { fromX: number, fromZ: number, toX: number, toZ: number }
	local peelers: Effects.Effects<Peeler> = Effects.new(PEELER_CAPACITY)
	local peelerPool = Pool.new(function(): { body: Part, head: Part }
		return {
			body = newPart(folder, Enum.PartType.Block, Vector3.new(1.4, 2, 1.4), FOLLOWER_COLOR),
			head = newPart(folder, Enum.PartType.Ball, Vector3.new(1.3, 1.3, 1.3), FOLLOWER_COLOR),
		}
	end, function(m)
		m.body.Parent, m.head.Parent = folder, folder
	end, function(m)
		m.body.Parent, m.head.Parent = nil, nil
	end)

	local clock = 0
	local view = {} :: ObstacleView

	function view.onObstacle(_, payload: any, leadX: number, leadZ: number): boolean
		local plan = feedback:handle(payload)
		if plan == nil then
			return false
		end
		for i = 1, plan.puffs do
			chunks:start(clock, BURST_SECONDS, { i = i, n = plan.puffs, x = plan.x, z = plan.z })
		end
		for i = 1, plan.peelers do
			peelers:start(clock, PEEL_SECONDS, {
				fromX = leadX + (i - (plan.peelers + 1) / 2) * 2,
				fromZ = leadZ - 3,
				toX = plan.sidewalkX[i],
				toZ = plan.sidewalkZ[i],
			})
		end
		return true
	end

	function view.reset(_)
		feedback:reset()
		chunks:clear()
		peelers:clear()
	end

	function view.update(_, dt: number)
		clock += dt
		local live = chunks:active(clock)
		local cs = chunkPool:setCount(#live)
		for i, p in cs do
			local c = live[i]
			local m = FeedbackMath.burst(c.data.i, c.data.n, c.f)
			p.Position = Vector3.new(c.data.x + m.dx, 1 + m.dy, c.data.z + m.dz)
			p.Size = Vector3.one * m.size
			p.Color = if c.data.i % 3 == 0 then RUBBLE_COLOR else DUST_COLOR
			p.Transparency = 1 - m.alpha * 0.85
		end

		local pl = peelers:active(clock)
		local ps = peelerPool:setCount(#pl)
		for i, m in ps do
			local e = pl[i]
			local d = e.data
			local x, z, y = d.toX, d.toZ, 0.9 * math.abs(math.sin(clock * 12 + i))
			if e.f < PEEL_RUN_SHARE then
				x, z, y = FeedbackMath.run(d.fromX, d.fromZ, d.toX, d.toZ, e.f / PEEL_RUN_SHARE)
			end
			m.body.Position = Vector3.new(x, 1 + y, z)
			m.head.Position = Vector3.new(x, 2.6 + y, z)
		end
	end

	return view
end

return ObstacleView
