--!strict
-- Issue #104: applies the UiType tokens to screen text and buttons. Presentation only.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UiType = require(Shared:WaitForChild("UiType"))

local TypeStyle = {}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Enum.Font member for a role in UiType.FONT.
function TypeStyle.font(role: string): Enum.Font
	return Enum.Font[UiType.FONT[role]]
end

-- Dark outline on a text label or button.
function TypeStyle.outline(gui: GuiObject)
	local s = Instance.new("UIStroke")
	-- Contextual follows the glyph shape on a text label; Border would draw a box around its rect.
	local isText = gui:IsA("TextLabel") or gui:IsA("TextButton")
	s.ApplyStrokeMode = if isText
		then Enum.ApplyStrokeMode.Contextual
		else Enum.ApplyStrokeMode.Border
	if gui:IsA("TextLabel") then
		gui.TextStrokeTransparency = 1 -- avoid drawing a second glyph outline
	elseif gui:IsA("TextButton") then
		gui.TextStrokeTransparency = 1
	end
	s.Thickness = UiType.STROKE_THICKNESS
	s.Color = rgb(UiType.STROKE_RGB)
	s.Parent = gui
end

-- Vertical yellow-to-orange gradient for a title.
function TypeStyle.gradient(gui: GuiObject)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(rgb(UiType.TITLE_TOP_RGB), rgb(UiType.TITLE_BOTTOM_RGB))
	g.Parent = gui
end

-- Semi-transparent rounded panel behind floating text, so it reads over a busy 3D scene.
function TypeStyle.backing(gui: GuiObject)
	gui.BackgroundColor3 = rgb(UiType.BACKING_RGB)
	gui.BackgroundTransparency = UiType.BACKING_TRANSPARENCY
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, UiType.BACKING_CORNER_PX)
	c.Parent = gui
end

-- Pill-shaped corners for a primary button.
function TypeStyle.pill(gui: GuiObject)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(UiType.PILL_SCALE, 0)
	c.Parent = gui
end

return TypeStyle
