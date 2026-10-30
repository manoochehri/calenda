--!strict
-- Ending-only banner (issue #16). Active gameplay has no screen text (issue #160).
-- IN-ENGINE BEHAVIOUR IS UNVERIFIED.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ScreenLayout = require(Shared:WaitForChild("ScreenLayout"))
local GuiLayout = require(script.Parent:WaitForChild("GuiLayout"))
local TypeStyle = require(script.Parent:WaitForChild("TypeStyle"))

export type RunHud = {
	setBanner: (self: RunHud, text: string?) -> (),
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

	local banner = Instance.new("TextLabel")
	banner.Name = "Banner"
	GuiLayout.place(banner, "Banner")
	GuiLayout.limitText(banner, "Banner")
	banner.BackgroundTransparency = 1
	banner.TextScaled = true
	banner.Font = TypeStyle.font("alert")
	TypeStyle.outline(banner)
	banner.TextColor3 = Color3.fromRGB(255, 221, 0)
	banner.TextStrokeTransparency = 1 -- use the glyph-shaped UIStroke only
	banner.Visible = false
	banner.Parent = gui
	local bannerScale = Instance.new("UIScale")
	bannerScale.Parent = banner

	local lastBanner = ""
	local hud = {} :: RunHud

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
		lastBanner = ""
		banner.Visible = false
	end

	return hud
end

return RunHud
