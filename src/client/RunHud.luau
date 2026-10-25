--!strict
-- Always-visible section meter and the end-beat banner (issue #16). Sound-off friendly: a meter
-- filling toward the next section, plus big banner text. The exact counter and section count stay
-- in Hud (issue #10); this adds the meter and the banner only. IN-ENGINE BEHAVIOUR IS UNVERIFIED.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ScreenLayout = require(Shared:WaitForChild("ScreenLayout"))
local GuiLayout = require(script.Parent:WaitForChild("GuiLayout"))
local HudMeters = require(Shared:WaitForChild("HudMeters"))

local WHITE = Color3.fromRGB(255, 255, 255)
local OUTLINE = Color3.fromRGB(28, 22, 34)

export type RunHud = {
	setMeter: (self: RunHud, meter: HudMeters.SectionMeter) -> (),
	setBanner: (self: RunHud, text: string?) -> (),
	setMeterVisible: (self: RunHud, visible: boolean) -> (),
	reset: (self: RunHud) -> (),
}

local RunHud = {}

function RunHud.new(): RunHud
	local gui = Instance.new("ScreenGui")
	gui.Name = "CalendaRunHud"
	gui.ResetOnSpawn = false
	GuiLayout.safe(gui)
	gui.DisplayOrder = ScreenLayout.DISPLAY_ORDER.runHud
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Meter: a bar under the counter that fills as loose followers approach the next section.
	local back = Instance.new("Frame")
	back.Name = "SectionMeter"
	GuiLayout.place(back, "SectionMeter")
	back.BackgroundColor3 = Color3.fromRGB(30, 20, 30)
	back.BackgroundTransparency = 0.35
	back.BorderSizePixel = 0
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(250, 204, 21)
	fill.BorderSizePixel = 0
	fill.Parent = back
	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.Size = UDim2.fromScale(1, 1)
	caption.BackgroundTransparency = 1
	caption.TextScaled = true
	GuiLayout.limitText(caption, "SectionMeter")
	caption.Font = Enum.Font.GothamBold
	caption.TextColor3 = WHITE
	caption.TextStrokeColor3 = OUTLINE
	caption.TextStrokeTransparency = 0
	caption.Parent = back

	back.Visible = false -- hidden until the first State

	local banner = Instance.new("TextLabel")
	banner.Name = "Banner"
	GuiLayout.place(banner, "Banner")
	GuiLayout.limitText(banner, "Banner")
	banner.BackgroundTransparency = 1
	banner.TextScaled = true
	banner.Font = Enum.Font.GothamBlack
	banner.TextColor3 = Color3.fromRGB(255, 221, 0)
	banner.TextStrokeColor3 = OUTLINE
	banner.TextStrokeTransparency = 0
	banner.Visible = false
	banner.Parent = gui
	local bannerScale = Instance.new("UIScale")
	bannerScale.Parent = banner

	local lastFraction, lastLabel, lastBanner = -1.0, "", ""
	local hud = {} :: RunHud

	function hud.setMeter(_, meter: HudMeters.SectionMeter)
		if meter.fraction ~= lastFraction then
			lastFraction = meter.fraction
			fill.Size = UDim2.fromScale(meter.fraction, 1)
		end
		if meter.label ~= lastLabel then
			lastLabel = meter.label
			caption.Text = meter.label
		end
	end

	function hud.setMeterVisible(_, visible: boolean)
		back.Visible = visible
	end

	function hud.setBanner(_, text: string?)
		local shown = text or ""
		if shown == lastBanner then
			return
		end
		lastBanner = shown
		banner.Visible = text ~= nil
		if text ~= nil then
			banner.Text = text
			bannerScale.Scale = 0.4
			TweenService:Create(
				bannerScale,
				TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Scale = 1 }
			):Play()
		end
	end

	function hud.reset(_)
		lastFraction, lastLabel, lastBanner = -1.0, "", ""
		banner.Visible = false
	end

	return hud
end

return RunHud
