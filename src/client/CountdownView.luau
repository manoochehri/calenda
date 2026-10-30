--!strict
-- Issue #203: draws the "tres, dos, uno" numeral from the pure sequence (shared/Countdown,
-- shared/StartSequence). One centred label over the street; each frame only its scale and
-- transparency are set from Countdown.visual (eased over >= 0.25 s), so nothing flashes or pulses
-- the screen (#85, #171). Presentation only. The on-device look is UNVERIFIED.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GuiLayout = require(script.Parent:WaitForChild("GuiLayout"))
local TypeStyle = require(script.Parent:WaitForChild("TypeStyle"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ScreenLayout = require(Shared:WaitForChild("ScreenLayout"))
local TitleLayout = require(Shared:WaitForChild("TitleLayout"))
local Countdown = require(Shared:WaitForChild("Countdown"))

export type View = {
	-- Shows `word` at the given look, or hides the numeral when word is nil.
	show: (self: View, word: string?, look: Countdown.Look?) -> (),
	destroy: (self: View) -> (),
}

local CountdownView = {}

function CountdownView.new(): View
	local gui = Instance.new("ScreenGui")
	gui.Name = "CalendaCountdown"
	GuiLayout.fullScreen(gui) -- decorative and non-interactive
	gui.ResetOnSpawn = false
	gui.DisplayOrder = ScreenLayout.DISPLAY_ORDER.startupControls + 1
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local e = TitleLayout.COUNTDOWN
	local text = Instance.new("TextLabel")
	text.Name = "Numeral"
	text.AnchorPoint = Vector2.new(e.ax, e.ay)
	text.Position = UDim2.fromScale(e.x, e.y)
	text.Size = UDim2.fromScale(e.w, e.h)
	text.BackgroundTransparency = 1
	text.Font = TypeStyle.font("title")
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(255, 222, 164)
	text.Visible = false
	text.Parent = gui
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = (e.text :: ScreenLayout.TextSpec).minSize
	limit.MaxTextSize = (e.text :: ScreenLayout.TextSpec).maxSize
	limit.Parent = text
	TypeStyle.gradient(text)
	local outline = Instance.new("UIStroke")
	outline.Thickness = 6
	outline.Color = Color3.fromRGB(48, 29, 55)
	outline.Parent = text
	local scale = Instance.new("UIScale")
	scale.Parent = text

	local view = {} :: View
	function view.show(_, word: string?, look: Countdown.Look?)
		if word == nil or look == nil then
			text.Visible = false
			return
		end
		text.Text = word
		text.Visible = true
		scale.Scale = look.scale
		text.TextTransparency = 1 - look.opacity
		outline.Transparency = 1 - look.opacity
	end
	function view.destroy(_)
		gui:Destroy()
	end
	return view
end

return CountdownView
