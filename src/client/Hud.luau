--!strict
-- Screen text (issues #10, #13): the always-visible crowd counter, the steering hint, and the end
-- of run panel with the replay button. What to show is decided by the pure RunView/InputIntent;
-- this module only owns the Roblox GUI objects. IN-ENGINE BEHAVIOUR IS UNVERIFIED.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RunView = require(Shared:WaitForChild("RunView"))
local Strings = require(Shared:WaitForChild("Strings"))

local WHITE = Color3.fromRGB(255, 255, 255)
local OUTLINE = Color3.fromRGB(28, 22, 34)

export type Hud = {
	update: (self: Hud, hud: RunView.Hud, hintVisible: boolean) -> (),
	pop: (self: Hud) -> (),
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
	gui.IgnoreGuiInset = true
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Crowd counter, top center. The big number is the exact total; the line under it is the
	-- exact loose count and section count.
	label(
		gui,
		"Caption",
		UDim2.fromScale(0.5, 0.02),
		UDim2.fromScale(0.4, 0.04),
		Enum.Font.GothamBold
	).Text =
		Strings.followers
	local counter = label(
		gui,
		"Counter",
		UDim2.fromScale(0.5, 0.06),
		UDim2.fromScale(0.5, 0.11),
		Enum.Font.GothamBlack
	)
	local scale = Instance.new("UIScale")
	scale.Parent = counter
	local detail = label(
		gui,
		"Detail",
		UDim2.fromScale(0.5, 0.17),
		UDim2.fromScale(0.4, 0.04),
		Enum.Font.GothamBold
	)

	local hint = label(
		gui,
		"Hint",
		UDim2.fromScale(0.5, 0.86),
		UDim2.fromScale(0.7, 0.07),
		Enum.Font.GothamBlack
	)
	hint.Text = Strings.hint

	-- End of run panel. Shown purely from State (over/outcome); hidden again on replay.
	local panel = Instance.new("Frame")
	panel.Name = "EndPanel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = Color3.fromRGB(30, 20, 30)
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
	replay.BackgroundColor3 = Color3.fromRGB(240, 120, 20)
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
