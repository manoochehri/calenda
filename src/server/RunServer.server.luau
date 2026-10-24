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

type Session = { driver: RunDriver.RunDriver, sinceState: number }
local sessions: { [Player]: Session } = {}

local function sendState(player: Player, session: Session)
	stateRemote:FireClient(player, Remotes.encodeState(session.driver:snapshot()))
end

local function startRun(player: Player)
	-- The layout is the authored constant; nothing from the client reaches the driver's setup.
	local session: Session = {
		driver = RunDriver.new({ layout = DebugLayout, automated = false }),
		sinceState = 0,
	}
	sessions[player] = session
	sendState(player, session)
end

Players.PlayerAdded:Connect(startRun)
for _, player in Players:GetPlayers() do
	startRun(player)
end

Players.PlayerRemoving:Connect(function(player)
	sessions[player] = nil -- drops the driver and its RunState
end)

steerRemote.OnServerEvent:Connect(function(player: Player, payload: any)
	local session = sessions[player]
	if session then
		session.driver:steer(os.clock(), payload)
	end
end)

replayRemote.OnServerEvent:Connect(function(player: Player)
	local session = sessions[player]
	if session and session.driver:replay(os.clock()) then
		session.sinceState = STATE_INTERVAL -- push the fresh state on the next step
	end
end)

RunService.Heartbeat:Connect(function(dt: number)
	for player, session in sessions do
		for _, e in session.driver:tick(dt) do
			eventRemote:FireClient(player, e)
		end
		session.sinceState += dt
		if session.sinceState >= STATE_INTERVAL then
			session.sinceState = 0
			sendState(player, session)
		end
	end
end)
