--!strict
-- The one place the client mirrors the lateral axis (issue #58). All pure and server logic uses
-- "left = negative world x" (Level.sideOf, RunState, InputIntent, Targeting, DebugLayout) and means
-- the SCREEN's left. CameraRig looks along +Z with up +Y, and in Roblox's right-handed world that
-- camera has screen-right = world -X, so an unmirrored world draws left on the right. The client
-- therefore converts every world/state x (and every lateral offset) with ViewMap.x when it builds a
-- Roblox position; the world, the server and the input intent keep their meaning.
-- Rule: world -> Roblox position goes through ViewMap.x; never the other way round except fromView.
local ViewMap = {}

-- World x (or lateral offset, left negative) -> x of the Roblox position to draw.
function ViewMap.x(worldX: number): number
	return -worldX + 0 -- "+ 0" turns -0 into 0
end

-- Inverse (the mirror is its own inverse): Roblox x -> world x.
function ViewMap.fromView(viewX: number): number
	return -viewX + 0
end

-- World x of a gate panel's centre: left gates sit at negative x, right at positive x.
function ViewMap.gateWorldX(side: string, halfWidth: number): number
	local anchor = halfWidth / 2
	return if side == "left" then -anchor else anchor
end

return ViewMap
