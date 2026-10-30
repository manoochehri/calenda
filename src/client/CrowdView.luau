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
local LayerHeights = require(Shared:WaitForChild("LayerHeights"))
local DebugLayout = require(Shared:WaitForChild("DebugLayout"))
local Effects = require(Shared:WaitForChild("Effects"))
local Dance = require(Shared:WaitForChild("Dance"))
local DanceConfig = require(Shared:WaitForChild("DanceConfig"))
local Config = require(Shared:WaitForChild("Config"))
local CrowdFeel = require(Shared:WaitForChild("CrowdFeel"))
local FollowerFlow = require(Shared:WaitForChild("FollowerFlow"))
local FollowerLook = require(Shared:WaitForChild("FollowerLook"))
local FollowerSource = require(Shared:WaitForChild("FollowerSource"))
local LeadPose = require(Shared:WaitForChild("LeadPose"))
local Pool = require(Shared:WaitForChild("Pool"))
local ReyFormation = require(Shared:WaitForChild("ReyFormation"))
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
	variant: string,
	look: FollowerLook.Look,
	lastClock: number,
	steps: number,
	seen: boolean,
	member: boolean, -- issue #178: drawn as a crowd member this frame
	joinedAt: number, -- issue #178: clock time it last became a member (join bounce)
}
type ReyPiece = { part: Part, offset: Vector3 }
type Rey = { pieces: { ReyPiece } }

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

local function buildRey(parent: Instance): Rey
	local s = ReyFormation.SCALE
	local pieces: { ReyPiece } = {}
	local function add(
		name: string,
		shape: Enum.PartType,
		size: Vector3,
		offset: Vector3,
		color: Color3
	)
		local piecePart = part(parent, name, shape, size * s, offset * s, color)
		piecePart.CanTouch = false
		table.insert(pieces, {
			part = piecePart,
			offset = offset * s,
		})
	end
	add(
		"ReyBody",
		Enum.PartType.Ball,
		Vector3.new(1.5, 1.1, 1.65),
		Vector3.new(0, ReyFormation.BODY_CENTER_Y, 0),
		Color3.fromRGB(250, 242, 226)
	)
	add(
		"ReyHead",
		Enum.PartType.Ball,
		Vector3.new(0.72, 0.72, 0.72),
		Vector3.new(0, 1.28, -0.56),
		Color3.fromRGB(232, 172, 58)
	)
	add(
		"ReyBeak",
		Enum.PartType.Ball,
		Vector3.new(0.36, 0.26, 0.42),
		Vector3.new(0, 1.2, -0.92),
		Color3.fromRGB(244, 130, 40)
	)
	add(
		"ReyComb",
		Enum.PartType.Ball,
		Vector3.new(0.24, 0.34, 0.22),
		Vector3.new(0, 1.77, -0.52),
		Color3.fromRGB(204, 65, 56)
	)
	add(
		"ReyLeftEye",
		Enum.PartType.Ball,
		Vector3.new(0.12, 0.12, 0.12),
		Vector3.new(-0.23, 1.34, -0.82),
		Color3.fromRGB(30, 28, 30)
	)
	add(
		"ReyRightEye",
		Enum.PartType.Ball,
		Vector3.new(0.12, 0.12, 0.12),
		Vector3.new(0.23, 1.34, -0.82),
		Color3.fromRGB(30, 28, 30)
	)
	add(
		"ReyLeftWing",
		Enum.PartType.Ball,
		Vector3.new(0.68, 0.7, 0.9),
		Vector3.new(-0.45, 0.76, 0.05),
		Color3.fromRGB(232, 172, 58)
	)
	add(
		"ReyRightWing",
		Enum.PartType.Ball,
		Vector3.new(0.68, 0.7, 0.9),
		Vector3.new(0.45, 0.76, 0.05),
		Color3.fromRGB(232, 172, 58)
	)
	add(
		"ReyFeet",
		Enum.PartType.Block,
		Vector3.new(1, 0.16, 0.22),
		Vector3.new(0, 0.12, 0.12),
		Color3.fromRGB(244, 130, 40)
	)
	return { pieces = pieces }
end

local function drawRey(rey: Rey, leadX: number, leadZ: number, seed: number)
	local pose = ReyFormation.pose(leadX, leadZ, seed, DebugLayout.halfWidth - 6)
	for _, piece in rey.pieces do
		piece.part.CFrame = CFrame.new(
			ViewMap.x(pose.x) + ViewMap.x(piece.offset.X),
			piece.offset.Y + pose.bob,
			pose.z + piece.offset.Z
		)
	end
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
	-- Issue #114: five pieces, no arms (FollowerLook.PIECES).
	return {
		id = -1,
		pieces = { body, head, skirt, hat, flower },
		body = body,
		head = head,
		skirt = skirt,
		hat = hat,
		flower = flower,
		variant = "march",
		look = FollowerLook.of(0),
		lastClock = 0,
		steps = 0,
		seen = false,
		member = false,
		joinedAt = -math.huge,
	}
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Dresses an avatar for a follower id (its colour, hat or flower); called when the id changes.
local function restyle(avatar: Avatar, id: number, clock: number)
	local look = FollowerLook.of(id)
	avatar.id, avatar.look, avatar.lastClock, avatar.steps = id, look, clock, 0
	avatar.variant = Dance.variant(id)
	local tints = FollowerLook.tints(look)
	avatar.body.part.Color = rgb(tints.body)
	avatar.skirt.part.Color = rgb(tints.skirt)
	avatar.head.part.Color = rgb(tints.head)
	avatar.hat.part.Color = rgb(tints.accent)
	avatar.flower.part.Color = rgb(tints.accent)
	avatar.hat.part.Transparency = if look.topper == "hat" then 0 else 1
	avatar.flower.part.Transparency = if look.topper == "flower" then 0 else 1
end

-- A neon ring on the ground under the lead: the steering anchor that never gets lost.
local function buildRing(parent: Instance): Part
	local ring = Instance.new("Part")
	ring.Name = "LeadRing"
	ring.Shape = Enum.PartType.Cylinder
	-- Issue #114: wider than before (LeadPose.RING_DIAMETER). Cylinder axis is X; rotated upright below.
	ring.Size = Vector3.new(0.2, LeadPose.RING_DIAMETER, LeadPose.RING_DIAMETER)
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
	local rey = buildRey(folder)

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
	local clock = os.clock()
	local lastLeadZ: number? = nil
	local danceAmplitude, danceTempo = 1, 1
	local reactionKind = ""
	local reactionAt = -math.huge
	local cheerAt, flinchAt = -math.huge, -math.huge -- issue #178: total went up / down at this clock

	local view = {} :: CrowdView

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
		if marching and not avatar.member then
			avatar.joinedAt = clock -- issue #178: a new member starts its join bounce
		end
		avatar.member = marching
		local look = avatar.look
		local isFar = lastLeadZ ~= nil and math.abs(z - lastLeadZ) > DanceConfig.farDistance
		local beat = clock * Config.music.bpm / 60 * danceTempo + look.phase / (2 * math.pi)
		local danceHop: number, danceSway: number, _arm: number, spin: number
		-- The arm swing is unused: followers have no arms (issue #114).
		if isFar then
			danceHop, danceSway, _arm, spin = Dance.lowDetailPose(beat)
		else
			danceHop, danceSway, _arm, spin = Dance.pose(avatar.variant, beat, danceAmplitude)
		end
		local eventHop, eventRoll, eventTurn = Dance.reaction(reactionKind, clock - reactionAt)
		local marchY, marchSquashY, marchSquashXZ =
			FollowerLook.marchValues(look, clock * danceTempo)
		local hop, sy, sxz = y + danceHop * DanceConfig.followerDanceHopScale + eventHop, 1, 1
		if marching then
			hop += marchY
			sy, sxz = marchSquashY, marchSquashXZ
			if FollowerLook.footfall(look, avatar.lastClock, clock) then
				avatar.steps += 1
				if FollowerLook.raisesDust(id, avatar.steps) then
					dust:start(clock, FollowerLook.DUST_SECONDS, { x = x, z = z })
				end
			end
		else
			hop += DanceConfig.runnerMarchHopScale * marchY -- runners and leavers keep their own hop
		end
		-- Issue #178: join bounce (members only), and the cheer or flinch shared by everyone drawn.
		local joinAge = if marching then clock - avatar.joinedAt else math.huge
		local feelHop, feelY, feelXZ = CrowdFeel.combine(joinAge, clock - cheerAt, clock - flinchAt)
		hop += feelHop
		sy *= feelY
		sxz *= feelXZ
		avatar.lastClock = clock
		-- Each follower breathes at its own offset, so the crowd does not pulse in lockstep.
		local k = look.scale * FollowerLook.breath(clock, CrowdFeel.breathPhase(id))
		local base = CFrame.new(ViewMap.x(x), hop, z)
			* CFrame.Angles(
				eventRoll,
				spin + eventTurn,
				FollowerLook.lean(ViewMap.x(vx)) + danceSway
			)
		for _, p in avatar.pieces do
			p.part.Size = Vector3.new(p.size.X * sxz, p.size.Y * sy, p.size.Z * sxz) * k
			local localFrame = CFrame.new(p.x * sxz * k, p.y * sy * k, 0)
			p.part.CFrame = base * localFrame
		end
	end

	function view.onEvent(_, payload: any, t: number)
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
		clock = os.clock() -- shared local monotonic beat clock with SectionsView and LeadAvatar
		absent = LeadPose.absence(absent, hasAvatar == true, dt)
		if lastLeadZ ~= nil and leadZ < lastLeadZ - REPLAY_JUMP then
			cachedTotal = -1 -- a new run: the field starts settled again
		end
		lastLeadZ = leadZ
		drawRey(rey, leadX, leadZ, DebugLayout.seed)
		if total ~= cachedTotal then
			if cachedTotal < 0 then
				flow:reset(total)
				cheerAt, flinchAt = -math.huge, -math.huge
			else
				flow:setTotal(total)
				-- Issue #178: the server's total went up (cheer) or down (flinch). Display only.
				if total > cachedTotal then
					cheerAt = clock
				else
					flinchAt = clock
				end
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
		danceAmplitude, danceTempo = Dance.intensity(total, total // Config.sectionSize)
		-- Avatars are keyed by follower id: one follower leaving never restyles the others.
		for _, avatar in live do
			avatar.seen = false
			avatar.member = false
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
