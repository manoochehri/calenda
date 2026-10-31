--!strict
local Config = require("../src/shared/Config")
local CrowdMath = require("../src/shared/CrowdMath")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {expected}, got {actual}`)
end

local function listEq(actual: { any }, expected: { any }, name: string)
	eq(#actual, #expected, `{name} length`)
	for i = 1, #expected do
		eq(actual[i], expected[i], `{name}[{i}]`)
	end
end

local function add(n: number): CrowdMath.Op
	return { kind = "add", value = n }
end

local function mul(n: number): CrowdMath.Op
	return { kind = "multiply", value = n }
end

local function loss(n: number): CrowdMath.Op
	return { kind = "loss", value = n }
end

local function expectSplit(total: number, sections: number, loose: number)
	eq(CrowdMath.sectionCount(total), sections, `sectionCount({total})`)
	eq(CrowdMath.looseFollowers(total), loose, `looseFollowers({total})`)
end

return {
	{
		name = "spec: start at 10 is 10 loose followers, no section",
		run = function()
			eq(CrowdMath.startingTotal(), Config.startingTotal, "startingTotal")
			expectSplit(CrowdMath.startingTotal(), 0, 0)
		end,
	},
	{
		name = "spec: 49 + 1 = 50 forms the first section",
		run = function()
			expectSplit(49, 0, 49)
			local after = CrowdMath.applyOp(49, add(1))
			eq(after, 50, "49+1")
			expectSplit(after, 1, 0)
		end,
	},
	{
		name = "spec: 120 is 2 sections + 20 loose",
		run = function()
			expectSplit(120, 2, 20)
		end,
	},
	{
		name = "spec: 120 x2 = 240 is 4 sections + 40 loose",
		run = function()
			local after = CrowdMath.applyOp(120, mul(2))
			eq(after, 240, "120x2")
			expectSplit(after, 4, 40)
		end,
	},
	{
		name = "spec: 105 - 10 = 95 is 1 section + 45 loose",
		run = function()
			expectSplit(105, 2, 5)
			local after = CrowdMath.applyOp(105, loss(Config.obstacleLoss))
			eq(after, 95, "105-10")
			expectSplit(after, 1, 45)
		end,
	},
	{
		name = "obstacleOp builds the Config loss",
		run = function()
			local op = CrowdMath.obstacleOp()
			eq(op.kind, "loss", "kind")
			eq(op.value, Config.obstacleLoss, "value")
			eq(CrowdMath.applyOp(105, op), 95, "105 with obstacleOp")
		end,
	},
	{
		name = "section boundary values use Config.sectionSize",
		run = function()
			local s = Config.sectionSize
			expectSplit(0, 0, 0)
			expectSplit(s - 1, 0, s - 1)
			expectSplit(s, 1, 0)
			expectSplit(s + 1, 1, 1)
			expectSplit(2 * s, 2, 0)
		end,
	},
	{
		name = "loss clamps at zero",
		run = function()
			eq(CrowdMath.applyOp(5, loss(10)), 0, "5-10")
			eq(CrowdMath.applyOp(0, loss(10)), 0, "0-10")
			eq(CrowdMath.applyOp(10, loss(10)), 0, "10-10")
			expectSplit(CrowdMath.applyOp(5, loss(10)), 0, 0)
		end,
	},
	{
		name = "applyOp add and multiply from zero stay integers",
		run = function()
			eq(CrowdMath.applyOp(0, add(20)), 20, "0+20")
			eq(CrowdMath.applyOp(0, mul(2)), 0, "0x2")
			eq(CrowdMath.applyOp(10, add(20)), 30, "10+20")
			eq(CrowdMath.applyOp(10, mul(2)), 20, "10x2")
			for _, op in Config.gateOps do
				local out = CrowdMath.applyOp(37, op :: CrowdMath.Op)
				eq(out, math.floor(out), "integer result")
			end
		end,
	},
	{
		name = "applyOp does not mutate its op",
		run = function()
			local op = add(20)
			CrowdMath.applyOp(10, op)
			eq(op.kind, "add", "kind")
			eq(op.value, 20, "value")
		end,
	},
	{
		name = "applyOp rejects invalid input",
		run = function()
			assert(not pcall(CrowdMath.applyOp, -1, add(1)), "negative total")
			assert(not pcall(CrowdMath.applyOp, 1.5, add(1)), "fractional total")
			assert(not pcall(CrowdMath.applyOp, 1, add(0.5)), "fractional value")
			assert(not pcall(CrowdMath.applyOp, 1, add(-1)), "negative value")
			assert(not pcall(CrowdMath.applyOp, 1, { kind = "divide", value = 2 } :: any), "kind")
			assert(not pcall(CrowdMath.applyOp, 1, mul(1)), "multiply below 2")
			assert(not pcall(CrowdMath.sectionCount, -1), "sectionCount negative")
			assert(not pcall(CrowdMath.looseFollowers, 2.5), "looseFollowers fractional")
		end,
	},
	{
		name = "10,000 stays exact",
		run = function()
			expectSplit(10000, 200, 0)
			expectSplit(10001, 200, 1)
			eq(CrowdMath.applyOp(5000, mul(2)), 10000, "5000x2")
			eq(CrowdMath.applyOp(9990, add(10)), 10000, "9990+10")
			eq(CrowdMath.applyOp(10010, loss(10)), 10000, "10010-10")
			eq(CrowdMath.applyOp(10000, loss(10)), 9990, "10000-10")
			local r = CrowdMath.crossings(0, 10000)
			eq(r.direction, "up", "direction")
			eq(r.count, 200, "count")
		end,
	},
	{
		name = "crossings: no boundary crossed",
		run = function()
			local r = CrowdMath.crossings(10, 30)
			eq(r.direction, "none", "direction")
			eq(r.count, 0, "count")
			eq(#r.sections, 0, "sections")
			local same = CrowdMath.crossings(50, 50)
			eq(same.direction, "none", "same total")
			eq(same.count, 0, "same total count")
		end,
	},
	{
		name = "crossings: 49 -> 50 crosses up once, forming section 1 (puppet)",
		run = function()
			local r = CrowdMath.crossings(49, 50)
			eq(r.direction, "up", "direction")
			eq(r.count, 1, "count")
			listEq(r.sections, { 1 }, "sections")
			listEq(r.types, { "puppet" }, "types")
		end,
	},
	{
		name = "crossings: multi-threshold jump reports once with all sections",
		run = function()
			-- 10 -> 240 in a single gate: sections 1..4, one result, count 4.
			local r = CrowdMath.crossings(10, 240)
			eq(r.direction, "up", "direction")
			eq(r.count, 4, "count")
			listEq(r.sections, { 1, 2, 3, 4 }, "sections")
			listEq(r.types, { "puppet", "globo", "dancers", "puppet" }, "types")
			-- Starting mid-way: 120 (2 sections) -> 240 (4) forms sections 3 and 4 only.
			local r2 = CrowdMath.crossings(120, 240)
			eq(r2.count, 2, "count 120->240")
			listEq(r2.sections, { 3, 4 }, "sections 120->240")
			listEq(r2.types, { "dancers", "puppet" }, "types 120->240")
		end,
	},
	{
		name = "crossings: down disperses the newest section, newest first",
		run = function()
			-- 105 (2 sections) -> 95 (1): section 2 (globo) disperses.
			local r = CrowdMath.crossings(105, 95)
			eq(r.direction, "down", "direction")
			eq(r.count, 1, "count")
			listEq(r.sections, { 2 }, "sections")
			listEq(r.types, { "globo" }, "types")
			-- 240 (4) -> 95 (1): sections 4, 3, 2 disperse, newest first, one result.
			local r2 = CrowdMath.crossings(240, 95)
			eq(r2.count, 3, "count")
			listEq(r2.sections, { 4, 3, 2 }, "sections")
			listEq(r2.types, { "puppet", "dancers", "globo" }, "types")
		end,
	},
	{
		name = "crossings: loss to zero disperses every section",
		run = function()
			local r = CrowdMath.crossings(100, 0)
			eq(r.direction, "down", "direction")
			listEq(r.sections, { 2, 1 }, "sections")
		end,
	},
	{
		name = "crossings: loose-only changes inside a section never cross",
		run = function()
			local r = CrowdMath.crossings(105, 100)
			eq(r.direction, "none", "down within section")
			local r2 = CrowdMath.crossings(100, 149)
			eq(r2.direction, "none", "up within section")
			-- exactly onto a boundary downward: 100 -> 99 drops section 2.
			local r3 = CrowdMath.crossings(100, 99)
			eq(r3.direction, "down", "100->99")
			listEq(r3.sections, { 2 }, "100->99 sections")
		end,
	},
	{
		name = "sectionType: puppet -> globo -> dancers, deterministic and repeating",
		run = function()
			local expected = { "puppet", "globo", "dancers" }
			for i = 1, 30 do
				eq(CrowdMath.sectionType(i), expected[(i - 1) % 3 + 1], `sectionType({i})`)
			end
			eq(CrowdMath.sectionType(200), "globo", "sectionType(200)")
			eq(CrowdMath.sectionType(1), CrowdMath.sectionType(1), "stable")
			assert(not pcall(CrowdMath.sectionType, 0), "index 0 invalid")
			assert(not pcall(CrowdMath.sectionType, 1.5), "fractional index invalid")
		end,
	},
	{
		name = "sequence puppet -> globo -> dancers through real gates",
		run = function()
			local total = 0
			local seen: { string } = {}
			for _ = 1, 4 do
				local before = total
				total = CrowdMath.applyOp(total, add(Config.sectionSize))
				local r = CrowdMath.crossings(before, total)
				for _, t in r.types do
					table.insert(seen, t)
				end
			end
			listEq(seen, { "puppet", "globo", "dancers", "puppet" }, "seen")
		end,
	},
	{
		name = "up then down round trip returns the same sections",
		run = function()
			local up = CrowdMath.crossings(10, 240)
			local down = CrowdMath.crossings(240, 10)
			eq(up.count, down.count, "count")
			for i = 1, up.count do
				eq(up.sections[i], down.sections[up.count - i + 1], `section {i}`)
			end
		end,
	},
}
