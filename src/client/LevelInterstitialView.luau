--!strict
-- Presentation for the between-level card (issue #129). The lead avatar remains the player's
-- own character in the world behind this light card; this module only owns the readable overlay.
-- IN-ENGINE BEHAVIOUR IS UNVERIFIED until the issue's Studio checklist is run.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ScreenLayout = require(Shared:WaitForChild("ScreenLayout"))
local TypeStyle = require(script.Parent:WaitForChild("TypeStyle"))

export type View = {
	show: (self: View, level: number, levelName: string) -> (),
	hide: (self: View) -> (),
}

local View = {}

function View.new(onSkip: () -> ()): View
	local gui = Instance.new("ScreenGui")
	gui.Name = "CalendaLevelInterstitial"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = ScreenLayout.DISPLAY_ORDER.runHud
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(39, 29, 57)
	backdrop.BackgroundTransparency = 0.18
	backdrop.BorderSizePixel = 0
	backdrop.Parent = gui

	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.45)
	card.Size = UDim2.fromScale(0.72, 0.42)
	card.BackgroundColor3 = Color3.fromRGB(246, 178, 60)
	card.BackgroundTransparency = 0.08
	card.BorderSizePixel = 0
	TypeStyle.pill(card)
	card.Parent = gui

	local avatar = Instance.new("ViewportFrame")
	avatar.Name = "Avatar"
	avatar.Position = UDim2.fromScale(0.04, 0.08)
	avatar.Size = UDim2.fromScale(0.30, 0.84)
	avatar.BackgroundTransparency = 1
	avatar.Ambient = Color3.fromRGB(210, 210, 210)
	avatar.LightColor = Color3.fromRGB(255, 235, 190)
	avatar.LightDirection = Vector3.new(-1, -1, -1)
	avatar.Parent = card
	local world = Instance.new("WorldModel")
	world.Parent = avatar
	local camera = Instance.new("Camera")
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 2.5, 8), Vector3.new(0, 2.5, 0))
	camera.FieldOfView = 35
	camera.Parent = avatar
	avatar.CurrentCamera = camera
	local avatarGeneration = 0
	local function populateAvatar(generation: number)
		local character = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
		if generation ~= avatarGeneration or not gui.Enabled then
			return
		end
		character:WaitForChild("HumanoidRootPart", 2)
		if generation ~= avatarGeneration or not gui.Enabled then
			return
		end
		-- Character models may opt out of cloning. This is a local presentation copy, so explicitly
		-- enable cloning and leave the live character untouched if the property cannot be changed.
		local archivable = character.Archivable
		local setArchivable = pcall(function()
			character.Archivable = true
		end)
		local ok, clone =
			if setArchivable
				then pcall(function()
					return character:Clone()
				end)
				else false, nil
		pcall(function()
			character.Archivable = archivable
		end)
		if not ok or clone == nil then
			return
		end
		for _, descendant in world:GetChildren() do
			descendant:Destroy()
		end
		for _, descendant in clone:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanTouch = false
				descendant.CanQuery = false
			end
		end
		clone:PivotTo(CFrame.new())
		clone.Parent = world
	end

	local title = Instance.new("TextLabel")
	title.Name = "NextLevel"
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.43)
	title.Size = UDim2.fromScale(0.86, 0.48)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextScaled = true
	title.Font = TypeStyle.font("title")
	TypeStyle.outline(title)
	title.Parent = card

	local skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.Size = UDim2.fromScale(1, 1)
	skip.BackgroundTransparency = 1
	skip.Text = ""
	skip.AutoButtonColor = false
	skip.Activated:Connect(onSkip)
	skip.Parent = gui

	local view = {} :: View
	function view.show(_, level: number, levelName: string)
		avatarGeneration += 1
		for _, child in world:GetChildren() do
			child:Destroy()
		end
		title.Text = if levelName ~= "" then `Nivel {level}\n{levelName}` else `Nivel {level}`
		gui.Enabled = true
		task.spawn(populateAvatar, avatarGeneration)
	end
	function view.hide(_)
		avatarGeneration += 1
		gui.Enabled = false
	end
	return view
end

return View
