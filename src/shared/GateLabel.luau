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

return GateLabel
