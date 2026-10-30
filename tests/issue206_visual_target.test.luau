--!strict
-- Issue #206: the owner's visual target. Enemy hordes read as one saturated red mass, the parade
-- and converted runners as one blue family, and the reward "+N" floater is small and never drawn
-- over the gate numbers. Display palettes only: no authority, count or event changes.
-- IN-ENGINE LOOK IS UNVERIFIED.
local fs = require("@lune/fs")
local FeedbackMath = require("../src/shared/FeedbackMath")
local FollowerLook = require("../src/shared/FollowerLook")
local MobCharge = require("../src/shared/MobCharge")
local Layouts = require("../src/shared/Layouts")

local function isRed(c: { number }): boolean
	return c[1] >= 190 and c[2] <= 80 and c[3] <= 80
end

local function isBlue(c: { number }): boolean
	return c[3] >= 200 and c[1] <= 90 and c[2] >= c[1] and c[2] <= 170
end

return {
	{
		name = "issue 206: every authored layout sends all its hordes down one lane",
		run = function()
			for _, layout in Layouts.all do
				local lane = layout.clusters[1].lane
				assert(lane ~= "center", `{layout.name}: horde lane must be a side lane`)
				for _, c in layout.clusters do
					assert(
						c.lane == lane,
						`{layout.name}: cluster {c.id} is in {c.lane}, expected {lane}`
					)
				end
			end
		end,
	},
	{
		name = "issue 206: every enemy horde tone is a saturated red",
		run = function()
			for i, c in MobCharge.ANGRY do
				assert(isRed(c), `ANGRY[{i}] = {table.concat(c, ",")} is not saturated red`)
			end
		end,
	},
	{
		name = "issue 206: parade costumes and converted runners are one blue family",
		run = function()
			for i, c in FollowerLook.PALETTE do
				assert(isBlue(c), `PALETTE[{i}] = {table.concat(c, ",")} is not saturated blue`)
			end
			for i, c in MobCharge.PARTY do
				assert(isBlue(c), `PARTY[{i}] = {table.concat(c, ",")} is not saturated blue`)
			end
		end,
	},
	{
		name = "issue 206: ally blue and enemy red never overlap",
		run = function()
			for _, e in MobCharge.ANGRY do
				for _, a in FollowerLook.PALETTE do
					assert(a[3] > a[1] + 100 and e[1] > e[3] + 100, "ally/enemy hues must differ")
				end
			end
		end,
	},
	{
		name = "issue 206: the reward floater is small and not always-on-top",
		run = function()
			local size = (FeedbackMath :: any).FLOAT_GUI_SIZE
			assert(size ~= nil, "FeedbackMath.FLOAT_GUI_SIZE missing")
			assert(size.x <= 72 and size.y <= 32, "reward floater billboard is too large")
			assert(
				(FeedbackMath :: any).FLOAT_ALWAYS_ON_TOP == false,
				"floater must not cover gates"
			)
			local src = fs.readFile("src/client/ClusterView.luau")
			assert(
				string.find(src, "FeedbackMath.FLOAT_GUI_SIZE", 1, true),
				"ClusterView does not use the floater size"
			)
			assert(
				string.find(src, "gui.AlwaysOnTop = FeedbackMath.FLOAT_ALWAYS_ON_TOP", 1, true),
				"ClusterView floater AlwaysOnTop is not the named constant"
			)
		end,
	},
}
