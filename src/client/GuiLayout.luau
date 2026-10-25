--!strict
-- Issue #78: the one ScreenGui inset convention and the helpers that apply ScreenLayout's data.
-- Every HUD ScreenGui (text, meters, buttons) is `safe`: its 0..1 space is the safe area (clear of
-- notches, rounded corners and the Roblox top bar), IgnoreGuiInset = false. Purely decorative
-- full-screen layers (hit flash, dim, title backdrop) are `fullScreen`. Mixing the two for
-- positions that must line up is the bug this fixes (PlusSections vs the section meter).
-- Source checked: Roblox docs list ScreenGui.ScreenInsets (Enum.ScreenInsets: None,
-- DeviceSafeInsets, CoreUISafeInsets, TopbarSafeInsets) and say CoreUISafeInsets keeps
-- descendants clear of top bar buttons and screen cutouts and is recommended for interactive
-- ScreenGuis. The docs give no semantics for IgnoreGuiInset/the other items. IN-ENGINE UNVERIFIED.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ScreenLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ScreenLayout"))

local GuiLayout = {}

function GuiLayout.safe(gui: ScreenGui)
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
end

function GuiLayout.fullScreen(gui: ScreenGui)
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
end

-- Anchor, position and size of `obj` from the ScreenLayout element called `name`.
function GuiLayout.place(obj: GuiObject, name: string)
	local e = ScreenLayout.element(name)
	assert(e, `no ScreenLayout element {name}`)
	obj.AnchorPoint = Vector2.new(e.ax, e.ay)
	obj.Position = UDim2.fromScale(e.x, e.y)
	obj.Size = UDim2.fromScale(e.w, e.h)
end

-- MinTextSize / MaxTextSize on `label` from the element's text spec.
function GuiLayout.limitText(label: TextLabel | TextButton, name: string)
	local e = ScreenLayout.element(name)
	assert(e and e.text, `no ScreenLayout text {name}`)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = e.text.minSize
	limit.MaxTextSize = e.text.maxSize
	limit.Parent = label
end

return GuiLayout
