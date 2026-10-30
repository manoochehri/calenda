--!strict
-- Low, bounded Oaxaca-colored town blocks that fill the lateral gap between the street facades
-- and distant hills. This is presentation geometry only; the client creates non-colliding Parts.
local LevelTheme = require("./LevelTheme")

local BackdropLayout = {}

BackdropLayout.NEAR_MIN_X = 41
BackdropLayout.NEAR_MAX_X = 68
BackdropLayout.MAX_GAP = 16
BackdropLayout.MAX_HEIGHT = 22
BackdropLayout.MAX_BUILDINGS = 80

export type Building = {
	name: string,
	side: number,
	row: number,
	x: number,
	z0: number,
	z1: number,
	depth: number,
	height: number,
	color: LevelTheme.Rgb,
}

function BackdropLayout.generate(streetLength: number, theme: LevelTheme.Theme?): { Building }
	assert(
		streetLength > 0 and streetLength == streetLength and streetLength < math.huge,
		"invalid street length"
	)
	local useTheme = theme or LevelTheme.level1
	local layout: { Building } = {}
	local rows = {
		{ x = 54, depth = 24, width = 148, pitch = 155 },
		{ x = 112, depth = 30, width = 176, pitch = 185 },
	}
	local heights = { 13, 16, 19, 15, 18, 12 }

	for _, side in { -1, 1 } do
		for rowIndex, row in rows do
			local z = -80
			local index = 0
			while z < streetLength + 80 do
				index += 1
				local style =
					useTheme.facades[(index + rowIndex + (if side < 0 then 0 else 1) - 1) % #useTheme.facades + 1]
				local z1 = z + row.width
				table.insert(layout, {
					name = `TownBackdrop{side}_{rowIndex}_{index}`,
					side = side,
					row = rowIndex,
					x = side * row.x,
					z0 = z,
					z1 = z1,
					depth = row.depth,
					height = heights[(index + rowIndex - 2) % #heights + 1],
					color = style.wall,
				})
				z += row.pitch
			end
		end
	end

	assert(
		#layout <= BackdropLayout.MAX_BUILDINGS,
		`town backdrop requires {#layout} buildings; cap is {BackdropLayout.MAX_BUILDINGS}`
	)
	return layout
end

return BackdropLayout
