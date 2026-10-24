--!strict
-- Trivial pure module proving the Lune harness can load code from src/shared (ADR 0001).
local Smoke = {}

function Smoke.add(a: number, b: number): number
	return a + b
end

return Smoke
