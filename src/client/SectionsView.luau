--!strict
-- Section representatives and the signature assembly (issue #14, spec s5, s7, s8).
-- What to play is decided by the pure SectionEvents/SectionDirector (Lune-tested); how many
-- representatives and their xN stacks come from VisualBudget via Formation. This module only
-- draws: the swirl value it returns pulls the loose crowd inward (applied by CrowdView), confetti
-- and dust burst behind the lead, a puppet rises with a small decorative entourage, and a
-- "+N secciones" label shows for a multi-threshold gate. Entourages are decoration only.
-- Section types are looked up in a SectionRegistry, so globo and dancers (issues #19, #20) plug in
-- by registering a builder. IN-ENGINE BEHAVIOUR IS UNVERIFIED (see the PR checklist).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Formation = require(Shared:WaitForChild("Formation"))
local PuppetPose = require(Shared:WaitForChild("PuppetPose"))
local SectionDirector = require(Shared:WaitForChild("SectionDirector"))
local SectionEvents = require(Shared:WaitForChild("SectionEvents"))
local SectionRegistry = require(Shared:WaitForChild("SectionRegistry"))
local SectionTypes = require(Shared:WaitForChild("SectionTypes"))

local Bits = require(script.Parent:WaitForChild("Bits"))
local PuppetFigure = require(script.Parent:WaitForChild("PuppetFigure"))

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
local ENTOURAGE_SCALE = 0.35 -- [default]
local ENTOURAGE_RADIUS = 4.2 -- [default] studs around the puppet
local INDICATOR_SECONDS = 1.3 -- [default] the "+N secciones" label outlives the 0.8 s animation
local DISPERSE_DANCERS = 5 -- [default] per dispersed section

-- One drawn representative: the main figure plus its decorative entourage.
type Rep = {
	index: number,
	sectionType: string,
	figures: { PuppetFigure.Figure },
	scales: { number }, -- relative size per figure (1 for the main figure)
	badge: TextLabel,
	badgeGui: BillboardGui,
	count: number,
	riseT: number, -- 0..1 progress of the rise (1 when settled)
	phase: number,
	x: number,
	z: number,
}
-- Builder: creates a representative's figures. Globo/dancers register theirs in #19/#20.
export type Builder = (
	parent: Instance,
	index: number,
	entourage: number
) -> ({ PuppetFigure.Figure }, { number })

export type SectionsView = {
	-- Returns the current swirl 0..1 so the caller can pull the loose crowd inward.
	update: (self: SectionsView, leadX: number, leadZ: number, total: number, dt: number) -> number,
	reset: (self: SectionsView, total: number) -> (),
	builders: SectionRegistry.Registry<Builder>,
}

local SectionsView = {}

local function makeBadge(figure: PuppetFigure.Figure): (TextLabel, BillboardGui)
	local gui = Instance.new("BillboardGui")
	gui.Name = "StackBadge"
	gui.Size = UDim2.fromOffset(70, 36)
	gui.StudsOffset = Vector3.new(0, 2.4, 0)
	gui.AlwaysOnTop = true
	gui.Enabled = false
	gui.Adornee = figure.badgeAnchor
	gui.Parent = figure.badgeAnchor
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

local function puppetBuilder(
	parent: Instance,
	index: number,
	entourage: number
): ({ PuppetFigure.Figure }, { number })
	local palettes = PuppetFigure.PALETTES
	local figures = { PuppetFigure.new(parent, palettes[(index - 1) % #palettes + 1]) }
	local scales = { 1 }
	for i = 1, entourage do
		table.insert(figures, PuppetFigure.new(parent, palettes[(index + i - 1) % #palettes + 1]))
		table.insert(scales, ENTOURAGE_SCALE)
	end
	return figures, scales
end

function SectionsView.new(initialTotal: number): SectionsView
	local folder = Instance.new("Folder")
	folder.Name = "CalendaSections"
	folder.Parent = Workspace

	local builders = SectionRegistry.new() :: SectionRegistry.Registry<Builder>
	builders:register("puppet", puppetBuilder)
	-- globo / dancers: not registered yet; a representative of those types uses the puppet builder
	-- as a stand-in so the xN stack is still readable until #19 / #20 register theirs.

	local bits = Bits.new(folder)
	local director = SectionDirector.new(initialTotal)
	local reps: { [number]: Rep } = {}
	local ghosts: { { rep: Rep, t: number } } = {}
	local clock = 0
	local layoutTotal = -1
	local layout: Formation.Layout = Formation.forTotal(0)
	local indicatorT = 0

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
		local descriptor = SectionTypes.descriptors:get(sectionType :: any)
		if descriptor then
			entourage = descriptor.entourage
		end
		local builder = builders:get(sectionType :: any) or puppetBuilder
		local figures, scales = builder(folder, index, entourage)
		local badge, badgeGui = makeBadge(figures[1])
		return {
			index = index,
			sectionType = sectionType,
			figures = figures,
			scales = scales,
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
		for _, f in rep.figures do
			f:destroy()
		end
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
			reps[r.index] = build(r.index, r.sectionType, r.count, 1)
		end
	end
	snap(initialTotal)

	function view.reset(_, total: number)
		director:reset(total)
		snap(total)
		indicatorT = 0
		indicator.Visible = false
		bits:clear()
	end

	local function pivotOf(x: number, z: number): Vector3
		return Vector3.new(x, 0.5, z + PIVOT_DZ)
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
				reps[r.index] = build(r.index, r.sectionType, r.count, 0)
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
		clock += dt
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
		local intensity = PuppetPose.intensity(layout.plan.logicalSections)
		local risePerSecond = 1 / Config.durations.assemblySeconds
		for index, rep in reps do
			local slot = layout.sections[index]
			if slot then
				rep.x, rep.z = leadX + slot.dx, leadZ + slot.dz
			end
			if rep.riseT < 1 then
				rep.riseT = math.min(1, rep.riseT + dt * risePerSecond)
			end
			local scale = PuppetPose.rise(rep.riseT)
			local ground = CFrame.new(rep.x, 0, rep.z)
			for i, figure in rep.figures do
				local offset = Vector3.zero
				if i > 1 then
					local a = (i - 2) / math.max(1, #rep.figures - 1) * math.pi * 2 + math.pi / 2
					offset = Vector3.new(math.cos(a), 0, math.sin(a)) * ENTOURAGE_RADIUS
				end
				local pose = PuppetPose.pose(os.clock(), rep.phase + (i - 1) * 0.25)
				figure:setPose(ground * CFrame.new(offset), pose, scale * rep.scales[i], intensity)
			end
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
				for j, figure in g.rep.figures do
					figure:setPose(
						ground,
						PuppetPose.pose(os.clock(), g.rep.phase),
						k * g.rep.scales[j],
						1
					)
				end
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
		bits:update(dt)
		return swirl
	end

	return view
end

return SectionsView
