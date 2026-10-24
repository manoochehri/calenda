--!strict
local Config = require("../src/shared/Config")
local DebugLayout = require("../src/shared/DebugLayout")
local FollowerFlow = require("../src/shared/FollowerFlow")
local FollowerSlots = require("../src/shared/FollowerSlots")
local FollowerSource = require("../src/shared/FollowerSource")
local FollowerStagger = require("../src/shared/FollowerStagger")
local ViewMap = require("../src/shared/ViewMap")

local CAP = Config.visualBudget.looseAvatars
local DT = 1 / 60

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

-- Runs the flow for `seconds` with the lead moving down the street; returns the last frame and
-- the largest number of members / runners / leavers drawn in any frame.
local function run(flow: FollowerFlow.Flow, seconds: number, z0: number?, x: number?)
	local z = z0 or 100
	local frame
	local maxM, maxR, maxL, firstFull = 0, 0, 0, nil
	local times = {}
	for i = 1, math.floor(seconds / DT) do
		z += Config.speed * DT
		frame = flow:step(DT, x or 0, z, 0)
		maxM = math.max(maxM, #frame.members)
		maxR = math.max(maxR, #frame.runners)
		maxL = math.max(maxL, #frame.leavers)
		times[i] = #frame.members
	end
	return frame, maxM, maxR, maxL, times, z
end

local function newFlow(total: number): FollowerFlow.Flow
	local flow = FollowerFlow.new(DebugLayout.halfWidth)
	flow:reset(total)
	return flow
end

return {
	{
		name = "start: the existing loose followers are on the field at once (no join animation)",
		run = function()
			local flow = newFlow(12)
			local frame = flow:step(DT, 0, 100, 0)
			eq(#frame.members, 12, "12 settled members")
			eq(#frame.runners, 0, "no runners")
		end,
	},
	{
		name = "a +5 conversion joins one at a time from the converted group, not all in one frame",
		run = function()
			local flow = newFlow(3)
			flow:step(DT, 0, 100, 0)
			flow:hint({ kind = "cluster", x = -16, z = 130, side = "left" })
			flow:setTotal(8)
			local counts = {}
			local frame
			for i = 1, 90 do
				frame = flow:step(DT, 0, 100, 0)
				counts[i] = #frame.members
			end
			eq(counts[1], 4, "first joiner starts at once, the rest wait")
			local distinct = {}
			for _, c in counts do
				distinct[c] = true
			end
			assert(distinct[5] and distinct[6] and distinct[7], "member count climbs 4,5,6,7,...")
			eq(counts[90], 8, "all five arrived")
		end,
	},
	{
		name = "a joiner starts at the source (the converted group) and ends on its slot",
		run = function()
			local flow = newFlow(0)
			flow:step(DT, 0, 100, 0)
			flow:hint({ kind = "cluster", x = -16, z = 118, side = "left" })
			flow:setTotal(1)
			local first = flow:step(DT, 0, 100, 0).members[1]
			assert(math.abs(first.x + 16) < 4, `starts near the group, x={first.x}`)
			local frame = run(flow, 3, 100, 0)
			local m = frame.members[1]
			assert(math.abs(m.vx) < 2.5, "settled")
			local s = FollowerSlots.slot(m.slot, 0)
			assert(
				math.abs(m.x - s.dx) <= FollowerFlow.SWAY_AMPLITUDE + 0.05,
				"at its slot laterally"
			)
		end,
	},
	{
		name = "a +1000 jump never takes more than about a second and draws a bounded burst",
		run = function()
			local flow = newFlow(10)
			flow:step(DT, 0, 100, 0)
			flow:hint({ kind = "gate", x = 10, z = 100, side = "right" })
			flow:setTotal(1010)
			local lastStart = 0
			local _, maxM, maxR, _, _, _ = run(flow, 2.5, 100, 0)
			assert(maxM <= CAP, "members stay within the cap")
			assert(maxR <= FollowerFlow.STREAM_CAP, "stream bounded")
			local offsets = FollowerStagger.offsets(1000)
			lastStart = offsets[#offsets]
			assert(lastStart < 1.0, "schedule ends within a second")
			local counts = flow:counts()
			eq(counts.pending, 0, "nothing still waiting after 2.5s")
			eq(counts.runners, 0, "stream finished")
		end,
	},
	{
		name = "cap reached: extra joins stream in as runners that merge, members stay at the cap",
		run = function()
			local flow = newFlow(30) -- 30 loose, 24 drawn
			flow:step(DT, 0, 100, 0)
			flow:hint({ kind = "cluster", x = 16, z = 110, side = "right" })
			flow:setTotal(45) -- still 24 drawn, +15 exact
			local sawRunners = 0
			for _ = 1, 90 do
				local frame = flow:step(DT, 0, 100, 0)
				sawRunners = math.max(sawRunners, #frame.runners)
				eq(#frame.members, CAP, "members stay at the cap")
			end
			assert(sawRunners >= 3, `expected a visible stream, saw {sawRunners}`)
			eq(flow:counts().runners, 0, "all merged")
		end,
	},
	{
		name = "a gain that only grows sections still shows a stream (no loose change)",
		run = function()
			local flow = newFlow(53) -- 3 loose, 1 section
			flow:step(DT, 0, 100, 0)
			flow:hint({ kind = "gate", x = 10, z = 100, side = "right" })
			flow:setTotal(153)
			local saw = 0
			for _ = 1, 90 do
				saw = math.max(saw, #flow:step(DT, 0, 100, 0).runners)
			end
			assert(saw >= 5, "runners visible")
		end,
	},
	{
		name = "a loss peels followers off one at a time to the sidewalk, never as a block",
		run = function()
			local flow = newFlow(20)
			flow:step(DT, 0, 100, 0)
			flow:hint({ kind = "obstacle", x = -20, z = 110, side = "left" })
			flow:setTotal(10)
			local memberCounts, maxLeavers = {}, 0
			local frame
			for i = 1, 150 do
				frame = flow:step(DT, 0, 100, 0)
				memberCounts[i] = #frame.members
				maxLeavers = math.max(maxLeavers, #frame.leavers)
			end
			local steps = {}
			for i = 2, #memberCounts do
				if memberCounts[i] ~= memberCounts[i - 1] then
					table.insert(steps, memberCounts[i - 1] - memberCounts[i])
				end
			end
			assert(#steps >= 8, `expected about ten separate departures, got {#steps}`)
			for _, d in steps do
				assert(d <= 2, "no block of followers vanishing in a frame")
			end
			eq(memberCounts[150], 10, "ten stay")
			assert(maxLeavers >= 2 and maxLeavers <= CAP, "leavers visible and bounded")
			eq(flow:counts().leavers, 0, "all gone at the end")
		end,
	},
	{
		name = "peelers head for the hinted sidewalk",
		run = function()
			local flow = newFlow(6)
			flow:step(DT, 0, 100, 0)
			flow:hint({ kind = "obstacle", x = -20, z = 110, side = "left" })
			flow:setTotal(2)
			local minX = 0
			for _ = 1, 90 do
				local frame = flow:step(DT, 0, 100, 0)
				for _, l in frame.leavers do
					minX = math.min(minX, l.x)
				end
			end
			assert(minX < -DebugLayout.halfWidth + 4, `reached the left sidewalk, min x {minX}`)
		end,
	},
	{
		name = "total 0 clears the field (the end scene stands in)",
		run = function()
			local flow = newFlow(20)
			flow:setTotal(0)
			eq(#flow:step(DT, 0, 100, 0).members, 0, "members")
			eq(flow:counts().leavers, 0, "leavers")
		end,
	},
	{
		name = "a section forming merges the loose followers into the lead instead of sidewalks",
		run = function()
			local flow = newFlow(48) -- 24 drawn
			flow:step(DT, 0, 100, 0)
			flow:setTotal(52) -- 2 loose
			local frame = flow:step(DT, 0, 100, 0)
			local _ = frame
			local maxL = 0
			local maxAbs = 0
			for _ = 1, 120 do
				local f = flow:step(DT, 0, 100, 0)
				maxL = math.max(maxL, #f.leavers)
				for _, l in f.leavers do
					maxAbs = math.max(maxAbs, math.abs(l.x))
				end
			end
			assert(maxAbs < 12, `merging followers stay near the lead, max |x| {maxAbs}`)
			assert(maxL >= 1, "leavers drawn")
		end,
	},
	{
		name = "slot stability through the flow: survivors keep their slot index when others come and go",
		run = function()
			local flow = newFlow(10)
			local before = {}
			for _, m in flow:step(DT, 0, 100, 0).members do
				before[m.id] = m.slot
			end
			flow:setTotal(16)
			run(flow, 2, 100, 0)
			flow:setTotal(7)
			local frame = run(flow, 3, 100, 0)
			for _, m in frame.members do
				if before[m.id] ~= nil then
					eq(m.slot, before[m.id], `survivor {m.id} kept its slot`)
				end
			end
			eq(#frame.members, 7, "seven now")
		end,
	},
	{
		name = "property: random gains and losses keep every invariant (cap, finite, settle)",
		run = function()
			local seed = 7
			local function rnd(): number
				seed = (seed * 1103515245 + 12345) % 2147483648
				return seed / 2147483648
			end
			for _ = 1, 40 do
				local total = math.floor(rnd() * 120)
				local flow = newFlow(total)
				local z = 100
				for _ = 1, 25 do
					local new = math.max(0, total + math.floor((rnd() - 0.45) * 400))
					flow:hint({ kind = "gate", x = (rnd() - 0.5) * 30, z = z - 5, side = "left" })
					flow:setTotal(new)
					total = new
					for _ = 1, math.floor(rnd() * 70) do
						z += Config.speed * DT
						local f = flow:step(DT, (rnd() - 0.5) * 0.2, z, 0)
						assert(#f.members <= CAP, "members over the cap")
						assert(#f.runners <= FollowerFlow.STREAM_CAP, "runners over the cap")
						assert(#f.leavers <= FollowerFlow.LEAVER_CAP, "leavers over the cap")
						for _, m in f.members do
							assert(
								m.x == m.x and m.z == m.z and math.abs(m.x) < 200,
								"member finite"
							)
						end
					end
				end
				-- Everything ends: after a settle the drawn count is exactly the budget's loose count.
				local f = run(flow, 4, z, 0)
				eq(
					#f.members,
					math.min(total % Config.sectionSize, CAP) * (if total == 0 then 0 else 1),
					"settled count"
				)
				eq(#f.runners + #f.leavers, 0, "transients are gone")
			end
		end,
	},
	{
		name = "flow: followers lag the lead with different phases and lean (ripple, not a rigid block)",
		run = function()
			local flow = newFlow(24)
			local z = 100
			for _ = 1, 60 do
				z += Config.speed * DT
				flow:step(DT, 0, z, 0)
			end
			local xs = {}
			for i = 1, 12 do
				z += Config.speed * DT
				local f = flow:step(DT, i * 0.4, z, 0) -- the lead slides sideways
				for _, m in f.members do
					xs[m.id] = m.vx
				end
			end
			local lo, hi = math.huge, -math.huge
			for _, v in xs do
				lo, hi = math.min(lo, v), math.max(hi, v)
			end
			assert(hi - lo > 0.3, `per-follower lag differs, vx spread {hi - lo}`)
		end,
	},
	{
		name = "source: gate, filled cluster and obstacle events give world-space hints",
		run = function()
			local layout = DebugLayout
			local g = FollowerSource.fromEvent(layout, { kind = "gate", id = 1, side = "right" }, 5)
			assert(g ~= nil and g.kind == "gate", "gate hint")
			eq((g :: any).z, layout.gates[1].z, "gate z")
			eq(
				(g :: any).x,
				ViewMap.gateWorldX("right", layout.halfWidth),
				"gate x is the right panel"
			)
			local miss = FollowerSource.fromEvent(layout, { kind = "cluster", id = 1, hits = 1 }, 5)
			eq(miss, nil, "an unfilled shot gives no hint")
			local c = FollowerSource.fromEvent(layout, { kind = "cluster", id = 1, hits = 3 }, 5)
			assert(c ~= nil and c.kind == "cluster", "filled cluster hint")
			eq(
				FollowerSource.fromEvent(layout, { kind = "gate", id = 999, side = "left" }, 5),
				nil,
				"unknown gate"
			)
			eq(FollowerSource.fromEvent(layout, "junk", 5), nil, "junk")
			eq(
				FollowerSource.fromEvent(layout, { kind = "gate", id = 1, side = "up" }, 5),
				nil,
				"bad side"
			)
		end,
	},
}
