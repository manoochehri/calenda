--!strict
-- Issue #256 / #147: on-device perf overlay behind Config.debug.perfOverlay. One TextLabel, text
-- rebuilt at 2 Hz (the Workspace walk is the only cost and runs only when the switch is on); dt is
-- sampled every frame into a rolling window (PerfStats). The owner reads Parts / Emitters / Trails
-- and dt p50/p95 off a phone screenshot. Display only; in-engine behaviour is UNVERIFIED.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PerfStats = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PerfStats"))

local WINDOW = 300 -- [default] frames in the rolling window (about 5 s at 60 fps)
local REFRESH = 0.5 -- [default] seconds between text updates

local PerfOverlay = {}

function PerfOverlay.new()
	local gui = Instance.new("ScreenGui")
	gui.Name = "CalendaPerfOverlay"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1000
	local label = Instance.new("TextLabel")
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.BackgroundTransparency = 0.25
	label.TextColor3 = Color3.new(1, 1, 0.4)
	label.Font = Enum.Font.Code
	label.TextSize = 28
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.AnchorPoint = Vector2.new(0, 1)
	label.Position = UDim2.fromScale(0.01, 0.99)
	label.Size = UDim2.fromOffset(620, 120)
	label.Text = ""
	label.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local stats = PerfStats.new(WINDOW)
	local sinceRefresh = REFRESH -- draw on the first frame
	local self = {}

	function self.frame(_, dt: number)
		stats:push(dt)
		sinceRefresh += dt
		if sinceRefresh < REFRESH then
			return
		end
		sinceRefresh = 0
		local parts, emitters, trails = 0, 0, 0
		for _, d in Workspace:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			elseif d:IsA("ParticleEmitter") then
				emitters += 1
			elseif d:IsA("Trail") then
				trails += 1
			end
		end
		label.Text = PerfStats.format(
			parts,
			emitters,
			trails,
			stats:percentile(0.5),
			stats:percentile(0.95),
			stats.n
		)
	end

	return self
end

return PerfOverlay
