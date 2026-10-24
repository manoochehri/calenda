--!strict
-- Z-fight audit (issues #54, #85): every pair of overlapping flat ground surfaces differs by at
-- least LayerHeights.MIN_STEP, every flat top the street generator emits is a named layer, and the
-- client files that draw ground-level flats use LayerHeights.
local fs = require("@lune/fs")
local DebugLayout = require("../src/shared/DebugLayout")
local LayerHeights = require("../src/shared/LayerHeights")
local LevelTheme = require("../src/shared/LevelTheme")
local StreetLayoutGen = require("../src/shared/StreetLayoutGen")

local info = {
	streetLength = DebugLayout.streetLength,
	plazaStart = DebugLayout.plazaStart,
	halfWidth = DebugLayout.halfWidth,
	gates = DebugLayout.gates,
	obstacles = DebugLayout.obstacles,
}
local theme = LevelTheme.level1
local generated = StreetLayoutGen.generate(info, theme, 54)

-- Flat prims the generator emits, as surfaces (only the thin ones: the ground layers).
local function generatedSurfaces(): { LayerHeights.Surface }
	local list: { LayerHeights.Surface } = {}
	for _, p in generated.ground do
		table.insert(list, {
			name = p.name,
			top = p.cy + p.sy / 2,
			x0 = p.cx - p.sx / 2,
			x1 = p.cx + p.sx / 2,
			z0 = p.cz - p.sz / 2,
			z1 = p.cz + p.sz / 2,
		})
	end
	for _, p in generated.plaza do
		if p.group == "paving" then
			table.insert(list, {
				name = p.name,
				top = p.cy + p.sy / 2,
				x0 = p.cx - p.sx / 2,
				x1 = p.cx + p.sx / 2,
				z0 = p.cz - p.sz / 2,
				z1 = p.cz + p.sz / 2,
			})
		end
	end
	return list
end

local function everything(): { LayerHeights.Surface }
	local list = LayerHeights.surfaces(info)
	for _, s in generatedSurfaces() do
		table.insert(list, s)
	end
	return list
end

return {
	{
		name = "layers are ordered and at least MIN_STEP apart",
		run = function()
			local values: { number } = {}
			for _, v in LayerHeights.all do
				table.insert(values, v)
			end
			table.sort(values)
			for i = 2, #values do
				assert(values[i] - values[i - 1] >= LayerHeights.MIN_STEP - 1e-9, "layer gap")
			end
			assert(LayerHeights.MIN_STEP >= 0.2, "at least 0.2 studs")
		end,
	},
	{
		name = "no two overlapping flat surfaces in the whole world are within MIN_STEP (audit)",
		run = function()
			local list = everything()
			local bad = LayerHeights.conflicts(list)
			assert(#bad == 0, `{#bad} z-fight pairs, first: {bad[1]}`)
			print(`z-fight audit: {#list} flat surfaces checked`)
		end,
	},
	{
		name = "negative control: a new flat at an equal or near height is reported",
		run = function()
			local list = everything()
			table.insert(list, {
				name = "NewDecal",
				top = LayerHeights.MARKING + 0.03,
				x0 = -1,
				x1 = 1,
				z0 = 40,
				z1 = 50,
			})
			assert(#LayerHeights.conflicts(list) > 0, "must be caught")
			table.remove(list)
			table.insert(list, {
				name = "SameAsRoad",
				top = LayerHeights.GROUND,
				x0 = 1,
				x1 = 2,
				z0 = 100,
				z1 = 101,
			})
			assert(#LayerHeights.conflicts(list) > 0, "equal height over a course is caught")
		end,
	},
	{
		name = "every flat top the street generator emits is a named layer",
		run = function()
			for _, s in generatedSurfaces() do
				local named = false
				for _, v in LayerHeights.all do
					if math.abs(s.top - v) < 1e-9 then
						named = true
					end
				end
				assert(named, `{s.name} top {s.top} is not a LayerHeights layer`)
			end
		end,
	},
	{
		name = "the client files that draw ground flats take their heights from LayerHeights",
		run = function()
			for _, file in
				{
					"WorldBuilder.client",
					"Backdrop",
					"GateView",
					"CrowdView",
					"Bits",
				}
			do
				local source = fs.readFile(`src/client/{file}.luau`)
				assert(string.find(source, "LayerHeights", 1, true), `{file} must use LayerHeights`)
			end
		end,
	},
}
