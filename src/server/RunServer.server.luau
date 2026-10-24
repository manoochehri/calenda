--!strict
-- Server run loop (issue #8). One RunDriver per player; all game decisions are in the pure
-- modules under ReplicatedStorage.Shared (RunDriver, Crossing, Steering, Remotes), which are
-- Lune-tested. This script only wires Roblox services and remotes to the driver.
--
-- IN-ENGINE BEHAVIOUR IS UNVERIFIED (not run in Studio by the author): see the PR for the check.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DebugLayout = require(Shared:WaitForChild("DebugLayout"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local RunDriver = require(Shared:WaitForChild("RunDriver"))
local RunHooks = require(Shared:WaitForChild("RunHooks"))
local RunLog = require(Shared:WaitForChild("RunLog"))
local TickPacer = require(Shared:WaitForChild("TickPacer"))

local STATE_INTERVAL = 0.1 -- seconds between State snapshots per player (about 10 Hz)

-- Create the remotes once. The client only ever sends Steer and Replay; handlers below ignore
-- everything except the shape the contract defines.
local folder = Instance.new("Folder")
folder.Name = Remotes.folderName
local function makeRemote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = folder
	return r
end
local steerRemote = makeRemote(Remotes.names.steer)
local replayRemote = makeRemote(Remotes.names.replay)
local stateRemote = makeRemote(Remotes.names.state)
local eventRemote = makeRemote(Remotes.names.event)
folder.Parent = ReplicatedStorage

type Session = {
	driver: RunDriver.RunDriver,
	sinceState: number,
	accumulator: number,
}
local sessions: { [Player]: Session } = {}
local logKeeper = RunLog.newKeeper() -- last few finished-run logs per player; released on leave

local function sendState(player: Player, session: Session)
	stateRemote:FireClient(player, Remotes.encodeState(session.driver:snapshot()))
end

local function startRun(player: Player)
	-- The layout is the authored constant; nothing from the client reaches the driver's setup.
	local session: Session = {
		driver = RunDriver.new({
			layout = DebugLayout,
			automated = false,
			hooks = RunHooks.new(DebugLayout),
		}),
		sinceState = 0,
		accumulator = 0,
	}
	sessions[player] = session
	sendState(player, session)
end

-- Cosmetic only (issue #55, ADR 0003): the world is built on the client, so the server's copy of a
-- player's character has no floor at spawn. Anchor it and make it non-colliding so it cannot fall
-- to FallenPartsDestroyHeight and respawn in a loop. No gameplay state; the lead hitbox stays the
-- fixed Crossing hitbox. The client drives its own copy as the lead (src/client/LeadAvatar).
local function pinCharacter(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root and root:IsA("BasePart") then
		root.Anchored = true
	end
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
		end
	end
end

Players.PlayerAdded:Connect(function(player: Player)
	player.CharacterAdded:Connect(pinCharacter)
	if player.Character then
		task.spawn(pinCharacter, player.Character)
	end
end)
for _, player in Players:GetPlayers() do
	player.CharacterAdded:Connect(pinCharacter)
	if player.Character then
		task.spawn(pinCharacter, player.Character)
	end
end

Players.PlayerAdded:Connect(startRun)
for _, player in Players:GetPlayers() do
	startRun(player)
end

Players.PlayerRemoving:Connect(function(player)
	sessions[player] = nil -- drops the driver and its RunState
	logKeeper:release(player)
end)

steerRemote.OnServerEvent:Connect(function(player: Player, payload: any)
	local session = sessions[player]
	if session then
		session.driver:steer(workspace:GetServerTimeNow(), payload)
	end
end)

replayRemote.OnServerEvent:Connect(function(player: Player)
	local session = sessions[player]
	if session and session.driver:replay(workspace:GetServerTimeNow()) then
		session.sinceState = STATE_INTERVAL -- push the fresh state on the next step
		session.accumulator = 0
	end
end)

RunService.Heartbeat:Connect(function(dt: number)
	for player, session in sessions do
		local ok, err = pcall(function()
			local steps, carried = TickPacer.plan(session.accumulator, dt, RunDriver.TICK_DT)
			session.accumulator = carried
			for _ = 1, steps do
				for _, e in session.driver:tick(RunDriver.TICK_DT) do
					eventRemote:FireClient(player, e)
					if e.kind == "complete" or e.kind == "defeated" then
						local log = session.driver:runLog()
						logKeeper:add(player, log)
						RunLog.print(log)
					end
				end
			end
			session.sinceState += dt
			if session.sinceState >= STATE_INTERVAL then
				session.sinceState = 0
				sendState(player, session)
			end
		end)
		if not ok then
			warn(`run session dropped after an error: {err}`)
			sessions[player] = nil
			logKeeper:release(player)
		end
	end
end)
