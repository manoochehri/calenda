--!strict
-- Spectator clusters, projectile arcs and the cheer (issue #12), drawn from primitive Parts.
-- What to draw comes from the pure modules (ClusterVisual, ClusterFeed, FeedbackMath, Effects);
-- this file only turns it into Instances. Display only: nothing here is sent to the server and
-- nothing here credits anything. Every pool is bounded (ClusterVisual / Effects capacities).
-- IN-ENGINE BEHAVIOUR IS UNVERIFIED (see the PR checklist).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClusterFeed = require(Shared:WaitForChild("ClusterFeed"))
local ClusterEvents = require(Shared:WaitForChild("ClusterEvents"))
local ClusterVisual = require(Shared:WaitForChild("ClusterVisual"))
local MeterDisplay = require(Shared:WaitForChild("MeterDisplay"))
local Effects = require(Shared:WaitForChild("Effects"))
local FeedbackMath = require(Shared:WaitForChild("FeedbackMath"))
local GiftVisual = require(Shared:WaitForChild("GiftVisual"))
local Pool = require(Shared:WaitForChild("Pool"))
local ViewMap = require(Shared:WaitForChild("ViewMap"))

local Bits = require(script.Parent:WaitForChild("Bits"))

-- Spectators are warm orange against the gray road and blue followers: one mass, strong contrast.
local SPECTATOR_COLOR = Color3.fromRGB(255, 120, 40)
local SPECTATOR_HEAD = Color3.fromRGB(255, 205, 150)
local BAR_BACK = Color3.fromRGB(30, 20, 45)
local BAR_FILL = Color3.fromRGB(255, 60, 160)
local BAR_DONE = Color3.fromRGB(80, 235, 120)
local NOTE_COLOR = Color3.fromRGB(table.unpack(GiftVisual.NOTE_RGB))
local TREAT_STRIPE = Color3.fromRGB(255, 255, 255)
local CATCH_FLASH = Color3.fromRGB(255, 255, 255)

local METER_RATE = 14 -- [default] easing of the bar fill
local CHEER_HOP = 0.9 -- [default] studs
local CHEER_RATE = 12 -- [default] radians/second
local PROJECTILE_CAPACITY = 16 -- [default] live shots; extras are simply not drawn
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
local RUNNER_POOL = ClusterVisual.MAX_VISIBLE_CLUSTERS * ClusterVisual.RUNNERS

type Member = { body: Part, head: Part }
type Group = {
	root: Part, -- invisible anchor carrying the bar
	members: { Member },
	back: Frame,
	fill: Frame,
	numeral: TextLabel,
	reward: TextLabel,
	meter: MeterDisplay.Meter, -- smoothed bar fill bound to the cluster id (cleared on hide/reset)
}

export type ClusterView = {
	onCluster: (self: ClusterView, payload: any) -> (),
	onAttack: (self: ClusterView, payload: any) -> boolean, -- false for a duplicate event
	reset: (self: ClusterView) -> (),
	update: (self: ClusterView, t: number, leadX: number, leadZ: number, dt: number) -> (),
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
	local root = newPart(folder, Enum.PartType.Block, Vector3.new(1, 1, 1), SPECTATOR_COLOR)
	root.Transparency = 1
	local members: { Member } = {}
	for _ = 1, ClusterVisual.MAX_MEMBERS do
		local body = newPart(folder, Enum.PartType.Block, Vector3.new(1.4, 2, 1.4), SPECTATOR_COLOR)
		local head = newPart(folder, Enum.PartType.Ball, Vector3.new(1.3, 1.3, 1.3), SPECTATOR_HEAD)
		table.insert(members, { body = body, head = head })
	end
	-- A SMALL tag attached to the group (issue #70): hit count, reward and a thin meter bar. It must
	-- never read as a gate, so no big floating numeral panel: gates are the standing portals.
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(88, 30)
	gui.StudsOffset = Vector3.new(0, 4, 0)
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
		members = members,
		back = back,
		fill = fill,
		numeral = numeral,
		reward = reward,
		meter = MeterDisplay.new(),
	}
end

function ClusterView.new(layout: any): ClusterView
	local folder = Instance.new("Folder")
	folder.Name = "CalendaSpectators"
	folder.Parent = Workspace

	local tracker = ClusterVisual.new(layout)

	local groups = Pool.new(function(): Group
		return buildGroup(folder)
	end, function(g: Group)
		g.root.Parent = folder
	end, function(g: Group)
		g.root.Parent = nil
		g.meter:clear()
		for _, m in g.members do
			m.body.Parent = nil
			m.head.Parent = nil
		end
	end)
	-- Runners: single spectators hopping into the parade.
	local runnerPool = Pool.new(function(): Member
		return {
			body = newPart(folder, Enum.PartType.Block, Vector3.new(1.4, 2, 1.4), SPECTATOR_COLOR),
			head = newPart(folder, Enum.PartType.Ball, Vector3.new(1.3, 1.3, 1.3), SPECTATOR_HEAD),
		}
	end, function(m: Member)
		m.body.Parent, m.head.Parent = folder, folder
	end, function(m: Member)
		m.body.Parent, m.head.Parent = nil, nil
	end)

	type Flight = { id: number, variant: string, hits: number, fromX: number, fromZ: number }
	local flights: Effects.Effects<Flight> = Effects.new(PROJECTILE_CAPACITY)
	-- A shot is one body Part (a ball for a note); a gift also shows its wrapped-treat extras:
	-- a ribbon stripe and two twisted ends (issue #20). Pooled, never destroyed.
	type Shot = { body: Part, extras: { Part } }
	local projectilePool = Pool.new(function(): Shot
		local body = newPart(folder, Enum.PartType.Ball, Vector3.new(1, 1, 1), NOTE_COLOR)
		local stripe = newPart(
			folder,
			Enum.PartType.Cylinder,
			Vector3.new(0.4, GiftVisual.TREAT_THICK + 0.1, GiftVisual.TREAT_THICK + 0.1),
			TREAT_STRIPE
		)
		local twistA = newPart(folder, Enum.PartType.Block, Vector3.new(0.5, 0.9, 0.2), NOTE_COLOR)
		local twistB = newPart(folder, Enum.PartType.Block, Vector3.new(0.5, 0.9, 0.2), NOTE_COLOR)
		return { body = body, extras = { stripe, twistA, twistB } }
	end, function(p: Shot)
		p.body.Parent = folder
	end, function(p: Shot)
		p.body.Parent = nil
		for _, e in p.extras do
			e.Parent = nil
		end
	end)

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
			return
		end
		local result = tracker:shot(shot, lastT)
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
			return -- over budget, a duplicate, or a cluster that is gone: no projectile
		end
		local variant = FeedbackMath.variant(shot.shot, shot.hits)
		local dist = math.sqrt((at.x - lastLeadX) ^ 2 + (at.z - lastLeadZ) ^ 2)
		flights:start(clock, FeedbackMath.flightSeconds(dist), {
			id = shot.id,
			variant = variant,
			hits = shot.hits,
			fromX = lastLeadX,
			fromZ = lastLeadZ,
		})
		if variant ~= "note" then
			catches[shot.id] = clock + FeedbackMath.flightSeconds(dist)
		end
	end

	-- An unfilled cluster reached the parade (issue #50): a cartoon bump of flying hats and
	-- instrument bits at the lead. The HP bar, shake and flash are driven by Main from the same
	-- Event. A repeated event for the same cluster, or a flood, plays nothing extra.
	function view.onAttack(_, payload: any): boolean
		if type(payload) ~= "table" then
			return false
		end
		local id = if type(payload.id) == "number" then payload.id else nil
		if not attacked:first(id) then
			return false -- a duplicate event: nothing again, not even the HP shake
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

	function view.reset(_)
		tracker:reset()
		groups:setCount(0) -- hides every slot, which clears its bar
		flights:clear()
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
		for i, v in views do
			currentPositions[v.id] = { x = v.x, z = v.z }
			local g = gs[i]
			g.root.Position = Vector3.new(ViewMap.x(v.x), 1, v.z)
			local caughtAt = catches[v.id]
			if
				caughtAt ~= nil
				and clock - caughtAt
					> GiftVisual.CATCH_SECONDS + GiftVisual.STAGGER_SECONDS * v.members
			then
				catches[v.id] = nil
				caughtAt = nil
			end
			for mi, m in g.members do
				if mi <= v.members then
					local ox, oz = ClusterVisual.memberOffset(mi, v.members)
					local hop = if v.phase == "cheering"
						then CHEER_HOP * math.abs(math.sin(clock * CHEER_RATE + mi))
						else 0.2 * math.abs(math.sin(clock * 6 + mi))
					local glow = 0
					if caughtAt ~= nil then -- the gift landed: the group hops and flashes, in a ripple
						local c = GiftVisual.catch(clock - caughtAt, mi)
						hop += c.hop
						glow = c.glow
					end
					m.body.Color = SPECTATOR_COLOR:Lerp(CATCH_FLASH, glow * 0.7)
					m.body.Position = Vector3.new(ViewMap.x(v.x + ox), 1 + hop, v.z + oz)
					m.head.Position = Vector3.new(ViewMap.x(v.x + ox), 2.6 + hop, v.z + oz)
					m.body.Parent, m.head.Parent = folder, folder
				else
					m.body.Parent, m.head.Parent = nil, nil
				end
			end
			g.fill.Size = UDim2.fromScale(g.meter:step(v.id, v.fill, dt, METER_RATE), 1)
			local done = v.phase == "cheering"
			g.fill.BackgroundColor3 = if done then BAR_DONE else BAR_FILL
			g.numeral.Text = if done then "" else string.format("%d", v.remaining)
			g.reward.Text = string.format("+%d", v.reward)
			for _, r in v.runners do
				table.insert(runnerViews, r)
			end
		end

		local rs = runnerPool:setCount(math.min(#runnerViews, RUNNER_POOL))
		for i, m in rs do
			local r = runnerViews[i]
			m.body.Position = Vector3.new(ViewMap.x(r.x), 1 + r.y, r.z)
			m.head.Position = Vector3.new(ViewMap.x(r.x), 2.6 + r.y, r.z)
		end

		local live = flights:active(clock)
		local ps = projectilePool:setCount(#live)
		for i, p in ps do
			local f = live[i]
			local to = currentPositions[f.data.id]
			local gift = f.data.variant ~= "note"
			for _, e in p.extras do
				e.Parent = if gift and to ~= nil then folder else nil
			end
			if to == nil then
				p.body.Transparency = 1
			else
				p.body.Transparency = 0
				local x, y, z = FeedbackMath.arc(
					ViewMap.x(f.data.fromX),
					2.5,
					f.data.fromZ,
					ViewMap.x(to.x),
					3,
					to.z,
					f.f,
					FeedbackMath.ARC_HEIGHT
				)
				if gift then
					-- A wrapped treat: a cylinder roll with a ribbon and twisted ends, tumbling.
					local look = GiftVisual.look(f.data.hits)
					local w = GiftVisual.WRAPPERS[look.wrapper]
					local wrap = Color3.fromRGB(w[1], w[2], w[3])
					local at = CFrame.new(x, y, z)
						* CFrame.Angles(GiftVisual.tumble(f.f) * (look.spin / 9), 0.6, 0)
					local half = GiftVisual.TREAT_LENGTH / 2
					p.body.Shape = Enum.PartType.Cylinder
					p.body.Size =
						Vector3.new(half * 1.3, GiftVisual.TREAT_THICK, GiftVisual.TREAT_THICK)
					p.body.Color = wrap
					p.body.CFrame = at
					p.extras[1].CFrame = at
					p.extras[2].Color, p.extras[3].Color = wrap, wrap
					p.extras[2].CFrame = at
						* CFrame.new(half * 0.8, 0, 0)
						* CFrame.Angles(0.5, 0, 0)
					p.extras[3].CFrame = at
						* CFrame.new(-half * 0.8, 0, 0)
						* CFrame.Angles(-0.5, 0, 0)
				else
					p.body.Position = Vector3.new(x, y, z)
					p.body.Color = NOTE_COLOR
					p.body.Size = Vector3.one * GiftVisual.NOTE_SIZE
					p.body.Shape = Enum.PartType.Ball
				end
			end
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
