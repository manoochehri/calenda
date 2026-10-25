--!strict
local Config = require("../src/shared/Config")
local DebugLayout = require("../src/shared/DebugLayout")
local LayoutValidator = require("../src/shared/LayoutValidator")
local Level = require("../src/shared/Level")

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

return {
	{
		name = "route bound uses section-scaled fire rate after a section forms",
		run = function()
			local layout = clone(DebugLayout)
			layout.maxTotal = 119
			layout.intendedRecruitTotal = 20
			for i, gate in layout.gates do
				local value = if i == 1 then 40 elseif i == #layout.gates then 41 else 1
				local op = { kind = "add", value = value }
				gate.left = clone(op)
				gate.right = clone(op)
			end

			-- One early group clears the first-conversion requirement without forming a section.
			local clusters = {
				{
					id = 1,
					wave = 1,
					type = "small",
					spawnTime = 0,
					spawn = { x = -16, z = 300 },
					path = {},
				},
			}
			-- At t=20 these four small clusters are just inside range. The gate at 12 s has
			-- already formed one section, so the server fires at 7/s instead of the 6/s base.
			for i = 1, 4 do
				table.insert(clusters, {
					id = i + 1,
					wave = i + 1,
					type = "small",
					spawnTime = 0,
					spawn = {
						x = if i % 2 == 1 then 16 else -16,
						z = Level.leadZ(20)
							+ Config.firing.range
							+ Config.spectators.approachSpeed * 20,
					},
					path = {},
				})
			end
			layout.clusters = clusters

			local config = clone(Config)
			config.finaleThresholds = { 50 }
			local report = LayoutValidator.check(layout, config)
			assert(
				not report.ok,
				"validator must reject the route whose section-scaled fire exceeds maxTotal"
			)
			local errors = table.concat(report.errors, " | ")
			assert(string.find(errors, "above maxTotal", 1, true), errors)
			assert(
				report.bestFinal > layout.maxTotal,
				`best {report.bestFinal} <= maxTotal {layout.maxTotal}`
			)
			assert(
				report.recruitTotalAvailable == 25,
				"available reward remains distinct from route-converted reward"
			)
		end,
	},
}
