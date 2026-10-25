--!strict
-- Screen text (issues #10, #13): the always-visible crowd counter, the steering hint, and the end
-- of run panel with the replay button. What to show is decided by the pure RunView/InputIntent;
-- this module only owns the Roblox GUI objects. IN-ENGINE BEHAVIOUR IS UNVERIFIED.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ScreenLayout = require(Shared:WaitForChild("ScreenLayout"))
local GuiLayout = require(script.Parent:WaitForChild("GuiLayout"))
local TypeStyle = require(script.Parent:WaitForChild("TypeStyle"))
local HitFeedback = require(Shared:WaitForChild("HitFeedback"))
local HpBar = require(Shared:WaitForChild("HpBar"))
local RunView = require(Shared:WaitForChild("RunView"))
local Strings = require(Shared:WaitForChild("Strings"))

local WHITE = Color3.fromRGB(255, 255, 255)
local OUTLINE = Color3.fromRGB(28, 22, 34)

export type Hud = {
	update: (self: Hud, hud: RunView.Hud, hintVisible: boolean) -> (),
	pop: (self: Hud) -> (),
	-- Issue #50: the parade HP bar (nil hides it) and the hit reaction on it and the screen edges.
	setHp: (self: Hud, view: HpBar.View?, clock: number) -> (),
	applyHit: (self: Hud, sample: HitFeedback.Sample) -> (),
	resetHp: (self: Hud) -> (),
}

local Hud = {}

local function label(
	parent: Instance,
	name: string,
	position: UDim2,
	size: UDim2,
	font: Enum.Font
): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Position = position
	l.Size = size
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.BackgroundTransparency = 1
	l.TextColor3 = WHITE
	l.TextStrokeColor3 = OUTLINE
	l.TextStrokeTransparency = 0 -- chunky dark outline
	l.TextScaled = true
	l.Font = font
	l.Parent = parent
	return l
end

-- A text label placed by its ScreenLayout element, with that element's text size limits. Issue
-- #104: every main label gets the dark outline (TypeStyle.outline).
local function placed(parent: Instance, name: string, font: Enum.Font): TextLabel
	local l = label(parent, name, UDim2.new(), UDim2.new(), font)
	GuiLayout.place(l, name)
	GuiLayout.limitText(l, name)
	TypeStyle.outline(l)
	return l
end

function Hud.new(onReplay: () -> (), onMusicMute: (muted: boolean) -> ()): Hud
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	-- Issue #78: landscape only. PlayerGui.ScreenOrientation reorients a running session at once
	-- (Roblox docs, Mobile input); the place default is set in default.project.json.
	pcall(function()
		playerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
	end)
	local gui = Instance.new("ScreenGui")
	gui.Name = "CalendaHud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = ScreenLayout.DISPLAY_ORDER.hud
	GuiLayout.safe(gui)
	gui.Parent = playerGui
	-- Decorative full-screen layer (hit flash, results dim): no text, no buttons.
	local fx = Instance.new("ScreenGui")
	fx.Name = "CalendaHudFx"
	fx.ResetOnSpawn = false
	-- Below CalendaHud (order 0) so the results dim sits UNDER the Title/Score/Best/Replay texts; ties
	-- are unspecified in the docs. Table and test: ScreenLayout.DISPLAY_ORDER.
	fx.DisplayOrder = ScreenLayout.DISPLAY_ORDER.hudFx
	GuiLayout.fullScreen(fx)
	fx.Parent = playerGui

	-- Crowd counter, top center. The big number is the exact total; the line under it is the
	-- exact loose count and section count. Rects come from ScreenLayout (tested at every aspect).
	placed(gui, "Caption", TypeStyle.font("body")).Text = Strings.followers
	local counter = placed(gui, "Counter", TypeStyle.font("number"))
	local scale = Instance.new("UIScale")
	scale.Parent = counter
	local detail = placed(gui, "Detail", TypeStyle.font("body"))
	local musicMuted = false
	local musicToggle = Instance.new("TextButton")
	musicToggle.Name = "MusicToggle"
	GuiLayout.place(musicToggle, "MusicToggle") -- top right corner, a >= 44 px target
	musicToggle.BackgroundColor3 = Color3.fromRGB(48, 29, 55)
	musicToggle.BackgroundTransparency = 0.15
	musicToggle.TextColor3 = WHITE
	musicToggle.TextStrokeColor3 = OUTLINE
	musicToggle.TextStrokeTransparency = 0
	musicToggle.TextScaled = true
	musicToggle.Font = TypeStyle.font("body")
	musicToggle.Text = Strings.musicOn
	musicToggle.Parent = gui
	GuiLayout.limitText(musicToggle, "MusicToggle")
	musicToggle.Activated:Connect(function()
		musicMuted = not musicMuted
		musicToggle.Text = if musicMuted then Strings.musicOff else Strings.musicOn
		onMusicMute(musicMuted)
	end)

	local hint = placed(gui, "Hint", TypeStyle.font("body"))
	hint.Text = Strings.hint
	TypeStyle.backing(hint) -- issue #104: a panel behind the floating hint

	-- Parade HP bar (issue #50), top left next to the counter: icon, meter and number, so it
	-- reads with the sound off. Hidden until HP is replicated.
	local hpRoot = Instance.new("Frame")
	hpRoot.Name = "HpBar"
	hpRoot.BackgroundTransparency = 1
	GuiLayout.place(hpRoot, "HpBar")
	hpRoot.Visible = false
	hpRoot.Parent = gui
	local hpScale = Instance.new("UIScale")
	hpScale.Parent = hpRoot
	local hpIcon = label(
		hpRoot,
		"Icon",
		UDim2.fromScale(0.09, 0),
		UDim2.fromScale(0.18, 1),
		Enum.Font.GothamBlack
	)
	hpIcon.Text = Strings.hpIcon
	hpIcon.TextColor3 = Color3.fromRGB(235, 60, 60)
	local hpBack = Instance.new("Frame")
	hpBack.Name = "Back"
	hpBack.Position = UDim2.fromScale(0.2, 0.15)
	hpBack.Size = UDim2.fromScale(0.8, 0.7)
	hpBack.BackgroundColor3 = Color3.fromRGB(30, 20, 30)
	hpBack.BackgroundTransparency = 0.2
	hpBack.BorderSizePixel = 0
	hpBack.Parent = hpRoot
	local hpStroke = Instance.new("UIStroke")
	hpStroke.Thickness = 2
	hpStroke.Color = OUTLINE
	hpStroke.Parent = hpBack
	local hpFill = Instance.new("Frame")
	hpFill.Name = "Fill"
	hpFill.Size = UDim2.fromScale(1, 1)
	hpFill.BorderSizePixel = 0
	hpFill.Parent = hpBack
	local hpNumber = Instance.new("TextLabel")
	hpNumber.Name = "Number"
	hpNumber.Size = UDim2.fromScale(1, 1)
	hpNumber.BackgroundTransparency = 1
	hpNumber.TextScaled = true
	hpNumber.Font = Enum.Font.GothamBlack
	hpNumber.TextColor3 = WHITE
	hpNumber.TextStrokeColor3 = OUTLINE
	hpNumber.TextStrokeTransparency = 0
	hpNumber.ZIndex = 2
	local hpLimit = Instance.new("UITextSizeConstraint")
	hpLimit.MinTextSize = 14 -- readable on a phone (ScreenLayout.MIN_TEXT)
	hpLimit.MaxTextSize = 26
	hpLimit.Parent = hpNumber
	hpNumber.Parent = hpBack

	-- Hit flash: a vignette of four edge gradients plus a faint full-screen wash, white then red.
	local flashParts: { Frame } = {}
	local function flashEdge(position: UDim2, size: UDim2, rotation: number)
		local f = Instance.new("Frame")
		f.Name = "HitEdge"
		f.Position = position
		f.Size = size
		f.BorderSizePixel = 0
		f.BackgroundTransparency = 1
		f.Visible = false
		local g = Instance.new("UIGradient")
		g.Rotation = rotation
		g.Transparency = NumberSequence.new(0, 1)
		g.Parent = f
		f.Parent = fx
		table.insert(flashParts, f)
	end
	flashEdge(UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.25), 90) -- top, opaque at the edge
	flashEdge(UDim2.fromScale(0, 0.75), UDim2.fromScale(1, 0.25), 270)
	flashEdge(UDim2.fromScale(0, 0), UDim2.fromScale(0.15, 1), 0)
	flashEdge(UDim2.fromScale(0.85, 0), UDim2.fromScale(0.15, 1), 180)
	local wash = Instance.new("Frame")
	wash.Name = "HitWash"
	wash.Size = UDim2.fromScale(1, 1)
	wash.BorderSizePixel = 0
	wash.BackgroundTransparency = 1
	wash.Visible = false
	wash.Parent = fx

	-- End of run panel. Shown purely from State (over/outcome); hidden again on replay. The dim
	-- is full screen (fx gui); the texts and the replay button sit in the safe area.
	local dim = Instance.new("Frame")
	dim.Name = "EndDim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(30, 20, 30)
	dim.BackgroundTransparency = 0.45
	dim.BorderSizePixel = 0
	dim.Visible = false
	dim.Parent = fx
	local panel = Instance.new("Frame")
	panel.Name = "EndPanel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundTransparency = 1
	panel.Visible = false
	panel.Parent = gui
	local title = placed(panel, "Title", TypeStyle.font("title"))
	TypeStyle.gradient(title)
	local score = placed(panel, "Score", TypeStyle.font("number"))
	local best = placed(panel, "Best", TypeStyle.font("body"))
	-- Primary button: the lower right corner, under the right thumb (ScreenLayout.PRIMARY_BUTTON).
	local replay = Instance.new("TextButton")
	replay.Name = "Replay"
	GuiLayout.place(replay, "Replay")
	replay.BackgroundColor3 = Color3.fromRGB(240, 120, 20)
	replay.TextColor3 = WHITE
	replay.TextStrokeColor3 = OUTLINE
	replay.TextStrokeTransparency = 0
	replay.TextScaled = true
	replay.Font = TypeStyle.font("button")
	replay.Text = Strings.replay
	replay.Parent = panel
	TypeStyle.pill(replay)
	TypeStyle.outline(replay)
	TypeStyle.border(replay) -- issue #104: keep a separate pill-frame outline around the text outline
	GuiLayout.limitText(replay, "Replay")
	replay.Activated:Connect(onReplay)

	-- Assign text only when it changes: State arrives about 10 times a second.
	local last = { counter = "", detail = "", title = "", score = "", best = "" }

	local hud = {} :: Hud

	function hud.update(_, view: RunView.Hud, hintVisible: boolean)
		if view.counter ~= last.counter then
			last.counter = view.counter
			counter.Text = view.counter
		end
		if view.detail ~= last.detail then
			last.detail = view.detail
			detail.Text = view.detail
		end
		hint.Visible = hintVisible
		panel.Visible = view.showEnd
		dim.Visible = view.showEnd
		if view.showEnd then
			if view.endTitle ~= last.title then
				last.title = view.endTitle
				title.Text = view.endTitle
			end
			if view.score ~= last.score then
				last.score = view.score
				score.Text = view.score
			end
			if view.best ~= last.best then
				last.best = view.best
				best.Text = view.best
			end
		end
	end

	local hpShown = false
	local lastHpLabel = ""
	function hud.setHp(_, view: HpBar.View?, clock: number)
		if view == nil then
			if hpShown then
				hpShown = false
				hpRoot.Visible = false
			end
			return
		end
		hpShown = true
		hpRoot.Visible = true
		hpFill.Size = UDim2.fromScale(view.fraction, 1)
		local c = view.color
		local fillColor = Color3.fromRGB(c[1], c[2], c[3])
		if view.low then
			-- Warning pulse: the fill and outline flash toward red-white, the icon beats.
			local p = HpBar.pulse(clock)
			fillColor = fillColor:Lerp(Color3.fromRGB(255, 255, 255), p * 0.5)
			hpStroke.Color = OUTLINE:Lerp(Color3.fromRGB(235, 60, 60), p)
			hpStroke.Thickness = 2 + 2 * p
			hpIcon.TextTransparency = 0.5 * (1 - p)
		else
			hpStroke.Color = OUTLINE
			hpStroke.Thickness = 2
			hpIcon.TextTransparency = 0
		end
		hpFill.BackgroundColor3 = fillColor
		if view.label ~= lastHpLabel then
			lastHpLabel = view.label
			hpNumber.Text = view.label
		end
	end

	function hud.applyHit(_, s: HitFeedback.Sample)
		hpScale.Scale = 1 + s.jolt
		hpRoot.Rotation = s.shakeX * 4 -- a wobble, from the same envelope as the screen shake
		local on = s.flash > 0.005
		local color = Color3.fromRGB(255, 255, 255):Lerp(Color3.fromRGB(235, 40, 50), s.redMix)
		for _, f in flashParts do
			f.Visible = on
			f.BackgroundColor3 = color
			f.BackgroundTransparency = 1 - s.flash
		end
		wash.Visible = on
		wash.BackgroundColor3 = color
		wash.BackgroundTransparency = 1 - s.flash * 0.25
	end

	-- Replay: no bar, no flash, no wobble left over from the last run.
	function hud.resetHp(_)
		hpShown, lastHpLabel = false, ""
		hpRoot.Visible = false
		hud.applyHit(hud, HitFeedback.new():sample())
	end

	-- The counter jumps big and settles: feedback when a gate or obstacle changes the total.
	function hud.pop(_)
		scale.Scale = 1.5
		TweenService:Create(
			scale,
			TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
	end

	return hud
end

return Hud
