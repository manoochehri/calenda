--!strict
-- Display-only text for gate pairs. The result is computed from the same authoritative
-- arithmetic as RunState so labels can be refreshed from the latest server total.
local CrowdMath = require("./CrowdMath")

export type Op = { kind: "add" | "multiply", value: number }

local GateLabel = {}

function GateLabel.format(op: Op, total: number): (string, string)
	if type(op) ~= "table" or (op.kind ~= "add" and op.kind ~= "multiply") then
		error("gate op must be add or multiply", 2)
	end
	local result = CrowdMath.applyOp(total, op)
	local symbol = if op.kind == "add" then "+" else "x"
	return `{symbol}{op.value}`, `→ {result}`
end

-- The BIG line (issue #82): just the number for an adder (the badge carries the "+"), "x3" for a
-- multiplier. The full "+20" stays in GateLabel.format for the smaller result line and the HUD.
function GateLabel.big(op: Op): string
	if type(op) ~= "table" or (op.kind ~= "add" and op.kind ~= "multiply") then
		error("gate op must be add or multiply", 2)
	end
	return if op.kind == "add" then `{op.value}` else `x{op.value}`
end

return GateLabel
