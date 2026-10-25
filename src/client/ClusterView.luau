--!strict
-- Spectator MOB tags, projectile arcs and the cheer (issue #12), drawn from primitive Parts. The
-- mobs themselves (hundreds of spectators by level of detail, the charge, the slam, the dispersal)
-- are MobView's (issue #65); this file feeds it, keeps the meter tags, and adds the telegraph
-- chevrons and the screen-edge pulse of the tension-from-the-top rules (Emergence).
-- What to draw comes from the pure modules (ClusterVisual, ClusterFeed, FeedbackMath, Effects);
-- this file only turns it into Instances. Display only: nothing here is sent to the server and
-- nothing here credits anything. Every pool is bounded (ClusterVisual / Effects capacities).
-- IN-ENGINE BEHAVIOUR IS UNVERIFIED (see the PR checklist).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClusterFeed = require(Shared:WaitForChild("ClusterFeed"))
local ClusterEvents = require(Shared:WaitForChild("ClusterEvents"))
local ClusterVisual = require(Shared:WaitForChild("ClusterVisual"))
local Config = require(Shared:WaitForChild("Config"))
local Emergence = require(Shared:WaitForChild("Emergence"))
local LayerHeights = require(Shared:WaitForChild("LayerHeights"))
local MobCharge = require(Shared:WaitForChild("MobCharge"))
local MobLod = require(Shared:WaitForChild("MobLod"))
local QualityConfig = require(Shared:WaitForChild("QualityConfig"))
local MeterDisplay = require(Shared:WaitForChild("MeterDisplay"))
local Effects = require(Shared:WaitForChild("Effects"))
local FeedbackMath = require(Shared:WaitForChild("FeedbackMath"))
local GiftVisual = require(Shared:WaitForChild("GiftVisual"))
local Pool = require(Shared:WaitForChild("Pool"))
local ShotLook = require(Shared:WaitForChild("ShotLook"))
local ViewMap = require(Shared:WaitForChild("ViewMap"))

local Bits = require(script.Parent:WaitForChild("Bits"))
local MobView = require(script.Parent:WaitForChild("MobView"))

-- Spectators are warm orange against the gray road and blue followers: one mass, strong contrast.
local SPECTATOR_COLOR = Color3.fromRGB(255, 120, 40) -- float parts only
local PARTY_COLOR = Color3.fromRGB(table.unpack(MobCharge.PARTY[1])) -- converted runners
local SPECTATOR_HEAD = Color3.fromRGB(255, 205, 150)
local BAR_BACK = Color3.fromRGB(30, 20, 45)
local BAR_FILL = Color3.fromRGB(255, 60, 160)
local BAR_DONE = Color3.fromRGB(80, 235, 120)
local NOTE_COLOR = Color3.fromRGB(table.unpack(GiftVisual.NOTE_RGB))

local METER_RATE = 14 -- [default] easing of the bar fill
local CHEVRONS = 6 -- [default] most warning chevrons at the top of the lanes at once
local CHEVRON_COLOR = Color3.fromRGB(255, 120, 40)
local EDGE_COLOR = Color3.fromRGB(255, 70, 40)
local EDGE_MAX_ALPHA = 0.35 -- [default] the pulse never hides the game
local EDGE_WIDTH = 0.07 -- [default] share of the screen width per side
local CHEVRON_ROW = 0.88 -- [default] share of the visible depth where the chevron sits
-- Live shots: covers the firing cap x the longest flight (20/s x 0.9 s = 18, +4 slack = 22), under
-- ShotLook.PROJECTILE_HARD_CAP. Extras are simply not drawn. All look knobs live in ShotLook.
local PROJECTILE_CAPACITY = ShotLook.projectileCapacity(Config.firing.cap, FeedbackMath.MAX_FLIGHT)
local FLOAT_CAPACITY = 6 -- [default]
local FLOAT_SECONDS = 1.1 -- [default]
-- Issue #50: the cartoon bump when an unfilled cluster reaches the parade. Hats and instrument
-- bits fly up and tumble: playful, no gore.
local BUMP_BITS = 7 -- [default] pieces per attack (Bits.MAX still bounds the total)
local BUMP_SPREAD = 5 -- [default] studs
local BUMP_COLORS = {
	Color3.fromRGB(255, 200, 40),
	Color3.fromRGB(235, 70, 90),
	Color3.fromRGB(70, 160, 255),
	Color3.fromRGB(255, 255, 255),
}
local RUNNER_POOL = QualityConfig.levels.high.maxStream -- the stream cap of the best level

type Member = { body: Part, head: Part }
type Group = {
	root: Part, -- invisible anchor carrying the tag
	gui: BillboardGui,
	back: Frame,
	fill: Frame,
	numeral: TextLabel,
	reward: TextLabel,
	meter: MeterDisplay.Meter, -- smoothed bar fill bound to the cluster id (cleared on hide/reset)
}
type Chevron = { left: Part, right: Part, dust: ParticleEmitter }

export type ClusterView = {
	onCluster: (self: ClusterView, payload: any) -> boolean,
	onMiss: (self: ClusterView, payload: any) -> (), -- a continuous-fire shot with no target
	onAttack: (self: ClusterView, payload: any) -> boolean, -- false for a duplicate event
	reset: (self: ClusterView) -> (),
	update: (self: ClusterView, t: number, leadX: number, leadZ: number, dt: number) -> (),
	setPullback: (self: ClusterView, pullback: number) -> (), -- the camera's pullback, for the fade
	setQuality: (self: ClusterView, name: string) -> (), -- "high" | "medium" | "low" (QualityConfig)
	threat: (self: ClusterView) -> number, -- 0..1 threat of the nearest unconverted wave (last update)
}

local ClusterView = {}

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

local function label(parent: Instance, size: UDim2, pos: UDim2, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = pos
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.2
	l.TextStrokeColor3 = Color3.fromRGB(20, 10, 30)
	l.Text = ""
	l.Parent = parent
	return l
end

local function buildGroup(folder: Folder): Group
	local root = newPart(folder, Enum.PartType.Block, Vector3.new(1, 1, 1), BAR_BACK)
	root.Transparency = 1
	-- A SMALL tag attached to the mob (issue #70): hit count, reward and a thin meter bar. It must
	-- never read as a gate, so no big floating numeral panel: gates are the standing portals.
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(88, 30)
	gui.StudsOffset = Vector3.new(0, 6, 0)
	gui.AlwaysOnTop = false -- do not cover the gate text from the high camera
	gui.MaxDistance = 120
	gui.Parent = root
	local numeral =
		label(gui, UDim2.fromScale(0.4, 0.6), UDim2.fromScale(0, 0), Color3.new(1, 1, 1))
	local reward = label(gui, UDim2.fromScale(0.6, 0.6), UDim2.fromScale(0.4, 0), BAR_DONE)
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 0.28)
	back.Position = UDim2.fromScale(0, 0.72)
	back.BackgroundColor3 = BAR_BACK
	back.BorderSizePixel = 0
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = BAR_FILL
	fill.BorderSizePixel = 0
	fill.Parent = back
	return {
		root = root,
		gui = gui,
		back = back,
		fill = fill,
		numeral = numeral,
		reward = reward,
		meter = MeterDisplay.new(),
	}
end

-- A flat warning chevron "v" pointing down the lane (two Neon bars) with a small dust emitter.
local function buildChevron(folder: Folder): Chevron
	local function arm(): Part
		local p = newPart(folder, Enum.PartType.Block, Vector3.new(6, 0.2, 1.6), CHEVRON_COLOR)
		p.Material = Enum.Material.Neon
		return p
	end
	local left, right = arm(), arm()
	local dust = Instance.new("ParticleEmitter")
	dust.Rate = 0
	dust.Lifetime = NumberRange.new(0.8, 1.4)
	dust.Speed = NumberRange.new(2, 5)
	dust.SpreadAngle = Vector2.new(40, 40)
	dust.LockedToPart = false
	dust.Color = ColorSequence.new(Color3.fromRGB(214, 190, 150))
	dust.Size = NumberSequence.new(2, 5)
	dust.Transparency = NumberSequence.new(0.5, 1)
	dust.Parent = left
	return { left = left, right = right, dust = dust }
end

function ClusterView.new(layout: any): ClusterView
	local folder = Instance.new("Folder")
	folder.Name = "CalendaSpectators"
	folder.Parent = Workspace

	-- Quality: the owner's override (player attribute "CalendaQuality", read now and on change)
	-- beats Config.debug.quality, which beats the device default (QualityConfig.pick).
	local player = Players.LocalPlayer
	local function pickQuality(): string
		local attribute = if player then player:GetAttribute("CalendaQuality") else nil
		return QualityConfig.pick(attribute, Config.debug.quality, UserInputService.TouchEnabled)
	end
	local quality = pickQuality()
	local mobs = MobView.new(folder, quality)
	if player then
		player:GetAttributeChangedSignal("CalendaQuality"):Connect(function()
			quality = pickQuality()
			mobs:setQuality(quality)
		end)
	end
	local pullback = 1
	local pulsePhase: { [number]: number } = {} -- cluster id -> running alert pulse phase
	local approachThreat = 0 -- Emergence.threat of the nearest unconverted mob, drawn share (music)
	local chevronPool = Pool.new(function(): Chevron
		return buildChevron(folder)
	end, function(c: Chevron)
		c.left.Parent, c.right.Parent = folder, folder
	end, function(c: Chevron)
		c.left.Parent, c.right.Parent = nil, nil
		c.dust.Rate = 0
	end)
	-- Screen-edge pulse as a wave closes in: two thin gradient strips (display only).
	local edgeLeft: Frame? = nil
	local edgeRight: Frame? = nil
	do
		local playerGui = if Players.LocalPlayer
			then Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
			else nil
		if playerGui ~= nil then
			local gui = Instance.new("ScreenGui")
			gui.Name = "CalendaThreat"
			gui.ResetOnSpawn = false
			gui.IgnoreGuiInset = true
			gui.DisplayOrder = 1
			gui.Parent = playerGui
			local function strip(left: boolean): Frame
				local f = Instance.new("Frame")
				f.Size = UDim2.fromScale(EDGE_WIDTH, 1)
				f.Position = UDim2.fromScale(if left then 0 else 1 - EDGE_WIDTH, 0)
				f.BackgroundColor3 = EDGE_COLOR
				f.BackgroundTransparency = 1
				f.BorderSizePixel = 0
				local g = Instance.new("UIGradient")
				g.Transparency = NumberSequence.new(if left then 0 else 1, if left then 1 else 0)
				g.Parent = f
				f.Parent = gui
				return f
			end
			edgeLeft, edgeRight = strip(true), strip(false)
		end
	end

	local tracker = ClusterVisual.new(layout)

	local groups = Pool.new(function(): Group
		return buildGroup(folder)
	end, function(g: Group)
		g.root.Parent = folder
	end, function(g: Group)
		g.root.Parent = nil
		g.meter:clear()
	end)
	-- Runners: single spectators hopping into the parade.
	local runnerPool = Pool.new(function(): Member
		return {
			body = newPart(folder, Enum.PartType.Block, Vector3.new(1.4, 2, 1.4), PARTY_COLOR),
			head = newPart(folder, Enum.PartType.Ball, Vector3.new(1.3, 1.3, 1.3), SPECTATOR_HEAD),
		}
	end, function(m: Member)
		m.body.Parent, m.head.Parent = folder, folder
	end, function(m: Member)
		m.body.Parent, m.head.Parent = nil, nil
	end)

	type Flight = {
		id: number?, -- nil for a miss
		variant: string,
		hits: number,
		fromX: number,
		fromZ: number,
		miss: boolean,
		n: number,
	}
	local flights: Effects.Effects<Flight> = Effects.new(PROJECTILE_CAPACITY)
	-- A shot (issue #67): a glowing Neon core inside a larger translucent halo, a Trail, and up to
	-- three extra parts whose meaning depends on the look (note stem; heart lobes; snack ribbon and
	-- twisted ends, issue #20). Pooled, never destroyed; hard capped by PROJECTILE_CAPACITY.
	type Shot = {
		body: Part,
		halo: Part,
		trail: Trail,
		a0: Attachment,
		a1: Attachment,
		extras: { Part },
	}
	local projectilePool = Pool.new(function(): Shot
		local body = newPart(folder, Enum.PartType.Ball, Vector3.one, NOTE_COLOR)
		body.Material = Enum.Material.Neon
		local halo = newPart(folder, Enum.PartType.Ball, Vector3.one, NOTE_COLOR)
		halo.Material = Enum.Material.Neon
		halo.Transparency = ShotLook.HALO_TRANSPARENCY
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Parent, a1.Parent = body, body
		local trail = Instance.new("Trail")
		trail.Attachment0, trail.Attachment1 = a0, a1
		trail.Lifetime = ShotLook.TRAIL_SECONDS
		trail.LightEmission = 1
		trail.MinLength = 0.05
		trail.Transparency = NumberSequence.new(ShotLook.TRAIL_ALPHA, 1)
		trail.Parent = body
		local extras = {}
		for _ = 1, 3 do
			local e = newPart(folder, Enum.PartType.Block, Vector3.one, NOTE_COLOR)
			e.Material = Enum.Material.Neon
			table.insert(extras, e)
		end
		return { body = body, halo = halo, trail = trail, a0 = a0, a1 = a1, extras = extras }
	end, function(p: Shot)
		p.body.Parent, p.halo.Parent = folder, folder
		p.trail:Clear() -- a recycled shot must not streak from its previous flight
	end, function(p: Shot)
		p.body.Parent, p.halo.Parent = nil, nil
		for _, e in p.extras do
			e.Parent = nil
		end
	end)

	-- Muzzle pops at the lead and impact bursts on the target (issue #67). Display only, capped.
	local muzzles: Effects.Effects<{ variant: string }> = Effects.new(ShotLook.MUZZLE_CAPACITY)
	local impacts: Effects.Effects<{ x: number, z: number, variant: string }> =
		Effects.new(ShotLook.IMPACT_CAPACITY)
	local function popPart(): Part
		local p = newPart(folder, Enum.PartType.Ball, Vector3.one, NOTE_COLOR)
		p.Material = Enum.Material.Neon
		return p
	end
	local muzzlePool = Pool.new(popPart, function(p: Part)
		p.Parent = folder
	end, function(p: Part)
		p.Parent = nil
	end)
	local impactPool = Pool.new(popPart, function(p: Part)
		p.Parent = folder
	end, function(p: Part)
		p.Parent = nil
	end)
	-- Aimed shots that have not landed yet: when `at` passes, the burst and squash play. Bounded by
	-- the projectile capacity (a launch past it simply has no impact), cleared on reset.
	local pending: { { at: number, id: number, variant: string } } = {}
	-- Cluster id -> clock time of its latest impact (squash). One slot per layout cluster.
	local impactAt: { [number]: number } = {}

	-- Gift catches: cluster id -> clock time the gift lands. One slot per layout cluster, so it is
	-- bounded; cleared on reset. Visual only.
	local catches: { [number]: number } = {}

	type Float = { x: number, z: number, text: string }
	local floats: Effects.Effects<Float> = Effects.new(FLOAT_CAPACITY)
	local floatPool = Pool.new(function(): { part: Part, text: TextLabel }
		local p = newPart(folder, Enum.PartType.Block, Vector3.new(1, 1, 1), SPECTATOR_COLOR)
		p.Transparency = 1
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(160, 70)
		gui.AlwaysOnTop = true
		gui.Parent = p
		return {
			part = p,
			text = label(gui, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), BAR_DONE),
		}
	end, function(f)
		f.part.Parent = folder
	end, function(f)
		f.part.Parent = nil
	end)

	local bits = Bits.new(folder)
	local shotBudget = ClusterEvents.budget(ClusterEvents.EVENTS_PER_FRAME)
	local attackBudget = ClusterEvents.budget(ClusterEvents.ATTACKS_PER_FRAME)
	local attacked = ClusterEvents.dedupe()

	local clock, lastT, lastLeadX, lastLeadZ = 0, 0, 0, 0
	local currentPositions: { [number]: { x: number, z: number } } = {}
	local view = {} :: ClusterView

	function view.onCluster(_, payload: any)
		local shot = ClusterFeed.decode(payload)
		if shot == nil then
			return false
		end
		local result = tracker:shot(shot, lastT)
		local converted = result.filled
		local at = currentPositions[shot.id]
		-- The tracker above is always fed, so a flood never loses a fill. Only the visuals are
		-- budgeted (issue #60); the +N plays on the first fill whatever else is suppressed.
		local plan = ClusterEvents.plan({
			accepted = result.accepted,
			alreadyFilled = result.alreadyFilled,
			filled = result.filled,
			reward = result.reward,
			visible = at ~= nil,
			inBudget = shotBudget:take(),
		})
		if plan.float and result.reward then
			floats:start(clock, FLOAT_SECONDS, {
				x = result.x,
				z = result.z,
				text = string.format("+%d", result.reward),
			})
		end
		if not plan.projectile or at == nil then
			return converted -- over budget, a duplicate, or a cluster that is gone: no projectile
		end
		local variant = FeedbackMath.variant(shot.shot, shot.hits)
		local dist = math.sqrt((at.x - lastLeadX) ^ 2 + (at.z - lastLeadZ) ^ 2)
		local seconds = FeedbackMath.flightSeconds(dist)
		if
			flights:start(clock, seconds, {
				id = shot.id,
				variant = variant,
				hits = shot.hits,
				fromX = lastLeadX,
				fromZ = lastLeadZ,
				miss = false,
				n = shot.hits,
			})
		then
			muzzles:start(clock, ShotLook.MUZZLE_SECONDS, { variant = variant })
			if #pending < PROJECTILE_CAPACITY then
				table.insert(pending, { at = clock + seconds, id = shot.id, variant = variant })
			end
		end
		if variant ~= "note" then
			catches[shot.id] = clock + seconds
		end
		return converted
	end

	-- A continuous-fire shot with no target (issue #67): flies straight ahead and fades. Display
	-- only: no tracker, no catch, no impact; it shares the per-frame visual budget.
	function view.onMiss(_, payload: any)
		local miss = ClusterFeed.decodeMiss(payload)
		if miss == nil or not shotBudget:take() then
			return
		end
		-- heart / snack alternate per gift, as for hits (a gift is every Nth shot number)
		local variant = FeedbackMath.variant(miss.shot, miss.n // Config.giftEveryNthShot)
		if
			flights:start(clock, ShotLook.MISS_SECONDS, {
				id = nil,
				variant = variant,
				hits = 0,
				fromX = lastLeadX,
				fromZ = lastLeadZ,
				miss = true,
				n = miss.n,
			})
		then
			muzzles:start(clock, ShotLook.MUZZLE_SECONDS, { variant = variant })
		end
	end

	-- An unfilled cluster reached the parade (issue #50): a cartoon bump of flying hats and
	-- instrument bits at the lead. The counter wobble, shake and flash are driven by Main from the same
	-- Event. A repeated event for the same cluster, or a flood, plays nothing extra.
	function view.onAttack(_, payload: any): boolean
		if type(payload) ~= "table" then
			return false
		end
		local id = if type(payload.id) == "number" then payload.id else nil
		if not attacked:first(id) then
			return false -- a duplicate event: nothing again, not even the counter wobble
		end
		-- The server's attack Event is what starts the mob's slam (issue #65): the pure tracker keeps
		-- it pinned at the front of the parade until now (or a short fallback), then slams and
		-- disperses it. The bump below is the same one as before, not a second one.
		if id ~= nil then
			tracker:attack(id, lastT)
		end
		if not attackBudget:take() then
			return true
		end
		bits:burst(
			"prop",
			Vector3.new(ViewMap.x(lastLeadX), 3, lastLeadZ),
			BUMP_BITS,
			BUMP_SPREAD,
			BUMP_COLORS
		)
		return true
	end

	function view.setPullback(_, p: number)
		if type(p) == "number" and p == p and p > 0 then
			pullback = p
		end
	end

	function view.setQuality(_, name: string)
		quality = QualityConfig.resolve(name)
		mobs:setQuality(quality)
	end

	function view.threat(_): number
		return approachThreat
	end

	function view.reset(_)
		tracker:reset()
		mobs:clear()
		chevronPool:setCount(0)
		table.clear(pulsePhase)
		if edgeLeft ~= nil and edgeRight ~= nil then
			edgeLeft.BackgroundTransparency, edgeRight.BackgroundTransparency = 1, 1
		end
		groups:setCount(0) -- hides every slot, which clears its bar
		flights:clear()
		muzzles:clear()
		impacts:clear()
		table.clear(pending)
		table.clear(impactAt)
		floats:clear()
		bits:clear()
		attacked:reset()
		table.clear(catches)
		currentPositions = {}
	end

	function view.update(_, t: number, leadX: number, leadZ: number, dt: number)
		clock += dt
		shotBudget:newFrame()
		attackBudget:newFrame()
		bits:update(dt)
		lastT, lastLeadX, lastLeadZ = t, leadX, leadZ
		local views = tracker:views(t, leadX, leadZ)

		local gs = groups:setCount(#views)
		local runnerViews = {}
		currentPositions = {}
		local depth = Emergence.visibleDepthAhead(pullback)
		local descs: { MobView.Desc } = {}
		local alerts: { { ahead: number, x: number, alpha: number } } = {}
		local worstThreat = 0
		approachThreat = 0
		for i, v in views do
			-- Where the mob's body is (its front is v.z): shots and the +N aim at the middle.
			local _, mobDepth = MobLod.footprint(MobLod.mobSize(v.reward, quality))
			local midZ = v.z + mobDepth * 0.5
			currentPositions[v.id] = { x = v.x, z = midZ }
			local fade = Emergence.fade(v.ahead, depth)
			local g = gs[i]
			g.root.Position = Vector3.new(ViewMap.x(v.x), 1, midZ)
			local caughtAt = catches[v.id]
			local glow, catchHop = 0, 0
			if
				caughtAt ~= nil
				and clock - caughtAt > GiftVisual.CATCH_SECONDS + GiftVisual.STAGGER_SECONDS * 4
			then
				catches[v.id] = nil
				caughtAt = nil
			end
			if caughtAt ~= nil then -- the gift landed: the mob hops and flashes
				local c = GiftVisual.catch(clock - caughtAt, 1)
				catchHop, glow = c.hop, c.glow
			end
			-- Impact squash (issue #67): the whole mob dips for a moment after a shot lands.
			local hitAt = impactAt[v.id]
			local sq = ShotLook.squash(if hitAt ~= nil then clock - hitAt else -1)
			local dip = math.clamp((1 - sq.y) / ShotLook.SQUASH_AMOUNT, 0, 1)
			-- Alert pulse: an unconverted mob flashes faster as it closes in on the parade.
			local pulse = 0
			if v.phase == "walking" then
				local threat = Emergence.threat(v.ahead)
				local phase = (pulsePhase[v.id] or 0) + dt * Emergence.pulseRate(threat)
				pulsePhase[v.id] = phase
				pulse = Emergence.pulse(threat, phase) * fade
				worstThreat = math.max(worstThreat, pulse)
				approachThreat = math.max(approachThreat, threat * fade)
				table.insert(
					alerts,
					{ ahead = v.ahead, x = v.x, alpha = Emergence.telegraph(v.ahead, depth) }
				)
			end
			table.insert(descs, {
				id = v.id,
				x = v.x,
				z = v.z,
				reward = v.reward,
				ahead = v.ahead,
				fade = fade,
				phase = v.phase,
				phaseT = v.phaseT,
				age = v.age,
				pulse = pulse,
				dip = dip,
				hop = catchHop,
				glow = glow,
			})
			g.fill.Size = UDim2.fromScale(g.meter:step(v.id, v.fill, dt, METER_RATE), 1)
			local done = v.phase == "cheering"
			g.fill.BackgroundColor3 = if done then BAR_DONE else BAR_FILL
			g.numeral.Text = if done then "" else string.format("%d", v.remaining)
			g.reward.Text = string.format("+%d", v.reward)
			for _, r in v.runners do
				table.insert(runnerViews, r)
			end
		end
		debug.profilebegin("Calenda/Mobs")
		mobs:update(descs, leadZ, clock, dt)
		debug.profileend()
		-- Tags only for DRAWN mobs (a mob waiting for a slot has no tag) and not while it slams.
		for i, v in views do
			gs[i].gui.Enabled = Emergence.fade(v.ahead, depth) > 0.5
				and mobs:rankFade(v.id) > 0.5
				and v.phase ~= "dispersing"
				and v.phase ~= "slamming"
		end

		-- Screen-edge pulse: the nearest unconverted wave tints the left and right edges.
		if edgeLeft ~= nil and edgeRight ~= nil then
			local a = 1 - EDGE_MAX_ALPHA * worstThreat
			edgeLeft.BackgroundTransparency, edgeRight.BackgroundTransparency = a, a
		end

		-- Telegraph: warning chevrons at the top of the lane while a wave is about to appear.
		table.sort(alerts, function(a, b)
			return a.ahead < b.ahead
		end)
		local shownChevrons: { { x: number, alpha: number } } = {}
		for _, al in alerts do
			if al.alpha > 0.02 and #shownChevrons < CHEVRONS then
				local dupe = false
				for _, o in shownChevrons do
					if math.abs(o.x - al.x) < 4 then
						dupe = true -- same lane: one chevron is enough
					end
				end
				if not dupe then
					table.insert(shownChevrons, { x = al.x, alpha = al.alpha })
				end
			end
		end
		local cs = chevronPool:setCount(#shownChevrons)
		for i, c in cs do
			local sc = shownChevrons[i]
			local blink = 0.55 + 0.45 * math.sin(clock * 9)
			local z = leadZ + depth * CHEVRON_ROW
			local y = LayerHeights.TELEGRAPH - 0.1
			local tr = 1 - sc.alpha * blink
			-- two bars forming a "v" whose apex points down the lane (Emergence.chevronBars, tested);
			-- the lateral position goes through ViewMap.x once, the shape is symmetric
			local bars = Emergence.chevronBars(ViewMap.x(sc.x), z)
			c.left.Size = Vector3.new(bars[1].length, 0.2, bars[1].width)
			c.right.Size = Vector3.new(bars[2].length, 0.2, bars[2].width)
			c.left.CFrame = CFrame.new(bars[1].x, y, bars[1].z) * CFrame.Angles(0, bars[1].yaw, 0)
			c.right.CFrame = CFrame.new(bars[2].x, y, bars[2].z) * CFrame.Angles(0, bars[2].yaw, 0)
			c.left.Transparency, c.right.Transparency = tr, tr
			c.dust.Rate = 12 * sc.alpha
		end

		local rs = runnerPool:setCount(
			math.min(#runnerViews, RUNNER_POOL, QualityConfig.get(quality).maxStream)
		)
		for i, m in rs do
			local r = runnerViews[i]
			m.body.Position = Vector3.new(ViewMap.x(r.x), 1 + r.y, r.z)
			m.head.Position = Vector3.new(ViewMap.x(r.x), 2.6 + r.y, r.z)
		end

		-- Aimed shots that have landed: impact burst and squash on the target group (issue #67).
		local keep = 0
		for _, p in pending do
			if clock >= p.at then
				local where = currentPositions[p.id]
				if where ~= nil then
					impactAt[p.id] = clock
					impacts:start(
						clock,
						ShotLook.IMPACT_SECONDS,
						{ x = where.x, z = where.z, variant = p.variant }
					)
				end
			else
				keep += 1
				pending[keep] = p
			end
		end
		for i = #pending, keep + 1, -1 do
			pending[i] = nil
		end

		local live = flights:active(clock)
		local ps = projectilePool:setCount(#live)
		for i, p in ps do
			local f = live[i]
			local look = ShotLook.LOOKS[f.data.variant] or ShotLook.LOOKS.note
			local to = if f.data.id ~= nil then currentPositions[f.data.id] else nil
			local gone = not f.data.miss and to == nil -- the target left: hide, never retarget
			local alpha = 1
			local x, y, z = 0.0, 0.0, 0.0
			local size = look.size * ShotLook.pulse(f.f)
			if f.data.miss then
				local m = ShotLook.miss(f.f, f.data.n)
				x, y, z = ViewMap.x(f.data.fromX + m.dx), 2.5 + m.dy, f.data.fromZ + m.dz
				alpha, size = m.alpha, size * m.scale
			elseif to ~= nil then
				x, y, z = FeedbackMath.arc(
					ViewMap.x(f.data.fromX),
					2.5,
					f.data.fromZ,
					ViewMap.x(to.x),
					3,
					to.z,
					f.f,
					FeedbackMath.ARC_HEIGHT
				)
			end
			local gift = f.data.variant == "snack"
			local core = look.core
			local glow = look.glow
			if gift then
				local w = GiftVisual.WRAPPERS[GiftVisual.look(f.data.hits).wrapper]
				core = w
			end
			local coreColor = Color3.fromRGB(core[1], core[2], core[3])
			local glowColor = Color3.fromRGB(glow[1], glow[2], glow[3])
			local fade = 1 - alpha
			p.body.Transparency = if gone then 1 else fade
			p.halo.Transparency = if gone
				then 1
				else ShotLook.HALO_TRANSPARENCY + (1 - ShotLook.HALO_TRANSPARENCY) * fade
			p.trail.Enabled = not gone and alpha > 0.15
			p.trail.Color = ColorSequence.new(glowColor)
			local half = size * ShotLook.TRAIL_WIDTH / 2
			p.a0.Position, p.a1.Position = Vector3.new(0, half, 0), Vector3.new(0, -half, 0)
			p.body.Color, p.halo.Color = coreColor, glowColor
			p.halo.Size = Vector3.one * size * ShotLook.HALO_SCALE
			p.halo.Position = Vector3.new(x, y, z)
			for _, e in p.extras do
				e.Parent = nil
			end
			if gone then
				continue
			end
			if gift then
				-- A wrapped treat: a cylinder roll with a ribbon and twisted ends, tumbling; scaled
				-- up by the look (issue #20 shapes, issue #67 size).
				local k = look.size / GiftVisual.TREAT_THICK
				local at = CFrame.new(x, y, z)
					* CFrame.Angles(
						GiftVisual.tumble(f.f) * (GiftVisual.look(f.data.hits).spin / 9),
						0.6,
						0
					)
				local halfLen = GiftVisual.TREAT_LENGTH / 2 * k
				p.body.Shape = Enum.PartType.Cylinder
				p.body.Size = Vector3.new(halfLen * 1.3, size, size)
				p.body.CFrame = at
				local stripe, twistA, twistB = p.extras[1], p.extras[2], p.extras[3]
				stripe.Shape = Enum.PartType.Cylinder
				stripe.Size = Vector3.new(0.4 * k, size + 0.1, size + 0.1)
				stripe.Color = Color3.new(1, 1, 1)
				stripe.CFrame = at
				for _, tw in { twistA, twistB } do
					tw.Shape = Enum.PartType.Block
					tw.Size = Vector3.new(0.5 * k, 0.9 * k, 0.2 * k)
					tw.Color = coreColor
				end
				twistA.CFrame = at * CFrame.new(halfLen * 0.8, 0, 0) * CFrame.Angles(0.5, 0, 0)
				twistB.CFrame = at * CFrame.new(-halfLen * 0.8, 0, 0) * CFrame.Angles(-0.5, 0, 0)
				stripe.Parent, twistA.Parent, twistB.Parent = folder, folder, folder
			else
				p.body.Shape = Enum.PartType.Ball
				p.body.Size = Vector3.one * size
				p.body.Position = Vector3.new(x, y, z)
				if f.data.variant == "heart" then
					-- Two lobes on top of the pink core read as a heart from the high camera.
					for li = 2, 3 do
						local lobe = p.extras[li]
						lobe.Shape = Enum.PartType.Ball
						lobe.Size = Vector3.one * size * 0.62
						lobe.Color = coreColor
						lobe.Position = Vector3.new(
							x + (if li == 2 then -0.3 else 0.3) * size,
							y + 0.42 * size,
							z
						)
						lobe.Transparency = fade
						lobe.Parent = folder
					end
				else
					-- A note: a gold stem standing on the glowing head.
					local stem = p.extras[1]
					stem.Shape = Enum.PartType.Block
					stem.Size = Vector3.new(0.22 * size, 1.1 * size, 0.22 * size)
					stem.Color = coreColor
					stem.Position = Vector3.new(x + 0.4 * size, y + 0.6 * size, z)
					stem.Transparency = fade
					stem.Parent = folder
				end
			end
		end

		-- Muzzle pops at the lead: a quick swell with a tiny recoil bob (the pop moves, never the
		-- avatar) (issue #67).
		local mz = muzzles:active(clock)
		local mps = muzzlePool:setCount(#mz)
		for i, p in mps do
			local m = mz[i]
			local pop = ShotLook.pop(m.f)
			local look = ShotLook.LOOKS[m.data.variant] or ShotLook.LOOKS.note
			p.Color = Color3.fromRGB(look.glow[1], look.glow[2], look.glow[3])
			p.Size = Vector3.one * ShotLook.MUZZLE_SIZE * pop.scale
			p.Transparency = 1 - pop.alpha * 0.85
			p.Position = Vector3.new(
				ViewMap.x(lastLeadX),
				ShotLook.MUZZLE_HEIGHT,
				lastLeadZ + ShotLook.MUZZLE_FORWARD - ShotLook.recoil(m.f)
			)
		end

		-- Impact bursts on the target group.
		local im = impacts:active(clock)
		local ips = impactPool:setCount(#im)
		for i, p in ips do
			local m = im[i]
			local pop = ShotLook.pop(m.f)
			local look = ShotLook.LOOKS[m.data.variant] or ShotLook.LOOKS.note
			p.Color = Color3.fromRGB(look.core[1], look.core[2], look.core[3])
			p.Size = Vector3.one * ShotLook.IMPACT_SIZE * pop.scale
			p.Transparency = 1 - pop.alpha * 0.8
			p.Position = Vector3.new(ViewMap.x(m.data.x), ShotLook.IMPACT_HEIGHT, m.data.z)
		end

		local fl = floats:active(clock)
		local fs = floatPool:setCount(#fl)
		for i, item in fs do
			local f = fl[i]
			local m = FeedbackMath.floatText(f.f)
			item.part.Position = Vector3.new(ViewMap.x(f.data.x), 12 + m.dy, f.data.z)
			item.text.Text = f.data.text
			item.text.TextTransparency = 1 - m.alpha
			item.text.TextStrokeTransparency = 1 - m.alpha * 0.8
		end
	end

	return view
end

return ClusterView
