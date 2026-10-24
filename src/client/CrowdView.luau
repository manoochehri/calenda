--!strict
-- The ring under the lead, the pooled follower avatars (issue #13), and a primitive block that
-- stands in for the lead ONLY when the player's own avatar (src/client/LeadAvatar, issue #55) has
-- not been available for LeadPose.FALLBACK_GRACE seconds.
-- The crowd FLOWS (issue #68): the pure FollowerFlow decides who is drawn where (staggered joins from a
-- source, individual peel-offs, stable organic slots, spring follow); FollowerLook decides how each
-- follower looks and moves (costume colour, size, hat or flower, bounce, squash, lean, breathing, dust).
-- This file only turns those numbers into Parts. The exact count is shown by the HUD, not by this view;
-- how many are drawn is capped by the visual budget (24 members, plus bounded transient runners).
-- IN-ENGINE BEHAVIOUR IS UNVERIFIED (see the PR checklist).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraRig = require(Shared:WaitForChild("CameraRig"))
local Formation = require(Shared:WaitForChild("Formation"))
local LayerHeights = require(Shared:WaitForChild("LayerHeights"))
local DebugLayout = require(Shared:WaitForChild("DebugLayout"))
local Effects = require(Shared:WaitForChild("Effects"))
local FollowerFlow = require(Shared:WaitForChild("FollowerFlow"))
local FollowerLook = require(Shared:WaitForChild("FollowerLook"))
local FollowerSource = require(Shared:WaitForChild("FollowerSource"))
local LeadPose = require(Shared:WaitForChild("LeadPose"))
local Pool = require(Shared:WaitForChild("Pool"))
local ViewMap = require(Shared:WaitForChild("ViewMap"))

-- Flat, saturated colors: the lead is the brightest thing on screen, followers share one color.
local LEAD_COLOR = Color3.fromRGB(255, 221, 0)
local LEAD_HEAD_COLOR = Color3.fromRGB(255, 240, 150)
local LEAD_HAT_COLOR = Color3.fromRGB(255, 110, 20)
local HORN_COLOR = Color3.fromRGB(235, 175, 40)
local RING_COLOR = Color3.fromRGB(80, 235, 255)
local DUST_COLOR = Color3.fromRGB(225, 212, 190)
local BLOCK_STANDING = 1.5 -- studs: centre height of the stand-in block
local REPLAY_JUMP = 5 -- studs the lead's z must go BACK to count as a new run

-- One follower body: parts positioned from a shared frame so squash, stretch and lean are cheap.
type Piece = { part: Part, size: Vector3, y: number, x: number }
type Avatar = {
	id: number,
	pieces: { Piece },
	body: Piece,
	head: Piece,
	skirt: Piece,
	hat: Piece,
	flower: Piece,
	look: FollowerLook.Look,
	lastClock: number,
	steps: number,
	seen: boolean,
}

export type CrowdView = {
	-- swirl 0..1 (issue #14): pulls the loose followers inward during a section celebration.
	-- A server Event (gate, filled cluster, obstacle): where new followers should come from.
	onEvent: (self: CrowdView, payload: any, t: number) -> (),
	update: (
		self: CrowdView,
		leadX: number,
		leadZ: number,
		total: number,
		dt: number,
		swirl: number?,
		tumble: number?, -- issue #16: lead roll in radians (the defeat breakup)
		lift: number?, -- issue #16: studs the lead hops during the tumble
		hasAvatar: boolean?, -- issue #55: the player's avatar is in place as the lead
		fallbackGrace: number? -- seconds without an avatar before the stand-in block shows
	) -> (),
}

local CrowdView = {}

local function part(
	parent: Instance,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	offset: Vector3,
	color: Color3
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Position = offset
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function buildLead(parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Lead"
	local body =
		part(model, "Body", Enum.PartType.Block, Vector3.new(2.6, 3, 2.2), Vector3.zero, LEAD_COLOR)
	part(
		model,
		"Head",
		Enum.PartType.Ball,
		Vector3.new(2.2, 2.2, 2.2),
		Vector3.new(0, 2.6, 0),
		LEAD_HEAD_COLOR
	)
	part(
		model,
		"Hat",
		Enum.PartType.Block,
		Vector3.new(1.8, 0.9, 1.8),
		Vector3.new(0, 4, 0),
		LEAD_HAT_COLOR
	)
	part(
		model,
		"Horn",
		Enum.PartType.Block,
		Vector3.new(0.7, 0.7, 2.2),
		Vector3.new(0, 0.5, 1.8),
		HORN_COLOR
	)
	model.PrimaryPart = body
	model.Parent = parent
	return model
end

local function piece(
	parent: Instance,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	x: number,
	y: number
): Piece
	local p = part(parent, name, shape, size, Vector3.zero, Color3.new(1, 1, 1))
	return { part = p, size = size, x = x, y = y }
end

local function buildFollower(parent: Instance): Avatar
	local model = Instance.new("Model")
	model.Name = "Follower"
	model.Parent = parent
	local body = piece(model, "Body", Enum.PartType.Block, Vector3.new(1.4, 2, 1.4), 0, 1.2)
	local head = piece(model, "Head", Enum.PartType.Ball, Vector3.new(1.3, 1.3, 1.3), 0, 2.8)
	local skirt = piece(model, "Skirt", Enum.PartType.Block, Vector3.new(2, 0.7, 2), 0, 0.45)
	local hat = piece(model, "Hat", Enum.PartType.Block, Vector3.new(1, 0.9, 1), 0, 3.75)
	local flower = piece(model, "Flower", Enum.PartType.Ball, Vector3.new(0.7, 0.7, 0.7), 0.55, 3.4)
	model.PrimaryPart = body.part
	return {
		id = -1,
		pieces = { body, head, skirt, hat, flower },
		body = body,
		head = head,
		skirt = skirt,
		hat = hat,
		flower = flower,
		look = FollowerLook.of(0),
		lastClock = 0,
		steps = 0,
		seen = false,
	}
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Dresses an avatar for a follower id (its colour, hat or flower); called when the id changes.
local function restyle(avatar: Avatar, id: number, clock: number)
	local look = FollowerLook.of(id)
	avatar.id, avatar.look, avatar.lastClock, avatar.steps = id, look, clock, 0
	local color, accent = rgb(look.color), rgb(look.accent)
	avatar.body.part.Color = color
	avatar.skirt.part.Color = color:Lerp(Color3.new(1, 1, 1), 0.35)
	avatar.head.part.Color = color:Lerp(Color3.new(1, 1, 1), 0.6)
	avatar.hat.part.Color = accent
	avatar.flower.part.Color = accent
	avatar.hat.part.Transparency = if look.topper == "hat" then 0 else 1
	avatar.flower.part.Transparency = if look.topper == "flower" then 0 else 1
end

-- A neon ring on the ground under the lead: the steering anchor that never gets lost.
local function buildRing(parent: Instance): Part
	local ring = Instance.new("Part")
	ring.Name = "LeadRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, 8, 8) -- cylinder axis is X; rotated upright below
	ring.Color = RING_COLOR
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.2
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CastShadow = false
	ring.Parent = parent
	return ring
end

function CrowdView.new(): CrowdView
	local folder = Instance.new("Folder")
	folder.Name = "CalendaCrowd"
	folder.Parent = Workspace

	local lead = buildLead(folder) -- stand-in only; the avatar is the lead (spec s3, issue #55)
	lead.Parent = nil
	local absent = 0
	local ring = buildRing(folder)

	local live: { [number]: Avatar } = {} -- drawn avatars by follower id
	local free: { Avatar } = {} -- hidden, ready for reuse

	local dust: Effects.Effects<{ x: number, z: number }> = Effects.new(FollowerLook.DUST_CAP)
	local dustPool = Pool.new(function(): Part
		local p =
			part(folder, "Dust", Enum.PartType.Ball, Vector3.new(1, 1, 1), Vector3.zero, DUST_COLOR)
		p.Material = Enum.Material.SmoothPlastic
		return p
	end, function(p: Part)
		p.Parent = folder
	end, function(p: Part)
		p.Parent = nil
	end)

	local cachedTotal = -1
	local flow = FollowerFlow.new(DebugLayout.halfWidth)
	local clock = 0
	local lastLeadZ: number? = nil

	local view = {} :: CrowdView

	local breathNow = 1 -- crowd breathing scale of the frame being drawn

	local function draw(id: number, x: number, z: number, vx: number, y: number, marching: boolean)
		local avatar = live[id]
		if avatar == nil then
			avatar = table.remove(free) or buildFollower(folder)
			restyle(avatar, id, clock)
			for _, p in avatar.pieces do
				p.part.Parent = folder
			end
			live[id] = avatar
		end
		avatar.seen = true
		local look = avatar.look
		local march = FollowerLook.march(look, clock)
		local hop, sy, sxz = y, 1, 1
		if marching then
			hop += march.y
			sy, sxz = march.squashY, march.squashXZ
			if FollowerLook.footfall(look, avatar.lastClock, clock) then
				avatar.steps += 1
				if FollowerLook.raisesDust(id, avatar.steps) then
					dust:start(clock, FollowerLook.DUST_SECONDS, { x = x, z = z })
				end
			end
		else
			hop += 0.6 * march.y -- runners and leavers keep their own hop
		end
		avatar.lastClock = clock
		local k = look.scale * breathNow
		local base = CFrame.new(ViewMap.x(x), hop, z)
			* CFrame.Angles(0, 0, FollowerLook.lean(ViewMap.x(vx)))
		for _, p in avatar.pieces do
			p.part.Size = Vector3.new(p.size.X * sxz, p.size.Y * sy, p.size.Z * sxz) * k
			p.part.CFrame = base * CFrame.new(p.x * sxz * k, p.y * sy * k, 0)
		end
	end

	function view.onEvent(_, payload: any, t: number)
		local hint = FollowerSource.fromEvent(DebugLayout, payload, t)
		if hint then
			flow:hint(hint)
		end
	end

	function view.update(
		_,
		leadX: number,
		leadZ: number,
		total: number,
		dt: number,
		swirl: number?,
		tumble: number?,
		lift: number?,
		hasAvatar: boolean?,
		fallbackGrace: number?
	)
		clock += dt
		absent = LeadPose.absence(absent, hasAvatar == true, dt)
		if lastLeadZ ~= nil and leadZ < lastLeadZ - REPLAY_JUMP then
			cachedTotal = -1 -- a new run: the field starts settled again
		end
		lastLeadZ = leadZ
		if total ~= cachedTotal then
			if cachedTotal < 0 then
				flow:reset(total)
			else
				flow:setTotal(total)
			end
			cachedTotal = total
		end

		if LeadPose.showFallback(hasAvatar == true, absent, fallbackGrace) then
			local pose = LeadPose.at(leadX, leadZ, clock, lift or 0, BLOCK_STANDING)
			lead.Parent = folder
			lead:PivotTo(CFrame.new(pose.x, pose.y, pose.z) * CFrame.Angles(tumble or 0, 0, 0))
		else
			lead.Parent = nil
		end
		ring.CFrame = CFrame.new(ViewMap.x(leadX), LayerHeights.RING - 0.1, leadZ)
			* CFrame.Angles(0, 0, math.pi / 2)

		local frame = flow:step(dt, leadX, leadZ, swirl)
		breathNow = FollowerLook.breath(clock)
		-- Avatars are keyed by follower id: one follower leaving never restyles the others.
		for _, avatar in live do
			avatar.seen = false
		end
		for _, m in frame.members do
			draw(m.id, m.x, m.z, m.vx, m.y, true)
		end
		for _, r in frame.runners do
			draw(r.id, r.x, r.z, r.vx, r.y, false)
		end
		for _, l in frame.leavers do
			draw(l.id, l.x, l.z, l.vx, l.y, false)
		end
		for id, avatar in live do
			if not avatar.seen then
				live[id] = nil
				for _, p in avatar.pieces do
					p.part.Parent = nil
				end
				table.insert(free, avatar)
			end
		end

		local puffs = dust:active(clock)
		local ds = dustPool:setCount(#puffs)
		for i, p in ds do
			local d = puffs[i]
			p.Size = Vector3.one * (0.4 + FollowerLook.DUST_SIZE * d.f)
			p.Transparency = 0.35 + 0.65 * d.f
			p.Position = Vector3.new(ViewMap.x(d.data.x), 0.4 + 0.9 * d.f, d.data.z - 0.9)
		end
	end

	return view
end

return CrowdView
