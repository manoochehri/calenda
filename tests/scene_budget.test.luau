--!nocheck
-- Issue #254: the scene-inventory and write-spy tests. These run the REAL src/client views against
-- the recording Roblox stub (tests/helpers/SceneStub.luau) and assert what a frame leaves in the
-- tree and what it writes. They exist because #235 passed 1017 mostly source-grep tests while the
-- game was reported broken (#241): a source grep cannot see an Instance that is detached and
-- re-attached every frame (#236), a Neon count that grew, or a require that stopped loading.
--
-- BUDGETS are measured on main (merged tree: main ff7da85 + this PR, 2026-10-31) plus a small margin and recorded in
-- the PR for #254. They are a tripwire, not a target: when a change legitimately needs more, raise
-- the number in the same PR and say why. Set SCENE_REPORT=1 to print the measured numbers.
-- What this CANNOT see: rendering, Trail behaviour in the engine, the real cost of a write.
-- Whether the game looks right on a phone stays UNVERIFIED until it is seen in Studio.
local fs = require("@lune/fs")
local process = require("@lune/process")
local SceneStub = require("./helpers/SceneStub")

local REPORT = process.env.SCENE_REPORT ~= nil

-- Measured on main + margin. `redundantPerFrame` = property writes per frame that set a value the
-- property already held; `writesPerFrame` = every property write. Both are worst frame in the window.
local BUDGETS = {
	calm = {
		low = {
			parts = 450,
			visibleParts = 425,
			neon = 95,
			translucent = 95,
			trails = 0,
			emitters = 0,
			emittersActive = 0,
			guis = 26,
			parentWrites = 0,
			redundantPerFrame = 320,
			writesPerFrame = 905,
		},
		medium = {
			parts = 770,
			visibleParts = 745,
			neon = 95,
			translucent = 95,
			trails = 0,
			emitters = 0,
			emittersActive = 0,
			guis = 26,
			parentWrites = 0,
			redundantPerFrame = 320,
			writesPerFrame = 1225,
		},
		high = {
			parts = 1100,
			visibleParts = 1075,
			neon = 95,
			translucent = 95,
			trails = 0,
			emitters = 0,
			emittersActive = 0,
			guis = 26,
			parentWrites = 0,
			redundantPerFrame = 320,
			writesPerFrame = 1555,
		},
	},
	heavy = {
		low = {
			parts = 450,
			visibleParts = 425,
			neon = 95,
			translucent = 95,
			trails = 26,
			emitters = 5,
			emittersActive = 2,
			guis = 26,
			parentWrites = 0,
			redundantPerFrame = 380,
			writesPerFrame = 1020,
		},
		medium = {
			parts = 775,
			visibleParts = 745,
			neon = 95,
			translucent = 95,
			trails = 26,
			emitters = 7,
			emittersActive = 2,
			guis = 26,
			parentWrites = 0,
			redundantPerFrame = 385,
			writesPerFrame = 1345,
		},
		high = {
			parts = 1110,
			visibleParts = 1075,
			neon = 95,
			translucent = 95,
			trails = 26,
			emitters = 10,
			emittersActive = 2,
			guis = 26,
			parentWrites = 0,
			redundantPerFrame = 390,
			writesPerFrame = 1685,
		},
	},
}
local LANE_VIEW_BUDGET = { parts = 125, neon = 0, translucent = 0, trails = 0, emitters = 0 }

local DT = 1 / 60
local T0 = 44 -- seconds into calle-del-mercado: hordes on screen, chevrons up

-- Drives ClusterView through a fixed fight: a stream of notes and gifts, then a steady window of
-- frames with the clock frozen at T0 (so no mob streams in or out) while the shots are in flight.
-- `source` overrides the ClusterView text (the fail-first proof runs a broken copy).
local function runFight(quality: string, source: string?, calm: boolean)
	local overrides = {}
	if source then
		overrides["client/ClusterView"] = source
	end
	if not calm then
		-- The old heavy path: every committed `default = true` (the #255 calm-screen switches)
		-- flipped back off, so Trails, dust, strips, floaters and the lead ring are built again.
		local registry = fs.readFile("src/shared/DebugRegistry.luau")
		local flipped = string.gsub(registry, "default = true,", "default = false,")
		assert(flipped ~= registry, "no calm default found to flip")
		overrides["shared/DebugRegistry"] = flipped
	end
	local scene = SceneStub.new({ overrides = overrides })
	local ClusterView = scene:require("client/ClusterView")
	local Layouts = scene:require("shared/Layouts")
	local ClusterFeed = scene:require("shared/ClusterFeed")
	local Level = scene:require("shared/Level")
	local view = ClusterView.new(Layouts.all[1])
	view:setQuality(quality)
	local t = T0
	local function step(advance: boolean)
		if advance then
			t += DT
		end
		view:update(t, 0, Level.leadZ(t), DT)
	end
	for _ = 1, 30 do
		step(true)
	end
	local n = 0
	for _ = 1, 12 do
		for _, kind in { "note", "gift" } do
			n += 1
			view:onMiss(ClusterFeed.encodeMiss({ kind = kind, number = n }))
		end
		step(true)
	end
	for _ = 1, 20 do -- let the muzzle pops expire; the shots (0.9 s) are still flying
		step(false)
	end
	local frames = scene:frames(10, function()
		step(false)
	end)
	local inv = scene:inventory(scene.workspace)
	local sum = SceneStub.summarize(frames)
	return {
		inv = inv,
		parts = inv.parts,
		visibleParts = inv.visibleParts,
		neon = inv.neon,
		translucent = inv.translucent,
		trails = inv.trails,
		emitters = inv.emitters,
		emittersActive = inv.emittersActive,
		guis = inv.guis,
		parentWrites = sum.parentWrites,
		redundantPerFrame = sum.maxRedundant,
		writesPerFrame = sum.maxWrites,
		sum = sum,
	}
end

-- A list of "name: measured > budget" strings; empty = within budget.
local function violations(m, budget): { string }
	local out = {}
	for key, limit in budget do
		if m[key] > limit then
			table.insert(out, `{key}: {m[key]} > {limit}`)
		end
	end
	table.sort(out)
	return out
end

local function report(label: string, m)
	if REPORT then
		print(
			`SCENE {label}: parts={m.parts} visible={m.visibleParts} neon={m.neon} translucent={m.translucent} `
				.. `trails={m.trails} emitters={m.emitters} active={m.emittersActive} guis={m.guis} `
				.. `parentWrites={m.parentWrites} redundant/frame(max)={m.redundantPerFrame} writes/frame(max)={m.writesPerFrame}`
		)
		for _, s in m.sum.parentSamples do
			print(`  parent write: {s}`)
		end
	end
end

local function replaceOnce(text: string, find: string, with: string): string
	local a, b = string.find(text, find, 1, true)
	assert(a ~= nil, `fail-first patch target not found (the fix moved?): {find}`)
	return string.sub(text, 1, a - 1) .. with .. string.sub(text, b + 1)
end

-- ClusterView as it was before #247 (3dd5d2e^): every shot part detached and re-attached each frame.
local function preFix247(): string
	local text = fs.readFile("src/client/ClusterView.luau")
	text = replaceOnce(
		text,
		"\t\t\tif gone then\n",
		"\t\t\tfor _, e in p.extras do\n\t\t\t\te.Parent = nil\n\t\t\tend\n\t\t\tp.body.Parent = nil\n\t\t\tif gone then\n"
	)
	text = replaceOnce(
		text,
		"if part.Parent ~= folder then\n\t\t\t\t\tpart.Parent = folder\n\t\t\t\tend",
		"part.Parent = folder"
	)
	return text
end

local cases = {}

for _, mode in { "calm", "heavy" } do
	for _, quality in { "low", "medium", "high" } do
		table.insert(cases, {
			name = `issue 254: ClusterView fight ({mode} defaults) at {quality} quality stays inside the scene budgets`,
			run = function()
				local m = runFight(quality, nil, mode == "calm")
				report(`{mode} {quality}`, m)
				local v = violations(m, BUDGETS[mode][quality])
				assert(#v == 0, `scene budget exceeded ({quality}): {table.concat(v, "; ")}`)
				assert(m.visibleParts > 0, "the fight must actually put things on screen")
				if mode == "heavy" then
					assert(
						m.trails > 0 and m.neon > 0,
						"the heavy path must put Trails and Neon shots on screen"
					)
				end
			end,
		})
	end
end

table.insert(cases, {
	name = "issue 254: a steady frame re-parents nothing (calm and heavy)",
	run = function()
		local m = runFight("medium", nil, true)
		assert(
			m.parentWrites == 0,
			`{m.parentWrites} Parent writes in 10 steady frames: {table.concat(
				m.sum.parentSamples,
				"; "
			)}`
		)
	end,
})

table.insert(cases, {
	name = "issue 254 fail-first: the budgets FAIL on ClusterView as it was before #247",
	run = function()
		local source = process.env.SCENE_CLUSTERVIEW_SRC
		local text = if source then fs.readFile(source) else preFix247()
		local m = runFight("medium", text, false)
		report("pre-#247", m)
		local v = violations(m, BUDGETS.heavy.medium)
		assert(#v > 0, "the budgets did not catch the pre-#247 per-frame re-parenting")
		local caught = false
		for _, line in v do
			if string.find(line, "parentWrites", 1, true) then
				caught = true
			end
		end
		assert(caught, `expected parentWrites to trip, got: {table.concat(v, "; ")}`)
	end,
})

table.insert(cases, {
	name = "issue 254: LaneView's static scene stays inside its inventory budget",
	run = function()
		local scene = SceneStub.new()
		local LaneView = scene:require("client/LaneView")
		local DebugLayout = scene:require("shared/DebugLayout")
		LaneView.new(DebugLayout)
		local inv = scene:inventory(scene.workspace)
		if REPORT then
			print(
				`SCENE lane: parts={inv.parts} neon={inv.neon} translucent={inv.translucent} trails={inv.trails} emitters={inv.emitters}`
			)
		end
		local v = violations(inv, LANE_VIEW_BUDGET)
		assert(#v == 0, `LaneView scene budget exceeded: {table.concat(v, "; ")}`)
	end,
})

table.insert(cases, {
	name = "issue 254: every client module still loads (a broken require shows here, not as a blank game)",
	run = function()
		local loaded = 0
		for _, entry in fs.readDir("src/client") do
			local name = string.match(entry, "^(.*)%.luau$")
			if name and not string.find(name, "%.client$") then
				local scene = SceneStub.new()
				local ok, err = pcall(function()
					return scene:require(`client/{name}`)
				end)
				assert(ok, `client/{name} failed to load: {tostring(err)}`)
				loaded += 1
			end
		end
		assert(loaded >= 20, `only {loaded} client modules found`)
	end,
})

-- The harness is the instrument, so test the instrument.
table.insert(cases, {
	name = "issue 254: the stub counts Parent writes, no-change writes and the inventory correctly",
	run = function()
		local scene = SceneStub.new()
		local Instance, Enum = scene.env.Instance, scene.env.Enum
		local folder = Instance.new("Folder")
		folder.Parent = scene.workspace
		local part = Instance.new("Part")
		part.Parent = folder
		local neonPart = Instance.new("Part")
		neonPart.Material = Enum.Material.Neon
		neonPart.Transparency = 0.5
		neonPart.Parent = folder
		local hidden = Instance.new("Part")
		hidden.Transparency = 1
		hidden.Parent = folder
		Instance.new("Trail").Parent = part
		Instance.new("ParticleEmitter").Parent = part
		local inv = scene:inventory(scene.workspace)
		assert(inv.parts == 3 and inv.visibleParts == 2, `parts {inv.parts}/{inv.visibleParts}`)
		assert(
			inv.neon == 1 and inv.translucent == 1,
			`neon {inv.neon} translucent {inv.translucent}`
		)
		assert(inv.trails == 1 and inv.emitters == 1 and inv.emittersActive == 1, "trail/emitter")

		scene:beginFrame()
		part.Parent = nil
		part.Parent = folder
		part.Parent = folder -- same parent: counted as a write and as redundant
		part.Transparency = 0.2
		part.Transparency = 0.2 -- same value again
		local f = scene:endFrame()
		assert(f.parentWrites == 3, `parentWrites {f.parentWrites}`)
		assert(f.writes == 5, `writes {f.writes}`)
		assert(f.redundant == 2, `redundant {f.redundant}`)
		scene:beginFrame()
		local quiet = scene:endFrame()
		assert(quiet.writes == 0, "nothing written, nothing counted")
		part.Transparency = 0.9 -- outside a frame the spy is off
		assert(scene.spy.frame.writes == 0, "the spy is off outside a frame")
		assert(
			part.Transparency == 0.9 and part:IsDescendantOf(scene.workspace),
			"reads and ancestry"
		)
	end,
})

table.insert(cases, {
	name = "issue 254: a module that requires something missing fails loudly",
	run = function()
		local scene = SceneStub.new({
			overrides = {
				["client/Broken"] = 'return require(script.Parent:WaitForChild("NoSuchModule"))',
			},
		})
		local ok = pcall(function()
			return scene:require("client/Broken")
		end)
		assert(not ok, "a broken require must throw")
	end,
})

return cases
