--!nocheck
-- Issue #254: a headless Roblox stub that runs the REAL client render code (src/client/*.luau) and
-- records what it does to the scene. Two instruments:
--   * inventory(root): counts what a frame leaves in the tree (Parts, Neon, translucent, Trails,
--     emitters, GUIs), the "what is on screen" question #235/#241 could not answer.
--   * the write spy: counts, per frame, every property write, the writes that change nothing, and
--     every Parent write (re-parenting). A shown, unchanged part that is re-parented or rewritten
--     each frame is the #236 bug class; the spy sees it without an engine.
-- The stub models the object graph and the writes. It does NOT model rendering, physics, replication
-- or the cost of a write in the engine, so a pass here is "nothing silently changed", never "it looks
-- right on a phone": that stays UNVERIFIED until it is seen in Studio.
--
-- Usage:
--   local scene = SceneStub.new()
--   local ClusterView = scene:require("client/ClusterView")
--   scene:beginFrame(); view:update(...); local frame = scene:endFrame()
--   local inv = scene:inventory(scene.workspace)
-- A module whose require chain fails to load throws from scene:require, so a broken require shows
-- as a failed test instead of a silent empty scene.
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local SceneStub = {}

local TYPE = "__type"

-- ---------------------------------------------------------------------------------------------
-- Value types. Plain tables with structural equality, so "wrote the same value again" is detectable.
-- ---------------------------------------------------------------------------------------------
local function valuesEqual(a: any, b: any): boolean
	if rawequal(a, b) then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	local ma, mb = getmetatable(a), getmetatable(b)
	if ma == nil or mb == nil or ma ~= mb or not ma.__value then
		return false -- instances and tokens compare by identity only
	end
	for k, v in a do
		if not valuesEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function valueType(name: string)
	return { __value = true, [TYPE] = name, __eq = valuesEqual }
end

local function numOp(op)
	return function(a, b)
		local function comp(x, y, k)
			local xv = if type(x) == "number" then x else x[k]
			local yv = if type(y) == "number" then y else y[k]
			return op(xv, yv)
		end
		local first = if type(a) == "table" then a else b
		local out = {}
		for k in first do
			out[k] = comp(a, b, k)
		end
		return setmetatable(out, getmetatable(first))
	end
end

local V3 = valueType("Vector3")
V3.__index = function(self, k)
	if k == "Magnitude" then
		return math.sqrt(self.X ^ 2 + self.Y ^ 2 + self.Z ^ 2)
	elseif k == "Unit" then
		local m = math.sqrt(self.X ^ 2 + self.Y ^ 2 + self.Z ^ 2)
		m = if m == 0 then 1 else m
		return setmetatable({ X = self.X / m, Y = self.Y / m, Z = self.Z / m }, V3)
	elseif k == "Lerp" then
		return function(a, b, t)
			return setmetatable({
				X = a.X + (b.X - a.X) * t,
				Y = a.Y + (b.Y - a.Y) * t,
				Z = a.Z + (b.Z - a.Z) * t,
			}, V3)
		end
	elseif k == "Dot" then
		return function(a, b)
			return a.X * b.X + a.Y * b.Y + a.Z * b.Z
		end
	end
	return nil
end
V3.__add = numOp(function(x, y)
	return x + y
end)
V3.__sub = numOp(function(x, y)
	return x - y
end)
V3.__mul = numOp(function(x, y)
	return x * y
end)
V3.__div = numOp(function(x, y)
	return x / y
end)
V3.__unm = function(a)
	return setmetatable({ X = -a.X, Y = -a.Y, Z = -a.Z }, V3)
end
local function v3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3)
end

local V2 = valueType("Vector2")
V2.__add = numOp(function(x, y)
	return x + y
end)
V2.__sub = numOp(function(x, y)
	return x - y
end)
V2.__mul = numOp(function(x, y)
	return x * y
end)
V2.__div = numOp(function(x, y)
	return x / y
end)
local function v2(x, y)
	return setmetatable({ X = x or 0, Y = y or 0 }, V2)
end

-- CFrame is structural (a tree of constructors and products): good for equality, not for geometry.
local CF = valueType("CFrame")
CF.__index = function(self, k)
	if k == "Position" then
		return v3(rawget(self, "x") or 0, rawget(self, "y") or 0, rawget(self, "z") or 0)
	elseif k == "X" or k == "Y" or k == "Z" then
		return rawget(self, string.lower(k)) or 0
	end
	return function()
		return self
	end
end
CF.__mul = function(a, b)
	if getmetatable(b) == V3 then
		return b
	end
	return setmetatable({ product = { a, b } }, CF)
end
local CFrame = {
	new = function(x, y, z, ...)
		if type(x) == "table" and getmetatable(x) == V3 then
			return setmetatable({ x = x.X, y = x.Y, z = x.Z, look = y }, CF)
		end
		return setmetatable({ x = x or 0, y = y or 0, z = z or 0, extra = { ... } }, CF)
	end,
	Angles = function(a, b, c)
		return setmetatable({ ax = a, ay = b, az = c }, CF)
	end,
	lookAt = function(a, b)
		return setmetatable({ lookFrom = a, lookAt = b }, CF)
	end,
}
CFrame.fromOrientation = CFrame.Angles
CFrame.identity = setmetatable({}, CF)

local C3 = valueType("Color3")
local function c3(r, g, b)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3)
end

local UD2 = valueType("UDim2")
local function ud2(xs, xo, ys, yo)
	return setmetatable({ xs = xs or 0, xo = xo or 0, ys = ys or 0, yo = yo or 0 }, UD2)
end
UD2.__add = function(a, b)
	return ud2(a.xs + b.xs, a.xo + b.xo, a.ys + b.ys, a.yo + b.yo)
end

local function plainValue(name: string)
	local mt = valueType(name)
	return function(...)
		return setmetatable({ ... }, mt)
	end
end

local Enums = {}
local EnumMT = { [TYPE] = "EnumItem" }
local function enumItem(kind: string, name: string)
	local byName = Enums[kind]
	if byName == nil then
		byName = {}
		Enums[kind] = byName
	end
	local item = byName[name]
	if item == nil then
		item = setmetatable({ EnumType = kind, Name = name }, EnumMT)
		byName[name] = item
	end
	return item
end
EnumMT.__tostring = function(self)
	return `Enum.{self.EnumType}.{self.Name}`
end
local Enum = setmetatable({}, {
	__index = function(_, kind)
		return setmetatable({}, {
			__index = function(_, name)
				return enumItem(kind, name)
			end,
		})
	end,
})

-- ---------------------------------------------------------------------------------------------
-- Instances and the write spy.
-- ---------------------------------------------------------------------------------------------
local BASE_PARTS =
	{ Part = true, MeshPart = true, WedgePart = true, TrussPart = true, SpawnLocation = true }
local GUI_OBJECTS =
	{ Frame = true, TextLabel = true, ImageLabel = true, TextButton = true, ImageButton = true }
local SIGNALS = {
	Changed = true,
	ChildAdded = true,
	ChildRemoved = true,
	DescendantAdded = true,
	DescendantRemoving = true,
	Touched = true,
	TouchEnded = true,
	Heartbeat = true,
	RenderStepped = true,
	Stepped = true,
	InputBegan = true,
	InputChanged = true,
	InputEnded = true,
	Activated = true,
	MouseButton1Click = true,
	OnClientEvent = true,
	OnServerEvent = true,
	Destroying = true,
	AncestryChanged = true,
	Event = true,
	Completed = true,
	PlayerAdded = true,
	PlayerRemoving = true,
	CharacterAdded = true,
}

local function newSignal()
	local signal = {}
	local conn = { Disconnect = function() end, Connected = true }
	function signal.Connect(_, _fn)
		return conn
	end
	signal.Once = signal.Connect
	function signal.Wait()
		return nil
	end
	return signal
end

local function defaultsFor(class: string): { [string]: any }
	local d = {}
	if BASE_PARTS[class] then
		d.Transparency = 0
		d.Anchored = false
		d.CanCollide = true
		d.CanQuery = true
		d.CanTouch = true
		d.CastShadow = true
		d.Material = enumItem("Material", "Plastic")
		d.Size = v3(2, 1, 2)
		d.Position = v3(0, 0, 0)
		d.CFrame = CFrame.new(0, 0, 0)
		d.Color = c3(0.64, 0.64, 0.64)
		d.Shape = enumItem("PartType", "Block")
	elseif class == "Trail" then
		d.Enabled = true
		d.LightEmission = 0
	elseif class == "ParticleEmitter" then
		d.Enabled = true
		d.Rate = 20
	elseif
		class == "Beam"
		or class == "BillboardGui"
		or class == "SurfaceGui"
		or class == "ScreenGui"
		or class == "PointLight"
		or class == "SpotLight"
		or class == "SurfaceLight"
	then
		d.Enabled = true
	elseif GUI_OBJECTS[class] then
		d.Visible = true
		d.BackgroundTransparency = 0
		d.Text = ""
		d.TextTransparency = 0
	elseif class == "Attachment" then
		d.Position = v3(0, 0, 0)
	end
	return d
end

local Instance = {}
local InstanceMT = { [TYPE] = "Instance" }
local worldOf = setmetatable({}, { __mode = "k" }) -- instance -> world, for the spy

local function isA(class: string, name: string): boolean
	if class == name or name == "Instance" then
		return true
	end
	if name == "BasePart" then
		return BASE_PARTS[class] == true
	elseif name == "GuiObject" then
		return GUI_OBJECTS[class] == true
	elseif name == "PVInstance" then
		return BASE_PARTS[class] == true or class == "Model"
	end
	return false
end

local function bump(world, key: string, redundant: boolean, isParent: boolean)
	local spy = world.spy
	if not spy.on then
		return
	end
	local f = spy.frame
	f.writes += 1
	f.byKey[key] = (f.byKey[key] or 0) + 1
	if redundant then
		f.redundant += 1
		f.redundantByKey[key] = (f.redundantByKey[key] or 0) + 1
	end
	if isParent then
		f.parentWrites += 1
	end
end

local function removeChild(parent, child)
	local kids = parent.__children
	local i = table.find(kids, child)
	if i then
		table.remove(kids, i)
	end
end

local function makeInstance(world, class: string)
	local data = {
		__class = class,
		__props = {},
		__children = {},
		__parent = nil,
		__attrs = {},
		__defaults = defaultsFor(class),
	}
	data.Name = class
	local inst = setmetatable(data, InstanceMT)
	worldOf[inst] = world
	return inst
end

InstanceMT.__index = function(self, k)
	local class = rawget(self, "__class")
	if k == "ClassName" then
		return class
	elseif k == "Parent" then
		return rawget(self, "__parent")
	elseif k == "Name" then
		return rawget(self, "Name")
	end
	local props = rawget(self, "__props")
	if props[k] ~= nil then
		return props[k]
	end
	local d = rawget(self, "__defaults")[k]
	if d ~= nil then
		return d
	end
	local method = SceneStub._methods[k]
	if method then
		return method
	end
	if SIGNALS[k] then
		local sig = newSignal()
		props[k] = sig
		return sig
	end
	-- a named child, as the Roblox DataModel allows (workspace.Folder)
	for _, c in rawget(self, "__children") do
		if rawget(c, "Name") == k then
			return c
		end
	end
	return nil
end

InstanceMT.__newindex = function(self, k, v)
	local world = worldOf[self]
	local class = rawget(self, "__class")
	local key = `{class}.{k}`
	if k == "Parent" then
		local old = rawget(self, "__parent")
		bump(world, key, rawequal(old, v), true)
		if world.spy.on and #world.spy.frame.parentSamples < 8 then
			table.insert(
				world.spy.frame.parentSamples,
				`{class} "{rawget(self, "Name")}" {if old then rawget(old, "Name") else "nil"} -> {if v
					then rawget(v, "Name")
					else "nil"}`
			)
		end
		if rawequal(old, v) then
			return
		end
		if old ~= nil then
			removeChild(old, self)
		end
		rawset(self, "__parent", v)
		if v ~= nil then
			table.insert(rawget(v, "__children"), self)
		end
		return
	elseif k == "Name" then
		rawset(self, "Name", v)
		return
	end
	local props = rawget(self, "__props")
	local current = props[k]
	if current == nil then
		current = rawget(self, "__defaults")[k]
	end
	-- A write counts as "redundant" only when the property already holds an explicit or default value.
	bump(world, key, current ~= nil and valuesEqual(current, v), false)
	props[k] = v
end

InstanceMT.__tostring = function(self)
	return rawget(self, "Name")
end

local function walk(inst, out)
	for _, c in rawget(inst, "__children") do
		table.insert(out, c)
		walk(c, out)
	end
	return out
end

SceneStub._methods = {
	IsA = function(self, name)
		return isA(rawget(self, "__class"), name)
	end,
	GetChildren = function(self)
		return table.clone(rawget(self, "__children"))
	end,
	GetDescendants = function(self)
		return walk(self, {})
	end,
	FindFirstChild = function(self, name, recursive)
		local list = if recursive then walk(self, {}) else rawget(self, "__children")
		for _, c in list do
			if rawget(c, "Name") == name then
				return c
			end
		end
		return nil
	end,
	FindFirstChildOfClass = function(self, class)
		for _, c in rawget(self, "__children") do
			if rawget(c, "__class") == class then
				return c
			end
		end
		return nil
	end,
	FindFirstChildWhichIsA = function(self, class)
		for _, c in rawget(self, "__children") do
			if isA(rawget(c, "__class"), class) then
				return c
			end
		end
		return nil
	end,
	WaitForChild = function(self, name)
		for _, c in rawget(self, "__children") do
			if rawget(c, "Name") == name then
				return c
			end
		end
		error(`stub: WaitForChild("{name}") would wait forever on {rawget(self, "Name")}`, 2)
	end,
	IsDescendantOf = function(self, ancestor)
		local p = rawget(self, "__parent")
		while p ~= nil do
			if rawequal(p, ancestor) then
				return true
			end
			p = rawget(p, "__parent")
		end
		return false
	end,
	Destroy = function(self)
		local world = worldOf[self]
		self.Parent = nil
		bump(world, `{rawget(self, "__class")}.Destroy`, false, false)
	end,
	ClearAllChildren = function(self)
		for _, c in table.clone(rawget(self, "__children")) do
			c.Parent = nil
		end
	end,
	Clone = function(self)
		local world = worldOf[self]
		local copy = makeInstance(world, rawget(self, "__class"))
		rawset(copy, "Name", rawget(self, "Name"))
		for k, v in rawget(self, "__props") do
			rawget(copy, "__props")[k] = v
		end
		for _, c in rawget(self, "__children") do
			SceneStub._methods.Clone(c).Parent = copy
		end
		return copy
	end,
	GetAttribute = function(self, name)
		return rawget(self, "__attrs")[name]
	end,
	SetAttribute = function(self, name, value)
		rawget(self, "__attrs")[name] = value
	end,
	GetAttributeChangedSignal = function()
		return newSignal()
	end,
	GetPropertyChangedSignal = function()
		return newSignal()
	end,
	Clear = function() end, -- Trail:Clear
	Emit = function() end, -- ParticleEmitter:Emit
	Play = function() end,
	Stop = function() end,
	Pause = function() end,
	Resume = function() end,
	Cancel = function() end,
	Connect = function()
		return { Disconnect = function() end }
	end,
	FireServer = function() end,
	FireClient = function() end,
	GetPivot = function(self)
		return self.CFrame or CFrame.new(0, 0, 0)
	end,
	PivotTo = function(self, cf)
		self.CFrame = cf
	end,
	MoveTo = function() end,
	GetService = function(self, name)
		return SceneStub._services(worldOf[self])[name]
	end,
	BulkMoveTo = function(self, parts, cfs)
		local world = worldOf[self]
		world.spy.bulkMoves += #parts
		for i, part in parts do
			part.CFrame = cfs[i]
		end
	end,
	SetPrimaryPartCFrame = function() end,
	GetFullName = function(self)
		return rawget(self, "Name")
	end,
}

-- ---------------------------------------------------------------------------------------------
-- A world: services, the spy, the module loader.
-- ---------------------------------------------------------------------------------------------
local function newFrame()
	return {
		writes = 0,
		redundant = 0,
		parentWrites = 0,
		byKey = {},
		redundantByKey = {},
		parentSamples = {},
	}
end

local function repoPath(rel: string): string
	return `src/{rel}.luau`
end

function SceneStub._services(world)
	return world.services
end

local function moduleToken(world, rel: string)
	return setmetatable({ __moduleRel = rel }, {
		[TYPE] = "ModuleScript",
		__index = function(_, k)
			if k == "Parent" then
				local dir = string.match(rel, "^(.*)/[^/]+$")
				return world:folderToken(dir)
			end
			return nil
		end,
	})
end

function SceneStub.new(options: { overrides: { [string]: string }? }?)
	local world = {
		spy = { on = false, frame = newFrame(), bulkMoves = 0, frames = 0 },
		cache = {},
		overrides = (options and options.overrides) or {},
		services = {},
	}
	setmetatable(world, { __index = SceneStub })

	local function service(name: string)
		local s = makeInstance(world, name)
		rawset(s, "Name", name)
		world.services[name] = s
		return s
	end
	local workspace = service("Workspace")
	world.workspace = workspace
	workspace.CurrentCamera = makeInstance(world, "Camera")
	world.replicated = service("ReplicatedStorage")
	local players = service("Players")
	players.LocalPlayer = nil
	local uis = service("UserInputService")
	uis.TouchEnabled = false
	uis.MouseEnabled = true
	for _, n in
		{
			"RunService",
			"Lighting",
			"TweenService",
			"SoundService",
			"GuiService",
			"ContentProvider",
			"Debris",
			"StarterGui",
			"Teams",
			"HttpService",
			"MarketplaceService",
			"TextService",
			"CollectionService",
		}
	do
		service(n)
	end
	world.services.Workspace = workspace

	-- Lets a module reach folders as Roblox script trees: `Shared:WaitForChild("Config")`.
	function world:folderToken(dir: string)
		return setmetatable({ __folder = dir }, {
			[TYPE] = "Folder",
			__index = function(_, k)
				if k == "WaitForChild" or k == "FindFirstChild" then
					return function(_, name)
						local rel = `{dir}/{name}`
						if world.overrides[rel] or fs.isFile(repoPath(rel)) then
							return moduleToken(world, rel)
						end
						if fs.isDir(`src/{rel}`) then
							return world:folderToken(rel)
						end
						error(`stub: no module {repoPath(rel)} (require chain broken)`, 2)
					end
				end
				return nil
			end,
		})
	end

	local game = {}
	function game.GetService(_, name)
		local s = world.services[name]
		if s == nil then
			error(`stub: service {name} not modelled`, 2)
		end
		return s
	end
	game.Workspace = workspace
	world.game = game

	-- ReplicatedStorage.Shared resolves to src/shared on disk.
	local replicatedMethods = {
		WaitForChild = function(_, name)
			if name == "Shared" then
				return world:folderToken("shared")
			end
			error(`stub: ReplicatedStorage.{name} not modelled`, 2)
		end,
	}
	replicatedMethods.FindFirstChild = replicatedMethods.WaitForChild
	local replicatedMT = getmetatable(world.replicated)
	local replicated = setmetatable({}, {
		[TYPE] = "Instance",
		__index = function(_, k)
			return replicatedMethods[k] or world.replicated[k]
		end,
		__newindex = function(_, k, v)
			world.replicated[k] = v
		end,
	})
	_ = replicatedMT
	world.services.ReplicatedStorage = replicated

	world.env = world:buildEnv()
	return world
end

function SceneStub.buildEnv(world)
	local function instanceNew(class: string, parent: any?)
		local inst = makeInstance(world, class)
		if parent ~= nil then
			inst.Parent = parent
		end
		return inst
	end
	local env = {
		Instance = { new = instanceNew },
		Vector3 = {
			new = v3,
			zero = v3(0, 0, 0),
			one = v3(1, 1, 1),
			xAxis = v3(1, 0, 0),
			yAxis = v3(0, 1, 0),
			zAxis = v3(0, 0, 1),
		},
		Vector2 = { new = v2, zero = v2(0, 0), one = v2(1, 1) },
		CFrame = CFrame,
		Color3 = {
			new = c3,
			fromRGB = function(r, g, b)
				return c3(r / 255, g / 255, b / 255)
			end,
			fromHSV = function(h, s, v)
				return c3(h, s, v)
			end,
		},
		UDim2 = {
			new = ud2,
			fromScale = function(x, y)
				return ud2(x, 0, y, 0)
			end,
			fromOffset = function(x, y)
				return ud2(0, x, 0, y)
			end,
		},
		UDim = { new = plainValue("UDim") },
		Rect = { new = plainValue("Rect") },
		NumberRange = { new = plainValue("NumberRange") },
		NumberSequence = { new = plainValue("NumberSequence") },
		NumberSequenceKeypoint = { new = plainValue("NumberSequenceKeypoint") },
		ColorSequence = { new = plainValue("ColorSequence") },
		ColorSequenceKeypoint = { new = plainValue("ColorSequenceKeypoint") },
		TweenInfo = { new = plainValue("TweenInfo") },
		Random = {
			new = function()
				return {
					NextNumber = function()
						return 0.5
					end,
					NextInteger = function(_, a)
						return a
					end,
				}
			end,
		},
		Enum = Enum,
		game = world.game,
		workspace = world.workspace,
		debug = {
			profilebegin = function() end,
			profileend = function() end,
			traceback = debug.traceback,
		},
		task = {
			wait = function() end,
			spawn = function(f, ...)
				return f(...)
			end,
			defer = function(f, ...)
				return f(...)
			end,
			delay = function() end,
		},
		tick = function()
			return 0
		end,
		time = function()
			return 0
		end,
		typeof = function(v)
			local mt = getmetatable(v)
			if type(mt) == "table" and rawget(mt, TYPE) then
				return rawget(mt, TYPE)
			end
			return type(v)
		end,
		shared = {},
	}
	-- Per-module environment: `script` and `require` differ per module.
	function world.moduleEnv(rel: string)
		local e = table.clone(env)
		e.script = moduleToken(world, rel)
		e.require = function(target)
			local r = type(target) == "table" and rawget(target, "__moduleRel")
			if type(target) == "string" then
				-- A path require ("./Config", "../shared/Config"), resolved against this module's folder.
				local parts = string.split(string.match(rel, "^(.*)/[^/]+$") or "", "/")
				for _, seg in string.split(target, "/") do
					if seg == ".." then
						table.remove(parts)
					elseif seg ~= "." and seg ~= "" then
						table.insert(parts, seg)
					end
				end
				r = table.concat(parts, "/")
			end
			if not r then
				error(`stub: require of a non-module ({tostring(target)}) in {rel}`, 2)
			end
			return world:load(r)
		end
		return e
	end
	return env
end

-- Load (once per world) the module at src/<rel>.luau, or its override text, with the stub globals.
function SceneStub.load(world, rel: string)
	local hit = world.cache[rel]
	if hit ~= nil then
		return hit.value
	end
	local source = world.overrides[rel]
	if source == nil then
		source = fs.readFile(repoPath(rel))
	end
	local chunk, err =
		luau.load(source, { debugName = `src/{rel}`, environment = world.moduleEnv(rel) })
	if chunk == nil then
		error(`stub: cannot compile src/{rel}: {tostring(err)}`, 0)
	end
	local entry = { value = nil }
	world.cache[rel] = entry
	entry.value = chunk()
	return entry.value
end

-- scene:require("client/ClusterView") -> the module's return value.
function SceneStub.require(world, rel: string)
	return world:load(rel)
end

-- ---------------------------------------------------------------------------------------------
-- Frames and inventory.
-- ---------------------------------------------------------------------------------------------
function SceneStub.beginFrame(world)
	world.spy.frame = newFrame()
	world.spy.on = true
end

function SceneStub.endFrame(world)
	world.spy.on = false
	world.spy.frames += 1
	return world.spy.frame
end

-- Runs fn once per frame for `frames` frames; returns the per-frame records.
function SceneStub.frames(world, frames: number, fn: (i: number) -> ())
	local out = {}
	for i = 1, frames do
		world:beginFrame()
		fn(i)
		out[i] = world:endFrame()
	end
	return out
end

-- Everything under `root` (the root's descendants), counted by the things that cost on a phone.
function SceneStub.inventory(_world, root)
	local inv = {
		instances = 0,
		parts = 0,
		visibleParts = 0, -- Transparency < 1
		neon = 0, -- Material Neon, not fully transparent
		translucent = 0, -- 0 < Transparency < 1
		trails = 0,
		trailsEnabled = 0,
		emitters = 0,
		emittersActive = 0, -- Enabled with Rate > 0
		lights = 0,
		guis = 0, -- BillboardGui and SurfaceGui
		byClass = {},
	}
	local neon = enumItem("Material", "Neon")
	for _, d in walk(root, {}) do
		local class = rawget(d, "__class")
		inv.instances += 1
		inv.byClass[class] = (inv.byClass[class] or 0) + 1
		if BASE_PARTS[class] then
			inv.parts += 1
			local tr = d.Transparency
			if tr < 1 then
				inv.visibleParts += 1
				if d.Material == neon then
					inv.neon += 1
				end
			end
			if tr > 0 and tr < 1 then
				inv.translucent += 1
			end
		elseif class == "Trail" then
			inv.trails += 1
			if d.Enabled then
				inv.trailsEnabled += 1
			end
		elseif class == "ParticleEmitter" then
			inv.emitters += 1
			if d.Enabled and d.Rate > 0 then
				inv.emittersActive += 1
			end
		elseif class == "PointLight" or class == "SpotLight" or class == "SurfaceLight" then
			inv.lights += 1
		elseif class == "BillboardGui" or class == "SurfaceGui" then
			inv.guis += 1
		end
	end
	return inv
end

-- Sums over a list of frame records: totals, and the worst single frame.
function SceneStub.summarize(frames)
	local s = {
		parentSamples = {},
		frames = #frames,
		writes = 0,
		redundant = 0,
		parentWrites = 0,
		maxWrites = 0,
		maxRedundant = 0,
		redundantByKey = {},
		parentByKey = {},
	}
	for _, f in frames do
		s.writes += f.writes
		s.redundant += f.redundant
		s.parentWrites += f.parentWrites
		for _, sample in f.parentSamples do
			if #s.parentSamples < 8 then
				table.insert(s.parentSamples, sample)
			end
		end
		s.maxWrites = math.max(s.maxWrites, f.writes)
		s.maxRedundant = math.max(s.maxRedundant, f.redundant)
		for k, n in f.redundantByKey do
			s.redundantByKey[k] = (s.redundantByKey[k] or 0) + n
		end
		for k, n in f.byKey do
			if string.sub(k, -7) == ".Parent" then
				s.parentByKey[k] = (s.parentByKey[k] or 0) + n
			end
		end
	end
	return s
end

return SceneStub
