--!strict
-- Issue #238: a gate pair must be a real choice. Written before the validator rule; it fails
-- against the code that only checks timing, growth and completability.
--
-- DOMINATED: for every whole crowd size n in 0..maxTotal, one option's result
-- CrowdMath.applyOp(n, op) is >= the other's (so a tie everywhere also counts).
-- IN RANGE (stricter): among the crowd sizes actually reached on arrival at that gate across the
-- witness runs, at least one crowd favors each side strictly.
local Config = require("../src/shared/Config")
local CrowdMath = require("../src/shared/CrowdMath")
local DebugLayout = require("../src/shared/DebugLayout")
local LayoutValidator = require("../src/shared/LayoutValidator")
local LayoutWitness = require("../src/shared/LayoutWitness")
local Layouts = require("../src/shared/Layouts")

local function clone(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = clone(v)
	end
	return out
end

local function op(kind: string, value: number): any
	return { kind = kind, value = value }
end

local function z(baseZ: number): number
	return baseZ * Config.speed / 16
end

-- The seven rows of the played level as they were before #238 (rows 3 to 6 add versus add).
local function legacyGates(): any
	return {
		{ id = 1, z = z(192), left = op("add", 15), right = op("multiply", 2) },
		{ id = 2, z = z(320), left = op("multiply", 2), right = op("add", 20) },
		{ id = 3, z = z(512), left = op("add", 30), right = op("add", 40) },
		{ id = 4, z = z(736), left = op("add", 40), right = op("add", 50) },
		{ id = 5, z = z(928), left = op("add", 50), right = op("add", 40) },
		{ id = 6, z = z(1152), left = op("add", 80), right = op("add", 100) },
		{ id = 7, z = z(1344), left = op("multiply", 3), right = op("add", 200) },
	}
end

local function withGates(gates: any): any
	local l = clone(DebugLayout)
	l.name = "test-copy"
	l.gates = gates
	return l
end

local function joined(errors: { string }): string
	return table.concat(errors, " | ")
end

return {
	{
		name = "dominated: the four add-versus-add rows of the old played level are rejected by gate id",
		run = function()
			local report = LayoutValidator.check(withGates(legacyGates()))
			assert(not report.ok, "add versus add rows were accepted")
			local text = joined(report.errors)
			for _, id in { 3, 4, 5, 6 } do
				assert(
					string.find(text, `gate {id} is dominated`, 1, true),
					`gate {id} not reported as dominated in: {text}`
				)
			end
		end,
	},
	{
		name = "dominated: +15 versus x2 and x2 versus +20 are not reported as dominated",
		run = function()
			local report = LayoutValidator.check(withGates(legacyGates()))
			local text = joined(report.errors)
			assert(not string.find(text, "gate 1 is dominated", 1, true), text)
			assert(not string.find(text, "gate 2 is dominated", 1, true), text)
		end,
	},
	{
		name = "in range: x2 versus +100 at the first gate is rejected, the crowd there never reaches 100",
		run = function()
			local l = clone(DebugLayout)
			l.name = "test-copy"
			l.gates[1].left = op("multiply", 2)
			l.gates[1].right = op("add", 100)
			local report = LayoutValidator.check(l)
			assert(not report.ok, "x2 versus +100 was accepted")
			local text = joined(report.errors)
			assert(
				string.find(text, "gate 1 crossover", 1, true)
					and string.find(text, "outside the crowd range reached", 1, true),
				`expected an in-range rejection for gate 1 in: {text}`
			)
			assert(
				not string.find(text, "gate 1 is dominated", 1, true),
				"it is not dominated globally"
			)
		end,
	},
	{
		name = "played level: every gate row is a real choice, dominance and in range",
		run = function()
			local report = LayoutValidator.check(DebugLayout)
			assert(report.ok, joined(report.errors))
			local result = LayoutWitness.search(DebugLayout)
			for _, g in DebugLayout.gates do
				local choice = LayoutValidator.gateChoice(g.left, g.right, DebugLayout.maxTotal)
				assert(not choice.dominated, `gate {g.id} dominated`)
				local crowds = (result.gateCrowds :: any)[g.id]
				local leftWins, rightWins = 0, 0
				for _, n in crowds do
					local d = CrowdMath.applyOp(n, g.left) - CrowdMath.applyOp(n, g.right)
					if d > 0 then
						leftWins += 1
					elseif d < 0 then
						rightWins += 1
					end
				end
				print(
					`gate {g.id}: {#crowds} of {result.runs} runs, left better {leftWins}, right better {rightWins}`
				)
				assert(
					leftWins > 0 and rightWins > 0,
					`gate {g.id} favors one side at every reached crowd`
				)
			end
		end,
	},
	{
		name = "unplayed catalogue: layouts with dominated rows are each listed with a reason",
		run = function()
			for _, layout in Layouts.all do
				local copy = clone(layout)
				copy.name = "unlisted-copy"
				local report = LayoutValidator.check(copy)
				assert(
					string.find(joined(report.errors), "is dominated", 1, true),
					`{layout.name}: no dominated row reported; remove it from the exemption list`
				)
				local why = (LayoutValidator.UNPLAYED_EXEMPT :: any)[layout.name]
				assert(
					type(why) == "string" and #why > 20,
					`{layout.name} is not listed with a reason in LayoutValidator.UNPLAYED_EXEMPT`
				)
			end
		end,
	},
	{
		name = "choice: gateChoice reports crossover and dominance over 0..maxTotal",
		run = function()
			local choice = LayoutValidator.gateChoice
			assert(choice(op("add", 40), op("add", 50), 4000).dominated, "+40 vs +50")
			assert(choice(op("add", 50), op("add", 50), 4000).dominated, "equal ops tie everywhere")
			assert(not choice(op("add", 15), op("multiply", 2), 4000).dominated, "+15 vs x2")
			assert(choice(op("add", 15), op("multiply", 2), 4000).crossover == 15, "crossover 15")
			-- x2 versus +5 is NOT dominated over 0..maxTotal (+5 wins below 5); only the in-range test sees it.
			assert(not choice(op("multiply", 2), op("add", 5), 4000).dominated, "x2 vs +5 global")
		end,
	},
	{
		name = "witness: gate crowds are recorded for every gate on the same runs, with sample size",
		run = function()
			local result = LayoutWitness.search(DebugLayout)
			assert(result.gateCrowds ~= nil, "no gateCrowds in the witness result")
			for _, g in DebugLayout.gates do
				local crowds = (result.gateCrowds :: any)[g.id]
				assert(crowds ~= nil and #crowds > 0, `no crowd samples at gate {g.id}`)
				assert(#crowds <= result.runs, "more samples than runs")
			end
		end,
	},
}
