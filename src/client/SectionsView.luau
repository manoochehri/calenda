--!strict
-- Section representatives and the signature assembly (issue #14, spec s5, s7, s8).
-- What to play is decided by the pure SectionEvents/SectionDirector (Lune-tested); how many
-- representatives and their xN stacks come from VisualBudget via Formation. This module only
-- draws: the swirl value it returns pulls the loose crowd inward (applied by CrowdView), confetti
-- and dust burst behind the lead, a puppet rises with a small decorative entourage, and a
-- "+N secciones" label shows for a multi-threshold gate. Entourages are decoration only.
-- Section types are looked up in a SectionRegistry: puppet, globo (issue #19, decorative rings on
-- the beat) and dancers (issue #20, tossing on gift shots) each register a builder. IN-ENGINE BEHAVIOUR IS UNVERIFIED (see the PR checklist).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Dance = require(Shared:WaitForChild("Dance"))
local Formation = require(Shared:WaitForChild("Formation"))
local FollowerSlots = require(Shared:WaitForChild("FollowerSlots"))
local ClusterFeed = require(Shared:WaitForChild("ClusterFeed"))
local Effects = require(Shared:WaitForChild("Effects"))
local GloboPose = require(Shared:WaitForChild("GloboPose"))
local Pool = require(Shared:WaitForChild("Pool"))
local PuppetPose = require(Shared:WaitForChild("PuppetPose"))
local SectionDirector = require(Shared:WaitForChild("SectionDirector"))
local SectionEvents = require(Shared:WaitForChild("SectionEvents"))
local SectionRegistry = require(Shared:WaitForChild("SectionRegistry"))
local SectionScale = require(Shared:WaitForChild("SectionScale"))
local SectionTypes = require(Shared:WaitForChild("SectionTypes"))
local ViewMap = require(Shared:WaitForChild("ViewMap"))

local Bits = require(script.Parent:WaitForChild("Bits"))
local DancerFigure = require(script.Parent:WaitForChild("DancerFigure"))
local GloboFigure = require(script.Parent:WaitForChild("GloboFigure"))
local SectionFigure = require(script.Parent:WaitForChild("SectionFigure"))

local WHITE = Color3.fromRGB(255, 255, 255)
local OUTLINE = Color3.fromRGB(28, 22, 34)
local CONFETTI_COLORS = {
	Color3.fromRGB(255, 80, 120),
	Color3.fromRGB(255, 210, 40),
	Color3.fromRGB(60, 200, 240),
	Color3.fromRGB(110, 230, 120),
	Color3.fromRGB(190, 110, 255),
}
local DUST_COLORS = { Color3.fromRGB(235, 225, 205) }
local PIVOT_DZ = SectionEvents.SWIRL_PIVOT_DZ -- the swirl and confetti center, behind the lead
local RING_COLORS = {
	Color3.fromRGB(255, 215, 40),
	Color3.fromRGB(255, 80, 150),
	Color3.fromRGB(60, 200, 240),
}
local RING_MIN_RISE = 0.8 -- [default] rings start once the globo has nearly finished rising
local INDICATOR_SECONDS = 1.3 -- [default] the "+N secciones" label outlives the 0.8 s animation
local DISPERSE_DANCERS = 5 -- [default] per dispersed section

-- One drawn representative: its visual (figure plus decorative entourage) and its xN badge.
type Rep = {
	index: number,
	sectionType: string,
	visual: SectionFigure.Visual,
	emitsRings: boolean,
	tossesGifts: boolean,
	badge: TextLabel,
	badgeGui: BillboardGui,
	count: number,
	riseT: number, -- 0..1 progress of the rise (1 when settled)
	phase: number,
	x: number,
	z: number,
}
-- Builder: creates a representative's visual. One per section type, registered below.
export type Builder = SectionFigure.Builder

export type SectionsView = {
	-- Returns the current swirl 0..1 so the caller can pull the loose crowd inward.
	update: (self: SectionsView, leadX: number, leadZ: number, total: number, dt: number) -> number,
	onEvent: (self: SectionsView, payload: any) -> (),
	reset: (self: SectionsView, total: number) -> (),
	-- A server cluster or miss Event: a gift shot makes every dancer section toss (visual only).
	onShot: (self: SectionsView, payload: any) -> (),
	builders: SectionRegistry.Registry<Builder>,
}

local SectionsView = {}

local function makeBadge(anchor: Part): (TextLabel, BillboardGui)
	local gui = Instance.new("BillboardGui")
	gui.Name = "StackBadge"
	gui.Size = UDim2.fromOffset(70, 36)
	gui.StudsOffset = Vector3.new(0, 2.4, 0)
	gui.AlwaysOnTop = true
	gui.Enabled = false
	gui.Adornee = anchor
	gui.Parent = anchor
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.TextColor3 = WHITE
	l.TextStrokeColor3 = OUTLINE
	l.TextStrokeTransparency = 0
	l.TextScaled = true
	l.Font = Enum.Font.GothamBlack
	l.Parent = gui
	return l, gui
end

function SectionsView.new(initialTotal: number): SectionsView
	local folder = Instance.new("Folder")
	folder.Name = "CalendaSections"
	folder.Parent = Workspace

	local builders = SectionRegistry.new() :: SectionRegistry.Registry<Builder>
	builders:register("puppet", SectionFigure.puppet)
	builders:register("globo", GloboFigure.new) -- issue #19
	builders:register("dancers", DancerFigure.new) -- issue #20

	local bits = Bits.new(folder)
	local director = SectionDirector.new(initialTotal)
	local reps: { [number]: Rep } = {}
	local ghosts: { { rep: Rep, t: number } } = {}
	local clock = os.clock()
	local layoutTotal = -1
	local layout: Formation.Layout = Formation.forTotal(0)
	local indicatorT = 0
	local reactionKind = ""
	local reactionAt = -math.huge

	-- Decorative musical rings on the beat (globo only; they never recruit or touch the total).
	-- A bounded set of timed rings drawn as camera-facing circles; capacity is GloboPose.MAX_RINGS.
	type RingData = { x: number, y: number, z: number, scale: number, color: Color3 }
	local rings: Effects.Effects<RingData> = Effects.new(GloboPose.MAX_RINGS)
	local ringPool = Pool.new(function()
		local part = Instance.new("Part")
		part.Name = "BeatRing"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CastShadow = false
		part.Transparency = 1
		part.Size = Vector3.one
		local ringGui = Instance.new("BillboardGui")
		ringGui.Size = UDim2.fromScale(1, 1) -- Scale is studs on a BillboardGui
		ringGui.MaxDistance = 400
		ringGui.Parent = part
		local circle = Instance.new("Frame")
		circle.Size = UDim2.fromScale(1, 1)
		circle.BackgroundTransparency = 1
		circle.Parent = ringGui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = circle
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 5
		stroke.Parent = circle
		return { part = part, gui = ringGui, stroke = stroke }
	end, function(r)
		r.part.Parent = folder
	end, function(r)
		r.part.Parent = nil
	end)
	local ringClock = 0
	local lastBeatClock = 0
	local beatCount = 0

	local gui = Instance.new("ScreenGui")
	gui.Name = "CalendaSections"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local indicator = Instance.new("TextLabel")
	indicator.Name = "PlusSections"
	indicator.AnchorPoint = Vector2.new(0.5, 0)
	indicator.Position = UDim2.fromScale(0.5, 0.17) -- under the counter, off the gates ahead
	indicator.Size = UDim2.fromScale(0.5, 0.07)
	indicator.BackgroundTransparency = 1
	indicator.TextColor3 = Color3.fromRGB(255, 221, 0)
	indicator.TextStrokeColor3 = OUTLINE
	indicator.TextStrokeTransparency = 0
	indicator.TextScaled = true
	indicator.Font = Enum.Font.GothamBlack
	indicator.Visible = false
	indicator.Parent = gui

	local view = {} :: SectionsView
	view.builders = builders

	local function build(index: number, sectionType: string, count: number, riseT: number): Rep
		local entourage = 0
		local emitsRings, tossesGifts = false, false
		local descriptor = SectionTypes.descriptors:get(sectionType :: any)
		if descriptor then
			entourage = descriptor.entourage
			emitsRings, tossesGifts = descriptor.emitsRings, descriptor.tossesGifts
		end
		local builder = builders:get(sectionType :: any) or SectionFigure.puppet
		local visual = builder(folder, index, entourage)
		local badge, badgeGui = makeBadge(visual.badgeAnchor)
		return {
			index = index,
			sectionType = sectionType,
			visual = visual,
			emitsRings = emitsRings,
			tossesGifts = tossesGifts,
			badge = badge,
			badgeGui = badgeGui,
			count = count,
			riseT = riseT,
			phase = index * 0.37,
			x = 0,
			z = 0,
		}
	end

	local function destroyRep(rep: Rep)
		rep.visual:destroy()
	end

	-- The only way a representative enters `reps`: a live one at the same index is destroyed first,
	-- so a rebuild can never orphan its Parts (the leak fixed in PR 46).
	local function place(index: number, rep: Rep)
		local old = reps[index]
		if old ~= nil then
			destroyRep(old)
		end
		reps[index] = rep
	end

	local function clearAll()
		for i, rep in reps do
			destroyRep(rep)
			reps[i] = nil
		end
		for _, g in ghosts do
			destroyRep(g.rep)
		end
		table.clear(ghosts)
	end

	-- Brings the drawn representatives to match a total without any animation (start, new run).
	local function snap(total: number)
		clearAll()
		for _, r in Formation.forTotal(total).plan.representatives do
			place(r.index, build(r.index, r.sectionType, r.count, 1))
		end
	end
	snap(initialTotal)

	function view.reset(_, total: number)
		director:reset(total)
		snap(total)
		indicatorT = 0
		indicator.Visible = false
		bits:clear()
		rings:clear()
		ringPool:setCount(0)
		ringClock = 0
		lastBeatClock = 0
	end

	function view.onShot(_, payload: any)
		local shot = ClusterFeed.decode(payload) or ClusterFeed.decodeMiss(payload)
		if shot == nil or shot.shot ~= "gift" then
			return
		end
		local now = os.clock()
		for _, rep in reps do
			local toss = rep.visual.toss
			if rep.tossesGifts and toss ~= nil then
				toss(rep.visual, now)
			end
		end
	end

	function view.onEvent(_, payload: any)
		if
			type(payload) == "table"
			and (
				payload.kind == "gate"
				or payload.kind == "conversion"
				or payload.kind == "attack"
				or payload.kind == "complete"
				or payload.kind == "defeated"
			)
		then
			reactionKind, reactionAt = payload.kind, clock
		end
	end

	local function pivotOf(x: number, z: number): Vector3
		return Vector3.new(ViewMap.x(x), 0.5, z + PIVOT_DZ)
	end

	local function startPlan(plan: SectionEvents.Plan, leadX: number, leadZ: number)
		local diff = plan.reps
		local center = pivotOf(leadX, leadZ)
		if plan.kind == "celebrate" then
			local built: { [number]: boolean } = {}
			for index in reps do
				built[index] = true
			end
			for _, r in SectionEvents.toBuild(diff, built) do
				place(r.index, build(r.index, r.sectionType, r.count, 0))
			end
			for _, r in diff.appeared do -- merged plans re-list shown reps: just refresh their xN
				local existing = reps[r.index]
				if existing then
					existing.count = r.count
				end
			end
			for _, c in diff.changed do
				local rep = reps[c.index]
				if rep then
					rep.count = c.toCount
				end
			end
			bits:burst("confetti", center + Vector3.new(0, 4, 0), 36, 6, CONFETTI_COLORS)
			bits:burst("dust", center, 10, 5, DUST_COLORS)
			if plan.indicator then
				indicator.Text = plan.indicator
				indicator.Visible = true
				indicatorT = INDICATOR_SECONDS
			end
		else -- disperse: the newest section(s) go back to dancers; nothing is destroyed
			for _, index in diff.removed do
				local rep = reps[index]
				if rep then
					reps[index] = nil
					table.insert(ghosts, { rep = rep, t = 0 })
					bits:burst(
						"dancer",
						Vector3.new(rep.x, 1, rep.z),
						DISPERSE_DANCERS,
						4,
						CONFETTI_COLORS
					)
				end
			end
			for _, c in diff.changed do
				local rep = reps[c.index]
				if rep then
					rep.count = c.toCount
					bits:burst(
						"dancer",
						Vector3.new(rep.x, 1, rep.z),
						DISPERSE_DANCERS,
						4,
						CONFETTI_COLORS
					)
				end
			end
		end
	end

	function view.update(_, leadX: number, leadZ: number, total: number, dt: number): number
		clock = os.clock() -- common local beat clock; music clock can replace it when synchronized stems exist
		local plan = director:observe(total)
		if plan then
			startPlan(plan, leadX, leadZ)
		end
		director:step(dt)

		local active = director:active()
		local swirl = 0
		if active and active.plan.kind == "celebrate" then
			swirl = SectionEvents.phases(active.progress).swirl
		end

		if total ~= layoutTotal then
			layoutTotal = total
			layout = Formation.forTotal(total)
		end
		local intensity, tempo = Dance.intensity(total, layout.plan.logicalSections)
		local eventHop, eventRoll, eventTurn = Dance.reaction(reactionKind, clock - reactionAt)
		local risePerSecond = 1 / Config.durations.assemblySeconds
		for index, rep in reps do
			local slot = layout.sections[index]
			if slot then
				rep.x, rep.z = ViewMap.x(FollowerSlots.worldX(leadX, slot.dx)), leadZ + slot.dz -- view space
			end
			if rep.riseT < 1 then
				rep.riseT = math.min(1, rep.riseT + dt * risePerSecond)
			end
			-- Towering figures standing inside the crowd (issue #68): size by type, varied per figure.
			local big = SectionScale.scaleOf(rep.sectionType, index)
			local scale = PuppetPose.rise(rep.riseT) * big
			local ground = CFrame.new(rep.x, 0, rep.z)
			local reaction = CFrame.new(0, eventHop, 0) * CFrame.Angles(eventRoll, eventTurn, 0)
			rep.visual:setPose(ground * reaction, clock * tempo, rep.phase, scale, intensity)
			rep.badge.Text = `x{rep.count}`
			rep.badgeGui.Enabled = rep.count > 1 and rep.riseT >= 1
		end
		for i = #ghosts, 1, -1 do
			local g = ghosts[i]
			g.t += dt
			local k = 1 - g.t / Config.durations.dispersalSeconds
			if k <= 0 then
				destroyRep(g.rep)
				table.remove(ghosts, i)
			else
				local ground = CFrame.new(g.rep.x, 0, g.rep.z)
				g.rep.visual:setPose(
					ground,
					os.clock(),
					g.rep.phase,
					k * SectionScale.scaleOf(g.rep.sectionType, g.rep.index),
					1
				)
				g.rep.badgeGui.Enabled = false
			end
		end
		if indicatorT > 0 then
			indicatorT -= dt
			local pop = math.clamp(indicatorT / INDICATOR_SECONDS, 0, 1)
			indicator.TextTransparency = math.clamp(1 - pop * 3, 0, 1)
			indicator.TextStrokeTransparency = indicator.TextTransparency
			indicator.Rotation = math.sin(clock * 14) * 3 * pop
			if indicatorT <= 0 then
				indicator.Visible = false
			end
		end
		-- One ring per beat per settled globo, however many beats a slow frame spans.
		ringClock += dt * tempo
		local beats = GloboPose.beatsIn(lastBeatClock, ringClock)
		lastBeatClock = ringClock
		if beats > 0 then
			beatCount += beats
			for _, rep in reps do
				local origin = rep.visual.ringOrigin
				if rep.emitsRings and origin ~= nil and rep.riseT >= RING_MIN_RISE then
					local at = origin(rep.visual)
					rings:start(clock, GloboPose.RING_SECONDS, {
						x = at.X,
						y = at.Y,
						z = at.Z,
						scale = PuppetPose.rise(rep.riseT)
							* SectionScale.scaleOf(rep.sectionType, rep.index),
						color = RING_COLORS[GloboPose.ringColorIndex(beatCount, #RING_COLORS)],
					})
				end
			end
		end
		local live = rings:active(clock)
		local items = ringPool:setCount(#live)
		for i, item in items do
			local r = live[i]
			local ring = GloboPose.ring(r.f * GloboPose.RING_SECONDS)
			local d = 2 * ring.radius * r.data.scale
			item.part.Position =
				Vector3.new(r.data.x, r.data.y + ring.rise * r.data.scale, r.data.z)
			item.gui.Size = UDim2.fromScale(d, d)
			item.stroke.Color = r.data.color
			item.stroke.Transparency = 1 - ring.alpha
		end
		bits:update(dt)
		return swirl
	end

	return view
end

return SectionsView
