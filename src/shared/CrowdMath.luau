--!strict
-- Authoritative crowd arithmetic (spec sections 5 and 7). Pure: no game/Instance access.
-- All tunables come from Config; the only constants here are the spec's fixed section-type order.
local Config = require("./Config")

export type OpKind = "add" | "multiply" | "loss"
export type Op = { kind: OpKind, value: number }
export type SectionType = "puppet" | "globo" | "dancers"
export type Direction = "up" | "down" | "none"
-- One result per total change, however many boundaries it crosses (spec s7: one celebration).
-- `sections` holds 1-based section indices: ascending when forming (up), newest first when
-- dispersing (down). `types` is parallel to `sections`.
export type Crossings = {
	direction: Direction,
	count: number,
	sections: { number },
	types: { SectionType },
}

-- Spec s7: deterministic repeating sequence puppet -> globo -> dancers.
local SECTION_SEQUENCE: { SectionType } = { "puppet", "globo", "dancers" }

local function isWholeNumber(v: any): boolean
	return type(v) == "number" and v >= 0 and v == math.floor(v) and v < math.huge
end

local function checkTotal(total: any, name: string)
	if not isWholeNumber(total) then
		error(`{name} must be a non-negative integer, got {total}`, 3)
	end
end

local function sectionCount(total: number): number
	checkTotal(total, "total")
	return total // Config.sectionSize
end

local function looseFollowers(total: number): number
	checkTotal(total, "total")
	return total % Config.sectionSize
end

local function sectionType(index: number): SectionType
	if type(index) ~= "number" or index < 1 or index ~= math.floor(index) then
		error(`section index must be a positive integer, got {index}`, 2)
	end
	return SECTION_SEQUENCE[(index - 1) % #SECTION_SEQUENCE + 1]
end

-- Applies one gate or obstacle to the whole total. Always returns a non-negative integer.
local function applyOp(total: number, op: Op): number
	checkTotal(total, "total")
	local value = op.value
	if not isWholeNumber(value) then
		error(`op.value must be a non-negative integer, got {value}`, 2)
	end
	if op.kind == "add" then
		return total + value
	elseif op.kind == "multiply" then
		if value < 2 then
			error("multiply value must be >= 2", 2)
		end
		return total * value
	elseif op.kind == "loss" then
		return math.max(0, total - value)
	end
	error(`unknown op kind {op.kind}`, 2)
end

-- ADR 0006 (Amendment 4): the share of the parade a single hit removes, computed from the total
-- before the hit. Whole followers, rounded down, never fewer than `minimum`. Pure.
local function shareLoss(total: number, percent: number, minimum: number): number
	return math.max(minimum, math.floor(total * percent / 100))
end

local function startingTotal(): number
	return Config.startingTotal
end

local function obstacleOp(): Op
	return { kind = "loss", value = Config.obstacleLoss }
end

-- Section boundaries crossed between two totals, reported once. Up: sections that form.
-- Down: sections that disperse, newest first (spec s5: the newest section disperses).
local function crossings(from: number, to: number): Crossings
	local before = sectionCount(from)
	local after = sectionCount(to)
	local sections: { number } = {}
	local types: { SectionType } = {}
	local direction: Direction = "none"
	if after > before then
		direction = "up"
		for i = before + 1, after do
			table.insert(sections, i)
			table.insert(types, sectionType(i))
		end
	elseif after < before then
		direction = "down"
		for i = before, after + 1, -1 do
			table.insert(sections, i)
			table.insert(types, sectionType(i))
		end
	end
	return { direction = direction, count = #sections, sections = sections, types = types }
end

return {
	startingTotal = startingTotal,
	sectionCount = sectionCount,
	looseFollowers = looseFollowers,
	sectionType = sectionType,
	applyOp = applyOp,
	obstacleOp = obstacleOp,
	shareLoss = shareLoss,
	crossings = crossings,
}
