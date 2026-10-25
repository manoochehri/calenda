--!strict
-- Draws spectator MOBS as INDIVIDUALS (issue #65, owner direction 2026-10-25: "we want random
-- individuals coming at the player", not grouped bunches). Reusable: the ambient street crowds of
-- #54 phase 2 feed it the same descriptors. The numbers come from the pure modules
-- (SpectatorScatter, MobCharge, QualityConfig, MobLod, Config.spectators.scatter); this file only
-- turns them into Instances.
--
--  FIGURES: pooled real figures (body + head + arms = 3 Parts, no accessories). Each cluster's
--   spectators stand on their own spots in a loose, jittered scatter (SpectatorScatter.place,
--   seeded from the mob id), so no two touch and no bunch forms. A figure far up the lane is
--   enlarged (SpectatorScatter.legibleScale, capped at maxScale) so it still reads. Every figure
--   of every mob moves in ONE Workspace:BulkMoveTo call per frame (Roblox docs: "provides a very
--   fast way to move large numbers of parts"; FireCFrameChanged fires only the CFrame event). Sizes
--   change only when a figure's scale step changes; colours only when they change.
--  DUST: a capped set of dust emitters on the nearest mobs (stride dust, slam and dissolve puffs).
--   Rate = dots / Lifetime is no longer used; the ParticleEmitter docs' "Number of particles = Rate
--   * Lifetime" still holds for the dust.
-- Display only. IN-ENGINE BEHAVIOUR IS UNVERIFIED (see docs/mob-waves-studio-checklist.md).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraRig = require(Shared:WaitForChild("CameraRig"))
local Config = require(Shared:WaitForChild("Config"))
local MobCharge = require(Shared:WaitForChild("MobCharge"))
local MobLod = require(Shared:WaitForChild("MobLod"))
local Pool = require(Shared:WaitForChild("Pool"))
local QualityConfig = require(Shared:WaitForChild("QualityConfig"))
local SpectatorScatter = require(Shared:WaitForChild("SpectatorScatter"))
local ViewMap = require(Shared:WaitForChild("ViewMap"))

local FIGURE_HEIGHT = 2.2 -- studs, what the legibility share is measured on
local DUST_RATE = 14 -- [default] stride dust per second on a charging mob (before fade)
local DUST_COLOR = Color3.fromRGB(214, 190, 150)
local SCALE_STEP = 0.25 -- figures are resized only when their scale moves by this much
local BODY_SIZE = Vector3.new(1.1, 1.5, 0.8)
local HEAD_SIZE = 0.95
local ARMS_SIZE = Vector3.new(1.9, 0.3, 0.3)

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
	update: (
		self: MobView,
		mobs: { Desc },
		leadZ: number,
		clock: number,
		dt: number,
		pullback: number?
	) -> (),
	rankFade: (self: MobView, id: number) -> number, -- 0 when the mob is not drawn (its tag must hide)
	setQuality: (self: MobView, name: string) -> (),
	quality: (self: MobView) -> string,
	counts: (self: MobView) -> { figures: number, mobs: number, emitters: number },
	clear: (self: MobView) -> (),
}

type Figure = {
	body: Part,
	head: Part,
	arms: Part,
	bodyKey: number,
	headKey: number,
	scaleKey: number,
}
type Dust = { part: Part, emitter: ParticleEmitter }
type Spots = { n: number, offsets: { SpectatorScatter.Offset } }

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

function MobView.new(parent: Instance, quality: string): MobView
	local folder = Instance.new("Folder")
	folder.Name = "CalendaMobs"
	folder.Parent = parent

	local scatter = Config.spectators.scatter
	local level = QualityConfig.get(quality)
	local levelName = QualityConfig.resolve(quality)
	local self = {} :: MobView

	local figures = Pool.new(function(): Figure
		local body = newPart(folder, Enum.PartType.Block, BODY_SIZE, Color3.fromRGB(214, 58, 46))
		local head = newPart(
			folder,
			Enum.PartType.Ball,
			Vector3.new(HEAD_SIZE, HEAD_SIZE, HEAD_SIZE),
			Color3.fromRGB(255, 214, 170)
		)
		local arms = newPart(folder, Enum.PartType.Block, ARMS_SIZE, Color3.fromRGB(214, 58, 46))
		return { body = body, head = head, arms = arms, bodyKey = -1, headKey = -1, scaleKey = -1 }
	end, function(f: Figure)
		f.body.Parent, f.head.Parent, f.arms.Parent = folder, folder, folder
	end, function(f: Figure)
		f.body.Parent, f.head.Parent, f.arms.Parent = nil, nil, nil
	end)

	local dusts: { Dust } = {}
	local puffed: { [number]: boolean } = {}
	local admission = MobLod.admission(level.maxMobs)
	local rankFades: { [number]: number } = {}
	local spots: { [number]: Spots } = {} -- each mob's individual spots, kept by id
	local usedFigures, usedMobs, usedEmitters = 0, 0, 0

	-- Reused per-frame arrays for BulkMoveTo.
	local moveParts: { Instance } = {}
	local moveCFrames: { CFrame } = {}
	local moveCount = 0

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

	-- The individual spots of a mob with `n` spectators, computed once per (id, n).
	local function spotsFor(id: number, n: number): { SpectatorScatter.Offset }
		local s = spots[id]
		if s == nil or s.n ~= n then
			s = { n = n, offsets = SpectatorScatter.place(n, id, scatter) }
			spots[id] = s
		end
		return s.offsets
	end

	function self.update(
		_,
		mobs: { Desc },
		leadZ: number,
		clock: number,
		dt: number,
		pullback: number?
	)
		moveCount = 0
		local sorted = table.clone(mobs)
		table.sort(sorted, function(a, b)
			return a.ahead < b.ahead
		end)
		-- Rank-based admission: only the nearest maxMobs are drawn; a farther mob waits for a free
		-- slot and fades in from 0, a displaced one fades out first (never a pop, never over the cap).
		local ids: { number } = {}
		for i, m in sorted do
			ids[i] = m.id
		end
		rankFades = admission:step(ids, dt)
		local admitted: { Desc } = {}
		for _, m in sorted do
			if rankFades[m.id] ~= nil then
				table.insert(admitted, m)
			end
		end
		sorted = admitted

		-- How many individuals each mob shows, nearest first, under the per-mob and on-screen caps.
		local pose = CameraRig.pose(0, leadZ, pullback or 1)
		local want: { { count: number, fade: number } } = {}
		local counts: { number } = {}
		local fades: { number } = {}
		local legible: { number } = {}
		for i, m in sorted do
			local n = SpectatorScatter.individuals(m.reward, levelName, scatter)
			local keep = if m.phase == "cheering" then MobCharge.streamKeep(m.age) else 1
			local fade = math.clamp(m.fade * keep * (rankFades[m.id] :: number), 0, 1)
			counts[i], fades[i] = n, fade
			want[i] = { count = n, fade = fade }
			local frac = CameraRig.screenFraction(pose, FIGURE_HEIGHT / 2, m.z, FIGURE_HEIGHT)
			legible[i] = SpectatorScatter.legibleScale(frac, scatter)
		end
		local shown = SpectatorScatter.allocate(want, levelName)

		local seen: { [number]: boolean } = {}
		local needed = 0
		for _, s in shown do
			needed += s
		end
		local figureSlots = figures:setCount(needed)
		local figureCursor, drawn = 0, 0

		for i, m in sorted do
			local count = shown[i]
			if count <= 0 then
				continue
			end
			drawn += 1
			seen[m.id] = true
			local n, fade = counts[i], fades[i]
			local offsets = spotsFor(m.id, n)
			local party = if m.phase == "cheering" then MobCharge.partyMix(m.age) else 0
			local depthScale = 1
			if m.phase == "slamming" then
				depthScale = MobCharge.slamDepth(m.age)
			end
			local pulse = math.max(m.pulse, m.glow)
			local depth = SpectatorScatter.extent(n, scatter)
			local centerX = MobLod.lateralFit(m.x, 2 * scatter.spreadHalfWidth) -- keeps figures inside the street
			local slam = if m.phase == "slamming" then MobCharge.slam(m.age) else 0
			-- the figure scale: a far figure is enlarged a step at a time so it keeps reading
			local scaleKey = math.floor(legible[i] / SCALE_STEP + 0.5)
			local scale = scaleKey * SCALE_STEP

			for k = 1, count do
				figureCursor += 1
				local f = figureSlots[figureCursor]
				if f.scaleKey ~= scaleKey then
					f.scaleKey = scaleKey
					f.body.Size = BODY_SIZE * scale
					f.head.Size = Vector3.new(HEAD_SIZE, HEAD_SIZE, HEAD_SIZE) * scale
					f.arms.Size = ARMS_SIZE * scale
				end
				local off = offsets[k]
				local dx, dz = off.dx, off.dz
				-- each individual rises out of the road as the mob's fade passes it (no pop)
				local sink = (1 - SpectatorScatter.risen(k, n, fade)) * MobCharge.SINK
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
				push(f.body, root * CFrame.new(0, 0.75 * scale, 0))
				push(f.head, root * CFrame.new(0, 1.95 * scale, 0))
				push(f.arms, root * CFrame.new(0, arm * scale, 0))
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

			-- dust: a trail while charging, a puff on the slam and again as the mob dissolves
			local d = dustFor(drawn)
			if d ~= nil then
				push(d.part, CFrame.new(ViewMap.x(centerX), 0.6, m.z + depth * 0.6))
				d.part.Size = Vector3.new(2 * scatter.spreadHalfWidth * 0.8, 1, depth * 0.8)
				d.emitter.Rate = if m.phase == "walking" then DUST_RATE * fade else 0
				if (m.phase == "slamming" or m.phase == "dispersing") and not puffed[m.id] then
					puffed[m.id] = true
					d.emitter:Emit(level.puff)
				end
			end
		end
		usedFigures, usedMobs = figureCursor, drawn
		-- mobs that are gone (or no longer drawn) forget their spots
		for id in table.clone(spots) do
			if not seen[id] then
				spots[id] = nil
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
		usedEmitters = math.min(drawn, level.maxDust)

		-- one call moves every figure and dust Part
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
		admission = MobLod.admission(level.maxMobs)
		table.clear(spots)
	end

	function self.rankFade(_, id: number): number
		return rankFades[id] or 0
	end

	function self.quality(_): string
		return levelName
	end

	function self.counts(_)
		return { figures = usedFigures, mobs = usedMobs, emitters = usedEmitters }
	end

	function self.clear(_)
		figures:setCount(0)
		for _, d in dusts do
			d.emitter.Rate = 0
		end
		table.clear(puffed)
		table.clear(spots)
		admission:clear()
		rankFades = {}
		usedFigures, usedMobs, usedEmitters = 0, 0, 0
	end

	return self
end

return MobView
