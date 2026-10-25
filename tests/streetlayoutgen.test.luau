--!strict
-- StreetLayoutGen (issue #54 phase 1): deterministic, bounded, and clear of the camera sight lines.
local CameraRig = require("../src/shared/CameraRig")
local DebugLayout = require("../src/shared/DebugLayout")
local LevelTheme = require("../src/shared/LevelTheme")
local StreetLayoutGen = require("../src/shared/StreetLayoutGen")
local ViewMap = require("../src/shared/ViewMap")

local theme = LevelTheme.level1
local info = {
	streetLength = DebugLayout.streetLength,
	plazaStart = DebugLayout.plazaStart,
	startPlazaEnd = DebugLayout.startPlazaEnd,
	halfWidth = DebugLayout.halfWidth,
}
local result = StreetLayoutGen.generate(info, theme, 54)

type Box = { cx: number, cy: number, cz: number, sx: number, sy: number, sz: number }

-- Slab test: does the segment a->b hit the axis-aligned box?
local function hits(a: { number }, b: { number }, box: Box): boolean
	local lo = { box.cx - box.sx / 2, box.cy - box.sy / 2, box.cz - box.sz / 2 }
	local hi = { box.cx + box.sx / 2, box.cy + box.sy / 2, box.cz + box.sz / 2 }
	local t0, t1 = 0, 1
	for i = 1, 3 do
		local d = b[i] - a[i]
		if math.abs(d) < 1e-12 then
			if a[i] < lo[i] or a[i] > hi[i] then
				return false
			end
		else
			local ta, tb = (lo[i] - a[i]) / d, (hi[i] - a[i]) / d
			if ta > tb then
				ta, tb = tb, ta
			end
			t0, t1 = math.max(t0, ta), math.min(t1, tb)
			if t0 > t1 then
				return false
			end
		end
	end
	return true
end

local function allBoxes(r: StreetLayoutGen.Result): { Box }
	local boxes: { Box } = {}
	for _, f in r.facades do
		for _, p in StreetLayoutGen.facadeBoxes(f) do
			table.insert(boxes, p)
		end
	end
	for _, s in r.flags do
		table.insert(boxes, {
			cx = s.x,
			cy = s.y,
			cz = (s.z0 + s.z1) / 2,
			sx = 0.4,
			sy = s.height,
			sz = s.z1 - s.z0,
		})
	end
	for _, l in r.lamps do
		table.insert(
			boxes,
			{ cx = l.x, cy = l.height / 2, cz = l.z, sx = 1, sy = l.height, sz = 1 }
		)
	end
	for _, p in r.plaza do
		if p.group == "paving" then
			continue -- floor slabs, not blockers
		end
		table.insert(boxes, { cx = p.cx, cy = p.cy, cz = p.cz, sx = p.sx, sy = p.sy, sz = p.sz })
	end
	return boxes
end

local lastHit = ""
-- Every (camera, target) sight line the player cares about for one lead position.
local function blockedCount(boxes: { Box }, leadX: number, leadZ: number, pullback: number): number
	local pose = CameraRig.pose(leadX, leadZ, pullback)
	local cam = { pose.px, pose.py, pose.pz }
	local targets: { { number } } = { { leadX, CameraRig.LEAD_TOP, leadZ } }
	for _, x in { -20, -10, 0, 10, 20 } do
		for dz = 0, 8, 4 do
			table.insert(targets, { x, 0.2, leadZ + CameraRig.GATE_NEAR + dz })
		end
	end
	for _, x in { -20, -16, 16, 20 } do -- spectators on the sidewalks
		for dz = -10, 40, 10 do
			for _, y in { 0, 6 } do
				table.insert(targets, { x, y, leadZ + dz })
			end
		end
	end
	local n = 0
	for _, t in targets do
		for _, box in boxes do
			if hits(cam, t, box) then
				n += 1
				if n == 1 then
					lastHit =
						`box cx={box.cx} cy={box.cy} cz={box.cz} sx={box.sx} sy={box.sy} sz={box.sz} target={t[1]},{t[2]},{t[3]}`
				end
			end
		end
	end
	return n
end

return {
	{
		name = "street paving starts beyond the opening plaza, leaving the route continuously walkable",
		run = function()
			for _, p in result.ground do
				if p.group == "road" or p.group == "curb" then
					assert(p.cz - p.sz / 2 >= DebugLayout.startPlazaEnd - 1e-6, p.name)
				end
			end
		end,
	},
	{
		name = "deterministic: same seed same output, different seed differs",
		run = function()
			local again = StreetLayoutGen.generate(info, theme, 54)
			assert(#again.facades == #result.facades, "count")
			for i, f in result.facades do
				local g = again.facades[i]
				assert(f.z == g.z and f.width == g.width and f.wall == g.wall, `facade {i}`)
			end
			local other = StreetLayoutGen.generate(info, theme, 55)
			local differs = false
			for i, f in result.facades do
				if other.facades[i].width ~= f.width or other.facades[i].wall ~= f.wall then
					differs = true
					break
				end
			end
			assert(differs, "seed changes the street")
		end,
	},
	{
		name = "world x convention: left facades, flags and lamps are negative, right positive",
		run = function()
			for _, f in result.facades do
				assert((f.side == "left") == (f.x < 0), `facade {f.id} side/x`)
				assert(math.abs(f.x) - f.depth / 2 >= theme.layout.facadeInset - 1e-9, "inset")
				assert(ViewMap.x(f.x) * f.x < 0, "ViewMap mirrors")
			end
			for _, s in result.flags do
				assert((s.side == "left") == (s.x < 0), "flag side")
			end
			for _, l in result.lamps do
				assert((l.side == "left") == (l.x < 0), "lamp side")
			end
		end,
	},
	{
		name = "mirror-safe colors: no facade style is tied to a side, both sides use every style",
		run = function()
			local seen: { [string]: { left: boolean?, right: boolean? } } = {}
			for _, f in result.facades do
				if f.stone then
					continue
				end
				local entry = seen[f.style] or {}
				entry[f.side] = true
				seen[f.style] = entry
			end
			for _, style in theme.facades do
				local entry = seen[style.name]
				assert(entry and entry.left and entry.right, `{style.name} on both sides`)
			end
			-- the same street seen mirrored (ViewMap) is the same street: x flips, nothing else
			for _, f in result.facades do
				assert(ViewMap.fromView(ViewMap.x(f.x)) == f.x, "ViewMap round trip")
			end
		end,
	},
	{
		name = "the whole street is covered: facades from the run-in to past the end, no big gaps",
		run = function()
			for _, side in { "left", "right" } do
				local lo, hi = math.huge, -math.huge
				local covered = 0
				for _, f in result.facades do
					if f.side == side then
						lo = math.min(lo, f.z - f.width / 2)
						hi = math.max(hi, f.z + f.width / 2)
						covered += f.width
					end
				end
				assert(lo <= -theme.layout.runIn + 1e-6, `{side} starts at the run-in`)
				assert(
					hi >= info.streetLength + theme.layout.endExtra - 1e-6,
					`{side} reaches the end`
				)
				assert(covered >= (hi - lo) - 1e-6, `{side} has no gaps`)
			end
			-- kinds along the way: the arcade is in the plaza only, stone corners and shops exist
			local kinds: { [string]: number } = {}
			for _, f in result.facades do
				kinds[f.kind] = (kinds[f.kind] or 0) + 1
				if f.kind == "portal" then
					assert(f.z >= info.plazaStart and f.z <= info.streetLength, "portal in plaza")
				end
			end
			assert(
				(kinds.stone or 0) >= 4 and (kinds.shop or 0) >= 4 and (kinds.portal or 0) >= 2,
				"types"
			)
			assert((kinds.colonial or 0) > 40, "colonial dominates")
		end,
	},
	{
		name = "a lamp every ~96 studs along the street and some with lights; a plaza with kiosco and trees",
		run = function()
			local firstZ, lastZ = math.huge, 0
			for _, l in result.lamps do
				firstZ, lastZ = math.min(firstZ, l.z), math.max(lastZ, l.z)
			end
			assert(firstZ < 60 and lastZ > info.streetLength - 120, "lamps along the route")
			local groups: { [string]: boolean } = {}
			for _, p in result.plaza do
				groups[p.group] = true
			end
			assert(
				groups.kiosco and groups.tree and groups.paving and groups.cathedral,
				"zocalo props"
			)
		end,
	},
	{
		name = "counts bounded by the theme budgets and under 600 parts (measured)",
		run = function()
			local c = result.counts
			local b = theme.budgets
			assert(c.facadeParts <= b.maxFacadeParts, `facade parts {c.facadeParts}`)
			assert(#result.flags <= b.maxFlagStrips, `strips {#result.flags}`)
			assert(c.flagCells <= b.maxFlagCells, `cells {c.flagCells}`)
			assert(#result.lamps <= b.maxLamps, `lamps {#result.lamps}`)
			assert(c.lights <= b.maxLights, `lights {c.lights}`)
			assert(c.plazaParts <= b.maxPlazaParts, `plaza {c.plazaParts}`)
			assert(c.groundParts <= b.maxGroundParts, `ground {c.groundParts}`)
			assert(c.guiInstances <= b.maxGuiInstances, `gui {c.guiInstances}`)
			assert(c.totalParts <= 600, `total parts {c.totalParts}`)
			print(
				`street parts={c.totalParts} (facade {c.facadeParts}, strips {#result.flags}, lamps {#result.lamps * 2}, plaza {c.plazaParts}, ground {c.groundParts}), flag cells={c.flagCells}, gui={c.guiInstances}, lights={c.lights}`
			)
		end,
	},
	{
		name = "facade heights stay inside the theme range and below the camera",
		run = function()
			local top = 0
			for _, f in result.facades do
				assert(f.height >= theme.heights.facadeMin - 1e-9, "min")
				assert(f.height <= theme.heights.facadeMax + 1e-9, "max")
				top = math.max(top, f.height + theme.heights.roofExtra)
			end
			assert(top <= LevelTheme.facadeTopMax(theme) + 1e-9, "top")
			assert(top < CameraRig.pose(0, 0, 1).py, "below camera")
		end,
	},
	{
		name = "buildings have depth and substantial projecting balconies, not only facade graphics",
		run = function()
			local eligible, withBalcony = 0, 0
			for _, f in result.facades do
				assert(f.depth >= 9, `facade {f.id} has visible wall depth`)
				if f.floors == 2 and f.kind ~= "stone" then
					eligible += 1
					if #f.balconies > 0 then
						withBalcony += 1
						assert(f.balconies[1].depth >= 2.5, "balconies visibly project")
					end
				end
			end
			assert(
				eligible > 0 and withBalcony / eligible >= 0.9,
				"most two-storey buildings have real balconies"
			)
		end,
	},
	{
		name = "camera sight lines to the lead, the next gate row and spectators clear every prop",
		run = function()
			local boxes = allBoxes(result)
			local checked = 0
			for _, pullback in { 1, 1.2, 1.4 } do
				for _, leadX in { -14, -7, 0, 7, 14 } do
					for _, leadZ in
						{
							0,
							150,
							400,
							700,
							1000,
							1300,
							DebugLayout.plazaStart - 10,
							DebugLayout.plazaStart + 60,
						}
					do
						local n = blockedCount(boxes, leadX, leadZ, pullback)
						assert(
							n == 0,
							`{n} blocked ({lastHit}) at x={leadX} z={leadZ} pullback={pullback}`
						)
						checked += 1
					end
				end
			end
			print(`sight-line scenarios clear: {checked}`)
		end,
	},
	{
		name = "negative control: a tall wall at the road edge is detected as hiding the gate row",
		run = function()
			local wall: Box = { cx = 0, cy = 15, cz = 14, sx = 12, sy = 30, sz = 2 }
			assert(blockedCount({ wall }, 0, 0, 1) > 0, "the sight-line test can fail")
		end,
	},
	{
		name = "flags are strips of colored cells, not one part per flag; rows converge by lane height",
		run = function()
			assert(#result.flags >= 8, "flags exist")
			local lanes: { [number]: boolean } = {}
			for _, s in result.flags do
				lanes[s.lane] = true
				assert(#s.cells >= 10, "cells per strip")
				assert(s.canvasWidth <= 2048, "canvas fits")
				assert(s.z1 > s.z0, "ordered")
			end
			local n = 0
			for _ in lanes do
				n += 1
			end
			assert(n >= 2, "several rows")
		end,
	},
	{
		name = "plaza props sit past the dancers' area and the kiosco is behind the street end",
		run = function()
			assert(#result.plaza > 0, "plaza props exist")
			for _, p in result.plaza do
				if p.group == "kiosco" or p.group == "cathedral" then
					assert(p.cz - p.sz / 2 >= info.streetLength, `{p.name} behind the street end`)
				elseif p.group == "tree" then
					assert(
						math.abs(p.cx) - p.sx / 2 >= info.halfWidth,
						"tree outside the plaza floor"
					)
				end
			end
		end,
	},
	{
		name = "build order lists every item once, near the start first",
		run = function()
			local order = StreetLayoutGen.buildOrder(result)
			local expected = #result.facades
				+ #result.flags
				+ #result.lamps
				+ #result.ground
				+ #result.plaza
			assert(#order == expected, `{#order} vs {expected}`)
			local lastZ = -math.huge
			for _, item in order do
				assert(item.z >= lastZ - 1e-9, "sorted by z")
				lastZ = item.z
			end
		end,
	},
	{
		name = "a short street still generates within budgets",
		run = function()
			local small = StreetLayoutGen.generate(
				{ streetLength = 400, plazaStart = 300, halfWidth = 20 },
				theme,
				1
			)
			assert(#small.facades > 0 and small.counts.totalParts <= 600, "bounded")
		end,
	},
}
