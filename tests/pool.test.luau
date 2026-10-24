--!strict
local Config = require("../src/shared/Config")
local Formation = require("../src/shared/Formation")
local Pool = require("../src/shared/Pool")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

type Item = { id: number, shown: boolean }

local function newPool()
	local created = 0
	local pool = Pool.new(function(): Item
		created += 1
		return { id = created, shown = false }
	end, function(item: Item)
		item.shown = true
	end, function(item: Item)
		item.shown = false
	end)
	return pool, function()
		return created
	end
end

return {
	{
		name = "setCount creates only what is needed and shows exactly that many",
		run = function()
			local pool, created = newPool()
			eq(#pool:setCount(0), 0, "zero")
			eq(created(), 0, "nothing created for zero")
			local items = pool:setCount(3)
			eq(#items, 3, "three")
			eq(created(), 3, "three created")
			for _, item in items do
				eq(item.shown, true, "shown")
			end
		end,
	},
	{
		name = "shrinking hides and growing again reuses the same items",
		run = function()
			local pool, created = newPool()
			local first = pool:setCount(5)
			local ids = {}
			for i, item in first do
				ids[i] = item.id
			end
			local small = pool:setCount(2)
			eq(#small, 2, "two active")
			eq(first[3].shown, false, "third hidden")
			eq(first[5].shown, false, "fifth hidden")
			local again = pool:setCount(5)
			eq(created(), 5, "no new items")
			for i, item in again do
				eq(item.id, ids[i], `item {i} reused`)
				eq(item.shown, true, `item {i} shown again`)
			end
		end,
	},
	{
		name = "avatars follow the budget: totals 0, 1, 24, 49, 10,000 never create more than 24",
		run = function()
			local pool, created = newPool()
			local expected = { [0] = 0, [1] = 1, [24] = 24, [49] = 24, [10000] = 0 }
			for _, total in { 0, 1, 24, 49, 10000, 49, 1, 24 } do
				local plan = Formation.forTotal(total)
				eq(#pool:setCount(#plan.slots), #plan.slots, `active for {total}`)
				if expected[total] ~= nil then
					eq(#plan.slots, expected[total], `slots for {total}`)
				end
			end
			assert(created() <= Config.visualBudget.looseAvatars, "pool never exceeds the budget")
			eq(created(), 24, "exactly the budget was created")
		end,
	},
	{
		name = "a bad count is an error",
		run = function()
			local pool = newPool()
			assert(not pcall(function()
				pool:setCount(-1)
			end), "negative")
			assert(not pcall(function()
				pool:setCount(1.5)
			end), "fractional")
		end,
	},
}
