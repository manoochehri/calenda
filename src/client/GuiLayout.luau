--!strict
-- Issue #78: the one ScreenGui inset convention and the helpers that apply ScreenLayout's data.
-- Every HUD ScreenGui (text, meters, buttons) is `safe`: its 0..1 space is the safe area (clear of
-- notches, rounded corners and the Roblox top bar), IgnoreGuiInset = false. Purely decorative
-- full-screen layers (dim, title backdrop) are `fullScreen`. Mixing the two for
-- positions that must line up is the bug this fixes.
-- Source checked (create.roblox.com/docs/reference/engine/classes/ScreenGui.md): IgnoreGuiInset
-- only matters while ScreenInsets is CoreUISafeInsets. false (the default) keeps CoreUISafeInsets,
-- which keeps contents below the top bar and clear of cutouts; true switches CoreUISafeInsets to
-- DeviceSafeInsets (cutouts respected, top bar not). ScreenInsets = None applies no insets (and
-- makes ClipToDeviceSafeArea irrelevant); the docs recommend None only for non-interactive
-- backgrounds. So `safe` (false + CoreUISafeInsets) and `fullScreen` (true + None) are
-- consistent and nothing is inset twice, whatever order the two are set in. The inset SIZES in
-- ScreenLayout are estimates. IN-ENGINE BEHAVIOUR UNVERIFIED.
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
