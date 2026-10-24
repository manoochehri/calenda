--!strict
-- Client entry point (issues #10, #13): wires the server's State/Event remotes to the camera, the
-- input controller, the crowd view and the HUD. Everything it decides comes from pure, Lune-tested
-- modules in ReplicatedStorage.Shared; this file only connects Roblox services.
-- The client sends a steering intent and a replay request, nothing else (Remotes trust model).
--
-- IN-ENGINE BEHAVIOUR IS UNVERIFIED (not run in Studio by the author): see the PR checklist.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraRig = require(Shared:WaitForChild("CameraRig"))
local Config = require(Shared:WaitForChild("Config"))
local DebugLayout = require(Shared:WaitForChild("DebugLayout"))
local InputIntent = require(Shared:WaitForChild("InputIntent"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local RunView = require(Shared:WaitForChild("RunView"))
local Steering = require(Shared:WaitForChild("Steering"))
local VisualBudget = require(Shared:WaitForChild("VisualBudget"))

local TouchControls = require(script.Parent:WaitForChild("TouchControls"))
local Backdrop = require(script.Parent:WaitForChild("Backdrop"))
local ClusterView = require(script.Parent:WaitForChild("ClusterView"))
local CrowdView = require(script.Parent:WaitForChild("CrowdView"))
local Hud = require(script.Parent:WaitForChild("Hud"))
local InputController = require(script.Parent:WaitForChild("InputController"))
local SectionsView = require(script.Parent:WaitForChild("SectionsView"))
local ObstacleView = require(script.Parent:WaitForChild("ObstacleView"))

local CAMERA_X_RATE = 8 -- [default] easing of the lead's drawn x and the camera
local PULLBACK_RATE = 2 -- [default] easing of the camera pullback as the parade grows

local remotes = ReplicatedStorage:WaitForChild(Remotes.folderName)
local steerRemote = remotes:WaitForChild(Remotes.names.steer) :: RemoteEvent
local replayRemote = remotes:WaitForChild(Remotes.names.replay) :: RemoteEvent
local stateRemote = remotes:WaitForChild(Remotes.names.state) :: RemoteEvent
local eventRemote = remotes:WaitForChild(Remotes.names.event) :: RemoteEvent

Backdrop.build()
TouchControls.disable()

local input = InputController.new(Steering.bound(DebugLayout.halfWidth), function(x: number)
	steerRemote:FireServer({ x = x })
end)
local hud = Hud.new(function()
	replayRemote:FireServer()
end)
local crowd = CrowdView.new()
local sections = SectionsView.new(Config.startingTotal)
local clusters = ClusterView.new(DebugLayout)
local obstacleFeedback = ObstacleView.new(DebugLayout)
local leadZNow = 0 -- last drawn lead z, where shots and peel-offs start

local latest: Remotes.StatePayload? = nil
local receivedAt = 0
local drawnX = 0
local pullback = 1

local function looksLikeState(p: any): boolean
	return type(p) == "table"
		and type(p.t) == "number"
		and type(p.z) == "number"
		and type(p.x) == "number"
		and type(p.total) == "number"
end

-- The run's end is read from State (`over`, `outcome`); a State arrives every 0.1 s, so this
-- recovers even when the one-off "complete" Event came before this listener existed.
stateRemote.OnClientEvent:Connect(function(payload: any)
	if not looksLikeState(payload) then
		return
	end
	local state = payload :: Remotes.StatePayload
	if RunView.isNewRun(if latest then latest.t else nil, state.t) then
		input:reset(state.x)
		drawnX = state.x
		pullback = 1
		sections:reset(RunView.wholeTotal(state.total))
		clusters:reset()
		obstacleFeedback:reset()
	end
	latest = state
	receivedAt = os.clock()
end)

-- Gates and the obstacle change the total: pop the counter. (The new total itself arrives in State.)
eventRemote.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if payload.kind == "gate" then
		hud:pop()
	elseif payload.kind == "obstacle" then
		-- A repeated event for the same obstacle plays nothing (ObstacleFeedback dedupes).
		if obstacleFeedback:onObstacle(payload, drawnX, leadZNow) then
			hud:pop()
		end
	elseif payload.kind == "cluster" then
		clusters:onCluster(payload)
	elseif payload.kind == "attack" then
		clusters:onAttack(payload) -- hook for issue #36; draws nothing yet
	end
end)

RunService:BindToRenderStep(
	"CalendaFrame",
	Enum.RenderPriority.Camera.Value + 1,
	function(dt: number)
		local state = latest
		if state == nil then
			return
		end
		local now = os.clock()
		local x, z, t =
			RunView.leadPosition(state, now - receivedAt, Config.speed, DebugLayout.plazaStart)

		input:step(dt, now)
		drawnX = CameraRig.smooth(drawnX, x, dt, CAMERA_X_RATE)
		local total = RunView.wholeTotal(state.total)
		local swirl = sections:update(drawnX, z, total, dt)
		crowd:update(drawnX, z, total, dt, swirl)
		leadZNow = z
		clusters:update(t, drawnX, z, dt)
		obstacleFeedback:update(dt)

		local plan = VisualBudget.allocate(total)
		pullback = CameraRig.smooth(pullback, plan.cameraPullback, dt, PULLBACK_RATE)
		local pose = CameraRig.pose(drawnX, z, pullback)
		local camera = Workspace.CurrentCamera
		if camera then
			camera.CameraType = Enum.CameraType.Scriptable
			camera.FieldOfView = CameraRig.FIELD_OF_VIEW
			camera.CFrame = CFrame.lookAt(
				Vector3.new(pose.px, pose.py, pose.pz),
				Vector3.new(pose.lx, pose.ly, pose.lz)
			)
		end

		hud:update(RunView.hud(state), InputIntent.hintVisible(t, input:hasSteered(), state.over))
	end
)
