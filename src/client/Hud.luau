--!strict
-- Results text and replay button. Active gameplay has no screen text (issue #160).
-- What to show is decided by the pure RunView;
-- this module only owns the Roblox GUI objects. IN-ENGINE BEHAVIOUR IS UNVERIFIED.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ScreenLayout = require(Shared:WaitForChild("ScreenLayout"))
local GuiLayout = require(script.Parent:WaitForChild("GuiLayout"))
local TypeStyle = require(script.Parent:WaitForChild("TypeStyle"))
local HitFeedback = require(Shared:WaitForChild("HitFeedback"))
local RunView = require(Shared:WaitForChild("RunView"))
local Strings = require(Shared:WaitForChild("Strings"))

local WHITE = Color3.fromRGB(255, 255, 255)
local OUTLINE = Color3.fromRGB(28, 22, 34)

export type Hud = {
	update: (self: Hud, hud: RunView.Hud) -> (),
	-- The hit reaction at the screen edges; camera shake remains in Main.
	applyHit: (self: Hud, sample: HitFeedback.Sample) -> (),
	resetHit: (self: Hud) -> (),
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

function Hud.new(onReplay: () -> ()): Hud
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
	-- Decorative full-screen layer (results dim): no text, no buttons.
	local fx = Instance.new("ScreenGui")
	fx.Name = "CalendaHudFx"
	fx.ResetOnSpawn = false
	-- Below CalendaHud (order 0) so the results dim sits UNDER the Title/Score/Best/Replay texts; ties
	-- are unspecified in the docs. Table and test: ScreenLayout.DISPLAY_ORDER.
	fx.DisplayOrder = ScreenLayout.DISPLAY_ORDER.hudFx
	GuiLayout.fullScreen(fx)
	fx.Parent = playerGui

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
	local last = { title = "", score = "", best = "" }

	local hud = {} :: Hud

	function hud.update(_, view: RunView.Hud)
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

	-- Hit feedback no longer creates a screen flash. Camera shake remains in Main.
	function hud.applyHit(_, _: HitFeedback.Sample) end

	function hud.resetHit(_) end

	return hud
end

return Hud
