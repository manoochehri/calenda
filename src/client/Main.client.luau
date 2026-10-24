--!strict
-- Client entry point (issues #10, #13): wires the server's State/Event remotes to the camera, the
-- input controller, the crowd view and the HUD. Everything it decides comes from pure, Lune-tested
-- modules in ReplicatedStorage.Shared; this file only connects Roblox services.
-- The client sends a steering intent, a replay request and one payload-free Start request
-- after the loading screen is ready (Remotes trust model).
--
-- IN-ENGINE BEHAVIOUR IS UNVERIFIED (not run in Studio by the author): see the PR checklist.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StartupTrace = require(script.Parent:WaitForChild("StartupTrace"))
local startupTrace = StartupTrace.trace
local TIMING = StartupTrace.enabled -- opt-in startup timing (#73): every call below is free when false
local timedRequire = StartupTrace.timedRequire
if TIMING then
	startupTrace:mark("Main.client script start")
end

local CameraRig = timedRequire("Shared", Shared, "CameraRig")
local Config = StartupTrace.Config
local DebugLayout = timedRequire("Shared", Shared, "DebugLayout")
local HitFeedback = timedRequire("Shared", Shared, "HitFeedback")
local HpBar = timedRequire("Shared", Shared, "HpBar")
local HpExtension = timedRequire("Shared", Shared, "HpExtension")
local InputIntent = timedRequire("Shared", Shared, "InputIntent")
local Remotes = timedRequire("Shared", Shared, "Remotes")
local ResetPlan = timedRequire("Shared", Shared, "ResetPlan")
local RunView = timedRequire("Shared", Shared, "RunView")
local ServerClock = timedRequire("Shared", Shared, "ServerClock")
local StartFlow = timedRequire("Shared", Shared, "StartFlow")
local StartupProgress = timedRequire("Shared", Shared, "StartupProgress")
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
local SfxPlayer = timedRequire("Client", script.Parent, "SfxPlayer")
local SectionsView = timedRequire("Client", script.Parent, "SectionsView")
local ObstacleView = timedRequire("Client", script.Parent, "ObstacleView")
local StartupScreen = timedRequire("Client", script.Parent, "StartupScreen")

local CAMERA_X_RATE = 8 -- [default] easing of the lead's drawn x and the camera

local remotes = ReplicatedStorage:WaitForChild(Remotes.folderName)
local steerRemote = remotes:WaitForChild(Remotes.names.steer) :: RemoteEvent
local replayRemote = remotes:WaitForChild(Remotes.names.replay) :: RemoteEvent
local startRemote = remotes:WaitForChild(Remotes.names.start) :: RemoteEvent
local stateRemote = remotes:WaitForChild(Remotes.names.state) :: RemoteEvent
local eventRemote = remotes:WaitForChild(Remotes.names.event) :: RemoteEvent

local startupFlow = StartFlow.new()
local startupProgress = StartupProgress.new({ "client", "street", "world", "server" })
local startupScreen: StartupScreen.Screen
local music: any
local function updateProgress()
	local fraction = StartupProgress.fraction(startupProgress)
	StartFlow.progress(startupFlow, fraction)
	startupScreen:setProgress(fraction)
	if startupFlow.phase == "title" then
		startupScreen:showTitle()
	end
end
local function onPlay()
	if StartFlow.play(startupFlow) then
		startupScreen:hide()
		music:start(os.clock()) -- start the selected loop on Jugar, before the server's first running State
		startRemote:FireServer()
	end
end
startupScreen = StartupScreen.new(onPlay)
startupScreen:setMessage("Cargando el desfile...")

-- Register both server listeners before the first ready State can unlock the title. The only
-- client message that starts the run is the user's single, payload-free Play request.
local listenersReady = false
local function markClientReady()
	if listenersReady then
		return
	end
	listenersReady = true
	StartupProgress.report(startupProgress, "client", 1)
	updateProgress()
end
local function markWorldReady()
	if StartupProgress.report(startupProgress, "world", 1) then
		updateProgress()
	end
end

-- The world builder is a sibling LocalScript. Observe its concrete model rather than advancing
-- the progress bar by elapsed time or pretending a frame has loaded.
task.spawn(function()
	while Workspace:FindFirstChild("CalendaWorld") == nil do
		RunService.Heartbeat:Wait()
	end
	markWorldReady()
end)

local stepAt = startupTrace:begin()
Backdrop.build(function(fraction: number)
	StartupProgress.report(startupProgress, "street", fraction)
	updateProgress()
end)
stepAt = startupTrace:lap("Backdrop.build", stepAt)
TouchControls.disable()

local input = InputController.new(Steering.bound(DebugLayout.halfWidth), function(x: number)
	steerRemote:FireServer({ x = x })
end)
stepAt = startupTrace:lap("InputController.new", stepAt)
music = MusicPlayer.new() -- one selected full-mix loop (issue #21)
stepAt = startupTrace:lap("MusicPlayer.new", stepAt)
local sfx = SfxPlayer.new() -- silent while Config.sfx ids are empty (issue #62)
stepAt = startupTrace:lap("SfxPlayer.new", stepAt)
local hud = Hud.new(function()
	replayRemote:FireServer()
	sfx:play("replayClick", music:intensity(), os.clock())
end, function(muted: boolean)
	music:setMuted(muted)
end)
stepAt = startupTrace:lap("Hud.new", stepAt)
local crowd = CrowdView.new() -- pools are lazy: nothing is prewarmed here
stepAt = startupTrace:lap("CrowdView.new", stepAt)
local leadAvatar = LeadAvatar.new() -- the player's own character is the lead (issue #55)
stepAt = startupTrace:lap("LeadAvatar.new", stepAt)
local sections = SectionsView.new(Config.startingTotal)
stepAt = startupTrace:lap("SectionsView.new", stepAt)
local clusters = ClusterView.new(DebugLayout)
stepAt = startupTrace:lap("ClusterView.new", stepAt)
local obstacleFeedback = ObstacleView.new(DebugLayout)
stepAt = startupTrace:lap("ObstacleView.new", stepAt)
local hitFx = HitFeedback.new() -- hit jolt, screen shake and flash (issue #50)
stepAt = startupTrace:lap("HitFeedback.new", stepAt)
local hudClock = 0
local leadZNow = 0 -- last drawn lead z, where shots and peel-offs start
local endFlow = EndFlow.new() -- finale, breakup, results gating (issue #16)
startupTrace:lap("EndFlow.new", stepAt)

-- Startup timing (#73): true until the mark is taken, then a single boolean test per frame/event.
-- Always false when the flag is off, so the render step and State handler skip all of it.
local awaitingFirstState = TIMING
local awaitingFirstFrame = TIMING

local latest: Remotes.StatePayload? = nil
local receivedAt = 0
local drawnX = 0
local pullback = 1
local serverClock = ServerClock.new() -- smoothed lead timeline (issue #85)
local frozenCamera: CFrame? = nil -- Config.debug.freezeCamera A/B only
if Config.debug.noShadows then
	game:GetService("Lighting").GlobalShadows = false
end

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
	if awaitingFirstState then
		awaitingFirstState = false
		startupTrace:mark("first State received")
		StartupTrace.finishIfReady()
	end
	local state = payload :: Remotes.StatePayload
	if Remotes.isPhase(state.phase) then
		StartFlow.serverPhase(startupFlow, state.phase)
		if state.phase == "ready" then
			StartupProgress.report(startupProgress, "server", 1)
		end
		updateProgress()
	end
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
			serverClock:reset()
		end
		handlers.sections = function()
			sections:reset(RunView.wholeTotal(state.total))
		end
		handlers.music = function()
			music:reset()
		end
		handlers.audio = function()
			music:resetAudio()
			sfx:reset()
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
	serverClock:observe(state, receivedAt)
end)

-- Gates and the obstacle change the total: pop the counter. (The new total itself arrives in State.)
eventRemote.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then
		return
	end
	sfx:onEvent(payload, music:intensity(), os.clock())
	crowd:onEvent(payload, if latest then latest.t else 0) -- where new followers come from (issue #68)
	sections:onEvent(payload)
	leadAvatar:onEvent(payload)
	if payload.kind == "gate" then
		hud:pop()
	elseif payload.kind == "obstacle" then
		-- A repeated event for the same obstacle plays nothing (ObstacleFeedback dedupes).
		if obstacleFeedback:onObstacle(payload, drawnX, leadZNow) then
			hud:pop()
		end
	elseif payload.kind == "cluster" then
		if clusters:onCluster(payload) then
			local conversion = { kind = "conversion" }
			crowd:onEvent(conversion, if latest then latest.t else 0)
			sections:onEvent(conversion)
			leadAvatar:onEvent(conversion)
		end
		sections:onShot(payload) -- dancer sections toss on gift shots (issue #20)
	elseif payload.kind == "miss" then
		clusters:onMiss(payload) -- continuous fire with no target: flies on and fades (issue #67)
		sections:onShot(payload) -- a miss can be a gift shot too: dancers toss
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
		if awaitingFirstFrame then
			awaitingFirstFrame = false
			startupTrace:mark("first CalendaFrame render-step callback")
			StartupTrace.finishIfReady()
		end
		local state = latest
		if state == nil then
			return
		end
		if state.phase == "ready" then
			return -- server clock, input and presentation stay paused behind the title screen
		end
		local now = os.clock()
		local x, z, t
		if Config.debug.rawExtrapolation then
			x, z, t =
				RunView.leadPosition(state, now - receivedAt, Config.speed, DebugLayout.plazaStart)
		else
			x, z, t = serverClock:sample(now, Config.speed, DebugLayout.plazaStart)
		end

		input:step(dt, now)
		drawnX = CameraRig.smooth(drawnX, x, dt, CAMERA_X_RATE)
		local total = RunView.wholeTotal(state.total)
		local swirl = sections:update(drawnX, z, total, dt)
		local fx = endFlow:frame(state, drawnX, z, dt, total)
		local hasAvatar = leadAvatar:update(drawnX, z, dt, fx.tumble, fx.lift, total)
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
		music:setPeak(fx.musicIntensity)
		music:setDucked(fx.defeated)
		music:update(total, now)
		sfx:update(total, music:intensity(), dt, now)
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
			if camera.CameraType ~= Enum.CameraType.Scriptable then
				camera.CameraType = Enum.CameraType.Scriptable
			end
			if camera.FieldOfView ~= CameraRig.FIELD_OF_VIEW then
				camera.FieldOfView = CameraRig.FIELD_OF_VIEW
			end
			local cf = CFrame.lookAt(
				Vector3.new(pose.px, pose.py, pose.pz),
				Vector3.new(pose.lx, pose.ly, pose.lz)
			) * CFrame.new(hit.shakeX, hit.shakeY, 0) -- decaying screen punch, camera space
			if Config.debug.freezeCamera then
				frozenCamera = frozenCamera or cf
				cf = frozenCamera :: CFrame
			end
			camera.CFrame = cf
		end

		hud:setHp(HpBar.view(HpExtension.read(state)), hudClock)
		hud:applyHit(hit)
		hud:update(
			fx.view(RunView.hud(state)),
			InputIntent.hintVisible(t, input:hasSteered(), state.over)
		)
	end
)

-- State/Event listeners and the render loop are now attached. Start stays withheld until both
-- actual world builders and the server's paused State are ready.
markClientReady()
