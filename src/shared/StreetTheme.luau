--!strict
-- Shared presentation palette for the Oaxaca-inspired street (issue #54).
-- RGB data stays plain so Lune can check contrast without Roblox Color3.
local StreetTheme = {}

export type RGB = { number }

StreetTheme.palette = {
	ground = { 241, 221, 182 },
	road = { 75, 56, 47 },
	sidewalk = { 230, 189, 131 },
	plaza = { 196, 110, 82 },
	facade = { 211, 106, 76 },
	window = { 35, 63, 66 },
	follower = { 64, 160, 232 },
	leadRing = { 67, 215, 242 },
	roadLine = { 245, 218, 166 },
	ink = { 52, 37, 40 },
	cream = { 255, 247, 224 },
	marigold = { 245, 181, 55 },
	cone = { 202, 72, 53 },
	bunting = {
		{ 211, 72, 71 },
		{ 244, 177, 50 },
		{ 53, 139, 107 },
		{ 67, 145, 198 },
		{ 183, 91, 150 },
	},
	facades = {
		{ 211, 106, 76 },
		{ 225, 153, 74 },
		{ 177, 100, 75 },
		{ 195, 153, 94 },
	},
}

local function deepFreeze(value: any)
	if type(value) == "table" then
		for _, child in value do
			deepFreeze(child)
		end
		table.freeze(value)
	end
end

deepFreeze(StreetTheme.palette)

local function channel(value: number): number
	assert(
		type(value) == "number" and value % 1 == 0 and value >= 0 and value <= 255,
		"invalid RGB channel"
	)
	local normalized = value / 255
	return if normalized <= 0.04045
		then normalized / 12.92
		else ((normalized + 0.055) / 1.055) ^ 2.4
end

function StreetTheme.luminance(color: RGB): number
	assert(type(color) == "table" and #color == 3, "RGB color must have three channels")
	return 0.2126 * channel(color[1]) + 0.7152 * channel(color[2]) + 0.0722 * channel(color[3])
end

function StreetTheme.contrastRatio(a: RGB, b: RGB): number
	local l1, l2 = StreetTheme.luminance(a), StreetTheme.luminance(b)
	if l1 < l2 then
		l1, l2 = l2, l1
	end
	return (l1 + 0.05) / (l2 + 0.05)
end

return StreetTheme
