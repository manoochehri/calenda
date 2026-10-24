--!strict
-- `make ladder`: the full policy-ladder report to stdout (issue #17). Not part of `make test`.
local DebugLayout = require("../src/shared/DebugLayout")
local LayoutValidator = require("../src/shared/LayoutValidator")
local BotHarness = require("./helpers/BotHarness")
local Ladder = require("./helpers/Ladder")

print(Ladder.report(Ladder.FULL))
print(Ladder.trajectories(30))
print(Ladder.trajectories(60))
print("")

-- maxTotal reconciliation: the validator's bound vs what a real run reaches.
local v = LayoutValidator.check(DebugLayout)
local s = BotHarness.play(DebugLayout, BotHarness.policy("scripted", 1))
print("--- maxTotal reconciliation (fixed debug-1) ---")
print(`DebugLayout.maxTotal = {DebugLayout.maxTotal}`)
print(
	`LayoutValidator best route = {v.bestFinal} (it credits only {v.recruitTotalBaseRate} recruits, simulated at the constant base fire rate; the layout offers {v.recruitTotalAvailable})`
)
print(`scripted run through the real driver: final total {s.total}, cluster credits {s.credits}`)
