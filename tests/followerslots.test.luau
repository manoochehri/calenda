--!strict
local Config = require("../src/shared/Config")
local FollowerSlots = require("../src/shared/FollowerSlots")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local function dist(a: FollowerSlots.Slot, b: FollowerSlots.Slot): number
	return math.sqrt((a.dx - b.dx) ^ 2 + (a.dz - b.dz) ^ 2)
end

-- Tiny deterministic generator so the property tests are repeatable.
local function rng(seed: number): () -> number
	local state = seed
	return function()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
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
		name = "property: adding and removing followers never moves a survivor's slot",
		run = function()
			local random = rng(68)
			for _, density in { 0, 0.5, 1 } do
				local owned: { [number]: number } = {} -- id -> slot
				local taken: { [number]: boolean } = {}
				local remembered: { [number]: FollowerSlots.Slot } = {}
				local nextId = 0
				for _ = 1, 400 do
					if next(owned) ~= nil and random() < 0.45 then
						-- remove a random follower
						local ids = {}
						for id in owned do
							table.insert(ids, id)
						end
						table.sort(ids)
						local id = ids[math.floor(random() * #ids) + 1]
						taken[owned[id]] = nil
						owned[id] = nil
						remembered[id] = nil
					else
						local count = 0
						for _ in owned do
							count += 1
						end
						if count < FollowerSlots.capacity() then
							nextId += 1
							local slot = FollowerSlots.lowestFree(taken)
							taken[slot] = true
							owned[nextId] = slot
							remembered[nextId] = FollowerSlots.slot(slot, density)
						end
					end
					for id, slot in owned do
						local now = FollowerSlots.slot(slot, density)
						assert(dist(now, remembered[id]) < 1e-9, `follower {id} moved`)
					end
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
						dist(b, FollowerSlots.slot(j)) >= FollowerSlots.BASE_HOLE - 1e-9,
						`follower {j} inside the hole of base {i}`
					)
				end
				for j = i + 1, 6 do
					local o = FollowerSlots.base(j)
					assert(dist(b, o) >= 4.5, `bases {i},{j} crowd each other`)
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
}
