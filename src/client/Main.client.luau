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
local StartupTrace = require(script.Parent:WaitForChild("StartupTrace"))
local startupTrace = StartupTrace.trace
local TIMING = StartupTrace.enabled -- opt-in startup timing (#73): free when false
local timedRequire = StartupTrace.timedRequire
if TIMING then
	startupTrace:mark("Main.client script start")
end

local Config = StartupTrace.Config
local CameraRig = timedRequire("Shared", Shared, "CameraRig")
local DebugLayout = timedRequire("Shared", Shared, "DebugLayout")
local HitFeedback = timedRequire("Shared", Shared, "HitFeedback")
local HpBar = timedRequire("Shared", Shared, "HpBar")
local HpExtension = timedRequire("Shared", Shared, "HpExtension")
local InputIntent = timedRequire("Shared", Shared, "InputIntent")
local Remotes = timedRequire("Shared", Shared, "Remotes")
local ResetPlan = timedRequire("Shared", Shared, "ResetPlan")
local RunView = timedRequire("Shared", Shared, "RunView")
local Steering = timedRequire("Shared", Shared, "Steering")
local ViewMap = timedRequire("Shared", Shared, "ViewMap")
local VisualBudget = timedRequire("Shared", Shared, "VisualBudget")

local TouchControls = timedRequire("Client", script.Parent, "TouchControls")
local Backdrop = timedRequire("Client", script.Parent, "Backdrop")
local ClusterView = timedRequire("Client", script.Parent, "ClusterView")
local CrowdView = timedRequire("Client", script.Parent, "CrowdView")
local EndFlow = timedRequire("Client", script.Parent, "EndFlow")
local Hud = timedRequire("Client", script.Parent, "Hud")
local InputController = timedRequire("Client", script.Parent, "InputController")
local LeadAvatar = timedRequire("Client", script.Parent, "LeadAvatar")
local MusicPlayer = timedRequire("Client", script.Parent, "MusicPlayer")
local SectionsView = timedRequire("Client", script.Parent, "SectionsView")
local ObstacleView = timedRequire("Client", script.Parent, "ObstacleView")

local CAMERA_X_RATE = 8 -- [default] easing of the lead's drawn x and the camera

local remotes = ReplicatedStorage:WaitForChild(Remotes.folderName)
local steerRemote = remotes:WaitForChild(Remotes.names.steer) :: RemoteEvent
local replayRemote = remotes:WaitForChild(Remotes.names.replay) :: RemoteEvent
local stateRemote = remotes:WaitForChild(Remotes.names.state) :: RemoteEvent
local eventRemote = remotes:WaitForChild(Remotes.names.event) :: RemoteEvent

startupTrace:measure("Backdrop.build", Backdrop.build)
TouchControls.disable()

local input = startupTrace:measure("InputController.new", function()
	return InputController.new(Steering.bound(DebugLayout.halfWidth), function(x: number)
		steerRemote:FireServer({ x = x })
	end)
end)
local hud = startupTrace:measure("Hud.new", function()
	return Hud.new(function()
		replayRemote:FireServer()
	end)
end)
local crowd = startupTrace:measure("CrowdView.new (lazy pool setup)", CrowdView.new)
local leadAvatar = startupTrace:measure("LeadAvatar.new", LeadAvatar.new) -- own avatar is lead (#55)
local sections = startupTrace:measure("SectionsView.new (lazy pool setup)", function()
	return SectionsView.new(Config.startingTotal)
end)
local clusters = startupTrace:measure("ClusterView.new (lazy pool setup)", function()
	return ClusterView.new(DebugLayout)
end)
local obstacleFeedback = startupTrace:measure("ObstacleView.new (lazy pool setup)", function()
	return ObstacleView.new(DebugLayout)
end)
local hitFx = startupTrace:measure("HitFeedback.new", HitFeedback.new)
local hudClock = 0
local leadZNow = 0 -- last drawn lead z, where shots and peel-offs start
local endFlow = startupTrace:measure("EndFlow.new", EndFlow.new)
local music = startupTrace:measure("MusicPlayer.new", MusicPlayer.new)

local function finishStartupIfReady()
	if
		startupTrace:has("WorldBuilder built")
		and startupTrace:has("first State received")
		and startupTrace:has("first CalendaFrame render-step callback")
	then
		startupTrace:finish()
	end
end

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
	if not startupTrace:has("first State received") then
		startupTrace:mark("first State received")
		finishStartupIfReady()
	end
	local state = payload :: Remotes.StatePayload
	if RunView.isNewRun(if latest then latest.t else nil, state.t) then
		-- Replay checklist (issue #16): ResetPlan warns (never throws) if an item is missing here.
		local handlers = endFlow:resetHandlers()
		handlers.input = function()
			input:reset(state.x)
		end
		handlers.counters = function()
			latest = nil
		end
		handlers.camera = function()
			drawnX = state.x
			pullback = 1
		end
		handlers.sections = function()
			sections:reset(RunView.wholeTotal(state.total))
		end
		handlers.music = function()
			music:reset()
		end
		handlers.clusters = function()
			clusters:reset()
		end
		handlers.hp = function()
			hitFx:reset()
			hud:resetHp()
		end
		handlers.obstacles = function()
			obstacleFeedback:reset()
		end
		ResetPlan.apply(handlers, warn)
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
		sections:onShot(payload) -- dancer sections toss on gift shots (issue #20)
	elseif payload.kind == "attack" then
		-- Cartoon bump of flying bits; false for a duplicate event, which must not re-shake.
		if clusters:onAttack(payload) then
			local maxHp = if latest then latest.maxHp else nil
			hitFx:hit(HitFeedback.intensity(payload.hpBefore, payload.hpAfter, maxHp))
		end
	end
end)

RunService:BindToRenderStep(
	"CalendaFrame",
	Enum.RenderPriority.Camera.Value + 1,
	function(dt: number)
		if not startupTrace:has("first CalendaFrame render-step callback") then
			startupTrace:mark("first CalendaFrame render-step callback")
			finishStartupIfReady()
		end
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
		local fx = endFlow:frame(state, drawnX, z, dt, total)
		local hasAvatar = leadAvatar:update(drawnX, z, dt, fx.tumble, fx.lift)
		crowd:update(
			drawnX,
			z,
			fx.crowdTotal,
			dt,
			swirl,
			fx.tumble,
			fx.lift,
			hasAvatar,
			leadAvatar:fallbackGrace()
		)
		leadZNow = z
		music:update(total, now)
		clusters:update(t, drawnX, z, dt)
		obstacleFeedback:update(dt)

		local plan = VisualBudget.allocate(total)
		pullback = CameraRig.smooth(
			pullback,
			plan.cameraPullback * fx.pullback,
			dt,
			CameraRig.PULLBACK_RATE
		)
		hudClock += dt
		hitFx:step(dt)
		local hit = hitFx:sample()
		local pose = CameraRig.pose(ViewMap.x(drawnX), z, pullback) -- mirrored: see ViewMap
		local camera = Workspace.CurrentCamera
		if camera then
			camera.CameraType = Enum.CameraType.Scriptable
			camera.FieldOfView = CameraRig.FIELD_OF_VIEW
			camera.CFrame = CFrame.lookAt(
				Vector3.new(pose.px, pose.py, pose.pz),
				Vector3.new(pose.lx, pose.ly, pose.lz)
			) * CFrame.new(hit.shakeX, hit.shakeY, 0) -- decaying screen punch, camera space
		end

		hud:setHp(HpBar.view(HpExtension.read(state)), hudClock)
		hud:applyHit(hit)
		hud:update(
			fx.view(RunView.hud(state)),
			InputIntent.hintVisible(t, input:hasSteered(), state.over)
		)
	end
)
