--!strict
-- Keyboard and touch input -> one steering intent (issue #10). All the arithmetic is in the pure,
-- Lune-tested InputIntent; this module only reads Roblox input and calls it.
-- IN-ENGINE BEHAVIOUR IS UNVERIFIED (see the PR checklist).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local InputIntent = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("InputIntent"))

export type Controller = {
	step: (self: Controller, dt: number, now: number) -> (),
	reset: (self: Controller, x: number) -> (),
}

local InputController = {}

-- `bound` is the furthest |x| the lead may stand at (Steering.bound). `send` delivers one intent
-- to the server; the server clamps and rate limits it again.
function InputController.new(bound: number, send: (number) -> ()): Controller
	local intentX = 0
	local lastSentX: number? = nil
	local lastSentAt = 0
	local dragInput: InputObject? = nil
	local dragStartPixelX = 0
	local dragOriginX = 0

	local function viewportWidth(): number
		local camera = Workspace.CurrentCamera
		return if camera then camera.ViewportSize.X else 0
	end

	-- Touch drag: remember where the finger and the intent were, then move the intent by the drag.
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or input.UserInputType ~= Enum.UserInputType.Touch or dragInput then
			return
		end
		dragInput = input
		dragStartPixelX = input.Position.X
		dragOriginX = intentX
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if input == dragInput then
			intentX = InputIntent.dragToX(
				dragOriginX,
				input.Position.X - dragStartPixelX,
				viewportWidth(),
				bound
			)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input == dragInput then
			dragInput = nil
		end
	end)

	local controller = {} :: Controller

	function controller.step(_, dt: number, now: number)
		local axis = InputIntent.keyAxis(
			UserInputService:IsKeyDown(Enum.KeyCode.A)
				or UserInputService:IsKeyDown(Enum.KeyCode.Left),
			UserInputService:IsKeyDown(Enum.KeyCode.D)
				or UserInputService:IsKeyDown(Enum.KeyCode.Right)
		)
		if axis ~= 0 then
			intentX = InputIntent.stepKeys(intentX, axis, dt, bound)
		end
		if InputIntent.shouldSend(lastSentX, lastSentAt, intentX, now) then
			lastSentX, lastSentAt = intentX, now
			send(intentX)
		end
	end

	-- A new run starts at the lead's server position; forget the old drag.
	function controller.reset(_, x: number)
		intentX = math.clamp(x, -bound, bound)
		dragInput = nil
		lastSentX = intentX
	end

	return controller
end

return InputController
