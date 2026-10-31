--!strict
-- Client entry point (issues #10, #13): wires the server's State/Event remotes to the camera, the
-- input controller, the crowd view and the HUD. Everything it decides comes from pure, Lune-tested
-- modules in ReplicatedStorage.Shared; this file only connects Roblox services.
-- The client sends a steering intent, a replay request and one payload-free Start request
-- after the loading screen is ready and the opening camera move has settled (Remotes trust model;
-- issue #177: the move is presentation, the server still starts the run only on that request).
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

-- Issue #218: build the loading cover before the ~25 modules below load, so the screen shows the
-- title backdrop straight away instead of black. Jugar is wired to `onPlayPressed` further down.
local StartupScreen = timedRequire("Client", script.Parent, "StartupScreen")
local onPlayPressed: (() -> ())? = nil
local startupScreen: StartupScreen.Screen = StartupScreen.new(function()
	if onPlayPressed then
		onPlayPressed()
	end
end)
startupScreen:setMessage("Cargando el desfile...")

local AudioIntensity = timedRequire("Shared", Shared, "AudioIntensity")
local CameraRig = timedRequire("Shared", Shared, "CameraRig")
local Config = StartupTrace.Config
local DebugLayout = timedRequire("Shared", Shared, "DebugLayout")
local HitFeedback = timedRequire("Shared", Shared, "HitFeedback")
local Remotes = timedRequire("Shared", Shared, "Remotes")
local ResetPlan = timedRequire("Shared", Shared, "ResetPlan")
local RunView = timedRequire("Shared", Shared, "RunView")
local CrowdMath = timedRequire("Shared", Shared, "CrowdMath")
local ServerClock = timedRequire("Shared", Shared, "ServerClock")
local StartFlow = timedRequire("Shared", Shared, "StartFlow")
local StartSequence = timedRequire("Shared", Shared, "StartSequence")
local IntroCamera = timedRequire("Shared", Shared, "IntroCamera")
local StartupProgress = timedRequire("Shared", Shared, "StartupProgress")
local Steering = timedRequire("Shared", Shared, "Steering")
local LevelInterstitial = timedRequire("Shared", Shared, "LevelInterstitial")
local ViewMap = timedRequire("Shared", Shared, "ViewMap")
local VisualBudget = timedRequire("Shared", Shared, "VisualBudget")

local TouchControls = timedRequire("Client", script.Parent, "TouchControls")
local Backdrop = timedRequire("Client", script.Parent, "Backdrop")
local ClusterView = timedRequire("Client", script.Parent, "ClusterView")
local CrowdView = timedRequire("Client", script.Parent, "CrowdView")
local EndFlow = timedRequire("Client", script.Parent, "EndFlow")
local Hud = timedRequire("Client", script.Parent, "Hud")
local InputController = timedRequire("Client", script.Parent, "InputController")
local LevelInterstitialView = timedRequire("Client", script.Parent, "LevelInterstitialView")
local LaneView = timedRequire("Client", script.Parent, "LaneView")
local LeadAvatar = timedRequire("Client", script.Parent, "LeadAvatar")
local MusicPlayer = timedRequire("Client", script.Parent, "MusicPlayer")
local SfxPlayer = timedRequire("Client", script.Parent, "SfxPlayer")
local SectionsView = timedRequire("Client", script.Parent, "SectionsView")
local ObstacleView = timedRequire("Client", script.Parent, "ObstacleView")
local CountdownView = timedRequire("Client", script.Parent, "CountdownView")

local CAMERA_X_RATE = 8 -- [default] easing of the lead's drawn x and the camera

local remotes = ReplicatedStorage:WaitForChild(Remotes.folderName)
local steerRemote = remotes:WaitForChild(Remotes.names.steer) :: RemoteEvent
local replayRemote = remotes:WaitForChild(Remotes.names.replay) :: RemoteEvent
local startRemote = remotes:WaitForChild(Remotes.names.start) :: RemoteEvent
local stateRemote = remotes:WaitForChild(Remotes.names.state) :: RemoteEvent
local eventRemote = remotes:WaitForChild(Remotes.names.event) :: RemoteEvent

local startupFlow = StartFlow.new()
local startupProgress = StartupProgress.new({ "client", "street", "world", "server" })
local music: any
local function updateProgress()
	local fraction = StartupProgress.fraction(startupProgress)
	StartFlow.progress(startupFlow, fraction)
	startupScreen:setProgress(fraction)
	if startupFlow.phase == "title" then
		startupScreen:showTitle()
	end
end
-- Jugar -> camera move (#177) -> tres, dos, uno (#203) -> one Start request, while it plays.
local sequence: StartSequence.Sequence? = nil
local countdownView: CountdownView.View? = nil
onPlayPressed = function()
	if StartFlow.play(startupFlow) then
		music:start(os.clock()) -- start the selected loop on Jugar, before the server's first running State
		startupScreen:finishIntro()
		sequence = StartSequence.begin(os.clock())
		countdownView = CountdownView.new()
	end
end

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

local input = InputController.new(
	Steering.bound(DebugLayout.halfWidth, DebugLayout.leadLimit),
	function(x: number)
		steerRemote:FireServer({ x = x })
	end
)
stepAt = startupTrace:lap("InputController.new", stepAt)
local interstitial: LevelInterstitial.Flow? = nil
local skipInterstitial = false
local interstitialView = LevelInterstitialView.new(function()
	skipInterstitial = true
end)
music = MusicPlayer.new() -- one selected full-mix loop (issue #21)
stepAt = startupTrace:lap("MusicPlayer.new", stepAt)
local sfx = SfxPlayer.new() -- silent while Config.sfx ids are empty (issue #62)
stepAt = startupTrace:lap("SfxPlayer.new", stepAt)
local hud = Hud.new(function()
	replayRemote:FireServer()
	sfx:play("replayClick", music:intensity(), os.clock())
end)
stepAt = startupTrace:lap("Hud.new", stepAt)
local crowd = CrowdView.new() -- pools are lazy: nothing is prewarmed here
stepAt = startupTrace:lap("CrowdView.new", stepAt)
local leadAvatar = LeadAvatar.new() -- the player's own character is the lead (issue #55)
stepAt = startupTrace:lap("LeadAvatar.new", stepAt)
local laneView = LaneView.new(DebugLayout) -- visible lanes and the lead's lane marker (issue #193)
stepAt = startupTrace:lap("LaneView.new", stepAt)
local sections = SectionsView.new(Config.startingTotal)
stepAt = startupTrace:lap("SectionsView.new", stepAt)
local clusters = ClusterView.new(DebugLayout)
stepAt = startupTrace:lap("ClusterView.new", stepAt)
local obstacleFeedback = ObstacleView.new(DebugLayout)
stepAt = startupTrace:lap("ObstacleView.new", stepAt)
local hitFx = HitFeedback.new() -- hit jolt and screen shake (issue #50)
stepAt = startupTrace:lap("HitFeedback.new", stepAt)
local leadZNow = 0 -- last drawn lead z, where shots and peel-offs start
local endFlow = EndFlow.new() -- finale, breakup, results gating (issue #16)
startupTrace:lap("EndFlow.new", stepAt)

-- Startup timing (#73): true until the mark is taken, then a single boolean test per frame/event.
-- Always false when the flag is off, so the render step and State handler skip all of it.
local awaitingFirstState = TIMING
local awaitingFirstFrame = TIMING

local latest: Remotes.StatePayload? = nil
local lastLevel: number? = nil
local receivedAt = 0
local drawnX = 0
local pullback = 1
local serverClock = ServerClock.new() -- smoothed lead timeline (issue #85)
local frozenCamera: CFrame? = nil -- Config.debug.freezeCamera A/B only
if Config.debug.noShadows then
	game:GetService("Lighting").GlobalShadows = false
end

-- Puts the camera at `pose`, with the screen punch (camera space) applied on top.
local function placeCamera(pose: CameraRig.Pose, shakeX: number, shakeY: number)
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
		) * CFrame.new(shakeX, shakeY, 0) -- decaying screen punch, camera space
		if Config.debug.freezeCamera then
			frozenCamera = frozenCamera or cf
			cf = frozenCamera :: CFrame
		end
		camera.CFrame = cf
	end
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
	local levelTransition = latest ~= nil and state.level > latest.level
	if RunView.isNewRun(if latest then latest.t else nil, state.t) and not levelTransition then
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
		handlers.hit = function()
			hitFx:reset()
			hud:resetHit()
		end
		handlers.obstacles = function()
			obstacleFeedback:reset()
		end
		ResetPlan.apply(handlers, warn)
		lastLevel = state.level
		interstitial = nil
		skipInterstitial = false
		interstitialView:hide()
		input:setEnabled(true)
	elseif lastLevel ~= nil and state.level > (lastLevel :: number) then
		-- The server has already selected the next level; hold presentation and steering until
		-- this local card has been shown or skipped. The next State remains authoritative.
		interstitial = LevelInterstitial.new(os.clock(), state.level)
		skipInterstitial = false
		interstitialView:show(state.level, state.levelName)
		input:setEnabled(false)
		lastLevel = state.level
	elseif lastLevel ~= nil and state.level < (lastLevel :: number) then
		-- Replay can arrive with a lower level after the run clock resets.
		lastLevel = state.level
		interstitial = nil
		skipInterstitial = false
		interstitialView:hide()
		input:setEnabled(true)
	else
		lastLevel = state.level
	end
	latest = state
	receivedAt = os.clock()
	serverClock:observe(state, receivedAt)
end)

-- World reactions and sounds follow server events; crowd totals arrive in State.
eventRemote.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then
		return
	end
	sfx:onEvent(payload, music:intensity(), os.clock())
	crowd:onEvent(payload, if latest then latest.t else 0) -- where new followers come from (issue #68)
	sections:onEvent(payload)
	leadAvatar:onEvent(payload)
	if payload.kind == "obstacle" then
		-- A repeated event for the same obstacle plays nothing (ObstacleFeedback dedupes).
		obstacleFeedback:onObstacle(payload, drawnX, leadZNow)
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
			hitFx:hit(HitFeedback.intensity(payload.before, payload.after))
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
		if sequence == nil and (startupFlow.phase == "loading" or startupFlow.phase == "title") then
			-- The title (#211): the street shows behind it and the lead stands still at its start,
			-- framed on the right by the title camera. The move to the game camera starts on Play.
			local titleX = ViewMap.x(0)
			leadAvatar:hold(0, 0)
			placeCamera(IntroCamera.titlePose(titleX, 0), 0, 0)
			return
		end
		if sequence ~= nil then
			-- Opening move (#177), then tres, dos, uno (#203): the run is still paused, so input and
			-- the server clock wait. The lead stands at its start (x 0, z 0) while the camera settles.
			local now = os.clock()
			-- The move waits for the avatar to exist (IntroCamera.AVATAR_WAIT at most).
			local hasAvatar = leadAvatar:update(0, 0, dt)
			local frame = StartSequence.step(sequence, now, ViewMap.x(0), 0, hasAvatar)
			placeCamera(frame.pose, 0, 0)
			if countdownView ~= nil then
				countdownView:show(frame.word, frame.look)
			end
			local introState = latest
			if introState ~= nil and StartFlow.shouldUpdateMusic(startupFlow) then
				-- Music keeps moving through the opening move, as the count-in did.
				music:update(RunView.wholeTotal(introState.total), now)
			end
			if frame.startDue then
				sequence = nil
				if countdownView ~= nil then
					countdownView:destroy()
					countdownView = nil
				end
				startRemote:FireServer() -- the single payload-free Start, after the countdown
			end
			return
		end
		local state = latest
		if state == nil then
			return
		end
		if state.phase == "ready" then
			if StartFlow.shouldUpdateMusic(startupFlow) then
				music:update(RunView.wholeTotal(state.total), os.clock())
			end
			return -- server clock, input and presentation stay paused behind the title screen
		end
		if interstitial ~= nil then
			local frame = LevelInterstitial.step(interstitial, os.clock(), skipInterstitial)
			if frame.advance then
				interstitial = nil
				skipInterstitial = false
				interstitialView:hide()
				input:setEnabled(true)
			end
			return -- do not steer or update gameplay presentation through the card
		end
		local now = os.clock()
		debug.profilebegin("Calenda/ClockAndInput")
		local x, z, t
		if Config.debug.rawExtrapolation then
			x, z, t =
				RunView.leadPosition(state, now - receivedAt, Config.speed, DebugLayout.plazaStart)
		else
			x, z, t = serverClock:sample(now, Config.speed, DebugLayout.plazaStart)
		end

		input:step(dt, now)
		drawnX = CameraRig.smooth(drawnX, x, dt, CAMERA_X_RATE)
		debug.profileend()

		debug.profilebegin("Calenda/CrowdAndSections")
		local total = RunView.wholeTotal(state.total)
		clusters:setSections(CrowdMath.sectionCount(total)) -- shot streams (issue #63)
		local swirl = sections:update(drawnX, z, total, dt)
		local fx = endFlow:frame(state, drawnX, z, dt, total)
		local hasAvatar = leadAvatar:update(drawnX, z, dt, fx.tumble, fx.lift, total)
		laneView:update(drawnX, z)
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
		debug.profileend()

		debug.profilebegin("Calenda/AudioAndEffects")
		leadZNow = z
		music:setDucked(fx.defeated)
		clusters:setPullback(pullback) -- the camera reach decides where a mob fades in (issue #65)
		clusters:update(t, drawnX, z, dt)
		-- Issue #65 tension: the crowd's peak and the approaching wave's threat, whichever is higher
		music:setPeak(
			AudioIntensity.withPeak(
				fx.musicIntensity or 0,
				AudioIntensity.threatPeak(clusters:threat())
			)
		)
		music:update(total, now)
		sfx:update(total, music:intensity(), dt, now)
		obstacleFeedback:update(dt)
		debug.profileend()

		debug.profilebegin("Calenda/CameraAndHud")
		local plan = VisualBudget.allocate(total)
		pullback = CameraRig.smooth(
			pullback,
			plan.cameraPullback * fx.pullback,
			dt,
			CameraRig.PULLBACK_RATE
		)
		hitFx:step(dt)
		local hit = hitFx:sample()
		local pose = CameraRig.pose(ViewMap.x(drawnX), z, pullback) -- mirrored: see ViewMap
		placeCamera(pose, hit.shakeX, hit.shakeY)

		hud:applyHit(hit)
		hud:update(fx.view(RunView.hud(state)))
		debug.profileend()
	end
)

-- State/Event listeners and the render loop are now attached. Start stays withheld until both
-- actual world builders and the server's paused State are ready.
markClientReady()
