--!strict
-- Screen text (issues #10, #13): the always-visible crowd counter, the steering hint, and the end
-- of run panel with the replay button. What to show is decided by the pure RunView/InputIntent;
-- this module only owns the Roblox GUI objects. IN-ENGINE BEHAVIOUR IS UNVERIFIED.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HitFeedback = require(Shared:WaitForChild("HitFeedback"))
local HpBar = require(Shared:WaitForChild("HpBar"))
local HudLayout = require(Shared:WaitForChild("HudLayout"))
local RunView = require(Shared:WaitForChild("RunView"))
local StreetTheme = require(Shared:WaitForChild("StreetTheme"))
local Strings = require(Shared:WaitForChild("Strings"))

local function themeColor(rgb: StreetTheme.RGB): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local WHITE = themeColor(StreetTheme.palette.cream)
local OUTLINE = themeColor(StreetTheme.palette.ink)

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

function Hud.new(onReplay: () -> ()): Hud
	local gui = Instance.new("ScreenGui")
	gui.Name = "CalendaHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Crowd counter, top center. The big number is the exact total; the line under it is the
	-- exact loose count and section count.
	label(
		gui,
		"Caption",
		UDim2.fromScale(HudLayout.caption.centerX, HudLayout.caption.top),
		UDim2.fromScale(HudLayout.caption.width, HudLayout.caption.height),
		Enum.Font.GothamBold
	).Text =
		Strings.followers
	local counter = label(
		gui,
		"Counter",
		UDim2.fromScale(HudLayout.counter.centerX, HudLayout.counter.top),
		UDim2.fromScale(HudLayout.counter.width, HudLayout.counter.height),
		Enum.Font.GothamBlack
	)
	local scale = Instance.new("UIScale")
	scale.Parent = counter
	local detail = label(
		gui,
		"Detail",
		UDim2.fromScale(HudLayout.detail.centerX, HudLayout.detail.top),
		UDim2.fromScale(HudLayout.detail.width, HudLayout.detail.height),
		Enum.Font.GothamBold
	)

	local hint = label(
		gui,
		"Hint",
		UDim2.fromScale(HudLayout.hint.centerX, HudLayout.hint.top),
		UDim2.fromScale(HudLayout.hint.width, HudLayout.hint.height),
		Enum.Font.GothamBlack
	)
	hint.Text = Strings.hint

	-- Parade HP bar (issue #50), top left next to the counter: icon, meter and number, so it
	-- reads with the sound off. Hidden until HP is replicated.
	local hpRoot = Instance.new("Frame")
	hpRoot.Name = "HpBar"
	hpRoot.BackgroundTransparency = 1
	hpRoot.AnchorPoint = Vector2.new(0.5, 0)
	hpRoot.Position = UDim2.fromScale(HudLayout.hp.centerX, HudLayout.hp.top)
	hpRoot.Size = UDim2.fromScale(HudLayout.hp.width, HudLayout.hp.height)
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
	hpIcon.TextColor3 = themeColor(StreetTheme.palette.cone)
	local hpBack = Instance.new("Frame")
	hpBack.Name = "Back"
	hpBack.Position = UDim2.fromScale(0.2, 0.15)
	hpBack.Size = UDim2.fromScale(0.8, 0.7)
	hpBack.BackgroundColor3 = OUTLINE
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
	hpLimit.MinTextSize = 12 -- readable on a phone
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
		f.Parent = gui
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
	wash.Parent = gui

	-- End of run panel. Shown purely from State (over/outcome); hidden again on replay.
	local panel = Instance.new("Frame")
	panel.Name = "EndPanel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = OUTLINE
	panel.BackgroundTransparency = 0.45
	panel.Visible = false
	panel.Parent = gui
	local title = label(
		panel,
		"Title",
		UDim2.fromScale(0.5, 0.25),
		UDim2.fromScale(0.8, 0.12),
		Enum.Font.GothamBlack
	)
	local score = label(
		panel,
		"Score",
		UDim2.fromScale(0.5, 0.4),
		UDim2.fromScale(0.5, 0.08),
		Enum.Font.GothamBlack
	)
	local best = label(
		panel,
		"Best",
		UDim2.fromScale(0.5, 0.5),
		UDim2.fromScale(0.4, 0.05),
		Enum.Font.GothamBold
	)
	local replay = Instance.new("TextButton")
	replay.Name = "Replay"
	replay.AnchorPoint = Vector2.new(0.5, 0)
	replay.Position = UDim2.fromScale(0.5, 0.62)
	replay.Size = UDim2.fromScale(0.5, 0.1)
	replay.BackgroundColor3 = themeColor(StreetTheme.palette.marigold)
	replay.TextColor3 = WHITE
	replay.TextStrokeColor3 = OUTLINE
	replay.TextStrokeTransparency = 0
	replay.TextScaled = true
	replay.Font = Enum.Font.GothamBlack
	replay.Text = Strings.replay
	replay.Parent = panel
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
