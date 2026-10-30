--!strict
-- Original, primitive-only title/loading screen (issues #72, #176, #203). Title (logo, subtitle,
-- loading) on the left; the player's own avatar marching in place on the right; a papel picado
-- banner across the top; a small PROTOTIPO footer. No image assets, no asset IDs. Layout numbers
-- come from shared/TitleLayout (tested at every aspect); the march maths from shared/AvatarSlot.
-- Nothing here flashes or animates brightness (#85, #171): only slow rotation sways.
-- ENGINE PRESENTATION IS UNVERIFIED until the Studio checklist is completed. In particular:
--   * Cloning the local character into a ViewportFrame/WorldModel, and that a shipped walk
--     Animation (taken from the character's "Animate" script, never an invented ID) plays there.
--   * Whether UIGradient and UIStroke layers on the logo look as intended.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GuiLayout = require(script.Parent:WaitForChild("GuiLayout"))
local TypeStyle = require(script.Parent:WaitForChild("TypeStyle"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ScreenLayout = require(Shared:WaitForChild("ScreenLayout"))
local TitleLayout = require(Shared:WaitForChild("TitleLayout"))
local AvatarSlot = require(Shared:WaitForChild("AvatarSlot"))

export type Screen = {
	setProgress: (self: Screen, fraction: number) -> (),
	setMessage: (self: Screen, message: string) -> (),
	showTitle: (self: Screen) -> (),
	finishIntro: (self: Screen) -> (),
	hide: (self: Screen) -> (),
}

local StartupScreen = {}

local INK = Color3.fromRGB(48, 29, 55)
local CREAM = Color3.fromRGB(255, 244, 219)
local GOLD = Color3.fromRGB(255, 222, 164)
local CRIMSON = Color3.fromRGB(190, 52, 78)
local VERSION_LABEL = "PROTOTIPO"
local SUBTITLE = "Música, fiesta y una gran calenda"
local FLAG_COLORS = {
	Color3.fromRGB(232, 84, 150),
	Color3.fromRGB(244, 130, 40),
	Color3.fromRGB(250, 210, 50),
	Color3.fromRGB(60, 180, 110),
	Color3.fromRGB(60, 140, 230),
	Color3.fromRGB(150, 90, 200),
}
local FLAG_COUNT = 16
local CHARACTER_POLL = 0.25 -- seconds between looks for the player's character

local function round(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function circle(parent: Instance, color: Color3): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = f
	return f
end

local function stroke(parent: Instance, color: Color3, thickness: number)
	local outline = Instance.new("UIStroke")
	outline.Color = color
	outline.Thickness = thickness
	outline.Parent = parent
	return outline
end

local function label(parent: Instance, name: string, text: string, font: Enum.Font): TextLabel
	local item = Instance.new("TextLabel")
	item.Name = name
	item.BackgroundTransparency = 1
	item.Text = text
	item.TextColor3 = CREAM
	item.TextScaled = true
	item.TextWrapped = true
	item.Font = font
	item.Parent = parent
	return item
end

-- Anchor, position, size and text limits of a title element from TitleLayout.
local function place(obj: GuiObject, name: string)
	local e = TitleLayout.element(name)
	assert(e, `no TitleLayout element {name}`)
	obj.AnchorPoint = Vector2.new(e.ax, e.ay)
	obj.Position = UDim2.fromScale(e.x, e.y)
	obj.Size = UDim2.fromScale(e.w, e.h)
	if e.text and obj:IsA("TextLabel") then
		local limit = Instance.new("UITextSizeConstraint")
		limit.MinTextSize = e.text.minSize
		limit.MaxTextSize = e.text.maxSize
		limit.Parent = obj
	end
end

-- A cempasuchil (marigold) from primitives: two rings of round petals and a dark centre.
-- `size` is a UDim2 (square via UIAspectRatioConstraint).
local function marigold(parent: Instance, name: string, position: UDim2, size: UDim2): Frame
	local root = Instance.new("Frame")
	root.Name = name
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = position
	root.Size = size
	root.BackgroundTransparency = 1
	root.Parent = parent
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.Parent = root
	local function ring(count: number, radius: number, petal: number, color: Color3, turn: number)
		for i = 1, count do
			local a = turn + (i - 1) / count * math.pi * 2
			local p = circle(root, color)
			p.Position = UDim2.fromScale(0.5 + radius * math.cos(a), 0.5 + radius * math.sin(a))
			p.Size = UDim2.fromScale(petal, petal)
		end
	end
	ring(10, 0.33, 0.34, Color3.fromRGB(244, 130, 40), 0)
	ring(10, 0.22, 0.28, Color3.fromRGB(252, 176, 52), math.pi / 10)
	local centre = circle(root, Color3.fromRGB(120, 54, 30))
	centre.Position = UDim2.fromScale(0.5, 0.5)
	centre.Size = UDim2.fromScale(0.26, 0.26)
	return root
end

-- The papel picado banner: a cord across the top with cut-paper flags hanging from it.
local function addBanner(parent: Instance)
	local banner = Instance.new("Frame")
	banner.Name = "PapelPicado"
	banner.BackgroundTransparency = 1
	place(banner, "Banner")
	banner.Parent = parent
	local cord = Instance.new("Frame")
	cord.Name = "Cord"
	cord.AnchorPoint = Vector2.new(0.5, 0.5)
	cord.Position = UDim2.fromScale(0.5, 0.09)
	cord.Size = UDim2.new(1, 0, 0, 3)
	cord.BackgroundColor3 = GOLD
	cord.BorderSizePixel = 0
	cord.Parent = banner
	for index = 1, FLAG_COUNT do
		local flag = Instance.new("Frame")
		flag.Name = `Flag{index}`
		flag.AnchorPoint = Vector2.new(0.5, 0)
		flag.Position = UDim2.fromScale((index - 0.5) / FLAG_COUNT, 0.09)
		flag.Size = UDim2.fromScale(0.05, 0.82)
		flag.BackgroundColor3 = FLAG_COLORS[(index - 1) % #FLAG_COLORS + 1]
		flag.BorderSizePixel = 0
		flag.Parent = banner
		round(flag, 3)
		-- Cut-outs: a diamond, two round holes and a scalloped hem, in the backdrop colour.
		local hole = Color3.fromRGB(58, 39, 69)
		local diamond = Instance.new("Frame")
		diamond.AnchorPoint = Vector2.new(0.5, 0.5)
		diamond.Position = UDim2.fromScale(0.5, 0.42)
		diamond.Size = UDim2.fromScale(0.42, 0.28)
		diamond.BackgroundColor3 = hole
		diamond.BorderSizePixel = 0
		diamond.Rotation = 45
		diamond.Parent = flag
		for k = 1, 3 do
			local scallop = circle(flag, hole)
			scallop.Position = UDim2.fromScale((k - 0.5) / 3, 1)
			scallop.Size = UDim2.fromScale(0.3, 0.14)
		end
		local dot = circle(flag, hole)
		dot.Position = UDim2.fromScale(0.5, 0.78)
		dot.Size = UDim2.fromScale(0.18, 0.1)
		-- Slow sway about the cord; rotation only, never brightness.
		flag.Rotation = if index % 2 == 0 then 2 else -2
		TweenService:Create(
			flag,
			TweenInfo.new(
				1.6 + (index % 5) * 0.12,
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut,
				-1,
				true
			),
			{ Rotation = if index % 2 == 0 then -2 else 2 }
		):Play()
	end
end

-- The styled logo: a crimson extruded shadow, then the lettering with a marigold gradient and a
-- bold ink outline. All text of one string, layered; no images.
local function addLogo(parent: Instance)
	local shadow = label(parent, "LogoShadow", "CALENDA", TypeStyle.font("title"))
	place(shadow, "Logo")
	shadow.Position = shadow.Position + UDim2.fromScale(0.012, 0.045)
	shadow.TextColor3 = CRIMSON
	stroke(shadow, CRIMSON, 9).ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	local logo = label(parent, "Logo", "CALENDA", TypeStyle.font("title"))
	place(logo, "Logo")
	logo.TextColor3 = Color3.fromRGB(255, 255, 255) -- the gradient below colours the fill
	local outline = stroke(logo, INK, 6)
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	local fill = Instance.new("UIGradient")
	fill.Rotation = 90
	fill.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 160)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(252, 176, 52)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(240, 104, 40)),
	})
	fill.Parent = logo
end

-- A flourish row (marigold, gold rule, marigold) shown in the loading bar's place once the title
-- is ready, so the left column does not go empty.
local function addFlourish(parent: Instance): Frame
	local row = Instance.new("Frame")
	row.Name = "Flourish"
	place(row, "Loading")
	row.BackgroundTransparency = 1
	row.Visible = false
	row.Parent = parent
	marigold(row, "MarigoldLeft", UDim2.fromScale(0.1, 0.5), UDim2.fromScale(0.2, 0.7))
	marigold(row, "MarigoldRight", UDim2.fromScale(0.9, 0.5), UDim2.fromScale(0.2, 0.7))
	local rule = Instance.new("Frame")
	rule.AnchorPoint = Vector2.new(0.5, 0.5)
	rule.Position = UDim2.fromScale(0.5, 0.5)
	rule.Size = UDim2.new(0.5, 0, 0, 3)
	rule.BackgroundColor3 = GOLD
	rule.BorderSizePixel = 0
	rule.Parent = row
	local gem = Instance.new("Frame")
	gem.AnchorPoint = Vector2.new(0.5, 0.5)
	gem.Position = UDim2.fromScale(0.5, 0.5)
	gem.Size = UDim2.fromOffset(14, 14)
	gem.BackgroundColor3 = CRIMSON
	gem.BorderSizePixel = 0
	gem.Rotation = 45
	gem.Parent = row
	stroke(gem, GOLD, 2)
	return row
end

-- The stand-in shown until the player's character is ready: a puppet cutout swaying in place.
local function addPuppet(parent: Instance): Frame
	local puppet = Instance.new("Frame")
	puppet.Name = "PuppetFallback"
	puppet.AnchorPoint = Vector2.new(0.5, 1)
	puppet.Position = UDim2.fromScale(0.5, 0.92)
	puppet.Size = UDim2.fromScale(0.34, 0.5)
	puppet.BackgroundColor3 = FLAG_COLORS[2]
	puppet.BorderSizePixel = 0
	puppet.Parent = parent
	round(puppet, 14)
	stroke(puppet, Color3.fromRGB(255, 228, 185), 2)
	local head = Instance.new("Frame")
	head.Name = "Head"
	head.AnchorPoint = Vector2.new(0.5, 1)
	head.Position = UDim2.fromScale(0.5, -0.04)
	head.Size = UDim2.fromScale(0.62, 0.42)
	head.BackgroundColor3 = GOLD
	head.BorderSizePixel = 0
	head.Parent = puppet
	round(head, 24)
	TweenService:Create(
		puppet,
		TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Rotation = 6 }
	):Play()
	puppet.Rotation = -6
	return puppet
end

-- The avatar slot: a stage for the player's own avatar. It shows the puppet until the character
-- is ready, then a ViewportFrame with a clone of the character marching in place. Returns a
-- function that stops the per-frame work.
local function addAvatarSlot(parent: Instance): () -> ()
	local slot = Instance.new("Frame")
	slot.Name = "AvatarSlot"
	place(slot, "AvatarSlot")
	slot.BackgroundColor3 = Color3.fromRGB(58, 39, 69)
	slot.BackgroundTransparency = 0.25
	slot.BorderSizePixel = 0
	slot.ClipsDescendants = true
	slot.Parent = parent
	round(slot, 24)
	stroke(slot, GOLD, 3)
	local glow = Instance.new("UIGradient")
	glow.Rotation = 90
	glow.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(96, 45, 97)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(29, 57, 82)),
	})
	glow.Parent = slot
	-- Marigolds at the stage's feet.
	marigold(slot, "MarigoldA", UDim2.fromScale(0.16, 0.93), UDim2.fromScale(0.2, 0.2))
	marigold(slot, "MarigoldB", UDim2.fromScale(0.84, 0.93), UDim2.fromScale(0.2, 0.2))
	local floor = circle(slot, Color3.fromRGB(34, 26, 44))
	floor.Name = "Tarima"
	floor.Position = UDim2.fromScale(0.5, 0.9)
	floor.Size = UDim2.fromScale(0.7, 0.1)

	local puppet = addPuppet(slot)

	local player = Players.LocalPlayer
	local viewport: ViewportFrame? = nil
	local clone: Model? = nil
	local camera: Camera? = nil
	local base = CFrame.identity
	local center = Vector3.zero
	local size = Vector3.new(2, 5, 1)
	local sincePoll = CHARACTER_POLL -- look at once
	local alive = true

	-- Builds the viewport from the local character; false while it is not ready or cloning fails.
	local function attach(): boolean
		local character = player.Character
		if character == nil then
			return false
		end
		local okLoaded, loaded = pcall(function()
			return player:HasAppearanceLoaded()
		end)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not (okLoaded and loaded) or humanoid == nil or hrp == nil then
			return false
		end
		-- The shipped walk Animation of the standard "Animate" script, when present (UNVERIFIED).
		local walk: Animation? = nil
		local animate = character:FindFirstChild("Animate")
		local walkFolder = animate and animate:FindFirstChild("walk")
		if walkFolder then
			walk = walkFolder:FindFirstChildWhichIsA("Animation")
		end
		local wasArchivable = character.Archivable
		character.Archivable = true
		local okClone, copy = pcall(function()
			return character:Clone()
		end)
		character.Archivable = wasArchivable
		if not okClone or copy == nil then
			return false
		end
		local model = copy :: Model
		for _, d in model:GetDescendants() do
			if d:IsA("BaseScript") then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
			end
		end
		local view = Instance.new("ViewportFrame")
		view.Name = "Avatar"
		view.Size = UDim2.fromScale(1, 1)
		view.BackgroundTransparency = 1
		view.Ambient = Color3.fromRGB(190, 180, 170)
		view.LightColor = Color3.fromRGB(255, 244, 225)
		view.LightDirection = Vector3.new(-0.4, -0.6, 0.7)
		view.ZIndex = 2
		view.Parent = slot
		local world = Instance.new("WorldModel")
		world.Parent = view
		model.Parent = world
		local clonedHumanoid = model:FindFirstChildOfClass("Humanoid")
		if clonedHumanoid then
			clonedHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
		-- Face the camera (a Roblox front is -z) in a slight three-quarter view.
		base = CFrame.new(0, 3, 0) * CFrame.Angles(0, math.rad(-20), 0)
		model:PivotTo(base)
		local boxCF, boxSize = model:GetBoundingBox()
		center, size = boxCF.Position, boxSize
		local cam = Instance.new("Camera")
		cam.FieldOfView = AvatarSlot.FOV
		cam.Parent = view
		view.CurrentCamera = cam
		-- Play the shipped walk animation if it can run here; the procedural march below always runs.
		local animator = clonedHumanoid and clonedHumanoid:FindFirstChildOfClass("Animator")
		if walk and animator then
			pcall(function()
				local track = (animator :: Animator):LoadAnimation(walk :: Animation)
				track.Looped = true
				track:Play()
			end)
		end
		viewport, clone, camera = view, model, cam
		puppet.Visible = false
		return true
	end

	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt: number)
		if not alive then
			return
		end
		if clone == nil then
			sincePoll += dt
			if sincePoll >= CHARACTER_POLL then
				sincePoll = 0
				attach()
			end
			return
		end
		local model, cam, view = clone, camera, viewport
		if model == nil or cam == nil or view == nil or model.Parent == nil then
			return
		end
		local m = AvatarSlot.march(os.clock())
		model:PivotTo(base * CFrame.new(0, m.lift, 0) * CFrame.Angles(0, 0, m.roll))
		local px, py = view.AbsoluteSize.X, view.AbsoluteSize.Y
		local aspect = if py > 0 then px / py else 1
		local distance = AvatarSlot.cameraDistance(size.Y, AvatarSlot.FOV, aspect)
		cam.CFrame = CFrame.lookAt(center + Vector3.new(0, size.Y * 0.04, -distance), center)
	end)

	return function()
		alive = false
		connection:Disconnect()
	end
end

function StartupScreen.new(onPlay: () -> ()): Screen
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local old = playerGui:FindFirstChild("CalendaStartup")
	if old then
		old:Destroy()
	end
	local oldControls = playerGui:FindFirstChild("CalendaStartupControls")
	if oldControls then
		oldControls:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "CalendaStartup"
	GuiLayout.fullScreen(gui) -- decorative backdrop only; the Play button lives in `controls`
	gui.ResetOnSpawn = false
	gui.DisplayOrder = ScreenLayout.DISPLAY_ORDER.startup
	gui.Parent = playerGui
	-- Issue #78: the primary button is in the safe area, lower right, under the thumb.
	local controls = Instance.new("ScreenGui")
	controls.Name = "CalendaStartupControls"
	GuiLayout.safe(controls)
	controls.ResetOnSpawn = false
	controls.DisplayOrder = ScreenLayout.DISPLAY_ORDER.startupControls
	controls.Parent = playerGui

	local veil = Instance.new("Frame")
	veil.Name = "Veil"
	veil.Size = UDim2.fromScale(1, 1)
	veil.BackgroundColor3 = Color3.fromRGB(38, 27, 55)
	veil.BorderSizePixel = 0
	veil.Parent = gui
	local backgroundGradient = Instance.new("UIGradient")
	backgroundGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(96, 45, 97)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(51, 43, 77)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(29, 57, 82)),
	})
	backgroundGradient.Rotation = 30
	backgroundGradient.Parent = veil

	addBanner(veil)
	addLogo(veil)

	local subtitle = label(veil, "Subtitle", SUBTITLE, Enum.Font.GothamBold)
	place(subtitle, "Subtitle")
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.TextYAlignment = Enum.TextYAlignment.Top
	subtitle.TextColor3 = CREAM
	stroke(subtitle, INK, 2).ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	local loading = Instance.new("Frame")
	loading.Name = "Loading"
	place(loading, "Loading")
	loading.BackgroundTransparency = 1
	loading.Parent = veil
	local message = label(loading, "Message", "Preparando la calle...", Enum.Font.GothamBold)
	message.Position = UDim2.fromScale(0, 0)
	message.Size = UDim2.fromScale(1, 0.36)
	message.TextXAlignment = Enum.TextXAlignment.Left
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Position = UDim2.fromScale(0, 0.5)
	track.Size = UDim2.fromScale(1, 0.3)
	track.BackgroundColor3 = Color3.fromRGB(39, 29, 48)
	track.BorderSizePixel = 0
	track.Parent = loading
	round(track, 14)
	stroke(track, GOLD, 2).ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(251, 190, 76)
	fill.BorderSizePixel = 0
	fill.Parent = track
	round(fill, 14)
	local fillGradient = Instance.new("UIGradient")
	fillGradient.Color =
		ColorSequence.new(Color3.fromRGB(244, 130, 40), Color3.fromRGB(250, 210, 50))
	fillGradient.Parent = fill
	local percent = label(loading, "Percent", "0%", Enum.Font.GothamBold)
	percent.Position = UDim2.fromScale(0, 0.82)
	percent.Size = UDim2.fromScale(1, 0.2)
	percent.TextXAlignment = Enum.TextXAlignment.Left
	percent.TextColor3 = Color3.fromRGB(255, 228, 185)
	local flourish = addFlourish(veil)

	local stopAvatar = addAvatarSlot(veil)

	local footer = label(veil, "Version", VERSION_LABEL, Enum.Font.GothamBold)
	place(footer, "Version")
	footer.TextXAlignment = Enum.TextXAlignment.Left
	footer.TextColor3 = Color3.fromRGB(222, 204, 197)
	footer.TextTransparency = 0.35

	local play = Instance.new("TextButton")
	play.Name = "Play"
	local primary = ScreenLayout.PRIMARY_BUTTON
	play.AnchorPoint = Vector2.new(primary.ax, primary.ay)
	play.Position = UDim2.fromScale(primary.x, primary.y)
	play.Size = UDim2.fromScale(primary.w, primary.h)
	play.BackgroundColor3 = Color3.fromRGB(221, 82, 75)
	play.BorderSizePixel = 0
	play.AutoButtonColor = false
	play.Selectable = true
	play.Text = "Jugar"
	play.TextColor3 = Color3.fromRGB(255, 250, 232)
	play.TextScaled = true
	play.Font = TypeStyle.font("button")
	play.Visible = false
	play.Parent = controls
	local playLimit = Instance.new("UITextSizeConstraint")
	playLimit.MinTextSize = ScreenLayout.MIN_TEXT
	playLimit.MaxTextSize = 36
	playLimit.Parent = play
	TypeStyle.pill(play)
	TypeStyle.outline(play)
	local playBorder = Instance.new("UIStroke")
	playBorder.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	playBorder.Color = Color3.fromRGB(255, 226, 165)
	playBorder.Thickness = 3
	playBorder.Parent = play
	local playScale = Instance.new("UIScale")
	playScale.Parent = play
	local function press(scale: number)
		TweenService
			:Create(playScale, TweenInfo.new(0.11, Enum.EasingStyle.Quad), { Scale = scale })
			:Play()
	end
	play.MouseButton1Down:Connect(function()
		press(0.96)
	end)
	play.MouseButton1Up:Connect(function()
		press(1)
	end)
	play.Activated:Connect(onPlay)

	local active = true
	local inputConnection: RBXScriptConnection? = nil
	local function teardown()
		active = false
		stopAvatar()
		if inputConnection then
			inputConnection:Disconnect()
			inputConnection = nil
		end
		if GuiService.SelectedObject == play then
			GuiService.SelectedObject = nil
		end
		controls:Destroy()
		gui:Destroy() -- releases the banner sways and puppet tween with the instances
	end

	local screen = {} :: Screen
	function screen.setProgress(_, fraction: number)
		local bounded = math.clamp(fraction, 0, 1)
		fill.Size = UDim2.fromScale(bounded, 1)
		percent.Text = `{math.floor(bounded * 100 + 0.5)}%`
	end
	function screen.setMessage(_, text: string)
		message.Text = text
	end
	function screen.showTitle(_)
		if not active then
			return
		end
		if play.Visible then
			return
		end
		loading.Visible = false
		flourish.Visible = true
		play.Visible = true
		GuiService.SelectedObject = play
	end
	-- Play has been pressed: the title UI gives way to the opening camera move (issue #177), and the
	-- Play button goes with it so it never sits over the countdown or the run.
	function screen.finishIntro(_)
		if active then
			teardown()
		end
	end
	function screen.hide(_)
		if active then
			teardown()
		end
	end

	inputConnection = UserInputService.InputBegan:Connect(
		function(input: InputObject, processed: boolean)
			if
				active
				and play.Visible
				and not processed
				and (input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.Space)
			then
				onPlay()
			end
		end
	)

	return screen
end

return StartupScreen
