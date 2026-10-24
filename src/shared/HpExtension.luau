--!strict
-- EXTENSION POINT for the parade HP bar (Amendment 1, issue #16 follow-up). The HP bar itself is
-- NOT built yet: it needs the replicated `hp` and `maxHp` fields that issue #36 adds to State.
-- Until then `read` returns nil for every State and the HUD shows no bar. The follow-up issue
-- reads this, draws the bar next to the counter, and adds the hit jolt.
local HpExtension = {}

export type Hp = { hp: number, maxHp: number, fraction: number }

function HpExtension.read(state: any): Hp?
	local hp, maxHp = state.hp, state.maxHp
	if type(hp) ~= "number" or type(maxHp) ~= "number" or hp ~= hp or maxHp ~= maxHp then
		return nil
	end
	if maxHp <= 0 or maxHp == math.huge then
		return nil
	end
	local clamped = math.clamp(hp, 0, maxHp)
	return { hp = clamped, maxHp = maxHp, fraction = clamped / maxHp }
end

return HpExtension
