--!strict
-- Draws spectator MOBS by level of detail (issue #65). Reusable: the ambient street crowds of #54
-- phase 2 feed it the same descriptors. All numbers come from the pure modules (QualityConfig,
-- MobLod, MobCharge, Emergence); this file only turns them into Instances.
--
--  NEAR LOD: pooled real figures (body + head + arms = 3 Parts, no accessories), every figure of
--   every mob moved in ONE call per frame with Workspace:BulkMoveTo(parts, cframes,
--   Enum.BulkMoveMode.FireCFrameChanged). Verified in the Roblox docs (WorldRoot:BulkMoveTo,
--   Enum.BulkMoveMode): "provides a very fast way to move large numbers of parts"; the two arrays
--   are matched by index; FireCFrameChanged fires only the CFrame event (FireAllEvents, the
--   default, also fires Position/Orientation/Rotation). The docs add that it is only worth using
--   when part movement is a measured bottleneck: it is a deliberate choice here for hundreds of
--   anchored figures, to be confirmed in the Studio frame-time check. Colours and sizes are
--   written only when they change; the per-frame arrays are reused.
--  FAR LOD: one ParticleEmitter per mob on a transparent anchored emitter Part spanning the mob's
--   footprint, rolling forward with it (LockedToPart = false so the swarm trails). Texture is left
--   at the ParticleEmitter default (no asset ids are invented; its look is UNVERIFIED until Studio).
--   Rate = dots / Lifetime ("Number of particles = Rate * Lifetime", ParticleEmitter docs). The
--   docs state no particle-count limit, so the caps below are our own (QualityConfig).
--  DUST: a capped set of dust emitters on the nearest mobs (stride dust, impact and dissolve puffs).
-- Display only. IN-ENGINE BEHAVIOUR IS UNVERIFIED (see the PR checklist).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraRig = require(Shared:WaitForChild("CameraRig"))
local MobCharge = require(Shared:WaitForChild("MobCharge"))
local MobLod = require(Shared:WaitForChild("MobLod"))
local Pool = require(Shared:WaitForChild("Pool"))
local QualityConfig = require(Shared:WaitForChild("QualityConfig"))
local ViewMap = require(Shared:WaitForChild("ViewMap"))

local FIGURE_HEIGHT = 2.2 -- studs, what the LOD screen share is measured on
local DUST_RATE = 14 -- [default] stride dust per second on a charging mob (before fade)
local DUST_COLOR = Color3.fromRGB(214, 190, 150)
local SWARM_HEIGHT = 1.4 -- studs, centre height of the emitter Part
local DEPTH_PULLBACK = 1 -- LOD measured at the closest camera (the early game)

export type Desc = {
	id: number,
	x: number, -- WORLD x of the mob's centre (mirrored once here through ViewMap.x)
	z: number, -- the mob's FRONT
	reward: number,
	ahead: number, -- front z minus lead z
	fade: number, -- 0..1 emerge fade (Emergence.fade)
	phase: string, -- walking | slamming | dispersing | cheering
	phaseT: number,
	age: number,
	pulse: number, -- 0..1 alert pulse (unconverted only)
	dip: number, -- 0..1 impact squash of the whole mob
	hop: number, -- extra hop (gift catch), studs
	glow: number, -- 0..1 brighten (gift catch)
}

export type MobView = {
	update: (self: MobView, mobs: { Desc }, leadZ: number, clock: number) -> (),
	setQuality: (self: MobView, name: string) -> (),
	quality: (self: MobView) -> string,
	counts: (self: MobView) -> { figures: number, mobs: number, emitters: number },
	clear: (self: MobView) -> (),
}

type Figure = { body: Part, head: Part, arms: Part, bodyKey: number, headKey: number }
type Swarm = {
	part: Part,
	emitter: ParticleEmitter,
	id: number,
	mixKey: number,
	rate: number,
}
type Dust = { part: Part, emitter: ParticleEmitter }

local MobView = {}

local function newPart(parent: Instance, shape: Enum.PartType, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function emitterPart(parent: Instance): Part
	local p = newPart(parent, Enum.PartType.Block, Vector3.new(4, 2, 4), Color3.new(1, 1, 1))
	p.Transparency = 1
	return p
end

local function swarmEmitter(part: Part): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "Swarm"
	e.Rate = 0
	e.Lifetime = NumberRange.new(MobLod.LIFETIME * 0.8, MobLod.LIFETIME * 1.2)
	e.Speed = NumberRange.new(1, 3)
	e.SpreadAngle = Vector2.new(12, 12)
	e.EmissionDirection = Enum.NormalId.Front -- toward -z, where the mob charges
	e.LockedToPart = false -- the swarm trails behind the rolling mob
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.3),
		NumberSequenceKeypoint.new(1, 1.0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.75, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.LightEmission = 0
	e.Parent = part
	return e
end

local function dustEmitter(part: Part): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "Dust"
	e.Rate = 0
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.Speed = NumberRange.new(3, 8)
	e.SpreadAngle = Vector2.new(70, 70)
	e.EmissionDirection = Enum.NormalId.Top
	e.LockedToPart = false
	e.Acceleration = Vector3.new(0, -4, 0)
	e.Color = ColorSequence.new(DUST_COLOR)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.6),
		NumberSequenceKeypoint.new(1, 4.5),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Parent = part
	return e
end

-- ColorSequence of a mob's palette blended angry -> party by `mix`.
local function palette(mix: number, pulse: number): ColorSequence
	local points = {}
	for i = 1, 4 do
		local r, g, b = MobCharge.colour(i, mix, pulse, false)
		table.insert(
			points,
			ColorSequenceKeypoint.new((i - 1) / 3, Color3.fromRGB(r // 1, g // 1, b // 1))
		)
	end
	return ColorSequence.new(points)
end

function MobView.new(parent: Instance, quality: string): MobView
	local folder = Instance.new("Folder")
	folder.Name = "CalendaMobs"
	folder.Parent = parent

	local level = QualityConfig.get(quality)
	local levelName = QualityConfig.resolve(quality)
	local self = {} :: MobView

	local figures = Pool.new(function(): Figure
		local body = newPart(
			folder,
			Enum.PartType.Block,
			Vector3.new(1.1, 1.5, 0.8),
			Color3.fromRGB(214, 58, 46)
		)
		local head = newPart(
			folder,
			Enum.PartType.Ball,
			Vector3.new(0.95, 0.95, 0.95),
			Color3.fromRGB(255, 214, 170)
		)
		local arms = newPart(
			folder,
			Enum.PartType.Block,
			Vector3.new(1.9, 0.3, 0.3),
			Color3.fromRGB(214, 58, 46)
		)
		return { body = body, head = head, arms = arms, bodyKey = -1, headKey = -1 }
	end, function(f: Figure)
		f.body.Parent, f.head.Parent, f.arms.Parent = folder, folder, folder
	end, function(f: Figure)
		f.body.Parent, f.head.Parent, f.arms.Parent = nil, nil, nil
	end)

	local swarms: { Swarm } = {} -- one per drawn mob, kept by id so the emitter follows its mob
	local freeSwarms: { Swarm } = {}
	local byId: { [number]: Swarm } = {}
	local dusts: { Dust } = {}
	local puffed: { [number]: boolean } = {}
	local usedFigures, usedMobs, usedEmitters = 0, 0, 0

	-- Reused per-frame arrays for BulkMoveTo.
	local moveParts: { Instance } = {}
	local moveCFrames: { CFrame } = {}
	local moveCount = 0

	local function swarmFor(id: number): Swarm?
		local s = byId[id]
		if s ~= nil then
			return s
		end
		s = table.remove(freeSwarms)
		if s == nil then
			if #swarms >= level.maxMobs then
				return nil
			end
			local part = emitterPart(folder)
			s = { part = part, emitter = swarmEmitter(part), id = id, mixKey = -1, rate = 0 }
			table.insert(swarms, s :: Swarm)
		end
		local sw = s :: Swarm
		sw.id, sw.mixKey = id, -1
		sw.part.Parent = folder
		byId[id] = sw
		return sw
	end

	local function release(id: number)
		local s = byId[id]
		if s ~= nil then
			byId[id] = nil
			s.emitter.Rate = 0
			s.rate = 0
			s.part.Parent = nil
			table.insert(freeSwarms, s)
		end
	end

	local function dustFor(rank: number): Dust?
		if rank > level.maxDust then
			return nil
		end
		local d = dusts[rank]
		if d == nil then
			local part = emitterPart(folder)
			d = { part = part, emitter = dustEmitter(part) }
			dusts[rank] = d
		end
		return d
	end

	local function push(part: Instance, cf: CFrame)
		moveCount += 1
		moveParts[moveCount] = part
		moveCFrames[moveCount] = cf
	end

	function self.update(_, mobs: { Desc }, leadZ: number, clock: number)
		moveCount = 0
		local sorted = table.clone(mobs)
		table.sort(sorted, function(a, b)
			return a.ahead < b.ahead
		end)
		-- LOD: the share of the screen one figure takes, measured at the closest camera pose.
		local pose = CameraRig.pose(0, leadZ, DEPTH_PULLBACK)
		local ins: { MobLod.MobIn } = {}
		for i, m in sorted do
			local frac = CameraRig.screenFraction(pose, FIGURE_HEIGHT / 2, m.z, FIGURE_HEIGHT)
			local keep = if m.phase == "cheering" then MobCharge.streamKeep(m.age) else 1
			ins[i] = {
				size = MobLod.mobSize(m.reward, levelName),
				nearWeight = MobLod.nearWeight(frac),
				fade = m.fade * keep,
			}
		end
		local alloc = MobLod.allocate(ins, levelName)

		local seen: { [number]: boolean } = {}
		local figureCursor, drawn = 0, 0
		local needed = 0
		for _, a in alloc do
			needed += a.figures
		end
		local figureSlots = figures:setCount(needed)

		for i, m in sorted do
			local a = alloc[i]
			if not a.drawn then
				continue
			end
			drawn += 1
			seen[m.id] = true
			local size = ins[i].size
			local width, depth = MobLod.footprint(size)
			local party = if m.phase == "cheering" then MobCharge.partyMix(m.age) else 0
			local depthScale = 1
			if m.phase == "slamming" then
				depthScale = MobCharge.slamDepth(m.age)
			end
			local pulse = math.max(m.pulse, m.glow)
			local sink = (1 - m.fade) * MobCharge.SINK -- rises out of the road as it fades in
			local centerX = m.x
			local slam = if m.phase == "slamming" then MobCharge.slam(m.age) else 0

			-- real figures
			for k = 1, a.figures do
				figureCursor += 1
				local f = figureSlots[figureCursor]
				local dx, dz = MobCharge.wedgeSlot(k, level.maxFiguresPerMob, width, depth)
				local x, z = centerX + dx, m.z + dz * depthScale
				local hop, lean, arm = MobCharge.stride(k + m.id, clock)
				local down = sink
				if m.phase == "slamming" then
					local rowShare = 1 - math.min(1, dz / math.max(depth, 1))
					hop += MobCharge.SLAM_HOP * slam * rowShare
					lean = MobCharge.LEAN + 0.25 * slam
				elseif m.phase == "dispersing" then
					local sx, shop, ssink = MobCharge.disperse(x, centerX, m.phaseT)
					x, hop, down = sx, shop + hop * 0.3, math.max(down, ssink)
					z += dz * 0.6 * m.phaseT
					lean, arm = 0.1, MobCharge.ARM_UP
				elseif m.phase == "cheering" then
					lean, hop = 0, hop * 2 -- upright, cheering; the count already thins as they stream in
				end
				local y = hop + m.hop - m.dip * 0.4 - down
				local root = CFrame.new(ViewMap.x(x), y, z) * CFrame.Angles(-lean, 0, 0)
				push(f.body, root * CFrame.new(0, 0.75, 0))
				push(f.head, root * CFrame.new(0, 1.95, 0))
				push(f.arms, root * CFrame.new(0, arm, 0))
				-- colours only when they change (quantised)
				local qk = math.floor(party * 4 + 0.5) * 8 + math.floor(pulse * 4 + 0.5)
				local key = qk * 4 + (k + m.id) % 4
				if f.bodyKey ~= key then
					f.bodyKey = key
					local r, g, b = MobCharge.colour(k + m.id, party, pulse, false)
					local c = Color3.fromRGB(r // 1, g // 1, b // 1)
					f.body.Color, f.arms.Color = c, c
				end
				if f.headKey ~= (k + m.id) % 4 then
					f.headKey = (k + m.id) % 4
					local r, g, b = MobCharge.colour(k + m.id, 0, 0, true)
					f.head.Color = Color3.fromRGB(r // 1, g // 1, b // 1)
				end
			end

			-- the swarm (far LOD) on this mob's own emitter
			local sw = swarmFor(m.id)
			if sw ~= nil then
				local rate = a.rate
				if m.phase == "dispersing" then
					rate = 0
				end
				local cz = m.z + depth * depthScale * 0.5
				sw.part.Size = Vector3.new(width, 2, math.max(1, depth * depthScale))
				push(sw.part, CFrame.new(ViewMap.x(centerX), SWARM_HEIGHT - sink, cz))
				if math.abs(rate - sw.rate) > 0.5 then
					sw.emitter.Rate = rate
					sw.rate = rate
				end
				local mixKey = math.floor(party * 4 + 0.5) * 8 + math.floor(pulse * 4 + 0.5)
				if sw.mixKey ~= mixKey then
					sw.mixKey = mixKey
					sw.emitter.Color = palette(party, pulse)
				end
			end

			-- dust: a trail while charging, a puff on the slam and again as the mob dissolves
			local d = dustFor(drawn)
			if d ~= nil then
				push(d.part, CFrame.new(ViewMap.x(centerX), 0.6, m.z + depth * 0.6))
				d.part.Size = Vector3.new(width * 0.8, 1, depth * 0.8)
				d.emitter.Rate = if m.phase == "walking" then DUST_RATE * m.fade else 0
				if (m.phase == "slamming" or m.phase == "dispersing") and not puffed[m.id] then
					puffed[m.id] = true
					d.emitter:Emit(level.puff)
					if sw ~= nil then
						-- the mass dissolves into a puff of its own colour
						sw.emitter:Emit(math.min(level.puff * 2, a.dots))
					end
				end
			end
		end
		usedFigures, usedMobs = figureCursor, drawn
		-- mobs that are gone (or no longer drawn) hand their emitter back
		for id in table.clone(byId) do
			if not seen[id] then
				release(id)
			end
		end
		for rank = drawn + 1, #dusts do
			dusts[rank].emitter.Rate = 0
		end
		for id in puffed do
			if not seen[id] then
				puffed[id] = nil
			end
		end
		usedEmitters = MobLod.emitterCount(drawn, levelName)

		-- one call moves every figure and emitter Part
		for i = moveCount + 1, #moveParts do
			moveParts[i] = nil :: any
			moveCFrames[i] = nil :: any
		end
		if moveCount > 0 then
			Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end

	function self.setQuality(_, name: string)
		levelName = QualityConfig.resolve(name)
		level = QualityConfig.get(levelName)
	end

	function self.quality(_): string
		return levelName
	end

	function self.counts(_)
		return { figures = usedFigures, mobs = usedMobs, emitters = usedEmitters }
	end

	function self.clear(_)
		figures:setCount(0)
		for id in table.clone(byId) do
			release(id)
		end
		for _, d in dusts do
			d.emitter.Rate = 0
		end
		table.clear(puffed)
		usedFigures, usedMobs, usedEmitters = 0, 0, 0
	end

	return self
end

return MobView
