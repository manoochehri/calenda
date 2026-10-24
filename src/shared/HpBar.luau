--!strict
-- The parade HP bar as data (issue #50, Amendment 1: HP is shown as a bar with a number). Pure:
-- HpExtension.Hp in, what to draw out. Sound-off friendly: icon, meter and number all carry it.
local HpExtension = require("./HpExtension")

export type View = {
	fraction: number, -- 0..1 meter fill
	label: string, -- the number, "hp/maxHp"
	color: { number }, -- {r, g, b} bytes
	low: boolean, -- show the warning pulse
}

local HpBar = {}

HpBar.LOW_FRACTION = 0.3 -- [default] at or below this share of max HP the bar warns
HpBar.PULSE_HZ = 2 -- [default] warning pulses per second

local GREEN = { 80, 235, 120 }
local YELLOW = { 250, 204, 21 }
local RED = { 235, 60, 60 }

local function lerp3(a: { number }, b: { number }, k: number): { number }
	local out = {}
	for i = 1, 3 do
		out[i] = math.floor(a[i] + (b[i] - a[i]) * k + 0.5)
	end
	return out
end

-- Green when healthy, yellow at half, red when nearly out.
function HpBar.color(fraction: number): { number }
	local f = math.clamp(fraction, 0, 1)
	if f >= 0.5 then
		return lerp3(YELLOW, GREEN, (f - 0.5) / 0.5)
	end
	return lerp3(RED, YELLOW, f / 0.5)
end

-- nil (no bar) when HP is unavailable.
function HpBar.view(h: HpExtension.Hp?): View?
	if h == nil then
		return nil
	end
	-- Round up so the number is never 0 while any HP is left.
	local shown = if h.hp <= 0 then 0 else math.ceil(h.hp - 1e-9)
	return {
		fraction = h.fraction,
		label = `{shown}/{math.floor(h.maxHp + 0.5)}`,
		color = HpBar.color(h.fraction),
		low = h.hp > 0 and h.fraction <= HpBar.LOW_FRACTION,
	}
end

-- 0..1 warning pulse at clock time t (seconds).
function HpBar.pulse(t: number): number
	return 0.5 + 0.5 * math.sin(t * HpBar.PULSE_HZ * math.pi * 2)
end

return HpBar
