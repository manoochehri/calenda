--!strict
-- Standing gate portals (issue #70). Each gate pair is two portals, one per lane half: two posts
-- and a tall banner facing the camera, with huge numerals on its FRONT face (operation big,
-- "-> result" smaller, from GateLabel). Adders are square-postered and blue; multipliers have round
-- pillars with ball finials and are gold: shape, symbol and text, not color alone. Geometry,
-- timing and the lead-occlusion fade are pure and Lune-tested (PortalGeometry, PortalFx,
-- CameraRig). When the server's gate Event arrives the chosen portal flashes and bursts confetti
-- (the existing Bits pool, capped at 90) with a ring on the ground, and the other dims. The next
-- row pulses subtly as it nears. Every x goes through ViewMap.x exactly once.
-- IN-ENGINE BEHAVIOUR IS UNVERIFIED (see the PR checklist).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GateLabel = require(Shared:WaitForChild("GateLabel"))
local PortalFx = require(Shared:WaitForChild("PortalFx"))
local PortalGeometry = require(Shared:WaitForChild("PortalGeometry"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local RunView = require(Shared:WaitForChild("RunView"))
local ViewMap = require(Shared:WaitForChild("ViewMap"))
local Bits = require(script.Parent:WaitForChild("Bits"))

local WHITE = Color3.fromRGB(255, 255, 255)
local STROKE = Color3.fromRGB(24, 22, 30)
-- Theme palette per style (the Oaxacan look, issue #54, replaces these).
local PALETTE = {
	adder = { banner = Color3.fromRGB(36, 112, 226), post = Color3.fromRGB(20, 62, 140) },
	multiplier = { banner = Color3.fromRGB(226, 150, 20), post = Color3.fromRGB(118, 52, 158) },
}
local CONFETTI_COLORS = {
	Color3.fromRGB(255, 214, 64),
	WHITE,
	Color3.fromRGB(255, 80, 170),
	Color3.fromRGB(70, 210, 255),
}
local RING_COLOR = Color3.fromRGB(255, 240, 170)
local FLASH_SCALE = 0.08 -- [default] extra banner scale at the instant of the pass

type Portal = {
	desc: PortalGeometry.Portal,
	banner: Part,
	baseSize: Vector3,
	baseColor: Color3,
	operation: TextLabel,
	result: TextLabel,
	icon: TextLabel,
	strip: Part,
	shownTotal: number, -- the total the labels were formatted for
	lastKey: string,
}

export type GateView = {
	reset: (self: GateView) -> (),
}

local GateView = {}

local function part(
	parent: Instance,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	cf: CFrame,
	color: Color3
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false -- the lead walks through; the server decides the gate
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function textLabel(
	parent: Instance,
	name: string,
	pos: UDim2,
	size: UDim2,
	font: Enum.Font
): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Position = pos
	l.Size = size
	l.BackgroundTransparency = 1
	l.TextColor3 = WHITE
	l.TextStrokeColor3 = STROKE
	l.TextStrokeTransparency = 0.1
	l.TextScaled = true
	l.Font = font
	l.Text = ""
	l.Parent = parent
	return l
end

local function buildPortal(folder: Instance, desc: PortalGeometry.Portal, total: number): Portal
	local pal = PALETTE[desc.style.paletteKey]
	local name = `Gate{desc.gateId}{desc.side}`
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = folder

	local x = desc.centerX
	-- Posts: ViewMap.x applied to each post centre once.
	for i, sign in { -1, 1 } do
		local px = ViewMap.x(x + sign * desc.postOffset)
		if desc.style.postShape == "cylinder" then
			local h = PortalGeometry.TOP
				- (if desc.style.crown then PortalGeometry.FINIAL / 2 else 0)
			part(
				model,
				`Post{i}`,
				Enum.PartType.Cylinder,
				Vector3.new(h, PortalGeometry.POST_W, PortalGeometry.POST_W),
				CFrame.new(px, h / 2, desc.z) * CFrame.Angles(0, 0, math.pi / 2),
				pal.post
			)
		else
			part(
				model,
				`Post{i}`,
				Enum.PartType.Block,
				Vector3.new(PortalGeometry.POST_W, PortalGeometry.TOP, PortalGeometry.POST_W),
				CFrame.new(px, PortalGeometry.TOP / 2, desc.z),
				pal.post
			)
		end
		if desc.style.crown then -- ball finial: its top is exactly TOP
			part(
				model,
				`Finial{i}`,
				Enum.PartType.Ball,
				Vector3.one * PortalGeometry.FINIAL,
				CFrame.new(px, PortalGeometry.TOP - PortalGeometry.FINIAL / 2, desc.z),
				Color3.fromRGB(255, 226, 120)
			)
		end
	end

	local size =
		Vector3.new(desc.bannerWidth, PortalGeometry.BANNER_HEIGHT, PortalGeometry.BANNER_DEPTH)
	local banner = part(
		model,
		"Banner",
		Enum.PartType.Block,
		size,
		CFrame.new(ViewMap.x(x), desc.bannerCenterY, desc.z),
		pal.banner
	)

	-- The crossing line on the ground, visible from far, under the opening.
	local strip = part(
		model,
		"Strip",
		Enum.PartType.Block,
		Vector3.new(desc.opening, 0.1, 1.2),
		CFrame.new(ViewMap.x(x), 0.07, desc.z),
		pal.banner
	)
	strip.Transparency = 0.25

	local gui = Instance.new("SurfaceGui")
	gui.Name = "GateLabel"
	gui.Face = Enum.NormalId.Front -- toward the camera, which looks along +Z
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	local cw, ch = PortalGeometry.canvas(desc)
	gui.CanvasSize = Vector2.new(cw, ch)
	gui.AlwaysOnTop = true -- never hidden by sections or spectators standing in front
	gui.LightInfluence = 0
	gui.Parent = banner
	local L = PortalGeometry.LABEL
	local operation = textLabel(
		gui,
		"Operation",
		UDim2.fromScale(0, 0),
		UDim2.fromScale(1, L.opShare),
		Enum.Font.GothamBlack
	)
	local result = textLabel(
		gui,
		"Result",
		UDim2.fromScale(0, L.opShare),
		UDim2.fromScale(1, L.resultShare),
		Enum.Font.GothamBold
	)
	local icon = textLabel(
		gui,
		"Icon",
		UDim2.fromScale(0.01, 0.01),
		UDim2.fromScale(0.12, 0.2),
		Enum.Font.GothamBlack
	)
	icon.Text = desc.style.icon
	icon.TextTransparency = 0.25

	local o, r = GateLabel.format(desc.op, total)
	operation.Text, result.Text = o, r
	return {
		desc = desc,
		banner = banner,
		baseSize = size,
		baseColor = pal.banner,
		operation = operation,
		result = result,
		icon = icon,
		strip = strip,
		shownTotal = total,
		lastKey = "",
	}
end

function GateView.new(parent: Instance, layout: any): GateView
	local folder = Instance.new("Folder")
	folder.Name = "CalendaGates"
	folder.Parent = parent

	local bits = Bits.new(folder)
	local fx = PortalFx.new()
	local portals: { Portal } = {}
	for _, desc in PortalGeometry.all(layout) do
		table.insert(portals, buildPortal(folder, desc, Config.startingTotal))
	end

	local ring = part(
		folder,
		"PassRing",
		Enum.PartType.Cylinder,
		Vector3.new(0.2, 2, 2),
		CFrame.new(0, 0.12, 0) * CFrame.Angles(0, 0, math.pi / 2),
		RING_COLOR
	)
	ring.Material = Enum.Material.Neon
	ring.Parent = nil
	local ringAt: { x: number, z: number, t0: number }? = nil
	local reactions: { [number]: { side: string, t0: number } } = {}

	local clock = 0
	local latest: Remotes.StatePayload? = nil
	local receivedAt = 0
	local total = Config.startingTotal

	local view = {} :: GateView

	function view.reset(_)
		fx:reset()
		table.clear(reactions)
		bits:clear()
		ringAt = nil
		ring.Parent = nil
	end

	local remotes = ReplicatedStorage:WaitForChild(Remotes.folderName)
	local stateRemote = remotes:WaitForChild(Remotes.names.state) :: RemoteEvent
	local eventRemote = remotes:WaitForChild(Remotes.names.event) :: RemoteEvent

	stateRemote.OnClientEvent:Connect(function(payload: any)
		if
			type(payload) ~= "table"
			or type(payload.total) ~= "number"
			or type(payload.t) ~= "number"
			or type(payload.z) ~= "number"
			or type(payload.x) ~= "number"
		then
			return
		end
		if RunView.isNewRun(if latest then latest.t else nil, payload.t) then
			view:reset()
		end
		latest = payload
		receivedAt = os.clock()
		total = RunView.wholeTotal(payload.total)
	end)

	-- The server's gate Event: the chosen portal flashes and bursts, the other dims.
	eventRemote.OnClientEvent:Connect(function(payload: any)
		local plan = fx:handle(payload)
		if plan == nil then
			return
		end
		reactions[plan.gateId] = { side = plan.chosen, t0 = clock }
		for _, p in portals do
			if p.desc.gateId == plan.gateId and p.desc.side == plan.chosen then
				bits:burst(
					"confetti",
					Vector3.new(ViewMap.x(p.desc.centerX), p.desc.bannerCenterY, p.desc.z),
					plan.confetti,
					9,
					CONFETTI_COLORS
				)
				ringAt = { x = ViewMap.x(p.desc.centerX), z = p.desc.z, t0 = clock }
				ring.Parent = folder
			end
		end
	end)

	RunService.Heartbeat:Connect(function(dt: number)
		clock += dt
		bits:update(dt)
		local state = latest
		if state == nil then
			return
		end
		local _, leadZ =
			RunView.leadPosition(state, os.clock() - receivedAt, Config.speed, layout.plazaStart)
		local nextId = PortalFx.nextRowId(layout.gates, leadZ)

		for _, p in portals do
			local d = p.desc
			local fade = PortalFx.fade(leadZ - d.z)
			local glow = if d.gateId == nextId then PortalFx.pulse(d.z - leadZ, clock) else 0
			local flash, dim = 0, 0
			local react = reactions[d.gateId]
			if react then
				local seconds = clock - react.t0
				if react.side == d.side then
					flash = PortalFx.flash(seconds / PortalFx.DURATION)
				else
					dim = PortalFx.dim(seconds)
				end
			end
			local trans = 1 - (1 - fade) * (1 - dim)
			local scale = PortalFx.scale(glow) + FLASH_SCALE * flash
			local key = `{trans}|{scale}|{glow}|{flash}`
			if key ~= p.lastKey then
				p.lastKey = key
				p.banner.Transparency = trans
				p.banner.Size =
					Vector3.new(p.baseSize.X * scale, p.baseSize.Y * scale, p.baseSize.Z)
				p.banner.Color = p.baseColor:Lerp(WHITE, math.clamp(glow * 0.3 + flash * 0.8, 0, 1))
				p.strip.Transparency = 0.25 + 0.75 * trans
				for _, l in { p.operation, p.result, p.icon } do
					l.TextTransparency = trans
					l.TextStrokeTransparency = math.max(0.1, trans)
				end
			end
			if total ~= p.shownTotal then -- the result follows the current total
				p.shownTotal = total
				p.operation.Text, p.result.Text = GateLabel.format(d.op, total)
			end
		end

		local r = ringAt
		if r then
			local f = (clock - r.t0) / PortalFx.DURATION
			if f >= 1 then
				ringAt = nil
				ring.Parent = nil
			else
				local radius = PortalFx.ringRadius(f, layout.halfWidth / 2)
				ring.Size = Vector3.new(0.2, radius * 2, radius * 2)
				ring.CFrame = CFrame.new(r.x, 0.12, r.z) * CFrame.Angles(0, 0, math.pi / 2)
				ring.Transparency = 1 - PortalFx.ringAlpha(f)
			end
		end
	end)

	return view
end

return GateView
