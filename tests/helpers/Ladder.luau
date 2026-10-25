--!strict
-- Policy-ladder evidence report (issue #17). Runs bots through the real RunDriver/RunHooks and
-- prints, for each policy, n, the completed rate, the defeat time and the final followers (ADR 0006).
-- It REPORTS observed numbers only. It asserts nothing about balance and never says a layout is
-- "balanced" or that "the player has to react": any threshold for that is an owner decision.
local BotHarness = require("./BotHarness")
local DebugLayout = require("../../src/shared/DebugLayout")
local Level = require("../../src/shared/Level")

local Ladder = {}

export type Config = {
	randomSeeds: number, -- seeds per random policy per cell (the full ladder uses 200)
	perturbedLayouts: number, -- how many named perturbed layouts (seeds 101..)
	familySize: number, -- layouts in the perturbation-family row (0 = skip the row)
	rates: { number },
	label: string,
}

Ladder.FULL = {
	randomSeeds = 200,
	perturbedLayouts = 3,
	familySize = 50,
	rates = { 30, 60 },
	label = "FULL",
} :: Config
Ladder.SMOKE = {
	randomSeeds = 5,
	perturbedLayouts = 0,
	familySize = 0,
	rates = { 30 },
	label = "SMOKE",
} :: Config

local RANDOM = { ["random-side-0.5s"] = true, ["noisy-scripted"] = true }

type Row = {
	policy: string,
	n: number,
	completed: number,
	defeatTimes: { number },
	finalTotals: { number },
	overMax: number,
}

local function summarize(results: { BotHarness.Result }, policy: string, maxTotal: number): Row
	local row: Row = {
		policy = policy,
		n = #results,
		completed = 0,
		defeatTimes = {},
		finalTotals = {},
		overMax = 0,
	}
	for _, r in results do
		table.insert(row.finalTotals, r.total)
		if r.total > maxTotal then
			row.overMax += 1
		end
		if r.outcome == "completed" then
			row.completed += 1
		elseif r.outcome == "defeated" then
			table.insert(row.defeatTimes, r.time)
		end
	end
	table.sort(row.defeatTimes)
	table.sort(row.finalTotals)
	return row
end

local function triple(sorted: { number }, fmt: string): string
	if #sorted == 0 then
		return "-"
	end
	return string.format(
		`{fmt}/{fmt}/{fmt}`,
		sorted[1],
		BotHarness.quantile(sorted, 0.5),
		sorted[#sorted]
	)
end

local function formatRow(row: Row): string
	return string.format(
		"%-22s %4d %6.1f%%  %3d  %-20s  %s%s",
		row.policy,
		row.n,
		100 * row.completed / row.n,
		#row.defeatTimes,
		triple(row.defeatTimes, "%.1f"),
		triple(row.finalTotals, "%d"),
		if row.overMax > 0 then `  [{row.overMax} > maxTotal]` else ""
	)
end

local HEADER = string.format(
	"%-22s %4s %7s  %3s  %-20s  %s",
	"policy",
	"n",
	"compl",
	"nD",
	"defeat s min/med/max",
	"final total min/med/max"
)

-- Runs every policy over `layouts` (one run per layout per seed) at `hz` and returns the rows.
local function cell(layouts: { Level.Layout }, hz: number, cfg: Config, maxTotal: number): { Row }
	local rows: { Row } = {}
	for _, proto in BotHarness.policies(1) do
		local random = RANDOM[proto.name] == true
		local n = if random then cfg.randomSeeds else math.max(1, #layouts)
		local results: { BotHarness.Result } = {}
		for i = 1, n do
			local layout = layouts[(i - 1) % #layouts + 1]
			local policy = BotHarness.policy(proto.name, i)
			table.insert(results, BotHarness.play(layout, policy, { hz = hz }))
		end
		table.insert(rows, summarize(results, proto.name, maxTotal))
	end
	return rows
end

function Ladder.report(cfg: Config): string
	local out: { string } = {}
	local function line(s: string)
		table.insert(out, s)
	end
	local fixed = DebugLayout
	line(`=== POLICY LADDER ({cfg.label}) - observed facts only, no balance claim ===`)
	line(
		`Method: real RunDriver + RunHooks, bot steers via driver:steer (<=20/s), fixed tick 1/hz, sim clock.`
	)
	line(
		`n = runs per row. Deterministic policies: 1 run per layout. Random policies (random-side-0.5s, noisy-scripted): {cfg.randomSeeds} fixed seeds (LCG, seed = run index) on cycled layouts.`
	)
	line(
		`Final total is over ALL n runs (a defeated run ends at 0 followers). nD = defeated runs; defeat s is over those only. compl = completed rate.`
	)
	line(
		`Perturbation: cluster spawnTime +-0.75 s, spawn z +-8 studs, fixed-seed LCG; gates, obstacles, sides, plaza unchanged.`
	)
	line(
		`[> maxTotal] counts runs whose final total exceeded DebugLayout.maxTotal ({fixed.maxTotal}).`
	)
	line("")

	local named: { { name: string, layouts: { Level.Layout } } } =
		{ { name = "fixed debug-1", layouts = { fixed } } }
	for i = 1, cfg.perturbedLayouts do
		local l = BotHarness.perturb(fixed, 100 + i)
		table.insert(named, { name = `perturbed seed {100 + i} ({l.name})`, layouts = { l } })
	end
	if cfg.familySize > 0 then
		local family: { Level.Layout } = {}
		for i = 1, cfg.familySize do
			table.insert(family, BotHarness.perturb(fixed, i))
		end
		table.insert(named, {
			name = `perturbation family: {cfg.familySize} layouts (seeds 1..{cfg.familySize})`,
			layouts = family,
		})
	end
	for _, hz in cfg.rates do
		for _, entry in named do
			line(`--- layout: {entry.name} | {hz} Hz ---`)
			line(HEADER)
			for _, row in cell(entry.layouts, hz, cfg, fixed.maxTotal) do
				line(formatRow(row))
			end
			line("")
		end
	end
	return table.concat(out, "\n")
end

-- Follower trajectory (time, followers after each attack) for the no-input and scripted runs (ADR 0006).
function Ladder.trajectories(hz: number): string
	local out: { string } =
		{ `--- Follower trajectories, fixed debug-1, {hz} Hz (attack time: followers after) ---` }
	for _, name in { "none", "scripted" } do
		local r = BotHarness.play(DebugLayout, BotHarness.policy(name, 1), { hz = hz })
		local parts: { string } = {}
		for _, a in r.attacks do
			table.insert(parts, string.format("c%d(%s)@%.2fs:%d", a.id, a.kind, a.time, a.after))
		end
		table.insert(
			out,
			`{name}: {tostring(r.outcome)} at {string.format("%.2f", r.time)}s, total {r.total}, attacks {#r.attacks}: {table.concat(
				parts,
				" "
			)}`
		)
	end
	return table.concat(out, "\n")
end

return Ladder
