--!strict
-- The lead musician is the player's OWN Roblox character (issue #55, ADR 0003). This module takes
-- the local character over as a pure visual: it is anchored, never collides, never reads input and
-- is placed every frame where the server-driven lead is (the position math is LeadPose, Lune-tested).
-- Server authority is unchanged: the lead's hitbox is the fixed Crossing hitbox, not this model.
--
-- Roblox facts used, and what was checked (Creator Hub, 2026-10; none of it run in Studio):
--   * Players.LocalPlayer.CharacterAdded / .Character, Humanoid.RigType, HipHeight,
--     DisplayDistanceType (Enum.HumanoidDisplayDistanceType.None), HealthDisplayDistance: documented
--     Humanoid properties.
--   * Humanoid.Animator:LoadAnimation and AnimationTrack.Looped/Priority/Play: documented.
--   * The default "Animate" LocalScript holds Animation objects (walk.WalkAnim, run.RunAnim, ...)
--     with AnimationIds that Roblox ships. Its layout is from memory of the standard script:
--     UNVERIFIED. If it is absent or shaped differently the lead still marches by the root bob.
--   * An animation playing on a character whose root part is anchored still moves its Motor6Ds:
--     UNVERIFIED (the procedural bob does not depend on it).
--   * A client-side change to Anchored on its own character does not replicate to the server: the
--     server's copy of the character just stands at its spawn point; the run never reads it.
-- IN-ENGINE BEHAVIOUR IS UNVERIFIED (see the PR checklist).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LeadPose = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LeadPose"))
local Dance = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Dance"))
local DanceConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DanceConfig"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local WAIT = 10 -- [default] seconds to wait for a character's parts before giving up on it

export type LeadAvatar = {
	-- Places the avatar for this frame; true when an avatar is in place (false: use the fallback).
	update: (
		self: LeadAvatar,
		leadX: number,
		leadZ: number,
		dt: number,
		tumble: number?,
		lift: number?,
		total: number?
	) -> boolean,
	-- Holds the avatar still at its start for the title (issue #211); true when an avatar is in place.
	hold: (self: LeadAvatar, leadX: number, leadZ: number) -> boolean,
	-- Seconds without an avatar before the stand-in block may show (LeadPose.graceFor).
	fallbackGrace: (self: LeadAvatar) -> number,
	onEvent: (self: LeadAvatar, payload: any) -> (),
}

local LeadAvatar = {}

-- Make one part of the character a pure visual.
local function freeze(inst: Instance)
	if inst:IsA("BasePart") then
		inst.CanCollide = false
		inst.CanQuery = false
		inst.CanTouch = false
		inst.CastShadow = false
	end
end

local function standardWalk(character: Model): Animation?
	local animate = character:WaitForChild("Animate", 3)
	if animate == nil then
		return nil
	end
	local walk = animate:FindFirstChild("walk")
	local anim = walk and walk:FindFirstChildWhichIsA("Animation") -- WalkAnim
	if animate:IsA("LocalScript") then
		animate.Disabled = true -- it would fight the root we hold; we play the walk ourselves
	end
	return anim
end

function LeadAvatar.new(): LeadAvatar
	local player = Players.LocalPlayer
	local root: BasePart? = nil
	local standing = 3
	local clock = 0
	local hadAvatar = false -- an avatar has been in place at least once this session
	local generation = 0 -- bumps on every (re)attach so a stale load never claims the lead
	local connections: { RBXScriptConnection } = {}

	local current: Model? = nil
	local reactionKind = ""
	local reactionAt = -math.huge

	-- The old body stays where it stood (anchored) until the server removes it; hide it locally.
	local function hide(character: Model?)
		if character == nil then
			return
		end
		local function conceal(inst: Instance)
			if inst:IsA("BasePart") then
				inst.LocalTransparencyModifier = 1
			end
		end
		for _, d in character:GetDescendants() do
			conceal(d)
		end
		character.DescendantAdded:Connect(conceal) -- dies with the character when it is destroyed
	end

	local function detach()
		generation += 1
		root = nil
		hide(current)
		current = nil
		for _, c in connections do
			c:Disconnect()
		end
		table.clear(connections)
	end

	local function attach(character: Model)
		detach()
		current = character
		local mine = generation
		task.spawn(function()
			local humanoid = character:WaitForChild("Humanoid", WAIT) :: Humanoid?
			local hrp = character:WaitForChild("HumanoidRootPart", WAIT) :: BasePart?
			if mine ~= generation or humanoid == nil or hrp == nil then
				return -- a newer character took over, or this one never finished loading
			end

			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			humanoid.HealthDisplayDistance = 0
			humanoid.WalkSpeed = 0
			humanoid.JumpPower = 0
			humanoid.JumpHeight = 0
			humanoid.BreakJointsOnDeath = false
			for _, d in character:GetDescendants() do
				freeze(d)
			end
			table.insert(connections, character.DescendantAdded:Connect(freeze))
			-- Issue #114: a bigger lead (LeadPose.AVATAR_SCALE). Model:ScaleTo is documented; the in-engine
			-- result is UNVERIFIED until the Studio checklist runs.
			character:ScaleTo(LeadPose.AVATAR_SCALE)
			hrp.Anchored = true
			standing = LeadPose.rootHeight(humanoid.RigType.Name, humanoid.HipHeight, hrp.Size.Y)
			if humanoid.Health <= 0 then
				detach() -- already dead when we got here: never lead with a corpse
				return
			end
			root = hrp -- in place before the (possibly slow) animation setup below
			hadAvatar = true

			-- A reset or removal ends this lead; CharacterAdded brings the next one.
			table.insert(
				connections,
				humanoid.Died:Connect(function()
					if mine == generation then
						detach()
					end
				end)
			)
			table.insert(
				connections,
				character.AncestryChanged:Connect(function()
					if mine == generation and not character:IsDescendantOf(game) then
						detach()
					end
				end)
			)

			local animation = standardWalk(character)
			local animator = humanoid:FindFirstChildOfClass("Animator")
			if animation and animator then
				for _, track in animator:GetPlayingAnimationTracks() do
					track:Stop(0)
				end
				local ok, track = pcall(function()
					return animator:LoadAnimation(animation)
				end)
				if ok then
					track.Looped = true
					track.Priority = Enum.AnimationPriority.Action
					track:Play()
				end
			end
		end)
	end

	player.CharacterAdded:Connect(attach) -- lives as long as the player's client; no destroy path
	if player.Character then
		attach(player.Character)
	end

	local view = {} :: LeadAvatar

	function view.fallbackGrace(_)
		return LeadPose.graceFor(hadAvatar, Players.RespawnTime)
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

	-- The title pose (issue #211): the lead stands still at its start, no dance and no bob.
	function view.hold(_, leadX: number, leadZ: number): boolean
		local part = root
		if part == nil or part.Parent == nil then
			return false
		end
		local pose = LeadPose.still(leadX, leadZ, standing)
		part.CFrame = CFrame.new(pose.x, pose.y, pose.z) * CFrame.Angles(0, LeadPose.FACING_YAW, 0)
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
		return true
	end

	function view.update(
		_,
		leadX: number,
		leadZ: number,
		_dt: number,
		tumble: number?,
		lift: number?,
		total: number?
	)
		clock = os.clock() -- shared local monotonic beat clock
		local part = root
		if part == nil or part.Parent == nil then
			return false
		end
		local currentTotal = total or Config.startingTotal
		local amplitude, tempo = Dance.intensity(currentTotal, currentTotal // Config.sectionSize)
		local hop, sway, _, spin =
			Dance.pose("march", clock * Config.music.bpm / 60 * tempo, amplitude)
		local reactionHop, reactionRoll, reactionTurn =
			Dance.reaction(reactionKind, clock - reactionAt)
		local pose = LeadPose.at(
			leadX,
			leadZ,
			clock,
			(lift or 0) + hop * DanceConfig.leadDanceHopScale + reactionHop,
			standing
		)
		part.CFrame = CFrame.new(pose.x, pose.y, pose.z)
			* CFrame.Angles((tumble or 0) + reactionRoll, spin + reactionTurn, sway)
			* CFrame.Angles(0, LeadPose.FACING_YAW, 0)
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
		return true
	end

	return view
end

return LeadAvatar
