--!strict
-- Placeholder 3D for the two endings (issue #16): the plaza finale (completed) and the playful
-- party breakup (defeated, Amendment 1). Plain Parts, hard caps, no asset IDs. What happens when
-- is decided by the pure FinalePlan / DefeatPlan / Celebration; this module only draws it.
-- IN-ENGINE BEHAVIOUR IS UNVERIFIED (see the PR checklist).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Celebration = require(Shared:WaitForChild("Celebration"))
local Config = require(Shared:WaitForChild("Config"))
local DebugLayout = require(Shared:WaitForChild("DebugLayout"))
local Dance = require(Shared:WaitForChild("Dance"))
local DefeatPlan = require(Shared:WaitForChild("DefeatPlan"))
local FinalePlan = require(Shared:WaitForChild("FinalePlan"))
local Strings = require(Shared:WaitForChild("Strings"))
local Bits = require(script.Parent:WaitForChild("Bits"))

local CONFETTI = {
	Color3.fromRGB(255, 221, 0),
	Color3.fromRGB(236, 72, 153),
	Color3.fromRGB(34, 197, 94),
	Color3.fromRGB(56, 189, 248),
	Color3.fromRGB(249, 115, 22),
}
local BODY_COLORS = {
	Color3.fromRGB(236, 72, 153),
	Color3.fromRGB(249, 115, 22),
	Color3.fromRGB(56, 189, 248),
	Color3.fromRGB(250, 204, 21),
	Color3.fromRGB(168, 85, 247),
}
local HEAD_COLOR = Color3.fromRGB(224, 172, 125)
local BRASS = Color3.fromRGB(234, 179, 8)
local HAT_COLOR = Color3.fromRGB(190, 60, 40)

local MAX_DANCERS = Config.visualBudget.looseAvatars -- same cap as the street crowd (spec s8)
local MAX_GIFTS = 12 -- [default] largest tier's gift count
local MAX_FLYERS = DefeatPlan.HATS + DefeatPlan.INSTRUMENTS
local MAX_LAUGHS = 3
local GRAVITY = 40 -- [default] studs/second^2, same as Bits
local GIFT_FLIGHT = 1.2 -- [default] seconds a gift toss takes
local FLYER_LIFE = 2.2 -- [default] seconds a hat or instrument stays out

type Dancer = { model: Model, sx: number, sz: number, tx: number, tz: number, hue: number }
type Gift = { part: Part, t: number, ax: number, az: number, bx: number, bz: number }
type Flyer = { part: Part, t: number, vx: number, vy: number, vz: number, spin: number }
type Laugh = { gui: BillboardGui, t: number }

export type EndScene = {
	-- Starts an ending around `center` (the lead). `count` is the party size to draw.
	begin: (self: EndScene, kind: string, center: Vector3, count: number, tier: number) -> (),
	-- `elapsed`/`prev` are seconds into the ending (prev < elapsed fires the scheduled beats).
	update: (
		self: EndScene,
		kind: string,
		elapsed: number,
		prev: number,
		dt: number,
		tier: number
	) -> (),
	clear: (self: EndScene) -> (),
}

local EndScene = {}

local function block(parent: Instance, size: Vector3, color: Color3, shape: Enum.PartType): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

local function makeDancer(index: number): Dancer
	local model = Instance.new("Model")
	model.Name = "EndDancer"
	local body = block(
		model,
		Vector3.new(1.6, 2.2, 1.2),
		BODY_COLORS[(index - 1) % #BODY_COLORS + 1],
		Enum.PartType.Block
	)
	local head = block(model, Vector3.new(1.3, 1.3, 1.3), HEAD_COLOR, Enum.PartType.Ball)
	head.CFrame = CFrame.new(0, 1.8, 0)
	model.PrimaryPart = body
	return { model = model, sx = 0, sz = 0, tx = 0, tz = 0, hue = index }
end

function EndScene.new(): EndScene
	local folder = Instance.new("Folder")
	folder.Name = "CalendaEndScene"
	folder.Parent = Workspace

	local bits = Bits.new(folder)
	local dancers: { Dancer } = {}
	local shown = 0
	local gifts: { Gift } = {}
	local flyers: { Flyer } = {}
	local laughs: { Laugh } = {}
	local center = Vector3.zero
	local clock = 0

	for i = 1, MAX_DANCERS do
		dancers[i] = makeDancer(i)
	end
	for i = 1, MAX_GIFTS do
		local p = block(
			folder,
			Vector3.new(1.2, 1.2, 1.2),
			CONFETTI[(i - 1) % #CONFETTI + 1],
			Enum.PartType.Block
		)
		p.Parent = nil
		gifts[i] = { part = p, t = -1, ax = 0, az = 0, bx = 0, bz = 0 }
	end
	for i = 1, MAX_FLYERS do
		local isHat = i <= DefeatPlan.HATS
		local p = if isHat
			then block(folder, Vector3.new(1.6, 0.8, 1.6), HAT_COLOR, Enum.PartType.Block)
			else block(folder, Vector3.new(0.6, 0.6, 2.2), BRASS, Enum.PartType.Block)
		p.Parent = nil
		flyers[i] = { part = p, t = -1, vx = 0, vy = 0, vz = 0, spin = 0 }
	end
	for i = 1, MAX_LAUGHS do
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(120, 44)
		gui.StudsOffset = Vector3.new(0, 3.6, 0)
		gui.AlwaysOnTop = true
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Text = Strings.laugh
		text.TextScaled = true
		text.Font = Enum.Font.GothamBlack
		text.TextColor3 = Color3.fromRGB(255, 255, 255)
		text.TextStrokeTransparency = 0
		text.TextStrokeColor3 = Color3.fromRGB(28, 22, 34)
		text.Parent = gui
		laughs[i] = { gui = gui, t = -1 }
	end

	local function showDancers(n: number)
		shown = math.min(n, MAX_DANCERS)
		for i, d in dancers do
			d.model.Parent = if i <= shown then folder else nil
		end
	end

	local function toss()
		for _, g in gifts do
			if g.t < 0 then
				local n = math.max(1, shown)
				local d = dancers[math.random(1, n)]
				g.t, g.ax, g.az = 0, center.X, center.Z
				g.bx, g.bz = d.tx, d.tz
				g.part.Parent = folder
				return
			end
		end
	end

	local function launchFlyers()
		for _, f in flyers do
			local a = math.random() * math.pi * 2
			f.t = 0
			f.vx, f.vy, f.vz =
				math.cos(a) * (6 + math.random() * 8),
				24 + math.random() * 10,
				math.sin(a) * (6 + math.random() * 8)
			f.spin = (math.random() - 0.5) * 16
			f.part.Position = center + Vector3.new(0, 4, 0)
			f.part.Parent = folder
		end
	end

	local function showLaugh(wanderer: number)
		for _, l in laughs do
			if l.t < 0 then
				l.t = 0
				l.gui.Adornee =
					dancers[math.clamp(wanderer, 1, math.max(1, shown))].model.PrimaryPart
				l.gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
				return
			end
		end
	end

	local scene = {} :: EndScene

	function scene.begin(_, kind: string, at: Vector3, count: number, tier: number)
		center = at
		if kind == "finale" then
			local n = Celebration.profile(tier).dancers
			showDancers(n)
			for i = 1, shown do
				local d = dancers[i]
				local a = i / shown * math.pi * 2
				d.sx, d.sz = at.X + math.cos(a) * 3, at.Z + math.sin(a) * 3
				-- The room left ahead of the lead, not the plaza's full depth (issue #50).
				local dx, dz = FinalePlan.slot(
					i,
					shown,
					DebugLayout.halfWidth,
					FinalePlan.depthAhead(DebugLayout.streetLength, at.Z)
				)
				d.tx, d.tz =
					math.clamp(at.X + dx, -DebugLayout.halfWidth + 2, DebugLayout.halfWidth - 2),
					at.Z + dz
			end
		else
			-- breakup: the party strolls off to the sides, away from the stopped parade
			showDancers(math.min(count, MAX_DANCERS, 12))
			for i = 1, shown do
				local d = dancers[i]
				local a = i / math.max(1, shown) * math.pi * 2
				d.sx, d.sz = at.X + math.cos(a) * 3, at.Z + math.sin(a) * 3
				local side = if i % 2 == 0 then 1 else -1
				d.tx = math.clamp(
					at.X + side * (14 + (i % 4) * 4),
					-DebugLayout.halfWidth + 2,
					DebugLayout.halfWidth - 2
				)
				d.tz = at.Z + (i % 5 - 2) * 6
			end
		end
	end

	function scene.update(_, kind: string, elapsed: number, prev: number, dt: number, tier: number)
		clock += dt
		local reach, wanderT
		if kind == "finale" then
			local f = FinalePlan.at(elapsed)
			reach = f.spread
			local due = FinalePlan.due(prev, elapsed, tier)
			local perBurst = Celebration.profile(tier).confettiPerBurst
			for _ = 1, due.bursts do
				local dx, dz = FinalePlan.slot(
					math.random(1, 24),
					24,
					DebugLayout.halfWidth,
					math.min(60, FinalePlan.depthAhead(DebugLayout.streetLength, center.Z))
				)
				bits:burst(
					"confetti",
					Vector3.new(
						math.clamp(
							center.X + dx,
							-DebugLayout.halfWidth + 2,
							DebugLayout.halfWidth - 2
						),
						4,
						center.Z + dz
					),
					perBurst,
					6,
					CONFETTI
				)
			end
			for _ = 1, due.gifts do
				toss()
			end
		else
			local f = DefeatPlan.at(elapsed)
			reach = f.wander
			wanderT = f.wander
			local due = DefeatPlan.due(prev, elapsed)
			if due.hats > 0 or due.instruments > 0 then
				launchFlyers()
			end
			for _ = 1, due.bursts do
				bits:burst("confetti", center + Vector3.new(0, 4, 0), 14, 6, CONFETTI)
			end
			for _ = 1, due.laughs do
				showLaugh(math.random(1, math.max(1, shown)))
			end
		end

		for i = 1, shown do
			local d = dancers[i]
			local x = d.sx + (d.tx - d.sx) * reach
			local z = d.sz + (d.tz - d.sz) * reach
			local hop, sway, spin = 0, 0, 0
			if kind == "finale" then
				local partyHop, partySway, _, partySpin =
					Dance.pose("finale", elapsed * Config.music.bpm / 60, 1.5)
				hop, sway, spin = partyHop, partySway, partySpin
			else
				hop = 0.4 * math.abs(math.sin(clock * 4 + i)) * (1 - (wanderT or 0) * 0.5)
				sway = 0.08 * math.sin(clock * 5 + i)
			end
			local side = if i % 2 == 0 then 1 else -1
			d.model:PivotTo(CFrame.new(x, 1.3 + hop, z) * CFrame.Angles(0, spin, sway * side))
		end

		for _, g in gifts do
			if g.t >= 0 then
				g.t += dt
				local u = g.t / GIFT_FLIGHT
				if u >= 1 then
					g.t = -1
					g.part.Parent = nil
				else
					local x = g.ax + (g.bx - g.ax) * u
					local z = g.az + (g.bz - g.az) * u
					g.part.CFrame = CFrame.new(x, 2 + math.sin(math.pi * u) * 9, z)
						* CFrame.Angles(u * 9, u * 5, 0)
				end
			end
		end

		for _, f in flyers do
			if f.t >= 0 then
				f.t += dt
				if f.t >= FLYER_LIFE then
					f.t = -1
					f.part.Parent = nil
				else
					f.vy -= GRAVITY * dt
					local pos = f.part.Position + Vector3.new(f.vx, f.vy, f.vz) * dt
					if pos.Y < 0.4 then
						pos = Vector3.new(pos.X, 0.4, pos.Z)
						f.vy, f.vx, f.vz = 0, f.vx * 0.85, f.vz * 0.85
					end
					f.part.CFrame = CFrame.new(pos)
						* CFrame.Angles(f.t * f.spin, f.t * f.spin * 0.6, 0)
				end
			end
		end

		for _, l in laughs do
			if l.t >= 0 then
				l.t += dt
				if l.t >= 1.1 then
					l.t = -1
					l.gui.Parent = nil
				end
			end
		end
		bits:update(dt)
	end

	function scene.clear(_)
		bits:clear()
		showDancers(0)
		for _, g in gifts do
			g.t = -1
			g.part.Parent = nil
		end
		for _, f in flyers do
			f.t = -1
			f.part.Parent = nil
		end
		for _, l in laughs do
			l.t = -1
			l.gui.Parent = nil
		end
	end

	return scene
end

return EndScene
