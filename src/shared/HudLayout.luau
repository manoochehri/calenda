--!strict
-- Normalized screen regions for the compact, phone-landscape HUD (issue #54).
-- Geometry stays pure so row spacing and road visibility can be tested under Lune.
export type Region = {
	centerX: number,
	top: number,
	width: number,
	height: number,
}

type Layout = {
	caption: Region,
	counter: Region,
	detail: Region,
	meter: Region,
	hp: Region,
	hint: Region,
}

local HudLayout: Layout = {
	caption = { centerX = 0.5, top = 0.012, width = 0.34, height = 0.026 },
	counter = { centerX = 0.5, top = 0.042, width = 0.44, height = 0.078 },
	detail = { centerX = 0.5, top = 0.124, width = 0.42, height = 0.034 },
	meter = { centerX = 0.5, top = 0.166, width = 0.34, height = 0.043 },
	hp = { centerX = 0.13, top = 0.04, width = 0.18, height = 0.065 },
	hint = { centerX = 0.5, top = 0.875, width = 0.62, height = 0.06 },
}

return table.freeze(HudLayout)
