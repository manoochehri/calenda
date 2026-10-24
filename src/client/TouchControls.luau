--!strict
-- Turns off Roblox's default movement controls (touch thumbstick, WASD character movement). We
-- steer with our own drag/keys; the default thumbstick GUI would sink touches (InputBegan arrives
-- with processed == true) and the drag would be dropped where it sits. The `processed` check in
-- InputController stays, so taps on our own buttons (replay) are not read as steering.
--
-- Source checked: Roblox's PlayerModule exposes GetControls() returning the ControlModule, whose
-- Disable() hides the touch GUI and stops it reading input. The Creator Hub pages for
-- StarterPlayer.DevTouchMovementMode and Enum.DevTouchMovementMode (Scriptable = 5) list the
-- property but do not describe it, so that route is not used. UNVERIFIED in engine.
local Players = game:GetService("Players")

local TouchControls = {}

function TouchControls.disable()
	local player = Players.LocalPlayer
	local ok, err = pcall(function()
		local playerModule =
			require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10))
		playerModule:GetControls():Disable()
	end)
	if not ok then
		warn(`Calenda: could not disable default controls: {err}`)
	end
end

return TouchControls
