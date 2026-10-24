--!strict
local Config = require("../src/shared/Config")
local DebugLayout = require("../src/shared/DebugLayout")
local SectionScale = require("../src/shared/SectionScale")
local Steering = require("../src/shared/Steering")
local FollowerSlots = require("../src/shared/FollowerSlots")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function dist(a: FollowerSlots.Slot, b: FollowerSlots.Slot): number
	return math.sqrt((a.dx - b.dx) ^ 2 + (a.dz - b.dz) ^ 2)
end

return {
	{
		name = "a slot depends only on its index and density (same call, same answer)",
		run = function()
			for k = 1, 24 do
				for _, d in { 0, 0.4, 1 } do
					local a, b = FollowerSlots.slot(k, d), FollowerSlots.slot(k, d)
					eq(a.dx, b.dx, "dx")
					eq(a.dz, b.dz, "dz")
				end
			end
		end,
	},
	{
		name = "lowestFree reuses the smallest freed index",
		run = function()
			eq(FollowerSlots.lowestFree({}), 1, "empty")
			eq(FollowerSlots.lowestFree({ [1] = true, [2] = true, [4] = true }), 3, "gap")
		end,
	},
	{
		name = "caps: 24 slots keep apart, behind the lead hitbox, inside the cloud bounds",
		run = function()
			local cap = Config.visualBudget.looseAvatars
			eq(FollowerSlots.capacity(), cap, "capacity is the visual budget")
			local slots = {}
			for k = 1, cap do
				slots[k] = FollowerSlots.slot(k)
				assert(slots[k].dz <= FollowerSlots.MAX_DZ, "inside the lead hitbox zone")
				assert(slots[k].dz >= FollowerSlots.MIN_DZ, "too deep")
				assert(math.abs(slots[k].dx) <= FollowerSlots.MAX_DX, "too wide")
			end
			for i = 1, cap do
				for j = i + 1, cap do
					assert(dist(slots[i], slots[j]) >= 1.5, `slots {i},{j} overlap`)
				end
			end
			assert(not pcall(FollowerSlots.slot, cap + 1), "no slot past the budget")
		end,
	},
	{
		name = "section bases: 6 irregular spots, clear of every follower slot, no two in a row or column",
		run = function()
			eq(#FollowerSlots.BASES, Config.visualBudget.sectionRepresentatives, "six bases")
			for i = 1, 6 do
				local b = FollowerSlots.base(i)
				assert(b.dz <= -9, "far enough behind that no tall figure hides the lead")
				for j = 1, 24 do
					assert(
						dist(b, FollowerSlots.slot(j)) >= FollowerSlots.baseHole(i) - 1e-9,
						`follower {j} inside the hole of base {i}`
					)
				end
				for j = i + 1, 6 do
					local o = FollowerSlots.base(j)
					assert(dist(b, o) >= 4.0, `bases {i},{j} crowd each other`)
					assert(math.abs(b.dx - o.dx) > 0.3 and math.abs(b.dz - o.dz) > 0.3, "aligned")
				end
			end
			assert(not pcall(FollowerSlots.base, 7), "no seventh base")
		end,
	},
	{
		name = "layout is organic: not a grid (many distinct dz and dx values)",
		run = function()
			local dzs, dxs = {}, {}
			for k = 1, 24 do
				local s = FollowerSlots.slot(k)
				dzs[string.format("%.2f", s.dz)] = true
				dxs[string.format("%.2f", s.dx)] = true
			end
			local nz, nx = 0, 0
			for _ in dzs do
				nz += 1
			end
			for _ in dxs do
				nx += 1
			end
			assert(nz >= 20 and nx >= 20, `expected scattered slots, got {nx} x and {nz} z values`)
		end,
	},
	{
		name = "slot rejects a bad index",
		run = function()
			assert(not pcall(FollowerSlots.slot, 0, 0), "0")
			assert(not pcall(FollowerSlots.slot, 1.5, 0), "fraction")
		end,
	},
	{
		name = "reach: slots and bases (with their footprint) fit the cloud reach, which fits the road",
		run = function()
			eq(FollowerSlots.roadHalfWidth(), DebugLayout.halfWidth - 6, "road half width")
			assert(
				FollowerSlots.REACH < FollowerSlots.roadHalfWidth(),
				"the cloud is narrower than the road"
			)
			for k = 1, FollowerSlots.capacity() do
				local s = FollowerSlots.slot(k)
				assert(
					math.abs(s.dx) + FollowerSlots.FOLLOWER_MARGIN <= FollowerSlots.REACH + 1e-9,
					`slot {k} dx {s.dx}`
				)
			end
			local types = { "puppet", "globo", "dancers" }
			for i = 1, 6 do
				local b = FollowerSlots.base(i)
				local fp = SectionScale.footprint(types[(i - 1) % 3 + 1], i)
				assert(fp <= FollowerSlots.BASE_FOOTPRINT, `base {i} footprint {fp}`)
				assert(
					math.abs(b.dx) + fp <= FollowerSlots.REACH + 1e-9,
					`base {i} reaches {math.abs(b.dx) + fp}`
				)
			end
		end,
	},
	{
		name = "road: with the lead anywhere it can stand, every follower and figure stays on the road",
		run = function()
			local road = FollowerSlots.roadHalfWidth()
			local bound = Steering.bound(DebugLayout.halfWidth)
			for step = -40, 40 do
				local leadX = bound * step / 40
				for k = 1, FollowerSlots.capacity() do
					local x = FollowerSlots.worldX(leadX, FollowerSlots.slot(k).dx)
					assert(
						math.abs(x) + FollowerSlots.FOLLOWER_MARGIN <= road + 1e-6,
						`slot {k} at x {x}, lead {leadX}`
					)
				end
				for i = 1, 6 do
					local x = FollowerSlots.worldX(leadX, FollowerSlots.base(i).dx)
					assert(
						math.abs(x) + FollowerSlots.BASE_FOOTPRINT <= road + 1e-6,
						`base {i} at x {x}, lead {leadX}`
					)
				end
			end
		end,
	},
	{
		name = "attached: the cloud centre follows the lead (slope >= 0.7, offset small) except at the road edge",
		run = function()
			local road = FollowerSlots.roadHalfWidth()
			local bound = Steering.bound(DebugLayout.halfWidth)
			local follow = road
				- FollowerSlots.BASE_FOOTPRINT
				- FollowerSlots.MIN_WIDTH * (FollowerSlots.REACH - FollowerSlots.BASE_FOOTPRINT)
			for step = -40, 39 do
				local a, b = bound * step / 40, bound * (step + 1) / 40
				local ca, wa = FollowerSlots.layout(a) -- centre, width factor
				local cb = FollowerSlots.layout(b)
				if math.abs(a) < follow - 0.5 and math.abs(b) < follow - 0.5 then
					assert((cb - ca) / (b - a) >= 0.7, `centre lags at lead {a}`)
					eq(ca, a, "centre is exactly on the lead while the cloud fits")
				end
				if math.abs(a) <= follow + 3 then
					assert(math.abs(ca - a) <= 3, `centre {ca} is {math.abs(ca - a)} from lead {a}`)
				end
				assert(wa >= FollowerSlots.MIN_WIDTH - 1e-9 and wa <= 1, "width factor in range")
			end
			local _, wMid = FollowerSlots.layout(0)
			eq(wMid, 1, "no squeeze in the middle of the road")
		end,
	},
	{
		name = "attached: some follower is always near the lead, at every lead position",
		run = function()
			local bound = Steering.bound(DebugLayout.halfWidth)
			for step = -40, 40 do
				local leadX = bound * step / 40
				local nearest = math.huge
				for k = 1, FollowerSlots.capacity() do
					local s = FollowerSlots.slot(k)
					nearest = math.min(
						nearest,
						math.sqrt((FollowerSlots.worldX(leadX, s.dx) - leadX) ^ 2 + s.dz ^ 2)
					)
				end
				assert(nearest <= 8, `nearest follower is {nearest} studs from the lead at {leadX}`)
			end
		end,
	},
	{
		name = "continuous: the world x of any slot or base changes at most ~2x as fast as the lead",
		run = function()
			local bound = Steering.bound(DebugLayout.halfWidth)
			local dxs = {}
			for k = 1, FollowerSlots.capacity() do
				table.insert(dxs, FollowerSlots.slot(k).dx)
			end
			for i = 1, 6 do
				table.insert(dxs, FollowerSlots.base(i).dx)
			end
			local step = 0.05
			for x = -bound, bound - step, step do
				for _, dx in dxs do
					local jump =
						math.abs(FollowerSlots.worldX(x + step, dx) - FollowerSlots.worldX(x, dx))
					assert(jump <= 2.2 * step, `jump {jump} at lead {x}`)
				end
			end
		end,
	},
}
