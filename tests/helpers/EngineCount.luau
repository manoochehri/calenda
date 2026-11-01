--!nocheck
-- Headless counting stubs of the Roblox engine surface used by the client views (issue #147).
-- They count what a view asks the engine to do: Instance.new calls, property writes by name,
-- Parent changes, live Parts, and BulkMoveTo parts. They do NOT model engine or render cost.
local luau = require("@lune/luau")
local fs = require("@lune/fs")

local EngineCount = {}

function EngineCount.new()
	local c = {
		created = 0,
		writes = {} :: { [string]: number },
		parentChanges = 0,
		liveParts = 0,
		bulkCalls = 0,
		bulkParts = 0,
	}
	function c.resetFrame()
		c.created, c.parentChanges, c.bulkCalls, c.bulkParts = 0, 0, 0, 0
		c.writes = {}
	end
	local function inst(class)
		c.created += 1
		local store = { ClassName = class }
		return setmetatable({}, {
			__index = function(_, k)
				local v = store[k]
				if v ~= nil then
					return v
				end
				return function() end
			end,
			__newindex = function(_, k, v)
				c.writes[k] = (c.writes[k] or 0) + 1
				if k == "Parent" then
					c.parentChanges += 1
					if class == "Part" then
						if store.Parent == nil and v ~= nil then
							c.liveParts += 1
						elseif store.Parent ~= nil and v == nil then
							c.liveParts -= 1
						end
					end
				end
				store[k] = v
			end,
		})
	end
	local V3 = {}
	V3.__index = V3
	V3.__mul = function(a, b)
		if type(b) == "number" then
			return setmetatable({ X = a.X * b, Y = a.Y * b, Z = a.Z * b }, V3)
		end
		return setmetatable({ X = a.X * b.X, Y = a.Y * b.Y, Z = a.Z * b.Z }, V3)
	end
	local CF = {}
	CF.__index = CF
	CF.__mul = function(_, _)
		return setmetatable({}, CF)
	end
	local anyNew = {
		new = function(...)
			return { ... }
		end,
	}
	local workspace = {
		BulkMoveTo = function(_, parts)
			c.bulkCalls += 1
			c.bulkParts += #parts
		end,
	}
	c.env = {
		Vector3 = {
			new = function(x, y, z)
				return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3)
			end,
			zero = setmetatable({ X = 0, Y = 0, Z = 0 }, V3),
			one = setmetatable({ X = 1, Y = 1, Z = 1 }, V3),
		},
		Color3 = {
			fromRGB = function(r, g, b)
				return { r = r, g = g, b = b }
			end,
			new = function(r, g, b)
				return { r = r, g = g, b = b }
			end,
		},
		CFrame = {
			new = function()
				return setmetatable({}, CF)
			end,
			Angles = function()
				return setmetatable({}, CF)
			end,
		},
		Enum = setmetatable({}, {
			__index = function()
				return setmetatable({}, {
					__index = function(_, k)
						return k
					end,
				})
			end,
		}),
		Instance = { new = inst },
		NumberRange = anyNew,
		NumberSequence = anyNew,
		NumberSequenceKeypoint = anyNew,
		ColorSequence = anyNew,
		Vector2 = anyNew,
		Workspace = workspace,
		game = {
			GetService = function(_, name)
				if name == "Workspace" then
					return workspace
				end
				return {
					WaitForChild = function(self)
						return self
					end,
				}
			end,
		},
		os = os,
		math = math,
		table = table,
		string = string,
		type = type,
		pairs = pairs,
		ipairs = ipairs,
		tostring = tostring,
		tonumber = tonumber,
		error = error,
		assert = assert,
		setmetatable = setmetatable,
		warn = warn,
		print = print,
		next = next,
		select = select,
		typeof = function(v)
			return type(v)
		end,
		debug = { profilebegin = function() end, profileend = function() end },
	}
	return c
end

-- Compiles a client module with its `require(Shared:WaitForChild("X"))` calls resolved from `mods`.
function EngineCount.load(path: string, mods: { [string]: any }, c)
	local src = fs.readFile(path)
	src = string.gsub(src, 'require%(Shared:WaitForChild%("(%w+)"%)%)', '__shared("%1")')
	c.env.__shared = function(name)
		return assert(mods[name], "module not preloaded: " .. name)
	end
	local f = luau.load(src, { debugName = path, environment = c.env })
	return f()
end

return EngineCount
