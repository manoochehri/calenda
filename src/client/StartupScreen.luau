--!strict
-- Original, primitive-only title/loading screen for issue #72. Engine presentation is
-- UNVERIFIED until the Studio checklist is completed; no image assets or IDs are required.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

export type Screen = {
	setProgress: (self: Screen, fraction: number) -> (),
	setMessage: (self: Screen, message: string) -> (),
	showTitle: (self: Screen) -> (),
	showCountIn: (self: Screen, cue: string) -> (),
	finishCountIn: (self: Screen) -> (),
	hide: (self: Screen) -> (),
}

local StartupScreen = {}

local INK = Color3.fromRGB(48, 29, 55)
local CREAM = Color3.fromRGB(255, 244, 219)
local VERSION_LABEL = "PROTOTIPO"
local FLAG_COLORS = {
	Color3.fromRGB(232, 84, 150),
	Color3.fromRGB(244, 130, 40),
	Color3.fromRGB(250, 210, 50),
	Color3.fromRGB(60, 180, 110),
	Color3.fromRGB(60, 140, 230),
	Color3.fromRGB(150, 90, 200),
}

local function round(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
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

local function addFlagString(parent: Instance)
	local cord = Instance.new("Frame")
	cord.Name = "PapelPicadoCord"
	cord.AnchorPoint = Vector2.new(0.5, 0.5)
	cord.Position = UDim2.fromScale(0.5, 0.06)
	cord.Size = UDim2.fromScale(0.78, 0.007)
	cord.BackgroundColor3 = Color3.fromRGB(255, 222, 164)
	cord.BorderSizePixel = 0
	cord.Rotation = 1
	cord.Parent = parent
	for index = 1, 9 do
		local flag = Instance.new("Frame")
		flag.Name = `Flag{index}`
		flag.AnchorPoint = Vector2.new(0.5, 0)
		flag.Position = UDim2.fromScale((index - 0.5) / 9, 0.06)
		flag.Size = UDim2.fromOffset(25, 33)
		flag.BackgroundColor3 = FLAG_COLORS[(index - 1) % #FLAG_COLORS + 1]
		flag.BorderSizePixel = 0
		flag.Rotation = if index % 2 == 0 then 3 else -3
		flag.Parent = parent
		round(flag, 4)
		local cutout = Instance.new("Frame")
		cutout.AnchorPoint = Vector2.new(0.5, 1)
		cutout.Position = UDim2.fromScale(0.5, 1)
		cutout.Size = UDim2.fromScale(0.34, 0.24)
		cutout.BackgroundColor3 = Color3.fromRGB(54, 35, 68)
		cutout.BorderSizePixel = 0
		cutout.Parent = flag
	end
end

local function addParade(parent: Instance)
	local lane = Instance.new("Frame")
	lane.Name = "ParadeSilhouettes"
	lane.AnchorPoint = Vector2.new(0.5, 1)
	lane.Position = UDim2.fromScale(0.5, 1)
	lane.Size = UDim2.fromScale(0.8, 0.18)
	lane.BackgroundTransparency = 1
	lane.ClipsDescendants = true
	lane.Parent = parent

	local street = Instance.new("Frame")
	street.AnchorPoint = Vector2.new(0.5, 1)
	street.Position = UDim2.fromScale(0.5, 1)
	street.Size = UDim2.fromScale(1, 0.12)
	street.BackgroundColor3 = Color3.fromRGB(82, 69, 80)
	street.BorderSizePixel = 0
	street.Parent = lane
	round(street, 8)

	for index = 1, 5 do
		local x = 0.12 + (index - 1) * 0.19
		local figure = Instance.new("Frame")
		figure.Name = `Puppet{index}`
		figure.AnchorPoint = Vector2.new(0.5, 1)
		figure.Position = UDim2.fromScale(x, 0.89)
		figure.Size = UDim2.fromScale(0.08, 0.62 + (index % 2) * 0.08)
		figure.BackgroundColor3 = FLAG_COLORS[(index - 1) % #FLAG_COLORS + 1]
		figure.BorderSizePixel = 0
		figure.Parent = lane
		round(figure, 14)
		stroke(figure, Color3.fromRGB(255, 228, 185), 2)

		local head = Instance.new("Frame")
		head.Name = "Head"
		head.AnchorPoint = Vector2.new(0.5, 0)
		head.Position = UDim2.fromScale(0.5, -0.25)
		head.Size = UDim2.fromScale(0.64, 0.35)
		head.BackgroundColor3 = Color3.fromRGB(255, 222, 164)
		head.BorderSizePixel = 0
		head.Parent = figure
		round(head, 20)

		local sway = TweenService:Create(
			figure,
			TweenInfo.new(
				1.4 + index * 0.11,
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut,
				-1,
				true
			),
			{ Rotation = if index % 2 == 0 then 7 else -7 }
		)
		sway:Play()
	end

	local balloon = Instance.new("Frame")
	balloon.Name = "Globo"
	balloon.AnchorPoint = Vector2.new(0.5, 1)
	balloon.Position = UDim2.fromScale(0.87, 0.66)
	balloon.Size = UDim2.fromScale(0.1, 0.3)
	balloon.BackgroundColor3 = Color3.fromRGB(242, 145, 66)
	balloon.BorderSizePixel = 0
	balloon.Parent = lane
	local balloonCorner = Instance.new("UICorner")
	balloonCorner.CornerRadius = UDim.new(1, 0)
	balloonCorner.Parent = balloon
	stroke(balloon, Color3.fromRGB(255, 238, 198), 2)
	local pole = Instance.new("Frame")
	pole.AnchorPoint = Vector2.new(0.5, 0)
	pole.Position = UDim2.fromScale(0.5, 1)
	pole.Size = UDim2.fromOffset(3, 23)
	pole.BackgroundColor3 = Color3.fromRGB(255, 222, 164)
	pole.BorderSizePixel = 0
	pole.Parent = balloon
end

function StartupScreen.new(onPlay: () -> ()): Screen
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local old = playerGui:FindFirstChild("CalendaStartup")
	if old then
		old:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "CalendaStartup"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100
	gui.Parent = playerGui

	local veil = Instance.new("Frame")
	veil.Name = "Veil"
	veil.Size = UDim2.fromScale(1, 1)
	veil.BackgroundColor3 = Color3.fromRGB(38, 27, 55)
	veil.BackgroundTransparency = 0.12
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

	local countIn = label(veil, "CountIn", "", Enum.Font.FredokaOne)
	countIn.AnchorPoint = Vector2.new(0.5, 0.5)
	countIn.Position = UDim2.fromScale(0.5, 0.44)
	countIn.Size = UDim2.fromScale(0.84, 0.22)
	countIn.TextColor3 = Color3.fromRGB(255, 222, 164)
	countIn.TextStrokeColor3 = INK
	countIn.TextStrokeTransparency = 0
	countIn.TextSize = 86
	countIn.Visible = false

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.48)
	card.Size = UDim2.fromScale(0.84, 0.74)
	card.BackgroundColor3 = Color3.fromRGB(58, 39, 69)
	card.BackgroundTransparency = 0.06
	card.BorderSizePixel = 0
	card.Parent = veil
	round(card, 30)
	stroke(card, Color3.fromRGB(255, 223, 166), 3)
	local bounds = Instance.new("UISizeConstraint")
	bounds.MinSize = Vector2.new(300, 360)
	bounds.MaxSize = Vector2.new(600, 610)
	bounds.Parent = card

	addFlagString(card)

	local logo = label(card, "Logo", "CALENDA", Enum.Font.FredokaOne)
	logo.AnchorPoint = Vector2.new(0.5, 0)
	logo.Position = UDim2.fromScale(0.5, 0.17)
	logo.Size = UDim2.fromScale(0.9, 0.19)
	logo.TextColor3 = Color3.fromRGB(255, 222, 164)
	logo.TextStrokeColor3 = INK
	logo.TextStrokeTransparency = 0
	logo.TextSize = 72
	stroke(logo, Color3.fromRGB(255, 242, 210), 1.4)
	local logoGradient = Instance.new("UIGradient")
	logoGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 227, 147)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 181, 111)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 223, 146)),
	})
	logoGradient.Parent = logo
	local logoScale = Instance.new("UIScale")
	logoScale.Scale = 1
	logoScale.Parent = logo
	TweenService:Create(
		logoScale,
		TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Scale = 1.035 }
	):Play()

	local subtitle =
		label(card, "Subtitle", "Música, fiesta y una gran calenda", Enum.Font.GothamBold)
	subtitle.AnchorPoint = Vector2.new(0.5, 0)
	subtitle.Position = UDim2.fromScale(0.5, 0.37)
	subtitle.Size = UDim2.fromScale(0.86, 0.08)
	subtitle.TextColor3 = Color3.fromRGB(255, 242, 210)

	local loading = Instance.new("Frame")
	loading.Name = "Loading"
	loading.AnchorPoint = Vector2.new(0.5, 0)
	loading.Position = UDim2.fromScale(0.5, 0.53)
	loading.Size = UDim2.fromScale(0.72, 0.17)
	loading.BackgroundTransparency = 1
	loading.Parent = card
	local message = label(loading, "Message", "Preparando la calle...", Enum.Font.GothamBold)
	message.Position = UDim2.fromScale(0, 0)
	message.Size = UDim2.fromScale(1, 0.36)
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Position = UDim2.fromScale(0, 0.5)
	track.Size = UDim2.fromScale(1, 0.3)
	track.BackgroundColor3 = Color3.fromRGB(39, 29, 48)
	track.BorderSizePixel = 0
	track.Parent = loading
	round(track, 14)
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
	percent.TextColor3 = Color3.fromRGB(255, 228, 185)

	local play = Instance.new("TextButton")
	play.Name = "Play"
	play.AnchorPoint = Vector2.new(0.5, 0)
	play.Position = UDim2.fromScale(0.5, 0.54)
	play.Size = UDim2.fromScale(0.58, 0.16)
	play.BackgroundColor3 = Color3.fromRGB(221, 82, 75)
	play.BorderSizePixel = 0
	play.AutoButtonColor = false
	play.Selectable = true
	play.Text = "Jugar"
	play.TextColor3 = Color3.fromRGB(255, 250, 232)
	play.TextScaled = true
	play.Font = Enum.Font.FredokaOne
	play.Visible = false
	play.Parent = card
	round(play, 24)
	stroke(play, Color3.fromRGB(255, 226, 165), 3)
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

	local footer = label(card, "Version", VERSION_LABEL, Enum.Font.GothamBold)
	footer.AnchorPoint = Vector2.new(0.5, 1)
	footer.Position = UDim2.fromScale(0.5, 0.91)
	footer.Size = UDim2.fromScale(0.36, 0.045)
	footer.TextColor3 = Color3.fromRGB(222, 204, 197)
	footer.TextTransparency = 0.1
	footer.TextSize = 12

	addParade(veil)

	local active = true
	local inputConnection: RBXScriptConnection? = nil
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
		play.Visible = true
		GuiService.SelectedObject = play
	end
	function screen.showCountIn(_, cue: string)
		if not active then
			return
		end
		loading.Visible = false
		play.Visible = false
		card.Visible = false
		veil.BackgroundTransparency = 0.45
		countIn.Text = cue
		countIn.Visible = true
	end
	function screen.finishCountIn(_)
		if active then
			active = false
			if inputConnection then
				inputConnection:Disconnect()
				inputConnection = nil
			end
			gui:Destroy()
		end
	end
	function screen.hide(_)
		active = false
		if inputConnection then
			inputConnection:Disconnect()
			inputConnection = nil
		end
		if GuiService.SelectedObject == play then
			GuiService.SelectedObject = nil
		end
		gui:Destroy() -- releases the looping logo and parade tweens once Play begins
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
