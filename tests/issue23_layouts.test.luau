--!strict
-- Issue #23: three authored layouts selected by recorded seed (spec s9). Each must pass the
-- layout validator (the #7 timeline, growth, completability and recruit-total model), and a seed
-- must select one of them deterministically and be recorded in the run log.
local Config = require("../src/shared/Config")
local DebugLayout = require("../src/shared/DebugLayout")
local LayoutValidator = require("../src/shared/LayoutValidator")
local Layouts = require("../src/shared/Layouts")
local RunDriver = require("../src/shared/RunDriver")
local RunHooks = require("../src/shared/RunHooks")

local function errorsOf(layout: any): string
	local r = LayoutValidator.check(layout)
	return table.concat(r.errors, " | ")
end

local function gateSignature(layout: any): string
	local parts = {}
	for _, g in layout.gates do
		table.insert(parts, `{g.left.kind}{g.left.value}/{g.right.kind}{g.right.value}`)
	end
	return table.concat(parts, ",")
end

local function clusterSignature(layout: any): string
	local parts = {}
	for _, c in layout.clusters do
		table.insert(parts, `{c.type}{c.spawn.x}@{c.spawnTime}`)
	end
	return table.concat(parts, ",")
end

return {
	{
		name = "catalogue holds exactly three layouts with distinct names",
		run = function()
			assert(#Layouts.all == 3, `expected 3 layouts, got {#Layouts.all}`)
			assert(Layouts.all[1].name ~= Layouts.all[2].name, "names must differ")
			assert(Layouts.all[1].name ~= Layouts.all[3].name, "names must differ")
			assert(Layouts.all[2].name ~= Layouts.all[3].name, "names must differ")
		end,
	},
	{
		name = "each authored layout passes the layout validator with no errors",
		run = function()
			for _, layout in Layouts.all do
				local r = LayoutValidator.check(layout)
				assert(r.ok, `{layout.name} rejected: {table.concat(r.errors, " | ")}`)
				assert(r.routeCount == 2 ^ #layout.gates, `{layout.name}: routes not enumerated`)
			end
		end,
	},
	{
		name = "each authored layout is deeply frozen like the debug layout",
		run = function()
			for _, layout in Layouts.all do
				assert(table.isfrozen(layout), `{layout.name} not frozen`)
				assert(table.isfrozen(layout.gates), `{layout.name} gates not frozen`)
				assert(table.isfrozen(layout.clusters[1].spawn), `{layout.name} spawn not frozen`)
			end
		end,
	},
	{
		name = "layouts are distinct arrangements: gates or cluster sides differ pairwise",
		run = function()
			for i = 1, #Layouts.all do
				for j = i + 1, #Layouts.all do
					local a, b = Layouts.all[i], Layouts.all[j]
					assert(
						gateSignature(a) ~= gateSignature(b)
							or clusterSignature(a) ~= clusterSignature(b),
						`{a.name} and {b.name} are the same arrangement`
					)
				end
			end
		end,
	},
	{
		name = "each layout offers a route tradeoff: a gate where the two options differ in kind",
		run = function()
			for _, layout in Layouts.all do
				local tradeoff = false
				for _, g in layout.gates do
					if g.left.kind ~= g.right.kind then
						tradeoff = true
					end
				end
				assert(tradeoff, `{layout.name} has no add-versus-multiply gate`)
			end
		end,
	},
	{
		name = "select: same seed always gives the same layout",
		run = function()
			for seed = 0, 20 do
				assert(
					Layouts.select(seed).name == Layouts.select(seed).name,
					`seed {seed} not stable`
				)
			end
		end,
	},
	{
		name = "select: seeds 0, 1 and 2 reach all three layouts",
		run = function()
			local seen: { [string]: boolean } = {}
			for seed = 0, 2 do
				seen[Layouts.select(seed).name] = true
			end
			for _, layout in Layouts.all do
				assert(seen[layout.name], `{layout.name} never selected by seeds 0..2`)
			end
		end,
	},
	{
		name = "select: the chosen seed is recorded on the returned layout",
		run = function()
			for _, seed in { 0, 1, 2, 7, 1000 } do
				local layout = Layouts.select(seed)
				assert(layout.seed == seed, `seed {seed} recorded as {layout.seed}`)
			end
		end,
	},
	{
		name = "select: a seed's layout still passes the validator",
		run = function()
			for _, seed in { 0, 1, 2, 7 } do
				local e = errorsOf(Layouts.select(seed))
				assert(e == "", `seed {seed}: {e}`)
			end
		end,
	},
	{
		name = "select: non-finite, negative or fractional seeds are rejected",
		run = function()
			for _, bad in { -1, 0.5, math.huge, 0 / 0 } do
				local ok = pcall(Layouts.select, bad)
				assert(not ok, `seed {bad} was accepted`)
			end
		end,
	},
	{
		name = "the run log records the seed of the selected layout",
		run = function()
			local layout = Layouts.select(2)
			local driver = RunDriver.new({
				layout = layout,
				automated = true,
				hooks = RunHooks.new(layout),
			})
			local log = driver:runLog()
			assert(log.seed == 2, `run log seed is {log.seed}, expected 2`)
		end,
	},
	{
		name = "the fixed debug layout is still available unchanged",
		run = function()
			assert(LayoutValidator.check(DebugLayout).ok, "debug layout no longer valid")
			assert(Config.speed > 0, "speed must be positive")
		end,
	},
}
